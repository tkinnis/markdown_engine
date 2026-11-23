import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_engine/markdown_engine.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Active view mode inside [StudioInspectorPane].
enum StudioInspectorTab {
  /// Interactive AST & `SourceSpan` tree view.
  ast,

  /// Serialized CommonMark/GFM HTML output (`document.toHtml()`).
  html,

  /// Normalized plain text export (`document.toPlainText()`).
  plainText,
}

/// Right-hand inspector pane displaying live AST & `SourceSpan` trees,
/// rendered HTML output, and plain-text exports for the active document.
final class StudioInspectorPane extends StatefulWidget {
  /// Creates a [StudioInspectorPane].
  const StudioInspectorPane({
    super.key,
    required this.controller,
    required this.activeTab,
    required this.onTabChanged,
    required this.onNotify,
  });

  /// Controller supplying the active [MarkdownDocument].
  final MarkdownController controller;

  /// Currently selected inspector tab.
  final StudioInspectorTab activeTab;

  /// Callback invoked when the user switches inspector tabs.
  final ValueChanged<StudioInspectorTab> onTabChanged;

  /// Callback for lightweight copy/jump feedback banners.
  final ValueChanged<String> onNotify;

  @override
  State<StudioInspectorPane> createState() => _StudioInspectorPaneState();
}

final class _StudioInspectorPaneState extends State<StudioInspectorPane> {
  final Set<String> _expandedBlockIds = <String>{};

  void _toggleBlockExpanded(String blockId) {
    setState(() {
      if (!_expandedBlockIds.remove(blockId)) {
        _expandedBlockIds.add(blockId);
      }
    });
  }

  void _copyToClipboard(String label, String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    widget.onNotify('Copied $label (${text.length} chars) to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final MarkdownDocument doc = widget.controller.document;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.developer_board_rounded,
                        size: 16.0,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6.0),
                      Expanded(
                        child: Text(
                          'Inspector',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        '${doc.blocks.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'SF Mono',
                          fontFamilyFallback:
                              MarkdownThemeData.defaultCodeFontFallback,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  SegmentedButton<StudioInspectorTab>(
                    key: const Key('studio-inspector-tabs'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const <ButtonSegment<StudioInspectorTab>>[
                      ButtonSegment<StudioInspectorTab>(
                        value: StudioInspectorTab.ast,
                        tooltip: 'AST & SourceSpans',
                        label: Text(
                          'AST',
                          key: Key('inspector-tab-ast'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ButtonSegment<StudioInspectorTab>(
                        value: StudioInspectorTab.html,
                        tooltip: 'HTML Output',
                        label: Text(
                          'HTML',
                          key: Key('inspector-tab-html'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ButtonSegment<StudioInspectorTab>(
                        value: StudioInspectorTab.plainText,
                        tooltip: 'Plain Text Preview',
                        label: Text(
                          'Plain',
                          key: Key('inspector-tab-text'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    selected: <StudioInspectorTab>{widget.activeTab},
                    onSelectionChanged: (Set<StudioInspectorTab> selection) {
                      if (selection.isNotEmpty) {
                        widget.onTabChanged(selection.first);
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (widget.activeTab) {
                StudioInspectorTab.ast => _buildAstView(context, doc, scheme),
                StudioInspectorTab.html => _buildHtmlView(context, doc, scheme),
                StudioInspectorTab.plainText => _buildPlainTextView(
                  context,
                  doc,
                  scheme,
                ),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildAstView(
    BuildContext context,
    MarkdownDocument doc,
    ColorScheme scheme,
  ) {
    final List<MarkdownBlockNode> blocks = doc.blocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Wrap(
            spacing: 6.0,
            runSpacing: 4.0,
            children: <Widget>[
              _MetaBadge(label: 'Blocks: ${blocks.length}', scheme: scheme),
              _MetaBadge(
                label: 'Outline: ${doc.outline.length}',
                scheme: scheme,
              ),
              if (doc.frontmatter != null)
                _MetaBadge(
                  label: 'Frontmatter: ${doc.frontmatter!.format}',
                  scheme: scheme,
                ),
              if (doc.footnotes.isNotEmpty)
                _MetaBadge(
                  label: 'Footnotes: ${doc.footnotes.length}',
                  scheme: scheme,
                ),
              if (doc.remoteImageAddresses.isNotEmpty)
                _MetaBadge(
                  label: 'Remote imgs: ${doc.remoteImageAddresses.length}',
                  scheme: scheme,
                ),
            ],
          ),
        ),
        if (blocks.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'No AST blocks yet',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              key: const Key('studio-ast-tree'),
              padding: const EdgeInsets.all(8.0),
              itemCount: blocks.length,
              itemBuilder: (BuildContext context, int index) {
                final MarkdownBlockNode block = blocks[index];
                final bool expanded = _expandedBlockIds.contains(block.blockId);
                return _AstBlockCard(
                  key: ValueKey<String>('ast-card-${block.blockId}'),
                  block: block,
                  blockIndex: index,
                  expanded: expanded,
                  onToggle: () => _toggleBlockExpanded(block.blockId),
                  onJump: () {
                    unawaited(
                      widget.controller.jumpToPlace(
                        MarkdownReadingPlace(
                          blockIndex: index,
                          blockId: block.blockId,
                        ),
                        duration: const Duration(milliseconds: 220),
                      ),
                    );
                    widget.onNotify(
                      'Jumped to ${block.runtimeType} (${block.blockId}, '
                      'L${block.span.startLine}..${block.span.endLine}).',
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildHtmlView(
    BuildContext context,
    MarkdownDocument doc,
    ColorScheme scheme,
  ) {
    final String html = doc.toHtml();
    final int lineCount = html.isEmpty ? 0 : '\n'.allMatches(html).length + 1;
    return _CodeExportPane(
      paneKey: const Key('studio-html-output'),
      summary: '$lineCount lines · ${html.length} chars',
      content: html.isEmpty ? '<!-- Empty HTML output -->' : html,
      copyLabel: 'HTML',
      onCopy: () => _copyToClipboard('HTML', html),
      scheme: scheme,
    );
  }

  Widget _buildPlainTextView(
    BuildContext context,
    MarkdownDocument doc,
    ColorScheme scheme,
  ) {
    final String plainText = doc.toPlainText();
    final int wordCount = plainText.trim().isEmpty
        ? 0
        : plainText.trim().split(RegExp(r'\s+')).length;
    return _CodeExportPane(
      paneKey: const Key('studio-plaintext-output'),
      summary: '$wordCount words · ${plainText.length} chars',
      content: plainText.isEmpty ? '(Empty plain text output)' : plainText,
      copyLabel: 'Plain Text',
      onCopy: () => _copyToClipboard('Plain Text', plainText),
      scheme: scheme,
    );
  }
}

final class _CodeExportPane extends StatelessWidget {
  const _CodeExportPane({
    required this.paneKey,
    required this.summary,
    required this.content,
    required this.copyLabel,
    required this.onCopy,
    required this.scheme,
  });

  final Key paneKey;
  final String summary;
  final String content;
  final String copyLabel;
  final VoidCallback onCopy;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  summary,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'SF Mono',
                    fontFamilyFallback:
                        MarkdownThemeData.defaultCodeFontFallback,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 14.0),
                label: const Text('Copy'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  textStyle: const TextStyle(fontSize: 12.0),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: SelectableText(
              content,
              key: paneKey,
              style: TextStyle(
                fontFamily: 'SF Mono',
                fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
                fontSize: 12.0,
                height: 1.45,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.label, required this.scheme});

  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5.0),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.0,
          color: scheme.onSurfaceVariant,
          fontFamily: 'SF Mono',
          fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
        ),
      ),
    );
  }
}

final class _AstBlockCard extends StatelessWidget {
  const _AstBlockCard({
    super.key,
    required this.block,
    required this.blockIndex,
    required this.expanded,
    required this.onToggle,
    required this.onJump,
  });

  final MarkdownBlockNode block;
  final int blockIndex;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SourceSpan span = block.span;
    final String summary = _describeBlock(block);
    final List<Widget> detailChildren = expanded
        ? _buildExpandedChildren(block, scheme, depth: 1)
        : const <Widget>[];

    return Card(
      elevation: 0.0,
      margin: const EdgeInsets.only(bottom: 6.0),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 7.0, 6.0, 7.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        expanded
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 16.0,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2.0),
                      Expanded(
                        child: Wrap(
                          spacing: 6.0,
                          runSpacing: 2.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              '${block.runtimeType}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                                fontFamily: 'SF Mono',
                                fontFamilyFallback:
                                    MarkdownThemeData.defaultCodeFontFallback,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5.0,
                                vertical: 1.0,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: Text(
                                block.blockId,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSecondaryContainer,
                                  fontFamily: 'SF Mono',
                                  fontFamilyFallback:
                                      MarkdownThemeData.defaultCodeFontFallback,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onJump,
                        tooltip: 'Scroll preview to block #$blockIndex',
                        icon: const Icon(Icons.my_location_rounded, size: 14.0),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 24.0,
                          minHeight: 24.0,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3.0),
                  Padding(
                    padding: const EdgeInsets.only(left: 18.0),
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 2.0,
                      children: <Widget>[
                        Text(
                          'L${span.startLine}..${span.endLine}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'SF Mono',
                            fontFamilyFallback:
                                MarkdownThemeData.defaultCodeFontFallback,
                          ),
                        ),
                        Text(
                          'off ${span.startOffset}..${span.endOffset}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'SF Mono',
                            fontFamilyFallback:
                                MarkdownThemeData.defaultCodeFontFallback,
                          ),
                        ),
                        if (summary.isNotEmpty)
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.0,
                              color: scheme.onSurface,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded && detailChildren.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12.0, 4.0, 10.0, 8.0),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8.0),
                ),
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: detailChildren,
              ),
            ),
        ],
      ),
    );
  }
}

List<Widget> _buildExpandedChildren(
  MarkdownBlockNode block,
  ColorScheme scheme, {
  required int depth,
}) {
  final List<Widget> rows = <Widget>[];

  void addBlockChildren(List<MarkdownBlockNode> children) {
    for (final MarkdownBlockNode child in children) {
      rows.add(
        _AstNestedRow(
          depth: depth,
          typeName: '${child.runtimeType}',
          idLabel: child.blockId,
          span: child.span,
          detail: _describeBlock(child),
          scheme: scheme,
        ),
      );
      if (depth < 3) {
        rows.addAll(_buildExpandedChildren(child, scheme, depth: depth + 1));
      }
    }
  }

  void addInlineChildren(List<MarkdownInlineNode> inlines) {
    final int limit = inlines.length > 24 ? 24 : inlines.length;
    for (int i = 0; i < limit; i++) {
      final MarkdownInlineNode inline = inlines[i];
      rows.add(
        _AstNestedRow(
          depth: depth,
          typeName: '${inline.runtimeType}',
          idLabel: null,
          span: inline.span,
          detail: _describeInline(inline),
          scheme: scheme,
        ),
      );
    }
    if (inlines.length > limit) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 10.0, top: 2.0),
          child: Text(
            '... +${inlines.length - limit} more inline nodes',
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
  }

  switch (block) {
    case FrontmatterNode():
      for (final MapEntry<String, Object?> entry in block.entries.entries) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 10.0, top: 2.0),
            child: Text(
              '${entry.key}: ${entry.value}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.0,
                color: scheme.onSurface,
                fontFamily: 'SF Mono',
                fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
              ),
            ),
          ),
        );
      }
    case HeadingNode():
      addInlineChildren(block.children);
    case ParagraphNode():
      addInlineChildren(block.children);
    case BlockQuoteNode():
      addBlockChildren(block.children);
    case AlertNode():
      addBlockChildren(block.children);
    case ListNode():
      addBlockChildren(block.items);
    case ListItemNode():
      addBlockChildren(block.children);
    case TableNode():
      rows.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 10.0, top: 2.0),
          child: Text(
            'Headers: ${block.headers.map((TableCellNode c) => c.toPlainText()).join(' | ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.0, color: scheme.onSurface),
          ),
        ),
      );
    case DetailsBlockNode():
      addInlineChildren(block.summaryInlines);
      addBlockChildren(block.children);
    case AlignedBlockNode():
      addBlockChildren(block.children);
    case FigureBlockNode():
      addBlockChildren(block.children);
      addInlineChildren(block.captionInlines);
    case DefinitionListNode():
      for (final DefinitionGroup group in block.groups) {
        addInlineChildren(group.term);
        for (final List<MarkdownBlockNode> def in group.definitions) {
          addBlockChildren(def);
        }
      }
    case FootnoteDefinitionNode():
      addBlockChildren(block.children);
    case FootnoteSectionNode():
      addBlockChildren(block.definitions);
    case CodeBlockNode():
    case MathBlockNode():
    case HtmlBlockNode():
    case ThematicBreakNode():
      final String snippet = _truncate(block.toPlainText(), 90);
      if (snippet.isNotEmpty) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: depth * 10.0, top: 2.0),
            child: Text(
              snippet,
              style: TextStyle(
                fontSize: 11.0,
                color: scheme.onSurfaceVariant,
                fontFamily: 'SF Mono',
                fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
              ),
            ),
          ),
        );
      }
  }
  return rows;
}

final class _AstNestedRow extends StatelessWidget {
  const _AstNestedRow({
    required this.depth,
    required this.typeName,
    required this.idLabel,
    required this.span,
    required this.detail,
    required this.scheme,
  });

  final int depth;
  final String typeName;
  final String? idLabel;
  final SourceSpan span;
  final String detail;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 10.0, top: 3.0),
      child: Wrap(
        spacing: 6.0,
        runSpacing: 2.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            typeName,
            style: TextStyle(
              fontSize: 11.0,
              fontWeight: FontWeight.w600,
              color: scheme.tertiary,
              fontFamily: 'SF Mono',
              fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
            ),
          ),
          if (idLabel != null)
            Text(
              '[$idLabel]',
              style: TextStyle(
                fontSize: 10.0,
                color: scheme.onSurfaceVariant,
                fontFamily: 'SF Mono',
                fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
              ),
            ),
          Text(
            'L${span.startLine}..${span.endLine} (${span.startOffset}..${span.endOffset})',
            style: TextStyle(
              fontSize: 10.0,
              color: scheme.onSurfaceVariant,
              fontFamily: 'SF Mono',
              fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
            ),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.0, color: scheme.onSurface),
            ),
        ],
      ),
    );
  }
}

String _describeBlock(MarkdownBlockNode block) {
  switch (block) {
    case FrontmatterNode():
      return '${block.format} (${block.entries.length} keys)';
    case HeadingNode():
      final String slugText = block.slug != null ? ' #${block.slug}' : '';
      return 'H${block.level}$slugText "${_truncate(block.text, 34)}"';
    case ParagraphNode():
      return '"${_truncate(block.toPlainText(), 42)}"';
    case CodeBlockNode():
      final String lang = block.language ?? 'plain';
      return 'lang=$lang (${block.isFenced ? 'fenced' : 'indented'})';
    case BlockQuoteNode():
      return '${block.children.length} child block(s)';
    case AlertNode():
      return 'kind=${block.kind.name} (${block.children.length} blocks)';
    case ListNode():
      return '${block.ordered ? 'ordered' : 'bullet'} (${block.items.length} items)';
    case ListItemNode():
      final String task = block.taskState == null
          ? ''
          : (block.taskState! ? '[x] ' : '[ ] ');
      return '$task${block.children.length} block(s)';
    case TableNode():
      return '${block.headers.length} cols × ${block.rows.length} rows';
    case ThematicBreakNode():
      return '<hr />';
    case HtmlBlockNode():
      return 'type=${block.blockType} ${_truncate(block.literal, 32)}';
    case DetailsBlockNode():
      return 'open=${block.initiallyOpen} "${_truncate(block.summary, 30)}"';
    case AlignedBlockNode():
      return 'align=${block.alignment.name}';
    case FigureBlockNode():
      return block.caption == null
          ? '${block.children.length} child block(s)'
          : 'caption="${_truncate(block.caption!, 32)}"';
    case MathBlockNode():
      return _truncate(block.latex, 40);
    case DefinitionListNode():
      return '${block.groups.length} group(s)';
    case FootnoteDefinitionNode():
      return '[^${block.label}] #${block.index} (${block.referenceCount} refs)';
    case FootnoteSectionNode():
      return '${block.definitions.length} footnote(s)';
  }
}

String _describeInline(MarkdownInlineNode node) {
  switch (node) {
    case TextNode():
      return '"${_truncate(node.text, 36)}"';
    case SoftBreakNode():
      return 'soft-break';
    case HardBreakNode():
      return 'hard-break';
    case InlineBreakNode():
      return '<br />';
    case CodeSpanNode():
      return '`${_truncate(node.literal, 32)}`';
    case EmphasisNode():
      return 'em(${node.children.length})';
    case StrongNode():
      return 'strong(${node.children.length})';
    case StrikethroughNode():
      return 'del(${node.children.length})';
    case HighlightNode():
      return 'mark(${node.children.length})';
    case SubscriptNode():
      return 'sub(${node.children.length})';
    case SuperscriptNode():
      return 'sup(${node.children.length})';
    case LinkNode():
      final String dest = node.destination.isEmpty
          ? '(sanitized)'
          : _truncate(node.destination, 32);
      return 'href=$dest';
    case ImageNode():
      return 'src=${_truncate(node.destination, 32)}';
    case MathInlineNode():
      return '\$${_truncate(node.latex, 30)}\$';
    case FootnoteRefNode():
      return '[^${node.label}] (#${node.index})';
    case KbdInlineNode():
      return '<kbd>${_truncate(node.toPlainText(), 20)}</kbd>';
    case AbbrInlineNode():
      return '${node.toPlainText()}="${_truncate(node.title, 24)}"';
    case AnchorInlineNode():
      return '#${node.id}';
    case PictureInlineNode():
      return 'alt="${_truncate(node.alt, 24)}"';
    case RawHtmlInlineNode():
      return _truncate(node.html, 32);
  }
}

String _truncate(String input, int maxLength) {
  final String singleLine = input.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= maxLength) {
    return singleLine;
  }
  return '${singleLine.substring(0, maxLength - 1)}…';
}
