import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart' show CodeBlockNode;
import 'package:pele_dart/pele_dart.dart' as pele;
import 'package:vector_graphics/vector_graphics_compat.dart';

import 'built_in_mermaid_worker.dart';
import 'fast_text.dart' show MarkdownRichText;
import 'inline_renderer.dart' show MarkdownInteractiveAction;
import 'theme.dart';

/// Compiled or failed Mermaid diagram render outcome cached by [BuiltInMermaidCache].
@immutable
sealed class BuiltInMermaidResult {
  const BuiltInMermaidResult();
}

/// Successful compiled `vector_graphics` Mermaid render payload.
@immutable
final class BuiltInMermaidSuccess extends BuiltInMermaidResult {
  /// Creates a [BuiltInMermaidSuccess].
  const BuiltInMermaidSuccess({
    required this.compiledBytes,
    required this.logicalSize,
    required this.semanticsLabel,
  });

  /// Binary `vector_graphics` payload produced by `vg.encodeSvg`.
  final Uint8List compiledBytes;

  /// Intrinsic diagram logical size from the SVG viewBox.
  final Size logicalSize;

  /// Accessible label derived from SVG `aria-label` or diagram type.
  final String semanticsLabel;
}

/// Failure outcome when `pele_dart` or `vector_graphics_compiler` rejects input.
@immutable
final class BuiltInMermaidFailure extends BuiltInMermaidResult {
  /// Creates a [BuiltInMermaidFailure].
  const BuiltInMermaidFailure({required this.code, required this.message});

  /// Machine-readable error category (such as `'syntax'` or `'limit'`).
  final String code;

  /// Human-readable diagnostic explanation.
  final String message;
}

/// Derived [pele.PelePalette] paired with a deterministic cache key and card
/// background color.
final class DerivedMermaidTheme {
  /// Creates a [DerivedMermaidTheme].
  const DerivedMermaidTheme({
    required this.palette,
    required this.paletteKey,
    required this.cardBackground,
  });

  /// Palette passed to `pele.render(..., outputMode: SvgOutputMode.flattened)`.
  final pele.PelePalette palette;

  /// Stable cache-key suffix capturing all color tokens in [palette].
  final String paletteKey;

  /// Opaque surface background color matching `palette.bg`.
  final Color cardBackground;
}

String _colorToHexRgb(Color color) {
  final int rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

/// Derives a theme-reactive [pele.PelePalette] from [theme].
DerivedMermaidTheme deriveMermaidTheme(MarkdownThemeData theme) {
  final bool isDark = theme.brightness == Brightness.dark;
  final Color baseCanvas = isDark
      ? const Color(0xFF0F172A)
      : const Color(0xFFFFFFFF);
  final Color cardBg = Color.alphaBlend(theme.codeBackground, baseCanvas);
  final Color fgColor = Color.alphaBlend(theme.foreground, cardBg);
  final Color mutedColor = Color.alphaBlend(theme.muted, cardBg);
  final Color lineColor = Color.lerp(fgColor, mutedColor, 0.18) ?? fgColor;
  final Color surfaceColor = isDark
      ? (Color.lerp(cardBg, const Color(0xFF334155), 0.45) ?? cardBg)
      : (Color.lerp(cardBg, const Color(0xFFFFFFFF), 0.72) ?? cardBg);
  final Color surfaceAltColor = isDark
      ? (Color.lerp(cardBg, const Color(0xFF475569), 0.45) ?? cardBg)
      : (Color.lerp(cardBg, theme.border, 0.35) ?? cardBg);
  final Color borderBase = Color.alphaBlend(theme.border, cardBg);
  final Color borderColor =
      Color.lerp(borderBase, mutedColor, isDark ? 0.4 : 0.45) ?? borderBase;
  final Color accentColor = Color.alphaBlend(theme.accent, cardBg);
  final Color codeColor = Color.alphaBlend(
    theme.effectiveTableHeaderBackground,
    cardBg,
  );
  final Color criticalColor = Color.alphaBlend(
    theme.alertPalette.caution.foreground,
    cardBg,
  );
  final Color fgOnLight = isDark ? const Color(0xFF0F172A) : fgColor;
  final Color fgOnDark = isDark ? fgColor : const Color(0xFFF8FAFC);

  final List<String> series = <String>[
    _colorToHexRgb(accentColor),
    _colorToHexRgb(Color.alphaBlend(theme.alertPalette.tip.foreground, cardBg)),
    _colorToHexRgb(
      Color.alphaBlend(theme.alertPalette.important.foreground, cardBg),
    ),
    _colorToHexRgb(
      Color.alphaBlend(theme.alertPalette.warning.foreground, cardBg),
    ),
    _colorToHexRgb(criticalColor),
    _colorToHexRgb(
      Color.alphaBlend(theme.alertPalette.note.foreground, cardBg),
    ),
    isDark ? '#72b7b2' : '#4c78a8',
    isDark ? '#f5c2e7' : '#b279a2',
  ];

  final String bgHex = _colorToHexRgb(cardBg);
  final String fgHex = _colorToHexRgb(fgColor);
  final String fgOnLightHex = _colorToHexRgb(fgOnLight);
  final String fgOnDarkHex = _colorToHexRgb(fgOnDark);
  final String mutedHex = _colorToHexRgb(mutedColor);
  final String lineHex = _colorToHexRgb(lineColor);
  final String surfaceHex = _colorToHexRgb(surfaceColor);
  final String surfaceAltHex = _colorToHexRgb(surfaceAltColor);
  final String borderHex = _colorToHexRgb(borderColor);
  final String accentHex = _colorToHexRgb(accentColor);
  final String codeHex = _colorToHexRgb(codeColor);
  final String criticalHex = _colorToHexRgb(criticalColor);

  final pele.PelePalette palette = pele.PelePalette(
    bg: bgHex,
    fg: fgHex,
    fgOnLight: fgOnLightHex,
    fgOnDark: fgOnDarkHex,
    muted: mutedHex,
    line: lineHex,
    surface: surfaceHex,
    surfaceAlt: surfaceAltHex,
    border: borderHex,
    accent: accentHex,
    code: codeHex,
    critical: criticalHex,
    colors: series,
  );

  final String paletteKey =
      '$bgHex|$fgHex|$fgOnLightHex|$fgOnDarkHex|$mutedHex|$lineHex|'
      '$surfaceHex|$surfaceAltHex|$borderHex|$accentHex|$codeHex|'
      '$criticalHex|${series.join(',')}';

  return DerivedMermaidTheme(
    palette: palette,
    paletteKey: paletteKey,
    cardBackground: cardBg,
  );
}

BuiltInMermaidResult _decodeWorkerReply(MermaidWorkerReply reply) {
  final Uint8List? bytes = reply.compiledBytes;
  if (bytes != null) {
    return BuiltInMermaidSuccess(
      compiledBytes: bytes,
      logicalSize: Size(reply.width, reply.height),
      semanticsLabel: reply.semanticsLabel ?? 'Mermaid diagram',
    );
  }
  return BuiltInMermaidFailure(
    code: reply.errorCode ?? 'engineFailed',
    message: reply.errorMessage ?? 'Unable to render Mermaid diagram.',
  );
}

T _runInRealAsyncZone<T>(T Function() action) {
  final Zone current = Zone.current;
  if (identical(current, Zone.root)) {
    return action();
  }
  final Zone realAsyncZone = current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask:
          (Zone self, ZoneDelegate parent, Zone zone, void Function() f) {
            Zone.root.scheduleMicrotask(() => zone.runGuarded(f));
          },
      createTimer:
          (
            Zone self,
            ZoneDelegate parent,
            Zone zone,
            Duration duration,
            void Function() f,
          ) {
            return Zone.root.createTimer(duration, () => zone.runGuarded(f));
          },
      createPeriodicTimer:
          (
            Zone self,
            ZoneDelegate parent,
            Zone zone,
            Duration period,
            void Function(Timer timer) f,
          ) {
            return Zone.root.createPeriodicTimer(
              period,
              (Timer timer) => zone.runGuarded(() => f(timer)),
            );
          },
    ),
  );
  return realAsyncZone.run<T>(action);
}

bool get _isRunningInWidgetTest {
  if (!kDebugMode) {
    return false;
  }
  final Type? bindingType = BindingBase.debugBindingType();
  if (bindingType == null) {
    return false;
  }
  return bindingType.toString().contains('TestWidgetsFlutterBinding');
}

typedef _MermaidCacheKey = (String paletteKey, String trimmedCode);

typedef _MermaidCacheEntry = ({BuiltInMermaidResult result, int byteSize});

/// Bounded dual entry-count and retained-byte LRU cache and isolate compilation
/// coordinator for built-in Mermaid diagram rendering.
final class BuiltInMermaidCache {
  BuiltInMermaidCache._();

  /// Shared cache instance used by [BuiltInMermaidDiagram].
  static final BuiltInMermaidCache instance = BuiltInMermaidCache._();

  /// Default maximum number of retained compiled Mermaid diagrams.
  static const int defaultMaxEntries = 128;

  /// Default maximum estimated retained byte budget in the LRU cache (16 MiB).
  static const int defaultMaxBytes = 16 * 1024 * 1024;

  /// Test hook forcing background worker / `compute` compilation even under
  /// `TestWidgetsFlutterBinding` when testing async transitions via `runAsync`.
  bool debugForceAsyncInTests = false;

  final PersistentMermaidWorker _worker = PersistentMermaidWorker();
  final LinkedHashMap<_MermaidCacheKey, _MermaidCacheEntry> _cache =
      LinkedHashMap<_MermaidCacheKey, _MermaidCacheEntry>();
  final Map<_MermaidCacheKey, Future<BuiltInMermaidResult>> _inFlight =
      <_MermaidCacheKey, Future<BuiltInMermaidResult>>{};

  int _maxEntries = defaultMaxEntries;
  int _maxBytes = defaultMaxBytes;
  int _currentBytes = 0;
  int _renderCount = 0;
  int _hitCount = 0;
  int _epoch = 0;
  bool _usePersistentMermaidIsolate = true;
  bool _warmedSync = false;
  bool _warmedOneShot = false;

  /// Test-only accessor for the underlying [PersistentMermaidWorker].
  @visibleForTesting
  PersistentMermaidWorker get debugWorker => _worker;

  /// Whether cold Mermaid diagram compilations reuse a persistent pre-warmed
  /// background worker isolate instead of spawning one-shot `compute()`
  /// isolates per diagram.
  ///
  /// Defaults to `true`. Setting this to `false` immediately shuts down any
  /// active persistent worker and routes subsequent cold compiles through
  /// one-shot `compute()`.
  bool get usePersistentMermaidIsolate => _usePersistentMermaidIsolate;

  set usePersistentMermaidIsolate(bool value) {
    if (_usePersistentMermaidIsolate == value) {
      return;
    }
    _usePersistentMermaidIsolate = value;
    if (!value && _worker.isActive) {
      _epoch++;
      _inFlight.clear();
      unawaited(_worker.shutdown());
    }
  }

  /// Whether the persistent background Mermaid worker isolate is currently
  /// active or starting up.
  bool get isMermaidWorkerActive => _worker.isActive;

  /// Active maximum entry capacity before LRU eviction.
  int get maxEntries => _maxEntries;

  /// Active maximum estimated byte budget before LRU eviction.
  int get maxBytes => _maxBytes;

  /// Estimated retained bytes across all currently cached Mermaid entries.
  int get currentBytes => _currentBytes;

  /// Number of cold Mermaid compilations executed.
  int get renderCount => _renderCount;

  /// Number of cache hits avoiding Mermaid re-compilation.
  int get hitCount => _hitCount;

  /// Current number of cached Mermaid diagrams.
  int get length => _cache.length;

  /// Configures positive entry-count and/or byte-budget caps and immediately
  /// evicts least-recently-used entries exceeding the updated limits.
  void configure({int? maxEntries, int? maxBytes}) {
    if (maxEntries != null && maxEntries <= 0) {
      throw RangeError.value(
        maxEntries,
        'maxEntries',
        'Must be greater than zero.',
      );
    }
    if (maxBytes != null && maxBytes <= 0) {
      throw RangeError.value(
        maxBytes,
        'maxBytes',
        'Must be greater than zero.',
      );
    }
    if (maxEntries != null) {
      _maxEntries = maxEntries;
    }
    if (maxBytes != null) {
      _maxBytes = maxBytes;
    }
    _evictOverBudget();
  }

  /// Restores [defaultMaxEntries] and [defaultMaxBytes], evicting any entries
  /// exceeding the restored budgets.
  void resetDefaults() {
    _maxEntries = defaultMaxEntries;
    _maxBytes = defaultMaxBytes;
    _evictOverBudget();
  }

  /// Primes `pele_dart`'s diagram registry and `vector_graphics_compiler` so
  /// the first Mermaid diagram avoids lazy initialization overhead.
  ///
  /// When [usePersistentMermaidIsolate] is `true` (and outside default widget
  /// tests unless [debugForceAsyncInTests] is enabled), this lazily spawns and
  /// pre-warms the persistent background worker isolate.
  Future<void> warmUp() async {
    if (_isRunningInWidgetTest && !debugForceAsyncInTests) {
      if (_warmedSync) {
        return;
      }
      _warmedSync = true;
      pele.supports('flowchart LR\n  A --> B');
      return;
    }
    if (_usePersistentMermaidIsolate) {
      await _runInRealAsyncZone<Future<void>>(() => _worker.warmUp());
      return;
    }
    if (_warmedOneShot) {
      return;
    }
    _warmedOneShot = true;
    await _runInRealAsyncZone<Future<MermaidWorkerReply>>(
      () => compileMermaidCompute(
        'flowchart LR\n  A --> B',
        pele.PelePalette.light,
      ),
    );
  }

  /// Clears all cached diagrams, retained byte count, and telemetry counters.
  void clear() {
    _cache.clear();
    _currentBytes = 0;
    _renderCount = 0;
    _hitCount = 0;
  }

  /// Releases pending compilation state and shuts down any active persistent
  /// Mermaid worker isolate cleanly without leaving open ports or altering
  /// [usePersistentMermaidIsolate].
  Future<void> dispose() async {
    _epoch++;
    _inFlight.clear();
    _warmedSync = false;
    _warmedOneShot = false;
    await _worker.shutdown();
  }

  static int _estimateEntryBytes(
    BuiltInMermaidResult result,
    String trimmedCode,
  ) {
    return switch (result) {
      BuiltInMermaidSuccess() =>
        result.compiledBytes.lengthInBytes +
            result.semanticsLabel.length * 2 +
            trimmedCode.length * 2 +
            128,
      BuiltInMermaidFailure() =>
        result.code.length * 2 +
            result.message.length * 2 +
            trimmedCode.length * 2 +
            128,
    };
  }

  void _evictOverBudget() {
    while (_cache.isNotEmpty &&
        (_cache.length > _maxEntries || _currentBytes > _maxBytes)) {
      final _MermaidCacheKey oldestKey = _cache.keys.first;
      final _MermaidCacheEntry? removed = _cache.remove(oldestKey);
      if (removed != null) {
        _currentBytes -= removed.byteSize;
      }
    }
    if (_cache.isEmpty) {
      _currentBytes = 0;
    }
  }

  /// Looks up a cached [BuiltInMermaidResult] synchronously, promoting hits in
  /// LRU order.
  BuiltInMermaidResult? peek(String code, DerivedMermaidTheme theme) {
    final _MermaidCacheKey key = (theme.paletteKey, code.trim());
    final _MermaidCacheEntry? hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      _hitCount++;
      return hit.result;
    }
    return null;
  }

  void _put(_MermaidCacheKey key, BuiltInMermaidResult result) {
    final _MermaidCacheEntry? existing = _cache.remove(key);
    if (existing != null) {
      _currentBytes -= existing.byteSize;
    }
    final int byteSize = _estimateEntryBytes(result, key.$2);
    if (byteSize <= _maxBytes) {
      _cache[key] = (result: result, byteSize: byteSize);
      _currentBytes += byteSize;
      _evictOverBudget();
    }
  }

  /// Synchronously renders and compiles [code] against [theme] and caches the
  /// result.
  BuiltInMermaidResult renderSync(String code, DerivedMermaidTheme theme) {
    final BuiltInMermaidResult? cached = peek(code, theme);
    if (cached != null) {
      return cached;
    }
    final String trimmed = code.trim();
    final _MermaidCacheKey key = (theme.paletteKey, trimmed);
    _renderCount++;
    final BuiltInMermaidResult result = _decodeWorkerReply(
      compileMermaidSync(trimmed, theme.palette),
    );
    _put(key, result);
    return result;
  }

  /// Compiles [code] in the persistent background worker isolate (or one-shot
  /// `compute()` when [usePersistentMermaidIsolate] is `false`) in normal
  /// runtime, or synchronously under `TestWidgetsFlutterBinding` unless
  /// [debugForceAsyncInTests] is enabled.
  Future<BuiltInMermaidResult> render(String code, DerivedMermaidTheme theme) {
    final BuiltInMermaidResult? cached = peek(code, theme);
    if (cached != null) {
      return SynchronousFuture<BuiltInMermaidResult>(cached);
    }
    if (_isRunningInWidgetTest && !debugForceAsyncInTests) {
      return SynchronousFuture<BuiltInMermaidResult>(renderSync(code, theme));
    }

    final String trimmed = code.trim();
    final _MermaidCacheKey key = (theme.paletteKey, trimmed);
    final Future<BuiltInMermaidResult>? existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }

    final int requestEpoch = _epoch;
    _renderCount++;
    final Future<MermaidWorkerReply> replyFuture = _usePersistentMermaidIsolate
        ? _runInRealAsyncZone<Future<MermaidWorkerReply>>(
            () => _worker.compile(trimmed, theme.palette),
          )
        : _runInRealAsyncZone<Future<MermaidWorkerReply>>(
            () => compileMermaidCompute(trimmed, theme.palette),
          );

    final Future<BuiltInMermaidResult> future = replyFuture.then(
      (MermaidWorkerReply reply) {
        final BuiltInMermaidResult result = _decodeWorkerReply(reply);
        if (requestEpoch == _epoch) {
          _inFlight.remove(key);
          if (reply.cacheable) {
            _put(key, result);
          }
        }
        return result;
      },
      onError: (Object error, StackTrace _) {
        if (requestEpoch == _epoch) {
          _inFlight.remove(key);
        }
        return BuiltInMermaidFailure(
          code: 'engineFailed',
          message: 'Failed to render Mermaid diagram: $error',
        );
      },
    );
    _inFlight[key] = future;
    return future;
  }
}

/// Checks whether a fenced [CodeBlockNode] has an explicit closing fence line
/// inside [rawSource].
bool isFencedCodeBlockClosed(String rawSource, CodeBlockNode node) {
  if (!node.isFenced) {
    return true;
  }
  final String normalizedSource = rawSource.contains('\r')
      ? rawSource.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
      : rawSource;
  final int start = node.span.startOffset;
  final int end = node.span.endOffset;
  if (start < 0 || end <= start || end > normalizedSource.length) {
    return true;
  }
  if (node.span.endLine <= node.span.startLine) {
    return false;
  }

  final int firstNewline = normalizedSource.indexOf('\n', start);
  if (firstNewline == -1 || firstNewline >= end) {
    return false;
  }

  // Locate opening fence marker (` ``` ` or `~~~`) on the opening line.
  int openStart = -1;
  int openChar = 0;
  int openLen = 0;
  for (int i = start; i < firstNewline; i++) {
    final int cu = normalizedSource.codeUnitAt(i);
    if (cu == 0x60 || cu == 0x7E) {
      int run = 0;
      while (i + run < firstNewline &&
          normalizedSource.codeUnitAt(i + run) == cu) {
        run++;
      }
      if (run >= 3) {
        openStart = i;
        openChar = cu;
        openLen = run;
        break;
      }
      i += run - 1;
    }
  }
  if (openStart == -1) {
    return true;
  }

  // Locate the last non-empty line inside [start, end).
  int lineEnd = end;
  while (lineEnd > start && normalizedSource.codeUnitAt(lineEnd - 1) == 0x0A) {
    lineEnd--;
  }
  if (lineEnd <= firstNewline) {
    return false;
  }
  final int prevNewline = normalizedSource.lastIndexOf('\n', lineEnd - 1);
  final int lineStart = prevNewline < start ? start : prevNewline + 1;
  if (lineStart <= firstNewline) {
    return false;
  }

  // Allow leading blockquote markers (`>`) and indentation up to the opening
  // fence column + 3 spaces (per CommonMark closing fence indentation rules).
  final int maxLeadingColumn = (openStart - start) + 3;
  int k = lineStart;
  while (k < lineEnd && (k - lineStart) <= maxLeadingColumn) {
    final int cu = normalizedSource.codeUnitAt(k);
    if (cu == 0x20 || cu == 0x09 || cu == 0x3E) {
      k++;
    } else {
      break;
    }
  }
  if (k >= lineEnd || normalizedSource.codeUnitAt(k) != openChar) {
    return false;
  }

  int closeCount = 0;
  while (k < lineEnd && normalizedSource.codeUnitAt(k) == openChar) {
    closeCount++;
    k++;
  }
  if (closeCount < openLen) {
    return false;
  }
  while (k < lineEnd) {
    final int cu = normalizedSource.codeUnitAt(k);
    if (cu != 0x20 && cu != 0x09) {
      return false;
    }
    k++;
  }
  return true;
}

final class _CompiledMermaidBytesLoader extends BytesLoader {
  const _CompiledMermaidBytesLoader(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> loadBytes(BuildContext? context) =>
      SynchronousFuture<ByteData>(ByteData.sublistView(bytes));

  @override
  int get hashCode => identityHashCode(bytes);

  @override
  bool operator ==(Object other) =>
      other is _CompiledMermaidBytesLoader && identical(bytes, other.bytes);

  @override
  String toString() => '_CompiledMermaidBytesLoader(${bytes.length} bytes)';
}

/// Built-in Mermaid diagram widget rendering fenced `mermaid` blocks offline via
/// `pele_dart` and `vector_graphics`.
final class BuiltInMermaidDiagram extends StatefulWidget {
  /// Creates a [BuiltInMermaidDiagram].
  const BuiltInMermaidDiagram({
    super.key,
    required this.node,
    required this.theme,
    this.isStreamingIncomplete = false,
  });

  /// Fenced Mermaid [CodeBlockNode].
  final CodeBlockNode node;

  /// Resolved Markdown visual theme.
  final MarkdownThemeData theme;

  /// Whether this block is an unclosed fenced Mermaid block in an active
  /// unfinished stream.
  final bool isStreamingIncomplete;

  @override
  State<BuiltInMermaidDiagram> createState() => _BuiltInMermaidDiagramState();
}

final class _BuiltInMermaidDiagramState extends State<BuiltInMermaidDiagram> {
  BuiltInMermaidResult? _result;
  int _generation = 0;
  late DerivedMermaidTheme _mermaidTheme;
  bool _copied = false;
  Timer? _copiedResetTimer;

  @override
  void initState() {
    super.initState();
    _mermaidTheme = deriveMermaidTheme(widget.theme);
    _resolveOrSchedule();
  }

  @override
  void didUpdateWidget(BuiltInMermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    final DerivedMermaidTheme nextMermaidTheme = deriveMermaidTheme(
      widget.theme,
    );
    final bool codeChanged = oldWidget.node.literal != widget.node.literal;
    final bool paletteChanged =
        _mermaidTheme.paletteKey != nextMermaidTheme.paletteKey;
    final bool streamingStateChanged =
        oldWidget.isStreamingIncomplete != widget.isStreamingIncomplete;
    _mermaidTheme = nextMermaidTheme;

    if (codeChanged || paletteChanged || streamingStateChanged) {
      _resolveOrSchedule();
    }
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  void _resolveOrSchedule() {
    final int generation = ++_generation;
    if (widget.isStreamingIncomplete) {
      _result = null;
      return;
    }

    final BuiltInMermaidResult? cached = BuiltInMermaidCache.instance.peek(
      widget.node.literal,
      _mermaidTheme,
    );
    if (cached != null) {
      _result = cached;
      return;
    }

    if (_isRunningInWidgetTest &&
        !BuiltInMermaidCache.instance.debugForceAsyncInTests) {
      _result = BuiltInMermaidCache.instance.renderSync(
        widget.node.literal,
        _mermaidTheme,
      );
      return;
    }

    _result = null;
    unawaited(
      BuiltInMermaidCache.instance
          .render(widget.node.literal, _mermaidTheme)
          .then((BuiltInMermaidResult result) {
            if (!mounted || generation != _generation) {
              return;
            }
            setState(() {
              _result = result;
            });
          }),
    );
  }

  void _copySource() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.node.literal)));
    _copiedResetTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _copiedResetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isStreamingIncomplete) {
      return _buildStreamingPreviewCard();
    }

    final BuiltInMermaidResult? activeResult = _result;
    if (activeResult == null) {
      return _buildLoadingCard();
    }

    return switch (activeResult) {
      BuiltInMermaidSuccess() => _buildSuccessDiagram(activeResult),
      BuiltInMermaidFailure() => _buildInvalidFallbackCard(activeResult),
    };
  }

  Widget _buildSuccessDiagram(BuiltInMermaidSuccess result) {
    final MarkdownThemeData theme = widget.theme;
    final Size logicalSize = result.logicalSize;
    final double scaleFactor = (theme.fontSize / 16.0).clamp(0.75, 2.5);
    final Size targetSize = Size(
      logicalSize.width * scaleFactor,
      logicalSize.height * scaleFactor,
    );

    final Widget graphic = createCompatVectorGraphic(
      loader: _CompiledMermaidBytesLoader(result.compiledBytes),
      width: targetSize.width,
      height: targetSize.height,
      fit: BoxFit.contain,
      strategy: RenderingStrategy.picture,
      excludeFromSemantics: true,
      errorBuilder: (BuildContext ctx, Object error, StackTrace _) =>
          _buildInvalidFallbackCard(
            BuiltInMermaidFailure(
              code: 'decodeFailed',
              message: 'Unable to display Mermaid graphic: $error',
            ),
          ),
    );

    return Semantics(
      container: true,
      label: result.semanticsLabel,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _mermaidTheme.cardBackground,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: theme.border, width: 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(14.0),
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints constraints) {
              if (!constraints.hasBoundedWidth ||
                  constraints.maxWidth.isInfinite) {
                return Center(
                  child: SizedBox.fromSize(size: targetSize, child: graphic),
                );
              }
              final double availableWidth = constraints.maxWidth;
              if (targetSize.width <= availableWidth) {
                return Center(
                  child: SizedBox.fromSize(size: targetSize, child: graphic),
                );
              }
              const double minReadableScale = 0.55;
              if (targetSize.width * minReadableScale <= availableWidth) {
                return Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox.fromSize(size: targetSize, child: graphic),
                  ),
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox.fromSize(size: targetSize, child: graphic),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    final MarkdownThemeData theme = widget.theme;
    return SelectionContainer.disabled(
      child: Semantics(
        container: true,
        label: 'Mermaid diagram preview',
        excludeSemantics: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 20.0),
          decoration: BoxDecoration(
            color: _mermaidTheme.cardBackground,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: theme.border, width: 1.0),
          ),
          child: Center(
            child: Text(
              'Mermaid diagram preview',
              style: TextStyle(
                color: theme.muted,
                fontSize: theme.fontSize * 0.85,
                fontFamily: theme.fontFamily,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreamingPreviewCard() {
    final MarkdownThemeData theme = widget.theme;
    final String trimmed = widget.node.literal.endsWith('\n')
        ? widget.node.literal.substring(0, widget.node.literal.length - 1)
        : widget.node.literal;
    return Semantics(
      container: true,
      label: 'Mermaid diagram preview',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.codeBackground,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: theme.border, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SelectionContainer.disabled(
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.border, width: 1.0),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color: theme.border.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          'mermaid',
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: theme.codeFontSize * 0.8,
                            fontWeight: FontWeight.w600,
                            fontFamily: theme.effectiveCodeFontFamily,
                            fontFamilyFallback:
                                MarkdownThemeData.defaultCodeFontFallback,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          'Mermaid diagram preview',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: theme.fontSize * 0.78,
                            fontFamily: theme.fontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (trimmed.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12.0),
                child: MarkdownRichText(trimmed, style: theme.codeTextStyle()),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: MarkdownRichText(
                  'Waiting for diagram definition...',
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: theme.fontSize * 0.82,
                    fontStyle: FontStyle.italic,
                    fontFamily: theme.fontFamily,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvalidFallbackCard(BuiltInMermaidFailure failure) {
    final MarkdownThemeData theme = widget.theme;
    final String trimmed = widget.node.literal.endsWith('\n')
        ? widget.node.literal.substring(0, widget.node.literal.length - 1)
        : widget.node.literal;
    final Color warningAccent = theme.alertPalette.warning.foreground;
    final Color warningBg = Color.alphaBlend(
      theme.alertPalette.warning.background,
      theme.codeBackground,
    );

    return Semantics(
      container: true,
      label: 'Mermaid diagram source',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.codeBackground,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: theme.border, width: 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.border, width: 1.0),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  SelectionContainer.disabled(
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color: theme.border.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          'mermaid',
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: theme.codeFontSize * 0.8,
                            fontWeight: FontWeight.w600,
                            fontFamily: theme.effectiveCodeFontFamily,
                            fontFamilyFallback:
                                MarkdownThemeData.defaultCodeFontFallback,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SelectionContainer.disabled(
                    child: MarkdownInteractiveAction(
                      onActivate: _copySource,
                      semanticLabel: _copied ? 'Copied' : 'Copy Mermaid source',
                      focusBorderColor: theme.accent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        child: Text(
                          _copied ? 'Copied' : 'Copy',
                          style: TextStyle(
                            color: _copied ? theme.accent : theme.muted,
                            fontSize: theme.fontSize * 0.78,
                            fontWeight: FontWeight.w600,
                            fontFamily: theme.fontFamily,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (trimmed.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12.0),
                child: MarkdownRichText(trimmed, style: theme.codeTextStyle()),
              ),
            SelectionContainer.disabled(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  color: warningBg,
                  border: Border(
                    top: BorderSide(color: theme.border, width: 1.0),
                  ),
                ),
                child: Text(
                  failure.message,
                  style: TextStyle(
                    color: warningAccent,
                    fontSize: theme.fontSize * 0.78,
                    fontFamily: theme.fontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
