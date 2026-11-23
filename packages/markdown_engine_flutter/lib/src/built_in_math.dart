import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart'
    show MarkdownUrlPolicy, MathBlockNode, MathInlineNode;
import 'package:tex_math_flutter/tex_math_flutter.dart';

import 'delegates.dart';
import 'theme.dart';

typedef _MathCacheKey = (
  int fontSignature,
  TexMathDisplayMode displayMode,
  String latex,
);

typedef _MathCacheEntry = ({
  DisplayList? displayList,
  String? spokenText,
  TexMathError? error,
});

/// Bounded LRU cache mapping `(font.signature, displayMode, latex)` keys to
/// laid-out [DisplayList]s, spoken accessibility text, or caught [TexMathError]s.
final class BuiltInMathCache {
  BuiltInMathCache._();

  /// Shared cache instance used by built-in math rendering.
  static final BuiltInMathCache instance = BuiltInMathCache._();

  /// Maximum number of retained entries in the LRU cache.
  static const int maxEntries = 256;

  final LinkedHashMap<_MathCacheKey, _MathCacheEntry> _entries =
      LinkedHashMap<_MathCacheKey, _MathCacheEntry>();

  int _layoutCount = 0;
  int _hitCount = 0;

  /// Number of synchronous TeX layout evaluations executed on cache misses.
  int get layoutCount => _layoutCount;

  /// Number of cache lookups satisfied without re-running TeX layout.
  int get hitCount => _hitCount;

  /// Current number of cached entries.
  int get length => _entries.length;

  /// Clears all cached entries and resets hit/miss telemetry counters.
  void clear() {
    _entries.clear();
    _layoutCount = 0;
    _hitCount = 0;
  }

  _MathCacheEntry _lookupOrRender(
    String latex, {
    required TexMathDisplayMode displayMode,
    required MathFont font,
  }) {
    final _MathCacheKey key = (font.signature, displayMode, latex);
    final _MathCacheEntry? hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      _hitCount++;
      return hit;
    }

    _layoutCount++;
    _MathCacheEntry entry;
    try {
      final RenderResult result = TexMathEngine(font: font)
          .render(latex, options: TexMathOptions(displayMode: displayMode));
      final String spoken = result.toSpokenText().trim();
      entry = (
        displayList: result.displayList,
        spokenText: spoken.isNotEmpty ? spoken : latex,
        error: null,
      );
    } on TexMathError catch (error) {
      entry = (displayList: null, spokenText: null, error: error);
    } on Object catch (error) {
      entry = (
        displayList: null,
        spokenText: null,
        error: TexMathSyntaxError('Unable to render TeX expression: $error'),
      );
    }

    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = entry;
    return entry;
  }
}

/// Derives a reactive [TexMathThemeData] from [theme] without requiring a
/// Material ancestor.
TexMathThemeData deriveTexMathThemeData(
  MarkdownThemeData theme, {
  double? fontSize,
}) {
  final Color errorColor = theme.alertPalette.caution.foreground;
  final Color errorBg = Color.alphaBlend(
    theme.alertPalette.caution.background,
    theme.codeBackground,
  );
  return TexMathThemeData(
    foreground: theme.foreground,
    accent: theme.accent,
    error: errorColor,
    muted: theme.muted,
    errorBackground: errorBg,
    fontSize: fontSize ?? theme.fontSize,
  );
}

ValueChanged<String>? _resolveMathLinkTapCallback({
  required bool isInsideMarkdownLink,
  required MarkdownBuilderDelegates delegates,
  required MarkdownUrlPolicy urlPolicy,
}) {
  if (isInsideMarkdownLink) {
    return null;
  }
  final MarkdownLinkTapCallback? onTapLink = delegates.onTapLink;
  final MarkdownWebLinkCallback? onOpenWebLink = delegates.onOpenWebLink;
  if (onTapLink == null && onOpenWebLink == null) {
    return null;
  }
  return (String destination) {
    final String normalized = MarkdownBuilderDelegates.normalizeUrlDestination(
      destination,
    );
    if (normalized.isEmpty || !urlPolicy.isAllowed(normalized)) {
      return;
    }
    onTapLink?.call(normalized, null);
    if (onOpenWebLink != null) {
      final Uri? parsed = Uri.tryParse(normalized);
      if (parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https') &&
          parsed.hasAuthority) {
        onOpenWebLink(parsed);
      }
    }
  };
}

/// Builds the built-in `tex_math_flutter` inline math widget for [node].
///
/// The returned widget is intended to sit inside a baseline-aligned
/// [WidgetSpan]. Once [TexMathFontBundle.cachedMathFont] is available, layout
/// results are served synchronously from [BuiltInMathCache] via
/// [TexMath.displayList]; while cold, [TexMath.inline] loads the bundled font
/// asynchronously and renders without throwing on invalid LaTeX.
Widget buildBuiltInInlineMathWidget({
  required BuildContext context,
  required MathInlineNode node,
  required TextStyle style,
  required MarkdownThemeData theme,
  required MarkdownBuilderDelegates delegates,
  required MarkdownUrlPolicy urlPolicy,
  required bool isInsideLink,
}) {
  final bool hasAncestorSelection = SelectionContainer.maybeOf(context) != null;
  final TexMathThemeData mathTheme = deriveTexMathThemeData(
    theme,
    fontSize: style.fontSize ?? theme.fontSize,
  );
  final ValueChanged<String>? onInternalLinkTap = _resolveMathLinkTapCallback(
    isInsideMarkdownLink: isInsideLink,
    delegates: delegates,
    urlPolicy: urlPolicy,
  );

  final MathFont? cachedFont = TexMathFontBundle.cachedMathFont;
  if (cachedFont == null) {
    return TexMathTheme(
      data: mathTheme,
      child: _ColdInlineMath(
        latex: node.latex,
        style: style,
        theme: theme,
        hasAncestorSelection: hasAncestorSelection,
        onInternalLinkTap: onInternalLinkTap,
      ),
    );
  }

  return TexMathTheme(
    data: mathTheme,
    child: _buildWarmInlineMath(
      context: context,
      latex: node.latex,
      font: cachedFont,
      style: style,
      theme: theme,
      hasAncestorSelection: hasAncestorSelection,
      onInternalLinkTap: onInternalLinkTap,
    ),
  );
}

double _resolveScaledFontSize(
  BuildContext context,
  TextStyle style,
  MarkdownThemeData theme,
) {
  final double candidateSize = style.fontSize ?? theme.fontSize;
  final double safeBaseSize = (candidateSize.isFinite && candidateSize > 0.0)
      ? candidateSize
      : theme.fontSize;
  final double rawScaled =
      MediaQuery.maybeTextScalerOf(context)?.scale(safeBaseSize) ??
      safeBaseSize;
  return (rawScaled.isFinite && rawScaled > 0.0) ? rawScaled : safeBaseSize;
}

Widget _buildWarmInlineMath({
  required BuildContext context,
  required String latex,
  required MathFont font,
  required TextStyle style,
  required MarkdownThemeData theme,
  required bool hasAncestorSelection,
  required ValueChanged<String>? onInternalLinkTap,
}) {
  final double scaledFontSize = _resolveScaledFontSize(context, style, theme);
  final _MathCacheEntry entry = BuiltInMathCache.instance._lookupOrRender(
    latex,
    displayMode: TexMathDisplayMode.inline,
    font: font,
  );
  if (entry.error != null) {
    return _IntrinsicSizeHint(
      intrinsicWidth: 0.0,
      intrinsicHeight: scaledFontSize,
      baselineOffset: scaledFontSize * 0.8,
      child: TexMathErrorWidget(
        source: latex,
        error: entry.error,
        displayMode: TexMathDisplayMode.inline,
        selectable: hasAncestorSelection,
      ),
    );
  }

  final DisplayList displayList = entry.displayList!;
  final double intrinsicWidth = (displayList.metrics.widthEm * scaledFontSize)
      .clamp(0.0, 1e6);
  final double intrinsicHeight =
      (displayList.metrics.totalHeightEm * scaledFontSize).clamp(0.0, 1e6);
  final double baselineOffset =
      (displayList.metrics.baselineEm * scaledFontSize).clamp(
        0.0,
        intrinsicHeight,
      );

  return _IntrinsicSizeHint(
    intrinsicWidth: intrinsicWidth,
    intrinsicHeight: intrinsicHeight,
    baselineOffset: baselineOffset,
    child: TexMath.displayList(
      displayList,
      source: latex,
      displayMode: TexMathDisplayMode.inline,
      font: font,
      overflow: TexMathOverflow.scaleToFit,
      pathCache: TexMathPathCache.shared,
      textStyle: style,
      semanticsLabel: entry.spokenText,
      selectable: hasAncestorSelection,
      onLinkTap: onInternalLinkTap,
    ),
  );
}

final class _ColdInlineMath extends StatefulWidget {
  const _ColdInlineMath({
    required this.latex,
    required this.style,
    required this.theme,
    required this.hasAncestorSelection,
    required this.onInternalLinkTap,
  });

  final String latex;
  final TextStyle style;
  final MarkdownThemeData theme;
  final bool hasAncestorSelection;
  final ValueChanged<String>? onInternalLinkTap;

  @override
  State<_ColdInlineMath> createState() => _ColdInlineMathState();
}

final class _ColdInlineMathState extends State<_ColdInlineMath> {
  MathFont? _loadedFont;

  @override
  void initState() {
    super.initState();
    _loadedFont = TexMathFontBundle.cachedMathFont;
    if (_loadedFont == null) {
      unawaited(
        TexMathFontBundle.loadMathFont().then(
          (MathFont font) {
            if (mounted && _loadedFont == null) {
              setState(() {
                _loadedFont = font;
              });
            }
          },
          onError: (Object _, StackTrace _) {
            // Let TexMath.inline surface any font loading error cleanly.
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final MathFont? font = _loadedFont ?? TexMathFontBundle.cachedMathFont;
    if (font != null) {
      return _buildWarmInlineMath(
        context: context,
        latex: widget.latex,
        font: font,
        style: widget.style,
        theme: widget.theme,
        hasAncestorSelection: widget.hasAncestorSelection,
        onInternalLinkTap: widget.onInternalLinkTap,
      );
    }
    final double scaledFontSize = _resolveScaledFontSize(
      context,
      widget.style,
      widget.theme,
    );
    return _IntrinsicSizeHint(
      intrinsicWidth: 0.0,
      intrinsicHeight: scaledFontSize,
      baselineOffset: scaledFontSize * 0.8,
      child: TexMath.inline(
        widget.latex,
        overflow: TexMathOverflow.scaleToFit,
        pathCache: TexMathPathCache.shared,
        textStyle: widget.style,
        selectable: widget.hasAncestorSelection,
        onLinkTap: widget.onInternalLinkTap,
        errorBuilder: (BuildContext ctx, String source, TexMathError error) =>
            TexMathErrorWidget(
              source: source,
              error: error,
              displayMode: TexMathDisplayMode.inline,
              selectable: widget.hasAncestorSelection,
            ),
      ),
    );
  }
}

final class _IntrinsicSizeHint extends SingleChildRenderObjectWidget {
  const _IntrinsicSizeHint({
    required this.intrinsicWidth,
    required this.intrinsicHeight,
    required this.baselineOffset,
    required super.child,
  });

  final double intrinsicWidth;
  final double intrinsicHeight;
  final double baselineOffset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntrinsicSizeHint(intrinsicWidth, intrinsicHeight, baselineOffset);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderIntrinsicSizeHint renderObject,
  ) {
    renderObject
      ..intrinsicWidth = intrinsicWidth
      ..intrinsicHeight = intrinsicHeight
      ..baselineOffset = baselineOffset;
  }
}

final class _RenderIntrinsicSizeHint extends RenderProxyBox {
  _RenderIntrinsicSizeHint(
    this._intrinsicWidth,
    this._intrinsicHeight,
    this._baselineOffset,
  );

  double _intrinsicWidth;
  double get intrinsicWidth => _intrinsicWidth;
  set intrinsicWidth(double value) {
    if (_intrinsicWidth == value) {
      return;
    }
    _intrinsicWidth = value;
    markNeedsLayout();
  }

  double _intrinsicHeight;
  double get intrinsicHeight => _intrinsicHeight;
  set intrinsicHeight(double value) {
    if (_intrinsicHeight == value) {
      return;
    }
    _intrinsicHeight = value;
    markNeedsLayout();
  }

  double _baselineOffset;
  double get baselineOffset => _baselineOffset;
  set baselineOffset(double value) {
    if (_baselineOffset == value) {
      return;
    }
    _baselineOffset = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(_intrinsicWidth, super.computeMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(_intrinsicWidth, super.computeMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(_intrinsicHeight, super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(_intrinsicHeight, super.computeMaxIntrinsicHeight(width));

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    if (baseline == TextBaseline.alphabetic) {
      return _baselineOffset;
    }
    return math.max(
      _intrinsicHeight,
      super.computeDryLayout(constraints).height,
    );
  }
}

/// Builds the built-in `tex_math_flutter` display math block widget for [node].
Widget buildBuiltInMathBlockWidget({
  required BuildContext context,
  required MathBlockNode node,
  required MarkdownThemeData theme,
  required MarkdownBuilderDelegates delegates,
  required MarkdownUrlPolicy urlPolicy,
}) {
  final bool hasAncestorSelection = SelectionContainer.maybeOf(context) != null;
  final TexMathThemeData mathTheme = deriveTexMathThemeData(
    theme,
    fontSize: theme.fontSize,
  );
  final ValueChanged<String>? onInternalLinkTap = _resolveMathLinkTapCallback(
    isInsideMarkdownLink: false,
    delegates: delegates,
    urlPolicy: urlPolicy,
  );
  final String trimmedSource = node.latex.trim();
  final TextStyle displayStyle = TextStyle(
    color: theme.foreground,
    fontSize: theme.fontSize,
  );

  final MathFont? cachedFont = TexMathFontBundle.cachedMathFont;
  final Widget innerMath;
  if (cachedFont == null) {
    innerMath = TexMath.display(
      trimmedSource,
      overflow: TexMathOverflow.scroll,
      pathCache: TexMathPathCache.shared,
      textStyle: displayStyle,
      selectable: hasAncestorSelection,
      onLinkTap: onInternalLinkTap,
      errorBuilder: (BuildContext ctx, String source, TexMathError error) =>
          TexMathErrorWidget(
            source: source,
            error: error,
            displayMode: TexMathDisplayMode.display,
            selectable: hasAncestorSelection,
          ),
    );
  } else {
    final _MathCacheEntry entry = BuiltInMathCache.instance._lookupOrRender(
      trimmedSource,
      displayMode: TexMathDisplayMode.display,
      font: cachedFont,
    );
    if (entry.error != null) {
      innerMath = TexMathErrorWidget(
        source: trimmedSource,
        error: entry.error,
        displayMode: TexMathDisplayMode.display,
        selectable: hasAncestorSelection,
      );
    } else {
      innerMath = TexMath.displayList(
        entry.displayList!,
        source: trimmedSource,
        displayMode: TexMathDisplayMode.display,
        font: cachedFont,
        overflow: TexMathOverflow.scroll,
        pathCache: TexMathPathCache.shared,
        textStyle: displayStyle,
        semanticsLabel: entry.spokenText,
        selectable: hasAncestorSelection,
        onLinkTap: onInternalLinkTap,
      );
    }
  }

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
    decoration: BoxDecoration(
      color: theme.codeBackground.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(8.0),
      border: Border.all(color: theme.border, width: 1.0),
    ),
    child: Center(
      child: TexMathTheme(data: mathTheme, child: innerMath),
    ),
  );
}
