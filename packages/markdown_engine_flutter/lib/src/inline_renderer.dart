import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
// Keeps Tooltip compatibility with Flutter 3.32-3.50+ callers.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'built_in_math.dart';
import 'controller.dart';
import 'delegates.dart';
import 'fast_text.dart';
import 'html_block_renderer.dart' show decodeHtmlEntities;
import 'theme.dart';

/// Package-internal keyboard- and pointer-accessible interactive wrapper used
/// for Markdown controls (code copy, `<details>`, footnote links, image ask).
final class MarkdownInteractiveAction extends StatefulWidget {
  /// Creates a [MarkdownInteractiveAction].
  const MarkdownInteractiveAction({
    super.key,
    required this.onActivate,
    required this.semanticLabel,
    required this.focusBorderColor,
    required this.child,
    this.expanded,
    this.borderRadius = const BorderRadius.all(Radius.circular(4.0)),
    this.isButton = true,
    this.isLink = false,
  });

  /// Callback invoked on tap, keyboard Enter/Space, or semantic activation.
  final VoidCallback? onActivate;

  /// Accessible label announced by screen readers.
  final String semanticLabel;

  /// Border color used when keyboard focus highlight is active.
  final Color focusBorderColor;

  /// Visual content rendered inside the interactive target.
  final Widget child;

  /// Optional expanded state for toggle controls like `<details>`.
  final bool? expanded;

  /// Border radius for the keyboard focus indicator.
  final BorderRadius borderRadius;

  /// Whether to expose `Semantics(button: true)`.
  final bool isButton;

  /// Whether to expose `Semantics(link: true)`.
  final bool isLink;

  @override
  State<MarkdownInteractiveAction> createState() =>
      _MarkdownInteractiveActionState();
}

final class _MarkdownInteractiveActionState
    extends State<MarkdownInteractiveAction> {
  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  bool _isFocusHighlighted = false;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onActivate = widget.onActivate;
    return Semantics(
      container: true,
      button: widget.isButton ? true : null,
      link: widget.isLink ? true : null,
      expanded: widget.expanded,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: onActivate != null,
        mouseCursor: onActivate != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        shortcuts: _shortcuts,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (ActivateIntent _) {
              onActivate?.call();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (bool focused) {
          if (_isFocusHighlighted != focused) {
            setState(() {
              _isFocusHighlighted = focused;
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onActivate,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: _isFocusHighlighted
                ? BoxDecoration(
                    borderRadius: widget.borderRadius,
                    border: Border.all(
                      color: widget.focusBorderColor,
                      width: 1.5,
                    ),
                  )
                : const BoxDecoration(),
            child: onActivate != null
                ? DefaultSelectionStyle.merge(
                    mouseCursor: SystemMouseCursors.click,
                    child: ExcludeSemantics(child: widget.child),
                  )
                : ExcludeSemantics(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Internal widget that registers one or more anchor slugs with a
/// [MarkdownController] while mounted.
final class MarkdownAnchorTarget extends StatefulWidget {
  /// Creates a [MarkdownAnchorTarget].
  const MarkdownAnchorTarget({
    super.key,
    required this.slugs,
    required this.controller,
    required this.child,
  });

  /// Anchor slugs or IDs mapped to this widget's [BuildContext].
  final List<String> slugs;

  /// Optional controller receiving anchor registrations.
  final MarkdownController? controller;

  /// Child widget wrapped by this anchor target.
  final Widget child;

  @override
  State<MarkdownAnchorTarget> createState() => _MarkdownAnchorTargetState();
}

final class _MarkdownAnchorTargetState extends State<MarkdownAnchorTarget> {
  @override
  void initState() {
    super.initState();
    _registerAll(widget.controller, widget.slugs);
  }

  @override
  void didUpdateWidget(MarkdownAnchorTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !_stringListEquals(oldWidget.slugs, widget.slugs)) {
      _unregisterAll(oldWidget.controller, oldWidget.slugs);
      _registerAll(widget.controller, widget.slugs);
    }
  }

  @override
  void dispose() {
    _unregisterAll(widget.controller, widget.slugs);
    super.dispose();
  }

  void _registerAll(MarkdownController? controller, List<String> slugs) {
    if (controller == null) {
      return;
    }
    for (final String slug in slugs) {
      if (slug.isNotEmpty) {
        controller.registerAnchor(slug, context);
      }
    }
  }

  void _unregisterAll(MarkdownController? controller, List<String> slugs) {
    if (controller == null) {
      return;
    }
    for (final String slug in slugs) {
      if (slug.isNotEmpty) {
        controller.unregisterAnchor(slug, context);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Returns `true` when [nodes] contains only simple text/style inline nodes
/// with zero links, gesture recognizers, anchors, or embedded [WidgetSpan]s.
bool canBuildFastSimpleInlines(List<MarkdownInlineNode> nodes) {
  for (int i = 0; i < nodes.length; i++) {
    final MarkdownInlineNode node = nodes[i];
    switch (node) {
      case TextNode():
      case SoftBreakNode():
      case HardBreakNode():
      case InlineBreakNode():
      case CodeSpanNode():
        continue;
      case EmphasisNode():
        if (!canBuildFastSimpleInlines(node.children)) {
          return false;
        }
      case StrongNode():
        if (!canBuildFastSimpleInlines(node.children)) {
          return false;
        }
      case StrikethroughNode():
        if (!canBuildFastSimpleInlines(node.children)) {
          return false;
        }
      case HighlightNode():
        if (!canBuildFastSimpleInlines(node.children)) {
          return false;
        }
      case SubscriptNode():
      case SuperscriptNode():
      case LinkNode():
      case ImageNode():
      case PictureInlineNode():
      case MathInlineNode():
      case FootnoteRefNode():
      case KbdInlineNode():
      case AbbrInlineNode():
      case AnchorInlineNode():
      case RawHtmlInlineNode():
        return false;
    }
  }
  return true;
}

/// Builds a pure [InlineSpan] and plain-text string for a verified-simple
/// [nodes] list (caller must ensure [canBuildFastSimpleInlines] is `true`).
({InlineSpan span, String plainText}) buildFastSimpleInlineSpan(
  List<MarkdownInlineNode> nodes,
  TextStyle effectiveStyle,
  MarkdownThemeData theme, {
  TextStyle? cachedCodeSpanStyle,
}) {
  if (nodes.isEmpty) {
    return (span: TextSpan(text: '', style: effectiveStyle), plainText: '');
  }
  if (nodes.length == 1) {
    final MarkdownInlineNode single = nodes.first;
    switch (single) {
      case TextNode():
        return (
          span: TextSpan(text: single.text, style: effectiveStyle),
          plainText: single.text,
        );
      case SoftBreakNode():
        return (
          span: TextSpan(text: ' ', style: effectiveStyle),
          plainText: ' ',
        );
      case HardBreakNode():
      case InlineBreakNode():
        return (
          span: TextSpan(text: '\n', style: effectiveStyle),
          plainText: '\n',
        );
      case CodeSpanNode():
        final TextStyle codeStyle =
            cachedCodeSpanStyle ??
            _deriveFastCodeSpanStyle(effectiveStyle, theme);
        return (
          span: TextSpan(text: single.literal, style: codeStyle),
          plainText: single.literal,
        );
      case StrongNode():
        if (single.children.length == 1 && single.children.first is TextNode) {
          final String text = (single.children.first as TextNode).text;
          return (
            span: TextSpan(
              text: text,
              style: effectiveStyle.copyWith(fontWeight: FontWeight.w700),
            ),
            plainText: text,
          );
        }
      case EmphasisNode():
        if (single.children.length == 1 && single.children.first is TextNode) {
          final String text = (single.children.first as TextNode).text;
          return (
            span: TextSpan(
              text: text,
              style: effectiveStyle.copyWith(fontStyle: FontStyle.italic),
            ),
            plainText: text,
          );
        }
      default:
        break;
    }
  }

  final StringBuffer plainBuffer = StringBuffer();
  final List<InlineSpan> spans = _buildSimpleInlineChildren(
    nodes,
    effectiveStyle,
    theme,
    plainBuffer,
    cachedCodeSpanStyle: cachedCodeSpanStyle,
  );
  return (
    span: TextSpan(style: effectiveStyle, children: spans),
    plainText: plainBuffer.toString(),
  );
}

TextStyle _deriveFastCodeSpanStyle(TextStyle base, MarkdownThemeData theme) {
  final double baseSize = base.fontSize ?? theme.fontSize;
  return base.copyWith(
    fontFamily: theme.effectiveCodeFontFamily,
    fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
    fontSize: baseSize * 0.9,
    color: theme.effectiveCodeForeground,
    backgroundColor: theme.codeBackground,
  );
}

String? _trySinglePlainText(List<MarkdownInlineNode> nodes) {
  if (nodes.length == 1) {
    final MarkdownInlineNode single = nodes.first;
    return switch (single) {
      TextNode() => single.text,
      SoftBreakNode() => ' ',
      HardBreakNode() || InlineBreakNode() => '\n',
      _ => null,
    };
  }
  return null;
}

void _appendStyledSimpleSpan(
  List<InlineSpan> result,
  List<MarkdownInlineNode> children,
  TextStyle childStyle,
  MarkdownThemeData theme,
  StringBuffer plainBuffer,
) {
  final String? singleChild = _trySinglePlainText(children);
  if (singleChild != null) {
    plainBuffer.write(singleChild);
    result.add(TextSpan(text: singleChild, style: childStyle));
    return;
  }
  result.add(
    TextSpan(
      style: childStyle,
      children: _buildSimpleInlineChildren(
        children,
        childStyle,
        theme,
        plainBuffer,
      ),
    ),
  );
}

List<InlineSpan> _buildSimpleInlineChildren(
  List<MarkdownInlineNode> nodes,
  TextStyle style,
  MarkdownThemeData theme,
  StringBuffer plainBuffer, {
  TextStyle? cachedCodeSpanStyle,
}) {
  final List<InlineSpan> result = <InlineSpan>[];
  String? singlePlain;
  StringBuffer? runBuf;

  void flushPlain() {
    if (runBuf != null && runBuf!.isNotEmpty) {
      final String s = runBuf.toString();
      plainBuffer.write(s);
      result.add(TextSpan(text: s));
      runBuf!.clear();
    } else if (singlePlain != null) {
      plainBuffer.write(singlePlain);
      result.add(TextSpan(text: singlePlain));
      singlePlain = null;
    }
  }

  void pushPlain(String piece) {
    if (runBuf != null && runBuf!.isNotEmpty) {
      runBuf!.write(piece);
    } else if (singlePlain != null) {
      (runBuf ??= StringBuffer())
        ..write(singlePlain)
        ..write(piece);
      singlePlain = null;
    } else {
      singlePlain = piece;
    }
  }

  for (int i = 0; i < nodes.length; i++) {
    final MarkdownInlineNode node = nodes[i];
    switch (node) {
      case TextNode():
        pushPlain(node.text);
      case SoftBreakNode():
        pushPlain(' ');
      case HardBreakNode():
      case InlineBreakNode():
        pushPlain('\n');
      case CodeSpanNode():
        flushPlain();
        plainBuffer.write(node.literal);
        final TextStyle codeStyle =
            cachedCodeSpanStyle ?? _deriveFastCodeSpanStyle(style, theme);
        result.add(TextSpan(text: node.literal, style: codeStyle));
      case EmphasisNode():
        flushPlain();
        _appendStyledSimpleSpan(
          result,
          node.children,
          style.copyWith(fontStyle: FontStyle.italic),
          theme,
          plainBuffer,
        );
      case StrongNode():
        flushPlain();
        _appendStyledSimpleSpan(
          result,
          node.children,
          style.copyWith(fontWeight: FontWeight.w700),
          theme,
          plainBuffer,
        );
      case StrikethroughNode():
        flushPlain();
        _appendStyledSimpleSpan(
          result,
          node.children,
          style.copyWith(
            decoration: _combineDecoration(
              style.decoration,
              TextDecoration.lineThrough,
            ),
          ),
          theme,
          plainBuffer,
        );
      case HighlightNode():
        flushPlain();
        _appendStyledSimpleSpan(
          result,
          node.children,
          style.copyWith(backgroundColor: theme.highlightFill),
          theme,
          plainBuffer,
        );
      default:
        break;
    }
  }
  flushPlain();
  return result;
}

/// Builds a lean [FastMarkdownText] leaf widget when [nodes] contains only
/// simple text/style inlines, or falls back to [MarkdownInlineText].
Widget buildFastOrRichInlineText(
  BuildContext context, {
  required List<MarkdownInlineNode> nodes,
  required TextStyle baseStyle,
  required MarkdownThemeData theme,
  required MarkdownBuilderDelegates delegates,
  required MarkdownUrlPolicy urlPolicy,
  MarkdownController? controller,
  TextAlign textAlign = TextAlign.start,
  bool remoteImagesApproved = false,
  VoidCallback? onRequestLoadRemoteImages,
  MarkdownRenderEnvironment? environment,
  TextStyle? effectiveStyleOverride,
  EdgeInsets? contentPadding,
  double? maxWidth,
}) {
  if (canBuildFastSimpleInlines(nodes)) {
    final MarkdownRenderEnvironment env =
        environment ?? MarkdownRenderEnvironment.resolve(context);
    final TextStyle effectiveStyle =
        effectiveStyleOverride ?? env.resolveTextStyle(baseStyle);
    final ({InlineSpan span, String plainText}) built =
        buildFastSimpleInlineSpan(nodes, effectiveStyle, theme);
    return FastMarkdownText(
      span: built.span,
      plainText: built.plainText,
      effectiveStyle: effectiveStyle,
      resolvedTextAlign: textAlign,
      resolvedTextDirection: env.textDirection,
      resolvedTextScaler: env.textScaler,
      resolvedLocale: env.locale,
      selectionRegistrar: env.selectionRegistrar,
      selectionColor: env.selectionColor,
      selectionMouseCursor: env.selectionMouseCursor,
      useLeafRenderBox: true,
      contentPadding: contentPadding,
      maxWidth: maxWidth,
    );
  }
  final Widget rich = MarkdownInlineText(
    nodes: nodes,
    baseStyle: baseStyle,
    theme: theme,
    delegates: delegates,
    urlPolicy: urlPolicy,
    controller: controller,
    textAlign: textAlign,
    remoteImagesApproved: remoteImagesApproved,
    onRequestLoadRemoteImages: onRequestLoadRemoteImages,
    environment: environment,
  );
  if (contentPadding == null && maxWidth == null) {
    return rich;
  }
  Widget wrapped = rich;
  if (contentPadding != null) {
    wrapped = Padding(padding: contentPadding, child: wrapped);
  }
  if (maxWidth != null) {
    wrapped = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: wrapped,
    );
  }
  return wrapped;
}

/// Internal rich-text widget rendering a list of [MarkdownInlineNode]s while
/// owning and cleanly disposing all created [TapGestureRecognizer]s.
final class MarkdownInlineText extends StatefulWidget {
  /// Creates a [MarkdownInlineText].
  const MarkdownInlineText({
    super.key,
    required this.nodes,
    required this.baseStyle,
    required this.theme,
    required this.delegates,
    required this.urlPolicy,
    this.controller,
    this.textAlign = TextAlign.start,
    this.remoteImagesApproved = false,
    this.onRequestLoadRemoteImages,
    this.environment,
  });

  /// Inline AST nodes to render.
  final List<MarkdownInlineNode> nodes;

  /// Inherited base text style for this inline run.
  final TextStyle baseStyle;

  /// Active Markdown visual theme.
  final MarkdownThemeData theme;

  /// Pluggable builders and security delegates.
  final MarkdownBuilderDelegates delegates;

  /// Effective URL policy gating interactive links and images.
  final MarkdownUrlPolicy urlPolicy;

  /// Optional controller for `#anchor` and footnote navigation.
  final MarkdownController? controller;

  /// Horizontal text alignment applied to the paragraph.
  final TextAlign textAlign;

  /// Whether remote images were approved for the current view session.
  final bool remoteImagesApproved;

  /// Callback triggered when the user approves remote images in `ask` mode.
  final VoidCallback? onRequestLoadRemoteImages;

  /// Optional pre-resolved ambient environment hoisted by the enclosing view.
  final MarkdownRenderEnvironment? environment;

  @override
  State<MarkdownInlineText> createState() => _MarkdownInlineTextState();
}

final class _TrackedRecognizer {
  const _TrackedRecognizer(this.key, this.recognizer);

  final String key;
  final TapGestureRecognizer recognizer;
}

final class _InlineBuildAccumulator {
  _InlineBuildAccumulator(this.env);

  final MarkdownRenderEnvironment env;
  bool hasWidgetSpan = false;
}

enum _InlineHtmlStyleTag {
  underline,
  strikethrough,
  strong,
  emphasis,
  small,
  quote,
  code,
  samp,
  variable,
  highlight,
}

final class _MarkdownInlineTextState extends State<MarkdownInlineText> {
  static const Map<ShortcutActivator, Intent> _linkActivateShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  List<_TrackedRecognizer> _recognizers = const <_TrackedRecognizer>[];
  final List<TapGestureRecognizer> _retiredRecognizers =
      <TapGestureRecognizer>[];
  bool _postFrameCleanupScheduled = false;

  Widget? _cachedRichText;
  List<MarkdownInlineNode>? _cachedNodes;
  TextStyle? _cachedBaseStyle;
  MarkdownThemeData? _cachedTheme;
  MarkdownBuilderDelegates? _cachedDelegates;
  MarkdownUrlPolicy? _cachedUrlPolicy;
  MarkdownController? _cachedController;
  TextAlign? _cachedTextAlign;
  bool? _cachedRemoteImagesApproved;
  VoidCallback? _cachedOnRequestLoadRemoteImages;
  MarkdownRenderEnvironment? _cachedEnvironment;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.environment == null) {
      _cachedRichText = null;
    }
  }

  @override
  void dispose() {
    for (final _TrackedRecognizer entry in _recognizers) {
      entry.recognizer.dispose();
    }
    _recognizers = const <_TrackedRecognizer>[];
    _disposeRetiredRecognizers();
    _cachedRichText = null;
    super.dispose();
  }

  void _disposeRetiredRecognizers() {
    for (final TapGestureRecognizer recognizer in _retiredRecognizers) {
      recognizer.dispose();
    }
    _retiredRecognizers.clear();
  }

  void _scheduleRetiredCleanup() {
    if (_retiredRecognizers.isEmpty || _postFrameCleanupScheduled) {
      return;
    }
    _postFrameCleanupScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _postFrameCleanupScheduled = false;
      if (mounted) {
        _disposeRetiredRecognizers();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final MarkdownRenderEnvironment env =
        widget.environment ?? MarkdownRenderEnvironment.resolve(context);

    final Widget? cached = _cachedRichText;
    if (cached != null &&
        identical(widget.nodes, _cachedNodes) &&
        widget.baseStyle == _cachedBaseStyle &&
        widget.theme == _cachedTheme &&
        widget.delegates == _cachedDelegates &&
        widget.urlPolicy == _cachedUrlPolicy &&
        identical(widget.controller, _cachedController) &&
        widget.textAlign == _cachedTextAlign &&
        widget.remoteImagesApproved == _cachedRemoteImagesApproved &&
        widget.onRequestLoadRemoteImages == _cachedOnRequestLoadRemoteImages &&
        env == _cachedEnvironment) {
      return cached;
    }

    Map<String, List<TapGestureRecognizer>>? pool;
    if (_recognizers.isNotEmpty) {
      pool = <String, List<TapGestureRecognizer>>{};
      for (final _TrackedRecognizer entry in _recognizers) {
        pool
            .putIfAbsent(entry.key, () => <TapGestureRecognizer>[])
            .add(entry.recognizer);
      }
    }
    final List<_TrackedRecognizer> nextRecognizers = <_TrackedRecognizer>[];
    final _InlineBuildAccumulator acc = _InlineBuildAccumulator(env);
    final TextStyle effectiveStyle = env.resolveTextStyle(widget.baseStyle);

    final List<InlineSpan> spans = _buildInlines(
      context,
      widget.nodes,
      effectiveStyle,
      linkRecognizer: null,
      onLinkTap: null,
      isLink: false,
      linkUrl: null,
      recognizerPool: pool,
      nextRecognizers: nextRecognizers,
      acc: acc,
    );

    if (pool != null) {
      for (final List<TapGestureRecognizer> unused in pool.values) {
        _retiredRecognizers.addAll(unused);
      }
    }
    _recognizers = nextRecognizers.isEmpty
        ? const <_TrackedRecognizer>[]
        : nextRecognizers;
    _scheduleRetiredCleanup();

    final TextSpan baseSpan = TextSpan(style: effectiveStyle, children: spans);
    final Widget built;
    if (!acc.hasWidgetSpan) {
      final TextSpan rootSpan = env.applySpacingOverrides(baseSpan);
      built = FastMarkdownText(
        span: rootSpan,
        plainText: rootSpan.toPlainText(includeSemanticsLabels: false),
        effectiveStyle: effectiveStyle,
        resolvedTextAlign: widget.textAlign,
        resolvedTextDirection: env.textDirection,
        resolvedTextScaler: env.textScaler,
        resolvedLocale: env.locale,
        selectionRegistrar: env.selectionRegistrar,
        selectionColor: env.selectionColor,
        selectionMouseCursor: env.selectionMouseCursor,
        useLeafRenderBox: nextRecognizers.isEmpty,
      );
    } else {
      built = MarkdownRichText.rich(
        baseSpan,
        textAlign: widget.textAlign,
        textDirection: env.textDirection,
        textScaler: env.textScaler,
        locale: env.locale,
        selectionColor: env.selectionColor,
      );
    }
    _cachedRichText = built;
    _cachedNodes = widget.nodes;
    _cachedBaseStyle = widget.baseStyle;
    _cachedTheme = widget.theme;
    _cachedDelegates = widget.delegates;
    _cachedUrlPolicy = widget.urlPolicy;
    _cachedController = widget.controller;
    _cachedTextAlign = widget.textAlign;
    _cachedRemoteImagesApproved = widget.remoteImagesApproved;
    _cachedOnRequestLoadRemoteImages = widget.onRequestLoadRemoteImages;
    _cachedEnvironment = env;
    return built;
  }

  TapGestureRecognizer _acquireRecognizer(
    String key,
    VoidCallback onTap,
    Map<String, List<TapGestureRecognizer>>? pool,
    List<_TrackedRecognizer> nextRecognizers,
  ) {
    final List<TapGestureRecognizer>? bucket = pool?[key];
    final TapGestureRecognizer recognizer =
        (bucket != null && bucket.isNotEmpty)
        ? bucket.removeAt(0)
        : TapGestureRecognizer();
    recognizer.onTap = onTap;
    nextRecognizers.add(_TrackedRecognizer(key, recognizer));
    return recognizer;
  }

  List<InlineSpan> _buildInlines(
    BuildContext context,
    List<MarkdownInlineNode> nodes,
    TextStyle style, {
    int start = 0,
    int? end,
    Map<int, int>? rawPairCloseByOpen,
    int inlineHtmlDepth = 0,
    required TapGestureRecognizer? linkRecognizer,
    required VoidCallback? onLinkTap,
    required bool isLink,
    required Uri? linkUrl,
    required Map<String, List<TapGestureRecognizer>>? recognizerPool,
    required List<_TrackedRecognizer> nextRecognizers,
    required _InlineBuildAccumulator acc,
  }) {
    final int limit = end ?? nodes.length;
    if (start >= limit) {
      return const <InlineSpan>[];
    }
    final List<InlineSpan> result = <InlineSpan>[];
    final List<_InlineHtmlStyleTag> tagStack = <_InlineHtmlStyleTag>[];
    final MouseCursor? linkCursor = linkRecognizer != null
        ? SystemMouseCursors.click
        : null;

    for (int i = start; i < limit; i++) {
      final MarkdownInlineNode node = nodes[i];
      final TextStyle activeStyle = tagStack.isEmpty
          ? style
          : _applyHtmlTagStackStyle(style, tagStack, isLink: isLink);
      if (node is RawHtmlInlineNode) {
        final _RawHtmlDirective directive = _parseRawHtmlDirective(node.html);
        switch (directive.kind) {
          case _RawHtmlDirectiveKind.openUnderline:
            tagStack.add(_InlineHtmlStyleTag.underline);
          case _RawHtmlDirectiveKind.closeUnderline:
            _popTag(tagStack, _InlineHtmlStyleTag.underline);
          case _RawHtmlDirectiveKind.openStrikethrough:
            tagStack.add(_InlineHtmlStyleTag.strikethrough);
          case _RawHtmlDirectiveKind.closeStrikethrough:
            _popTag(tagStack, _InlineHtmlStyleTag.strikethrough);
          case _RawHtmlDirectiveKind.openStrong:
            tagStack.add(_InlineHtmlStyleTag.strong);
          case _RawHtmlDirectiveKind.closeStrong:
            _popTag(tagStack, _InlineHtmlStyleTag.strong);
          case _RawHtmlDirectiveKind.openEmphasis:
            tagStack.add(_InlineHtmlStyleTag.emphasis);
          case _RawHtmlDirectiveKind.closeEmphasis:
            _popTag(tagStack, _InlineHtmlStyleTag.emphasis);
          case _RawHtmlDirectiveKind.openSmall:
            tagStack.add(_InlineHtmlStyleTag.small);
          case _RawHtmlDirectiveKind.closeSmall:
            _popTag(tagStack, _InlineHtmlStyleTag.small);
          case _RawHtmlDirectiveKind.openQuote:
            tagStack.add(_InlineHtmlStyleTag.quote);
            result.add(
              TextSpan(
                text: '\u201C',
                style: activeStyle,
                recognizer: linkRecognizer,
                mouseCursor: linkCursor,
              ),
            );
          case _RawHtmlDirectiveKind.closeQuote:
            if (_popTag(tagStack, _InlineHtmlStyleTag.quote)) {
              result.add(
                TextSpan(
                  text: '\u201D',
                  style: activeStyle,
                  recognizer: linkRecognizer,
                  mouseCursor: linkCursor,
                ),
              );
            }
          case _RawHtmlDirectiveKind.openCode:
            tagStack.add(_InlineHtmlStyleTag.code);
          case _RawHtmlDirectiveKind.closeCode:
            _popTag(tagStack, _InlineHtmlStyleTag.code);
          case _RawHtmlDirectiveKind.openSamp:
            tagStack.add(_InlineHtmlStyleTag.samp);
          case _RawHtmlDirectiveKind.closeSamp:
            _popTag(tagStack, _InlineHtmlStyleTag.samp);
          case _RawHtmlDirectiveKind.openVar:
            tagStack.add(_InlineHtmlStyleTag.variable);
          case _RawHtmlDirectiveKind.closeVar:
            _popTag(tagStack, _InlineHtmlStyleTag.variable);
          case _RawHtmlDirectiveKind.openHighlight:
            tagStack.add(_InlineHtmlStyleTag.highlight);
          case _RawHtmlDirectiveKind.closeHighlight:
            _popTag(tagStack, _InlineHtmlStyleTag.highlight);
          case _RawHtmlDirectiveKind.openSubscript:
          case _RawHtmlDirectiveKind.openSuperscript:
            if (inlineHtmlDepth >= _maxInlineHtmlDepth) {
              break;
            }
            rawPairCloseByOpen ??= _computeRawHtmlPairCloses(
              nodes,
              start,
              limit,
            );
            final int? closeIndex = rawPairCloseByOpen[i];
            if (closeIndex != null && closeIndex < limit) {
              if (i + 1 < closeIndex) {
                final bool isSuperscript =
                    directive.kind == _RawHtmlDirectiveKind.openSuperscript;
                result.add(
                  _buildScriptSpan(
                    context,
                    nodes,
                    activeStyle,
                    start: i + 1,
                    end: closeIndex,
                    rawPairCloseByOpen: rawPairCloseByOpen,
                    inlineHtmlDepth: inlineHtmlDepth,
                    isSuperscript: isSuperscript,
                    linkRecognizer: linkRecognizer,
                    onLinkTap: onLinkTap,
                    isLink: isLink,
                    linkUrl: linkUrl,
                    recognizerPool: recognizerPool,
                    nextRecognizers: nextRecognizers,
                    acc: acc,
                  ),
                );
              }
              i = closeIndex;
            }
          case _RawHtmlDirectiveKind.closeSubscript:
          case _RawHtmlDirectiveKind.closeSuperscript:
            break;
          case _RawHtmlDirectiveKind.openAbbr:
            if (inlineHtmlDepth >= _maxInlineHtmlDepth) {
              break;
            }
            rawPairCloseByOpen ??= _computeRawHtmlPairCloses(
              nodes,
              start,
              limit,
            );
            final int? closeIndex = rawPairCloseByOpen[i];
            if (closeIndex != null && closeIndex < limit) {
              if (i + 1 < closeIndex) {
                final String? title = directive.value;
                if (title != null && title.isNotEmpty) {
                  result.add(
                    _buildAbbrSpan(
                      context,
                      nodes,
                      activeStyle,
                      title: title,
                      start: i + 1,
                      end: closeIndex,
                      rawPairCloseByOpen: rawPairCloseByOpen,
                      inlineHtmlDepth: inlineHtmlDepth,
                      linkRecognizer: linkRecognizer,
                      onLinkTap: onLinkTap,
                      isLink: isLink,
                      linkUrl: linkUrl,
                      recognizerPool: recognizerPool,
                      nextRecognizers: nextRecognizers,
                      acc: acc,
                    ),
                  );
                } else {
                  result.addAll(
                    _buildInlines(
                      context,
                      nodes,
                      activeStyle,
                      start: i + 1,
                      end: closeIndex,
                      rawPairCloseByOpen: rawPairCloseByOpen,
                      inlineHtmlDepth: inlineHtmlDepth + 1,
                      linkRecognizer: linkRecognizer,
                      onLinkTap: onLinkTap,
                      isLink: isLink,
                      linkUrl: linkUrl,
                      recognizerPool: recognizerPool,
                      nextRecognizers: nextRecognizers,
                      acc: acc,
                    ),
                  );
                }
              }
              i = closeIndex;
            }
          case _RawHtmlDirectiveKind.closeAbbr:
            break;
          case _RawHtmlDirectiveKind.anchor:
            final String? anchorId = directive.value;
            if (anchorId != null && anchorId.isNotEmpty) {
              acc.hasWidgetSpan = true;
              result.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ExcludeSemantics(
                    child: MarkdownAnchorTarget(
                      slugs: <String>[anchorId],
                      controller: widget.controller,
                      child: const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            }
          case _RawHtmlDirectiveKind.none:
            break;
        }
        continue;
      }

      result.add(
        _buildInline(
          context,
          node,
          activeStyle,
          inlineHtmlDepth: inlineHtmlDepth,
          linkRecognizer: linkRecognizer,
          onLinkTap: onLinkTap,
          isLink: isLink,
          linkUrl: linkUrl,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        ),
      );
    }
    return result;
  }

  TextStyle _applyHtmlTagStackStyle(
    TextStyle base,
    List<_InlineHtmlStyleTag> stack, {
    required bool isLink,
  }) {
    TextStyle current = base;
    for (final _InlineHtmlStyleTag tag in stack) {
      switch (tag) {
        case _InlineHtmlStyleTag.underline:
          current = current.copyWith(
            decoration: _combineDecoration(
              current.decoration,
              TextDecoration.underline,
            ),
          );
        case _InlineHtmlStyleTag.strikethrough:
          current = current.copyWith(
            decoration: _combineDecoration(
              current.decoration,
              TextDecoration.lineThrough,
            ),
          );
        case _InlineHtmlStyleTag.strong:
          current = current.copyWith(fontWeight: FontWeight.w700);
        case _InlineHtmlStyleTag.emphasis:
        case _InlineHtmlStyleTag.variable:
          current = current.copyWith(fontStyle: FontStyle.italic);
        case _InlineHtmlStyleTag.small:
          final double baseSize = current.fontSize ?? widget.theme.fontSize;
          current = current.copyWith(fontSize: baseSize * 0.85);
        case _InlineHtmlStyleTag.quote:
          break;
        case _InlineHtmlStyleTag.code:
        case _InlineHtmlStyleTag.samp:
          final double baseSize = current.fontSize ?? widget.theme.fontSize;
          current = current.copyWith(
            fontFamily: widget.theme.effectiveCodeFontFamily,
            fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
            fontSize: baseSize * 0.9,
            color: isLink
                ? current.color
                : widget.theme.effectiveCodeForeground,
            backgroundColor: widget.theme.codeBackground,
          );
        case _InlineHtmlStyleTag.highlight:
          current = current.copyWith(
            backgroundColor: widget.theme.highlightFill,
          );
      }
    }
    return current;
  }

  static bool _popTag(
    List<_InlineHtmlStyleTag> stack,
    _InlineHtmlStyleTag target,
  ) {
    for (int i = stack.length - 1; i >= 0; i--) {
      if (stack[i] == target) {
        stack.removeAt(i);
        return true;
      }
    }
    return false;
  }

  InlineSpan _buildInline(
    BuildContext context,
    MarkdownInlineNode node,
    TextStyle style, {
    int inlineHtmlDepth = 0,
    required TapGestureRecognizer? linkRecognizer,
    required VoidCallback? onLinkTap,
    required bool isLink,
    required Uri? linkUrl,
    required Map<String, List<TapGestureRecognizer>>? recognizerPool,
    required List<_TrackedRecognizer> nextRecognizers,
    required _InlineBuildAccumulator acc,
  }) {
    final MarkdownThemeData theme = widget.theme;
    final MarkdownBuilderDelegates delegates = widget.delegates;
    final MouseCursor? linkCursor = linkRecognizer != null
        ? SystemMouseCursors.click
        : null;

    switch (node) {
      case TextNode():
        return TextSpan(
          text: node.text,
          style: style,
          recognizer: linkRecognizer,
          mouseCursor: linkCursor,
        );
      case SoftBreakNode():
        return TextSpan(
          text: ' ',
          style: style,
          recognizer: linkRecognizer,
          mouseCursor: linkCursor,
        );
      case HardBreakNode():
      case InlineBreakNode():
        return TextSpan(text: '\n', style: style);
      case CodeSpanNode():
        final double baseSize = style.fontSize ?? theme.fontSize;
        final TextStyle codeStyle = style.copyWith(
          fontFamily: theme.effectiveCodeFontFamily,
          fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
          fontSize: baseSize * 0.9,
          color: linkRecognizer != null
              ? style.color
              : theme.effectiveCodeForeground,
          backgroundColor: theme.codeBackground,
        );
        return TextSpan(
          text: node.literal,
          style: codeStyle,
          recognizer: linkRecognizer,
          mouseCursor: linkCursor,
        );
      case EmphasisNode():
        final TextStyle emStyle = style.copyWith(fontStyle: FontStyle.italic);
        return TextSpan(
          style: emStyle,
          children: _buildInlines(
            context,
            node.children,
            emStyle,
            inlineHtmlDepth: inlineHtmlDepth,
            linkRecognizer: linkRecognizer,
            onLinkTap: onLinkTap,
            isLink: isLink,
            linkUrl: linkUrl,
            recognizerPool: recognizerPool,
            nextRecognizers: nextRecognizers,
            acc: acc,
          ),
        );
      case StrongNode():
        final TextStyle strongStyle = style.copyWith(
          fontWeight: FontWeight.w700,
        );
        return TextSpan(
          style: strongStyle,
          children: _buildInlines(
            context,
            node.children,
            strongStyle,
            inlineHtmlDepth: inlineHtmlDepth,
            linkRecognizer: linkRecognizer,
            onLinkTap: onLinkTap,
            isLink: isLink,
            linkUrl: linkUrl,
            recognizerPool: recognizerPool,
            nextRecognizers: nextRecognizers,
            acc: acc,
          ),
        );
      case StrikethroughNode():
        final TextStyle strikeStyle = style.copyWith(
          decoration: _combineDecoration(
            style.decoration,
            TextDecoration.lineThrough,
          ),
        );
        return TextSpan(
          style: strikeStyle,
          children: _buildInlines(
            context,
            node.children,
            strikeStyle,
            inlineHtmlDepth: inlineHtmlDepth,
            linkRecognizer: linkRecognizer,
            onLinkTap: onLinkTap,
            isLink: isLink,
            linkUrl: linkUrl,
            recognizerPool: recognizerPool,
            nextRecognizers: nextRecognizers,
            acc: acc,
          ),
        );
      case HighlightNode():
        final TextStyle highlightStyle = style.copyWith(
          backgroundColor: theme.highlightFill,
        );
        return TextSpan(
          style: highlightStyle,
          children: _buildInlines(
            context,
            node.children,
            highlightStyle,
            inlineHtmlDepth: inlineHtmlDepth,
            linkRecognizer: linkRecognizer,
            onLinkTap: onLinkTap,
            isLink: isLink,
            linkUrl: linkUrl,
            recognizerPool: recognizerPool,
            nextRecognizers: nextRecognizers,
            acc: acc,
          ),
        );
      case SubscriptNode():
        return _buildScriptSpan(
          context,
          node.children,
          style,
          inlineHtmlDepth: inlineHtmlDepth,
          isSuperscript: false,
          linkRecognizer: linkRecognizer,
          onLinkTap: onLinkTap,
          isLink: isLink,
          linkUrl: linkUrl,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        );
      case SuperscriptNode():
        return _buildScriptSpan(
          context,
          node.children,
          style,
          inlineHtmlDepth: inlineHtmlDepth,
          isSuperscript: true,
          linkRecognizer: linkRecognizer,
          onLinkTap: onLinkTap,
          isLink: isLink,
          linkUrl: linkUrl,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        );
      case LinkNode():
        return _buildLinkSpan(
          context,
          node,
          style,
          inlineHtmlDepth: inlineHtmlDepth,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        );
      case ImageNode():
        acc.hasWidgetSpan = true;
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _wrapWidgetWithLink(
            buildMarkdownImageWidget(
              context: context,
              node: node,
              theme: theme,
              delegates: delegates,
              urlPolicy: widget.urlPolicy,
              remoteImagesApproved: widget.remoteImagesApproved,
              onRequestLoadRemoteImages: widget.onRequestLoadRemoteImages,
            ),
            onLinkTap: onLinkTap,
            isLink: isLink,
            linkUrl: linkUrl,
          ),
        );
      case PictureInlineNode():
        acc.hasWidgetSpan = true;
        final String chosen = theme.brightness == Brightness.dark
            ? (node.darkSource.isNotEmpty ? node.darkSource : node.lightSource)
            : (node.lightSource.isNotEmpty
                  ? node.lightSource
                  : node.darkSource);
        final ImageNode syntheticImage = ImageNode(
          destination: chosen,
          alt: node.alt,
          span: node.span,
        );
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _wrapWidgetWithLink(
            buildMarkdownImageWidget(
              context: context,
              node: syntheticImage,
              theme: theme,
              delegates: delegates,
              urlPolicy: widget.urlPolicy,
              remoteImagesApproved: widget.remoteImagesApproved,
              onRequestLoadRemoteImages: widget.onRequestLoadRemoteImages,
            ),
            onLinkTap: onLinkTap,
            isLink: isLink,
            linkUrl: linkUrl,
          ),
        );
      case MathInlineNode():
        final MarkdownMathInlineBuilder? builder = delegates.mathInlineBuilder;
        if (builder != null) {
          final InlineSpan custom = builder(
            context,
            node,
            style,
            linkRecognizer,
          );
          if (custom is WidgetSpan) {
            acc.hasWidgetSpan = true;
          }
          return custom;
        }
        acc.hasWidgetSpan = true;
        if (delegates.enableBuiltInMath) {
          final Widget builtInMath = buildBuiltInInlineMathWidget(
            context: context,
            node: node,
            style: style,
            theme: theme,
            delegates: delegates,
            urlPolicy: widget.urlPolicy,
            isInsideLink: isLink,
            hasAncestorSelection: acc.env.selectionRegistrar != null,
            textScaler: acc.env.textScaler,
          );
          return WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            style: style,
            child: _wrapWidgetWithLink(
              builtInMath,
              onLinkTap: onLinkTap,
              isLink: isLink,
              linkUrl: linkUrl,
            ),
          );
        }
        final double baseSize = style.fontSize ?? theme.fontSize;
        final Widget mathChip = Semantics(
          label: 'Math: ${node.latex}',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
            decoration: BoxDecoration(
              color: theme.codeBackground,
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: MarkdownRichText(
              node.latex,
              style: style.copyWith(
                fontFamily: theme.effectiveCodeFontFamily,
                fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
                fontStyle: FontStyle.italic,
                fontSize: baseSize * 0.92,
                height: 1.2,
              ),
            ),
          ),
        );
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _wrapWidgetWithLink(
            mathChip,
            onLinkTap: onLinkTap,
            isLink: isLink,
            linkUrl: linkUrl,
          ),
        );
      case FootnoteRefNode():
        acc.hasWidgetSpan = true;
        return _buildFootnoteRefSpan(node, style);
      case KbdInlineNode():
        acc.hasWidgetSpan = true;
        final double baseSize = style.fontSize ?? theme.fontSize;
        final TextStyle kbdStyle = style.copyWith(
          fontFamily: theme.effectiveCodeFontFamily,
          fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
          fontSize: baseSize * 0.82,
          height: 1.15,
          color: linkRecognizer != null
              ? style.color
              : theme.effectiveCodeForeground,
        );
        final List<InlineSpan> kbdChildren = _buildInlines(
          context,
          node.children,
          kbdStyle,
          inlineHtmlDepth: inlineHtmlDepth,
          linkRecognizer: null,
          onLinkTap: null,
          isLink: false,
          linkUrl: null,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        );
        final Widget keycap = Semantics(
          label: 'Key ${node.toPlainText()}',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.5),
            decoration: BoxDecoration(
              color: theme.codeBackground,
              borderRadius: BorderRadius.circular(4.0),
              border: Border(
                top: BorderSide(color: theme.border, width: 1.0),
                left: BorderSide(color: theme.border, width: 1.0),
                right: BorderSide(color: theme.border, width: 1.0),
                bottom: BorderSide(color: theme.border, width: 2.0),
              ),
            ),
            child: MarkdownRichText.rich(
              TextSpan(style: kbdStyle, children: kbdChildren),
            ),
          ),
        );
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _wrapWidgetWithLink(
            keycap,
            onLinkTap: onLinkTap,
            isLink: isLink,
            linkUrl: linkUrl,
          ),
        );
      case AbbrInlineNode():
        return _buildAbbrSpan(
          context,
          node.children,
          style,
          title: node.title,
          inlineHtmlDepth: inlineHtmlDepth,
          linkRecognizer: linkRecognizer,
          onLinkTap: onLinkTap,
          isLink: isLink,
          linkUrl: linkUrl,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        );
      case AnchorInlineNode():
        acc.hasWidgetSpan = true;
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ExcludeSemantics(
            child: MarkdownAnchorTarget(
              slugs: <String>[node.id],
              controller: widget.controller,
              child: const SizedBox.shrink(),
            ),
          ),
        );
      case RawHtmlInlineNode():
        final ImageNode? rawImg = tryParseHtmlImageTag(node.html);
        if (rawImg != null) {
          acc.hasWidgetSpan = true;
          return WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _wrapWidgetWithLink(
              buildMarkdownImageWidget(
                context: context,
                node: rawImg,
                theme: theme,
                delegates: delegates,
                urlPolicy: widget.urlPolicy,
                remoteImagesApproved: widget.remoteImagesApproved,
                onRequestLoadRemoteImages: widget.onRequestLoadRemoteImages,
              ),
              onLinkTap: onLinkTap,
              isLink: isLink,
              linkUrl: linkUrl,
            ),
          );
        }
        return const TextSpan();
    }
  }

  InlineSpan _buildScriptSpan(
    BuildContext context,
    List<MarkdownInlineNode> nodes,
    TextStyle style, {
    int start = 0,
    int? end,
    Map<int, int>? rawPairCloseByOpen,
    required int inlineHtmlDepth,
    required bool isSuperscript,
    required TapGestureRecognizer? linkRecognizer,
    required VoidCallback? onLinkTap,
    required bool isLink,
    required Uri? linkUrl,
    required Map<String, List<TapGestureRecognizer>>? recognizerPool,
    required List<_TrackedRecognizer> nextRecognizers,
    required _InlineBuildAccumulator acc,
  }) {
    if (inlineHtmlDepth >= _maxInlineHtmlDepth) {
      return TextSpan(
        style: style,
        children: _buildInlines(
          context,
          nodes,
          style,
          start: start,
          end: end,
          rawPairCloseByOpen: rawPairCloseByOpen,
          inlineHtmlDepth: inlineHtmlDepth,
          linkRecognizer: linkRecognizer,
          onLinkTap: onLinkTap,
          isLink: isLink,
          linkUrl: linkUrl,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        ),
      );
    }
    acc.hasWidgetSpan = true;
    final double baseSize = style.fontSize ?? widget.theme.fontSize;
    final TextStyle scriptStyle = style.copyWith(
      fontSize: baseSize * 0.74,
      height: 1.0,
    );
    final List<InlineSpan> childSpans = _buildInlines(
      context,
      nodes,
      scriptStyle,
      start: start,
      end: end,
      rawPairCloseByOpen: rawPairCloseByOpen,
      inlineHtmlDepth: inlineHtmlDepth + 1,
      linkRecognizer: null,
      onLinkTap: null,
      isLink: false,
      linkUrl: null,
      recognizerPool: recognizerPool,
      nextRecognizers: nextRecognizers,
      acc: acc,
    );
    final double dy = isSuperscript ? -baseSize * 0.3 : baseSize * 0.2;
    final Widget scriptWidget = Transform.translate(
      offset: Offset(0.0, dy),
      child: MarkdownRichText.rich(
        TextSpan(style: scriptStyle, children: childSpans),
      ),
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _wrapWidgetWithLink(
        scriptWidget,
        onLinkTap: onLinkTap,
        isLink: isLink,
        linkUrl: linkUrl,
      ),
    );
  }

  InlineSpan _buildAbbrSpan(
    BuildContext context,
    List<MarkdownInlineNode> nodes,
    TextStyle style, {
    required String title,
    int start = 0,
    int? end,
    Map<int, int>? rawPairCloseByOpen,
    required int inlineHtmlDepth,
    required TapGestureRecognizer? linkRecognizer,
    required VoidCallback? onLinkTap,
    required bool isLink,
    required Uri? linkUrl,
    required Map<String, List<TapGestureRecognizer>>? recognizerPool,
    required List<_TrackedRecognizer> nextRecognizers,
    required _InlineBuildAccumulator acc,
  }) {
    final MarkdownThemeData theme = widget.theme;
    final int limit = end ?? nodes.length;
    final TextStyle abbrStyle = style.copyWith(
      decoration: _combineDecoration(
        style.decoration,
        TextDecoration.underline,
      ),
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: theme.muted,
    );
    if (inlineHtmlDepth >= _maxInlineHtmlDepth) {
      return TextSpan(
        style: abbrStyle,
        children: _buildInlines(
          context,
          nodes,
          abbrStyle,
          start: start,
          end: limit,
          rawPairCloseByOpen: rawPairCloseByOpen,
          inlineHtmlDepth: inlineHtmlDepth,
          linkRecognizer: linkRecognizer,
          onLinkTap: onLinkTap,
          isLink: isLink,
          linkUrl: linkUrl,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        ),
      );
    }
    acc.hasWidgetSpan = true;
    final List<InlineSpan> abbrChildren = _buildInlines(
      context,
      nodes,
      abbrStyle,
      start: start,
      end: limit,
      rawPairCloseByOpen: rawPairCloseByOpen,
      inlineHtmlDepth: inlineHtmlDepth + 1,
      linkRecognizer: null,
      onLinkTap: null,
      isLink: false,
      linkUrl: null,
      recognizerPool: recognizerPool,
      nextRecognizers: nextRecognizers,
      acc: acc,
    );
    Widget labelWidget = MarkdownRichText.rich(
      TextSpan(style: abbrStyle, children: abbrChildren),
    );
    if (acc.env.hasOverlay) {
      labelWidget = Tooltip(
        message: title,
        excludeFromSemantics: true,
        child: labelWidget,
      );
    }
    final Widget semanticAbbr = Semantics(
      label: _inlinesSliceToPlainText(nodes, start, limit),
      tooltip: title,
      excludeSemantics: true,
      child: labelWidget,
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _wrapWidgetWithLink(
        semanticAbbr,
        onLinkTap: onLinkTap,
        isLink: isLink,
        linkUrl: linkUrl,
      ),
    );
  }

  InlineSpan _buildLinkSpan(
    BuildContext context,
    LinkNode node,
    TextStyle style, {
    int inlineHtmlDepth = 0,
    required Map<String, List<TapGestureRecognizer>>? recognizerPool,
    required List<_TrackedRecognizer> nextRecognizers,
    required _InlineBuildAccumulator acc,
  }) {
    final String destination = node.destination.trim();
    final MarkdownUrlPolicy policy = widget.urlPolicy;
    final bool isAllowed =
        destination.isNotEmpty && policy.isAllowed(destination);

    if (!isAllowed) {
      return TextSpan(
        style: style,
        children: _buildInlines(
          context,
          node.children,
          style,
          inlineHtmlDepth: inlineHtmlDepth,
          linkRecognizer: null,
          onLinkTap: null,
          isLink: false,
          linkUrl: null,
          recognizerPool: recognizerPool,
          nextRecognizers: nextRecognizers,
          acc: acc,
        ),
      );
    }

    final bool isFragment = destination.startsWith('#');
    final Uri? parsedUri = Uri.tryParse(destination);
    final bool isWeb =
        parsedUri != null &&
        (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') &&
        parsedUri.hasAuthority;

    final MarkdownBuilderDelegates delegates = widget.delegates;
    final MarkdownController? controller = widget.controller;
    final bool hasAction =
        delegates.onTapLink != null ||
        (isWeb && delegates.onOpenWebLink != null) ||
        (isFragment && controller != null && delegates.autoScrollToAnchors);

    VoidCallback? onTap;
    TapGestureRecognizer? recognizer;

    if (hasAction) {
      onTap = () {
        if (!policy.isAllowed(destination)) {
          return;
        }
        if (isFragment && controller != null && delegates.autoScrollToAnchors) {
          unawaited(controller.scrollToAnchor(destination.substring(1)));
        }
        delegates.onTapLink?.call(destination, node.title);
        if (isWeb && delegates.onOpenWebLink != null) {
          final Uri? webUri = Uri.tryParse(destination);
          if (webUri != null &&
              (webUri.scheme == 'http' || webUri.scheme == 'https') &&
              webUri.hasAuthority) {
            delegates.onOpenWebLink!(webUri);
          }
        }
      };
      final String recognizerKey = '$destination\u0000${node.title ?? ''}';
      recognizer = _acquireRecognizer(
        recognizerKey,
        onTap,
        recognizerPool,
        nextRecognizers,
      );
    }

    final Color linkColor = widget.theme.effectiveLinkColor;
    final TextStyle linkStyle = style.copyWith(
      color: linkColor,
      decoration: _combineDecoration(
        style.decoration,
        TextDecoration.underline,
      ),
      decorationColor: linkColor,
    );

    return TextSpan(
      style: linkStyle,
      children: _buildInlines(
        context,
        node.children,
        linkStyle,
        inlineHtmlDepth: inlineHtmlDepth,
        linkRecognizer: recognizer,
        onLinkTap: onTap,
        isLink: true,
        linkUrl: parsedUri,
        recognizerPool: recognizerPool,
        nextRecognizers: nextRecognizers,
        acc: acc,
      ),
    );
  }

  InlineSpan _buildFootnoteRefSpan(FootnoteRefNode node, TextStyle style) {
    final MarkdownThemeData theme = widget.theme;
    final double baseSize = style.fontSize ?? theme.fontSize;
    final String suffix = node.occurrenceIndex > 1
        ? '-${node.occurrenceIndex}'
        : '';
    final String refAnchorId = 'fnref-${node.label}$suffix';
    final String targetAnchorId = 'fn-${node.label}';

    void handleTap() {
      final MarkdownController? ctrl = widget.controller;
      if (ctrl != null) {
        unawaited(ctrl.scrollToAnchor(targetAnchorId));
      } else {
        widget.delegates.onTapLink?.call('#$targetAnchorId', null);
      }
    }

    final Widget badge = MarkdownAnchorTarget(
      slugs: <String>[refAnchorId],
      controller: widget.controller,
      child: MarkdownInteractiveAction(
        onActivate: handleTap,
        semanticLabel: 'Footnote ${node.index}',
        focusBorderColor: theme.accent,
        child: Transform.translate(
          offset: Offset(0.0, -baseSize * 0.28),
          child: MarkdownRichText(
            '[${node.index}]',
            style: style.copyWith(
              color: theme.effectiveLinkColor,
              fontSize: baseSize * 0.72,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
        ),
      ),
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: badge,
    );
  }

  Widget _wrapWidgetWithLink(
    Widget child, {
    required VoidCallback? onLinkTap,
    required bool isLink,
    Uri? linkUrl,
  }) {
    Widget current = child;
    if (onLinkTap != null) {
      current = FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: _linkActivateShortcuts,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (ActivateIntent _) {
              onLinkTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLinkTap,
          child: DefaultSelectionStyle.merge(
            mouseCursor: SystemMouseCursors.click,
            child: current,
          ),
        ),
      );
    }
    if (isLink) {
      current = Semantics(
        link: true,
        linkUrl: linkUrl,
        onTap: onLinkTap,
        child: current,
      );
    }
    return current;
  }
}

/// Builds a security-gated image widget respecting [MarkdownUrlPolicy],
/// [MarkdownImagePolicy], and optional [MarkdownBuilderDelegates.imageBuilder].
Widget buildMarkdownImageWidget({
  required BuildContext context,
  required ImageNode node,
  required MarkdownThemeData theme,
  required MarkdownBuilderDelegates delegates,
  required MarkdownUrlPolicy urlPolicy,
  required bool remoteImagesApproved,
  VoidCallback? onRequestLoadRemoteImages,
}) {
  final String destination = MarkdownBuilderDelegates.normalizeUrlDestination(
    node.destination,
  );
  if (destination.isEmpty || !urlPolicy.isAllowed(destination)) {
    return _ImagePlaceholderCard(
      theme: theme,
      title: node.alt.isNotEmpty ? node.alt : 'Image blocked',
      subtitle: 'Disallowed URL scheme',
      allowLoadAction: false,
    );
  }

  final bool isRemote = MarkdownBuilderDelegates.isRemoteImageUrl(destination);
  if (isRemote) {
    if (delegates.imagePolicy == MarkdownImagePolicy.block) {
      return _ImagePlaceholderCard(
        theme: theme,
        title: node.alt.isNotEmpty ? node.alt : 'Remote image blocked',
        subtitle: _displayHostOrPath(destination),
        allowLoadAction: false,
      );
    }
    if (delegates.imagePolicy == MarkdownImagePolicy.ask &&
        !remoteImagesApproved) {
      return _ImagePlaceholderCard(
        theme: theme,
        title: node.alt.isNotEmpty ? node.alt : 'Remote image',
        subtitle: _displayHostOrPath(destination),
        allowLoadAction: true,
        onLoadPressed: () {
          delegates.onLoadRemoteImages?.call();
          if (delegates.onLoadRemoteImages == null) {
            onRequestLoadRemoteImages?.call();
          }
        },
      );
    }
  }

  final MarkdownImageBuilder? customBuilder = delegates.imageBuilder;
  if (customBuilder != null) {
    return customBuilder(context, node);
  }

  final double? explicitWidth = node.width?.toDouble();
  final double? explicitHeight = node.height?.toDouble();

  if (destination.toLowerCase().startsWith('data:image/')) {
    final Uint8List? bytes = _decodeSafeDataImage(destination);
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: explicitWidth,
        height: explicitHeight,
        fit: BoxFit.contain,
        semanticLabel: node.alt.isEmpty ? null : node.alt,
        errorBuilder:
            (BuildContext ctx, Object error, StackTrace? stackTrace) =>
                _ImagePlaceholderCard(
                  theme: theme,
                  title: node.alt.isNotEmpty ? node.alt : 'Invalid image data',
                  subtitle: 'Unable to decode inline image',
                  allowLoadAction: false,
                ),
      );
    }
  }

  if (isRemote) {
    final String normalizedUrl = destination.startsWith('//')
        ? 'https:$destination'
        : destination;
    return Image.network(
      normalizedUrl,
      width: explicitWidth,
      height: explicitHeight,
      fit: BoxFit.contain,
      semanticLabel: node.alt.isEmpty ? null : node.alt,
      errorBuilder: (BuildContext ctx, Object error, StackTrace? stackTrace) =>
          _ImagePlaceholderCard(
            theme: theme,
            title: node.alt.isNotEmpty ? node.alt : 'Image unavailable',
            subtitle: _displayHostOrPath(normalizedUrl),
            allowLoadAction: false,
          ),
    );
  }

  return _ImagePlaceholderCard(
    theme: theme,
    title: node.alt.isNotEmpty ? node.alt : 'Local image',
    subtitle: destination,
    allowLoadAction: false,
  );
}

final class _ImagePlaceholderCard extends StatelessWidget {
  const _ImagePlaceholderCard({
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.allowLoadAction,
    this.onLoadPressed,
  });

  final MarkdownThemeData theme;
  final String title;
  final String subtitle;
  final bool allowLoadAction;
  final VoidCallback? onLoadPressed;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Semantics(
        container: true,
        label: title,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: theme.codeBackground,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: theme.border, width: 1.0),
          ),
          child: Wrap(
            spacing: 10.0,
            runSpacing: 6.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: theme.foreground,
                        fontSize: theme.fontSize * 0.88,
                        fontWeight: FontWeight.w600,
                        fontFamily: theme.fontFamily,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: theme.muted,
                          fontSize: theme.fontSize * 0.78,
                          fontFamily: theme.fontFamily,
                        ),
                      ),
                  ],
                ),
              ),
              if (allowLoadAction)
                MarkdownInteractiveAction(
                  onActivate: onLoadPressed,
                  semanticLabel: 'Load remote images',
                  focusBorderColor: theme.accent,
                  borderRadius: BorderRadius.circular(6.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 5.0,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(
                        color: theme.accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Load remote images',
                      style: TextStyle(
                        color: theme.accent,
                        fontSize: theme.fontSize * 0.8,
                        fontWeight: FontWeight.w600,
                        fontFamily: theme.fontFamily,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RawHtmlDirectiveKind {
  none,
  openUnderline,
  closeUnderline,
  openStrikethrough,
  closeStrikethrough,
  openStrong,
  closeStrong,
  openEmphasis,
  closeEmphasis,
  openSmall,
  closeSmall,
  openQuote,
  closeQuote,
  openCode,
  closeCode,
  openSamp,
  closeSamp,
  openVar,
  closeVar,
  openHighlight,
  closeHighlight,
  openSubscript,
  closeSubscript,
  openSuperscript,
  closeSuperscript,
  openAbbr,
  closeAbbr,
  anchor,
}

final class _RawHtmlDirective {
  const _RawHtmlDirective(this.kind, [this.value]);

  final _RawHtmlDirectiveKind kind;
  final String? value;

  static const _RawHtmlDirective none = _RawHtmlDirective(
    _RawHtmlDirectiveKind.none,
  );
}

final RegExp _rawAnchorAttrPattern = RegExp(
  r'''^<a\b[^>]*\b(?:id|name)\s*=\s*(?:"([^"]+)"|'([^']+)')[^>]*>$''',
  caseSensitive: false,
);
final RegExp _rawImgTagPattern = RegExp(
  r'''^<img\b([^>]*)/?>$''',
  caseSensitive: false,
);
final RegExp _rawHtmlAttrPattern = RegExp(
  r'''([a-zA-Z_:][a-zA-Z0-9_:\-.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
);

/// Extracts an [ImageNode] when [rawHtml] is a standalone HTML `<img>` tag.
ImageNode? tryParseHtmlImageTag(String rawHtml) {
  final RegExpMatch? tagMatch = _rawImgTagPattern.firstMatch(rawHtml.trim());
  if (tagMatch == null) {
    return null;
  }
  final String attrs = tagMatch.group(1) ?? '';
  String? src;
  String alt = '';
  String? title;
  int? width;
  int? height;

  for (final RegExpMatch match in _rawHtmlAttrPattern.allMatches(attrs)) {
    final String name = (match.group(1) ?? '').toLowerCase();
    final String value = decodeHtmlEntities(
      match.group(2) ?? match.group(3) ?? match.group(4) ?? '',
    );
    switch (name) {
      case 'src':
        src = value;
      case 'alt':
        alt = value;
      case 'title':
        title = value;
      case 'width':
        final int? parsedWidth = int.tryParse(value.trim());
        if (parsedWidth != null && parsedWidth > 0) {
          width = parsedWidth;
        }
      case 'height':
        final int? parsedHeight = int.tryParse(value.trim());
        if (parsedHeight != null && parsedHeight > 0) {
          height = parsedHeight;
        }
    }
  }

  if (src == null || src.trim().isEmpty) {
    return null;
  }
  return ImageNode(
    destination: src,
    alt: alt,
    title: title,
    width: width,
    height: height,
  );
}

bool _isInlineHtmlWhitespace(int cu) =>
    cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0C || cu == 0x0D;

const int _maxInlineHtmlDepth = 32;

Map<int, int> _computeRawHtmlPairCloses(
  List<MarkdownInlineNode> nodes,
  int start,
  int limit,
) {
  final Map<int, int> closeByOpen = <int, int>{};
  final List<int> subStack = <int>[];
  final List<int> supStack = <int>[];
  final List<int> abbrStack = <int>[];

  for (int i = start; i < limit; i++) {
    final MarkdownInlineNode candidate = nodes[i];
    if (candidate is! RawHtmlInlineNode) {
      continue;
    }
    switch (_parseRawHtmlDirective(candidate.html).kind) {
      case _RawHtmlDirectiveKind.openSubscript:
        subStack.add(i);
      case _RawHtmlDirectiveKind.closeSubscript:
        if (subStack.isNotEmpty) {
          closeByOpen[subStack.removeLast()] = i;
        }
      case _RawHtmlDirectiveKind.openSuperscript:
        supStack.add(i);
      case _RawHtmlDirectiveKind.closeSuperscript:
        if (supStack.isNotEmpty) {
          closeByOpen[supStack.removeLast()] = i;
        }
      case _RawHtmlDirectiveKind.openAbbr:
        abbrStack.add(i);
      case _RawHtmlDirectiveKind.closeAbbr:
        if (abbrStack.isNotEmpty) {
          closeByOpen[abbrStack.removeLast()] = i;
        }
      default:
        break;
    }
  }
  return closeByOpen;
}

String _inlinesSliceToPlainText(
  List<MarkdownInlineNode> nodes,
  int start,
  int end,
) {
  if (start >= end) {
    return '';
  }
  if (end - start == 1) {
    return nodes[start].toPlainText();
  }
  final StringBuffer out = StringBuffer();
  for (int i = start; i < end; i++) {
    out.write(nodes[i].toPlainText());
  }
  return out.toString();
}

_RawHtmlDirective _parseAbbrOpenDirective(String rawHtml, int start, int end) {
  int i = start;
  String? title;
  bool selfClosing = false;

  while (i < end) {
    while (i < end && _isInlineHtmlWhitespace(rawHtml.codeUnitAt(i))) {
      i++;
    }
    if (i >= end) {
      break;
    }
    final int cu = rawHtml.codeUnitAt(i);
    if (cu == 0x2F) {
      if (i == end - 1) {
        selfClosing = true;
      }
      i++;
      continue;
    }
    final int attrNameStart = i;
    while (i < end) {
      final int c = rawHtml.codeUnitAt(i);
      if (_isInlineHtmlWhitespace(c) || c == 0x3D || c == 0x2F) {
        break;
      }
      i++;
    }
    if (i == attrNameStart) {
      i++;
      continue;
    }
    final String attrName = rawHtml.substring(attrNameStart, i).toLowerCase();
    while (i < end && _isInlineHtmlWhitespace(rawHtml.codeUnitAt(i))) {
      i++;
    }
    String rawVal = '';
    if (i < end && rawHtml.codeUnitAt(i) == 0x3D) {
      i++;
      while (i < end && _isInlineHtmlWhitespace(rawHtml.codeUnitAt(i))) {
        i++;
      }
      if (i < end) {
        final int q = rawHtml.codeUnitAt(i);
        if (q == 0x22 || q == 0x27) {
          i++;
          final int valStart = i;
          while (i < end && rawHtml.codeUnitAt(i) != q) {
            i++;
          }
          rawVal = rawHtml.substring(valStart, i);
          if (i < end && rawHtml.codeUnitAt(i) == q) {
            i++;
          }
        } else {
          final int valStart = i;
          while (i < end && !_isInlineHtmlWhitespace(rawHtml.codeUnitAt(i))) {
            i++;
          }
          if (i == end && i > valStart && rawHtml.codeUnitAt(i - 1) == 0x2F) {
            rawVal = rawHtml.substring(valStart, i - 1);
            selfClosing = true;
          } else {
            rawVal = rawHtml.substring(valStart, i);
          }
        }
      }
    }
    if (attrName == 'title' && title == null) {
      title = decodeHtmlEntities(rawVal).trim();
    }
  }

  if (selfClosing) {
    return _RawHtmlDirective.none;
  }
  return _RawHtmlDirective(_RawHtmlDirectiveKind.openAbbr, title);
}

_RawHtmlDirective _parseRawHtmlDirective(String rawHtml) {
  final int len = rawHtml.length;
  if (len < 3 ||
      rawHtml.codeUnitAt(0) != 0x3C ||
      rawHtml.codeUnitAt(len - 1) != 0x3E) {
    return _RawHtmlDirective.none;
  }
  final bool isClosing = rawHtml.codeUnitAt(1) == 0x2F;
  final int nameStart = isClosing ? 2 : 1;
  int pos = nameStart;
  while (pos < len - 1) {
    final int cu = rawHtml.codeUnitAt(pos);
    if ((cu >= 0x41 && cu <= 0x5A) ||
        (cu >= 0x61 && cu <= 0x7A) ||
        (cu >= 0x30 && cu <= 0x39)) {
      pos++;
    } else {
      break;
    }
  }
  if (pos == nameStart) {
    return _RawHtmlDirective.none;
  }
  if (pos < len - 1) {
    final int afterCu = rawHtml.codeUnitAt(pos);
    if (!_isInlineHtmlWhitespace(afterCu) && (isClosing || afterCu != 0x2F)) {
      return _RawHtmlDirective.none;
    }
    if (isClosing) {
      int scan = pos;
      while (scan < len - 1) {
        if (!_isInlineHtmlWhitespace(rawHtml.codeUnitAt(scan))) {
          return _RawHtmlDirective.none;
        }
        scan++;
      }
    }
  }
  final String tag = rawHtml.substring(nameStart, pos).toLowerCase();
  final bool isSelfClosing = !isClosing && len >= 4 && rawHtml.endsWith('/>');
  switch (tag) {
    case 'u':
    case 'ins':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeUnderline);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openUnderline);
    case 'del':
    case 's':
    case 'strike':
      if (isClosing) {
        return const _RawHtmlDirective(
          _RawHtmlDirectiveKind.closeStrikethrough,
        );
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openStrikethrough);
    case 'strong':
    case 'b':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeStrong);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openStrong);
    case 'em':
    case 'i':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeEmphasis);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openEmphasis);
    case 'small':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeSmall);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openSmall);
    case 'q':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeQuote);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openQuote);
    case 'code':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeCode);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openCode);
    case 'samp':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeSamp);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openSamp);
    case 'var':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeVar);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openVar);
    case 'mark':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeHighlight);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openHighlight);
    case 'sub':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeSubscript);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openSubscript);
    case 'sup':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeSuperscript);
      }
      return isSelfClosing
          ? _RawHtmlDirective.none
          : const _RawHtmlDirective(_RawHtmlDirectiveKind.openSuperscript);
    case 'abbr':
      if (isClosing) {
        return const _RawHtmlDirective(_RawHtmlDirectiveKind.closeAbbr);
      }
      return _parseAbbrOpenDirective(rawHtml, pos, len - 1);
    case 'a':
      if (isClosing) {
        return _RawHtmlDirective.none;
      }
      final RegExpMatch? match = _rawAnchorAttrPattern.firstMatch(rawHtml);
      final String? id = match?.group(1) ?? match?.group(2);
      if (id != null && id.isNotEmpty) {
        return _RawHtmlDirective(_RawHtmlDirectiveKind.anchor, id);
      }
      return _RawHtmlDirective.none;
    default:
      return _RawHtmlDirective.none;
  }
}

TextDecoration _combineDecoration(
  TextDecoration? existing,
  TextDecoration addition,
) {
  if (existing == null || existing == TextDecoration.none) {
    return addition;
  }
  return TextDecoration.combine(<TextDecoration>[existing, addition]);
}

String _displayHostOrPath(String url) {
  final Uri? uri = Uri.tryParse(url.startsWith('//') ? 'https:$url' : url);
  if (uri != null && uri.host.isNotEmpty) {
    return uri.host;
  }
  return url;
}

const int _maxDataImageCacheEntries = 64;
const int _maxCachedDataImageBytes = 512 * 1024;
final Map<String, Uint8List> _decodedDataImageCache = <String, Uint8List>{};

Uint8List? _decodeSafeDataImage(String dataUrl) {
  final Uint8List? cached = _decodedDataImageCache.remove(dataUrl);
  if (cached != null) {
    _decodedDataImageCache[dataUrl] = cached;
    return cached;
  }
  try {
    final UriData data = UriData.parse(dataUrl);
    final Uint8List bytes = data.contentAsBytes();
    if (bytes.length <= _maxCachedDataImageBytes) {
      if (_decodedDataImageCache.length >= _maxDataImageCacheEntries) {
        _decodedDataImageCache.remove(_decodedDataImageCache.keys.first);
      }
      _decodedDataImageCache[dataUrl] = bytes;
    }
    return bytes;
  } on FormatException {
    return null;
  }
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
