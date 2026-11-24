import 'ast.dart';
import 'options.dart';
import 'security.dart';
import 'slugs.dart';

/// Counts the total number of AST block nodes in [blocks] (including nested
/// containers), without shifting spans.
int countTotalBlocks(List<MarkdownBlockNode> blocks) {
  int total = 0;
  void walk(List<MarkdownBlockNode> list) {
    for (final MarkdownBlockNode b in list) {
      total++;
      switch (b) {
        case FrontmatterNode():
        case HeadingNode():
        case ParagraphNode():
        case CodeBlockNode():
        case TableNode():
        case ThematicBreakNode():
        case HtmlBlockNode():
        case MathBlockNode():
          break;
        case BlockQuoteNode():
          walk(rawBlockQuoteChildren(b));
        case AlertNode():
          walk(rawAlertChildren(b));
        case ListNode():
          final List<ListItemNode> items = rawListItems(b);
          for (int i = 0; i < items.length; i++) {
            total++;
            walk(rawListItemChildren(items[i]));
          }
        case ListItemNode():
          walk(rawListItemChildren(b));
        case DetailsBlockNode():
          walk(rawDetailsChildren(b));
        case AlignedBlockNode():
          walk(rawAlignedChildren(b));
        case FigureBlockNode():
          walk(rawFigureChildren(b));
        case DefinitionListNode():
          for (final DefinitionGroup g in rawDefinitionGroups(b)) {
            for (final List<MarkdownBlockNode> def in rawDefinitionBodies(g)) {
              walk(def);
            }
          }
        case FootnoteDefinitionNode():
          walk(rawFootnoteDefChildren(b));
        case FootnoteSectionNode():
          for (final FootnoteDefinitionNode d in rawFootnoteSectionDefs(b)) {
            total++;
            walk(rawFootnoteDefChildren(d));
          }
      }
    }
  }

  walk(blocks);
  return total;
}

/// Returns whether [block] or any of its nested containers holds a [HeadingNode].
bool blockContainsHeading(MarkdownBlockNode block) {
  switch (block) {
    case HeadingNode():
      return true;
    case FrontmatterNode():
    case ParagraphNode():
    case CodeBlockNode():
    case TableNode():
    case ThematicBreakNode():
    case HtmlBlockNode():
    case MathBlockNode():
      return false;
    case BlockQuoteNode():
      return containsHeadingInBlocks(rawBlockQuoteChildren(block));
    case AlertNode():
      return containsHeadingInBlocks(rawAlertChildren(block));
    case ListNode():
      final List<ListItemNode> items = rawListItems(block);
      for (int i = 0; i < items.length; i++) {
        if (containsHeadingInBlocks(rawListItemChildren(items[i]))) {
          return true;
        }
      }
      return false;
    case ListItemNode():
      return containsHeadingInBlocks(rawListItemChildren(block));
    case DetailsBlockNode():
      return containsHeadingInBlocks(rawDetailsChildren(block));
    case AlignedBlockNode():
      return containsHeadingInBlocks(rawAlignedChildren(block));
    case FigureBlockNode():
      return containsHeadingInBlocks(rawFigureChildren(block));
    case DefinitionListNode():
      final List<DefinitionGroup> groups = rawDefinitionGroups(block);
      for (int i = 0; i < groups.length; i++) {
        final List<List<MarkdownBlockNode>> defs = rawDefinitionBodies(
          groups[i],
        );
        for (int j = 0; j < defs.length; j++) {
          if (containsHeadingInBlocks(defs[j])) {
            return true;
          }
        }
      }
      return false;
    case FootnoteDefinitionNode():
      return containsHeadingInBlocks(rawFootnoteDefChildren(block));
    case FootnoteSectionNode():
      final List<FootnoteDefinitionNode> defs = rawFootnoteSectionDefs(block);
      for (int i = 0; i < defs.length; i++) {
        if (containsHeadingInBlocks(rawFootnoteDefChildren(defs[i]))) {
          return true;
        }
      }
      return false;
  }
}

/// Returns whether any block in [blocks] or its nested containers is a
/// [HeadingNode].
bool containsHeadingInBlocks(List<MarkdownBlockNode> blocks) {
  for (int i = 0; i < blocks.length; i++) {
    if (blockContainsHeading(blocks[i])) {
      return true;
    }
  }
  return false;
}

/// Appends raw heading plain texts from [block] (excluding explicit IDs) in
/// Phase 2 order so settled headings can be seeded lazily into a slug batch.
void collectSettledHeadingTexts(
  MarkdownBlockNode block,
  MarkdownOptions options,
  List<String> out,
) {
  if (!options.headingSlugs || !blockContainsHeading(block)) {
    return;
  }
  _walkSettledHeadingTexts(block, options, out.add);
}

/// Advances [slugGenerator] across any headings contained inside [block]
/// (matching Phase 2 slug generation order) without constructing outline items.
void collectSettledBlockSlugs(
  MarkdownBlockNode block,
  MarkdownOptions options,
  HeadingSlugGenerator slugGenerator,
) {
  if (!options.headingSlugs || !blockContainsHeading(block)) {
    return;
  }
  _walkSettledHeadingTexts(block, options, slugGenerator.generate);
}

void _walkSettledHeadingTexts(
  MarkdownBlockNode block,
  MarkdownOptions options,
  void Function(String) onHeadingText,
) {
  void walkBlock(MarkdownBlockNode b) {
    switch (b) {
      case HeadingNode():
        final bool hasExplicit =
            options.explicitHeadingIds && b.explicitId != null;
        if (!hasExplicit) {
          onHeadingText(b.text);
        }
      case FrontmatterNode():
      case ParagraphNode():
      case CodeBlockNode():
      case TableNode():
      case ThematicBreakNode():
      case HtmlBlockNode():
      case MathBlockNode():
        break;
      case BlockQuoteNode():
        if (blockContainsHeading(b)) {
          for (final MarkdownBlockNode child in rawBlockQuoteChildren(b)) {
            walkBlock(child);
          }
        }
      case AlertNode():
        if (blockContainsHeading(b)) {
          for (final MarkdownBlockNode child in rawAlertChildren(b)) {
            walkBlock(child);
          }
        }
      case ListNode():
        if (blockContainsHeading(b)) {
          for (final ListItemNode item in rawListItems(b)) {
            for (final MarkdownBlockNode child in rawListItemChildren(item)) {
              walkBlock(child);
            }
          }
        }
      case ListItemNode():
        if (blockContainsHeading(b)) {
          for (final MarkdownBlockNode child in rawListItemChildren(b)) {
            walkBlock(child);
          }
        }
      case DetailsBlockNode():
        if (blockContainsHeading(b)) {
          for (final MarkdownBlockNode child in rawDetailsChildren(b)) {
            walkBlock(child);
          }
        }
      case AlignedBlockNode():
        if (blockContainsHeading(b)) {
          for (final MarkdownBlockNode child in rawAlignedChildren(b)) {
            walkBlock(child);
          }
        }
      case FigureBlockNode():
        if (blockContainsHeading(b)) {
          for (final MarkdownBlockNode child in rawFigureChildren(b)) {
            walkBlock(child);
          }
        }
      case DefinitionListNode():
        if (blockContainsHeading(b)) {
          for (final DefinitionGroup g in rawDefinitionGroups(b)) {
            for (final List<MarkdownBlockNode> def in rawDefinitionBodies(g)) {
              for (final MarkdownBlockNode child in def) {
                walkBlock(child);
              }
            }
          }
        }
      case FootnoteDefinitionNode():
        if (blockContainsHeading(b)) {
          for (final MarkdownBlockNode child in rawFootnoteDefChildren(b)) {
            walkBlock(child);
          }
        }
      case FootnoteSectionNode():
        if (blockContainsHeading(b)) {
          for (final FootnoteDefinitionNode d in rawFootnoteSectionDefs(b)) {
            for (final MarkdownBlockNode child in rawFootnoteDefChildren(d)) {
              walkBlock(child);
            }
          }
        }
    }
  }

  walkBlock(block);
}

/// Advances [slugGenerator] across any headings contained inside [block]
/// (matching Phase 2 slug generation order) and appends outline items to
/// [outlineOut] when outline tracking is active for [options].
void collectSettledBlockOutlineAndSlugs(
  MarkdownBlockNode block,
  MarkdownOptions options,
  HeadingSlugGenerator slugGenerator,
  List<MarkdownOutlineItem> outlineOut,
) {
  void walkBlock(MarkdownBlockNode b) {
    switch (b) {
      case HeadingNode():
        final bool hasExplicit =
            options.explicitHeadingIds && b.explicitId != null;
        if (!hasExplicit && options.headingSlugs) {
          slugGenerator.generate(b.text);
        }
        if (options.headingSlugs || b.explicitId != null) {
          outlineOut.add(
            MarkdownOutlineItem(
              text: b.text,
              level: b.level,
              line: b.span.startLine,
              slug: b.slug ?? slugifyHeadingText(b.text),
              span: b.span,
            ),
          );
        }
      case FrontmatterNode():
      case ParagraphNode():
      case CodeBlockNode():
      case TableNode():
      case ThematicBreakNode():
      case HtmlBlockNode():
      case MathBlockNode():
        break;
      case BlockQuoteNode():
        if (blockContainsHeading(b)) {
          final List<MarkdownBlockNode> children = b.children;
          for (int i = 0; i < children.length; i++) {
            walkBlock(children[i]);
          }
        }
      case AlertNode():
        if (blockContainsHeading(b)) {
          final List<MarkdownBlockNode> children = b.children;
          for (int i = 0; i < children.length; i++) {
            walkBlock(children[i]);
          }
        }
      case ListNode():
        if (blockContainsHeading(b)) {
          final List<ListItemNode> items = b.items;
          for (int i = 0; i < items.length; i++) {
            final List<MarkdownBlockNode> children = items[i].children;
            for (int j = 0; j < children.length; j++) {
              walkBlock(children[j]);
            }
          }
        }
      case ListItemNode():
        if (blockContainsHeading(b)) {
          final List<MarkdownBlockNode> children = b.children;
          for (int i = 0; i < children.length; i++) {
            walkBlock(children[i]);
          }
        }
      case DetailsBlockNode():
        if (blockContainsHeading(b)) {
          final List<MarkdownBlockNode> children = b.children;
          for (int i = 0; i < children.length; i++) {
            walkBlock(children[i]);
          }
        }
      case AlignedBlockNode():
        if (blockContainsHeading(b)) {
          final List<MarkdownBlockNode> children = b.children;
          for (int i = 0; i < children.length; i++) {
            walkBlock(children[i]);
          }
        }
      case FigureBlockNode():
        if (blockContainsHeading(b)) {
          final List<MarkdownBlockNode> children = b.children;
          for (int i = 0; i < children.length; i++) {
            walkBlock(children[i]);
          }
        }
      case DefinitionListNode():
        if (blockContainsHeading(b)) {
          final List<DefinitionGroup> groups = b.groups;
          for (int i = 0; i < groups.length; i++) {
            final List<List<MarkdownBlockNode>> defs = groups[i].definitions;
            for (int j = 0; j < defs.length; j++) {
              final List<MarkdownBlockNode> def = defs[j];
              for (int k = 0; k < def.length; k++) {
                walkBlock(def[k]);
              }
            }
          }
        }
      case FootnoteDefinitionNode():
        if (blockContainsHeading(b)) {
          final List<MarkdownBlockNode> children = b.children;
          for (int i = 0; i < children.length; i++) {
            walkBlock(children[i]);
          }
        }
      case FootnoteSectionNode():
        if (blockContainsHeading(b)) {
          final List<FootnoteDefinitionNode> defs = b.definitions;
          for (int i = 0; i < defs.length; i++) {
            final List<MarkdownBlockNode> children = defs[i].children;
            for (int j = 0; j < children.length; j++) {
              walkBlock(children[j]);
            }
          }
        }
    }
  }

  walkBlock(block);
}

/// Collects heading outline entries across [blocks] (including nested
/// containers), respecting `options.headingSlugs` and explicit heading IDs.
List<MarkdownOutlineItem> collectOutlineFromBlocks(
  List<MarkdownBlockNode> blocks, {
  required MarkdownOptions options,
}) {
  final List<MarkdownOutlineItem> out = <MarkdownOutlineItem>[];

  void walk(List<MarkdownBlockNode> list) {
    for (int i = 0; i < list.length; i++) {
      final MarkdownBlockNode b = list[i];
      switch (b) {
        case HeadingNode():
          if (options.headingSlugs || b.explicitId != null) {
            out.add(
              MarkdownOutlineItem(
                text: b.text,
                level: b.level,
                line: b.span.startLine,
                slug: b.slug ?? slugifyHeadingText(b.text),
                span: b.span,
              ),
            );
          }
        case FrontmatterNode():
        case ParagraphNode():
        case CodeBlockNode():
        case TableNode():
        case ThematicBreakNode():
        case HtmlBlockNode():
        case MathBlockNode():
          break;
        case BlockQuoteNode():
          if (blockContainsHeading(b)) {
            walk(b.children);
          }
        case AlertNode():
          if (blockContainsHeading(b)) {
            walk(b.children);
          }
        case ListNode():
          if (blockContainsHeading(b)) {
            for (final ListItemNode item in b.items) {
              walk(item.children);
            }
          }
        case ListItemNode():
          if (blockContainsHeading(b)) {
            walk(b.children);
          }
        case DetailsBlockNode():
          if (blockContainsHeading(b)) {
            walk(b.children);
          }
        case AlignedBlockNode():
          if (blockContainsHeading(b)) {
            walk(b.children);
          }
        case FigureBlockNode():
          if (blockContainsHeading(b)) {
            walk(b.children);
          }
        case DefinitionListNode():
          if (blockContainsHeading(b)) {
            for (final DefinitionGroup g in b.groups) {
              for (final List<MarkdownBlockNode> def in g.definitions) {
                walk(def);
              }
            }
          }
        case FootnoteDefinitionNode():
          if (blockContainsHeading(b)) {
            walk(b.children);
          }
        case FootnoteSectionNode():
          if (blockContainsHeading(b)) {
            for (final FootnoteDefinitionNode d in b.definitions) {
              walk(d.children);
            }
          }
      }
    }
  }

  walk(blocks);
  return freezeFreshList(out);
}

/// Recomputes deduplicated heading slugs and outline items recursively across
/// all container blocks in [blocks], reusing unchanged containers by reference.
({List<MarkdownBlockNode> blocks, List<MarkdownOutlineItem> outline})
recomputeSlugsAndOutline(
  List<MarkdownBlockNode> blocks,
  MarkdownOptions options,
) {
  final HeadingSlugGenerator gen = HeadingSlugGenerator();
  final List<MarkdownOutlineItem> outline = <MarkdownOutlineItem>[];

  MarkdownBlockNode visitBlock(MarkdownBlockNode b) {
    switch (b) {
      case HeadingNode():
        final String slug = (options.explicitHeadingIds && b.explicitId != null)
            ? b.explicitId!
            : gen.generate(b.text);
        if (options.headingSlugs || b.explicitId != null) {
          outline.add(
            MarkdownOutlineItem(
              text: b.text,
              level: b.level,
              line: b.span.startLine,
              slug: slug,
              span: b.span,
            ),
          );
        }
        if (slug == b.slug) {
          return b;
        }
        return createFrozenHeadingNode(
          blockId: b.blockId,
          level: b.level,
          text: b.text,
          slug: slug,
          explicitId: b.explicitId,
          children: b.children,
          isSetext: b.isSetext,
          span: b.span,
        );
      case FrontmatterNode():
      case ParagraphNode():
      case CodeBlockNode():
      case TableNode():
      case ThematicBreakNode():
      case HtmlBlockNode():
      case MathBlockNode():
        return b;
      case BlockQuoteNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<MarkdownBlockNode> updated = _visitBlockList(
          b.children,
          visitBlock,
        );
        if (identical(updated, b.children)) {
          return b;
        }
        return createFrozenBlockQuoteNode(
          blockId: b.blockId,
          children: updated,
          span: b.span,
        );
      case AlertNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<MarkdownBlockNode> updated = _visitBlockList(
          b.children,
          visitBlock,
        );
        if (identical(updated, b.children)) {
          return b;
        }
        return createFrozenAlertNode(
          blockId: b.blockId,
          kind: b.kind,
          title: b.title,
          children: updated,
          span: b.span,
        );
      case ListNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<ListItemNode> prevItems = b.items;
        List<ListItemNode>? nextItems;
        for (int i = 0; i < prevItems.length; i++) {
          final ListItemNode item = prevItems[i];
          final ListItemNode visitedItem = visitBlock(item) as ListItemNode;
          if (!identical(visitedItem, item)) {
            nextItems ??= List<ListItemNode>.of(prevItems);
            nextItems[i] = visitedItem;
          }
        }
        if (nextItems == null) {
          return b;
        }
        return createFrozenListNode(
          blockId: b.blockId,
          ordered: b.ordered,
          start: b.start,
          tight: b.tight,
          delimiter: b.delimiter,
          items: freezeFreshList(nextItems),
          span: b.span,
        );
      case ListItemNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<MarkdownBlockNode> updated = _visitBlockList(
          b.children,
          visitBlock,
        );
        if (identical(updated, b.children)) {
          return b;
        }
        return createFrozenListItemNode(
          blockId: b.blockId,
          taskState: b.taskState,
          children: updated,
          span: b.span,
        );
      case DetailsBlockNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<MarkdownBlockNode> updated = _visitBlockList(
          b.children,
          visitBlock,
        );
        if (identical(updated, b.children)) {
          return b;
        }
        return createFrozenDetailsBlockNode(
          blockId: b.blockId,
          summary: b.summary,
          summaryInlines: b.summaryInlines,
          initiallyOpen: b.initiallyOpen,
          children: updated,
          span: b.span,
        );
      case AlignedBlockNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<MarkdownBlockNode> updated = _visitBlockList(
          b.children,
          visitBlock,
        );
        if (identical(updated, b.children)) {
          return b;
        }
        return createFrozenAlignedBlockNode(
          blockId: b.blockId,
          alignment: b.alignment,
          children: updated,
          span: b.span,
        );
      case FigureBlockNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<MarkdownBlockNode> updated = _visitBlockList(
          b.children,
          visitBlock,
        );
        if (identical(updated, b.children)) {
          return b;
        }
        return createFrozenFigureBlockNode(
          blockId: b.blockId,
          children: updated,
          caption: b.caption,
          captionInlines: b.captionInlines,
          span: b.span,
        );
      case DefinitionListNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<DefinitionGroup> prevGroups = b.groups;
        List<DefinitionGroup>? nextGroups;
        for (int gi = 0; gi < prevGroups.length; gi++) {
          final DefinitionGroup g = prevGroups[gi];
          final List<List<MarkdownBlockNode>> prevDefs = g.definitions;
          List<List<MarkdownBlockNode>>? nextDefs;
          for (int di = 0; di < prevDefs.length; di++) {
            final List<MarkdownBlockNode> def = prevDefs[di];
            final List<MarkdownBlockNode> visitedDef = _visitBlockList(
              def,
              visitBlock,
            );
            if (!identical(visitedDef, def)) {
              nextDefs ??= List<List<MarkdownBlockNode>>.of(prevDefs);
              nextDefs[di] = visitedDef;
            }
          }
          if (nextDefs != null) {
            nextGroups ??= List<DefinitionGroup>.of(prevGroups);
            nextGroups[gi] = createFrozenDefinitionGroup(
              term: g.term,
              definitions: freezeFreshList(nextDefs),
              span: g.span,
            );
          }
        }
        if (nextGroups == null) {
          return b;
        }
        return createFrozenDefinitionListNode(
          blockId: b.blockId,
          groups: freezeFreshList(nextGroups),
          span: b.span,
        );
      case FootnoteDefinitionNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<MarkdownBlockNode> updated = _visitBlockList(
          b.children,
          visitBlock,
        );
        if (identical(updated, b.children)) {
          return b;
        }
        return createFrozenFootnoteDefinitionNode(
          blockId: b.blockId,
          label: b.label,
          index: b.index,
          referenceCount: b.referenceCount,
          children: updated,
          span: b.span,
        );
      case FootnoteSectionNode():
        if (!blockContainsHeading(b)) {
          return b;
        }
        final List<FootnoteDefinitionNode> prevDefs = b.definitions;
        List<FootnoteDefinitionNode>? nextDefs;
        for (int i = 0; i < prevDefs.length; i++) {
          final FootnoteDefinitionNode d = prevDefs[i];
          final FootnoteDefinitionNode visited =
              visitBlock(d) as FootnoteDefinitionNode;
          if (!identical(visited, d)) {
            nextDefs ??= List<FootnoteDefinitionNode>.of(prevDefs);
            nextDefs[i] = visited;
          }
        }
        if (nextDefs == null) {
          return b;
        }
        return createFrozenFootnoteSectionNode(
          blockId: b.blockId,
          definitions: freezeFreshList(nextDefs),
          span: b.span,
        );
    }
  }

  final List<MarkdownBlockNode> updated = _visitBlockList(blocks, visitBlock);
  return (blocks: freezeList(updated), outline: freezeFreshList(outline));
}

List<MarkdownBlockNode> _visitBlockList(
  List<MarkdownBlockNode> list,
  MarkdownBlockNode Function(MarkdownBlockNode) visit,
) {
  List<MarkdownBlockNode>? copy;
  for (int i = 0; i < list.length; i++) {
    final MarkdownBlockNode orig = list[i];
    final MarkdownBlockNode next = visit(orig);
    if (!identical(next, orig)) {
      copy ??= List<MarkdownBlockNode>.of(list);
      copy[i] = next;
    }
  }
  return copy == null ? list : freezeFreshList(copy);
}

/// Collects deduplicated remote (`http://`, `https://`, or protocol-relative
/// `//`) image URLs across [blocks] using exhaustive AST walks.
List<String> collectRemoteImagesFromBlocks(
  List<MarkdownBlockNode> blocks, {
  MarkdownOptions? options,
}) {
  final List<String> result = <String>[];
  final Set<String> seen = <String>{};
  collectRemoteImagesInto(blocks, result, seen, options: options);
  return freezeFreshList(result);
}

/// Appends deduplicated remote image URLs from [blocks] into [result] using
/// [seen] to preserve uniqueness.
void collectRemoteImagesInto(
  List<MarkdownBlockNode> blocks,
  List<String> result,
  Set<String> seen, {
  MarkdownOptions? options,
}) {
  void addUrl(String url) {
    if (url.isEmpty) {
      return;
    }
    final String cleaned = stripControlAndWhitespaceForUrl(url);
    if (cleaned.isEmpty) {
      return;
    }
    if (options != null &&
        options.sanitizeUrls &&
        !options.urlPolicy.isAllowed(cleaned)) {
      return;
    }
    final String lower = cleaned.toLowerCase();
    if ((lower.startsWith('http://') ||
            lower.startsWith('https://') ||
            lower.startsWith('//')) &&
        seen.add(cleaned)) {
      result.add(cleaned);
    }
  }

  void walkInlines(List<MarkdownInlineNode> inlines) {
    final int len = inlines.length;
    for (int i = 0; i < len; i++) {
      final MarkdownInlineNode n = inlines[i];
      switch (n) {
        case ImageNode():
          addUrl(n.destination);
          walkInlines(n.children);
        case PictureInlineNode():
          addUrl(n.lightSource);
          addUrl(n.darkSource);
        case LinkNode():
          walkInlines(n.children);
        case EmphasisNode():
          walkInlines(n.children);
        case StrongNode():
          walkInlines(n.children);
        case StrikethroughNode():
          walkInlines(n.children);
        case HighlightNode():
          walkInlines(n.children);
        case SubscriptNode():
          walkInlines(n.children);
        case SuperscriptNode():
          walkInlines(n.children);
        case KbdInlineNode():
          walkInlines(n.children);
        case AbbrInlineNode():
          walkInlines(n.children);
        case TextNode():
        case SoftBreakNode():
        case HardBreakNode():
        case CodeSpanNode():
        case MathInlineNode():
        case FootnoteRefNode():
        case AnchorInlineNode():
        case InlineBreakNode():
        case RawHtmlInlineNode():
          break;
      }
    }
  }

  void walkBlocks(List<MarkdownBlockNode> list) {
    final int len = list.length;
    for (int i = 0; i < len; i++) {
      final MarkdownBlockNode b = list[i];
      switch (b) {
        case ParagraphNode():
          walkInlines(rawParagraphInlines(b));
        case HeadingNode():
          walkInlines(rawHeadingInlines(b));
        case BlockQuoteNode():
          walkBlocks(rawBlockQuoteChildren(b));
        case AlertNode():
          walkBlocks(rawAlertChildren(b));
        case ListNode():
          final List<ListItemNode> items = rawListItems(b);
          for (int j = 0; j < items.length; j++) {
            walkBlocks(rawListItemChildren(items[j]));
          }
        case ListItemNode():
          walkBlocks(rawListItemChildren(b));
        case TableNode():
          final List<TableCellNode> headers = rawTableHeaders(b);
          for (int j = 0; j < headers.length; j++) {
            walkInlines(rawTableCellInlines(headers[j]));
          }
          final List<List<TableCellNode>> rows = rawTableRows(b);
          for (int r = 0; r < rows.length; r++) {
            final List<TableCellNode> row = rows[r];
            for (int c = 0; c < row.length; c++) {
              walkInlines(rawTableCellInlines(row[c]));
            }
          }
        case DetailsBlockNode():
          walkInlines(rawDetailsSummaryInlines(b));
          walkBlocks(rawDetailsChildren(b));
        case AlignedBlockNode():
          walkBlocks(rawAlignedChildren(b));
        case FigureBlockNode():
          walkBlocks(rawFigureChildren(b));
          walkInlines(rawFigureCaptionInlines(b));
        case DefinitionListNode():
          final List<DefinitionGroup> groups = rawDefinitionGroups(b);
          for (int j = 0; j < groups.length; j++) {
            final DefinitionGroup g = groups[j];
            walkInlines(rawDefinitionTerm(g));
            final List<List<MarkdownBlockNode>> defs = rawDefinitionBodies(g);
            for (int k = 0; k < defs.length; k++) {
              walkBlocks(defs[k]);
            }
          }
        case FootnoteDefinitionNode():
          walkBlocks(rawFootnoteDefChildren(b));
        case FootnoteSectionNode():
          final List<FootnoteDefinitionNode> defs = rawFootnoteSectionDefs(b);
          for (int j = 0; j < defs.length; j++) {
            walkBlocks(rawFootnoteDefChildren(defs[j]));
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

  walkBlocks(blocks);
}

/// Returns whether [slice] contains a line starting with a link, footnote, or
/// abbreviation definition marker (`[...]:` or `*[...]:`) after optional leading
/// blockquote markers (`>`) and up to 3 spaces.
bool mightContainDefinitionLine(String slice) {
  if (!slice.contains(']:')) {
    return false;
  }
  int lineStart = 0;
  final int len = slice.length;
  while (lineStart < len) {
    final int nl = slice.indexOf('\n', lineStart);
    final int lineEnd = nl == -1 ? len : nl;
    if (lineLooksLikeDefinition(slice, lineStart, lineEnd)) {
      return true;
    }
    if (nl == -1) {
      break;
    }
    lineStart = nl + 1;
  }
  return false;
}

/// Checks if `text[start..end)` looks like a link/footnote/abbreviation
/// definition line (`[label]:` or `*[label]:`).
bool lineLooksLikeDefinition(String text, int start, int end) {
  int i = start;
  while (i < end) {
    int spaces = 0;
    while (i < end && spaces < 3 && text.codeUnitAt(i) == 0x20) {
      spaces++;
      i++;
    }
    if (i < end && text.codeUnitAt(i) == 0x3E) {
      i++;
      if (i < end &&
          (text.codeUnitAt(i) == 0x20 || text.codeUnitAt(i) == 0x09)) {
        i++;
      }
      continue;
    }
    break;
  }
  if (i >= end) {
    return false;
  }
  final int cu = text.codeUnitAt(i);
  if (cu == 0x5B) {
    final int closeIdx = text.indexOf(']:', i + 1);
    return closeIdx != -1 && closeIdx < end;
  }
  if (cu == 0x2A && i + 1 < end && text.codeUnitAt(i + 1) == 0x5B) {
    final int closeIdx = text.indexOf(']:', i + 2);
    return closeIdx != -1 && closeIdx < end;
  }
  return false;
}

/// Returns whether [block] is a raw HTML container opener/closer tag when
/// structured HTML container extensions (`<details>`, `<figure>`, `<div align>`)
/// are enabled.
bool isPotentialHtmlContainerBoundary(
  MarkdownBlockNode block,
  MarkdownOptions options,
) {
  if (!options.detailsBlocks &&
      !options.figureBlocks &&
      !options.alignedBlocks) {
    return false;
  }
  if (block is HtmlBlockNode) {
    return true;
  }
  return false;
}
