import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'isolate_parse.dart';

/// Asynchronous Markdown document loader that parses short inputs synchronously
/// and offloads large documents (`>= 4096` UTF-16 code units by default) to a
/// background isolate with latest-wins coalescing.
final class MarkdownDocumentReader extends ChangeNotifier {
  /// Creates a [MarkdownDocumentReader].
  MarkdownDocumentReader({
    this.engine = const MarkdownEngine(),
    this.syncThreshold = defaultSyncThreshold,
    MarkdownDocument? initialDocument,
  }) : assert(syncThreshold >= 0, 'syncThreshold must be non-negative'),
       _document =
           initialDocument ??
           MarkdownDocument(source: '', options: engine.defaultOptions);

  /// Default UTF-16 code-unit threshold above which parsing moves off the UI
  /// thread into a background isolate (`4096`).
  static const int defaultSyncThreshold = 4096;

  /// Pure-Dart [MarkdownEngine] used for synchronous and isolate parses.
  final MarkdownEngine engine;

  /// Minimum source length in UTF-16 code units parsed in a background isolate.
  final int syncThreshold;

  MarkdownDocument _document;
  bool _isParsing = false;
  Object? _lastError;
  StackTrace? _lastStackTrace;
  int _parseCount = 0;
  int _backgroundParseCount = 0;

  int _generation = 0;
  bool _isWorkerActive = false;
  bool _isDisposed = false;
  String? _pendingSource;
  MarkdownOptions? _pendingOptions;
  int _pendingGeneration = 0;
  String? _lastSettledSource;
  MarkdownOptions? _lastSettledOptions;
  final List<Completer<MarkdownDocument>> _waiters =
      <Completer<MarkdownDocument>>[];

  /// Latest parsed [MarkdownDocument].
  MarkdownDocument get document => _document;

  /// Whether a background isolate parse is currently in flight.
  bool get isParsing => _isParsing;

  /// Error captured from the most recent failed [update], or `null` if healthy.
  Object? get lastError => _lastError;

  /// Stack trace associated with [lastError], if any.
  StackTrace? get lastStackTrace => _lastStackTrace;

  /// Total number of completed parses committed to [document].
  int get parseCount => _parseCount;

  /// Total number of completed parses executed on a background isolate.
  int get backgroundParseCount => _backgroundParseCount;

  /// Parses [source] using [options] (or [engine]'s defaults).
  ///
  /// Sources shorter than [syncThreshold] parse synchronously before returning;
  /// sources at or above [syncThreshold] execute in a background isolate with
  /// latest-wins coalescing so rapid edits skip superseded intermediate jobs.
  Future<MarkdownDocument> update(
    String source, {
    MarkdownOptions? options,
  }) async {
    if (_isDisposed) {
      return _document;
    }

    final MarkdownOptions effective = options ?? engine.defaultOptions;
    if (_parseCount > 0 &&
        !_isParsing &&
        _lastError == null &&
        _lastSettledSource == source &&
        _lastSettledOptions == effective) {
      return _document;
    }

    final int requestGeneration = ++_generation;

    if (source.length < syncThreshold) {
      _pendingSource = null;
      _pendingOptions = null;
      _pendingGeneration = requestGeneration;
      try {
        final MarkdownDocument parsed = engine.parse(
          source,
          options: effective,
        );
        _document = parsed;
        _lastError = null;
        _lastStackTrace = null;
        _lastSettledSource = source;
        _lastSettledOptions = effective;
        _parseCount++;
      } on Object catch (error, stackTrace) {
        _lastError = error;
        _lastStackTrace = stackTrace;
      }
      _isParsing = false;
      if (!_isDisposed) {
        notifyListeners();
      }
      _completeWaiters(_document);
      return _document;
    }

    _pendingSource = source;
    _pendingOptions = effective;
    _pendingGeneration = requestGeneration;

    final Completer<MarkdownDocument> waiter = Completer<MarkdownDocument>();
    _waiters.add(waiter);

    if (!_isWorkerActive) {
      _isWorkerActive = true;
      _isParsing = true;
      notifyListeners();
      unawaited(_drainBackgroundQueue());
    } else if (!_isParsing) {
      _isParsing = true;
      notifyListeners();
    }

    return waiter.future;
  }

  /// Resets the reader back to an empty document and clears any recorded error.
  void clear() {
    if (_isDisposed) {
      return;
    }
    _generation++;
    _pendingSource = null;
    _pendingOptions = null;
    _lastSettledSource = null;
    _lastSettledOptions = null;
    _lastError = null;
    _lastStackTrace = null;
    _isParsing = false;
    _document = MarkdownDocument(source: '', options: engine.defaultOptions);
    notifyListeners();
    _completeWaiters(_document);
  }

  Future<void> _drainBackgroundQueue() async {
    try {
      while (!_isDisposed && _pendingSource != null) {
        final String nextSource = _pendingSource!;
        final MarkdownOptions nextOptions = _pendingOptions!;
        final int jobGeneration = _pendingGeneration;
        _pendingSource = null;
        _pendingOptions = null;

        try {
          final MarkdownDocument parsed = await parseMarkdownInBackground(
            engine,
            nextSource,
            nextOptions,
          );
          if (_isDisposed) {
            return;
          }
          if (jobGeneration == _generation) {
            _document = parsed;
            _lastError = null;
            _lastStackTrace = null;
            _lastSettledSource = nextSource;
            _lastSettledOptions = nextOptions;
            _parseCount++;
            _backgroundParseCount++;
          }
        } on Object catch (error, stackTrace) {
          if (_isDisposed) {
            return;
          }
          if (jobGeneration == _generation) {
            _lastError = error;
            _lastStackTrace = stackTrace;
          }
        }
      }
    } finally {
      _isWorkerActive = false;
      if (!_isDisposed) {
        _isParsing = false;
        notifyListeners();
      }
      _completeWaiters(_document);
    }
  }

  void _completeWaiters(MarkdownDocument doc) {
    if (_waiters.isEmpty) {
      return;
    }
    final List<Completer<MarkdownDocument>> pending =
        List<Completer<MarkdownDocument>>.of(_waiters);
    _waiters.clear();
    for (final Completer<MarkdownDocument> completer in pending) {
      if (!completer.isCompleted) {
        completer.complete(doc);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _generation++;
    _pendingSource = null;
    _pendingOptions = null;
    _completeWaiters(_document);
    super.dispose();
  }
}
