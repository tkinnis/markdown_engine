import 'dart:async';
import 'dart:isolate';
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
  double width,
  double height,
  String? semanticsLabel,
  String? errorCode,
  String? errorMessage,
);

const String _debugUncaughtErrorTrigger = '__debug_trigger_worker_error__';

void _prewarmMermaidEngine() {
  try {
    compileMermaidSync('flowchart LR\n  A --> B', pele.PelePalette.light);
  } on Object {
    // Best-effort pre-warm; per-diagram compiles still handle errors safely.
  }
}

void _mermaidWorkerEntryPoint(SendPort mainSendPort) {
  final ReceivePort workerPort = ReceivePort();
  _prewarmMermaidEngine();
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

/// Persistent pre-warmed background `Isolate` worker for Mermaid diagram
/// layout and `vector_graphics` encoding on VM, desktop, and mobile targets.
final class PersistentMermaidWorker {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _mainPort;
  ReceivePort? _exitPort;
  ReceivePort? _errorPort;
  StreamSubscription<dynamic>? _mainSub;
  StreamSubscription<dynamic>? _exitSub;
  StreamSubscription<dynamic>? _errorSub;
  Completer<SendPort?>? _readyCompleter;
  final Map<int, Completer<MermaidWorkerReply>> _pending =
      <int, Completer<MermaidWorkerReply>>{};
  int _nextRequestId = 1;
  int _generation = 0;
  bool _spawnUnsupported = false;
  String? _lastFailureMessage;

  /// Whether a persistent background Mermaid isolate is currently active or
  /// starting up.
  bool get isActive => _isolate != null || _readyCompleter != null;

  /// Lazily spawns and pre-warms the persistent background worker isolate.
  Future<void> warmUp() async {
    final SendPort? port = await _ensureWorker();
    if (port == null && _spawnUnsupported) {
      pele.supports('flowchart LR\n  A --> B');
    }
  }

  /// Compiles Mermaid [code] against [palette] on the persistent background
  /// isolate, multiplexing concurrent requests by monotonic request ID.
  Future<MermaidWorkerReply> compile(
    String code,
    pele.PelePalette palette,
  ) async {
    final SendPort? port = await _ensureWorker();
    if (port == null) {
      if (_spawnUnsupported) {
        return compileMermaidSync(code, palette);
      }
      return (
        compiledBytes: null,
        width: 0.0,
        height: 0.0,
        semanticsLabel: null,
        errorCode: 'engineFailed',
        errorMessage:
            _lastFailureMessage ?? 'Mermaid worker isolate unavailable.',
        cacheable: false,
      );
    }

    if (!identical(port, _sendPort)) {
      return (
        compiledBytes: null,
        width: 0.0,
        height: 0.0,
        semanticsLabel: null,
        errorCode: 'engineFailed',
        errorMessage: 'Mermaid worker isolate was shut down.',
        cacheable: false,
      );
    }

    final int id = _nextRequestId++;
    final Completer<MermaidWorkerReply> completer =
        Completer<MermaidWorkerReply>();
    _pending[id] = completer;
    try {
      port.send((id, code, encodePelePalette(palette)));
    } on Object catch (error) {
      _pending.remove(id);
      return (
        compiledBytes: null,
        width: 0.0,
        height: 0.0,
        semanticsLabel: null,
        errorCode: 'engineFailed',
        errorMessage: 'Failed to dispatch Mermaid render request: $error',
        cacheable: false,
      );
    }
    return completer.future;
  }

  /// Shuts down the persistent worker isolate (if active), closes all
  /// [ReceivePort]s, cancels stream subscriptions, and completes any pending
  /// requests cleanly.
  Future<void> shutdown() async {
    _resetWorkerState(
      errorCode: 'engineFailed',
      errorMessage: 'Mermaid worker isolate was shut down.',
      sendGracefulClose: true,
    );
  }

  /// Test-only identity hash of the active worker [Isolate], or `null` when
  /// no worker isolate is active.
  @visibleForTesting
  int? get debugIsolateIdentity =>
      _isolate == null ? null : identityHashCode(_isolate);

  /// Test-only helper killing the underlying [Isolate] directly without calling
  /// [shutdown], exercising real `onExit` worker failure recovery.
  @visibleForTesting
  void debugKillIsolateWithoutReset() {
    _isolate?.kill(priority: Isolate.immediate);
  }

  /// Test-only helper injecting an uncaught error into the worker isolate,
  /// exercising real `onError` worker failure recovery.
  @visibleForTesting
  void debugTriggerUncaughtError() {
    _sendPort?.send(_debugUncaughtErrorTrigger);
  }

  Future<SendPort?> _ensureWorker() {
    final SendPort? existingPort = _sendPort;
    if (existingPort != null && _isolate != null) {
      return Future<SendPort?>.value(existingPort);
    }
    final Completer<SendPort?>? existingReady = _readyCompleter;
    if (existingReady != null) {
      return existingReady.future;
    }

    _spawnUnsupported = false;
    _lastFailureMessage = null;
    final int generation = ++_generation;
    final Completer<SendPort?> readyCompleter = Completer<SendPort?>();
    _readyCompleter = readyCompleter;

    void maybeCompleteReady() {
      if (generation != _generation) {
        return;
      }
      final SendPort? port = _sendPort;
      if (_isolate != null && port != null && !readyCompleter.isCompleted) {
        _readyCompleter = null;
        readyCompleter.complete(port);
      }
    }

    Zone.root.run(() {
      final ReceivePort mainPort = ReceivePort();
      final ReceivePort exitPort = ReceivePort();
      final ReceivePort errorPort = ReceivePort();

      _mainPort = mainPort;
      _exitPort = exitPort;
      _errorPort = errorPort;

      _mainSub = mainPort.listen((Object? message) {
        if (generation != _generation) {
          return;
        }
        if (message is SendPort) {
          _sendPort = message;
          maybeCompleteReady();
          return;
        }
        if (message is _WorkerWireReply) {
          _handleWorkerReply(message);
        }
      });

      _exitSub = exitPort.listen((Object? _) {
        if (generation != _generation) {
          return;
        }
        _resetWorkerState(
          errorCode: 'engineFailed',
          errorMessage: 'Mermaid worker isolate exited unexpectedly.',
        );
      });

      _errorSub = errorPort.listen((Object? error) {
        if (generation != _generation) {
          return;
        }
        final String description = _formatIsolateError(error);
        _resetWorkerState(
          errorCode: 'engineFailed',
          errorMessage: 'Mermaid worker isolate error: $description',
        );
      });

      unawaited(
        Isolate.spawn<SendPort>(
          _mermaidWorkerEntryPoint,
          mainPort.sendPort,
          onExit: exitPort.sendPort,
          onError: errorPort.sendPort,
          errorsAreFatal: true,
          debugName: 'markdown_engine_mermaid_worker',
        ).then(
          (Isolate isolate) {
            if (generation != _generation) {
              isolate.kill(priority: Isolate.immediate);
              return;
            }
            _isolate = isolate;
            maybeCompleteReady();
          },
          onError: (Object error, StackTrace _) {
            if (generation != _generation) {
              return;
            }
            if (error is IsolateSpawnException) {
              _spawnUnsupported = true;
            }
            _resetWorkerState(
              errorCode: 'engineFailed',
              errorMessage: 'Failed to spawn Mermaid worker isolate: $error',
            );
          },
        ),
      );
    });

    return readyCompleter.future;
  }

  void _handleWorkerReply(_WorkerWireReply message) {
    final (
      int id,
      TransferableTypedData? transferable,
      double width,
      double height,
      String? semanticsLabel,
      String? errorCode,
      String? errorMessage,
    ) = message;
    final Completer<MermaidWorkerReply>? completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    Uint8List? bytes;
    if (transferable != null) {
      try {
        bytes = transferable.materialize().asUint8List();
      } on Object catch (error) {
        completer.complete((
          compiledBytes: null,
          width: 0.0,
          height: 0.0,
          semanticsLabel: null,
          errorCode: 'engineFailed',
          errorMessage: 'Failed to materialize Mermaid payload: $error',
          cacheable: false,
        ));
        return;
      }
    }
    completer.complete((
      compiledBytes: bytes,
      width: width,
      height: height,
      semanticsLabel: semanticsLabel,
      errorCode: errorCode,
      errorMessage: errorMessage,
      cacheable: true,
    ));
  }

  void _resetWorkerState({
    required String errorCode,
    required String errorMessage,
    bool sendGracefulClose = false,
  }) {
    _generation++;
    _lastFailureMessage = errorMessage;

    final SendPort? sendPort = _sendPort;
    _sendPort = null;
    if (sendGracefulClose && sendPort != null) {
      try {
        sendPort.send(null);
      } on Object {
        // Isolate may already be shutting down.
      }
    }

    final Isolate? isolate = _isolate;
    _isolate = null;

    final Completer<SendPort?>? readyCompleter = _readyCompleter;
    _readyCompleter = null;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.complete(null);
    }

    if (_pending.isNotEmpty) {
      final List<Completer<MermaidWorkerReply>> pendingList = _pending.values
          .toList(growable: false);
      _pending.clear();
      final MermaidWorkerReply failureReply = (
        compiledBytes: null,
        width: 0.0,
        height: 0.0,
        semanticsLabel: null,
        errorCode: errorCode,
        errorMessage: errorMessage,
        cacheable: false,
      );
      for (final Completer<MermaidWorkerReply> completer in pendingList) {
        if (!completer.isCompleted) {
          completer.complete(failureReply);
        }
      }
    }

    if (_mainSub != null) {
      unawaited(_mainSub!.cancel());
      _mainSub = null;
    }
    if (_exitSub != null) {
      unawaited(_exitSub!.cancel());
      _exitSub = null;
    }
    if (_errorSub != null) {
      unawaited(_errorSub!.cancel());
      _errorSub = null;
    }

    _mainPort?.close();
    _exitPort?.close();
    _errorPort?.close();
    _mainPort = null;
    _exitPort = null;
    _errorPort = null;

    if (isolate != null) {
      isolate.kill(priority: Isolate.immediate);
    }
  }
}
