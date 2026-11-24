import 'dart:math' as math;
import 'dart:ui' as ui show TextBox;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/rendering.dart';
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
    final Color? selectionColor = registrar != null
        ? (DefaultSelectionStyle.of(context).selectionColor ??
              DefaultSelectionStyle.defaultColor)
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

  /// Applies [lineHeightScaleFactor], [letterSpacing], and [wordSpacing]
  /// overrides to nested [TextSpan] children when active.
  TextSpan applySpacingOverrides(TextSpan span) {
    if (lineHeightScaleFactor == null &&
        letterSpacing == null &&
        wordSpacing == null) {
      return span;
    }
    final TextStyle overrideStyle = TextStyle(
      height: lineHeightScaleFactor,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
    );
    return _applyOverrideSpan(overrideStyle, span);
  }

  static TextSpan _applyOverrideSpan(TextStyle overrideStyle, TextSpan span) {
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownRenderEnvironment &&
          textScaler == other.textScaler &&
          textDirection == other.textDirection &&
          identical(selectionRegistrar, other.selectionRegistrar) &&
          selectionColor == other.selectionColor &&
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
    locale,
    hasOverlay,
    defaultTextStyle,
    boldText,
    lineHeightScaleFactor,
    letterSpacing,
    wordSpacing,
  );
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
      return RichText(
        text: activeSpan,
        textAlign: resolvedTextAlign,
        textDirection: resolvedTextDirection,
        textScaler: resolvedTextScaler,
        locale: resolvedLocale,
        selectionRegistrar: selectionRegistrar,
        selectionColor: selectionColor,
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

  /// Effective text direction.
  TextDirection get textDirection => _textPainter.textDirection!;

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
  MouseCursor get cursor =>
      _registrar != null ? SystemMouseCursors.text : MouseCursor.defer;

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
    with Selectable, SelectionRegistrant {
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

  bool get hasSelection => _start != null && _end != null;

  bool get hasHandleLayers =>
      (_startHandleLink != null && _geometry.startSelectionPoint != null) ||
      (_endHandleLink != null && _geometry.endSelectionPoint != null);

  @override
  SelectionGeometry get value => _geometry;

  @override
  int get contentLength => _box._plainText.length;

  @override
  Size get size => _box.size;

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) =>
      _box.getTransformTo(ancestor);

  @override
  List<Rect> get boundingBoxes => <Rect>[_box.paintBounds];

  List<ui.TextBox> get selectionBoxes {
    if (!hasSelection) {
      return const <ui.TextBox>[];
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
    clearHandleLayers();
    super.dispose();
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
        notifyListeners();
      }
      return;
    }
    _start = _start!.clamp(0, len);
    _end = _end!.clamp(0, len);
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
      notifyListeners();
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
    if (!_box.hasSize) {
      return SelectionGeometry(
        status: start == end
            ? SelectionStatus.collapsed
            : SelectionStatus.uncollapsed,
        hasContent: hasContent,
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
        final TextPosition pos = _box._textPainter.getPositionForOffset(local);
        final TextRange word = _box._textPainter.getWordBoundary(pos);
        _start = word.start;
        _end = word.end;
        result = SelectionResult.end;
      case SelectionEventType.selectParagraph:
        final SelectParagraphSelectionEvent paraEvent =
            event as SelectParagraphSelectionEvent;
        _start = 0;
        _end = len;
        result = paraEvent.absorb ? SelectionResult.next : SelectionResult.end;
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final SelectionEdgeUpdateEvent edgeEvent =
            event as SelectionEdgeUpdateEvent;
        final bool isEnd = edgeEvent.type == SelectionEventType.endEdgeUpdate;
        final Offset local = _box.globalToLocal(edgeEvent.globalPosition);
        final SelectionResult edgeResult = SelectionUtils.getResultBasedOnRect(
          _box.paintBounds,
          local,
        );
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
      return event.forward ? SelectionResult.next : SelectionResult.previous;
    }
    final int current =
        (event.isEnd ? _end : _start) ?? (event.forward ? 0 : len);
    int next = current;
    switch (event.granularity) {
      case TextGranularity.character:
        next = event.forward ? current + 1 : current - 1;
      case TextGranularity.word:
        if (event.forward) {
          final TextRange w = _box._textPainter.getWordBoundary(
            TextPosition(offset: current.clamp(0, len)),
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
      case TextGranularity.document:
        next = event.forward ? len : 0;
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
      return switch (event.direction) {
        SelectionExtendDirection.previousLine ||
        SelectionExtendDirection.backward => SelectionResult.previous,
        SelectionExtendDirection.nextLine ||
        SelectionExtendDirection.forward => SelectionResult.next,
      };
    }
    final Offset localOrigin = _box.localToGlobal(Offset.zero);
    final double localDx = event.dx - localOrigin.dx;
    final int current = (event.isEnd ? _end : _start) ?? 0;
    final Offset caret = _box._textPainter.getOffsetForCaret(
      TextPosition(offset: current.clamp(0, len)),
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
          TextPosition(offset: current.clamp(0, len)),
        );
        _setEdge(event.isEnd, line.end);
        return SelectionResult.end;
      case SelectionExtendDirection.backward:
        final TextRange line = _box._textPainter.getLineBoundary(
          TextPosition(offset: current.clamp(0, len)),
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
