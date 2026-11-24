import 'dart:math' as math;
import 'dart:ui' as ui show TextBox, TextHeightBehavior;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart'
    show
        MouseCursor,
        MouseTrackerAnnotation,
        PointerEnterEventListener,
        PointerExitEventListener;
import 'package:flutter/widgets.dart';

/// Ambient Flutter environment values resolved once at `SliverMarkdownDocument`
/// or `MarkdownView` rather than per-block or per-inline span.
@immutable
final class MarkdownRenderEnvironment {
  /// Creates a [MarkdownRenderEnvironment].
  const MarkdownRenderEnvironment({
    required this.textScaler,
    required this.textDirection,
    required this.selectionRegistrar,
    required this.selectionColor,
    this.selectionMouseCursor,
    required this.locale,
    required this.hasOverlay,
    required this.defaultTextStyle,
    required this.boldText,
    this.lineHeightScaleFactor,
    this.letterSpacing,
    this.wordSpacing,
  });

  /// Resolves all ambient text/selection/directionality properties once from
  /// [context].
  factory MarkdownRenderEnvironment.resolve(BuildContext context) {
    final DefaultTextStyle defaultText = DefaultTextStyle.of(context);
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    final DefaultSelectionStyle? selectionStyle = registrar != null
        ? DefaultSelectionStyle.of(context)
        : null;
    final Color? selectionColor = registrar != null
        ? (selectionStyle!.selectionColor ?? DefaultSelectionStyle.defaultColor)
        : null;
    final MouseCursor? selectionMouseCursor = registrar != null
        ? selectionStyle!.mouseCursor
        : null;
    final TextScaler scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final TextDirection dir =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    final bool bold = MediaQuery.boldTextOf(context);
    final double? lineHeightScaleFactor =
        MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
    final double? letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(
      context,
    );
    final double? wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
    final Locale? locale = Localizations.maybeLocaleOf(context);
    final bool hasOverlay = Overlay.maybeOf(context) != null;
    return MarkdownRenderEnvironment(
      textScaler: scaler,
      textDirection: dir,
      selectionRegistrar: registrar,
      selectionColor: selectionColor,
      selectionMouseCursor: selectionMouseCursor,
      locale: locale,
      hasOverlay: hasOverlay,
      defaultTextStyle: defaultText.style,
      boldText: bold,
      lineHeightScaleFactor: lineHeightScaleFactor,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
    );
  }

  /// Ambient text scaler.
  final TextScaler textScaler;

  /// Ambient text direction.
  final TextDirection textDirection;

  /// Ambient selection registrar, or `null` when non-selectable.
  final SelectionRegistrar? selectionRegistrar;

  /// Ambient selection highlight color.
  final Color? selectionColor;

  /// Ambient selection mouse cursor override when selectable.
  final MouseCursor? selectionMouseCursor;

  /// Ambient locale.
  final Locale? locale;

  /// Whether an [Overlay] ancestor exists (for `Tooltip` widgets).
  final bool hasOverlay;

  /// Ambient [DefaultTextStyle.style].
  final TextStyle defaultTextStyle;

  /// Ambient `MediaQuery.boldTextOf`.
  final bool boldText;

  /// Optional accessibility line-height override.
  final double? lineHeightScaleFactor;

  /// Optional accessibility letter-spacing override.
  final double? letterSpacing;

  /// Optional accessibility word-spacing override.
  final double? wordSpacing;

  /// Merges [defaultTextStyle], [boldText], and spacing overrides onto
  /// [style], matching `Text.build` semantics.
  TextStyle resolveTextStyle(TextStyle style) {
    TextStyle resolved = style.inherit ? defaultTextStyle.merge(style) : style;
    if (boldText) {
      resolved = resolved.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    if (lineHeightScaleFactor != null ||
        letterSpacing != null ||
        wordSpacing != null) {
      resolved = resolved.merge(
        TextStyle(
          height: lineHeightScaleFactor,
          letterSpacing: letterSpacing,
          wordSpacing: wordSpacing,
        ),
      );
    }
    return resolved;
  }

  /// Returns a copy with [selectionMouseCursor] replaced (or `this` if
  /// unchanged).
  MarkdownRenderEnvironment withSelectionMouseCursor(MouseCursor? cursor) {
    if (selectionMouseCursor == cursor) {
      return this;
    }
    return MarkdownRenderEnvironment(
      textScaler: textScaler,
      textDirection: textDirection,
      selectionRegistrar: selectionRegistrar,
      selectionColor: selectionColor,
      selectionMouseCursor: cursor,
      locale: locale,
      hasOverlay: hasOverlay,
      defaultTextStyle: defaultTextStyle,
      boldText: boldText,
      lineHeightScaleFactor: lineHeightScaleFactor,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
    );
  }

  /// Applies [lineHeightScaleFactor], [letterSpacing], and [wordSpacing]
  /// overrides to nested [TextSpan] children when active.
  TextSpan applySpacingOverrides(TextSpan span) => _applyTextSpacingOverrides(
    lineHeightScaleFactor: lineHeightScaleFactor,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    textSpan: span,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownRenderEnvironment &&
          textScaler == other.textScaler &&
          textDirection == other.textDirection &&
          identical(selectionRegistrar, other.selectionRegistrar) &&
          selectionColor == other.selectionColor &&
          selectionMouseCursor == other.selectionMouseCursor &&
          locale == other.locale &&
          hasOverlay == other.hasOverlay &&
          defaultTextStyle == other.defaultTextStyle &&
          boldText == other.boldText &&
          lineHeightScaleFactor == other.lineHeightScaleFactor &&
          letterSpacing == other.letterSpacing &&
          wordSpacing == other.wordSpacing;

  @override
  int get hashCode => Object.hash(
    textScaler,
    textDirection,
    selectionRegistrar,
    selectionColor,
    selectionMouseCursor,
    locale,
    hasOverlay,
    defaultTextStyle,
    boldText,
    lineHeightScaleFactor,
    letterSpacing,
    wordSpacing,
  );
}

TextSpan _applyTextSpacingOverrides({
  double? lineHeightScaleFactor,
  double? letterSpacing,
  double? wordSpacing,
  required TextSpan textSpan,
}) {
  if (lineHeightScaleFactor == null &&
      letterSpacing == null &&
      wordSpacing == null) {
    return textSpan;
  }
  final TextStyle overrideStyle = TextStyle(
    height: lineHeightScaleFactor,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
  );
  return _applyOverrideSpan(overrideStyle, textSpan);
}

TextSpan _applyOverrideSpan(TextStyle overrideStyle, TextSpan span) {
  return TextSpan(
    text: span.text,
    children: span.children
        ?.map((InlineSpan child) {
          if (child is TextSpan && child.runtimeType == TextSpan) {
            return _applyOverrideSpan(overrideStyle, child);
          }
          return child;
        })
        .toList(growable: false),
    style: span.style?.merge(overrideStyle) ?? overrideStyle,
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    semanticsIdentifier: span.semanticsIdentifier,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

/// Package-internal capability interface for [Selectable] implementations that
/// expose release-safe layout readiness before screen-order sorting or event
/// dispatch.
abstract interface class MarkdownLayoutAwareSelectable {
  /// Whether the backing [RenderObject] is attached, sized, and clean for
  /// layout queries in debug, profile, and release builds.
  bool get isLayoutReady;
}

bool _isRenderObjectClean(RenderObject ro) {
  if (!ro.attached) {
    return false;
  }
  if (ro is RenderBox && !ro.hasSize) {
    return false;
  }
  if (ro.debugNeedsLayout) {
    return false;
  }
  if (ro is _SafeRenderParagraph && !ro.isLayoutClean) {
    return false;
  }
  if (ro is RenderMarkdownParagraph && !ro.isLayoutClean) {
    return false;
  }
  return true;
}

bool _isRenderSubtreeLayoutReady(RenderObject root) {
  if (!_isRenderObjectClean(root)) {
    return false;
  }
  // Never descend into RenderViewportBase / RenderSliver so off-screen
  // kept-alive sliver items in _keepAliveBucket do not block viewport-level
  // selection readiness.
  if (root is RenderViewportBase || root is RenderSliver) {
    return true;
  }
  bool ready = true;
  void checkChild(RenderObject child) {
    if (!ready) {
      return;
    }
    if (!_isRenderObjectClean(child)) {
      ready = false;
      return;
    }
    if (child is RenderViewportBase || child is RenderSliver) {
      return;
    }
    child.visitChildren(checkChild);
  }

  root.visitChildren(checkChild);
  return ready;
}

/// Returns whether [selectable] has completed layout cleanly across debug,
/// profile, and release builds and is safe to query for bounding boxes or
/// selection events.
bool isSelectableLayoutReady(Selectable selectable) {
  if (selectable case final MarkdownLayoutAwareSelectable aware) {
    return aware.isLayoutReady;
  }
  if (selectable case final RenderObject ro) {
    return _isRenderSubtreeLayoutReady(ro);
  }
  if (selectable case final State state) {
    if (!state.mounted) {
      return false;
    }
    final RenderObject? ro = state.context.findRenderObject();
    return ro != null && _isRenderSubtreeLayoutReady(ro);
  }
  return true;
}

final class _SafeRenderParagraph extends RenderParagraph {
  _SafeRenderParagraph(
    super.text, {
    super.textAlign,
    required super.textDirection,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    super.registrar,
  });

  bool _needsLayoutFlag = true;
  VoidCallback? onDidLayout;

  bool get isLayoutClean =>
      attached && hasSize && !_needsLayoutFlag && !debugNeedsLayout;

  @override
  void markNeedsLayout() {
    _needsLayoutFlag = true;
    super.markNeedsLayout();
  }

  @override
  void systemFontsDidChange() {
    _needsLayoutFlag = true;
    super.systemFontsDidChange();
  }

  @override
  void performLayout() {
    super.performLayout();
    _needsLayoutFlag = false;
    onDidLayout?.call();
  }

  @override
  void dispose() {
    onDidLayout = null;
    super.dispose();
  }
}

final class _SafeRichText extends RichText {
  _SafeRichText({
    super.key,
    required super.text,
    super.textAlign = TextAlign.start,
    super.textDirection,
    super.softWrap = true,
    super.overflow = TextOverflow.clip,
    super.textScaler = TextScaler.noScaling,
    super.maxLines,
    super.locale,
    super.strutStyle,
    super.textWidthBasis = TextWidthBasis.parent,
    super.textHeightBehavior,
    super.selectionRegistrar,
    super.selectionColor,
    this.onDidLayout,
  });

  final VoidCallback? onDidLayout;

  @override
  _SafeRenderParagraph createRenderObject(BuildContext context) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    final _SafeRenderParagraph renderObject = _SafeRenderParagraph(
      text,
      textAlign: textAlign,
      textDirection: textDirection ?? Directionality.of(context),
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      registrar: selectionRegistrar,
      selectionColor: selectionColor,
    )..onDidLayout = onDidLayout;
    super.updateRenderObject(context, renderObject);
    return renderObject;
  }

  @override
  void updateRenderObject(BuildContext context, RenderParagraph renderObject) {
    super.updateRenderObject(context, renderObject);
    if (renderObject is _SafeRenderParagraph) {
      renderObject.onDidLayout = onDidLayout;
    }
  }
}

/// Drop-in [Text] replacement that guards paragraph selection and screen-order
/// layout readiness across debug, profile, and release builds.
///
/// Inside an enclosing [SelectionContainer] (such as `SelectionArea` or
/// `MarkdownView`), [MarkdownRichText] wraps its text in a layout-aware
/// [SelectionContainer] backed by [_SafeRenderParagraph] rather than relying on
/// [RenderObject.debugNeedsLayout], which always returns `false` in profile and
/// release builds. This prevents stale-layout assertions and crashes when
/// off-screen kept-alive sliver items rebuild during theme toggles, font loads,
/// or document updates while preserving identical typography and metrics to
/// Flutter's [Text].
///
/// Outside a selection scope (including under [SelectionContainer.disabled]),
/// [MarkdownRichText] renders a non-selectable paragraph directly.
final class MarkdownRichText extends Text {
  /// Creates a layout-safe selectable text widget displaying [data].
  ///
  /// Parameters match [Text.new]. When [style] is `null`, the widget inherits
  /// from the closest enclosing [DefaultTextStyle].
  const MarkdownRichText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    // ignore: deprecated_member_use
    super.textScaleFactor,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  /// Creates a layout-safe selectable text widget with an [InlineSpan] tree.
  ///
  /// Parameters match [Text.rich]. Supports nested [TextSpan]s and
  /// [WidgetSpan]s while ensuring screen-order comparisons, triple-click
  /// paragraph selection, and drag selection wait until layout is clean.
  const MarkdownRichText.rich(
    super.textSpan, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    // ignore: deprecated_member_use
    super.textScaleFactor,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  }) : super.rich();

  @override
  Widget build(BuildContext context) {
    final DefaultTextStyle defaultTextStyle = DefaultTextStyle.of(context);
    TextStyle? effectiveTextStyle = style;
    if (style == null || style!.inherit) {
      effectiveTextStyle = defaultTextStyle.style.merge(style);
    }
    if (MediaQuery.boldTextOf(context)) {
      effectiveTextStyle = effectiveTextStyle!.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final double? lineHeightScaleFactor =
        MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
    final double? letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(
      context,
    );
    final double? wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
    final TextSpan effectiveTextSpan = _applyTextSpacingOverrides(
      lineHeightScaleFactor: lineHeightScaleFactor,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textSpan: TextSpan(
        style: effectiveTextStyle,
        text: data,
        locale: locale,
        children: textSpan != null ? <InlineSpan>[textSpan!] : null,
      ),
    );
    final StrutStyle? effectiveStrutStyle = strutStyle?.merge(
      StrutStyle(height: lineHeightScaleFactor),
    );
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    // ignore: deprecated_member_use
    final double? deprecatedScaleFactor = textScaleFactor;
    final TextScaler resolvedTextScaler = switch ((
      textScaler,
      deprecatedScaleFactor,
    )) {
      (final TextScaler scaler, _) => scaler,
      (null, final double scaleFactor) => TextScaler.linear(scaleFactor),
      (null, null) => MediaQuery.textScalerOf(context),
    };
    final TextAlign resolvedTextAlign =
        textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start;
    final bool resolvedSoftWrap = softWrap ?? defaultTextStyle.softWrap;
    final TextOverflow resolvedOverflow =
        overflow ?? effectiveTextStyle?.overflow ?? defaultTextStyle.overflow;
    final int? resolvedMaxLines = maxLines ?? defaultTextStyle.maxLines;
    final TextWidthBasis resolvedTextWidthBasis =
        textWidthBasis ?? defaultTextStyle.textWidthBasis;
    final ui.TextHeightBehavior? resolvedTextHeightBehavior =
        textHeightBehavior ??
        defaultTextStyle.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context);
    final Color resolvedSelectionColor =
        selectionColor ??
        DefaultSelectionStyle.of(context).selectionColor ??
        DefaultSelectionStyle.defaultColor;

    late Widget result;
    if (registrar != null) {
      result = MouseRegion(
        cursor:
            DefaultSelectionStyle.of(context).mouseCursor ??
            SystemMouseCursors.text,
        child: _SafeSelectableTextContainer(
          textAlign: resolvedTextAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: resolvedSoftWrap,
          overflow: resolvedOverflow,
          textScaler: resolvedTextScaler,
          maxLines: resolvedMaxLines,
          strutStyle: effectiveStrutStyle,
          textWidthBasis: resolvedTextWidthBasis,
          textHeightBehavior: resolvedTextHeightBehavior,
          selectionColor: resolvedSelectionColor,
          text: effectiveTextSpan,
        ),
      );
    } else {
      result = _SafeRichText(
        textAlign: resolvedTextAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: resolvedSoftWrap,
        overflow: resolvedOverflow,
        textScaler: resolvedTextScaler,
        maxLines: resolvedMaxLines,
        strutStyle: effectiveStrutStyle,
        textWidthBasis: resolvedTextWidthBasis,
        textHeightBehavior: resolvedTextHeightBehavior,
        selectionColor: resolvedSelectionColor,
        text: effectiveTextSpan,
      );
    }
    if (semanticsLabel != null || semanticsIdentifier != null) {
      result = Semantics(
        textDirection: textDirection,
        label: semanticsLabel,
        identifier: semanticsIdentifier,
        child: ExcludeSemantics(
          excluding: semanticsLabel != null,
          child: result,
        ),
      );
    }
    return result;
  }
}

final class _SafeSelectableTextContainer extends StatefulWidget {
  const _SafeSelectableTextContainer({
    required this.text,
    required this.textAlign,
    this.textDirection,
    required this.softWrap,
    required this.overflow,
    required this.textScaler,
    this.maxLines,
    this.locale,
    this.strutStyle,
    required this.textWidthBasis,
    this.textHeightBehavior,
    required this.selectionColor,
  });

  final TextSpan text;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final bool softWrap;
  final TextOverflow overflow;
  final TextScaler textScaler;
  final int? maxLines;
  final Locale? locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final Color selectionColor;

  @override
  State<_SafeSelectableTextContainer> createState() =>
      _SafeSelectableTextContainerState();
}

final class _SafeSelectableTextContainerState
    extends State<_SafeSelectableTextContainer> {
  late final _SafeRichTextSelectionContainerDelegate _selectionDelegate;
  final GlobalKey _textKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectionDelegate = _SafeRichTextSelectionContainerDelegate(_textKey);
  }

  @override
  void dispose() {
    _selectionDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(
      delegate: _selectionDelegate,
      child: _SafeRichTextScope(
        textKey: _textKey,
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        locale: widget.locale,
        softWrap: widget.softWrap,
        overflow: widget.overflow,
        textScaler: widget.textScaler,
        maxLines: widget.maxLines,
        strutStyle: widget.strutStyle,
        textWidthBasis: widget.textWidthBasis,
        textHeightBehavior: widget.textHeightBehavior,
        selectionColor: widget.selectionColor,
        text: widget.text,
        onDidLayout: _selectionDelegate._handleParagraphDidLayout,
      ),
    );
  }
}

final class _SafeRichTextScope extends StatelessWidget {
  const _SafeRichTextScope({
    this.textKey,
    required this.text,
    required this.textAlign,
    this.textDirection,
    required this.softWrap,
    required this.overflow,
    required this.textScaler,
    this.maxLines,
    this.locale,
    this.strutStyle,
    required this.textWidthBasis,
    this.textHeightBehavior,
    required this.selectionColor,
    this.onDidLayout,
  });

  final GlobalKey? textKey;
  final InlineSpan text;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final bool softWrap;
  final TextOverflow overflow;
  final TextScaler textScaler;
  final int? maxLines;
  final Locale? locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final Color selectionColor;
  final VoidCallback? onDidLayout;

  @override
  Widget build(BuildContext context) {
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    return _SafeRichText(
      key: textKey,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionRegistrar: registrar,
      selectionColor: selectionColor,
      text: text,
      onDidLayout: onDidLayout,
    );
  }
}

const double _kSafeSelectableVerticalThreshold = 3.0;

/// Compares two screen-space rectangles in top-to-bottom, left-to-right
/// reading order while ordering non-finite rectangles deterministically.
int compareScreenOrderRects(Rect rectA, Rect rectB) {
  final bool finiteA = rectA.isFinite;
  final bool finiteB = rectB.isFinite;
  if (!finiteA || !finiteB) {
    if (!finiteA && !finiteB) {
      return 0;
    }
    return finiteA ? 1 : -1;
  }
  if (rectA == rectB) {
    return 0;
  }
  final int vertical = _compareScreenOrderVertically(rectA, rectB);
  if (vertical != 0) {
    return vertical;
  }
  return _compareScreenOrderHorizontally(rectA, rectB);
}

int _compareScreenOrderVertically(Rect a, Rect b) {
  if ((a.top - b.top < _kSafeSelectableVerticalThreshold &&
          a.bottom - b.bottom > -_kSafeSelectableVerticalThreshold) ||
      (b.top - a.top < _kSafeSelectableVerticalThreshold &&
          b.bottom - a.bottom > -_kSafeSelectableVerticalThreshold)) {
    return 0;
  }
  if ((a.top - b.top).abs() > _kSafeSelectableVerticalThreshold) {
    return a.top.compareTo(b.top);
  }
  final int byBottom = a.bottom.compareTo(b.bottom);
  return byBottom != 0 ? byBottom : a.top.compareTo(b.top);
}

int _compareScreenOrderHorizontally(Rect a, Rect b) {
  if ((a.left - b.left).abs() < precisionErrorTolerance &&
      (a.right - b.right).abs() < precisionErrorTolerance) {
    return 0;
  }
  if (a.left - b.left < precisionErrorTolerance &&
      a.right - b.right > -precisionErrorTolerance) {
    return -1;
  }
  if (b.left - a.left < precisionErrorTolerance &&
      b.right - a.right > -precisionErrorTolerance) {
    return 1;
  }
  if ((a.left - b.left).abs() > precisionErrorTolerance) {
    return a.left.compareTo(b.left);
  }
  final int byRight = a.right.compareTo(b.right);
  return byRight != 0 ? byRight : a.left.compareTo(b.left);
}

typedef _SafeSelectionInfo = ({int contentLength, SelectedContentRange? range});

final class _SafeRichTextSelectionContainerDelegate
    extends StaticSelectionContainerDelegate {
  _SafeRichTextSelectionContainerDelegate(this._textKey);

  final GlobalKey _textKey;
  final Map<Selectable, int> _registrationOrder =
      Map<Selectable, int>.identity();
  final Set<Selectable> _trackedSelectables = <Selectable>{};
  int _nextRegistrationOrder = 0;

  bool _needsReorderAfterLayout = false;
  bool _pendingSelectAll = false;
  bool _needsSyncAfterLayout = false;
  bool _postFrameFlushScheduled = false;
  bool _disposed = false;

  _SafeRenderParagraph? get _paragraph {
    final RenderObject? ro = _textKey.currentContext?.findRenderObject();
    return ro is _SafeRenderParagraph ? ro : null;
  }

  bool _isSubtreeLayoutReady() {
    final _SafeRenderParagraph? p = _paragraph;
    if (p == null || !p.isLayoutClean) {
      return false;
    }
    for (final Selectable s in _trackedSelectables) {
      if (!p.selectableBelongsToParagraph(s) && !isSelectableLayoutReady(s)) {
        return false;
      }
    }
    return true;
  }

  void _schedulePostFrameFlush() {
    if (_postFrameFlushScheduled || _disposed) {
      return;
    }
    _postFrameFlushScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _postFrameFlushScheduled = false;
      if (_disposed || !_isSubtreeLayoutReady()) {
        return;
      }
      _flushDeferredUpdatesAfterLayout();
    });
  }

  void _handleParagraphDidLayout() {
    if (_disposed) {
      return;
    }
    if (!_needsReorderAfterLayout &&
        !_pendingSelectAll &&
        !_needsSyncAfterLayout) {
      return;
    }
    _schedulePostFrameFlush();
  }

  void _flushDeferredUpdatesAfterLayout() {
    _resortIfNeeded();
    final bool runSelectAll = _pendingSelectAll;
    _pendingSelectAll = false;
    final bool runSync = _needsSyncAfterLayout;
    _needsSyncAfterLayout = false;
    if (runSelectAll) {
      if (selectables.isNotEmpty) {
        super.handleSelectAll(const SelectAllSelectionEvent());
      }
      layoutDidChange();
      return;
    }
    if (runSync) {
      didChangeSelectables();
    }
    layoutDidChange();
  }

  void _resortIfNeeded() {
    if (!_needsReorderAfterLayout || !_isSubtreeLayoutReady()) {
      return;
    }
    _needsReorderAfterLayout = false;
    if (selectables.length > 1) {
      final Selectable? startSel =
          (currentSelectionStartIndex >= 0 &&
              currentSelectionStartIndex < selectables.length)
          ? selectables[currentSelectionStartIndex]
          : null;
      final Selectable? endSel =
          (currentSelectionEndIndex >= 0 &&
              currentSelectionEndIndex < selectables.length)
          ? selectables[currentSelectionEndIndex]
          : null;
      selectables.sort(compareOrder);
      if (startSel != null) {
        currentSelectionStartIndex = selectables.indexOf(startSel);
      }
      if (endSel != null) {
        currentSelectionEndIndex = selectables.indexOf(endSel);
      }
    }
  }

  @override
  void add(Selectable selectable) {
    _registrationOrder[selectable] = _nextRegistrationOrder++;
    _trackedSelectables.add(selectable);
    super.add(selectable);
  }

  @override
  void remove(Selectable selectable) {
    _trackedSelectables.remove(selectable);
    _registrationOrder.remove(selectable);
    super.remove(selectable);
  }

  @override
  void dispose() {
    _disposed = true;
    _trackedSelectables.clear();
    _registrationOrder.clear();
    super.dispose();
  }

  @override
  Comparator<Selectable> get compareOrder {
    if (!_isSubtreeLayoutReady()) {
      _needsReorderAfterLayout = true;
      return _compareByRegistrationOrder;
    }
    return _compareScreenOrder;
  }

  int _compareByRegistrationOrder(Selectable a, Selectable b) {
    if (identical(a, b)) {
      return 0;
    }
    return (_registrationOrder[a] ?? 0).compareTo(_registrationOrder[b] ?? 0);
  }

  int _compareScreenOrder(Selectable a, Selectable b) {
    if (identical(a, b)) {
      return 0;
    }
    final List<Rect> boxesA = a.boundingBoxes;
    final List<Rect> boxesB = b.boundingBoxes;
    if (boxesA.isEmpty || boxesB.isEmpty) {
      if (boxesA.isEmpty && boxesB.isEmpty) {
        return _compareByRegistrationOrder(a, b);
      }
      return boxesA.isEmpty ? -1 : 1;
    }
    final Rect rectA = MatrixUtils.transformRect(
      a.getTransformTo(null),
      boxesA.first,
    );
    final Rect rectB = MatrixUtils.transformRect(
      b.getTransformTo(null),
      boxesB.first,
    );
    final int order = compareScreenOrderRects(rectA, rectB);
    if (order != 0) {
      return order;
    }
    return _compareByRegistrationOrder(a, b);
  }

  @override
  SelectionGeometry getSelectionGeometry() {
    if (_pendingSelectAll) {
      final _SafeRenderParagraph? p = _paragraph;
      final Offset endPos = (p != null && p.hasSize)
          ? Offset(p.size.width, p.size.height)
          : Offset.zero;
      return SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        startSelectionPoint: const SelectionPoint(
          localPosition: Offset.zero,
          lineHeight: 0.0,
          handleType: TextSelectionHandleType.left,
        ),
        endSelectionPoint: SelectionPoint(
          localPosition: endPos,
          lineHeight: 0.0,
          handleType: TextSelectionHandleType.right,
        ),
      );
    }
    return super.getSelectionGeometry();
  }

  @override
  void ensureChildUpdated(Selectable selectable) {
    if (!_isSubtreeLayoutReady()) {
      _needsSyncAfterLayout = true;
      return;
    }
    super.ensureChildUpdated(selectable);
  }

  @override
  SelectionResult dispatchSelectionEventToChild(
    Selectable selectable,
    SelectionEvent event,
  ) {
    if (event is! ClearSelectionEvent && !_isSubtreeLayoutReady()) {
      _needsSyncAfterLayout = true;
      if (event is DirectionallyExtendSelectionEvent ||
          event is GranularlyExtendSelectionEvent) {
        return SelectionResult.end;
      }
      return SelectionResult.none;
    }
    return super.dispatchSelectionEventToChild(selectable, event);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (event is ClearSelectionEvent) {
      _pendingSelectAll = false;
      _needsSyncAfterLayout = false;
      return super.dispatchSelectionEvent(event);
    }
    if (!_isSubtreeLayoutReady()) {
      switch (event.type) {
        case SelectionEventType.clear:
          _pendingSelectAll = false;
          _needsSyncAfterLayout = false;
          return super.dispatchSelectionEvent(event);
        case SelectionEventType.selectAll:
          _pendingSelectAll = true;
          if (_paragraph?.isLayoutClean ?? false) {
            _schedulePostFrameFlush();
          }
          layoutDidChange();
          return SelectionResult.none;
        case SelectionEventType.directionallyExtendSelection:
          final DirectionallyExtendSelectionEvent dirEvent =
              event as DirectionallyExtendSelectionEvent;
          return switch (dirEvent.direction) {
            SelectionExtendDirection.previousLine => SelectionResult.previous,
            SelectionExtendDirection.nextLine => SelectionResult.next,
            SelectionExtendDirection.forward ||
            SelectionExtendDirection.backward => SelectionResult.end,
          };
        case SelectionEventType.granularlyExtendSelection:
          return SelectionResult.end;
        case SelectionEventType.startEdgeUpdate:
        case SelectionEventType.endEdgeUpdate:
          final SelectionEdgeUpdateEvent edgeEvent =
              event as SelectionEdgeUpdateEvent;
          _pendingSelectAll = false;
          _needsSyncAfterLayout = true;
          updateLastSelectionEdgeLocation(
            globalSelectionEdgeLocation: edgeEvent.globalPosition,
            forEnd: edgeEvent.type == SelectionEventType.endEdgeUpdate,
          );
          if (_paragraph?.isLayoutClean ?? false) {
            _schedulePostFrameFlush();
          }
          layoutDidChange();
          return SelectionResult.none;
        case SelectionEventType.selectWord:
        case SelectionEventType.selectParagraph:
          _pendingSelectAll = false;
          _needsSyncAfterLayout = true;
          if (_paragraph?.isLayoutClean ?? false) {
            _schedulePostFrameFlush();
          }
          return SelectionResult.none;
      }
    }
    _pendingSelectAll = false;
    _resortIfNeeded();
    return super.dispatchSelectionEvent(event);
  }

  @override
  void didChangeSelectables() {
    if (_isSubtreeLayoutReady()) {
      _resortIfNeeded();
      if (_pendingSelectAll) {
        _pendingSelectAll = false;
        if (selectables.isNotEmpty) {
          super.handleSelectAll(const SelectAllSelectionEvent());
        }
      }
    }
    super.didChangeSelectables();
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    _pendingSelectAll = false;
    _needsSyncAfterLayout = false;
    return super.handleClearSelection(event);
  }

  @override
  SelectionResult handleSelectAll(SelectAllSelectionEvent event) {
    if (!_isSubtreeLayoutReady()) {
      _pendingSelectAll = true;
      if (_paragraph?.isLayoutClean ?? false) {
        _schedulePostFrameFlush();
      }
      layoutDidChange();
      return SelectionResult.none;
    }
    _pendingSelectAll = false;
    if (selectables.isEmpty) {
      return SelectionResult.none;
    }
    _resortIfNeeded();
    return super.handleSelectAll(event);
  }

  @override
  SelectionResult handleSelectWord(SelectWordSelectionEvent event) {
    if (!_isSubtreeLayoutReady() || selectables.isEmpty) {
      return SelectionResult.none;
    }
    _pendingSelectAll = false;
    _resortIfNeeded();
    return super.handleSelectWord(event);
  }

  @override
  SelectionResult handleSelectParagraph(SelectParagraphSelectionEvent event) {
    if (!_isSubtreeLayoutReady() || selectables.isEmpty) {
      return SelectionResult.none;
    }
    _pendingSelectAll = false;
    _resortIfNeeded();
    final SelectionResult result = _handleSelectParagraph(event);
    super.didReceiveSelectionBoundaryEvents();
    return result;
  }

  SelectionResult _handleSelectParagraph(SelectParagraphSelectionEvent event) {
    final _SafeRenderParagraph? p = _paragraph;
    if (p == null || selectables.isEmpty) {
      return SelectionResult.none;
    }
    if (event.absorb) {
      for (int index = 0; index < selectables.length; index += 1) {
        dispatchSelectionEventToChild(selectables[index], event);
      }
      currentSelectionStartIndex = 0;
      currentSelectionEndIndex = selectables.length - 1;
      return SelectionResult.next;
    }

    for (int index = 0; index < selectables.length; index += 1) {
      final bool selectableIsPlaceholder = !p.selectableBelongsToParagraph(
        selectables[index],
      );
      if (selectableIsPlaceholder &&
          selectables[index].boundingBoxes.isNotEmpty) {
        for (final Rect rect in selectables[index].boundingBoxes) {
          final Rect globalRect = MatrixUtils.transformRect(
            selectables[index].getTransformTo(null),
            rect,
          );
          if (globalRect.contains(event.globalPosition)) {
            currentSelectionStartIndex = currentSelectionEndIndex = index;
            return dispatchSelectionEventToChild(selectables[index], event);
          }
        }
      }
    }

    SelectionResult? lastSelectionResult;
    bool foundStart = false;
    int? lastNextIndex;
    for (int index = 0; index < selectables.length; index += 1) {
      if (!p.selectableBelongsToParagraph(selectables[index])) {
        if (foundStart) {
          final SelectionEvent synthesizedEvent = SelectParagraphSelectionEvent(
            globalPosition: event.globalPosition,
            absorb: true,
          );
          final SelectionResult result = dispatchSelectionEventToChild(
            selectables[index],
            synthesizedEvent,
          );
          if (selectables.length - 1 == index) {
            currentSelectionEndIndex = index;
            _flushInactiveSelections();
            return result;
          }
        }
        continue;
      }
      final SelectionGeometry existingGeometry = selectables[index].value;
      lastSelectionResult = dispatchSelectionEventToChild(
        selectables[index],
        event,
      );
      if (index == selectables.length - 1 &&
          lastSelectionResult == SelectionResult.next) {
        if (foundStart) {
          currentSelectionEndIndex = index;
        } else {
          currentSelectionStartIndex = currentSelectionEndIndex = index;
        }
        return SelectionResult.next;
      }
      if (lastSelectionResult == SelectionResult.next) {
        if (selectables[index].value == existingGeometry && !foundStart) {
          lastNextIndex = index;
        }
        if (selectables[index].value != existingGeometry && !foundStart) {
          final List<Rect> boxes = selectables[index].boundingBoxes;
          final List<Rect> selRects = selectables[index].value.selectionRects;
          final bool selectionAtStartOfSelectable =
              boxes.isNotEmpty &&
              selRects.isNotEmpty &&
              boxes[0].overlaps(selRects[0]);
          final int startIndex;
          if (lastNextIndex != null && selectionAtStartOfSelectable) {
            startIndex = lastNextIndex + 1;
          } else {
            startIndex = lastNextIndex == null && selectionAtStartOfSelectable
                ? 0
                : index;
          }
          for (int i = startIndex; i < index; i += 1) {
            final SelectionEvent synthesizedEvent =
                SelectParagraphSelectionEvent(
                  globalPosition: event.globalPosition,
                  absorb: true,
                );
            dispatchSelectionEventToChild(selectables[i], synthesizedEvent);
          }
          currentSelectionStartIndex = startIndex;
          foundStart = true;
        }
        continue;
      }
      if (index == 0 && lastSelectionResult == SelectionResult.previous) {
        return SelectionResult.previous;
      }
      if (selectables[index].value != existingGeometry) {
        if (!foundStart && lastNextIndex == null) {
          currentSelectionStartIndex = 0;
          for (int i = 0; i < index; i += 1) {
            final SelectionEvent synthesizedEvent =
                SelectParagraphSelectionEvent(
                  globalPosition: event.globalPosition,
                  absorb: true,
                );
            dispatchSelectionEventToChild(selectables[i], synthesizedEvent);
          }
        }
        currentSelectionEndIndex = index;
        _flushInactiveSelections();
      }
      return SelectionResult.end;
    }
    return lastSelectionResult ?? SelectionResult.end;
  }

  SelectionResult _adjustSelection(
    SelectionEdgeUpdateEvent event, {
    required bool isEnd,
  }) {
    if (selectables.isEmpty) {
      return SelectionResult.none;
    }
    SelectionResult? finalResult;
    final bool isCurrentEdgeWithinViewport = isEnd
        ? value.endSelectionPoint != null
        : value.startSelectionPoint != null;
    final bool isOppositeEdgeWithinViewport = isEnd
        ? value.startSelectionPoint != null
        : value.endSelectionPoint != null;
    int newIndex = switch ((
      isEnd,
      isCurrentEdgeWithinViewport,
      isOppositeEdgeWithinViewport,
    )) {
      (true, true, true) => currentSelectionEndIndex,
      (true, true, false) => currentSelectionEndIndex,
      (true, false, true) => currentSelectionStartIndex,
      (true, false, false) => 0,
      (false, true, true) => currentSelectionStartIndex,
      (false, true, false) => currentSelectionStartIndex,
      (false, false, true) => currentSelectionEndIndex,
      (false, false, false) => 0,
    }.clamp(0, selectables.length - 1);
    bool? forward;
    late SelectionResult currentSelectableResult;
    while (newIndex < selectables.length &&
        newIndex >= 0 &&
        finalResult == null) {
      currentSelectableResult = dispatchSelectionEventToChild(
        selectables[newIndex],
        event,
      );
      switch (currentSelectableResult) {
        case SelectionResult.end:
        case SelectionResult.pending:
        case SelectionResult.none:
          finalResult = currentSelectableResult;
        case SelectionResult.next:
          if (forward == false) {
            newIndex += 1;
            finalResult = SelectionResult.end;
          } else if (newIndex == selectables.length - 1) {
            finalResult = currentSelectableResult;
          } else {
            forward = true;
            newIndex += 1;
          }
        case SelectionResult.previous:
          if (forward ?? false) {
            newIndex -= 1;
            finalResult = SelectionResult.end;
          } else if (newIndex == 0) {
            finalResult = currentSelectableResult;
          } else {
            forward = false;
            newIndex -= 1;
          }
      }
    }
    if (isEnd) {
      final bool forwardSelection =
          currentSelectionEndIndex >= currentSelectionStartIndex;
      if (forward != null &&
          ((!forwardSelection &&
                  forward &&
                  newIndex >= currentSelectionStartIndex) ||
              (forwardSelection &&
                  !forward &&
                  newIndex <= currentSelectionStartIndex))) {
        currentSelectionStartIndex = currentSelectionEndIndex;
      }
      currentSelectionEndIndex = newIndex;
    } else {
      final bool forwardSelection =
          currentSelectionEndIndex >= currentSelectionStartIndex;
      if (forward != null &&
          ((!forwardSelection &&
                  !forward &&
                  newIndex <= currentSelectionEndIndex) ||
              (forwardSelection &&
                  forward &&
                  newIndex >= currentSelectionEndIndex))) {
        currentSelectionEndIndex = currentSelectionStartIndex;
      }
      currentSelectionStartIndex = newIndex;
    }
    _flushInactiveSelections();
    return finalResult ?? SelectionResult.none;
  }

  SelectedContentRange? _calculateLocalRange(
    List<_SafeSelectionInfo> selections, {
    required bool layoutReady,
  }) {
    if (currentSelectionStartIndex == -1 ||
        currentSelectionEndIndex == -1 ||
        currentSelectionStartIndex >= selectables.length ||
        currentSelectionEndIndex >= selectables.length) {
      return null;
    }
    int startOffset = 0;
    int endOffset = 0;
    bool foundStart = false;
    bool forwardSelection =
        currentSelectionEndIndex >= currentSelectionStartIndex;
    if (currentSelectionEndIndex == currentSelectionStartIndex) {
      final SelectedContentRange? rangeAtSelectableInSelection =
          selectables[currentSelectionStartIndex].getSelection();
      if (rangeAtSelectableInSelection == null) {
        return null;
      }
      forwardSelection =
          rangeAtSelectableInSelection.endOffset >=
          rangeAtSelectableInSelection.startOffset;
    }
    final _SafeRenderParagraph? p = layoutReady ? _paragraph : null;
    for (int index = 0; index < selections.length; index++) {
      final _SafeSelectionInfo selection = selections[index];
      if (selection.range == null) {
        if (foundStart) {
          return SelectedContentRange(
            startOffset: forwardSelection ? startOffset : endOffset,
            endOffset: forwardSelection ? endOffset : startOffset,
          );
        }
        startOffset += selection.contentLength;
        endOffset = startOffset;
        continue;
      }
      final int selectionStartNormalized = math.min(
        selection.range!.startOffset,
        selection.range!.endOffset,
      );
      final int selectionEndNormalized = math.max(
        selection.range!.startOffset,
        selection.range!.endOffset,
      );
      if (!foundStart) {
        final bool shouldConsiderContentStart =
            p != null &&
            index > 0 &&
            p.selectableBelongsToParagraph(selectables[index]) &&
            selectables[index].boundingBoxes.isNotEmpty;
        startOffset +=
            (selectionStartNormalized -
                    (shouldConsiderContentStart
                        ? p
                              .getPositionForOffset(
                                selectables[index]
                                    .boundingBoxes
                                    .first
                                    .centerLeft,
                              )
                              .offset
                        : 0))
                .abs();
        endOffset =
            startOffset +
            (selectionEndNormalized - selectionStartNormalized).abs();
        foundStart = true;
      } else {
        endOffset += (selectionEndNormalized - selectionStartNormalized).abs();
      }
    }
    if (!foundStart) {
      return null;
    }
    return SelectedContentRange(
      startOffset: forwardSelection ? startOffset : endOffset,
      endOffset: forwardSelection ? endOffset : startOffset,
    );
  }

  @override
  SelectedContentRange? getSelection() {
    if (_pendingSelectAll) {
      final int len = contentLength > 0
          ? contentLength
          : (_paragraph?.text
                    .toPlainText(includeSemanticsLabels: false)
                    .length ??
                0);
      return SelectedContentRange(startOffset: 0, endOffset: len);
    }
    if (currentSelectionStartIndex == -1 ||
        currentSelectionEndIndex == -1 ||
        selectables.isEmpty) {
      return null;
    }
    final bool ready = _isSubtreeLayoutReady();
    if (ready) {
      _resortIfNeeded();
    }
    final List<_SafeSelectionInfo> selections = <_SafeSelectionInfo>[
      for (final Selectable selectable in selectables)
        (
          contentLength: selectable.contentLength,
          range: selectable.getSelection(),
        ),
    ];
    return _calculateLocalRange(selections, layoutReady: ready);
  }

  @override
  SelectedContent? getSelectedContent() {
    if (_pendingSelectAll) {
      final String plainText =
          _paragraph?.text.toPlainText(includeSemanticsLabels: false) ?? '';
      return plainText.isEmpty ? null : SelectedContent(plainText: plainText);
    }
    if (_isSubtreeLayoutReady()) {
      _resortIfNeeded();
    }
    return super.getSelectedContent();
  }

  void _flushInactiveSelections() {
    if (currentSelectionStartIndex == -1 && currentSelectionEndIndex == -1) {
      return;
    }
    if (currentSelectionStartIndex == -1 || currentSelectionEndIndex == -1) {
      final int skipIndex = currentSelectionStartIndex == -1
          ? currentSelectionEndIndex
          : currentSelectionStartIndex;
      for (int i = 0; i < selectables.length; i++) {
        if (i == skipIndex) {
          continue;
        }
        dispatchSelectionEventToChild(
          selectables[i],
          const ClearSelectionEvent(),
        );
      }
      return;
    }
    final int skipStart = math.min(
      currentSelectionStartIndex,
      currentSelectionEndIndex,
    );
    final int skipEnd = math.max(
      currentSelectionStartIndex,
      currentSelectionEndIndex,
    );
    for (int index = 0; index < selectables.length; index += 1) {
      if (index >= skipStart && index <= skipEnd) {
        continue;
      }
      dispatchSelectionEventToChild(
        selectables[index],
        const ClearSelectionEvent(),
      );
    }
  }

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    _pendingSelectAll = false;
    if (!_isSubtreeLayoutReady()) {
      _needsSyncAfterLayout = true;
      return SelectionResult.none;
    }
    _resortIfNeeded();
    if (event.granularity != TextGranularity.paragraph) {
      return super.handleSelectionEdgeUpdate(event);
    }
    updateLastSelectionEdgeLocation(
      globalSelectionEdgeLocation: event.globalPosition,
      forEnd: event.type == SelectionEventType.endEdgeUpdate,
    );
    if (event.type == SelectionEventType.endEdgeUpdate) {
      return currentSelectionEndIndex == -1 ||
              currentSelectionEndIndex >= selectables.length
          ? super.handleSelectionEdgeUpdate(event)
          : _adjustSelection(event, isEnd: true);
    }
    return currentSelectionStartIndex == -1 ||
            currentSelectionStartIndex >= selectables.length
        ? super.handleSelectionEdgeUpdate(event)
        : _adjustSelection(event, isEnd: false);
  }
}

/// Fast [Text] subclass bypassing `Text.build`'s per-instance inherited-widget
/// lookups, `MouseRegion`, and `_SelectableTextContainer` wrapper bloat.
///
/// Because this widget extends [Text] and populates [textSpan], widget-test
/// finders such as `find.text(...)` and `tester.widget<Text>(...)` continue to
/// match seamlessly while rendering via either [MarkdownParagraphLeaf] or
/// direct [RichText] with pre-resolved environment values.
final class FastMarkdownText extends Text {
  /// Creates a [FastMarkdownText].
  const FastMarkdownText({
    super.key,
    required InlineSpan span,
    required this.plainText,
    required this.effectiveStyle,
    required this.resolvedTextAlign,
    required this.resolvedTextDirection,
    required this.resolvedTextScaler,
    this.resolvedLocale,
    this.selectionRegistrar,
    super.selectionColor,
    this.selectionMouseCursor,
    this.useLeafRenderBox = true,
    this.topPadding = 0.0,
    this.dividerSpacing = 0.0,
    this.dividerColor,
    this.contentPadding,
    this.backgroundColor,
    this.leftBorderColor,
    this.leftBorderWidth = 0.0,
    this.expandWidth = false,
    this.maxWidth,
  }) : super.rich(
         span,
         style: effectiveStyle,
         textAlign: resolvedTextAlign,
         textDirection: resolvedTextDirection,
         textScaler: resolvedTextScaler,
         locale: resolvedLocale,
       );

  /// Flattened plain-text content matching [textSpan].
  final String plainText;

  /// Merged [TextStyle] including ambient `DefaultTextStyle` and `boldText`.
  final TextStyle effectiveStyle;

  /// Resolved horizontal alignment.
  final TextAlign resolvedTextAlign;

  /// Pre-resolved [TextDirection].
  final TextDirection resolvedTextDirection;

  /// Pre-resolved [TextScaler].
  final TextScaler resolvedTextScaler;

  /// Pre-resolved optional [Locale].
  final Locale? resolvedLocale;

  /// Pre-resolved ancestor [SelectionRegistrar], or `null` when non-selectable.
  final SelectionRegistrar? selectionRegistrar;

  /// Optional hover cursor override when selectable.
  final MouseCursor? selectionMouseCursor;

  /// Whether to render via [MarkdownParagraphLeaf] (`true`) or direct
  /// [RichText] (`false`, used when spans contain tap recognizers).
  final bool useLeafRenderBox;

  /// Optional top padding baked directly into [MarkdownParagraphLeaf].
  final double topPadding;

  /// Gap between text and bottom divider rule when [dividerColor] is non-null.
  final double dividerSpacing;

  /// Optional bottom 1px hairline color (for H1/H2 headings).
  final Color? dividerColor;

  /// Optional padding baked directly around the text (e.g. callouts/blockquotes).
  final EdgeInsets? contentPadding;

  /// Optional background fill painted behind [contentPadding] and text.
  final Color? backgroundColor;

  /// Optional left accent bar color painted inside the left edge.
  final Color? leftBorderColor;

  /// Width of the left accent bar when [leftBorderColor] is set.
  final double leftBorderWidth;

  /// Whether to stretch width to `constraints.maxWidth` when finite.
  final bool expandWidth;

  /// Optional maximum outer width constraint baked into [MarkdownParagraphLeaf].
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final InlineSpan activeSpan = textSpan!;
    if (!useLeafRenderBox) {
      final SelectionRegistrar? activeRegistrar = selectionRegistrar != null
          ? SelectionContainer.maybeOf(context)
          : null;
      if (activeRegistrar == null) {
        return _SafeRichText(
          text: activeSpan,
          textAlign: resolvedTextAlign,
          textDirection: resolvedTextDirection,
          textScaler: resolvedTextScaler,
          locale: resolvedLocale,
          selectionRegistrar: null,
          selectionColor: selectionColor,
        );
      }
      final TextSpan selectableSpan = activeSpan is TextSpan
          ? activeSpan
          : TextSpan(children: <InlineSpan>[activeSpan]);
      return MouseRegion(
        cursor:
            selectionMouseCursor ??
            DefaultSelectionStyle.of(context).mouseCursor ??
            SystemMouseCursors.text,
        child: _SafeSelectableTextContainer(
          textAlign: resolvedTextAlign,
          textDirection: resolvedTextDirection,
          locale: resolvedLocale,
          softWrap: true,
          overflow: TextOverflow.clip,
          textScaler: resolvedTextScaler,
          maxLines: null,
          strutStyle: null,
          textWidthBasis: TextWidthBasis.parent,
          textHeightBehavior: null,
          selectionColor:
              selectionColor ??
              DefaultSelectionStyle.of(context).selectionColor ??
              DefaultSelectionStyle.defaultColor,
          text: selectableSpan,
        ),
      );
    }
    return MarkdownParagraphLeaf(
      text: activeSpan,
      plainText: plainText,
      textAlign: resolvedTextAlign,
      textDirection: resolvedTextDirection,
      textScaler: resolvedTextScaler,
      locale: resolvedLocale,
      registrar: selectionRegistrar,
      selectionColor: selectionColor,
      selectionMouseCursor: selectionMouseCursor,
      topPadding: topPadding,
      dividerSpacing: dividerSpacing,
      dividerColor: dividerColor,
      contentPadding: contentPadding,
      backgroundColor: backgroundColor,
      leftBorderColor: leftBorderColor,
      leftBorderWidth: leftBorderWidth,
      expandWidth: expandWidth,
      maxWidth: maxWidth,
    );
  }
}

/// Lean [LeafRenderObjectWidget] rendering a span tree without child widgets,
/// updating its underlying [TextPainter] in place across streaming tokens.
final class MarkdownParagraphLeaf extends LeafRenderObjectWidget {
  /// Creates a [MarkdownParagraphLeaf].
  const MarkdownParagraphLeaf({
    super.key,
    required this.text,
    required this.plainText,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    this.locale,
    this.registrar,
    this.selectionColor,
    this.selectionMouseCursor,
    this.topPadding = 0.0,
    this.dividerSpacing = 0.0,
    this.dividerColor,
    this.contentPadding,
    this.backgroundColor,
    this.leftBorderColor,
    this.leftBorderWidth = 0.0,
    this.expandWidth = false,
    this.maxWidth,
  });

  /// Span tree painted by this leaf.
  final InlineSpan text;

  /// Plain text corresponding to [text].
  final String plainText;

  /// Horizontal text alignment.
  final TextAlign textAlign;

  /// Text direction.
  final TextDirection textDirection;

  /// Text scale factor.
  final TextScaler textScaler;

  /// Optional locale.
  final Locale? locale;

  /// Selection registrar when inside a selection container.
  final SelectionRegistrar? registrar;

  /// Selection highlight fill color.
  final Color? selectionColor;

  /// Optional hover cursor override when selectable.
  final MouseCursor? selectionMouseCursor;

  /// Top padding baked into layout/paint.
  final double topPadding;

  /// Gap between text bottom and bottom rule when [dividerColor] is set.
  final double dividerSpacing;

  /// Optional 1px bottom rule color.
  final Color? dividerColor;

  /// Optional padding baked around the text.
  final EdgeInsets? contentPadding;

  /// Optional background color fill.
  final Color? backgroundColor;

  /// Optional left accent bar color.
  final Color? leftBorderColor;

  /// Width of left accent bar when [leftBorderColor] is set.
  final double leftBorderWidth;

  /// Whether to stretch width to finite `constraints.maxWidth`.
  final bool expandWidth;

  /// Optional maximum outer width constraint.
  final double? maxWidth;

  @override
  RenderMarkdownParagraph createRenderObject(BuildContext context) {
    return RenderMarkdownParagraph(
      text: text,
      plainText: plainText,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      registrar: registrar,
      selectionColor: selectionColor,
      selectionMouseCursor: selectionMouseCursor,
      topPadding: topPadding,
      dividerSpacing: dividerSpacing,
      dividerColor: dividerColor,
      contentPadding: contentPadding,
      backgroundColor: backgroundColor,
      leftBorderColor: leftBorderColor,
      leftBorderWidth: leftBorderWidth,
      expandWidth: expandWidth,
      maxWidth: maxWidth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMarkdownParagraph renderObject,
  ) {
    renderObject
      ..updateContent(
        text: text,
        plainText: plainText,
        textAlign: textAlign,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        topPadding: topPadding,
        dividerSpacing: dividerSpacing,
        dividerColor: dividerColor,
        contentPadding: contentPadding,
        backgroundColor: backgroundColor,
        leftBorderColor: leftBorderColor,
        leftBorderWidth: leftBorderWidth,
        expandWidth: expandWidth,
        maxWidth: maxWidth,
      )
      ..selectionColor = selectionColor
      ..selectionMouseCursor = selectionMouseCursor
      ..registrar = registrar;
  }
}

/// Custom leaf [RenderBox] backed by a reusable [TextPainter] and persistent
/// [Selectable] integration.
final class RenderMarkdownParagraph extends RenderBox
    implements MouseTrackerAnnotation {
  /// Creates a [RenderMarkdownParagraph].
  RenderMarkdownParagraph({
    required InlineSpan text,
    required String plainText,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required TextScaler textScaler,
    Locale? locale,
    SelectionRegistrar? registrar,
    Color? selectionColor,
    MouseCursor? selectionMouseCursor,
    double topPadding = 0.0,
    double dividerSpacing = 0.0,
    Color? dividerColor,
    EdgeInsets? contentPadding,
    Color? backgroundColor,
    Color? leftBorderColor,
    double leftBorderWidth = 0.0,
    bool expandWidth = false,
    double? maxWidth,
    // ignore: prefer_initializing_formals
  }) : _plainText = plainText,
       _registrar = registrar,
       // ignore: prefer_initializing_formals
       _selectionColor = selectionColor,
       // ignore: prefer_initializing_formals
       _selectionMouseCursor = selectionMouseCursor,
       // ignore: prefer_initializing_formals
       _topPadding = topPadding,
       // ignore: prefer_initializing_formals
       _dividerSpacing = dividerSpacing,
       // ignore: prefer_initializing_formals
       _dividerColor = dividerColor,
       // ignore: prefer_initializing_formals
       _contentPadding = contentPadding,
       // ignore: prefer_initializing_formals
       _backgroundColor = backgroundColor,
       // ignore: prefer_initializing_formals
       _leftBorderColor = leftBorderColor,
       // ignore: prefer_initializing_formals
       _leftBorderWidth = leftBorderWidth,
       // ignore: prefer_initializing_formals
       _expandWidth = expandWidth,
       // ignore: prefer_initializing_formals
       _maxWidth = maxWidth,
       _textPainter = TextPainter(
         text: text,
         textAlign: textAlign,
         textDirection: textDirection,
         textScaler: textScaler,
         locale: locale,
       ) {
    if (registrar != null) {
      _selectable = _MarkdownTextSelectable(this);
    }
  }

  final TextPainter _textPainter;
  String _plainText;
  SelectionRegistrar? _registrar;
  Color? _selectionColor;
  MouseCursor? _selectionMouseCursor;
  double _topPadding;
  double _dividerSpacing;
  Color? _dividerColor;
  EdgeInsets? _contentPadding;
  Color? _backgroundColor;
  Color? _leftBorderColor;
  double _leftBorderWidth;
  bool _expandWidth;
  double? _maxWidth;
  _MarkdownTextSelectable? _selectable;

  double? _laidOutMinWidth;
  double? _laidOutMaxWidth;
  bool _needsLayoutFlag = true;

  /// Whether this paragraph is attached, sized, and has clean layout state in
  /// debug, profile, and release builds.
  bool get isLayoutClean =>
      attached && hasSize && !_needsLayoutFlag && !debugNeedsLayout;

  /// Effective text direction.
  TextDirection get textDirection => _textPainter.textDirection!;

  @override
  void markNeedsLayout() {
    _needsLayoutFlag = true;
    super.markNeedsLayout();
  }

  /// Updates content and styling in place, avoiding `SelectionRegistrar`
  /// remove/add churn when text changes mid-stream.
  void updateContent({
    required InlineSpan text,
    required String plainText,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
    required double topPadding,
    required double dividerSpacing,
    required Color? dividerColor,
    required EdgeInsets? contentPadding,
    required Color? backgroundColor,
    required Color? leftBorderColor,
    required double leftBorderWidth,
    required bool expandWidth,
    required double? maxWidth,
  }) {
    bool needsLayout = false;
    bool needsPaint = false;
    bool semanticsChanged = false;

    final InlineSpan? previousSpan = _textPainter.text;
    if (!identical(previousSpan, text)) {
      final RenderComparison comparison = previousSpan == null
          ? RenderComparison.layout
          : previousSpan.compareTo(text);
      switch (comparison) {
        case RenderComparison.identical:
          break;
        case RenderComparison.metadata:
          _textPainter.text = text;
          semanticsChanged = true;
        case RenderComparison.paint:
          _textPainter.text = text;
          needsPaint = true;
          semanticsChanged = true;
        case RenderComparison.layout:
          _textPainter.text = text;
          needsLayout = true;
          semanticsChanged = true;
      }
    }

    if (_plainText != plainText) {
      _plainText = plainText;
      semanticsChanged = true;
    }

    if (_textPainter.textAlign != textAlign) {
      _textPainter.textAlign = textAlign;
      needsLayout = true;
    }
    if (_textPainter.textDirection != textDirection) {
      _textPainter.textDirection = textDirection;
      needsLayout = true;
      semanticsChanged = true;
    }
    if (_textPainter.textScaler != textScaler) {
      _textPainter.textScaler = textScaler;
      needsLayout = true;
    }
    if (_textPainter.locale != locale) {
      _textPainter.locale = locale;
      needsLayout = true;
    }
    if (_topPadding != topPadding) {
      _topPadding = topPadding;
      needsLayout = true;
    }
    if (_dividerSpacing != dividerSpacing) {
      _dividerSpacing = dividerSpacing;
      needsLayout = true;
    }
    if (_dividerColor != dividerColor) {
      final bool hadRule = _dividerColor != null;
      final bool hasRule = dividerColor != null;
      _dividerColor = dividerColor;
      if (hadRule != hasRule) {
        needsLayout = true;
      } else {
        needsPaint = true;
      }
    }
    if (_contentPadding != contentPadding) {
      _contentPadding = contentPadding;
      needsLayout = true;
    }
    if (_backgroundColor != backgroundColor) {
      _backgroundColor = backgroundColor;
      needsPaint = true;
    }
    if (_leftBorderColor != leftBorderColor) {
      _leftBorderColor = leftBorderColor;
      needsPaint = true;
    }
    if (_leftBorderWidth != leftBorderWidth) {
      _leftBorderWidth = leftBorderWidth;
      needsPaint = true;
    }
    if (_expandWidth != expandWidth) {
      _expandWidth = expandWidth;
      needsLayout = true;
    }
    if (_maxWidth != maxWidth) {
      _maxWidth = maxWidth;
      needsLayout = true;
    }

    if (needsLayout) {
      _laidOutMinWidth = null;
      _laidOutMaxWidth = null;
      markNeedsLayout();
      _selectable?.didUpdateContent();
    } else if (semanticsChanged) {
      _selectable?.didUpdateContent();
    }
    if (!needsLayout && needsPaint) {
      markNeedsPaint();
    }
    if (semanticsChanged) {
      markNeedsSemanticsUpdate();
    }
  }

  /// Selection highlight color.
  Color? get selectionColor => _selectionColor;
  set selectionColor(Color? value) {
    if (_selectionColor == value) {
      return;
    }
    _selectionColor = value;
    if (_selectable?.hasSelection ?? false) {
      markNeedsPaint();
    }
  }

  /// Optional hover cursor override when selectable.
  MouseCursor? get selectionMouseCursor => _selectionMouseCursor;
  set selectionMouseCursor(MouseCursor? value) {
    if (_selectionMouseCursor == value) {
      return;
    }
    _selectionMouseCursor = value;
    // Trigger a MouseTracker device update if the cursor changes while hovered.
    markNeedsPaint();
  }

  /// Ancestor selection registrar.
  SelectionRegistrar? get registrar => _registrar;
  set registrar(SelectionRegistrar? value) {
    if (identical(_registrar, value)) {
      return;
    }
    _registrar = value;
    if (value == null) {
      _selectable?.registrar = null;
      _selectable?.dispose();
      _selectable = null;
      markNeedsCompositingBitsUpdate();
    } else {
      final _MarkdownTextSelectable selectable = _selectable ??=
          _MarkdownTextSelectable(this);
      if (attached) {
        selectable.registrar = value;
      }
    }
  }

  @override
  MouseCursor get cursor => _registrar != null
      ? (_selectionMouseCursor ?? SystemMouseCursors.text)
      : MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  @override
  bool get validForMouseTracker => attached;

  @override
  bool get alwaysNeedsCompositing => _selectable?.hasHandleLayers ?? false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    PaintingBinding.instance.systemFonts.addListener(_handleSystemFontsChange);
    if (_registrar != null) {
      (_selectable ??= _MarkdownTextSelectable(this)).registrar = _registrar;
    }
  }

  @override
  void detach() {
    PaintingBinding.instance.systemFonts.removeListener(
      _handleSystemFontsChange,
    );
    _selectable?.registrar = null;
    _selectable?.clearHandleLayers();
    super.detach();
  }

  @override
  void dispose() {
    _selectable?.dispose();
    _selectable = null;
    _textPainter.dispose();
    super.dispose();
  }

  void _handleSystemFontsChange() {
    _needsLayoutFlag = true;
    _textPainter.markNeedsLayout();
    _laidOutMinWidth = null;
    _laidOutMaxWidth = null;
    markNeedsLayout();
  }

  double get _padLeft => _contentPadding?.left ?? 0.0;
  double get _padTop => _topPadding + (_contentPadding?.top ?? 0.0);
  double get _horizontalPad => _contentPadding?.horizontal ?? 0.0;
  double get _extraHeight =>
      _padTop +
      (_contentPadding?.bottom ?? 0.0) +
      (_dividerColor != null ? _dividerSpacing + 1.0 : 0.0);

  void _layoutFor(double minWidth, double maxWidth) {
    final double hPad = _horizontalPad;
    final double? cap = _maxWidth;
    final double effMinW = cap != null ? math.min(minWidth, cap) : minWidth;
    final double effMaxW = cap != null ? math.min(maxWidth, cap) : maxWidth;
    final double textMinW = math.max(0.0, effMinW - hPad);
    final double textMaxW = effMaxW.isFinite
        ? math.max(0.0, effMaxW - hPad)
        : double.infinity;
    if (_laidOutMinWidth == textMinW && _laidOutMaxWidth == textMaxW) {
      return;
    }
    _textPainter.layout(minWidth: textMinW, maxWidth: textMaxW);
    _laidOutMinWidth = textMinW;
    _laidOutMaxWidth = textMaxW;
  }

  void _restoreLayoutIfSized() {
    if (hasSize) {
      _layoutFor(constraints.minWidth, constraints.maxWidth);
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _layoutFor(0.0, double.infinity);
    final double w = _textPainter.minIntrinsicWidth + _horizontalPad;
    _restoreLayoutIfSized();
    return _maxWidth != null ? math.min(w, _maxWidth!) : w;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _layoutFor(0.0, double.infinity);
    final double w = _textPainter.maxIntrinsicWidth + _horizontalPad;
    _restoreLayoutIfSized();
    return _maxWidth != null ? math.min(w, _maxWidth!) : w;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _layoutFor(width, width);
    final double h = _textPainter.height + _extraHeight;
    _restoreLayoutIfSized();
    return h;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return computeMinIntrinsicHeight(width);
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    assert(!debugNeedsLayout);
    _layoutFor(constraints.minWidth, constraints.maxWidth);
    return _padTop +
        _textPainter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    _layoutFor(constraints.minWidth, constraints.maxWidth);
    final double value =
        _padTop +
        _textPainter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    _restoreLayoutIfSized();
    return value;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    _layoutFor(constraints.minWidth, constraints.maxWidth);
    final double? cap = _maxWidth;
    final double cappedMaxW = cap != null
        ? math.min(constraints.maxWidth, cap)
        : constraints.maxWidth;
    final bool fillWidth =
        (_expandWidth || _dividerColor != null) && cappedMaxW.isFinite;
    final double rawW = fillWidth
        ? cappedMaxW
        : math.min(cap ?? double.infinity, _textPainter.width + _horizontalPad);
    final double width = constraints.constrainWidth(rawW);
    final Size dry = Size(
      width,
      constraints.constrainHeight(_textPainter.height + _extraHeight),
    );
    _restoreLayoutIfSized();
    return dry;
  }

  @override
  void performLayout() {
    _layoutFor(constraints.minWidth, constraints.maxWidth);
    final double? cap = _maxWidth;
    final double cappedMaxW = cap != null
        ? math.min(constraints.maxWidth, cap)
        : constraints.maxWidth;
    final bool fillWidth =
        (_expandWidth || _dividerColor != null) && cappedMaxW.isFinite;
    final double rawW = fillWidth
        ? cappedMaxW
        : math.min(cap ?? double.infinity, _textPainter.width + _horizontalPad);
    final double width = constraints.constrainWidth(rawW);
    size = Size(
      width,
      constraints.constrainHeight(_textPainter.height + _extraHeight),
    );
    _needsLayoutFlag = false;
    _selectable?.didChangeLayout();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..attributedLabel = AttributedString(_plainText)
      ..textDirection = textDirection;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _layoutFor(constraints.minWidth, constraints.maxWidth);
    final Canvas canvas = context.canvas;
    final Color? bgColor = _backgroundColor;
    if (bgColor != null) {
      canvas.drawRect(offset & size, Paint()..color = bgColor);
    }
    final Color? barColor = _leftBorderColor;
    if (barColor != null && _leftBorderWidth > 0.0) {
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, _leftBorderWidth, size.height),
        Paint()..color = barColor,
      );
    }

    final double padLeft = _padLeft;
    final double padTop = _padTop;
    final Offset textOffset = (padLeft == 0.0 && padTop == 0.0)
        ? offset
        : Offset(offset.dx + padLeft, offset.dy + padTop);

    final _MarkdownTextSelectable? selectable = _selectable;
    if (selectable != null && selectable.hasSelection) {
      final Paint highlightPaint = Paint()
        ..color = _selectionColor ?? const Color(0x6633B5E5);
      for (final ui.TextBox box in selectable.selectionBoxes) {
        canvas.drawRect(box.toRect().shift(textOffset), highlightPaint);
      }
    }

    _textPainter.paint(canvas, textOffset);

    final Color? ruleColor = _dividerColor;
    if (ruleColor != null) {
      final Paint rulePaint = Paint()..color = ruleColor;
      canvas.drawRect(
        Rect.fromLTWH(
          offset.dx,
          offset.dy + size.height - 1.0,
          size.width,
          1.0,
        ),
        rulePaint,
      );
    }

    selectable?.pushLeaderLayers(context, offset);
  }
}

final class _MarkdownTextSelectable extends ChangeNotifier
    with Selectable, SelectionRegistrant
    implements MarkdownLayoutAwareSelectable {
  _MarkdownTextSelectable(this._box)
    : _geometry = SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: _box._plainText.isNotEmpty,
      );

  final RenderMarkdownParagraph _box;

  int? _start;
  int? _end;
  LayerLink? _startHandleLink;
  LayerLink? _endHandleLink;
  final LayerHandle<LeaderLayer> _startHandleLayer = LayerHandle<LeaderLayer>();
  final LayerHandle<LeaderLayer> _endHandleLayer = LayerHandle<LeaderLayer>();
  SelectionGeometry _geometry;
  bool _geometryNotifyScheduled = false;
  bool _disposed = false;

  bool get hasSelection => _start != null && _end != null;

  bool get hasHandleLayers =>
      (_startHandleLink != null && _geometry.startSelectionPoint != null) ||
      (_endHandleLink != null && _geometry.endSelectionPoint != null);

  @override
  bool get isLayoutReady => _box.isLayoutClean;

  @override
  SelectionGeometry get value => _geometry;

  @override
  int get contentLength => _box._plainText.length;

  @override
  Size get size => _box.hasSize ? _box.size : Size.zero;

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) =>
      _box.attached ? _box.getTransformTo(ancestor) : Matrix4.identity();

  @override
  List<Rect> get boundingBoxes =>
      _box.hasSize ? <Rect>[_box.paintBounds] : const <Rect>[Rect.zero];

  List<ui.TextBox> get selectionBoxes {
    if (!hasSelection || !_box.hasSize) {
      return const <ui.TextBox>[];
    }
    if (!_box.isLayoutClean) {
      _box._layoutFor(_box.constraints.minWidth, _box.constraints.maxWidth);
    }
    final int len = _box._plainText.length;
    final int a = _start!.clamp(0, len);
    final int b = _end!.clamp(0, len);
    if (a == b) {
      return const <ui.TextBox>[];
    }
    return _box._textPainter.getBoxesForSelection(
      TextSelection(baseOffset: math.min(a, b), extentOffset: math.max(a, b)),
    );
  }

  void clearHandleLayers() {
    _startHandleLink = null;
    _endHandleLink = null;
    _startHandleLayer.layer = null;
    _endHandleLayer.layer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    clearHandleLayers();
    super.dispose();
  }

  void _notifyGeometryChanged() {
    if (_disposed) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_geometryNotifyScheduled) {
        return;
      }
      _geometryNotifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        _geometryNotifyScheduled = false;
        if (!_disposed && _box.attached) {
          notifyListeners();
        }
      });
      return;
    }
    notifyListeners();
  }

  void didUpdateContent() {
    final int len = _box._plainText.length;
    if (!hasSelection) {
      final SelectionGeometry next = SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: len > 0,
      );
      if (_geometry != next) {
        _geometry = next;
        _notifyGeometryChanged();
      }
      return;
    }
    _start = _start!.clamp(0, len);
    _end = _end!.clamp(0, len);
    _updateGeometry();
  }

  void didChangeLayout() {
    if (hasSelection) {
      _updateGeometry();
    }
  }

  void _updateGeometry() {
    final bool hadHandles = hasHandleLayers;
    final SelectionGeometry next = _computeGeometry();
    if (_geometry != next) {
      _geometry = next;
      if (hadHandles != hasHandleLayers) {
        _box.markNeedsCompositingBitsUpdate();
      }
      _notifyGeometryChanged();
    }
  }

  SelectionGeometry _computeGeometry() {
    final String text = _box._plainText;
    final bool hasContent = text.isNotEmpty;
    if (!hasSelection) {
      return SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: hasContent,
      );
    }
    final int len = text.length;
    final int start = _start!.clamp(0, len);
    final int end = _end!.clamp(0, len);
    if (!_box.hasSize || !_box.attached) {
      return SelectionGeometry(
        status: text.isEmpty
            ? SelectionStatus.collapsed
            : SelectionStatus.uncollapsed,
        hasContent: hasContent,
        startSelectionPoint: const SelectionPoint(
          localPosition: Offset.zero,
          lineHeight: 0.0,
          handleType: TextSelectionHandleType.left,
        ),
        endSelectionPoint: const SelectionPoint(
          localPosition: Offset.zero,
          lineHeight: 0.0,
          handleType: TextSelectionHandleType.right,
        ),
      );
    }

    _box._layoutFor(_box.constraints.minWidth, _box.constraints.maxWidth);
    final TextPainter tp = _box._textPainter;
    final double lineHeight = tp.preferredLineHeight;
    final double padLeft = _box._padLeft;
    final double padTop = _box._padTop;
    final Offset caretOffset = Offset(padLeft, lineHeight + padTop);
    final Offset startCaret =
        tp.getOffsetForCaret(TextPosition(offset: start), Rect.zero) +
        caretOffset;
    final Offset endCaret =
        tp.getOffsetForCaret(TextPosition(offset: end), Rect.zero) +
        caretOffset;
    final bool isReversed = start > end;
    final bool flipHandles =
        isReversed != (_box.textDirection == TextDirection.rtl);
    final bool collapsed = start == end;
    final (
      TextSelectionHandleType startType,
      TextSelectionHandleType endType,
    ) = switch ((collapsed, flipHandles)) {
      (true, _) => (
        TextSelectionHandleType.collapsed,
        TextSelectionHandleType.collapsed,
      ),
      (false, true) => (
        TextSelectionHandleType.right,
        TextSelectionHandleType.left,
      ),
      (false, false) => (
        TextSelectionHandleType.left,
        TextSelectionHandleType.right,
      ),
    };
    final List<Rect> rects = <Rect>[
      if (!collapsed)
        for (final ui.TextBox box in tp.getBoxesForSelection(
          TextSelection(
            baseOffset: math.min(start, end),
            extentOffset: math.max(start, end),
          ),
        ))
          box.toRect().shift(Offset(padLeft, padTop)),
    ];
    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: startCaret,
        lineHeight: lineHeight,
        handleType: startType,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: endCaret,
        lineHeight: lineHeight,
        handleType: endType,
      ),
      selectionRects: rects,
      status: collapsed
          ? SelectionStatus.collapsed
          : SelectionStatus.uncollapsed,
      hasContent: hasContent,
    );
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (identical(_startHandleLink, startHandle) &&
        identical(_endHandleLink, endHandle)) {
      return;
    }
    final bool hadHandles = hasHandleLayers;
    _startHandleLink = startHandle;
    _endHandleLink = endHandle;
    if (hadHandles != hasHandleLayers) {
      _box.markNeedsCompositingBitsUpdate();
    }
    _box.markNeedsPaint();
  }

  void pushLeaderLayers(PaintingContext context, Offset offset) {
    final LayerLink? startLink = _startHandleLink;
    final SelectionPoint? startPt = _geometry.startSelectionPoint;
    if (startLink != null && startPt != null) {
      final LeaderLayer layer = _startHandleLayer.layer ??= LeaderLayer(
        link: startLink,
        offset: offset + startPt.localPosition,
      );
      layer
        ..link = startLink
        ..offset = offset + startPt.localPosition;
      context.pushLayer(layer, _paintNothing, Offset.zero);
    } else {
      _startHandleLayer.layer = null;
    }

    final LayerLink? endLink = _endHandleLink;
    final SelectionPoint? endPt = _geometry.endSelectionPoint;
    if (endLink != null && endPt != null) {
      final LeaderLayer layer = _endHandleLayer.layer ??= LeaderLayer(
        link: endLink,
        offset: offset + endPt.localPosition,
      );
      layer
        ..link = endLink
        ..offset = offset + endPt.localPosition;
      context.pushLayer(layer, _paintNothing, Offset.zero);
    } else {
      _endHandleLayer.layer = null;
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    if (!hasSelection) {
      return null;
    }
    final String text = _box._plainText;
    final int a = math.min(_start!, _end!).clamp(0, text.length);
    final int b = math.max(_start!, _end!).clamp(0, text.length);
    return SelectedContent(plainText: text.substring(a, b));
  }

  @override
  SelectedContentRange? getSelection() {
    if (!hasSelection) {
      return null;
    }
    return SelectedContentRange(startOffset: _start!, endOffset: _end!);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final int? prevStart = _start;
    final int? prevEnd = _end;
    final int len = _box._plainText.length;
    late final SelectionResult result;

    if (event is SelectAllSelectionEvent) {
      _start = 0;
      _end = len;
      result = SelectionResult.none;
    } else if (event is ClearSelectionEvent) {
      _start = null;
      _end = null;
      result = SelectionResult.none;
    } else if (!_box.hasSize || !_box.attached) {
      switch (event.type) {
        case SelectionEventType.selectAll:
        case SelectionEventType.clear:
        case SelectionEventType.selectWord:
        case SelectionEventType.startEdgeUpdate:
        case SelectionEventType.endEdgeUpdate:
          result = SelectionResult.none;
        case SelectionEventType.selectParagraph:
          final SelectParagraphSelectionEvent paraEvent =
              event as SelectParagraphSelectionEvent;
          result = paraEvent.absorb
              ? SelectionResult.next
              : SelectionResult.none;
        case SelectionEventType.granularlyExtendSelection:
          result = SelectionResult.end;
        case SelectionEventType.directionallyExtendSelection:
          final DirectionallyExtendSelectionEvent ext =
              event as DirectionallyExtendSelectionEvent;
          result = switch (ext.direction) {
            SelectionExtendDirection.previousLine => SelectionResult.previous,
            SelectionExtendDirection.nextLine => SelectionResult.next,
            SelectionExtendDirection.forward ||
            SelectionExtendDirection.backward => SelectionResult.end,
          };
      }
    } else {
      if (!_box.isLayoutClean) {
        _box._layoutFor(_box.constraints.minWidth, _box.constraints.maxWidth);
      }
      switch (event.type) {
        case SelectionEventType.selectAll:
          _start = 0;
          _end = len;
          result = SelectionResult.none;
        case SelectionEventType.clear:
          _start = null;
          _end = null;
          result = SelectionResult.none;
        case SelectionEventType.selectWord:
          final SelectWordSelectionEvent wordEvent =
              event as SelectWordSelectionEvent;
          final Offset local =
              _box.globalToLocal(wordEvent.globalPosition) -
              Offset(_box._padLeft, _box._padTop);
          final TextPosition pos = _box._textPainter.getPositionForOffset(
            local,
          );
          if (_start != null && _end != null && _start != _end) {
            final int selStart = math.min(_start!, _end!);
            final int selEnd = math.max(_start!, _end!);
            final bool withinSelection =
                (pos.offset > selStart && pos.offset < selEnd) ||
                (pos.offset == selStart &&
                    pos.affinity == TextAffinity.downstream) ||
                (pos.offset == selEnd && pos.affinity == TextAffinity.upstream);
            if (withinSelection) {
              result = SelectionResult.end;
              break;
            }
          }
          final TextRange word = _box._textPainter.getWordBoundary(pos);
          _start = word.start;
          _end = word.end;
          result = SelectionResult.end;
        case SelectionEventType.selectParagraph:
          final SelectParagraphSelectionEvent paraEvent =
              event as SelectParagraphSelectionEvent;
          _start = 0;
          _end = len;
          result = paraEvent.absorb
              ? SelectionResult.next
              : SelectionResult.end;
        case SelectionEventType.startEdgeUpdate:
        case SelectionEventType.endEdgeUpdate:
          final SelectionEdgeUpdateEvent edgeEvent =
              event as SelectionEdgeUpdateEvent;
          final bool isEnd = edgeEvent.type == SelectionEventType.endEdgeUpdate;
          final Offset local = _box.globalToLocal(edgeEvent.globalPosition);
          final SelectionResult edgeResult =
              SelectionUtils.getResultBasedOnRect(_box.paintBounds, local);
          final int targetOffset;
          switch (edgeResult) {
            case SelectionResult.previous:
              targetOffset = 0;
            case SelectionResult.next:
              targetOffset = len;
            case SelectionResult.end:
            case SelectionResult.pending:
            case SelectionResult.none:
              final Offset adjusted =
                  SelectionUtils.adjustDragOffset(
                    _box.paintBounds,
                    local,
                    direction: _box.textDirection,
                  ) -
                  Offset(_box._padLeft, _box._padTop);
              final TextPosition pos = _box._textPainter.getPositionForOffset(
                adjusted,
              );
              switch (edgeEvent.granularity) {
                case TextGranularity.word:
                  final TextRange word = _box._textPainter.getWordBoundary(pos);
                  final int? other = isEnd ? _start : _end;
                  if (other != null && pos.offset < other) {
                    targetOffset = word.start;
                  } else if (other != null && pos.offset > other) {
                    targetOffset = word.end;
                  } else {
                    targetOffset =
                        (pos.offset - word.start) <= (word.end - pos.offset)
                        ? word.start
                        : word.end;
                  }
                case TextGranularity.paragraph:
                  final int? other = isEnd ? _start : _end;
                  if (other != null && pos.offset < other) {
                    targetOffset = 0;
                  } else {
                    targetOffset = len;
                  }
                case TextGranularity.character:
                case TextGranularity.line:
                case TextGranularity.document:
                  targetOffset = pos.offset.clamp(0, len);
              }
          }
          if (isEnd) {
            _end = targetOffset;
            _start ??= targetOffset;
          } else {
            _start = targetOffset;
            _end ??= targetOffset;
          }
          result = edgeResult;
        case SelectionEventType.granularlyExtendSelection:
          final GranularlyExtendSelectionEvent ext =
              event as GranularlyExtendSelectionEvent;
          result = _handleGranularlyExtend(ext);
        case SelectionEventType.directionallyExtendSelection:
          final DirectionallyExtendSelectionEvent ext =
              event as DirectionallyExtendSelectionEvent;
          result = _handleDirectionallyExtend(ext);
      }
    }

    if (prevStart != _start || prevEnd != _end) {
      _box.markNeedsPaint();
      _updateGeometry();
    }
    return result;
  }

  SelectionResult _handleGranularlyExtend(
    GranularlyExtendSelectionEvent event,
  ) {
    final int len = _box._plainText.length;
    if (len == 0) {
      _setEdge(event.isEnd, 0);
      return event.forward ? SelectionResult.next : SelectionResult.previous;
    }
    final int initialOffset = event.forward ? 0 : len;
    _start ??= initialOffset;
    _end ??= initialOffset;
    final int current = (event.isEnd ? _end! : _start!).clamp(0, len);
    int next = current;
    switch (event.granularity) {
      case TextGranularity.character:
        next = event.forward ? current + 1 : current - 1;
      case TextGranularity.word:
        if (event.forward) {
          final TextRange w = _box._textPainter.getWordBoundary(
            TextPosition(offset: current),
          );
          next = w.end > current ? w.end : current + 1;
        } else {
          final int probe = math.max(0, current - 1);
          final TextRange w = _box._textPainter.getWordBoundary(
            TextPosition(offset: probe),
          );
          next = w.start < current ? w.start : current - 1;
        }
      case TextGranularity.line:
      case TextGranularity.paragraph:
        if (event.forward && current == len) {
          return SelectionResult.next;
        }
        if (!event.forward && current == 0) {
          return SelectionResult.previous;
        }
        next = event.forward ? len : 0;
      case TextGranularity.document:
        _setEdge(event.isEnd, event.forward ? len : 0);
        return event.forward ? SelectionResult.next : SelectionResult.previous;
    }

    if (next < 0) {
      _setEdge(event.isEnd, 0);
      return SelectionResult.previous;
    }
    if (next > len) {
      _setEdge(event.isEnd, len);
      return SelectionResult.next;
    }
    _setEdge(event.isEnd, next);
    return SelectionResult.end;
  }

  SelectionResult _handleDirectionallyExtend(
    DirectionallyExtendSelectionEvent event,
  ) {
    final int len = _box._plainText.length;
    if (len == 0) {
      _setEdge(event.isEnd, 0);
      return switch (event.direction) {
        SelectionExtendDirection.previousLine => SelectionResult.previous,
        SelectionExtendDirection.nextLine => SelectionResult.next,
        SelectionExtendDirection.forward ||
        SelectionExtendDirection.backward => SelectionResult.end,
      };
    }
    final int initialOffset = switch (event.direction) {
      SelectionExtendDirection.nextLine ||
      SelectionExtendDirection.forward => 0,
      SelectionExtendDirection.previousLine ||
      SelectionExtendDirection.backward => len,
    };
    _start ??= initialOffset;
    _end ??= initialOffset;
    final Offset localOrigin = _box.localToGlobal(Offset.zero);
    final double rawLocalDx = event.dx - localOrigin.dx - _box._padLeft;
    final double localDx = rawLocalDx.isFinite
        ? math.max(0.0, rawLocalDx)
        : 0.0;
    final int current = (event.isEnd ? _end! : _start!).clamp(0, len);
    final Offset caret = _box._textPainter.getOffsetForCaret(
      TextPosition(offset: current),
      Rect.zero,
    );
    final double lineHeight = _box._textPainter.preferredLineHeight;
    switch (event.direction) {
      case SelectionExtendDirection.previousLine:
        final double targetY = caret.dy - lineHeight * 0.5;
        if (targetY < 0.0) {
          _setEdge(event.isEnd, 0);
          return SelectionResult.previous;
        }
        _setEdge(
          event.isEnd,
          _box._textPainter
              .getPositionForOffset(Offset(localDx, targetY))
              .offset
              .clamp(0, len),
        );
        return SelectionResult.end;
      case SelectionExtendDirection.nextLine:
        final double targetY = caret.dy + lineHeight * 1.5;
        if (targetY > _box._textPainter.height) {
          _setEdge(event.isEnd, len);
          return SelectionResult.next;
        }
        _setEdge(
          event.isEnd,
          _box._textPainter
              .getPositionForOffset(Offset(localDx, targetY))
              .offset
              .clamp(0, len),
        );
        return SelectionResult.end;
      case SelectionExtendDirection.forward:
        final TextRange line = _box._textPainter.getLineBoundary(
          TextPosition(offset: current),
        );
        _setEdge(event.isEnd, line.end);
        return SelectionResult.end;
      case SelectionExtendDirection.backward:
        final TextRange line = _box._textPainter.getLineBoundary(
          TextPosition(offset: current),
        );
        _setEdge(event.isEnd, line.start);
        return SelectionResult.end;
    }
  }

  void _setEdge(bool isEnd, int offset) {
    if (isEnd) {
      _end = offset;
      _start ??= offset;
    } else {
      _start = offset;
      _end ??= offset;
    }
  }
}

void _paintNothing(PaintingContext context, Offset offset) {}

/// Lean single-child box replacing heavy `SingleChildScrollView` (`Scrollable` +
/// `Viewport` + `Ticker` + `RawGestureDetector`) on code blocks and tables.
///
/// Lays out [child] with unbounded width; when [child] fits inside the parent
/// constraints it paints with zero clip layer and zero gesture/scroll overhead,
/// and when [child] overflows horizontally it clips and supports pointer wheel
/// and horizontal drag scrolling.
final class MarkdownHorizontalOverflowBox
    extends SingleChildRenderObjectWidget {
  /// Creates a [MarkdownHorizontalOverflowBox].
  const MarkdownHorizontalOverflowBox({
    super.key,
    this.padding,
    required super.child,
  });

  /// Optional padding around [child].
  final EdgeInsets? padding;

  @override
  RenderHorizontalOverflowBox createRenderObject(BuildContext context) {
    return RenderHorizontalOverflowBox(padding: padding);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHorizontalOverflowBox renderObject,
  ) {
    renderObject.padding = padding;
  }
}

/// RenderBox backing [MarkdownHorizontalOverflowBox].
final class RenderHorizontalOverflowBox extends RenderShiftedBox {
  /// Creates a [RenderHorizontalOverflowBox].
  RenderHorizontalOverflowBox({
    EdgeInsets? padding,
    // ignore: prefer_initializing_formals
  }) : _padding = padding,
       super(null);

  EdgeInsets? _padding;
  double _scrollOffset = 0.0;
  double _maxScrollOffset = 0.0;

  set padding(EdgeInsets? value) {
    if (_padding == value) {
      return;
    }
    _padding = value;
    markNeedsLayout();
  }

  double get _padLeft => _padding?.left ?? 0.0;
  double get _padTop => _padding?.top ?? 0.0;
  double get _hPad => _padding?.horizontal ?? 0.0;
  double get _vPad => _padding?.vertical ?? 0.0;

  @override
  double computeMinIntrinsicWidth(double height) {
    final RenderBox? c = child;
    final double hPad = _hPad;
    if (c == null) {
      return hPad;
    }
    final double innerH = height.isFinite
        ? math.max(0.0, height - _vPad)
        : double.infinity;
    return c.getMinIntrinsicWidth(innerH) + hPad;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final RenderBox? c = child;
    final double hPad = _hPad;
    if (c == null) {
      return hPad;
    }
    final double innerH = height.isFinite
        ? math.max(0.0, height - _vPad)
        : double.infinity;
    return c.getMaxIntrinsicWidth(innerH) + hPad;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final RenderBox? c = child;
    final double vPad = _vPad;
    if (c == null) {
      return vPad;
    }
    return c.getMinIntrinsicHeight(double.infinity) + vPad;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return computeMinIntrinsicHeight(width);
  }

  BoxConstraints _childConstraints(BoxConstraints parent) {
    final double vPad = _vPad;
    return BoxConstraints(
      minWidth: 0.0,
      maxWidth: double.infinity,
      minHeight: math.max(0.0, parent.minHeight - vPad),
      maxHeight: parent.maxHeight.isFinite
          ? math.max(0.0, parent.maxHeight - vPad)
          : double.infinity,
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final RenderBox? c = child;
    final double hPad = _hPad;
    final double vPad = _vPad;
    if (c == null) {
      return constraints.constrain(Size(hPad, vPad));
    }
    final Size dry = c.getDryLayout(_childConstraints(constraints));
    return constraints.constrain(Size(dry.width + hPad, dry.height + vPad));
  }

  @override
  void performLayout() {
    final RenderBox? c = child;
    final double hPad = _hPad;
    final double vPad = _vPad;
    if (c == null) {
      size = constraints.constrain(Size(hPad, vPad));
      _maxScrollOffset = 0.0;
      _scrollOffset = 0.0;
      return;
    }
    c.layout(_childConstraints(constraints), parentUsesSize: true);
    final double totalW = c.size.width + hPad;
    final double totalH = c.size.height + vPad;
    size = constraints.constrain(Size(totalW, totalH));
    final double maxScroll = math.max(0.0, totalW - size.width);
    _maxScrollOffset = maxScroll;
    _scrollOffset = _scrollOffset.clamp(0.0, maxScroll);
    (c.parentData! as BoxParentData).offset = Offset(
      _padLeft - _scrollOffset,
      _padTop,
    );
  }

  @override
  bool hitTestSelf(Offset position) => _maxScrollOffset > 0.0;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (_maxScrollOffset <= 0.0) {
      return;
    }
    double delta = 0.0;
    if (event is PointerScrollEvent) {
      delta = event.scrollDelta.dx;
    } else if (event is PointerMoveEvent) {
      delta = -event.delta.dx;
    }
    if (delta == 0.0) {
      return;
    }
    final double next = (_scrollOffset + delta).clamp(0.0, _maxScrollOffset);
    if (next != _scrollOffset) {
      _scrollOffset = next;
      final RenderBox? c = child;
      if (c != null) {
        (c.parentData! as BoxParentData).offset = Offset(
          _padLeft - _scrollOffset,
          _padTop,
        );
      }
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_maxScrollOffset <= 0.0) {
      super.paint(context, offset);
      return;
    }
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
    );
  }
}
