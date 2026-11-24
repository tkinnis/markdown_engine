import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'built_in_math.dart';
import 'built_in_mermaid.dart';
import 'controller.dart';
import 'delegates.dart';
import 'fast_text.dart';
import 'html_block_renderer.dart';
import 'inline_renderer.dart';
import 'theme.dart';

/// Shared rendering configuration passed recursively through block builders.
@immutable
final class MarkdownBlockRenderContext {
  /// Creates a [MarkdownBlockRenderContext].
  const MarkdownBlockRenderContext({
    required this.theme,
    required this.delegates,
    required this.urlPolicy,
    this.controller,
    this.textAlign = TextAlign.start,
    this.listDepth = 0,
    this.remoteImagesApproved = false,
    this.onRequestLoadRemoteImages,
    this.streamingNormalizedSource,
    this.streamingNormalizedSourceProvider,
    this.environment,
    this.resolvedBodyStyle,
  });

  /// Active visual theme.
  final MarkdownThemeData theme;

  /// Pluggable builders and security callbacks.
  final MarkdownBuilderDelegates delegates;

  /// Effective URL policy gating interactive links and images.
  final MarkdownUrlPolicy urlPolicy;

  /// Optional navigation and reading-place controller.
  final MarkdownController? controller;

  /// Inherited horizontal alignment from enclosing containers.
  final TextAlign textAlign;

  /// Current list nesting depth (`0` at top level).
  final int listDepth;

  /// Whether remote images were locally approved in `ask` mode.
  final bool remoteImagesApproved;

  /// Callback invoked when the user approves remote images in `ask` mode.
  final VoidCallback? onRequestLoadRemoteImages;

  /// Normalized source text for unfinished active-tail streaming blocks, or
  /// `null` for settled or complete documents.
  final String? streamingNormalizedSource;

  /// Lazy provider returning active streaming normalized source only when a
  /// block (such as an unclosed Mermaid fence) requires it.
  final String? Function()? streamingNormalizedSourceProvider;

  /// Pre-resolved ambient Flutter environment hoisted at the document root.
  final MarkdownRenderEnvironment? environment;

  /// Optional pre-merged body text style avoiding repeated `TextStyle.merge`.
  final TextStyle? resolvedBodyStyle;

  /// Returns a derived context with selected fields overridden.
  MarkdownBlockRenderContext copyWith({
    MarkdownThemeData? theme,
    TextAlign? textAlign,
    int? listDepth,
    TextStyle? resolvedBodyStyle,
  }) {
    final MarkdownThemeData nextTheme = theme ?? this.theme;
    final TextStyle? nextBodyStyle =
        resolvedBodyStyle ??
        (theme != null && environment != null
            ? environment!.resolveTextStyle(nextTheme.bodyTextStyle())
            : (theme == null ? this.resolvedBodyStyle : null));
    return MarkdownBlockRenderContext(
      theme: nextTheme,
      delegates: delegates,
      urlPolicy: urlPolicy,
      controller: controller,
      textAlign: textAlign ?? this.textAlign,
      listDepth: listDepth ?? this.listDepth,
      remoteImagesApproved: remoteImagesApproved,
      onRequestLoadRemoteImages: onRequestLoadRemoteImages,
      streamingNormalizedSource: streamingNormalizedSource,
      streamingNormalizedSourceProvider: streamingNormalizedSourceProvider,
      environment: environment,
      resolvedBodyStyle: nextBodyStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownBlockRenderContext &&
          theme == other.theme &&
          delegates == other.delegates &&
          urlPolicy == other.urlPolicy &&
          identical(controller, other.controller) &&
          textAlign == other.textAlign &&
          listDepth == other.listDepth &&
          remoteImagesApproved == other.remoteImagesApproved &&
          onRequestLoadRemoteImages == other.onRequestLoadRemoteImages &&
          streamingNormalizedSource == other.streamingNormalizedSource &&
          streamingNormalizedSourceProvider ==
              other.streamingNormalizedSourceProvider &&
          environment == other.environment &&
          resolvedBodyStyle == other.resolvedBodyStyle;

  @override
  int get hashCode => Object.hash(
    theme,
    delegates,
    urlPolicy,
    controller,
    textAlign,
    listDepth,
    remoteImagesApproved,
    onRequestLoadRemoteImages,
    streamingNormalizedSource,
    streamingNormalizedSourceProvider,
    environment,
    resolvedBodyStyle,
  );
}

List<String> _headingSlugs(HeadingNode node) {
  final Set<String> slugSet = <String>{
    if (node.slug != null && node.slug!.isNotEmpty) node.slug!,
    if (node.explicitId != null && node.explicitId!.isNotEmpty)
      node.explicitId!,
    slugifyHeadingText(node.text),
  };
  return slugSet.toList(growable: false);
}

/// Builds a top-level Markdown block widget, avoiding stateful wrapper
/// overhead when [MarkdownBlockRenderContext.controller] is `null`.
Widget buildTopLevelMarkdownBlockWidget(
  BuildContext context, {
  Key? key,
  required MarkdownBlockNode node,
  required MarkdownBlockRenderContext renderContext,
  required double bottomSpacing,
  Widget? prebuiltInner,
}) {
  if (renderContext.controller != null) {
    return MarkdownTopLevelBlockWidget(
      key: key,
      node: node,
      renderContext: renderContext,
      bottomSpacing: bottomSpacing,
      prebuiltInner: prebuiltInner,
    );
  }
  final Widget inner =
      prebuiltInner ??
      buildMarkdownBlockWidget(context, node, renderContext, isTopLevel: true);
  if (bottomSpacing <= 0.0 && key == null) {
    return inner;
  }
  return Padding(
    key: key,
    padding: bottomSpacing <= 0.0
        ? EdgeInsets.zero
        : EdgeInsets.only(bottom: bottomSpacing),
    child: inner,
  );
}

/// Top-level block wrapper registering its [MarkdownBlockNode.blockId] with
/// [MarkdownController] while mounted inside a sliver or column.
final class MarkdownTopLevelBlockWidget extends StatefulWidget {
  /// Creates a [MarkdownTopLevelBlockWidget].
  const MarkdownTopLevelBlockWidget({
    super.key,
    required this.node,
    required this.renderContext,
    required this.bottomSpacing,
    this.prebuiltInner,
  });

  /// Block AST node to render.
  final MarkdownBlockNode node;

  /// Shared rendering context.
  final MarkdownBlockRenderContext renderContext;

  /// Bottom spacing applied after this block (`0.0` for the final block).
  final double bottomSpacing;

  /// Optional pre-built inner block widget reused across bottom-spacing edits.
  final Widget? prebuiltInner;

  @override
  State<MarkdownTopLevelBlockWidget> createState() =>
      _MarkdownTopLevelBlockWidgetState();
}

final class _MarkdownTopLevelBlockWidgetState
    extends State<MarkdownTopLevelBlockWidget> {
  Widget? _cachedInnerBlock;
  Widget? _cachedPaddedBlock;
  MarkdownBlockNode? _cachedNode;
  MarkdownBlockRenderContext? _cachedRenderContext;
  double? _cachedBottomSpacing;
  MarkdownRenderEnvironment? _cachedEnvironment;
  List<String>? _registeredHeadingSlugs;

  @override
  void initState() {
    super.initState();
    _registerWithController(widget.renderContext.controller, widget.node);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.renderContext.environment == null) {
      _cachedInnerBlock = null;
      _cachedPaddedBlock = null;
    }
  }

  @override
  void didUpdateWidget(MarkdownTopLevelBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool ctrlChanged = !identical(
      oldWidget.renderContext.controller,
      widget.renderContext.controller,
    );
    final bool blockIdChanged = oldWidget.node.blockId != widget.node.blockId;
    final bool headingChanged =
        (oldWidget.node is HeadingNode || widget.node is HeadingNode) &&
        !identical(oldWidget.node, widget.node);
    if (ctrlChanged || blockIdChanged || headingChanged) {
      _unregisterFromController(
        oldWidget.renderContext.controller,
        oldWidget.node,
      );
      _registerWithController(widget.renderContext.controller, widget.node);
    }
  }

  @override
  void dispose() {
    _cachedInnerBlock = null;
    _cachedPaddedBlock = null;
    _unregisterFromController(widget.renderContext.controller, widget.node);
    super.dispose();
  }

  void _registerWithController(
    MarkdownController? controller,
    MarkdownBlockNode node,
  ) {
    if (controller == null) {
      return;
    }
    controller.registerBlock(node.blockId, context);
    if (node is HeadingNode) {
      final List<String> slugs = _headingSlugs(node);
      _registeredHeadingSlugs = slugs;
      for (final String slug in slugs) {
        if (slug.isNotEmpty) {
          controller.registerAnchor(slug, context);
        }
      }
    } else {
      _registeredHeadingSlugs = null;
    }
  }

  void _unregisterFromController(
    MarkdownController? controller,
    MarkdownBlockNode node,
  ) {
    if (controller == null) {
      _registeredHeadingSlugs = null;
      return;
    }
    controller.unregisterBlock(node.blockId, context);
    final List<String>? slugs = _registeredHeadingSlugs;
    if (slugs != null) {
      for (final String slug in slugs) {
        if (slug.isNotEmpty) {
          controller.unregisterAnchor(slug, context);
        }
      }
      _registeredHeadingSlugs = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final MarkdownRenderEnvironment env =
        widget.renderContext.environment ??
        MarkdownRenderEnvironment.resolve(context);

    final bool innerValid =
        _cachedInnerBlock != null &&
        identical(widget.node, _cachedNode) &&
        widget.renderContext == _cachedRenderContext &&
        env == _cachedEnvironment;

    if (innerValid &&
        _cachedPaddedBlock != null &&
        widget.bottomSpacing == _cachedBottomSpacing) {
      return _cachedPaddedBlock!;
    }

    final Widget blockWidget =
        widget.prebuiltInner ??
        (innerValid
            ? _cachedInnerBlock!
            : buildMarkdownBlockWidget(
                context,
                widget.node,
                widget.renderContext,
                isTopLevel: true,
              ));

    final Widget result = Padding(
      padding: widget.bottomSpacing <= 0.0
          ? EdgeInsets.zero
          : EdgeInsets.only(bottom: widget.bottomSpacing),
      child: blockWidget,
    );

    _cachedInnerBlock = blockWidget;
    _cachedPaddedBlock = result;
    _cachedNode = widget.node;
    _cachedRenderContext = widget.renderContext;
    _cachedBottomSpacing = widget.bottomSpacing;
    _cachedEnvironment = env;
    return result;
  }
}

/// Builds a native Flutter widget for any [MarkdownBlockNode].
Widget buildMarkdownBlockWidget(
  BuildContext context,
  MarkdownBlockNode node,
  MarkdownBlockRenderContext renderContext, {
  bool isTopLevel = false,
}) {
  final MarkdownThemeData theme = renderContext.theme;

  switch (node) {
    case FrontmatterNode():
      return _buildFrontmatterCard(node, theme);
    case HeadingNode():
      return _buildHeading(
        context,
        node,
        renderContext,
        isTopLevel: isTopLevel,
      );
    case ParagraphNode():
      return _buildParagraph(context, node, renderContext);
    case CodeBlockNode():
      return _buildCodeBlock(context, node, renderContext);
    case BlockQuoteNode():
      return _buildBlockQuote(context, node, renderContext);
    case AlertNode():
      return _buildAlert(context, node, renderContext);
    case ListNode():
      return _buildList(context, node, renderContext);
    case ListItemNode():
      return _buildListItem(
        context,
        node,
        renderContext,
        ordered: false,
        index: 0,
        start: 1,
        delimiter: '-',
        tight: false,
      );
    case TableNode():
      return _buildTable(context, node, renderContext);
    case ThematicBreakNode():
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: ColoredBox(
          color: theme.border,
          child: const SizedBox(width: double.infinity, height: 1.0),
        ),
      );
    case HtmlBlockNode():
      return _buildHtmlBlockFallback(context, node, renderContext);
    case DetailsBlockNode():
      return _MarkdownDetailsBlock(
        key: ValueKey<String>('details-${node.blockId}'),
        node: node,
        renderContext: renderContext,
      );
    case AlignedBlockNode():
      return _buildAlignedBlock(context, node, renderContext);
    case FigureBlockNode():
      return _buildFigureBlock(context, node, renderContext);
    case MathBlockNode():
      return _buildMathBlock(context, node, renderContext);
    case DefinitionListNode():
      return _buildDefinitionList(context, node, renderContext);
    case FootnoteDefinitionNode():
      return _buildFootnoteDefinition(context, node, renderContext);
    case FootnoteSectionNode():
      return _buildFootnoteSection(context, node, renderContext);
  }
}

Widget _buildBlockColumn(
  BuildContext context,
  List<MarkdownBlockNode> blocks,
  MarkdownBlockRenderContext renderContext, {
  double? spacing,
  CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.stretch,
}) {
  if (blocks.isEmpty) {
    return const SizedBox.shrink();
  }
  if (blocks.length == 1) {
    return buildMarkdownBlockWidget(context, blocks.first, renderContext);
  }
  final double gap = spacing ?? renderContext.theme.blockSpacing * 0.75;
  return Column(
    crossAxisAlignment: crossAxisAlignment,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (int i = 0; i < blocks.length; i++)
        i < blocks.length - 1
            ? Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: buildMarkdownBlockWidget(
                  context,
                  blocks[i],
                  renderContext,
                ),
              )
            : buildMarkdownBlockWidget(context, blocks[i], renderContext),
    ],
  );
}

Widget _buildFrontmatterCard(FrontmatterNode node, MarkdownThemeData theme) {
  final Map<String, Object?> entries = node.entries;
  final String formatLabel = node.format.toUpperCase();

  return Semantics(
    container: true,
    label: '$formatLabel frontmatter metadata',
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: theme.codeBackground.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 2.0,
                ),
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: MarkdownRichText(
                  formatLabel,
                  style: TextStyle(
                    color: theme.accent,
                    fontSize: theme.fontSize * 0.72,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    fontFamily: theme.fontFamily,
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              MarkdownRichText(
                'Frontmatter',
                style: TextStyle(
                  color: theme.muted,
                  fontSize: theme.fontSize * 0.8,
                  fontWeight: FontWeight.w600,
                  fontFamily: theme.fontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          if (entries.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final MapEntry<String, Object?> entry in entries.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: _buildFrontmatterRow(entry.key, entry.value, theme),
                  ),
              ],
            )
          else if (node.raw.trim().isNotEmpty)
            MarkdownRichText(
              node.raw.trim(),
              style: theme.codeTextStyle(
                fontSizeOverride: theme.fontSize * 0.82,
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _buildFrontmatterRow(
  String key,
  Object? value,
  MarkdownThemeData theme,
) {
  final TextStyle keyStyle = TextStyle(
    color: theme.muted,
    fontSize: theme.fontSize * 0.85,
    fontWeight: FontWeight.w600,
    fontFamily: theme.fontFamily,
  );
  final TextStyle valStyle = TextStyle(
    color: theme.foreground,
    fontSize: theme.fontSize * 0.85,
    fontFamily: theme.fontFamily,
  );

  if (value is List<Object?>) {
    return Wrap(
      spacing: 6.0,
      runSpacing: 4.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        MarkdownRichText('$key:', style: keyStyle),
        for (final Object? item in value)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
            decoration: BoxDecoration(
              color: theme.border.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999.0),
            ),
            child: MarkdownRichText('$item', style: valStyle),
          ),
      ],
    );
  }

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      MarkdownRichText('$key: ', style: keyStyle),
      Expanded(child: MarkdownRichText('${value ?? ''}', style: valStyle)),
    ],
  );
}

Widget _buildHeading(
  BuildContext context,
  HeadingNode node,
  MarkdownBlockRenderContext renderContext, {
  bool isTopLevel = false,
}) {
  final MarkdownThemeData theme = renderContext.theme;
  final Widget headingContent;
  if (canBuildFastSimpleInlines(node.children)) {
    final MarkdownRenderEnvironment env =
        renderContext.environment ?? MarkdownRenderEnvironment.resolve(context);
    final TextStyle effectiveStyle = env.resolveTextStyle(
      theme.headingTextStyle(node.level),
    );
    final ({InlineSpan span, String plainText}) built =
        buildFastSimpleInlineSpan(node.children, effectiveStyle, theme);
    headingContent = Semantics(
      header: true,
      headingLevel: node.level.clamp(1, 6),
      child: FastMarkdownText(
        span: built.span,
        plainText: built.plainText,
        effectiveStyle: effectiveStyle,
        resolvedTextAlign: renderContext.textAlign,
        resolvedTextDirection: env.textDirection,
        resolvedTextScaler: env.textScaler,
        resolvedLocale: env.locale,
        selectionRegistrar: env.selectionRegistrar,
        selectionColor: env.selectionColor,
        useLeafRenderBox: true,
        topPadding: node.level <= 2 ? 8.0 : 4.0,
        dividerSpacing: node.level <= 2 ? 6.0 : 0.0,
        dividerColor: node.level <= 2 ? theme.border : null,
      ),
    );
  } else {
    headingContent = Semantics(
      header: true,
      headingLevel: node.level.clamp(1, 6),
      child: Padding(
        padding: EdgeInsets.only(top: node.level <= 2 ? 8.0 : 4.0),
        child: Column(
          crossAxisAlignment: _crossAxisForTextAlign(renderContext.textAlign),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MarkdownInlineText(
              nodes: node.children,
              baseStyle: theme.headingTextStyle(node.level),
              theme: theme,
              delegates: renderContext.delegates,
              urlPolicy: renderContext.urlPolicy,
              controller: renderContext.controller,
              textAlign: renderContext.textAlign,
              remoteImagesApproved: renderContext.remoteImagesApproved,
              onRequestLoadRemoteImages:
                  renderContext.onRequestLoadRemoteImages,
              environment: renderContext.environment,
            ),
            if (node.level <= 2) ...<Widget>[
              const SizedBox(height: 6.0),
              ColoredBox(
                color: theme.border,
                child: const SizedBox(width: double.infinity, height: 1.0),
              ),
            ],
          ],
        ),
      ),
    );
  }

  if (isTopLevel || renderContext.controller == null) {
    return headingContent;
  }

  return MarkdownAnchorTarget(
    slugs: _headingSlugs(node),
    controller: renderContext.controller,
    child: headingContent,
  );
}

Widget _buildParagraph(
  BuildContext context,
  ParagraphNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  if (node.children.length == 1) {
    final MarkdownInlineNode single = node.children.first;
    if (single is ImageNode) {
      return Align(
        alignment: _alignmentForTextAlign(renderContext.textAlign),
        child: buildMarkdownImageWidget(
          context: context,
          node: single,
          theme: theme,
          delegates: renderContext.delegates,
          urlPolicy: renderContext.urlPolicy,
          remoteImagesApproved: renderContext.remoteImagesApproved,
          onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
        ),
      );
    }
    if (single is PictureInlineNode) {
      final String chosen = theme.brightness == Brightness.dark
          ? (single.darkSource.isNotEmpty
                ? single.darkSource
                : single.lightSource)
          : (single.lightSource.isNotEmpty
                ? single.lightSource
                : single.darkSource);
      return Align(
        alignment: _alignmentForTextAlign(renderContext.textAlign),
        child: buildMarkdownImageWidget(
          context: context,
          node: ImageNode(
            destination: chosen,
            alt: single.alt,
            span: single.span,
          ),
          theme: theme,
          delegates: renderContext.delegates,
          urlPolicy: renderContext.urlPolicy,
          remoteImagesApproved: renderContext.remoteImagesApproved,
          onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
        ),
      );
    }
  }

  return buildFastOrRichInlineText(
    context,
    nodes: node.children,
    baseStyle: theme.bodyTextStyle(),
    theme: theme,
    delegates: renderContext.delegates,
    urlPolicy: renderContext.urlPolicy,
    controller: renderContext.controller,
    textAlign: renderContext.textAlign,
    remoteImagesApproved: renderContext.remoteImagesApproved,
    onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
    environment: renderContext.environment,
    effectiveStyleOverride: renderContext.resolvedBodyStyle,
  );
}

Widget _buildCodeBlock(
  BuildContext context,
  CodeBlockNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownDiagramBuilder? diagramBuilder =
      renderContext.delegates.diagramBuilder;
  if (diagramBuilder != null) {
    final Widget? diagram = diagramBuilder(context, node);
    if (diagram != null) {
      return diagram;
    }
  }

  if (renderContext.delegates.enableBuiltInMermaid &&
      node.language?.toLowerCase() == 'mermaid') {
    final String? streamSource =
        renderContext.streamingNormalizedSourceProvider?.call() ??
        renderContext.streamingNormalizedSource;
    final bool isStreamingIncomplete =
        streamSource != null && !isFencedCodeBlockClosed(streamSource, node);
    return BuiltInMermaidDiagram(
      key: ValueKey<String>('mermaid-${node.blockId}'),
      node: node,
      theme: renderContext.theme,
      isStreamingIncomplete: isStreamingIncomplete,
    );
  }

  final MarkdownCodeBlockBuilder? codeBuilder =
      renderContext.delegates.codeBlockBuilder;
  if (codeBuilder != null) {
    return codeBuilder(context, node);
  }

  return _MarkdownCodeBlock(
    key: ValueKey<String>('code-${node.blockId}'),
    node: node,
    theme: renderContext.theme,
    environment: renderContext.environment,
  );
}

final class _MarkdownCodeBlock extends StatefulWidget {
  const _MarkdownCodeBlock({
    super.key,
    required this.node,
    required this.theme,
    this.environment,
  });

  final CodeBlockNode node;
  final MarkdownThemeData theme;
  final MarkdownRenderEnvironment? environment;

  @override
  State<_MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

final class _MarkdownCodeBlockState extends State<_MarkdownCodeBlock> {
  bool _copied = false;
  Timer? _resetTimer;

  Widget? _cachedHeader;
  MarkdownThemeData? _headerTheme;
  String? _headerBadgeText;
  bool? _headerCopied;
  TextDirection? _headerDir;
  TextScaler? _headerScaler;
  Locale? _headerLocale;
  TextStyle? _headerDefaultStyle;
  bool? _headerBoldText;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copyCode() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.node.literal)));
    _resetTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  Widget _buildHeader(
    MarkdownThemeData theme,
    MarkdownRenderEnvironment env,
    String badgeText,
  ) {
    final Widget? cached = _cachedHeader;
    if (cached != null &&
        _headerTheme == theme &&
        _headerBadgeText == badgeText &&
        _headerCopied == _copied &&
        _headerDir == env.textDirection &&
        _headerScaler == env.textScaler &&
        _headerLocale == env.locale &&
        _headerDefaultStyle == env.defaultTextStyle &&
        _headerBoldText == env.boldText) {
      return cached;
    }

    final TextStyle badgeStyle = env.resolveTextStyle(
      TextStyle(
        color: theme.muted,
        fontSize: theme.codeFontSize * 0.8,
        fontWeight: FontWeight.w600,
        fontFamily: theme.effectiveCodeFontFamily,
        fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
      ),
    );
    final String copyLabel = _copied ? 'Copied' : 'Copy';
    final TextStyle copyStyle = env.resolveTextStyle(
      TextStyle(
        color: _copied ? theme.accent : theme.muted,
        fontSize: theme.fontSize * 0.78,
        fontWeight: FontWeight.w600,
        fontFamily: theme.fontFamily,
      ),
    );

    final Widget header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          SelectionContainer.disabled(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.border.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  child: FastMarkdownText(
                    span: TextSpan(text: badgeText, style: badgeStyle),
                    plainText: badgeText,
                    effectiveStyle: badgeStyle,
                    resolvedTextAlign: TextAlign.start,
                    resolvedTextDirection: env.textDirection,
                    resolvedTextScaler: env.textScaler,
                    resolvedLocale: env.locale,
                    selectionRegistrar: null,
                  ),
                ),
              ),
            ),
          ),
          SelectionContainer.disabled(
            child: MarkdownInteractiveAction(
              onActivate: _copyCode,
              semanticLabel: _copied ? 'Copied' : 'Copy code',
              focusBorderColor: theme.accent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 2.0,
                ),
                child: FastMarkdownText(
                  span: TextSpan(text: copyLabel, style: copyStyle),
                  plainText: copyLabel,
                  effectiveStyle: copyStyle,
                  resolvedTextAlign: TextAlign.start,
                  resolvedTextDirection: env.textDirection,
                  resolvedTextScaler: env.textScaler,
                  resolvedLocale: env.locale,
                  selectionRegistrar: null,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    _cachedHeader = header;
    _headerTheme = theme;
    _headerBadgeText = badgeText;
    _headerCopied = _copied;
    _headerDir = env.textDirection;
    _headerScaler = env.textScaler;
    _headerLocale = env.locale;
    _headerDefaultStyle = env.defaultTextStyle;
    _headerBoldText = env.boldText;
    return header;
  }

  @override
  Widget build(BuildContext context) {
    final MarkdownThemeData theme = widget.theme;
    final MarkdownRenderEnvironment env =
        widget.environment ?? MarkdownRenderEnvironment.resolve(context);
    final String? lang = widget.node.language;
    final String badgeText = (lang != null && lang.isNotEmpty) ? lang : 'code';
    final String trimmed = widget.node.literal.endsWith('\n')
        ? widget.node.literal.substring(0, widget.node.literal.length - 1)
        : widget.node.literal;
    final TextStyle codeStyle = env.resolveTextStyle(theme.codeTextStyle());

    return Container(
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
          _buildHeader(theme, env, badgeText),
          MarkdownHorizontalOverflowBox(
            padding: const EdgeInsets.all(12.0),
            child: FastMarkdownText(
              span: TextSpan(text: trimmed, style: codeStyle),
              plainText: trimmed,
              effectiveStyle: codeStyle,
              resolvedTextAlign: TextAlign.start,
              resolvedTextDirection: env.textDirection,
              resolvedTextScaler: env.textScaler,
              resolvedLocale: env.locale,
              selectionRegistrar: env.selectionRegistrar,
              selectionColor: env.selectionColor,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildBlockQuote(
  BuildContext context,
  BlockQuoteNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  if (node.children.length == 1 && node.children.first is ParagraphNode) {
    final ParagraphNode para = node.children.first as ParagraphNode;
    if (canBuildFastSimpleInlines(para.children)) {
      final MarkdownRenderEnvironment env =
          renderContext.environment ??
          MarkdownRenderEnvironment.resolve(context);
      final MarkdownThemeData quoteTheme = theme.copyWith(
        foreground: theme.muted,
      );
      final TextStyle effectiveStyle = env.resolveTextStyle(
        quoteTheme.bodyTextStyle(),
      );
      final ({InlineSpan span, String plainText}) built =
          buildFastSimpleInlineSpan(para.children, effectiveStyle, quoteTheme);
      return FastMarkdownText(
        span: built.span,
        plainText: built.plainText,
        effectiveStyle: effectiveStyle,
        resolvedTextAlign: renderContext.textAlign,
        resolvedTextDirection: env.textDirection,
        resolvedTextScaler: env.textScaler,
        resolvedLocale: env.locale,
        selectionRegistrar: env.selectionRegistrar,
        selectionColor: env.selectionColor,
        contentPadding: const EdgeInsets.fromLTRB(18.0, 10.0, 12.0, 10.0),
        backgroundColor: theme.effectiveBlockquoteBackground,
        leftBorderColor: theme.effectiveBlockquoteBorder,
        leftBorderWidth: 4.0,
        expandWidth: true,
      );
    }
  }
  final MarkdownBlockRenderContext quoteContext = renderContext.copyWith(
    theme: theme.copyWith(foreground: theme.muted),
  );
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14.0, 10.0, 12.0, 10.0),
    decoration: BoxDecoration(
      color: theme.effectiveBlockquoteBackground,
      border: Border(
        left: BorderSide(color: theme.effectiveBlockquoteBorder, width: 4.0),
      ),
    ),
    child: _buildBlockColumn(context, node.children, quoteContext),
  );
}

Widget _buildAlert(
  BuildContext context,
  AlertNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  final MarkdownAlertColors colors = theme.alertPalette.forKind(node.kind);
  final String glyph = _alertGlyph(node.kind);

  return Semantics(
    container: true,
    label: '${node.title} alert',
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14.0, 10.0, 14.0, 12.0),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8.0),
          bottomRight: Radius.circular(8.0),
        ),
        border: Border(left: BorderSide(color: colors.border, width: 4.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SelectionContainer.disabled(
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 20.0,
                    height: 20.0,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.border.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      glyph,
                      style: TextStyle(
                        color: colors.foreground,
                        fontSize: 12.0,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    node.title,
                    style: TextStyle(
                      color: colors.foreground,
                      fontSize: theme.fontSize * 0.94,
                      fontWeight: FontWeight.w700,
                      fontFamily: theme.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (node.children.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8.0),
            _buildBlockColumn(context, node.children, renderContext),
          ],
        ],
      ),
    ),
  );
}

String _alertGlyph(AlertKind kind) {
  switch (kind) {
    case AlertKind.note:
      return 'i';
    case AlertKind.tip:
      return '✦';
    case AlertKind.important:
      return '!';
    case AlertKind.warning:
      return '▲';
    case AlertKind.caution:
      return '×';
  }
}

Widget _buildList(
  BuildContext context,
  ListNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final List<ListItemNode> items = node.items;
  if (items.isEmpty) {
    return const SizedBox.shrink();
  }
  final MarkdownThemeData theme = renderContext.theme;
  final MarkdownBlockRenderContext childContext = renderContext.copyWith(
    listDepth: renderContext.listDepth + 1,
  );
  final MarkdownRenderEnvironment env =
      renderContext.environment ?? MarkdownRenderEnvironment.resolve(context);
  final TextStyle markerStyle = env.resolveTextStyle(
    theme.bodyTextStyle(color: theme.muted),
  );
  final String? sharedBullet;
  final TextSpan? sharedBulletSpan;
  if (!node.ordered) {
    sharedBullet = switch (renderContext.listDepth % 3) {
      0 => '•',
      1 => '◦',
      _ => '▪',
    };
    sharedBulletSpan = TextSpan(text: sharedBullet, style: markerStyle);
  } else {
    sharedBullet = null;
    sharedBulletSpan = null;
  }

  if (items.length == 1) {
    return _buildListItem(
      context,
      items.first,
      renderContext,
      ordered: node.ordered,
      index: 0,
      start: node.start,
      delimiter: node.delimiter,
      tight: node.tight,
      childContextOverride: childContext,
      envOverride: env,
      markerStyleOverride: markerStyle,
      sharedBullet: sharedBullet,
      sharedBulletSpan: sharedBulletSpan,
    );
  }

  final double itemGap = node.tight ? 4.0 : 8.0;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (int i = 0; i < items.length; i++)
        i < items.length - 1
            ? Padding(
                padding: EdgeInsets.only(bottom: itemGap),
                child: _buildListItem(
                  context,
                  items[i],
                  renderContext,
                  ordered: node.ordered,
                  index: i,
                  start: node.start,
                  delimiter: node.delimiter,
                  tight: node.tight,
                  childContextOverride: childContext,
                  envOverride: env,
                  markerStyleOverride: markerStyle,
                  sharedBullet: sharedBullet,
                  sharedBulletSpan: sharedBulletSpan,
                ),
              )
            : _buildListItem(
                context,
                items[i],
                renderContext,
                ordered: node.ordered,
                index: i,
                start: node.start,
                delimiter: node.delimiter,
                tight: node.tight,
                childContextOverride: childContext,
                envOverride: env,
                markerStyleOverride: markerStyle,
                sharedBullet: sharedBullet,
                sharedBulletSpan: sharedBulletSpan,
              ),
    ],
  );
}

Widget _buildListItem(
  BuildContext context,
  ListItemNode item,
  MarkdownBlockRenderContext renderContext, {
  required bool ordered,
  required int index,
  required int start,
  required String delimiter,
  required bool tight,
  MarkdownBlockRenderContext? childContextOverride,
  MarkdownRenderEnvironment? envOverride,
  TextStyle? markerStyleOverride,
  String? sharedBullet,
  TextSpan? sharedBulletSpan,
}) {
  final MarkdownThemeData theme = renderContext.theme;
  final MarkdownBlockRenderContext childContext =
      childContextOverride ??
      renderContext.copyWith(listDepth: renderContext.listDepth + 1);

  final Widget marker;
  if (item.isTaskItem) {
    final bool checked = item.taskState ?? false;
    marker = SelectionContainer.disabled(
      child: Semantics(
        checked: checked,
        readOnly: true,
        label: checked ? 'Completed task' : 'Incomplete task',
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.only(
              top: (theme.fontSize * theme.lineHeight - 16.0) / 2.0,
            ),
            child: Container(
              width: 16.0,
              height: 16.0,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: checked ? theme.accent : const Color(0x00000000),
                borderRadius: BorderRadius.circular(3.5),
                border: Border.all(
                  color: checked ? theme.accent : theme.muted,
                  width: 1.5,
                ),
              ),
              child: checked
                  ? Text(
                      '✓',
                      style: TextStyle(
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFFFFFFF),
                        fontSize: 11.0,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  } else if (ordered) {
    final MarkdownRenderEnvironment env =
        envOverride ??
        renderContext.environment ??
        MarkdownRenderEnvironment.resolve(context);
    final String label = '${start + index}$delimiter';
    final TextStyle markerStyle =
        markerStyleOverride ??
        env.resolveTextStyle(theme.bodyTextStyle(color: theme.muted));
    marker = SelectionContainer.disabled(
      child: SizedBox(
        width: 26.0,
        child: FastMarkdownText(
          span: TextSpan(text: label, style: markerStyle),
          plainText: label,
          effectiveStyle: markerStyle,
          resolvedTextAlign: TextAlign.right,
          resolvedTextDirection: env.textDirection,
          resolvedTextScaler: env.textScaler,
          resolvedLocale: env.locale,
          selectionRegistrar: null,
        ),
      ),
    );
  } else {
    final MarkdownRenderEnvironment env =
        envOverride ??
        renderContext.environment ??
        MarkdownRenderEnvironment.resolve(context);
    final String bullet =
        sharedBullet ??
        switch (renderContext.listDepth % 3) {
          0 => '•',
          1 => '◦',
          _ => '▪',
        };
    final TextStyle markerStyle =
        markerStyleOverride ??
        env.resolveTextStyle(theme.bodyTextStyle(color: theme.muted));
    final TextSpan bulletSpan =
        sharedBulletSpan ?? TextSpan(text: bullet, style: markerStyle);
    marker = SelectionContainer.disabled(
      child: ExcludeSemantics(
        child: SizedBox(
          width: 18.0,
          child: FastMarkdownText(
            span: bulletSpan,
            plainText: bullet,
            effectiveStyle: markerStyle,
            resolvedTextAlign: TextAlign.center,
            resolvedTextDirection: env.textDirection,
            resolvedTextScaler: env.textScaler,
            resolvedLocale: env.locale,
            selectionRegistrar: null,
          ),
        ),
      ),
    );
  }

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      marker,
      const SizedBox(width: 8.0),
      Expanded(
        child: _buildBlockColumn(
          context,
          item.children,
          childContext,
          spacing: tight ? 4.0 : theme.blockSpacing * 0.65,
        ),
      ),
    ],
  );
}

Widget _buildTable(
  BuildContext context,
  TableNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  final List<TableCellNode> headers = node.headers;
  final List<List<TableCellNode>> rows = node.rows;
  final List<TableAlignment> alignments = node.alignments;
  int columnCount = headers.length;
  for (final List<TableCellNode> row in rows) {
    if (row.length > columnCount) {
      columnCount = row.length;
    }
  }
  if (columnCount == 0) {
    return const SizedBox.shrink();
  }

  TableCellNode cellAt(List<TableCellNode> row, int col) {
    if (col < row.length) {
      return row[col];
    }
    final TableAlignment fallbackAlign = col < alignments.length
        ? alignments[col]
        : TableAlignment.none;
    return TableCellNode(alignment: fallbackAlign);
  }

  TableAlignment resolveAlignment(TableCellNode cell, int col) {
    if (cell.alignment != TableAlignment.none) {
      return cell.alignment;
    }
    if (col < alignments.length) {
      return alignments[col];
    }
    return TableAlignment.none;
  }

  const EdgeInsets cellPadding = EdgeInsets.symmetric(
    horizontal: 12.0,
    vertical: 8.0,
  );
  final MarkdownRenderEnvironment? env = renderContext.environment;
  final TextStyle baseBody = theme.bodyTextStyle();
  final TextStyle headerStyle = baseBody.copyWith(fontWeight: FontWeight.w700);
  final TextStyle bodyStyle = baseBody.copyWith(fontWeight: FontWeight.w400);
  final TextStyle? resolvedHeaderStyle = env?.resolveTextStyle(headerStyle);
  final TextStyle? resolvedBodyStyle = env?.resolveTextStyle(bodyStyle);

  Widget buildCell(TableCellNode cell, int col, {required bool isHeader}) {
    final TableAlignment alignment = resolveAlignment(cell, col);
    final TextAlign textAlign = _textAlignForTableAlignment(alignment);
    final Widget cellContent;
    if (canBuildFastSimpleInlines(cell.children)) {
      cellContent = buildFastOrRichInlineText(
        context,
        nodes: cell.children,
        baseStyle: isHeader ? headerStyle : bodyStyle,
        theme: theme,
        delegates: renderContext.delegates,
        urlPolicy: renderContext.urlPolicy,
        controller: renderContext.controller,
        textAlign: textAlign,
        remoteImagesApproved: renderContext.remoteImagesApproved,
        onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
        environment: env,
        effectiveStyleOverride: isHeader
            ? resolvedHeaderStyle
            : resolvedBodyStyle,
        contentPadding: cellPadding,
        maxWidth: 420.0,
      );
    } else {
      final Alignment boxAlign = _boxAlignmentForTableAlignment(alignment);
      final Widget textWidget = buildFastOrRichInlineText(
        context,
        nodes: cell.children,
        baseStyle: isHeader ? headerStyle : bodyStyle,
        theme: theme,
        delegates: renderContext.delegates,
        urlPolicy: renderContext.urlPolicy,
        controller: renderContext.controller,
        textAlign: textAlign,
        remoteImagesApproved: renderContext.remoteImagesApproved,
        onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
        environment: env,
      );
      cellContent = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420.0),
        child: Padding(
          padding: cellPadding,
          child: Align(
            alignment: boxAlign,
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: textWidget,
          ),
        ),
      );
    }
    if (!isHeader) {
      return cellContent;
    }
    return Semantics(container: true, header: true, child: cellContent);
  }

  final List<TableRow> tableRows = <TableRow>[
    if (headers.isNotEmpty)
      TableRow(
        decoration: BoxDecoration(color: theme.effectiveTableHeaderBackground),
        children: <Widget>[
          for (int col = 0; col < columnCount; col++)
            buildCell(cellAt(headers, col), col, isHeader: true),
        ],
      ),
    for (int r = 0; r < rows.length; r++)
      TableRow(
        decoration: r.isOdd
            ? BoxDecoration(color: theme.effectiveTableStripeBackground)
            : null,
        children: <Widget>[
          for (int col = 0; col < columnCount; col++)
            buildCell(cellAt(rows[r], col), col, isHeader: false),
        ],
      ),
  ];

  return MarkdownHorizontalOverflowBox(
    child: Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder.all(
        color: theme.effectiveTableBorder,
        width: 1.0,
        borderRadius: BorderRadius.circular(6.0),
      ),
      children: tableRows,
    ),
  );
}

final class _MarkdownDetailsBlock extends StatefulWidget {
  const _MarkdownDetailsBlock({
    super.key,
    required this.node,
    required this.renderContext,
  });

  final DetailsBlockNode node;
  final MarkdownBlockRenderContext renderContext;

  @override
  State<_MarkdownDetailsBlock> createState() => _MarkdownDetailsBlockState();
}

final class _MarkdownDetailsBlockState extends State<_MarkdownDetailsBlock> {
  late bool _isOpen;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.node.initiallyOpen;
  }

  @override
  void didUpdateWidget(_MarkdownDetailsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.blockId != widget.node.blockId) {
      _isOpen = widget.node.initiallyOpen;
    }
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final MarkdownThemeData theme = widget.renderContext.theme;
    final List<MarkdownInlineNode> summaryNodes =
        widget.node.summaryInlines.isNotEmpty
        ? widget.node.summaryInlines
        : <MarkdownInlineNode>[TextNode(widget.node.summary)];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MarkdownInteractiveAction(
            onActivate: _toggle,
            semanticLabel: widget.node.summary,
            expanded: _isOpen,
            focusBorderColor: theme.accent,
            borderRadius: BorderRadius.circular(8.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SelectionContainer.disabled(
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: 18.0,
                        child: Text(
                          _isOpen ? '▾' : '▸',
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: theme.fontSize,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  Expanded(
                    child: buildFastOrRichInlineText(
                      context,
                      nodes: summaryNodes,
                      baseStyle: theme.bodyTextStyle().copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      theme: theme,
                      delegates: widget.renderContext.delegates,
                      urlPolicy: widget.renderContext.urlPolicy,
                      controller: widget.renderContext.controller,
                      remoteImagesApproved:
                          widget.renderContext.remoteImagesApproved,
                      onRequestLoadRemoteImages:
                          widget.renderContext.onRequestLoadRemoteImages,
                      environment: widget.renderContext.environment,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isOpen) ...<Widget>[
            Container(height: 1.0, color: theme.border),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: _buildBlockColumn(
                context,
                widget.node.children,
                widget.renderContext,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _buildAlignedBlock(
  BuildContext context,
  AlignedBlockNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final TextAlign textAlign = _textAlignForTableAlignment(node.alignment);
  final CrossAxisAlignment crossAlign = _crossAxisForTextAlign(textAlign);
  final MarkdownBlockRenderContext alignedContext = renderContext.copyWith(
    textAlign: textAlign,
  );
  return SizedBox(
    width: double.infinity,
    child: _buildBlockColumn(
      context,
      node.children,
      alignedContext,
      crossAxisAlignment: crossAlign,
    ),
  );
}

Widget _buildFigureBlock(
  BuildContext context,
  FigureBlockNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  final MarkdownBlockRenderContext figureContext = renderContext.copyWith(
    textAlign: TextAlign.center,
  );
  final List<MarkdownInlineNode> captionNodes = node.captionInlines.isNotEmpty
      ? node.captionInlines
      : (node.caption != null && node.caption!.isNotEmpty
            ? <MarkdownInlineNode>[TextNode(node.caption!)]
            : const <MarkdownInlineNode>[]);

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12.0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8.0),
      border: Border.all(color: theme.border, width: 1.0),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildBlockColumn(
          context,
          node.children,
          figureContext,
          crossAxisAlignment: CrossAxisAlignment.center,
        ),
        if (captionNodes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8.0),
          buildFastOrRichInlineText(
            context,
            nodes: captionNodes,
            baseStyle: theme
                .bodyTextStyle(color: theme.muted)
                .copyWith(
                  fontSize: theme.fontSize * 0.88,
                  fontStyle: FontStyle.italic,
                ),
            theme: theme,
            delegates: renderContext.delegates,
            urlPolicy: renderContext.urlPolicy,
            controller: renderContext.controller,
            textAlign: TextAlign.center,
            remoteImagesApproved: renderContext.remoteImagesApproved,
            onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
            environment: renderContext.environment,
          ),
        ],
      ],
    ),
  );
}

Widget _buildMathBlock(
  BuildContext context,
  MathBlockNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownMathBlockBuilder? builder =
      renderContext.delegates.mathBlockBuilder;
  if (builder != null) {
    return builder(context, node);
  }
  if (renderContext.delegates.enableBuiltInMath) {
    return buildBuiltInMathBlockWidget(
      context: context,
      node: node,
      theme: renderContext.theme,
      delegates: renderContext.delegates,
      urlPolicy: renderContext.urlPolicy,
      hasAncestorSelection:
          renderContext.environment?.selectionRegistrar != null,
    );
  }
  final MarkdownThemeData theme = renderContext.theme;
  return Semantics(
    container: true,
    label: 'Display math: ${node.latex}',
    excludeSemantics: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: theme.codeBackground.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.border, width: 1.0),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: MarkdownRichText(
            node.latex,
            style: theme.codeTextStyle().copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      ),
    ),
  );
}

Widget _buildDefinitionList(
  BuildContext context,
  DefinitionListNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final List<DefinitionGroup> groups = node.groups;
  if (groups.isEmpty) {
    return const SizedBox.shrink();
  }
  final MarkdownThemeData theme = renderContext.theme;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (int g = 0; g < groups.length; g++)
        Padding(
          padding: EdgeInsets.only(bottom: g == groups.length - 1 ? 0.0 : 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              buildFastOrRichInlineText(
                context,
                nodes: groups[g].term,
                baseStyle: theme.bodyTextStyle().copyWith(
                  fontWeight: FontWeight.w700,
                ),
                theme: theme,
                delegates: renderContext.delegates,
                urlPolicy: renderContext.urlPolicy,
                controller: renderContext.controller,
                remoteImagesApproved: renderContext.remoteImagesApproved,
                onRequestLoadRemoteImages:
                    renderContext.onRequestLoadRemoteImages,
                environment: renderContext.environment,
              ),
              for (final List<MarkdownBlockNode> def in groups[g].definitions)
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                  child: Container(
                    padding: const EdgeInsets.only(left: 10.0),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: theme.border, width: 2.0),
                      ),
                    ),
                    child: _buildBlockColumn(context, def, renderContext),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

Widget _buildFootnoteSection(
  BuildContext context,
  FootnoteSectionNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final List<FootnoteDefinitionNode> definitions = node.definitions;
  if (definitions.isEmpty) {
    return const SizedBox.shrink();
  }
  final MarkdownThemeData theme = renderContext.theme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 10.0),
        child: Container(height: 1.0, color: theme.border),
      ),
      for (int i = 0; i < definitions.length; i++)
        Padding(
          padding: EdgeInsets.only(
            bottom: i == definitions.length - 1 ? 0.0 : 8.0,
          ),
          child: _buildFootnoteDefinition(
            context,
            definitions[i],
            renderContext,
          ),
        ),
    ],
  );
}

Widget _buildFootnoteDefinition(
  BuildContext context,
  FootnoteDefinitionNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  final MarkdownThemeData noteTheme = theme.copyWith(
    fontSize: theme.fontSize * 0.9,
  );
  final MarkdownBlockRenderContext noteContext = renderContext.copyWith(
    theme: noteTheme,
  );
  final int backCount = node.referenceCount > 0 ? node.referenceCount : 1;

  void navigateBack(int occurrence) {
    final String suffix = occurrence > 1 ? '-$occurrence' : '';
    final String refSlug = 'fnref-${node.label}$suffix';
    final MarkdownController? ctrl = renderContext.controller;
    if (ctrl != null) {
      unawaited(ctrl.scrollToAnchor(refSlug));
    } else {
      renderContext.delegates.onTapLink?.call('#$refSlug', null);
    }
  }

  return MarkdownAnchorTarget(
    slugs: <String>['fn-${node.label}'],
    controller: renderContext.controller,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 24.0,
          child: MarkdownRichText(
            '${node.index > 0 ? node.index : 1}.',
            textAlign: TextAlign.right,
            style: noteTheme.bodyTextStyle(color: theme.muted),
          ),
        ),
        const SizedBox(width: 8.0),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildBlockColumn(context, node.children, noteContext),
              const SizedBox(height: 2.0),
              Wrap(
                spacing: 6.0,
                children: <Widget>[
                  for (int occ = 1; occ <= backCount; occ++)
                    SelectionContainer.disabled(
                      child: MarkdownInteractiveAction(
                        onActivate: () => navigateBack(occ),
                        semanticLabel:
                            'Back to footnote reference ${node.index}',
                        focusBorderColor: theme.accent,
                        child: Text(
                          occ == 1 ? '↩' : '↩$occ',
                          style: TextStyle(
                            color: theme.effectiveLinkColor,
                            fontSize: noteTheme.fontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildHtmlBlockEntry(
  BuildContext context,
  HtmlBlockEntry entry,
  MarkdownBlockRenderContext renderContext,
) {
  final Widget blockWidget = buildMarkdownBlockWidget(
    context,
    entry.block,
    renderContext,
  );
  final List<MarkdownInlineNode>? caption = entry.tableCaption;
  if (entry.block is TableNode && caption != null && caption.isNotEmpty) {
    final MarkdownThemeData theme = renderContext.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: buildFastOrRichInlineText(
            context,
            nodes: caption,
            baseStyle: theme
                .bodyTextStyle(color: theme.muted)
                .copyWith(fontSize: theme.fontSize * 0.9),
            theme: theme,
            delegates: renderContext.delegates,
            urlPolicy: renderContext.urlPolicy,
            controller: renderContext.controller,
            textAlign: TextAlign.center,
            remoteImagesApproved: renderContext.remoteImagesApproved,
            onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
            environment: renderContext.environment,
          ),
        ),
        blockWidget,
      ],
    );
  }
  return blockWidget;
}

Widget _buildHtmlBlockFallback(
  BuildContext context,
  HtmlBlockNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  final String trimmed = node.literal.trim();
  if (trimmed.isEmpty) {
    return const SizedBox.shrink();
  }
  final List<HtmlBlockEntry> entries = parseHtmlBlockFragment(
    trimmed,
    parentBlockId: node.blockId,
    urlPolicy: renderContext.urlPolicy,
  );
  if (entries.isNotEmpty) {
    if (entries.length == 1) {
      return _buildHtmlBlockEntry(context, entries.first, renderContext);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < entries.length; i++)
          i < entries.length - 1
              ? Padding(
                  padding: EdgeInsets.only(bottom: theme.blockSpacing),
                  child: _buildHtmlBlockEntry(
                    context,
                    entries[i],
                    renderContext,
                  ),
                )
              : _buildHtmlBlockEntry(context, entries[i], renderContext),
      ],
    );
  }
  final String plain = extractSafeHtmlPlainText(trimmed);
  if (plain.isEmpty) {
    return const SizedBox.shrink();
  }
  return MarkdownRichText(
    plain,
    style: theme.bodyTextStyle(color: theme.muted),
  );
}

TextAlign _textAlignForTableAlignment(TableAlignment alignment) {
  switch (alignment) {
    case TableAlignment.none:
    case TableAlignment.left:
      return TextAlign.left;
    case TableAlignment.center:
      return TextAlign.center;
    case TableAlignment.right:
      return TextAlign.right;
  }
}

Alignment _boxAlignmentForTableAlignment(TableAlignment alignment) {
  switch (alignment) {
    case TableAlignment.none:
    case TableAlignment.left:
      return Alignment.centerLeft;
    case TableAlignment.center:
      return Alignment.center;
    case TableAlignment.right:
      return Alignment.centerRight;
  }
}

CrossAxisAlignment _crossAxisForTextAlign(TextAlign align) {
  switch (align) {
    case TextAlign.center:
      return CrossAxisAlignment.center;
    case TextAlign.right:
    case TextAlign.end:
      return CrossAxisAlignment.end;
    case TextAlign.left:
    case TextAlign.start:
    case TextAlign.justify:
      return CrossAxisAlignment.start;
  }
}

Alignment _alignmentForTextAlign(TextAlign align) {
  switch (align) {
    case TextAlign.center:
      return Alignment.center;
    case TextAlign.right:
    case TextAlign.end:
      return Alignment.centerRight;
    case TextAlign.left:
    case TextAlign.start:
    case TextAlign.justify:
      return Alignment.centerLeft;
  }
}
