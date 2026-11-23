import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'built_in_math.dart';
import 'built_in_mermaid.dart';
import 'controller.dart';
import 'delegates.dart';
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

  /// Returns a derived context with selected fields overridden.
  MarkdownBlockRenderContext copyWith({
    MarkdownThemeData? theme,
    TextAlign? textAlign,
    int? listDepth,
  }) {
    return MarkdownBlockRenderContext(
      theme: theme ?? this.theme,
      delegates: delegates,
      urlPolicy: urlPolicy,
      controller: controller,
      textAlign: textAlign ?? this.textAlign,
      listDepth: listDepth ?? this.listDepth,
      remoteImagesApproved: remoteImagesApproved,
      onRequestLoadRemoteImages: onRequestLoadRemoteImages,
      streamingNormalizedSource: streamingNormalizedSource,
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
          streamingNormalizedSource == other.streamingNormalizedSource;

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
  });

  /// Block AST node to render.
  final MarkdownBlockNode node;

  /// Shared rendering context.
  final MarkdownBlockRenderContext renderContext;

  /// Bottom spacing applied after this block (`0.0` for the final block).
  final double bottomSpacing;

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
  TextScaler? _cachedTextScaler;
  TextDirection? _cachedTextDirection;
  bool? _cachedHasSelectionContainer;

  @override
  void initState() {
    super.initState();
    widget.renderContext.controller?.registerBlock(
      widget.node.blockId,
      context,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedInnerBlock = null;
    _cachedPaddedBlock = null;
  }

  @override
  void didUpdateWidget(MarkdownTopLevelBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
          oldWidget.renderContext.controller,
          widget.renderContext.controller,
        ) ||
        oldWidget.node.blockId != widget.node.blockId) {
      oldWidget.renderContext.controller?.unregisterBlock(
        oldWidget.node.blockId,
        context,
      );
      widget.renderContext.controller?.registerBlock(
        widget.node.blockId,
        context,
      );
    }
  }

  @override
  void dispose() {
    _cachedInnerBlock = null;
    _cachedPaddedBlock = null;
    widget.renderContext.controller?.unregisterBlock(
      widget.node.blockId,
      context,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextScaler? textScaler = MediaQuery.maybeTextScalerOf(context);
    final TextDirection? textDirection = Directionality.maybeOf(context);
    final bool hasSelectionContainer =
        SelectionContainer.maybeOf(context) != null;

    final bool innerValid =
        _cachedInnerBlock != null &&
        identical(widget.node, _cachedNode) &&
        widget.renderContext == _cachedRenderContext &&
        textScaler == _cachedTextScaler &&
        textDirection == _cachedTextDirection &&
        hasSelectionContainer == _cachedHasSelectionContainer;

    if (innerValid &&
        _cachedPaddedBlock != null &&
        widget.bottomSpacing == _cachedBottomSpacing) {
      return _cachedPaddedBlock!;
    }

    final Widget blockWidget = innerValid
        ? _cachedInnerBlock!
        : buildMarkdownBlockWidget(context, widget.node, widget.renderContext);

    final Widget result = widget.bottomSpacing <= 0.0
        ? blockWidget
        : Padding(
            padding: EdgeInsets.only(bottom: widget.bottomSpacing),
            child: blockWidget,
          );

    _cachedInnerBlock = blockWidget;
    _cachedPaddedBlock = result;
    _cachedNode = widget.node;
    _cachedRenderContext = widget.renderContext;
    _cachedBottomSpacing = widget.bottomSpacing;
    _cachedTextScaler = textScaler;
    _cachedTextDirection = textDirection;
    _cachedHasSelectionContainer = hasSelectionContainer;
    return result;
  }
}

/// Builds a native Flutter widget for any [MarkdownBlockNode].
Widget buildMarkdownBlockWidget(
  BuildContext context,
  MarkdownBlockNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;

  switch (node) {
    case FrontmatterNode():
      return _buildFrontmatterCard(node, theme);
    case HeadingNode():
      return _buildHeading(node, renderContext);
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
      return _buildTable(node, renderContext);
    case ThematicBreakNode():
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Container(height: 1.0, color: theme.border),
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
  final double gap = spacing ?? renderContext.theme.blockSpacing * 0.75;
  return Column(
    crossAxisAlignment: crossAxisAlignment,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (int i = 0; i < blocks.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == blocks.length - 1 ? 0.0 : gap),
          child: buildMarkdownBlockWidget(context, blocks[i], renderContext),
        ),
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
                child: Text(
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
              Text(
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
            Text(
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
        Text('$key:', style: keyStyle),
        for (final Object? item in value)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
            decoration: BoxDecoration(
              color: theme.border.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999.0),
            ),
            child: Text('$item', style: valStyle),
          ),
      ],
    );
  }

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('$key: ', style: keyStyle),
      Expanded(child: Text('${value ?? ''}', style: valStyle)),
    ],
  );
}

Widget _buildHeading(
  HeadingNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  final Set<String> slugSet = <String>{
    if (node.slug != null && node.slug!.isNotEmpty) node.slug!,
    if (node.explicitId != null && node.explicitId!.isNotEmpty)
      node.explicitId!,
    slugifyHeadingText(node.text),
  };

  final Widget headingContent = Column(
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
        onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
      ),
      if (node.level <= 2) ...<Widget>[
        const SizedBox(height: 6.0),
        Container(height: 1.0, color: theme.border),
      ],
    ],
  );

  return MarkdownAnchorTarget(
    slugs: slugSet.toList(growable: false),
    controller: renderContext.controller,
    child: Semantics(
      header: true,
      headingLevel: node.level.clamp(1, 6),
      child: Padding(
        padding: EdgeInsets.only(top: node.level <= 2 ? 8.0 : 4.0),
        child: headingContent,
      ),
    ),
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

  return MarkdownInlineText(
    nodes: node.children,
    baseStyle: theme.bodyTextStyle(),
    theme: theme,
    delegates: renderContext.delegates,
    urlPolicy: renderContext.urlPolicy,
    controller: renderContext.controller,
    textAlign: renderContext.textAlign,
    remoteImagesApproved: renderContext.remoteImagesApproved,
    onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
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
    final String? streamSource = renderContext.streamingNormalizedSource;
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
  );
}

final class _MarkdownCodeBlock extends StatefulWidget {
  const _MarkdownCodeBlock({
    super.key,
    required this.node,
    required this.theme,
  });

  final CodeBlockNode node;
  final MarkdownThemeData theme;

  @override
  State<_MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

final class _MarkdownCodeBlockState extends State<_MarkdownCodeBlock> {
  bool _copied = false;
  Timer? _resetTimer;

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

  @override
  Widget build(BuildContext context) {
    final MarkdownThemeData theme = widget.theme;
    final String? lang = widget.node.language;
    final String badgeText = (lang != null && lang.isNotEmpty) ? lang : 'code';
    final String trimmed = widget.node.literal.endsWith('\n')
        ? widget.node.literal.substring(0, widget.node.literal.length - 1)
        : widget.node.literal;

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
                        badgeText,
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
                    onActivate: _copyCode,
                    semanticLabel: _copied ? 'Copied' : 'Copy code',
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12.0),
            child: Text(trimmed, style: theme.codeTextStyle()),
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
  final double itemGap = node.tight ? 4.0 : 8.0;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (int i = 0; i < items.length; i++)
        Padding(
          padding: EdgeInsets.only(
            bottom: i == items.length - 1 ? 0.0 : itemGap,
          ),
          child: _buildListItem(
            context,
            items[i],
            renderContext,
            ordered: node.ordered,
            index: i,
            start: node.start,
            delimiter: node.delimiter,
            tight: node.tight,
          ),
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
}) {
  final MarkdownThemeData theme = renderContext.theme;
  final MarkdownBlockRenderContext childContext = renderContext.copyWith(
    listDepth: renderContext.listDepth + 1,
  );

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
    marker = SelectionContainer.disabled(
      child: SizedBox(
        width: 26.0,
        child: Text(
          '${start + index}$delimiter',
          textAlign: TextAlign.right,
          style: theme.bodyTextStyle(color: theme.muted),
        ),
      ),
    );
  } else {
    final String bullet = switch (renderContext.listDepth % 3) {
      0 => '•',
      1 => '◦',
      _ => '▪',
    };
    marker = SelectionContainer.disabled(
      child: ExcludeSemantics(
        child: SizedBox(
          width: 18.0,
          child: Text(
            bullet,
            textAlign: TextAlign.center,
            style: theme.bodyTextStyle(color: theme.muted),
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

Widget _buildTable(TableNode node, MarkdownBlockRenderContext renderContext) {
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

  Widget buildCell(TableCellNode cell, int col, {required bool isHeader}) {
    final TableAlignment alignment = resolveAlignment(cell, col);
    final TextAlign textAlign = _textAlignForTableAlignment(alignment);
    final Alignment boxAlign = _boxAlignmentForTableAlignment(alignment);
    final TextStyle style = theme.bodyTextStyle().copyWith(
      fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
    );
    return Semantics(
      container: true,
      header: isHeader ? true : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          alignment: boxAlign,
          child: MarkdownInlineText(
            nodes: cell.children,
            baseStyle: style,
            theme: theme,
            delegates: renderContext.delegates,
            urlPolicy: renderContext.urlPolicy,
            controller: renderContext.controller,
            textAlign: textAlign,
            remoteImagesApproved: renderContext.remoteImagesApproved,
            onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
          ),
        ),
      ),
    );
  }

  final List<TableRow> tableRows = <TableRow>[
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

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
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
                    child: MarkdownInlineText(
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
          MarkdownInlineText(
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
          child: Text(
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
              MarkdownInlineText(
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
          child: Text(
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

final RegExp _dangerousHtmlBlockPattern = RegExp(
  r'<\s*(?:script|style|iframe|object|embed|applet|svg|math|form|textarea|title|xmp)\b',
  caseSensitive: false,
);
final RegExp _htmlCommentPattern = RegExp(r'<!--[\s\S]*?-->');
final RegExp _htmlTagStripPattern = RegExp(r'<[^>]+>');

Widget _buildHtmlBlockFallback(
  BuildContext context,
  HtmlBlockNode node,
  MarkdownBlockRenderContext renderContext,
) {
  final MarkdownThemeData theme = renderContext.theme;
  final String trimmed = node.literal.trim();
  if (trimmed.isEmpty || _dangerousHtmlBlockPattern.hasMatch(trimmed)) {
    return const SizedBox.shrink();
  }
  final String withoutComments = trimmed
      .replaceAll(_htmlCommentPattern, '')
      .trim();
  if (withoutComments.isEmpty) {
    return const SizedBox.shrink();
  }
  final ImageNode? htmlImg = tryParseHtmlImageTag(withoutComments);
  if (htmlImg != null) {
    return Align(
      alignment: _alignmentForTextAlign(renderContext.textAlign),
      child: buildMarkdownImageWidget(
        context: context,
        node: htmlImg,
        theme: theme,
        delegates: renderContext.delegates,
        urlPolicy: renderContext.urlPolicy,
        remoteImagesApproved: renderContext.remoteImagesApproved,
        onRequestLoadRemoteImages: renderContext.onRequestLoadRemoteImages,
      ),
    );
  }
  final String stripped = withoutComments
      .replaceAll(_htmlTagStripPattern, '')
      .trim();
  if (stripped.isEmpty) {
    return const SizedBox.shrink();
  }
  final String decoded = _decodeHtmlEntities(stripped);
  return Text(decoded, style: theme.bodyTextStyle(color: theme.muted));
}

const Map<String, String> _namedHtmlEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': '\'',
  'nbsp': '\u00A0',
  'ndash': '\u2013',
  'mdash': '\u2014',
  'hellip': '\u2026',
  'lsquo': '\u2018',
  'rsquo': '\u2019',
  'ldquo': '\u201C',
  'rdquo': '\u201D',
  'laquo': '\u00AB',
  'raquo': '\u00BB',
  'copy': '\u00A9',
  'reg': '\u00AE',
  'trade': '\u2122',
  'times': '\u00D7',
  'divide': '\u00F7',
  'plusmn': '\u00B1',
  'minus': '\u2212',
  'bull': '\u2022',
  'middot': '\u00B7',
  'deg': '\u00B0',
  'sect': '\u00A7',
  'para': '\u00B6',
  'larr': '\u2190',
  'uarr': '\u2191',
  'rarr': '\u2192',
  'darr': '\u2193',
  'harr': '\u2194',
  'le': '\u2264',
  'ge': '\u2265',
  'ne': '\u2260',
  'asymp': '\u2248',
  'infin': '\u221E',
};

String _decodeHtmlEntities(String input) {
  if (!input.contains('&')) {
    return input;
  }
  StringBuffer? out;
  int last = 0;
  int i = 0;
  final int len = input.length;
  while (i < len) {
    if (input.codeUnitAt(i) != 0x26) {
      i++;
      continue;
    }
    final int semi = input.indexOf(';', i + 1);
    if (semi == -1 || semi - i > 16) {
      i++;
      continue;
    }
    final String body = input.substring(i + 1, semi);
    String? replacement;
    if (body.startsWith('#')) {
      final int? cp;
      if (body.length > 2 && (body[1] == 'x' || body[1] == 'X')) {
        cp = int.tryParse(body.substring(2), radix: 16);
      } else if (body.length > 1) {
        cp = int.tryParse(body.substring(1), radix: 10);
      } else {
        cp = null;
      }
      if (cp != null) {
        final bool valid =
            cp > 0 && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF);
        replacement = valid ? String.fromCharCode(cp) : '\uFFFD';
      }
    } else {
      replacement =
          _namedHtmlEntities[body] ?? _namedHtmlEntities[body.toLowerCase()];
    }
    if (replacement != null) {
      out ??= StringBuffer();
      if (i > last) {
        out.write(input.substring(last, i));
      }
      out.write(replacement);
      i = semi + 1;
      last = i;
    } else {
      i++;
    }
  }
  if (out == null) {
    return input;
  }
  if (last < len) {
    out.write(input.substring(last));
  }
  return out.toString();
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
