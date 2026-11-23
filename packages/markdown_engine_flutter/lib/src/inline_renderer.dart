import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
// Keeps Tooltip compatibility with Flutter 3.32-3.50+ callers.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'controller.dart';
import 'delegates.dart';
import 'theme.dart';

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

  @override
  State<MarkdownInlineText> createState() => _MarkdownInlineTextState();
}

final class _MarkdownInlineTextState extends State<MarkdownInlineText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final TapGestureRecognizer recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final List<InlineSpan> spans = _buildInlines(
      context,
      widget.nodes,
      widget.baseStyle,
      linkRecognizer: null,
      onLinkTap: null,
    );
    return Text.rich(
      TextSpan(style: widget.baseStyle, children: spans),
      textAlign: widget.textAlign,
    );
  }

  List<InlineSpan> _buildInlines(
    BuildContext context,
    List<MarkdownInlineNode> nodes,
    TextStyle style, {
    required TapGestureRecognizer? linkRecognizer,
    required VoidCallback? onLinkTap,
  }) {
    if (nodes.isEmpty) {
      return const <InlineSpan>[];
    }
    final List<InlineSpan> result = <InlineSpan>[];
    for (final MarkdownInlineNode node in nodes) {
      result.add(
        _buildInline(
          context,
          node,
          style,
          linkRecognizer: linkRecognizer,
          onLinkTap: onLinkTap,
        ),
      );
    }
    return result;
  }

  InlineSpan _buildInline(
    BuildContext context,
    MarkdownInlineNode node,
    TextStyle style, {
    required TapGestureRecognizer? linkRecognizer,
    required VoidCallback? onLinkTap,
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
            linkRecognizer: linkRecognizer,
            onLinkTap: onLinkTap,
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
            linkRecognizer: linkRecognizer,
            onLinkTap: onLinkTap,
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
            linkRecognizer: linkRecognizer,
            onLinkTap: onLinkTap,
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
            linkRecognizer: linkRecognizer,
            onLinkTap: onLinkTap,
          ),
        );
      case SubscriptNode():
        return _buildScriptSpan(
          context,
          node.children,
          style,
          isSuperscript: false,
          onLinkTap: onLinkTap,
        );
      case SuperscriptNode():
        return _buildScriptSpan(
          context,
          node.children,
          style,
          isSuperscript: true,
          onLinkTap: onLinkTap,
        );
      case LinkNode():
        return _buildLinkSpan(context, node, style);
      case ImageNode():
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
          ),
        );
      case PictureInlineNode():
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
          ),
        );
      case MathInlineNode():
        final MarkdownMathInlineBuilder? builder = delegates.mathInlineBuilder;
        if (builder != null) {
          return builder(context, node, style, linkRecognizer);
        }
        final double baseSize = style.fontSize ?? theme.fontSize;
        final Widget mathChip = Semantics(
          label: 'Math: ${node.latex}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
            decoration: BoxDecoration(
              color: theme.codeBackground,
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Text(
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
          child: _wrapWidgetWithLink(mathChip, onLinkTap: onLinkTap),
        );
      case FootnoteRefNode():
        return _buildFootnoteRefSpan(node, style);
      case KbdInlineNode():
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
          linkRecognizer: null,
          onLinkTap: null,
        );
        final Widget keycap = Semantics(
          label: 'Key ${node.toPlainText()}',
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
            child: Text.rich(TextSpan(style: kbdStyle, children: kbdChildren)),
          ),
        );
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _wrapWidgetWithLink(keycap, onLinkTap: onLinkTap),
        );
      case AbbrInlineNode():
        final TextStyle abbrStyle = style.copyWith(
          decoration: _combineDecoration(
            style.decoration,
            TextDecoration.underline,
          ),
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: theme.muted,
        );
        final List<InlineSpan> abbrChildren = _buildInlines(
          context,
          node.children,
          abbrStyle,
          linkRecognizer: null,
          onLinkTap: null,
        );
        Widget labelWidget = Text.rich(
          TextSpan(style: abbrStyle, children: abbrChildren),
        );
        if (Overlay.maybeOf(context) != null) {
          labelWidget = Tooltip(message: node.title, child: labelWidget);
        }
        final Widget semanticAbbr = Semantics(
          label: node.toPlainText(),
          tooltip: node.title,
          hint: node.title,
          child: labelWidget,
        );
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _wrapWidgetWithLink(semanticAbbr, onLinkTap: onLinkTap),
        );
      case AnchorInlineNode():
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: MarkdownAnchorTarget(
            slugs: <String>[node.id],
            controller: widget.controller,
            child: const SizedBox.shrink(),
          ),
        );
      case RawHtmlInlineNode():
        return const TextSpan();
    }
  }

  InlineSpan _buildScriptSpan(
    BuildContext context,
    List<MarkdownInlineNode> children,
    TextStyle style, {
    required bool isSuperscript,
    required VoidCallback? onLinkTap,
  }) {
    final double baseSize = style.fontSize ?? widget.theme.fontSize;
    final TextStyle scriptStyle = style.copyWith(
      fontSize: baseSize * 0.74,
      height: 1.0,
    );
    final List<InlineSpan> childSpans = _buildInlines(
      context,
      children,
      scriptStyle,
      linkRecognizer: null,
      onLinkTap: null,
    );
    final double dy = isSuperscript ? -baseSize * 0.3 : baseSize * 0.2;
    final Widget scriptWidget = Transform.translate(
      offset: Offset(0.0, dy),
      child: Text.rich(TextSpan(style: scriptStyle, children: childSpans)),
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _wrapWidgetWithLink(scriptWidget, onLinkTap: onLinkTap),
    );
  }

  InlineSpan _buildLinkSpan(
    BuildContext context,
    LinkNode node,
    TextStyle style,
  ) {
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
          linkRecognizer: null,
          onLinkTap: null,
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
        (isFragment && controller != null);

    VoidCallback? onTap;
    TapGestureRecognizer? recognizer;

    if (hasAction) {
      onTap = () {
        if (!policy.isAllowed(destination)) {
          return;
        }
        if (delegates.onTapLink != null) {
          delegates.onTapLink!(destination, node.title);
        } else if (isFragment && controller != null) {
          unawaited(controller.scrollToAnchor(destination.substring(1)));
        }
        if (isWeb && delegates.onOpenWebLink != null) {
          final Uri? webUri = Uri.tryParse(destination);
          if (webUri != null &&
              (webUri.scheme == 'http' || webUri.scheme == 'https') &&
              webUri.hasAuthority) {
            delegates.onOpenWebLink!(webUri);
          }
        }
      };
      recognizer = TapGestureRecognizer()..onTap = onTap;
      _recognizers.add(recognizer);
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
        linkRecognizer: recognizer,
        onLinkTap: onTap,
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
      child: Semantics(
        button: true,
        label: 'Footnote ${node.index}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: handleTap,
            child: Transform.translate(
              offset: Offset(0.0, -baseSize * 0.28),
              child: Text(
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
        ),
      ),
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: badge,
    );
  }

  Widget _wrapWidgetWithLink(Widget child, {required VoidCallback? onLinkTap}) {
    if (onLinkTap == null) {
      return child;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onLinkTap,
        child: child,
      ),
    );
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
  final String destination = node.destination.trim();
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
    return Semantics(
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
            Column(
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
            if (allowLoadAction)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onLoadPressed,
                  child: Semantics(
                    button: true,
                    label: 'Load remote images',
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
                ),
              ),
          ],
        ),
      ),
    );
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

Uint8List? _decodeSafeDataImage(String dataUrl) {
  try {
    final UriData data = UriData.parse(dataUrl);
    return data.contentAsBytes();
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
