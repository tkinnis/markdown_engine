import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pele_dart/pele_dart.dart' as pele;

import 'built_in_mermaid_worker_stub.dart'
    show
        MermaidWorkerReply,
        SerializedPelePalette,
        compileMermaidSync,
        decodePelePalette,
        encodePelePalette;

export 'built_in_mermaid_worker_stub.dart'
    show
        MermaidWorkerReply,
        SerializedPelePalette,
        compileMermaidCompute,
        compileMermaidSync,
        decodePelePalette,
        encodePelePalette;

typedef _WorkerWireReply = (
  int id,
  TransferableTypedData? compiledBytes,
  String? svg,
  double width,
  double height,
  String? semanticsLabel,
  String? errorCode,
  String? errorMessage,
);

typedef _QueuedMermaidJob = ({
  String code,
  pele.PelePalette palette,
  Completer<MermaidWorkerReply> completer,
});

typedef _ActiveMermaidJob = ({int id, Completer<MermaidWorkerReply> completer});

const String _debugUncaughtErrorTrigger = '__debug_trigger_worker_error__';

void _prewarmMermaidEngine() {
  try {
    compileMermaidSync('flowchart LR\n  A --> B', pele.PelePalette.light);
  } on Object {
    // Best-effort pre-warm; per-diagram compiles still handle errors safely.
  }
}

void _mermaidWorkerEntryPoint((SendPort, bool) args) {
  final (SendPort mainSendPort, bool prewarm) = args;
  final ReceivePort workerPort = ReceivePort();
  if (prewarm) {
    _prewarmMermaidEngine();
  }
  mainSendPort.send(workerPort.sendPort);

  bool isDebugMode = false;
  assert(() {
    isDebugMode = true;
    return true;
  }());

  workerPort.listen((Object? message) {
    if (message == null) {
      workerPort.close();
      return;
    }
    if (isDebugMode && message == _debugUncaughtErrorTrigger) {
      throw StateError('Simulated uncaught Mermaid worker error.');
    }
    if (message is (int, String, SerializedPelePalette)) {
      final (int id, String code, SerializedPelePalette rawPalette) = message;
      final MermaidWorkerReply reply = compileMermaidSync(
        code,
        decodePelePalette(rawPalette),
      );
      final Uint8List? bytes = reply.compiledBytes;
      final TransferableTypedData? transferable = bytes == null
          ? null
          : TransferableTypedData.fromList(<Uint8List>[bytes]);
      mainSendPort.send((
        id,
        transferable,
        reply.svg,
        reply.width,
        reply.height,
        reply.semanticsLabel,
        reply.errorCode,
        reply.errorMessage,
      ));
    }
  });
}

String _formatIsolateError(Object? error) {
  if (error is List<Object?> && error.isNotEmpty) {
    return '${error.first}';
  }
  return '$error';
}

MermaidWorkerReply _failureReply({
  required String errorCode,
  required String errorMessage,
}) {
  return (
    compiledBytes: null,
    svg: null,
    width: 0.0,
    height: 0.0,
    semanticsLabel: null,
    errorCode: errorCode,
    errorMessage: errorMessage,
    cacheable: false,
  );
}

final class _MermaidWorkerSlot {
  _MermaidWorkerSlot({required this.isPrimary, required this.readyCompleter});

  final bool isPrimary;
  final Completer<bool> readyCompleter;

  Isolate? isolate;
  SendPort? sendPort;
  ReceivePort? mainPort;
  ReceivePort? exitPort;
  ReceivePort? errorPort;
  StreamSubscription<dynamic>? mainSub;
  StreamSubscription<dynamic>? exitSub;
  StreamSubscription<dynamic>? errorSub;
  Timer? idleTimer;
  _ActiveMermaidJob? activeRequest;
  bool retireWhenIdle = false;
  bool isClosed = false;

  bool get isReady => !isClosed && isolate != null && sendPort != null;

  bool get isStarting => !isClosed && (isolate == null || sendPort == null);

  bool get isBusy => activeRequest != null;

  bool get isIdleReady => isReady && !isBusy && !retireWhenIdle;

  void closeResources({bool sendGracefulClose = false}) {
    if (isClosed) {
      return;
    }
    isClosed = true;
    idleTimer?.cancel();
    idleTimer = null;

    if (!readyCompleter.isCompleted) {
      readyCompleter.complete(false);
    }

    final SendPort? port = sendPort;
    sendPort = null;
    if (sendGracefulClose && port != null) {
      try {
        port.send(null);
      } on Object {
        // Isolate may already be shutting down.
      }
    }

    final Isolate? runningIsolate = isolate;
    isolate = null;

    if (mainSub != null) {
      unawaited(mainSub!.cancel());
      mainSub = null;
    }
    if (exitSub != null) {
      unawaited(exitSub!.cancel());
      exitSub = null;
    }
    if (errorSub != null) {
      unawaited(errorSub!.cancel());
      errorSub = null;
    }

    mainPort?.close();
    exitPort?.close();
    errorPort?.close();
    mainPort = null;
    exitPort = null;
    errorPort = null;

    if (runningIsolate != null) {
      runningIsolate.kill(priority: Isolate.immediate);
    }
  }
}

/// Persistent pre-warmed primary background `Isolate` worker plus bounded
/// lazy auxiliary burst pool for Mermaid diagram layout and `vector_graphics`
/// encoding on VM, desktop, and mobile targets.
final class PersistentMermaidWorker {
  static const Duration _defaultBurstIdleTimeout = Duration(seconds: 15);

  /// Default maximum concurrent Mermaid worker isolates (`1` primary plus up
  /// to `3` auxiliary burst workers, bounded by `Platform.numberOfProcessors - 1`).
  static final int defaultMaxConcurrentWorkers = math.min(
    4,
    math.max(1, Platform.numberOfProcessors - 1),
  );

  _MermaidWorkerSlot? _primarySlot;
  final List<_MermaidWorkerSlot> _burstSlots = <_MermaidWorkerSlot>[];
  final Queue<_QueuedMermaidJob> _queue = ListQueue<_QueuedMermaidJob>();

  int _maxConcurrentWorkers = defaultMaxConcurrentWorkers;
  int _nextRequestId = 1;
  int _poolGeneration = 0;
  bool _spawnUnsupported = false;
  String? _lastFailureMessage;

  /// Test-only configurable idle timeout before auxiliary burst worker isolates
  /// automatically tear down when idle.
  ///
  /// Defaults to 15 seconds. Does not affect the persistent primary worker.
  @visibleForTesting
  Duration debugBurstWorkerIdleTimeout = _defaultBurstIdleTimeout;

  /// Maximum total worker isolates permitted across the persistent primary
  /// isolate and any lazily spawned auxiliary burst isolates.
  ///
  /// Defaults to [defaultMaxConcurrentWorkers]. Setting this to `1` disables
  /// auxiliary burst spawning while preserving the persistent primary isolate.
  /// Decreasing this below [activeWorkerCount] immediately shuts down idle
  /// excess burst workers and retires busy or starting excess burst workers
  /// cleanly as soon as their active job finishes.
  int get maxConcurrentWorkers => _maxConcurrentWorkers;

  set maxConcurrentWorkers(int value) {
    if (value < 1) {
      throw RangeError.value(
        value,
        'maxConcurrentWorkers',
        'Must be at least 1.',
      );
    }
    final int previous = _maxConcurrentWorkers;
    _maxConcurrentWorkers = value;

    if (value < activeWorkerCount) {
      for (
        int i = _burstSlots.length - 1;
        i >= 0 && activeWorkerCount > value;
        i--
      ) {
        final _MermaidWorkerSlot slot = _burstSlots[i];
        if (slot.isIdleReady) {
          _closeSlot(slot, sendGracefulClose: true);
        }
      }

      int nonRetiringCount =
          (_primarySlot != null ? 1 : 0) +
          _burstSlots
              .where((_MermaidWorkerSlot slot) => !slot.retireWhenIdle)
              .length;
      for (
        int i = _burstSlots.length - 1;
        i >= 0 && nonRetiringCount > value;
        i--
      ) {
        final _MermaidWorkerSlot slot = _burstSlots[i];
        if (!slot.retireWhenIdle) {
          slot.retireWhenIdle = true;
          slot.idleTimer?.cancel();
          slot.idleTimer = null;
          nonRetiringCount--;
        }
      }
    } else if (value > previous && _queue.isNotEmpty) {
      _pumpQueue();
    }
  }

  /// Number of currently active or starting worker isolates across the primary
  /// persistent worker and any auxiliary burst workers.
  int get activeWorkerCount =>
      (_primarySlot != null ? 1 : 0) + _burstSlots.length;

  /// Whether at least one persistent primary or auxiliary burst worker isolate
  /// is currently active or starting up.
  bool get isActive => activeWorkerCount > 0;

  /// Lazily spawns and pre-warms the persistent primary background worker
  /// isolate without spawning auxiliary burst workers.
  Future<void> warmUp() async {
    if (_spawnUnsupported) {
      pele.supports('flowchart LR\n  A --> B');
      return;
    }
    final _MermaidWorkerSlot? existing = _primarySlot;
    if (existing != null) {
      if (existing.isReady) {
        return;
      }
      final bool ready = await existing.readyCompleter.future;
      if (!ready && _spawnUnsupported) {
        pele.supports('flowchart LR\n  A --> B');
      }
      return;
    }

    _lastFailureMessage = null;
    final _MermaidWorkerSlot slot = _spawnSlot(isPrimary: true, prewarm: true);
    final bool ready = await slot.readyCompleter.future;
    if (!ready && _spawnUnsupported) {
      pele.supports('flowchart LR\n  A --> B');
    }
  }

  /// Compiles Mermaid [code] against [palette] on the persistent primary
  /// isolate or an auxiliary burst isolate when concurrent demand queues.
  Future<MermaidWorkerReply> compile(String code, pele.PelePalette palette) {
    if (_spawnUnsupported) {
      return Future<MermaidWorkerReply>.value(
        compileMermaidSync(code, palette),
      );
    }

    final Completer<MermaidWorkerReply> completer =
        Completer<MermaidWorkerReply>();
    _queue.addLast((code: code, palette: palette, completer: completer));
    _pumpQueue();
    return completer.future;
  }

  /// Shuts down the primary and all auxiliary burst worker isolates, cancels
  /// all burst idle timers, closes all [ReceivePort]s, cancels subscriptions,
  /// and completes any queued or active requests cleanly.
  Future<void> shutdown() async {
    _poolGeneration++;
    _spawnUnsupported = false;
    _lastFailureMessage = 'Mermaid worker isolate was shut down.';

    final MermaidWorkerReply shutdownReply = _failureReply(
      errorCode: 'engineFailed',
      errorMessage: 'Mermaid worker isolate was shut down.',
    );

    while (_queue.isNotEmpty) {
      final _QueuedMermaidJob job = _queue.removeFirst();
      if (!job.completer.isCompleted) {
        job.completer.complete(shutdownReply);
      }
    }

    final List<_MermaidWorkerSlot> slotsToClose = <_MermaidWorkerSlot>[
      ?_primarySlot,
      ..._burstSlots,
    ];
    _primarySlot = null;
    _burstSlots.clear();

    for (final _MermaidWorkerSlot slot in slotsToClose) {
      final _ActiveMermaidJob? active = slot.activeRequest;
      slot.activeRequest = null;
      slot.closeResources(sendGracefulClose: true);
      if (active != null && !active.completer.isCompleted) {
        active.completer.complete(shutdownReply);
      }
    }
  }

  /// Test-only identity hash of the active primary worker [Isolate], or
  /// `null` when no primary worker isolate is active.
  @visibleForTesting
  int? get debugIsolateIdentity {
    final Isolate? isolate = _primarySlot?.isolate;
    return isolate == null ? null : identityHashCode(isolate);
  }

  /// Test-only identity hashes of all currently spawned worker [Isolate]s
  /// across the primary worker and any active auxiliary burst workers.
  @visibleForTesting
  List<int> get debugWorkerIsolateIdentities {
    final List<int> ids = <int>[];
    final Isolate? primaryIsolate = _primarySlot?.isolate;
    if (primaryIsolate != null) {
      ids.add(identityHashCode(primaryIsolate));
    }
    for (final _MermaidWorkerSlot burst in _burstSlots) {
      final Isolate? isolate = burst.isolate;
      if (isolate != null) {
        ids.add(identityHashCode(isolate));
      }
    }
    return List<int>.unmodifiable(ids);
  }

  /// Test-only helper killing the primary [Isolate] directly without calling
  /// [shutdown], exercising real `onExit` worker failure recovery.
  @visibleForTesting
  void debugKillIsolateWithoutReset() {
    _primarySlot?.isolate?.kill(priority: Isolate.immediate);
  }

  /// Test-only helper injecting an uncaught error into the primary worker
  /// isolate, exercising real `onError` worker failure recovery.
  @visibleForTesting
  void debugTriggerUncaughtError() {
    _primarySlot?.sendPort?.send(_debugUncaughtErrorTrigger);
  }

  /// Test-only callback invoked before spawning a worker [Isolate], returning
  /// a non-null error object (such as [IsolateSpawnException] or [StateError])
  /// to simulate an asynchronous spawn failure in `_handleSpawnError`.
  @visibleForTesting
  Object? Function({required bool isPrimary})? debugSpawnErrorInjector;

  void _dispatchToReadyIdleSlots() {
    if (_queue.isEmpty) {
      return;
    }

    // Prefer an idle primary isolate first so sequential and streaming
    // workloads stay strictly on 1 isolate and never spawn burst workers.
    final _MermaidWorkerSlot? primary = _primarySlot;
    if (_queue.isNotEmpty && primary != null && primary.isIdleReady) {
      _dispatchToSlot(primary, _queue.removeFirst());
    }

    for (final _MermaidWorkerSlot burst in List<_MermaidWorkerSlot>.of(
      _burstSlots,
    )) {
      if (_queue.isEmpty) {
        break;
      }
      if (burst.isIdleReady) {
        _dispatchToSlot(burst, _queue.removeFirst());
      }
    }
  }

  void _pumpQueue() {
    if (_queue.isEmpty) {
      return;
    }

    _dispatchToReadyIdleSlots();

    int startingSlotCount = 0;
    final _MermaidWorkerSlot? currentPrimary = _primarySlot;
    if (currentPrimary != null &&
        currentPrimary.isStarting &&
        !currentPrimary.retireWhenIdle) {
      startingSlotCount++;
    }
    for (final _MermaidWorkerSlot burst in _burstSlots) {
      if (burst.isStarting && !burst.retireWhenIdle) {
        startingSlotCount++;
      }
    }

    while (_queue.isNotEmpty && _queue.length > startingSlotCount) {
      if (_primarySlot == null && activeWorkerCount < _maxConcurrentWorkers) {
        _spawnSlot(isPrimary: true, prewarm: false);
        startingSlotCount++;
      } else if (activeWorkerCount < _maxConcurrentWorkers) {
        _spawnSlot(isPrimary: false, prewarm: false);
        startingSlotCount++;
      } else {
        break;
      }
    }
  }

  void _dispatchToSlot(_MermaidWorkerSlot slot, _QueuedMermaidJob job) {
    slot.idleTimer?.cancel();
    slot.idleTimer = null;

    final SendPort? port = slot.sendPort;
    if (port == null || slot.isClosed) {
      _queue.addFirst(job);
      return;
    }

    final int id = _nextRequestId++;
    slot.activeRequest = (id: id, completer: job.completer);
    try {
      port.send((id, job.code, encodePelePalette(job.palette)));
    } on Object catch (error) {
      slot.activeRequest = null;
      _closeSlot(slot);
      if (!job.completer.isCompleted) {
        job.completer.complete(
          _failureReply(
            errorCode: 'engineFailed',
            errorMessage: 'Failed to dispatch Mermaid render request: $error',
          ),
        );
      }
    }
  }

  _MermaidWorkerSlot _spawnSlot({
    required bool isPrimary,
    required bool prewarm,
  }) {
    final int poolGeneration = _poolGeneration;
    final Completer<bool> readyCompleter = Completer<bool>();
    final _MermaidWorkerSlot slot = _MermaidWorkerSlot(
      isPrimary: isPrimary,
      readyCompleter: readyCompleter,
    );
    if (isPrimary) {
      _primarySlot = slot;
    } else {
      _burstSlots.add(slot);
    }

    void maybeCompleteReady() {
      if (poolGeneration != _poolGeneration || slot.isClosed) {
        return;
      }
      if (slot.isolate != null && slot.sendPort != null) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete(true);
        }
        if (slot.retireWhenIdle && !slot.isBusy) {
          _closeSlot(slot, sendGracefulClose: true);
          _pumpQueue();
          return;
        }
        _pumpQueue();
        if (!slot.isClosed &&
            !slot.isPrimary &&
            !slot.isBusy &&
            !slot.retireWhenIdle &&
            slot.idleTimer == null) {
          _scheduleBurstIdleTimer(slot);
        }
      }
    }

    Zone.root.run(() {
      final ReceivePort mainPort = ReceivePort();
      final ReceivePort exitPort = ReceivePort();
      final ReceivePort errorPort = ReceivePort();

      slot.mainPort = mainPort;
      slot.exitPort = exitPort;
      slot.errorPort = errorPort;

      slot.mainSub = mainPort.listen((Object? message) {
        if (poolGeneration != _poolGeneration || slot.isClosed) {
          return;
        }
        if (message is SendPort) {
          slot.sendPort = message;
          maybeCompleteReady();
          return;
        }
        if (message is _WorkerWireReply) {
          _handleSlotReply(slot, message);
        }
      });

      slot.exitSub = exitPort.listen((Object? _) {
        if (poolGeneration != _poolGeneration || slot.isClosed) {
          return;
        }
        _handleSlotFailure(
          slot,
          errorCode: 'engineFailed',
          errorMessage: 'Mermaid worker isolate exited unexpectedly.',
        );
      });

      slot.errorSub = errorPort.listen((Object? error) {
        if (poolGeneration != _poolGeneration || slot.isClosed) {
          return;
        }
        final String description = _formatIsolateError(error);
        _handleSlotFailure(
          slot,
          errorCode: 'engineFailed',
          errorMessage: 'Mermaid worker isolate error: $description',
        );
      });

      final Object? injectedError = debugSpawnErrorInjector?.call(
        isPrimary: isPrimary,
      );
      final Future<Isolate> spawnFuture = injectedError != null
          ? Future<Isolate>.error(injectedError)
          : Isolate.spawn<(SendPort, bool)>(
              _mermaidWorkerEntryPoint,
              (mainPort.sendPort, prewarm),
              onExit: exitPort.sendPort,
              onError: errorPort.sendPort,
              errorsAreFatal: true,
              debugName: isPrimary
                  ? 'markdown_engine_mermaid_worker'
                  : 'markdown_engine_mermaid_burst_worker',
            );

      unawaited(
        spawnFuture.then(
          (Isolate isolate) {
            if (poolGeneration != _poolGeneration || slot.isClosed) {
              isolate.kill(priority: Isolate.immediate);
              return;
            }
            slot.isolate = isolate;
            maybeCompleteReady();
          },
          onError: (Object error, StackTrace _) {
            if (poolGeneration != _poolGeneration || slot.isClosed) {
              return;
            }
            _handleSpawnError(slot, error);
          },
        ),
      );
    });

    return slot;
  }

  void _handleSlotReply(_MermaidWorkerSlot slot, _WorkerWireReply message) {
    final (
      int id,
      TransferableTypedData? transferable,
      String? svg,
      double width,
      double height,
      String? semanticsLabel,
      String? errorCode,
      String? errorMessage,
    ) = message;

    final _ActiveMermaidJob? active = slot.activeRequest;
    if (active == null || active.id != id) {
      return;
    }
    slot.activeRequest = null;

    late final MermaidWorkerReply reply;
    if (transferable != null) {
      try {
        final Uint8List bytes = transferable.materialize().asUint8List();
        reply = (
          compiledBytes: bytes,
          svg: svg,
          width: width,
          height: height,
          semanticsLabel: semanticsLabel,
          errorCode: errorCode,
          errorMessage: errorMessage,
          cacheable: true,
        );
      } on Object catch (error) {
        reply = _failureReply(
          errorCode: 'engineFailed',
          errorMessage: 'Failed to materialize Mermaid payload: $error',
        );
      }
    } else {
      reply = (
        compiledBytes: null,
        svg: svg,
        width: width,
        height: height,
        semanticsLabel: semanticsLabel,
        errorCode: errorCode,
        errorMessage: errorMessage,
        cacheable: true,
      );
    }

    if (slot.retireWhenIdle) {
      _closeSlot(slot, sendGracefulClose: true);
    } else if (_queue.isEmpty && !slot.isPrimary) {
      _scheduleBurstIdleTimer(slot);
    }

    if (!active.completer.isCompleted) {
      active.completer.complete(reply);
    }
    _pumpQueue();
  }

  void _handleSlotFailure(
    _MermaidWorkerSlot slot, {
    required String errorCode,
    required String errorMessage,
  }) {
    if (slot.isClosed) {
      return;
    }
    _lastFailureMessage = errorMessage;
    final _ActiveMermaidJob? active = slot.activeRequest;
    slot.activeRequest = null;
    _closeSlot(slot);

    if (active != null && !active.completer.isCompleted) {
      active.completer.complete(
        _failureReply(errorCode: errorCode, errorMessage: errorMessage),
      );
    }
    _pumpQueue();
  }

  void _handleSpawnError(_MermaidWorkerSlot slot, Object error) {
    if (slot.isClosed) {
      return;
    }
    final String message = 'Failed to spawn Mermaid worker isolate: $error';
    _lastFailureMessage = message;
    _closeSlot(slot);

    if (activeWorkerCount > 0) {
      _dispatchToReadyIdleSlots();
      if (activeWorkerCount > 0) {
        return;
      }
    }

    if (error is IsolateSpawnException) {
      _spawnUnsupported = true;
      while (_queue.isNotEmpty) {
        final _QueuedMermaidJob job = _queue.removeFirst();
        if (!job.completer.isCompleted) {
          job.completer.complete(compileMermaidSync(job.code, job.palette));
        }
      }
      return;
    }

    final MermaidWorkerReply failure = _failureReply(
      errorCode: 'engineFailed',
      errorMessage: _lastFailureMessage ?? message,
    );
    while (_queue.isNotEmpty) {
      final _QueuedMermaidJob job = _queue.removeFirst();
      if (!job.completer.isCompleted) {
        job.completer.complete(failure);
      }
    }
  }

  void _scheduleBurstIdleTimer(_MermaidWorkerSlot slot) {
    if (slot.isPrimary || slot.isClosed || slot.retireWhenIdle || slot.isBusy) {
      return;
    }
    slot.idleTimer?.cancel();
    final int poolGeneration = _poolGeneration;
    slot.idleTimer = Zone.root.run(
      () => Timer(debugBurstWorkerIdleTimeout, () {
        if (poolGeneration != _poolGeneration || slot.isClosed || slot.isBusy) {
          return;
        }
        _closeSlot(slot, sendGracefulClose: true);
      }),
    );
  }

  void _closeSlot(_MermaidWorkerSlot slot, {bool sendGracefulClose = false}) {
    if (identical(_primarySlot, slot)) {
      _primarySlot = null;
    } else {
      _burstSlots.remove(slot);
    }
    slot.closeResources(sendGracefulClose: sendGracefulClose);
  }
}
