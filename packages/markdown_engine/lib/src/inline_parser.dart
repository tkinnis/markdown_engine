import 'ast.dart';
import 'block_parser.dart';
import 'budgets.dart';
import 'emoji.dart';
import 'entities.dart';
import 'options.dart';
import 'slugs.dart';
import 'unicode.dart';
import 'url_utils.dart';

/// Phase 2 resolution output containing finalized immutable AST blocks,
/// document outline, ordered footnotes, and remote image addresses.
final class Phase2Result {
  /// Creates a [Phase2Result].
  const Phase2Result({
    required this.blocks,
    required this.outline,
    required this.footnotes,
    required this.remoteImageAddresses,
  });

  /// Finalized top-level block AST nodes.
  final List<MarkdownBlockNode> blocks;

  /// Extracted heading outline items.
  final List<MarkdownOutlineItem> outline;

  /// Referenced footnotes in first-citation order (followed by any unreferenced
  /// definitions if inspected via `MarkdownDocument.footnotes`).
  final List<FootnoteDefinitionNode> footnotes;

  /// Deduplicated `http:`/`https:` image URLs referenced in the document.
  final List<String> remoteImageAddresses;
}

/// Resolves inline syntax, links, images, emphasis, autolinks, math, footnotes,
/// slugs, and extensions across a Phase 1 block tree.
Phase2Result parseInlines(Phase1Result phase1, MarkdownOptions options) {
  final _InlineResolver resolver = _InlineResolver(
    options: options,
    budgets: options.effectiveBudgets,
    linkDefinitions: phase1.linkDefinitions,
    rawFootnotes: phase1.footnoteDefinitions,
    abbreviations: phase1.abbreviations,
  );
  return resolver.resolveDocument(phase1.blocks);
}

final class _InlineResolver {
  _InlineResolver({
    required this.options,
    required this.budgets,
    required this.linkDefinitions,
    required this.rawFootnotes,
    required this.abbreviations,
  });

  final MarkdownOptions options;
  final MarkdownBudgets budgets;
  final Map<String, MarkdownLinkDefinition> linkDefinitions;
  final Map<String, RawFootnoteDef> rawFootnotes;
  final Map<String, String> abbreviations;

  final HeadingSlugGenerator _slugs = HeadingSlugGenerator();
  final List<MarkdownOutlineItem> _outline = <MarkdownOutlineItem>[];
  final List<String> _remoteImages = <String>[];
  final Set<String> _remoteImageSet = <String>{};

  // Footnote citation tracking in order of first reference.
  final List<String> _citedFootnoteOrder = <String>[];
  final Map<String, int> _footnoteIndexByLabel = <String, int>{};
  final Map<String, int> _footnoteRefCountByLabel = <String, int>{};
  final Map<String, FootnoteDefinitionNode> _resolvedFootnotes =
      <String, FootnoteDefinitionNode>{};

  int _synthCounter = 0;

  Phase2Result resolveDocument(List<RawBlock> rawBlocks) {
    final List<MarkdownBlockNode> resolvedBlocks = _resolveBlockList(rawBlocks);

    // Resolve cited footnotes iteratively so footnote-in-footnote references
    // are discovered in citation order without risking cycles.
    int queueIdx = 0;
    while (queueIdx < _citedFootnoteOrder.length) {
      final String label = _citedFootnoteOrder[queueIdx];
      queueIdx++;
      final RawFootnoteDef? rawDef = rawFootnotes[label];
      if (rawDef == null) {
        continue;
      }
      final List<MarkdownBlockNode> body = _resolveBlockList(rawDef.children);
      _resolvedFootnotes[label] = FootnoteDefinitionNode(
        blockId: rawDef.blockId,
        span: rawDef.span,
        label: rawDef.label,
        index: _footnoteIndexByLabel[label]!,
        referenceCount: _footnoteRefCountByLabel[label] ?? 1,
        children: body,
      );
    }

    // Update final referenceCounts in case footnotes referenced earlier ones.
    final List<FootnoteDefinitionNode> orderedCited =
        <FootnoteDefinitionNode>[];
    for (final String label in _citedFootnoteOrder) {
      final FootnoteDefinitionNode? def = _resolvedFootnotes[label];
      if (def != null) {
        orderedCited.add(
          FootnoteDefinitionNode(
            blockId: def.blockId,
            span: def.span,
            label: def.label,
            index: _footnoteIndexByLabel[label]!,
            referenceCount: _footnoteRefCountByLabel[label] ?? 1,
            children: def.children,
          ),
        );
      }
    }

    final List<MarkdownBlockNode> finalBlocks = <MarkdownBlockNode>[
      ...resolvedBlocks,
    ];
    if (orderedCited.isNotEmpty) {
      finalBlocks.add(
        FootnoteSectionNode(
          blockId: 'footnote-section',
          definitions: orderedCited,
          span: orderedCited.first.span,
        ),
      );
    }

    // Also resolve unreferenced footnote definitions for `document.footnotes`.
    final List<FootnoteDefinitionNode> allFootnotes = <FootnoteDefinitionNode>[
      ...orderedCited,
    ];
    for (final MapEntry<String, RawFootnoteDef> entry in rawFootnotes.entries) {
      if (!_footnoteIndexByLabel.containsKey(entry.key)) {
        final RawFootnoteDef rawDef = entry.value;
        allFootnotes.add(
          FootnoteDefinitionNode(
            blockId: rawDef.blockId,
            span: rawDef.span,
            label: rawDef.label,
            index: 0,
            referenceCount: 0,
            children: _resolveBlockList(rawDef.children),
          ),
        );
      }
    }

    return Phase2Result(
      blocks: finalBlocks,
      outline: _outline,
      footnotes: allFootnotes,
      remoteImageAddresses: _remoteImages,
    );
  }

  List<MarkdownBlockNode> _resolveBlockList(List<RawBlock> rawBlocks) {
    final List<MarkdownBlockNode> out = <MarkdownBlockNode>[];
    for (final RawBlock raw in rawBlocks) {
      out.add(_resolveBlock(raw));
    }
    return out;
  }

  MarkdownBlockNode _resolveBlock(RawBlock raw) {
    switch (raw) {
      case RawFrontmatter():
        return raw.node;
      case RawParagraph():
        return ParagraphNode(
          blockId: raw.blockId,
          span: raw.span,
          children: _parseInlineString(raw.rawText, raw.span),
        );
      case RawHeading():
        final List<MarkdownInlineNode> children = _parseInlineString(
          raw.rawText,
          raw.span,
        );
        final String plain = _extractPlainText(children);
        String? slug;
        if (options.explicitHeadingIds && raw.explicitId != null) {
          slug = raw.explicitId;
        } else if (options.headingSlugs) {
          slug = _slugs.generate(plain);
        }
        if (options.headingSlugs || raw.explicitId != null) {
          _outline.add(
            MarkdownOutlineItem(
              text: plain,
              level: raw.level,
              line: raw.span.startLine,
              slug: slug ?? slugifyHeadingText(plain),
              span: raw.span,
            ),
          );
        }
        return HeadingNode(
          blockId: raw.blockId,
          span: raw.span,
          level: raw.level,
          text: plain,
          slug: slug,
          explicitId: raw.explicitId,
          children: children,
          isSetext: raw.isSetext,
        );
      case RawCodeBlock():
        return CodeBlockNode(
          blockId: raw.blockId,
          span: raw.span,
          info: raw.info,
          language: raw.language,
          literal: raw.literal,
          isFenced: raw.isFenced,
          codeUnitOffset: raw.codeUnitOffset,
        );
      case RawThematicBreak():
        return ThematicBreakNode(blockId: raw.blockId, span: raw.span);
      case RawHtmlBlock():
        return HtmlBlockNode(
          blockId: raw.blockId,
          span: raw.span,
          literal: raw.literal,
          blockType: raw.blockType,
        );
      case RawMathBlock():
        return MathBlockNode(
          blockId: raw.blockId,
          span: raw.span,
          latex: raw.latex,
        );
      case RawBlockQuote():
        return BlockQuoteNode(
          blockId: raw.blockId,
          span: raw.span,
          children: _resolveBlockList(raw.children),
        );
      case RawAlert():
        return AlertNode(
          blockId: raw.blockId,
          span: raw.span,
          kind: raw.kind,
          title: raw.title,
          children: _resolveBlockList(raw.children),
        );
      case RawList():
        return ListNode(
          blockId: raw.blockId,
          span: raw.span,
          ordered: raw.ordered,
          start: raw.start,
          tight: raw.tight,
          delimiter: raw.delimiter,
          items: raw.items
              .map(
                (RawListItem item) => ListItemNode(
                  blockId: item.blockId,
                  span: item.span,
                  taskState: item.taskState,
                  children: _resolveBlockList(item.children),
                ),
              )
              .toList(growable: false),
        );
      case RawListItem():
        return ListItemNode(
          blockId: raw.blockId,
          span: raw.span,
          taskState: raw.taskState,
          children: _resolveBlockList(raw.children),
        );
      case RawTable():
        final int colCount = raw.alignments.length;
        final List<TableCellNode> headers = <TableCellNode>[];
        for (int c = 0; c < colCount; c++) {
          final String cellText = c < raw.headerCells.length
              ? raw.headerCells[c]
              : '';
          headers.add(
            TableCellNode(
              children: _parseInlineString(cellText, raw.span),
              alignment: raw.alignments[c],
              span: raw.span,
            ),
          );
        }
        final List<List<TableCellNode>> rows = <List<TableCellNode>>[];
        for (final List<String> rawRow in raw.rows) {
          final List<TableCellNode> row = <TableCellNode>[];
          for (int c = 0; c < colCount; c++) {
            final String cellText = c < rawRow.length ? rawRow[c] : '';
            row.add(
              TableCellNode(
                children: _parseInlineString(cellText, raw.span),
                alignment: raw.alignments[c],
                span: raw.span,
              ),
            );
          }
          rows.add(row);
        }
        return TableNode(
          blockId: raw.blockId,
          span: raw.span,
          alignments: raw.alignments,
          headers: headers,
          rows: rows,
        );
      case RawDefinitionList():
        final List<DefinitionGroup> groups = raw.groups
            .map(
              (RawDefGroup g) => DefinitionGroup(
                term: _parseInlineString(g.termRaw, g.span),
                definitions: g.definitions
                    .map((List<RawBlock> d) => _resolveBlockList(d))
                    .toList(growable: false),
                span: g.span,
              ),
            )
            .toList(growable: false);
        return DefinitionListNode(
          blockId: raw.blockId,
          span: raw.span,
          groups: groups,
        );
      case RawFootnoteDef():
        return FootnoteDefinitionNode(
          blockId: raw.blockId,
          span: raw.span,
          label: raw.label,
          children: _resolveBlockList(raw.children),
        );
      case RawDetailsBlock():
        final List<MarkdownInlineNode> sumInlines = _parseInlineString(
          raw.summaryRaw,
          raw.span,
        );
        return DetailsBlockNode(
          blockId: raw.blockId,
          span: raw.span,
          summary: _extractPlainText(sumInlines),
          summaryInlines: sumInlines,
          initiallyOpen: raw.initiallyOpen,
          children: _resolveBlockList(raw.children),
        );
      case RawAlignedBlock():
        return AlignedBlockNode(
          blockId: raw.blockId,
          span: raw.span,
          alignment: raw.alignment,
          children: _resolveBlockList(raw.children),
        );
      case RawFigureBlock():
        final String? cap = raw.captionRaw;
        final List<MarkdownInlineNode> capInlines = cap == null
            ? const <MarkdownInlineNode>[]
            : _parseInlineString(cap, raw.span);
        return FigureBlockNode(
          blockId: raw.blockId,
          span: raw.span,
          children: _resolveBlockList(raw.children),
          caption: cap == null ? null : _extractPlainText(capInlines),
          captionInlines: capInlines,
        );
    }
  }

  List<MarkdownInlineNode> _parseInlineString(
    String input,
    SourceSpan blockSpan,
  ) {
    if (input.isEmpty) {
      return const <MarkdownInlineNode>[];
    }
    final _InlineScanner scanner = _InlineScanner(
      input: input,
      blockSpan: blockSpan,
      resolver: this,
    );
    return scanner.parse();
  }

  FootnoteRefNode? _registerFootnoteRef(String label, SourceSpan span) {
    if (!rawFootnotes.containsKey(label)) {
      return null;
    }
    int? index = _footnoteIndexByLabel[label];
    if (index == null) {
      _citedFootnoteOrder.add(label);
      index = _citedFootnoteOrder.length;
      _footnoteIndexByLabel[label] = index;
    }
    final int occurrence = (_footnoteRefCountByLabel[label] ?? 0) + 1;
    _footnoteRefCountByLabel[label] = occurrence;
    return FootnoteRefNode(
      label: label,
      index: index,
      occurrenceIndex: occurrence,
      span: span,
    );
  }

  String _sanitizeDestination(String url) {
    if (!options.sanitizeUrls) {
      return url;
    }
    return options.urlPolicy.sanitize(url);
  }

  void _recordImageUrl(String url) {
    if (url.isEmpty) {
      return;
    }
    final String lower = url.toLowerCase();
    if ((lower.startsWith('http://') || lower.startsWith('https://')) &&
        _remoteImageSet.add(url)) {
      _remoteImages.add(url);
    }
  }

  String nextId(String prefix) {
    _synthCounter++;
    return '$prefix-$_synthCounter';
  }
}

final class _InlineItem {
  _InlineItem.node(this.node) : isText = node is TextNode;

  _InlineItem.delim({
    required this.delimChar,
    required this.delimCount,
    required this.origCount,
    required this.canOpen,
    required this.canClose,
    required SourceSpan span,
  }) : isText = true,
       node = TextNode(String.fromCharCode(delimChar) * delimCount, span: span);

  MarkdownInlineNode node;
  bool isText;
  int delimChar = 0;
  int delimCount = 0;
  int origCount = 0;
  bool canOpen = false;
  bool canClose = false;
  bool isDelimiter = false;
  bool isBracket = false;
  bool bracketIsImage = false;
  bool bracketActive = true;
  int bracketSourcePos = 0;
}

final class _InlineScanner {
  _InlineScanner({
    required this.input,
    required this.blockSpan,
    required this.resolver,
  });

  final String input;
  final SourceSpan blockSpan;
  final _InlineResolver resolver;

  final List<_InlineItem> _items = <_InlineItem>[];
  final List<int> _delimiterIndices = <int>[];
  final List<int> _bracketIndices = <int>[];
  final Set<int> _unmatchedBacktickLengths = <int>{};
  int _tokenCount = 0;

  MarkdownOptions get options => resolver.options;
  MarkdownBudgets get budgets => resolver.budgets;

  SourceSpan _span(int start, int end) {
    final int base = blockSpan.startOffset;
    return SourceSpan(
      startOffset: base + start,
      endOffset: base + end,
      startLine: blockSpan.startLine,
      endLine: blockSpan.endLine,
    );
  }

  List<MarkdownInlineNode> parse() {
    final int len = input.length;
    int pos = 0;

    while (pos < len) {
      _tokenCount++;
      if (_tokenCount > budgets.maxTokens) {
        _appendText(input.substring(pos), _span(pos, len));
        break;
      }

      final int cu = input.codeUnitAt(pos);

      switch (cu) {
        case 0x0A: // '\n'
          pos = _handleNewline(pos);
        case 0x5C: // '\\'
          pos = _handleBackslash(pos);
        case 0x60: // '`'
          pos = _handleBackticks(pos);
        case 0x26: // '&'
          pos = _handleEntity(pos);
        case 0x3C: // '<'
          pos = _handleOpenAngle(pos);
        case 0x5B: // '['
          pos = _handleOpenBracket(pos, isImage: false);
        case 0x21: // '!'
          if (pos + 1 < len && input.codeUnitAt(pos + 1) == 0x5B) {
            if (options.footnotes &&
                pos + 3 < len &&
                input.codeUnitAt(pos + 2) == 0x5E) {
              final int closeFn = _findFootnoteClose(pos + 3);
              if (closeFn != -1 &&
                  resolver.rawFootnotes.containsKey(
                    input.substring(pos + 3, closeFn),
                  )) {
                _appendText('!', _span(pos, pos + 1));
                pos++;
                break;
              }
            }
            pos = _handleOpenBracket(pos, isImage: true);
          } else {
            _appendText('!', _span(pos, pos + 1));
            pos++;
          }
        case 0x5D: // ']'
          pos = _handleCloseBracket(pos);
        case 0x2A: // '*'
        case 0x5F: // '_'
          pos = _handleDelimiterRun(pos, cu);
        case 0x7E: // '~'
          if (options.gfmStrikethrough || options.subscript) {
            pos = _handleDelimiterRun(pos, cu);
          } else {
            _appendText('~', _span(pos, pos + 1));
            pos++;
          }
        case 0x3D: // '='
          if (options.highlight &&
              pos + 1 < len &&
              input.codeUnitAt(pos + 1) == 0x3D) {
            pos = _handleDelimiterRun(pos, cu);
          } else {
            _appendText('=', _span(pos, pos + 1));
            pos++;
          }
        case 0x5E: // '^'
          if (options.superscript) {
            pos = _handleDelimiterRun(pos, cu);
          } else {
            _appendText('^', _span(pos, pos + 1));
            pos++;
          }
        case 0x24: // '$'
          if (options.math) {
            pos = _handleInlineMath(pos);
          } else {
            _appendText(r'$', _span(pos, pos + 1));
            pos++;
          }
        default:
          pos = _scanPlainText(pos);
      }
    }

    _processEmphasis(-1);

    List<MarkdownInlineNode> nodes = _coalesceTextNodes(
      _collectActiveNodes(0, _items.length),
    );
    if (options.gfmAutolinks) {
      nodes = _applyGfmAutolinks(nodes);
    }
    if (options.emoji) {
      nodes = _applyEmojiShortcodes(nodes);
    }
    if (options.smartPunctuation) {
      nodes = _applySmartPunctuation(nodes);
    }
    if (options.abbreviations && resolver.abbreviations.isNotEmpty) {
      nodes = _applyAbbreviations(nodes);
    }
    return _coalesceTextNodes(nodes);
  }

  int _scanPlainText(int start) {
    int i = start + 1;
    final int len = input.length;
    while (i < len) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x0A ||
          cu == 0x5C ||
          cu == 0x60 ||
          cu == 0x26 ||
          cu == 0x3C ||
          cu == 0x5B ||
          cu == 0x5D ||
          cu == 0x21 ||
          cu == 0x2A ||
          cu == 0x5F ||
          ((cu == 0x7E) && (options.gfmStrikethrough || options.subscript)) ||
          ((cu == 0x3D) && options.highlight) ||
          ((cu == 0x5E) && options.superscript) ||
          ((cu == 0x24) && options.math)) {
        break;
      }
      i++;
    }
    _appendText(input.substring(start, i), _span(start, i));
    return i;
  }

  void _appendText(String text, SourceSpan span) {
    if (text.isEmpty) {
      return;
    }
    if (_items.isNotEmpty) {
      final _InlineItem last = _items.last;
      if (last.isText && !last.isDelimiter && !last.isBracket) {
        final TextNode prev = last.node as TextNode;
        last.node = TextNode(
          '${prev.text}$text',
          span: SourceSpan(
            startOffset: prev.span.startOffset,
            endOffset: span.endOffset,
            startLine: prev.span.startLine,
            endLine: span.endLine,
          ),
        );
        return;
      }
    }
    _items.add(_InlineItem.node(TextNode(text, span: span)));
  }

  int _handleNewline(int pos) {
    // Check trailing spaces in preceding plain text item.
    if (_items.isNotEmpty) {
      final _InlineItem last = _items.last;
      if (last.isText && !last.isDelimiter && !last.isBracket) {
        final TextNode prev = last.node as TextNode;
        int trailingSpaces = 0;
        for (int k = prev.text.length - 1; k >= 0; k--) {
          if (prev.text.codeUnitAt(k) == 0x20) {
            trailingSpaces++;
          } else {
            break;
          }
        }
        if (trailingSpaces > 0) {
          final String trimmed = prev.text.substring(
            0,
            prev.text.length - trailingSpaces,
          );
          if (trimmed.isEmpty) {
            _items.removeLast();
          } else {
            last.node = TextNode(trimmed, span: prev.span);
          }
          if (trailingSpaces >= 2) {
            _items.add(
              _InlineItem.node(HardBreakNode(span: _span(pos, pos + 1))),
            );
          } else {
            _items.add(
              _InlineItem.node(SoftBreakNode(span: _span(pos, pos + 1))),
            );
          }
          return _skipLeadingSpacesAfterNewline(pos + 1);
        }
      }
    }
    _items.add(_InlineItem.node(SoftBreakNode(span: _span(pos, pos + 1))));
    return _skipLeadingSpacesAfterNewline(pos + 1);
  }

  int _skipLeadingSpacesAfterNewline(int pos) {
    int i = pos;
    while (i < input.length) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x20 || cu == 0x09) {
        i++;
      } else {
        break;
      }
    }
    return i;
  }

  int _handleBackslash(int pos) {
    if (pos + 1 >= input.length) {
      _appendText(r'\', _span(pos, pos + 1));
      return pos + 1;
    }
    final int next = input.codeUnitAt(pos + 1);
    if (next == 0x0A) {
      _items.add(_InlineItem.node(HardBreakNode(span: _span(pos, pos + 2))));
      return _skipLeadingSpacesAfterNewline(pos + 2);
    }
    if (isAsciiPunctuation(next)) {
      _appendText(String.fromCharCode(next), _span(pos, pos + 2));
      return pos + 2;
    }
    _appendText(r'\', _span(pos, pos + 1));
    return pos + 1;
  }

  int _handleBackticks(int pos) {
    int count = 0;
    int i = pos;
    while (i < input.length && input.codeUnitAt(i) == 0x60) {
      count++;
      i++;
    }
    if (_unmatchedBacktickLengths.contains(count)) {
      _appendText(input.substring(pos, i), _span(pos, i));
      return i;
    }
    int search = i;
    while (search < input.length) {
      if (input.codeUnitAt(search) == 0x60) {
        int closeCount = 0;
        final int closeStart = search;
        while (search < input.length && input.codeUnitAt(search) == 0x60) {
          closeCount++;
          search++;
        }
        if (closeCount == count) {
          String raw = input.substring(i, closeStart).replaceAll('\n', ' ');
          if (raw.length >= 2 &&
              raw.codeUnitAt(0) == 0x20 &&
              raw.codeUnitAt(raw.length - 1) == 0x20) {
            bool hasNonSpace = false;
            for (int k = 0; k < raw.length; k++) {
              if (raw.codeUnitAt(k) != 0x20) {
                hasNonSpace = true;
                break;
              }
            }
            if (hasNonSpace) {
              raw = raw.substring(1, raw.length - 1);
            }
          }
          _items.add(
            _InlineItem.node(CodeSpanNode(raw, span: _span(pos, search))),
          );
          return search;
        }
      } else {
        search++;
      }
    }
    _unmatchedBacktickLengths.add(count);
    _appendText(input.substring(pos, i), _span(pos, i));
    return i;
  }

  int _handleEntity(int pos) {
    final ({String text, int nextIndex})? decoded = decodeCharacterReference(
      input,
      pos,
    );
    if (decoded != null) {
      _appendText(decoded.text, _span(pos, decoded.nextIndex));
      return decoded.nextIndex;
    }
    _appendText('&', _span(pos, pos + 1));
    return pos + 1;
  }

  int _handleInlineMath(int pos) {
    // Reject `$$` inside inline stream (leave as literal `$`).
    if (pos + 1 >= input.length || input.codeUnitAt(pos + 1) == 0x24) {
      _appendText(r'$', _span(pos, pos + 1));
      return pos + 1;
    }
    final int nextCu = input.codeUnitAt(pos + 1);
    if (isAsciiWhitespace(nextCu)) {
      _appendText(r'$', _span(pos, pos + 1));
      return pos + 1;
    }
    // Scan forward for closing `$`.
    int i = pos + 1;
    while (i < input.length) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x5C && i + 1 < input.length) {
        i += 2;
        continue;
      }
      if (cu == 0x24) {
        final bool precededBySpace = isAsciiWhitespace(input.codeUnitAt(i - 1));
        final bool followedByDigit =
            i + 1 < input.length && isAsciiDigit(input.codeUnitAt(i + 1));
        final bool isDoubleDollar =
            i + 1 < input.length && input.codeUnitAt(i + 1) == 0x24;
        if (!precededBySpace && !followedByDigit && !isDoubleDollar) {
          final String latex = input.substring(pos + 1, i);
          if (latex.isNotEmpty) {
            _items.add(
              _InlineItem.node(MathInlineNode(latex, span: _span(pos, i + 1))),
            );
            return i + 1;
          }
        }
      }
      i++;
    }
    _appendText(r'$', _span(pos, pos + 1));
    return pos + 1;
  }

  int _handleOpenAngle(int pos) {
    // 1. CommonMark URI autolink or email autolink.
    final ({String href, String label, int nextIndex})? auto =
        _matchAngleAutolink(pos);
    if (auto != null) {
      final String sanitized = resolver._sanitizeDestination(auto.href);
      _items.add(
        _InlineItem.node(
          LinkNode(
            destination: sanitized,
            isAutolink: true,
            children: <MarkdownInlineNode>[
              TextNode(auto.label, span: _span(pos + 1, auto.nextIndex - 1)),
            ],
            span: _span(pos, auto.nextIndex),
          ),
        ),
      );
      return auto.nextIndex;
    }

    // 2. CommonMark raw HTML inline.
    final int? htmlEnd = _matchRawHtmlInline(pos);
    if (htmlEnd != null) {
      final String rawHtml = input.substring(pos, htmlEnd);
      if (options.inlineBreaks &&
          RegExp(r'^<br\s*/?>$', caseSensitive: false).hasMatch(rawHtml)) {
        _items.add(
          _InlineItem.node(InlineBreakNode(span: _span(pos, htmlEnd))),
        );
        return htmlEnd;
      }
      if (options.kbd) {
        final RegExpMatch? kbdMatch = RegExp(
          r'^<kbd>(.*)</kbd>$',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(rawHtml);
        if (kbdMatch != null) {
          _items.add(
            _InlineItem.node(
              KbdInlineNode(
                children: <MarkdownInlineNode>[TextNode(kbdMatch.group(1)!)],
                span: _span(pos, htmlEnd),
              ),
            ),
          );
          return htmlEnd;
        }
      }
      if (options.explicitHeadingIds) {
        final RegExpMatch? anchorMatch = RegExp(
          r'''^<a\s+id=["']([^"']+)["']\s*>$''',
          caseSensitive: false,
        ).firstMatch(rawHtml);
        if (anchorMatch != null && input.startsWith('</a>', htmlEnd)) {
          _items.add(
            _InlineItem.node(
              AnchorInlineNode(
                anchorMatch.group(1)!,
                span: _span(pos, htmlEnd + 4),
              ),
            ),
          );
          return htmlEnd + 4;
        }
      }
      if (options.figureBlocks &&
          rawHtml.toLowerCase().startsWith('<picture')) {
        final int closePic = input.toLowerCase().indexOf('</picture>', pos);
        if (closePic != -1) {
          final String fullPic = input.substring(pos, closePic + 10);
          final PictureInlineNode? picNode = _tryParsePicture(
            fullPic,
            _span(pos, closePic + 10),
          );
          if (picNode != null) {
            resolver._recordImageUrl(picNode.lightSource);
            resolver._recordImageUrl(picNode.darkSource);
            _items.add(_InlineItem.node(picNode));
            return closePic + 10;
          }
        }
      }
      if (options.kbd && rawHtml.toLowerCase() == '<kbd>') {
        final int closeKbd = input.toLowerCase().indexOf('</kbd>', htmlEnd);
        if (closeKbd != -1) {
          final String inner = input.substring(htmlEnd, closeKbd);
          _items.add(
            _InlineItem.node(
              KbdInlineNode(
                children: <MarkdownInlineNode>[
                  TextNode(inner, span: _span(htmlEnd, closeKbd)),
                ],
                span: _span(pos, closeKbd + 6),
              ),
            ),
          );
          return closeKbd + 6;
        }
      }
      _items.add(
        _InlineItem.node(RawHtmlInlineNode(rawHtml, span: _span(pos, htmlEnd))),
      );
      return htmlEnd;
    }

    _appendText('<', _span(pos, pos + 1));
    return pos + 1;
  }

  PictureInlineNode? _tryParsePicture(String html, SourceSpan span) {
    final RegExpMatch? darkMatch = RegExp(
      r'''prefers-color-scheme\s*:\s*dark[^>]*srcset\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final RegExpMatch? imgMatch = RegExp(
      r'''<img\b[^>]*src\s*=\s*["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    ).firstMatch(html);
    if (darkMatch == null || imgMatch == null) {
      return null;
    }
    final RegExpMatch? altMatch = RegExp(
      r'''alt\s*=\s*["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(imgMatch.group(0)!);
    return PictureInlineNode(
      lightSource: resolver._sanitizeDestination(imgMatch.group(1)!),
      darkSource: resolver._sanitizeDestination(darkMatch.group(1)!),
      alt: altMatch?.group(1) ?? '',
      span: span,
    );
  }

  ({String href, String label, int nextIndex})? _matchAngleAutolink(int pos) {
    final int len = input.length;
    final int close = input.indexOf('>', pos + 1);
    if (close == -1) {
      return null;
    }
    final String inside = input.substring(pos + 1, close);
    if (inside.contains('<') || inside.contains('\n')) {
      return null;
    }
    if (_uriAutolinkPattern.hasMatch(inside)) {
      return (href: inside, label: inside, nextIndex: close + 1);
    }
    if (_emailAutolinkPattern.hasMatch(inside)) {
      return (href: 'mailto:$inside', label: inside, nextIndex: close + 1);
    }
    final _ = len;
    return null;
  }

  int? _matchRawHtmlInline(int pos) {
    final String sub = input.substring(pos);
    // 1. HTML comment (CommonMark 0.31.2: `<!-->`, `<!--->`, or `<!--...-->`).
    if (sub.startsWith('<!-->')) {
      return pos + 5;
    }
    if (sub.startsWith('<!--->')) {
      return pos + 6;
    }
    if (sub.startsWith('<!--')) {
      final int end = sub.indexOf('-->', 4);
      if (end != -1) {
        return pos + end + 3;
      }
      return null;
    }
    // 2. Processing instruction `<?...?>`.
    if (sub.startsWith('<?')) {
      final int end = sub.indexOf('?>', 2);
      if (end != -1) {
        return pos + end + 2;
      }
      return null;
    }
    // 3. CDATA `<![CDATA[...]]>`.
    if (sub.startsWith('<![CDATA[')) {
      final int end = sub.indexOf(']]>', 9);
      if (end != -1) {
        return pos + end + 3;
      }
      return null;
    }
    // 4. Declaration `<!NAME ...>`.
    final RegExpMatch? decl = _inlineHtmlDeclPattern.firstMatch(sub);
    if (decl != null) {
      return pos + decl.end;
    }
    // 5. Open tag or closing tag.
    final RegExpMatch? tag = _inlineHtmlTagPattern.firstMatch(sub);
    if (tag != null) {
      return pos + tag.end;
    }
    return null;
  }

  int _handleOpenBracket(int pos, {required bool isImage}) {
    // Check footnote reference `[^label]` when enabled and not an image.
    if (!isImage &&
        options.footnotes &&
        pos + 2 < input.length &&
        input.codeUnitAt(pos + 1) == 0x5E) {
      final int close = _findFootnoteClose(pos + 2);
      if (close != -1) {
        final String label = input.substring(pos + 2, close);
        final FootnoteRefNode? fnRef = resolver._registerFootnoteRef(
          label,
          _span(pos, close + 1),
        );
        if (fnRef != null) {
          _items.add(_InlineItem.node(fnRef));
          return close + 1;
        }
      }
    }

    final int markerLen = isImage ? 2 : 1;
    // Enforce maxNestingDepth on bracket stack to guard against hostile deep nesting.
    if (_bracketIndices.length >= budgets.maxNestingDepth) {
      _appendText(isImage ? '![' : '[', _span(pos, pos + markerLen));
      return pos + markerLen;
    }

    final _InlineItem item =
        _InlineItem.node(
            TextNode(isImage ? '![' : '[', span: _span(pos, pos + markerLen)),
          )
          ..isBracket = true
          ..bracketIsImage = isImage
          ..bracketSourcePos = pos;
    final int idx = _items.length;
    _items.add(item);
    _bracketIndices.add(idx);
    return pos + markerLen;
  }

  int _findFootnoteClose(int start) {
    int i = start;
    while (i < input.length) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x5D) {
        return i > start ? i : -1;
      }
      if (cu == 0x5B || isAsciiWhitespace(cu) || cu == 0x0A) {
        return -1;
      }
      i++;
    }
    return -1;
  }

  int _handleCloseBracket(int pos) {
    if (_bracketIndices.isEmpty) {
      _appendText(']', _span(pos, pos + 1));
      return pos + 1;
    }

    final int openerItemIdx = _bracketIndices.removeLast();
    final _InlineItem opener = _items[openerItemIdx];
    if (!opener.bracketActive) {
      _appendText(']', _span(pos, pos + 1));
      return pos + 1;
    }

    final bool isImage = opener.bracketIsImage;
    int afterBracket = pos + 1;
    String? destination;
    String? title;
    bool matched = false;

    // Case 1: Inline link/image `(dest "title")`.
    if (afterBracket < input.length && input.codeUnitAt(afterBracket) == 0x28) {
      final ({String destination, String? title, int nextIndex})? inlineTarget =
          _parseInlineLinkTarget(afterBracket);
      if (inlineTarget != null) {
        destination = inlineTarget.destination;
        title = inlineTarget.title;
        afterBracket = inlineTarget.nextIndex;
        matched = true;
      }
    }

    // Case 2: Reference link/image (`[foo][bar]`, `[foo][]`, or `[foo]`).
    if (!matched) {
      String? refLabel;
      int nextAfterRef = afterBracket;

      if (afterBracket < input.length &&
          input.codeUnitAt(afterBracket) == 0x5B) {
        final ({String label, int nextIndex})? explicitRef = _parseBracketLabel(
          afterBracket,
        );
        if (explicitRef != null) {
          if (explicitRef.label.isEmpty) {
            // Collapsed reference `[foo][]`.
            refLabel = input.substring(
              opener.bracketSourcePos + (isImage ? 2 : 1),
              pos,
            );
          } else {
            // Full reference `[foo][bar]`.
            refLabel = explicitRef.label;
          }
          nextAfterRef = explicitRef.nextIndex;
        }
      }

      // Shortcut reference `[foo]` (note: if `[foo][]` failed above or no `[` follows).
      if (refLabel == null) {
        refLabel = input.substring(
          opener.bracketSourcePos + (isImage ? 2 : 1),
          pos,
        );
        nextAfterRef = afterBracket;
      }

      final String normalized = normalizeLinkLabel(refLabel);
      if (normalized.isNotEmpty) {
        final MarkdownLinkDefinition? def =
            resolver.linkDefinitions[normalized];
        if (def != null) {
          destination = def.destination;
          title = def.title;
          afterBracket = nextAfterRef;
          matched = true;
        }
      }
    }

    if (!matched) {
      _appendText(']', _span(pos, pos + 1));
      return pos + 1;
    }

    // Process emphasis strictly inside the bracket slice `[openerItemIdx+1 ..]`.
    final int delimBottom = _findDelimiterBottomAfter(openerItemIdx);
    _processEmphasis(delimBottom);

    // Collect children inside the bracket.
    final List<MarkdownInlineNode> rawChildren = _collectActiveNodes(
      openerItemIdx + 1,
      _items.length,
    );
    List<MarkdownInlineNode> children = rawChildren;
    if (options.gfmAutolinks && isImage == false) {
      // Do not run autolinks inside LinkNode, so skip here!
    }
    children = _coalesceTextNodes(children);

    final String safeDest = resolver._sanitizeDestination(destination ?? '');

    // Remove inner items and opener from `_items` and `_delimiterIndices`.
    _items.removeRange(openerItemIdx, _items.length);
    _delimiterIndices.removeWhere((int idx) => idx >= openerItemIdx);

    if (isImage) {
      resolver._recordImageUrl(safeDest);
      final String alt = _extractAltText(children);
      _items.add(
        _InlineItem.node(
          ImageNode(
            destination: safeDest,
            alt: alt,
            title: title,
            children: children,
            span: _span(opener.bracketSourcePos, afterBracket),
          ),
        ),
      );
    } else {
      // Links cannot contain other links: deactivate all ancestor non-image brackets.
      for (final int bIdx in _bracketIndices) {
        if (!_items[bIdx].bracketIsImage) {
          _items[bIdx].bracketActive = false;
        }
      }
      _items.add(
        _InlineItem.node(
          LinkNode(
            destination: safeDest,
            title: title,
            children: children,
            span: _span(opener.bracketSourcePos, afterBracket),
          ),
        ),
      );
    }
    return afterBracket;
  }

  ({String destination, String? title, int nextIndex})? _parseInlineLinkTarget(
    int openParenPos,
  ) {
    final int len = input.length;
    int i = openParenPos + 1;
    while (i < len && isAsciiWhitespace(input.codeUnitAt(i))) {
      i++;
    }
    if (i >= len) {
      return null;
    }

    String dest = '';
    if (input.codeUnitAt(i) == 0x29) {
      // Empty destination `()`.
      return (destination: '', title: null, nextIndex: i + 1);
    }

    if (input.codeUnitAt(i) == 0x3C) {
      // Angle-bracketed destination `<...>`.
      i++;
      final int dStart = i;
      bool foundClose = false;
      while (i < len) {
        final int cu = input.codeUnitAt(i);
        if (cu == 0x0A || cu == 0x3C) {
          return null;
        }
        if (cu == 0x5C &&
            i + 1 < len &&
            isAsciiPunctuation(input.codeUnitAt(i + 1))) {
          i += 2;
          continue;
        }
        if (cu == 0x3E) {
          dest = unescapeMarkdownString(input.substring(dStart, i));
          i++;
          foundClose = true;
          break;
        }
        i++;
      }
      if (!foundClose) {
        return null;
      }
    } else {
      // Unbracketed destination with balanced parentheses (up to 32 levels).
      final int dStart = i;
      int parenDepth = 0;
      while (i < len) {
        final int cu = input.codeUnitAt(i);
        if (isAsciiControl(cu) || cu == 0x20) {
          break;
        }
        if (cu == 0x5C &&
            i + 1 < len &&
            isAsciiPunctuation(input.codeUnitAt(i + 1))) {
          i += 2;
          continue;
        }
        if (cu == 0x28) {
          parenDepth++;
          if (parenDepth > 32) {
            return null;
          }
        } else if (cu == 0x29) {
          if (parenDepth == 0) {
            break;
          }
          parenDepth--;
        }
        i++;
      }
      if (parenDepth != 0 || i == dStart) {
        return null;
      }
      dest = unescapeMarkdownString(input.substring(dStart, i));
    }

    // Optional whitespace + optional title + closing `)`.
    int wsCount = 0;
    while (i < len && isAsciiWhitespace(input.codeUnitAt(i))) {
      wsCount++;
      i++;
    }
    if (i >= len) {
      return null;
    }
    String? title;
    final int nextCu = input.codeUnitAt(i);
    if (wsCount > 0 && (nextCu == 0x22 || nextCu == 0x27 || nextCu == 0x28)) {
      final int closeChar = nextCu == 0x28 ? 0x29 : nextCu;
      i++;
      final int tStart = i;
      bool closedTitle = false;
      while (i < len) {
        final int cu = input.codeUnitAt(i);
        if (cu == 0x5C &&
            i + 1 < len &&
            isAsciiPunctuation(input.codeUnitAt(i + 1))) {
          i += 2;
          continue;
        }
        if (cu == closeChar) {
          title = unescapeMarkdownString(input.substring(tStart, i));
          i++;
          closedTitle = true;
          break;
        }
        if (nextCu == 0x28 && cu == 0x28) {
          return null;
        }
        i++;
      }
      if (!closedTitle) {
        return null;
      }
      while (i < len && isAsciiWhitespace(input.codeUnitAt(i))) {
        i++;
      }
    }
    if (i >= len || input.codeUnitAt(i) != 0x29) {
      return null;
    }
    return (destination: dest, title: title, nextIndex: i + 1);
  }

  ({String label, int nextIndex})? _parseBracketLabel(int openPos) {
    final int len = input.length;
    int i = openPos + 1;
    int chars = 0;
    while (i < len) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x5C &&
          i + 1 < len &&
          isAsciiPunctuation(input.codeUnitAt(i + 1))) {
        chars += 2;
        i += 2;
        if (chars > 999) {
          return null;
        }
        continue;
      }
      if (cu == 0x5B) {
        return null;
      }
      if (cu == 0x5D) {
        return (label: input.substring(openPos + 1, i), nextIndex: i + 1);
      }
      chars++;
      if (chars > 999) {
        return null;
      }
      i++;
    }
    return null;
  }

  int _handleDelimiterRun(int pos, int delimCu) {
    int end = pos;
    while (end < input.length && input.codeUnitAt(end) == delimCu) {
      end++;
    }
    final int count = end - pos;

    // Handle tilde/equals/caret constraints cleanly:
    // - GFM strikethrough (`~` without subscript): only runs of length 1 or 2.
    // - Subscript (`~` with subscript): length 1 = subscript, length 2 = strike, >=3 = literal.
    // - Highlight (`=`): length 2 only.
    // - Superscript (`^`): length 1 only.
    if (delimCu == 0x7E && count >= 3) {
      _appendText(input.substring(pos, end), _span(pos, end));
      return end;
    }
    if (delimCu == 0x3D && count != 2) {
      _appendText(input.substring(pos, end), _span(pos, end));
      return end;
    }
    if (delimCu == 0x5E && count != 1) {
      _appendText(input.substring(pos, end), _span(pos, end));
      return end;
    }

    final int beforeCp = pos == 0 ? 0x0A : codePointBefore(input, pos);
    final int afterCp = end >= input.length ? 0x0A : codePointAt(input, end);

    final bool beforeWs = isUnicodeWhitespace(beforeCp);
    final bool afterWs = isUnicodeWhitespace(afterCp);
    final bool beforePunct = isUnicodePunctuation(beforeCp);
    final bool afterPunct = isUnicodePunctuation(afterCp);

    final bool leftFlanking =
        !afterWs && (!afterPunct || beforeWs || beforePunct);
    final bool rightFlanking =
        !beforeWs && (!beforePunct || afterWs || afterPunct);

    bool canOpen;
    bool canClose;

    if (delimCu == 0x5F) {
      // '_' intraword rule.
      canOpen = leftFlanking && (!rightFlanking || beforePunct);
      canClose = rightFlanking && (!leftFlanking || afterPunct);
    } else if (delimCu == 0x7E) {
      // '~' rules: when subscript is enabled and count==1, allow intraword (H~2~O).
      if (options.subscript && count == 1) {
        canOpen = leftFlanking;
        canClose = rightFlanking;
      } else {
        // GFM strikethrough uses flanking rules (`~` cannot match inside whitespace).
        canOpen = leftFlanking;
        canClose = rightFlanking;
      }
    } else {
      // '*', '==', '^'
      canOpen = leftFlanking;
      canClose = rightFlanking;
    }

    final _InlineItem item = _InlineItem.delim(
      delimChar: delimCu,
      delimCount: count,
      origCount: count,
      canOpen: canOpen,
      canClose: canClose,
      span: _span(pos, end),
    )..isDelimiter = true;
    final int idx = _items.length;
    _items.add(item);
    _delimiterIndices.add(idx);
    return end;
  }

  int _findDelimiterBottomAfter(int bracketItemIdx) {
    for (int k = _delimiterIndices.length - 1; k >= 0; k--) {
      if (_delimiterIndices[k] < bracketItemIdx) {
        return k;
      }
    }
    return -1;
  }

  void _processEmphasis(int stackBottomDelimListIdx) {
    // Openers bottom table keyed by (delimChar, closerOrigLen % 3, closerCanOpen).
    final Map<int, int> openersBottom = <int, int>{};

    int currentPos = stackBottomDelimListIdx + 1;
    while (currentPos < _delimiterIndices.length) {
      final int closerItemIdx = _delimiterIndices[currentPos];
      final _InlineItem closer = _items[closerItemIdx];
      if (!closer.isDelimiter || !closer.canClose || closer.delimCount == 0) {
        currentPos++;
        continue;
      }

      final int key =
          (closer.delimChar << 4) |
          ((closer.origCount % 3) << 1) |
          (closer.canOpen ? 1 : 0);
      final int bottomLimit = openersBottom[key] ?? stackBottomDelimListIdx;

      int openerPos = currentPos - 1;
      bool foundOpener = false;

      while (openerPos > bottomLimit) {
        final int openerItemIdx = _delimiterIndices[openerPos];
        final _InlineItem opener = _items[openerItemIdx];
        if (!opener.isDelimiter ||
            !opener.canOpen ||
            opener.delimCount == 0 ||
            opener.delimChar != closer.delimChar) {
          openerPos--;
          continue;
        }

        // Exact length check for tilde (`~` vs `~~`), highlight (`==`), and superscript (`^`).
        if (closer.delimChar == 0x7E ||
            closer.delimChar == 0x3D ||
            closer.delimChar == 0x5E) {
          if (opener.origCount != closer.origCount) {
            openerPos--;
            continue;
          }
        }

        // CommonMark Rule 9/10 (multiple of 3 rule) for `*` and `_`.
        if ((closer.delimChar == 0x2A || closer.delimChar == 0x5F) &&
            (opener.canClose || closer.canOpen) &&
            ((opener.origCount + closer.origCount) % 3 == 0) &&
            !(opener.origCount % 3 == 0 && closer.origCount % 3 == 0)) {
          openerPos--;
          continue;
        }

        foundOpener = true;
        break;
      }

      if (!foundOpener) {
        openersBottom[key] = currentPos - 1;
        if (!closer.canOpen) {
          closer.isDelimiter = false;
        }
        currentPos++;
        continue;
      }

      final int openerItemIdx = _delimiterIndices[openerPos];
      final _InlineItem opener = _items[openerItemIdx];

      final int useCount;
      if (closer.delimChar == 0x7E) {
        useCount = opener.delimCount; // 1 or 2
      } else if (closer.delimChar == 0x3D) {
        useCount = 2;
      } else if (closer.delimChar == 0x5E) {
        useCount = 1;
      } else {
        useCount = (opener.delimCount >= 2 && closer.delimCount >= 2) ? 2 : 1;
      }

      opener.delimCount -= useCount;
      closer.delimCount -= useCount;

      final String delimStr = String.fromCharCode(opener.delimChar) * useCount;
      opener.node = TextNode(
        String.fromCharCode(opener.delimChar) * opener.delimCount,
        span: opener.node.span,
      );
      closer.node = TextNode(
        String.fromCharCode(closer.delimChar) * closer.delimCount,
        span: closer.node.span,
      );

      // Deactivate any leftover delimiters strictly between opener and closer.
      for (int k = openerPos + 1; k < currentPos; k++) {
        final _InlineItem mid = _items[_delimiterIndices[k]];
        mid.isDelimiter = false;
        mid.canOpen = false;
        mid.canClose = false;
      }

      // Collect children between openerItemIdx and closerItemIdx.
      final List<MarkdownInlineNode> children = _coalesceTextNodes(
        _collectActiveNodes(openerItemIdx + 1, closerItemIdx),
      );
      // Clear consumed interior items so subsequent scans don't revisit them.
      for (int idx = openerItemIdx + 1; idx < closerItemIdx; idx++) {
        _items[idx].node = const TextNode('');
        _items[idx].isText = false;
        _items[idx].isDelimiter = false;
      }

      final SourceSpan emSpan = SourceSpan(
        startOffset: opener.node.span.startOffset,
        endOffset: closer.node.span.endOffset,
        startLine: opener.node.span.startLine,
        endLine: closer.node.span.endLine,
      );

      final MarkdownInlineNode wrapped;
      if (opener.delimChar == 0x7E) {
        if (options.subscript && useCount == 1) {
          wrapped = SubscriptNode(children: children, span: emSpan);
        } else {
          wrapped = StrikethroughNode(children: children, span: emSpan);
        }
      } else if (opener.delimChar == 0x3D) {
        wrapped = HighlightNode(children: children, span: emSpan);
      } else if (opener.delimChar == 0x5E) {
        wrapped = SuperscriptNode(children: children, span: emSpan);
      } else if (useCount == 2) {
        wrapped = StrongNode(
          children: children,
          delimiter: delimStr,
          span: emSpan,
        );
      } else {
        wrapped = EmphasisNode(
          children: children,
          delimiter: delimStr,
          span: emSpan,
        );
      }

      // Place wrapped node immediately after openerItemIdx (in slot openerItemIdx + 1).
      // Wait: if openerItemIdx + 1 < closerItemIdx, reuse that slot! If adjacent
      // (openerItemIdx + 1 == closerItemIdx, e.g. empty `****`? Can't happen for
      // non-empty or empty? Actually for `****`, `****` is single run!), insert right after opener!
      if (openerItemIdx + 1 < closerItemIdx) {
        _items[openerItemIdx + 1]
          ..node = wrapped
          ..isText = false
          ..isDelimiter = false
          ..isBracket = false;
      } else {
        // Insert wrapped node between opener and closer, shifting later indices.
        final int insertAt = openerItemIdx + 1;
        _items.insert(insertAt, _InlineItem.node(wrapped));
        for (int k = 0; k < _delimiterIndices.length; k++) {
          if (_delimiterIndices[k] >= insertAt) {
            _delimiterIndices[k]++;
          }
        }
        for (int k = 0; k < _bracketIndices.length; k++) {
          if (_bracketIndices[k] >= insertAt) {
            _bracketIndices[k]++;
          }
        }
      }

      if (opener.delimCount == 0) {
        opener.isDelimiter = false;
        opener.isText = false;
      }
      if (closer.delimCount == 0) {
        closer.isDelimiter = false;
        closer.isText = false;
        currentPos++;
      }
    }
  }

  List<MarkdownInlineNode> _collectActiveNodes(int start, int end) {
    final List<MarkdownInlineNode> result = <MarkdownInlineNode>[];
    for (int i = start; i < end; i++) {
      final _InlineItem item = _items[i];
      final MarkdownInlineNode n = item.node;
      if (n is TextNode && n.text.isEmpty) {
        continue;
      }
      result.add(n);
    }
    return result;
  }

  // ===========================================================================
  // GFM Extended Autolinks Post-Processor (cmark-gfm 0.29.0.gfm.13)
  // ===========================================================================

  List<MarkdownInlineNode> _applyGfmAutolinks(List<MarkdownInlineNode> nodes) {
    final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
    for (final MarkdownInlineNode node in nodes) {
      if (node is TextNode) {
        out.addAll(_autolinkTextNode(node));
      } else if (node is EmphasisNode) {
        out.add(
          EmphasisNode(
            children: _applyGfmAutolinks(node.children),
            delimiter: node.delimiter,
            span: node.span,
          ),
        );
      } else if (node is StrongNode) {
        out.add(
          StrongNode(
            children: _applyGfmAutolinks(node.children),
            delimiter: node.delimiter,
            span: node.span,
          ),
        );
      } else if (node is StrikethroughNode) {
        out.add(
          StrikethroughNode(
            children: _applyGfmAutolinks(node.children),
            span: node.span,
          ),
        );
      } else if (node is HighlightNode) {
        out.add(
          HighlightNode(
            children: _applyGfmAutolinks(node.children),
            span: node.span,
          ),
        );
      } else if (node is SubscriptNode) {
        out.add(
          SubscriptNode(
            children: _applyGfmAutolinks(node.children),
            span: node.span,
          ),
        );
      } else if (node is SuperscriptNode) {
        out.add(
          SuperscriptNode(
            children: _applyGfmAutolinks(node.children),
            span: node.span,
          ),
        );
      } else {
        // Skip LinkNode, ImageNode, CodeSpanNode, RawHtmlInlineNode, etc.
        out.add(node);
      }
    }
    return out;
  }

  List<MarkdownInlineNode> _autolinkTextNode(TextNode node) {
    final String text = node.text;
    final int len = text.length;
    final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
    int lastEmit = 0;
    int i = 0;

    while (i < len) {
      final int cu = text.codeUnitAt(i);
      // 1. Check `www.`
      if ((cu == 0x77 || cu == 0x57) &&
          _matchesCaseInsensitiveAt(text, i, 'www.') &&
          _isValidAutolinkStart(text, i)) {
        final ({String url, String label, int end})? match =
            _scanGfmUrlAutolink(
              text,
              i,
              prefixLen: 0,
              schemePrefix: 'http://',
              allowSingleSegmentDomain: false,
            );
        if (match != null) {
          if (i > lastEmit) {
            out.add(TextNode(text.substring(lastEmit, i), span: node.span));
          }
          out.add(
            LinkNode(
              destination: resolver._sanitizeDestination(match.url),
              isAutolink: true,
              children: <MarkdownInlineNode>[TextNode(match.label)],
              span: node.span,
            ),
          );
          lastEmit = match.end;
          i = match.end;
          continue;
        }
      }

      // 2. Check `http://`, `https://`, `ftp://`
      if (cu == 0x68 || cu == 0x48 || cu == 0x66 || cu == 0x46) {
        int? schemeLen;
        if (_matchesCaseInsensitiveAt(text, i, 'https://')) {
          schemeLen = 8;
        } else if (_matchesCaseInsensitiveAt(text, i, 'http://')) {
          schemeLen = 7;
        } else if (_matchesCaseInsensitiveAt(text, i, 'ftp://')) {
          schemeLen = 6;
        }
        if (schemeLen != null && _isValidAutolinkStart(text, i)) {
          final ({String url, String label, int end})? match =
              _scanGfmUrlAutolink(
                text,
                i,
                prefixLen: schemeLen,
                schemePrefix: '',
                allowSingleSegmentDomain: true,
              );
          if (match != null) {
            if (i > lastEmit) {
              out.add(TextNode(text.substring(lastEmit, i), span: node.span));
            }
            out.add(
              LinkNode(
                destination: resolver._sanitizeDestination(match.url),
                isAutolink: true,
                children: <MarkdownInlineNode>[TextNode(match.label)],
                span: node.span,
              ),
            );
            lastEmit = match.end;
            i = match.end;
            continue;
          }
        }
      }

      // 3. Check `mailto:` / `xmpp:` or email `@`
      if (cu == 0x40) {
        final ({String href, String label, int start, int end})? emailMatch =
            _scanGfmEmailAt(text, i, minStart: lastEmit);
        if (emailMatch != null) {
          if (emailMatch.start > lastEmit) {
            out.add(
              TextNode(
                text.substring(lastEmit, emailMatch.start),
                span: node.span,
              ),
            );
          }
          out.add(
            LinkNode(
              destination: resolver._sanitizeDestination(emailMatch.href),
              isAutolink: true,
              children: <MarkdownInlineNode>[TextNode(emailMatch.label)],
              span: node.span,
            ),
          );
          lastEmit = emailMatch.end;
          i = emailMatch.end;
          continue;
        }
      }

      i++;
    }

    if (lastEmit == 0) {
      return <MarkdownInlineNode>[node];
    }
    if (lastEmit < len) {
      out.add(TextNode(text.substring(lastEmit), span: node.span));
    }
    return out;
  }

  bool _isValidAutolinkStart(String text, int index) {
    if (index == 0) {
      return true;
    }
    final int prev = codePointBefore(text, index);
    return isUnicodeWhitespace(prev) ||
        prev == 0x2A || // *
        prev == 0x5F || // _
        prev == 0x7E || // ~
        prev == 0x28 || // (
        prev == 0x22 || // "
        prev == 0x27 || // '
        prev == 0x3A || // :
        prev == 0x2F; // /
  }

  ({String url, String label, int end})? _scanGfmUrlAutolink(
    String text,
    int start, {
    required int prefixLen,
    required String schemePrefix,
    required bool allowSingleSegmentDomain,
  }) {
    final int len = text.length;
    final int domainStart = start + prefixLen;
    if (domainStart >= len) {
      return null;
    }
    // Scan domain up to `/`, `?`, `#`, whitespace, `<`, or invalid domain char.
    int i = domainStart;
    final List<String> segments = <String>[];
    final StringBuffer currentSeg = StringBuffer();

    while (i < len) {
      final int cp = codePointAt(text, i);
      final int step = cp > 0xFFFF ? 2 : 1;
      if (cp == 0x2E) {
        // '.'
        if (currentSeg.isEmpty) {
          break;
        }
        segments.add(currentSeg.toString());
        currentSeg.clear();
        i += step;
      } else if ((cp >= 0x80 && !isUnicodeWhitespace(cp)) ||
          isAsciiAlnum(cp) ||
          cp == 0x5F ||
          cp == 0x2D) {
        // alnum, non-ASCII non-whitespace (e.g. IDNs/emoji), '_', '-'
        currentSeg.write(String.fromCharCode(cp));
        i += step;
      } else {
        break;
      }
    }
    if (currentSeg.isNotEmpty) {
      segments.add(currentSeg.toString());
    } else if (i > domainStart && text.codeUnitAt(i - 1) == 0x2E) {
      // Trailing dot right after domain is NOT part of domain.
      i--;
    }

    if (segments.isEmpty) {
      return null;
    }
    if (!allowSingleSegmentDomain && segments.length < 2) {
      return null;
    }
    // No underscores allowed in the last two segments of the domain.
    final int checkFrom = segments.length >= 2 ? segments.length - 2 : 0;
    for (int s = checkFrom; s < segments.length; s++) {
      if (segments[s].contains('_')) {
        return null;
      }
    }

    // Consume path/query/fragment: zero or more non-whitespace non-'<' chars.
    int end = i;
    while (end < len) {
      final int cp = codePointAt(text, end);
      if (isUnicodeWhitespace(cp) || cp == 0x3C) {
        break;
      }
      end += cp > 0xFFFF ? 2 : 1;
    }

    // Extended autolink path validation (trailing punctuation, balanced parens,
    // and trailing entity-like `&word;` exclusion).
    while (end > start + prefixLen) {
      final int lastCu = text.codeUnitAt(end - 1);
      if (lastCu == 0x3F || // ?
          lastCu == 0x21 || // !
          lastCu == 0x2E || // .
          lastCu == 0x2C || // ,
          lastCu == 0x3A || // :
          lastCu == 0x2A || // *
          lastCu == 0x5F || // _
          lastCu == 0x7E || // ~
          lastCu == 0x27 || // '
          lastCu == 0x22) {
        // "
        end--;
        continue;
      }
      if (lastCu == 0x29) {
        int openCount = 0;
        int closeCount = 0;
        for (int k = start; k < end; k++) {
          final int c = text.codeUnitAt(k);
          if (c == 0x28) {
            openCount++;
          } else if (c == 0x29) {
            closeCount++;
          }
        }
        if (closeCount > openCount) {
          end--;
          continue;
        }
      }
      if (lastCu == 0x3B) {
        // Semicolon preceded by `&[A-Za-z0-9]+`.
        int k = end - 2;
        while (k >= start && isAsciiAlnum(text.codeUnitAt(k))) {
          k--;
        }
        if (k >= start && text.codeUnitAt(k) == 0x26 && k < end - 2) {
          end = k;
          continue;
        }
      }
      break;
    }

    if (end <= domainStart) {
      return null;
    }
    final String label = text.substring(start, end);
    return (url: '$schemePrefix$label', label: label, end: end);
  }

  ({String href, String label, int start, int end})? _scanGfmEmailAt(
    String text,
    int atPos, {
    required int minStart,
  }) {
    // Scan local-part backwards: [A-Za-z0-9._+-]+
    int localStart = atPos;
    while (localStart > minStart) {
      final int cu = text.codeUnitAt(localStart - 1);
      if (isAsciiAlnum(cu) ||
          cu == 0x2E ||
          cu == 0x2D ||
          cu == 0x5F ||
          cu == 0x2B) {
        localStart--;
      } else {
        break;
      }
    }
    if (localStart == atPos) {
      return null;
    }

    // Check optional `mailto:` or `xmpp:` prefix right before localStart.
    String scheme = 'mailto:';
    int fullStart = localStart;
    bool isXmpp = false;
    if (localStart >= minStart + 7 &&
        _matchesCaseInsensitiveAt(text, localStart - 7, 'mailto:') &&
        (localStart - 7 == minStart ||
            !isAsciiAlnum(text.codeUnitAt(localStart - 8)))) {
      fullStart = localStart - 7;
    } else if (localStart >= minStart + 5 &&
        _matchesCaseInsensitiveAt(text, localStart - 5, 'xmpp:') &&
        (localStart - 5 == minStart ||
            !isAsciiAlnum(text.codeUnitAt(localStart - 6)))) {
      fullStart = localStart - 5;
      scheme = 'xmpp:';
      isXmpp = true;
    }

    // Scan domain after `@`: [A-Za-z0-9._-]+ with at least one `.`.
    int domainEnd = atPos + 1;
    int dots = 0;
    while (domainEnd < text.length) {
      final int cu = text.codeUnitAt(domainEnd);
      if (isAsciiAlnum(cu) || cu == 0x2D || cu == 0x5F) {
        domainEnd++;
      } else if (cu == 0x2E) {
        // Consecutive dots or dot right after `@` not allowed.
        if (domainEnd == atPos + 1 || text.codeUnitAt(domainEnd - 1) == 0x2E) {
          break;
        }
        dots++;
        domainEnd++;
      } else {
        break;
      }
    }

    // Trailing `.` excluded from email domain.
    if (domainEnd > atPos + 1 && text.codeUnitAt(domainEnd - 1) == 0x2E) {
      domainEnd--;
      dots--;
    }
    if (domainEnd <= atPos + 1 || dots < 1) {
      return null;
    }
    final int lastCu = text.codeUnitAt(domainEnd - 1);
    if (lastCu == 0x2D || lastCu == 0x5F) {
      return null;
    }

    // For `xmpp:`, optional `/resource` follows.
    int end = domainEnd;
    if (isXmpp && end < text.length && text.codeUnitAt(end) == 0x2F) {
      end++;
      while (end < text.length) {
        final int cu = text.codeUnitAt(end);
        if (isAsciiAlnum(cu) || cu == 0x2D || cu == 0x5F || cu == 0x2E) {
          end++;
        } else {
          break;
        }
      }
      if (text.codeUnitAt(end - 1) == 0x2E) {
        end--;
      }
    }

    final String label = text.substring(fullStart, end);
    final String address = text.substring(localStart, end);
    final String href = scheme == 'xmpp:' ? 'xmpp:$address' : 'mailto:$address';
    return (href: href, label: label, start: fullStart, end: end);
  }

  bool _matchesCaseInsensitiveAt(String text, int index, String pattern) {
    if (index + pattern.length > text.length) {
      return false;
    }
    for (int i = 0; i < pattern.length; i++) {
      int a = text.codeUnitAt(index + i);
      int b = pattern.codeUnitAt(i);
      if (a >= 0x41 && a <= 0x5A) {
        a += 0x20;
      }
      if (b >= 0x41 && b <= 0x5A) {
        b += 0x20;
      }
      if (a != b) {
        return false;
      }
    }
    return true;
  }

  // ===========================================================================
  // Extended Inline Post-Processors (Emoji, Smart Punctuation, Abbreviations)
  // ===========================================================================

  List<MarkdownInlineNode> _applyEmojiShortcodes(
    List<MarkdownInlineNode> nodes,
  ) {
    return _mapTextNodes(nodes, (TextNode t) {
      final String replaced = t.text.replaceAllMapped(
        RegExp(r':([a-z0-9_+-]+):'),
        (Match m) => emojiShortcodes[m.group(1)!] ?? m.group(0)!,
      );
      return <MarkdownInlineNode>[TextNode(replaced, span: t.span)];
    });
  }

  List<MarkdownInlineNode> _applySmartPunctuation(
    List<MarkdownInlineNode> nodes,
  ) {
    return _mapTextNodes(nodes, (TextNode t) {
      String s = t.text;
      s = s.replaceAll('---', '\u2014');
      s = s.replaceAll('--', '\u2013');
      s = s.replaceAll('...', '\u2026');
      s = _smartQuotes(s);
      return <MarkdownInlineNode>[TextNode(s, span: t.span)];
    });
  }

  String _smartQuotes(String s) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final int cu = s.codeUnitAt(i);
      if (cu == 0x22) {
        final bool open =
            i == 0 ||
            isUnicodeWhitespace(codePointBefore(s, i)) ||
            s.codeUnitAt(i - 1) == 0x28 ||
            s.codeUnitAt(i - 1) == 0x5B;
        out.write(open ? '\u201C' : '\u201D');
      } else if (cu == 0x27) {
        final bool prevAlnum = i > 0 && isUnicodeAlnum(codePointBefore(s, i));
        final bool nextAlnum =
            i + 1 < s.length && isUnicodeAlnum(codePointAt(s, i + 1));
        if (prevAlnum && nextAlnum) {
          out.write('\u2019');
        } else {
          final bool open =
              i == 0 ||
              isUnicodeWhitespace(codePointBefore(s, i)) ||
              s.codeUnitAt(i - 1) == 0x28 ||
              s.codeUnitAt(i - 1) == 0x5B;
          out.write(open ? '\u2018' : '\u2019');
        }
      } else {
        out.writeCharCode(cu);
      }
    }
    return out.toString();
  }

  List<MarkdownInlineNode> _applyAbbreviations(List<MarkdownInlineNode> nodes) {
    final List<String> keys = resolver.abbreviations.keys.toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    final RegExp abbrPattern = RegExp(
      '\\b(${keys.map(RegExp.escape).join('|')})\\b',
    );
    return _mapTextNodes(nodes, (TextNode t) {
      final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
      int last = 0;
      for (final Match m in abbrPattern.allMatches(t.text)) {
        if (m.start > last) {
          out.add(TextNode(t.text.substring(last, m.start), span: t.span));
        }
        final String abbr = m.group(1)!;
        final String title = resolver.abbreviations[abbr]!;
        out.add(
          AbbrInlineNode(
            title: title,
            children: <MarkdownInlineNode>[TextNode(abbr, span: t.span)],
            span: t.span,
          ),
        );
        last = m.end;
      }
      if (last == 0) {
        return <MarkdownInlineNode>[t];
      }
      if (last < t.text.length) {
        out.add(TextNode(t.text.substring(last), span: t.span));
      }
      return out;
    });
  }

  List<MarkdownInlineNode> _mapTextNodes(
    List<MarkdownInlineNode> nodes,
    List<MarkdownInlineNode> Function(TextNode) fn,
  ) {
    final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
    for (final MarkdownInlineNode node in nodes) {
      if (node is TextNode) {
        out.addAll(fn(node));
      } else if (node is EmphasisNode) {
        out.add(
          EmphasisNode(
            children: _mapTextNodes(node.children, fn),
            delimiter: node.delimiter,
            span: node.span,
          ),
        );
      } else if (node is StrongNode) {
        out.add(
          StrongNode(
            children: _mapTextNodes(node.children, fn),
            delimiter: node.delimiter,
            span: node.span,
          ),
        );
      } else if (node is StrikethroughNode) {
        out.add(
          StrikethroughNode(
            children: _mapTextNodes(node.children, fn),
            span: node.span,
          ),
        );
      } else if (node is HighlightNode) {
        out.add(
          HighlightNode(
            children: _mapTextNodes(node.children, fn),
            span: node.span,
          ),
        );
      } else if (node is SubscriptNode) {
        out.add(
          SubscriptNode(
            children: _mapTextNodes(node.children, fn),
            span: node.span,
          ),
        );
      } else if (node is SuperscriptNode) {
        out.add(
          SuperscriptNode(
            children: _mapTextNodes(node.children, fn),
            span: node.span,
          ),
        );
      } else if (node is LinkNode) {
        if (node.isAutolink) {
          out.add(node);
        } else {
          out.add(
            LinkNode(
              destination: node.destination,
              title: node.title,
              children: _mapTextNodes(node.children, fn),
              isAutolink: node.isAutolink,
              span: node.span,
            ),
          );
        }
      } else {
        out.add(node);
      }
    }
    return out;
  }
}

List<MarkdownInlineNode> _coalesceTextNodes(List<MarkdownInlineNode> nodes) {
  if (nodes.length <= 1) {
    return nodes;
  }
  final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
  for (final MarkdownInlineNode node in nodes) {
    if (node is TextNode) {
      if (node.text.isEmpty) {
        continue;
      }
      if (out.isNotEmpty && out.last is TextNode) {
        final TextNode prev = out.last as TextNode;
        out[out.length - 1] = TextNode(
          '${prev.text}${node.text}',
          span: SourceSpan(
            startOffset: prev.span.startOffset,
            endOffset: node.span.endOffset,
            startLine: prev.span.startLine,
            endLine: node.span.endLine,
          ),
        );
      } else {
        out.add(node);
      }
    } else {
      out.add(node);
    }
  }
  return out;
}

String _extractPlainText(List<MarkdownInlineNode> nodes) {
  final StringBuffer out = StringBuffer();
  for (final MarkdownInlineNode node in nodes) {
    out.write(node.toPlainText());
  }
  return out.toString();
}

String _extractAltText(List<MarkdownInlineNode> nodes) {
  final StringBuffer out = StringBuffer();
  for (final MarkdownInlineNode node in nodes) {
    if (node is TextNode) {
      out.write(node.text);
    } else if (node is CodeSpanNode) {
      out.write(node.literal);
    } else if (node is SoftBreakNode || node is HardBreakNode) {
      out.write(' ');
    } else if (node is ImageNode) {
      out.write(node.alt);
    } else if (node is LinkNode) {
      out.write(_extractAltText(node.children));
    } else if (node is EmphasisNode) {
      out.write(_extractAltText(node.children));
    } else if (node is StrongNode) {
      out.write(_extractAltText(node.children));
    } else if (node is StrikethroughNode) {
      out.write(_extractAltText(node.children));
    } else if (node is HighlightNode) {
      out.write(_extractAltText(node.children));
    } else if (node is SubscriptNode) {
      out.write(_extractAltText(node.children));
    } else if (node is SuperscriptNode) {
      out.write(_extractAltText(node.children));
    } else {
      out.write(node.toPlainText());
    }
  }
  return out.toString();
}

final RegExp _uriAutolinkPattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\x00-\x20\x7F<>]*$',
);

final RegExp _emailAutolinkPattern = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
);

final RegExp _inlineHtmlDeclPattern = RegExp(
  r'^<![A-Za-z]+[\x20\x09\n\r][^>]*>',
);

final RegExp _inlineHtmlTagPattern = RegExp(
  r'^<(?:[A-Za-z][A-Za-z0-9-]*(?:[\x20\x09\n\r]+[A-Za-z_:][A-Za-z0-9_.:-]*(?:[\x20\x09\n\r]*=[\x20\x09\n\r]*(?:[^\x20\x09\n\r"'
  "'"
  r'=<>`]+|'
  "'"
  r"[^']*"
  "'"
  r'|"[^"]*"))?)*[\x20\x09\n\r]*/?|/[A-Za-z][A-Za-z0-9-]*[\x20\x09\n\r]*)>',
);
