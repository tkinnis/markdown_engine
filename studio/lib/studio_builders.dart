import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown_engine/markdown_engine.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Summary of hyperlink Destinations in a [MarkdownDocument] evaluated against
/// a [MarkdownUrlPolicy].
@immutable
final class StudioLinkAudit {
  /// Creates a [StudioLinkAudit].
  const StudioLinkAudit({
    required this.allowedCount,
    required this.blockedOrSanitizedCount,
  });

  /// Number of links whose destination is non-empty and allowed by the policy.
  final int allowedCount;

  /// Number of links whose destination was stripped or rejected by the policy.
  final int blockedOrSanitizedCount;

  /// Total [LinkNode] count found across the document AST.
  int get totalCount => allowedCount + blockedOrSanitizedCount;
}

/// Walks [document] and counts allowed versus blocked/sanitized [LinkNode]s
/// under [policy].
StudioLinkAudit auditDocumentLinks(
  MarkdownDocument document,
  MarkdownUrlPolicy policy,
) {
  int allowed = 0;
  int blocked = 0;

  void walkInlines(List<MarkdownInlineNode> nodes) {
    for (final MarkdownInlineNode node in nodes) {
      switch (node) {
        case LinkNode():
          final String dest = node.destination.trim();
          if (dest.isNotEmpty && policy.isAllowed(dest)) {
            allowed++;
          } else {
            blocked++;
          }
          walkInlines(node.children);
        case EmphasisNode():
          walkInlines(node.children);
        case StrongNode():
          walkInlines(node.children);
        case StrikethroughNode():
          walkInlines(node.children);
        case HighlightNode():
          walkInlines(node.children);
        case SubscriptNode():
          walkInlines(node.children);
        case SuperscriptNode():
          walkInlines(node.children);
        case KbdInlineNode():
          walkInlines(node.children);
        case AbbrInlineNode():
          walkInlines(node.children);
        case ImageNode():
          walkInlines(node.children);
        case TextNode():
        case SoftBreakNode():
        case HardBreakNode():
        case InlineBreakNode():
        case CodeSpanNode():
        case MathInlineNode():
        case FootnoteRefNode():
        case AnchorInlineNode():
        case PictureInlineNode():
        case RawHtmlInlineNode():
          break;
      }
    }
  }

  void walkBlocks(List<MarkdownBlockNode> blocks) {
    for (final MarkdownBlockNode block in blocks) {
      switch (block) {
        case HeadingNode():
          walkInlines(block.children);
        case ParagraphNode():
          walkInlines(block.children);
        case BlockQuoteNode():
          walkBlocks(block.children);
        case AlertNode():
          walkBlocks(block.children);
        case ListNode():
          for (final ListItemNode item in block.items) {
            walkBlocks(item.children);
          }
        case ListItemNode():
          walkBlocks(block.children);
        case TableNode():
          for (final TableCellNode cell in block.headers) {
            walkInlines(cell.children);
          }
          for (final List<TableCellNode> row in block.rows) {
            for (final TableCellNode cell in row) {
              walkInlines(cell.children);
            }
          }
        case DetailsBlockNode():
          walkInlines(block.summaryInlines);
          walkBlocks(block.children);
        case AlignedBlockNode():
          walkBlocks(block.children);
        case FigureBlockNode():
          walkBlocks(block.children);
          walkInlines(block.captionInlines);
        case DefinitionListNode():
          for (final DefinitionGroup group in block.groups) {
            walkInlines(group.term);
            for (final List<MarkdownBlockNode> def in group.definitions) {
              walkBlocks(def);
            }
          }
        case FootnoteDefinitionNode():
          walkBlocks(block.children);
        case FootnoteSectionNode():
          for (final FootnoteDefinitionNode def in block.definitions) {
            walkBlocks(def.children);
          }
        case FrontmatterNode():
        case CodeBlockNode():
        case ThematicBreakNode():
        case HtmlBlockNode():
        case MathBlockNode():
          break;
      }
    }
  }

  walkBlocks(document.blocks);
  return StudioLinkAudit(
    allowedCount: allowed,
    blockedOrSanitizedCount: blocked,
  );
}

/// Builds the Studio [MarkdownBuilderDelegates] supplying custom inline math,
/// display math, and diagram demo cards alongside [MarkdownUrlPolicy] link
/// status reporting.
MarkdownBuilderDelegates buildStudioDelegates({
  required MarkdownThemeData theme,
  required MarkdownUrlPolicy urlPolicy,
  required MarkdownLinkTapCallback onTapLink,
  required VoidCallback onLoadRemoteImages,
}) {
  return MarkdownBuilderDelegates(
    imagePolicy: MarkdownImagePolicy.ask,
    urlPolicy: urlPolicy,
    onTapLink: onTapLink,
    onLoadRemoteImages: onLoadRemoteImages,
    mathInlineBuilder:
        (
          BuildContext context,
          MathInlineNode node,
          TextStyle style,
          GestureRecognizer? linkRecognizer,
        ) {
          final double baseSize = style.fontSize ?? theme.fontSize;
          final Widget pill = Container(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(5.0),
              border: Border.all(color: theme.accent.withValues(alpha: 0.35)),
            ),
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'TeX ',
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: baseSize * 0.72,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  TextSpan(
                    text: node.latex,
                    style: style.copyWith(
                      fontFamily: theme.effectiveCodeFontFamily,
                      fontFamilyFallback:
                          MarkdownThemeData.defaultCodeFontFallback,
                      fontStyle: FontStyle.italic,
                      color: linkRecognizer != null
                          ? theme.effectiveLinkColor
                          : theme.foreground,
                      fontSize: baseSize * 0.88,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );

          final Widget interactive = linkRecognizer is TapGestureRecognizer
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: linkRecognizer.onTap,
                    child: pill,
                  ),
                )
              : pill;

          return WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: interactive,
          );
        },
    mathBlockBuilder: (BuildContext context, MathBlockNode node) {
      return Container(
        key: ValueKey<String>('studio-math-block-${node.blockId}'),
        width: double.infinity,
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: theme.accent.withValues(alpha: 0.32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.functions_rounded, size: 15.0, color: theme.accent),
                const SizedBox(width: 6.0),
                Expanded(
                  child: Text(
                    'Display Math · mathBlockBuilder',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 6.0),
                Text(
                  'L${node.span.startLine}..${node.span.endLine}',
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 11.0,
                    fontFamily: theme.effectiveCodeFontFamily,
                    fontFamilyFallback:
                        MarkdownThemeData.defaultCodeFontFallback,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 10.0,
              ),
              decoration: BoxDecoration(
                color: theme.codeBackground.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: Text(
                node.latex.trim(),
                textAlign: TextAlign.center,
                style: theme.codeTextStyle(fontSizeOverride: 15.0),
              ),
            ),
          ],
        ),
      );
    },
    diagramBuilder: (BuildContext context, CodeBlockNode node) {
      final String? lang = node.language?.toLowerCase();
      if (lang != 'mermaid' && lang != 'dot' && lang != 'plantuml') {
        return null;
      }
      final MarkdownAlertColors tipColors = theme.alertPalette.tip;
      final List<String> previewNodes = _extractMermaidLabels(node.literal);

      return Container(
        key: ValueKey<String>('studio-diagram-block-${node.blockId}'),
        width: double.infinity,
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: tipColors.background,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: tipColors.border.withValues(alpha: 0.65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.account_tree_outlined,
                  size: 15.0,
                  color: tipColors.foreground,
                ),
                const SizedBox(width: 6.0),
                Expanded(
                  child: Text(
                    'Diagram Card · diagramBuilder ($lang)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tipColors.foreground,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 6.0),
                Text(
                  'L${node.span.startLine}..${node.span.endLine}',
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 11.0,
                    fontFamily: theme.effectiveCodeFontFamily,
                    fontFamilyFallback:
                        MarkdownThemeData.defaultCodeFontFallback,
                  ),
                ),
              ],
            ),
            if (previewNodes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10.0),
              Wrap(
                spacing: 6.0,
                runSpacing: 6.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < previewNodes.length; i++) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 5.0,
                      ),
                      decoration: BoxDecoration(
                        color: theme.codeBackground,
                        borderRadius: BorderRadius.circular(6.0),
                        border: Border.all(color: tipColors.border),
                      ),
                      child: Text(
                        previewNodes[i],
                        style: TextStyle(
                          color: theme.foreground,
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (i < previewNodes.length - 1)
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14.0,
                        color: tipColors.foreground,
                      ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 10.0),
            Container(
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: theme.codeBackground.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: Text(
                node.literal.trim(),
                style: theme.codeTextStyle(fontSizeOverride: 12.5),
              ),
            ),
          ],
        ),
      );
    },
  );
}

final RegExp _mermaidLabelPattern = RegExp(r'\["([^"]+)"\]|\[([^\]]+)\]');

List<String> _extractMermaidLabels(String source) {
  final List<String> labels = <String>[];
  final Set<String> seen = <String>{};
  for (final Match match in _mermaidLabelPattern.allMatches(source)) {
    final String? raw = match.group(1) ?? match.group(2);
    if (raw == null) {
      continue;
    }
    final String cleaned = raw.trim();
    if (cleaned.isNotEmpty && seen.add(cleaned)) {
      labels.add(cleaned);
    }
  }
  return labels;
}
