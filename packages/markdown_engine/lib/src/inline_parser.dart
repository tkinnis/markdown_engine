import 'dart:typed_data';

import 'ast.dart';
import 'block_parser.dart';
import 'budgets.dart';
import 'emoji.dart';
import 'entities.dart';
import 'options.dart';
import 'security.dart';
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
Phase2Result parseInlines(
  Phase1Result phase1,
  MarkdownOptions options, {
  HeadingSlugGenerator? slugGenerator,
}) {
  final _InlineResolver resolver = _InlineResolver(
    options: options,
    budgets: options.effectiveBudgets,
    linkDefinitions: phase1.linkDefinitions,
    rawFootnotes: phase1.footnoteDefinitions,
    abbreviations: phase1.abbreviations,
    idPrefix: phase1.idPrefix,
    slugs: slugGenerator ?? HeadingSlugGenerator(),
  );
  return resolver.resolveDocument(phase1.blocks);
}

const int _maxAbbrPatternKeys = 512;

final Uint8List _postCharFlags = _buildPostCharFlags();

Uint8List _buildPostCharFlags() {
  final Uint8List flags = Uint8List(128);
  flags[0x3A] = 1; // ':' (emoji or ://)
  flags[0x40] = 2; // '@' (email autolink)
  flags[0x2E] = 4; // '.' (www. or ...)
  flags[0x22] = 8; // '"' (smart quote)
  flags[0x27] = 8; // '\'' (smart quote)
  flags[0x2D] = 16; // '-' (-- / ---)
  return flags;
}

Uint8List _buildStructuralLut(MarkdownOptions options) {
  final Uint8List lut = Uint8List(128);
  lut[0x0A] = 1; // '\n'
  lut[0x5C] = 1; // '\\'
  lut[0x60] = 1; // '`'
  lut[0x26] = 1; // '&'
  lut[0x3C] = 1; // '<'
  lut[0x5B] = 1; // '['
  lut[0x5D] = 1; // ']'
  lut[0x21] = 1; // '!'
  lut[0x2A] = 1; // '*'
  lut[0x5F] = 1; // '_'
  if (options.gfmStrikethrough || options.subscript) {
    lut[0x7E] = 1; // '~'
  }
  if (options.highlight) {
    lut[0x3D] = 1; // '='
  }
  if (options.superscript) {
    lut[0x5E] = 1; // '^'
  }
  if (options.math) {
    lut[0x24] = 1; // '$'
  }
  return lut;
}

final class _InlineResolver {
  _InlineResolver({
    required this.options,
    required this.budgets,
    required this.linkDefinitions,
    required this.rawFootnotes,
    required this.abbreviations,
    required this.idPrefix,
    required HeadingSlugGenerator slugs,
  }) : _slugs = slugs,
       structuralLut = _buildStructuralLut(options) {
    _scanner = _InlineScanner(resolver: this);
  }

  final MarkdownOptions options;
  final MarkdownBudgets budgets;
  final Map<String, MarkdownLinkDefinition> linkDefinitions;
  final Map<String, RawFootnoteDef> rawFootnotes;
  final Map<String, String> abbreviations;
  final String idPrefix;
  final Uint8List structuralLut;
  late final _InlineScanner _scanner;

  final HeadingSlugGenerator _slugs;
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
  int _totalTokens = 0;
  int _expandedOutputBytes = 0;
  RegExp? _cachedAbbrPattern;

  RegExp? get abbrPattern {
    if (_cachedAbbrPattern != null) {
      return _cachedAbbrPattern;
    }
    if (abbreviations.isEmpty) {
      return null;
    }
    final List<String> keys =
        abbreviations.keys.take(_maxAbbrPatternKeys).toList()
          ..sort((String a, String b) => b.length.compareTo(a.length));
    if (keys.isEmpty) {
      return null;
    }
    _cachedAbbrPattern = RegExp(
      '(?<!\\w)(${keys.map(RegExp.escape).join('|')})(?!\\w)',
    );
    return _cachedAbbrPattern;
  }

  bool tryConsumeExpandedBytes(int bytes) {
    if (bytes <= 0) {
      return true;
    }
    if (_expandedOutputBytes + bytes > budgets.maxOutputBytes) {
      return false;
    }
    _expandedOutputBytes += bytes;
    return true;
  }

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
      int minStartOffset = orderedCited.first.span.startOffset;
      int maxEndOffset = orderedCited.first.span.endOffset;
      int minStartLine = orderedCited.first.span.startLine;
      int maxEndLine = orderedCited.first.span.endLine;
      for (int i = 1; i < orderedCited.length; i++) {
        final SourceSpan s = orderedCited[i].span;
        if (s.startOffset < minStartOffset) {
          minStartOffset = s.startOffset;
        }
        if (s.endOffset > maxEndOffset) {
          maxEndOffset = s.endOffset;
        }
        if (s.startLine < minStartLine) {
          minStartLine = s.startLine;
        }
        if (s.endLine > maxEndLine) {
          maxEndLine = s.endLine;
        }
      }
      finalBlocks.add(
        FootnoteSectionNode(
          blockId: '${idPrefix}footnote-section',
          definitions: freezeList(orderedCited),
          span: SourceSpan(
            startOffset: minStartOffset,
            endOffset: maxEndOffset,
            startLine: minStartLine,
            endLine: maxEndLine,
          ),
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
      blocks: freezeList(finalBlocks),
      outline: freezeList(_outline),
      footnotes: freezeList(allFootnotes),
      remoteImageAddresses: freezeList(_remoteImages),
    );
  }

  List<MarkdownBlockNode> _resolveBlockList(List<RawBlock> rawBlocks) {
    if (rawBlocks.isEmpty) {
      return const <MarkdownBlockNode>[];
    }
    final List<MarkdownBlockNode> out = <MarkdownBlockNode>[
      for (final RawBlock raw in rawBlocks) _resolveBlock(raw),
    ];
    return freezeList(out);
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
          items: freezeList(<ListItemNode>[
            for (final RawListItem item in raw.items)
              ListItemNode(
                blockId: item.blockId,
                span: item.span,
                taskState: item.taskState,
                children: _resolveBlockList(item.children),
              ),
          ]),
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
          rows.add(freezeList(row));
        }
        return TableNode(
          blockId: raw.blockId,
          span: raw.span,
          alignments: raw.alignments,
          headers: freezeList(headers),
          rows: freezeList(rows),
        );
      case RawDefinitionList():
        final List<DefinitionGroup> groups = <DefinitionGroup>[
          for (final RawDefGroup g in raw.groups)
            DefinitionGroup(
              term: _parseInlineString(g.termRaw, g.span),
              definitions: freezeList(<List<MarkdownBlockNode>>[
                for (final List<RawBlock> d in g.definitions)
                  _resolveBlockList(d),
              ]),
              span: g.span,
            ),
        ];
        return DefinitionListNode(
          blockId: raw.blockId,
          span: raw.span,
          groups: freezeList(groups),
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
    if (_totalTokens >= budgets.maxTokens) {
      return freezeList(<MarkdownInlineNode>[TextNode(input, span: blockSpan)]);
    }

    // Zero-alloc plain-text pre-scan: skip _InlineScanner when no structural
    // delimiter/marker exists and detect exact post-processing triggers in 1 pass.
    final int len = input.length;
    bool hasStructural = false;
    bool hasAutolink = false;
    bool hasEmojiColon = false;
    bool hasSmartPunct = false;
    for (int i = 0; i < len; i++) {
      final int cu = input.codeUnitAt(i);
      if (cu < 128) {
        if (structuralLut[cu] != 0) {
          hasStructural = true;
          break;
        }
        final int pf = _postCharFlags[cu];
        if (pf != 0) {
          if (cu == 0x40) {
            hasAutolink = true;
          } else if (cu == 0x3A) {
            hasEmojiColon = true;
            if (i + 2 < len &&
                input.codeUnitAt(i + 1) == 0x2F &&
                input.codeUnitAt(i + 2) == 0x2F) {
              hasAutolink = true;
            }
          } else if (cu == 0x2E) {
            if (i >= 3 && _matchesWwwPrefixBeforeDot(input, i)) {
              hasAutolink = true;
            }
            if (i + 2 < len &&
                input.codeUnitAt(i + 1) == 0x2E &&
                input.codeUnitAt(i + 2) == 0x2E) {
              hasSmartPunct = true;
            }
          } else if (cu == 0x22 || cu == 0x27) {
            hasSmartPunct = true;
          } else if (cu == 0x2D) {
            if (i + 1 < len && input.codeUnitAt(i + 1) == 0x2D) {
              hasSmartPunct = true;
            }
          }
        }
      }
    }

    if (!hasStructural) {
      _totalTokens++;
      final bool runAutolinks = options.gfmAutolinks && hasAutolink;
      final bool runEmoji = options.emoji && hasEmojiColon;
      final bool runSmart = options.smartPunctuation && hasSmartPunct;
      final bool runAbbr = options.abbreviations && abbreviations.isNotEmpty;
      if (!runAutolinks && !runEmoji && !runSmart && !runAbbr) {
        return freezeList(<MarkdownInlineNode>[
          TextNode(input, span: blockSpan),
        ]);
      }
      _scanner.reset(input, blockSpan);
      List<MarkdownInlineNode> nodes = <MarkdownInlineNode>[
        TextNode(input, span: blockSpan),
      ];
      if (runAutolinks) {
        nodes = _scanner._applyGfmAutolinks(nodes);
      }
      if (runEmoji) {
        nodes = _scanner._applyEmojiShortcodes(nodes);
      }
      if (runSmart) {
        nodes = _scanner._applySmartPunctuation(nodes);
      }
      if (runAbbr) {
        nodes = _scanner._applyAbbreviations(nodes);
      }
      return freezeList(_coalesceTextNodes(nodes));
    }

    _scanner.reset(input, blockSpan);
    return _scanner.parse();
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

  ({String destination, bool blocked}) _resolveDestination(String url) {
    if (!options.sanitizeUrls) {
      return (destination: url, blocked: false);
    }
    final String safe = options.urlPolicy.sanitize(url);
    final bool blocked = safe.isEmpty && url.trim().isNotEmpty;
    return (destination: safe, blocked: blocked);
  }

  String _sanitizeDestination(String url) {
    if (!options.sanitizeUrls) {
      return url;
    }
    return options.urlPolicy.sanitize(url);
  }

  LinkNode _makeLinkNode({
    required String rawDestination,
    String? title,
    required List<MarkdownInlineNode> children,
    required bool isAutolink,
    required SourceSpan span,
  }) {
    final ({String destination, bool blocked}) resolved = _resolveDestination(
      rawDestination,
    );
    if (resolved.blocked) {
      return createBlockedLinkNode(
        title: title,
        children: children,
        isAutolink: isAutolink,
        span: span,
      );
    }
    return LinkNode(
      destination: resolved.destination,
      title: title,
      children: children,
      isAutolink: isAutolink,
      span: span,
    );
  }

  ImageNode _makeImageNode({
    required String rawDestination,
    required String alt,
    String? title,
    int? width,
    int? height,
    required List<MarkdownInlineNode> children,
    required SourceSpan span,
  }) {
    final ({String destination, bool blocked}) resolved = _resolveDestination(
      rawDestination,
    );
    if (resolved.blocked) {
      return createBlockedImageNode(
        alt: alt,
        title: title,
        width: width,
        height: height,
        children: children,
        span: span,
      );
    }
    _recordImageUrl(resolved.destination);
    return ImageNode(
      destination: resolved.destination,
      alt: alt,
      title: title,
      width: width,
      height: height,
      children: children,
      span: span,
    );
  }

  void _recordImageUrl(String url) {
    if (url.isEmpty) {
      return;
    }
    final String cleaned = stripControlAndWhitespaceForUrl(url);
    if (cleaned.isEmpty) {
      return;
    }
    if (options.sanitizeUrls && !options.urlPolicy.isAllowed(cleaned)) {
      return;
    }
    final String lower = cleaned.toLowerCase();
    if ((lower.startsWith('http://') ||
            lower.startsWith('https://') ||
            lower.startsWith('//')) &&
        _remoteImageSet.add(cleaned)) {
      _remoteImages.add(cleaned);
    }
  }

  String nextId(String prefix) {
    _synthCounter++;
    return '$idPrefix$prefix-$_synthCounter';
  }
}

bool _matchesWwwPrefixBeforeDot(String s, int dotIdx) {
  final int c0 = s.codeUnitAt(dotIdx - 3);
  final int c1 = s.codeUnitAt(dotIdx - 2);
  final int c2 = s.codeUnitAt(dotIdx - 1);
  return (c0 == 0x77 || c0 == 0x57) &&
      (c1 == 0x77 || c1 == 0x57) &&
      (c2 == 0x77 || c2 == 0x57);
}

final class _InlineItem {
  _InlineItem.node(this.node, {this.inlineDepth = 0})
    : isText = node is TextNode;

  _InlineItem.delim({
    required this.delimChar,
    required this.delimCount,
    required this.origCount,
    required this.canOpen,
    required this.canClose,
    required SourceSpan span,
  }) : isText = true,
       node = TextNode(_repeatDelimChar(delimChar, delimCount), span: span);

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
  int delimStackLen = 0;
  int savedDelimTail = -1;
  int inlineDepth = 0;
  int prevActive = -1;
  int nextActive = -1;
}

String _repeatDelimChar(int delimChar, int count) {
  if (count <= 0) {
    return '';
  }
  if (count == 1) {
    return switch (delimChar) {
      0x2A => '*',
      0x5F => '_',
      0x7E => '~',
      0x5E => '^',
      0x3D => '=',
      _ => String.fromCharCode(delimChar),
    };
  }
  if (count == 2) {
    return switch (delimChar) {
      0x2A => '**',
      0x5F => '__',
      0x7E => '~~',
      0x3D => '==',
      _ => String.fromCharCode(delimChar) * 2,
    };
  }
  if (count == 3 && delimChar == 0x2A) {
    return '***';
  }
  if (count == 3 && delimChar == 0x5F) {
    return '___';
  }
  return String.fromCharCode(delimChar) * count;
}

final class _InlineScanner {
  _InlineScanner({required this.resolver});

  final _InlineResolver resolver;

  late String input;
  late SourceSpan blockSpan;

  final List<_InlineItem> _items = <_InlineItem>[];
  final List<int> _delimiterIndices = <int>[];
  final List<int> _prevDelim = <int>[];
  final List<int> _nextDelim = <int>[];
  int _delimHead = -1;
  int _delimTail = -1;
  int _activeHead = -1;
  int _activeTail = -1;

  final List<int> _bracketIndices = <int>[];
  final Set<int> _unmatchedBacktickLengths = <int>{};

  int? _cachedLastGtPos;
  int _noClosingSingleQuoteFrom = 0;
  int _noClosingDoubleQuoteFrom = 0;
  Set<int>? _failedAttrBoundaries;
  bool _noCommentClose = false;
  bool _noPiClose = false;
  bool _noCdataClose = false;
  bool _noValidClosingDollar = false;
  bool _sawAutolinkCandidate = false;
  bool _sawEmojiColon = false;
  bool _sawSmartPunct = false;

  MarkdownOptions get options => resolver.options;
  MarkdownBudgets get budgets => resolver.budgets;

  void reset(String nextInput, SourceSpan nextSpan) {
    input = nextInput;
    blockSpan = nextSpan;
    if (_items.length > 1024) {
      _items.length = 0;
    } else {
      _items.clear();
    }
    _delimiterIndices.clear();
    _prevDelim.clear();
    _nextDelim.clear();
    _delimHead = -1;
    _delimTail = -1;
    _activeHead = -1;
    _activeTail = -1;
    _bracketIndices.clear();
    _unmatchedBacktickLengths.clear();
    _cachedLastGtPos = null;
    final int guardPos = nextInput.length + 1;
    _noClosingSingleQuoteFrom = guardPos;
    _noClosingDoubleQuoteFrom = guardPos;
    _failedAttrBoundaries = null;
    _noCommentClose = false;
    _noPiClose = false;
    _noCdataClose = false;
    _noValidClosingDollar = false;
    _sawAutolinkCandidate = false;
    _sawEmojiColon = false;
    _sawSmartPunct = false;
  }

  int get _lastGtPos => _cachedLastGtPos ??= input.lastIndexOf('>');

  SourceSpan _span(int start, int end) {
    final int base = blockSpan.startOffset;
    return SourceSpan(
      startOffset: base + start,
      endOffset: base + end,
      startLine: blockSpan.startLine,
      endLine: blockSpan.endLine,
    );
  }

  int _appendActiveItem(_InlineItem item) {
    final int idx = _items.length;
    item.prevActive = _activeTail;
    item.nextActive = -1;
    _items.add(item);
    if (_activeTail != -1) {
      _items[_activeTail].nextActive = idx;
    } else {
      _activeHead = idx;
    }
    _activeTail = idx;
    return idx;
  }

  void _popActiveTail() {
    if (_activeTail == -1) {
      return;
    }
    final int prev = _items[_activeTail].prevActive;
    _items[_activeTail].prevActive = -1;
    _items[_activeTail].nextActive = -1;
    if (prev != -1) {
      _items[prev].nextActive = -1;
      _activeTail = prev;
    } else {
      _activeHead = -1;
      _activeTail = -1;
    }
  }

  void _appendDelimiter(_InlineItem item) {
    final int itemIdx = _appendActiveItem(item);
    final int dPos = _delimiterIndices.length;
    _delimiterIndices.add(itemIdx);
    _prevDelim.add(_delimTail);
    _nextDelim.add(-1);
    if (_delimTail != -1) {
      _nextDelim[_delimTail] = dPos;
    } else {
      _delimHead = dPos;
    }
    _delimTail = dPos;
  }

  void _unlinkDelim(int dPos) {
    final int p = _prevDelim[dPos];
    final int n = _nextDelim[dPos];
    if (p != -1) {
      _nextDelim[p] = n;
    } else {
      _delimHead = n;
    }
    if (n != -1) {
      _prevDelim[n] = p;
    } else {
      _delimTail = p;
    }
    _prevDelim[dPos] = -1;
    _nextDelim[dPos] = -1;
  }

  List<MarkdownInlineNode> parse() {
    final int len = input.length;
    final Uint8List lut = resolver.structuralLut;
    int pos = 0;

    while (pos < len) {
      resolver._totalTokens++;
      if (resolver._totalTokens > budgets.maxTokens) {
        _appendText(input.substring(pos), _span(pos, len));
        break;
      }

      final int cu = input.codeUnitAt(pos);
      if (cu >= 128 || lut[cu] == 0) {
        pos = _scanPlainText(pos);
        continue;
      }

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
          pos = _handleDelimiterRun(pos, cu);
        case 0x3D: // '='
          if (pos + 1 < len && input.codeUnitAt(pos + 1) == 0x3D) {
            pos = _handleDelimiterRun(pos, cu);
          } else {
            _appendText('=', _span(pos, pos + 1));
            pos++;
          }
        case 0x5E: // '^'
          pos = _handleDelimiterRun(pos, cu);
        case 0x24: // '$'
          pos = _handleInlineMath(pos);
        default:
          pos = _scanPlainText(pos);
      }
    }

    if (_delimHead != -1) {
      _processEmphasis(
        bottomDelimPos: -1,
        firstCandidateDelimPos: _delimHead,
        maxAllowedDepth: budgets.maxNestingDepth,
      );
    }

    List<MarkdownInlineNode> nodes = _collectActiveNodesCoalesced(_activeHead);
    if (options.gfmAutolinks && _sawAutolinkCandidate) {
      nodes = _applyGfmAutolinks(nodes);
    }
    if (options.emoji && _sawEmojiColon) {
      nodes = _applyEmojiShortcodes(nodes);
    }
    if (options.smartPunctuation && _sawSmartPunct) {
      nodes = _applySmartPunctuation(nodes);
    }
    if (options.abbreviations && resolver.abbreviations.isNotEmpty) {
      nodes = _applyAbbreviations(nodes);
    }
    return freezeList(_coalesceTextNodes(nodes));
  }

  int _scanPlainText(int start) {
    final int len = input.length;
    final Uint8List lut = resolver.structuralLut;
    int i = start;
    while (i < len) {
      final int cu = input.codeUnitAt(i);
      if (cu < 128) {
        if (lut[cu] != 0) {
          if (i > start) {
            break;
          }
        } else {
          final int pf = _postCharFlags[cu];
          if (pf != 0) {
            if (cu == 0x40) {
              _sawAutolinkCandidate = true;
            } else if (cu == 0x3A) {
              _sawEmojiColon = true;
              if (!_sawAutolinkCandidate &&
                  i + 2 < len &&
                  input.codeUnitAt(i + 1) == 0x2F &&
                  input.codeUnitAt(i + 2) == 0x2F) {
                _sawAutolinkCandidate = true;
              }
            } else if (cu == 0x2E) {
              if (!_sawAutolinkCandidate &&
                  i >= 3 &&
                  _matchesWwwPrefixBeforeDot(input, i)) {
                _sawAutolinkCandidate = true;
              }
              if (!_sawSmartPunct &&
                  i + 2 < len &&
                  input.codeUnitAt(i + 1) == 0x2E &&
                  input.codeUnitAt(i + 2) == 0x2E) {
                _sawSmartPunct = true;
              }
            } else if (cu == 0x22 || cu == 0x27) {
              _sawSmartPunct = true;
            } else if (cu == 0x2D) {
              if (!_sawSmartPunct &&
                  i + 1 < len &&
                  input.codeUnitAt(i + 1) == 0x2D) {
                _sawSmartPunct = true;
              }
            }
          }
        }
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
    if (_activeTail != -1) {
      final _InlineItem last = _items[_activeTail];
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
    _appendActiveItem(_InlineItem.node(TextNode(text, span: span)));
  }

  int _handleNewline(int pos) {
    if (_activeTail != -1) {
      final _InlineItem last = _items[_activeTail];
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
            _popActiveTail();
          } else {
            last.node = TextNode(trimmed, span: prev.span);
          }
          if (trailingSpaces >= 2) {
            _appendActiveItem(
              _InlineItem.node(HardBreakNode(span: _span(pos, pos + 1))),
            );
          } else {
            _appendActiveItem(
              _InlineItem.node(SoftBreakNode(span: _span(pos, pos + 1))),
            );
          }
          return _skipLeadingSpacesAfterNewline(pos + 1);
        }
      }
    }
    _appendActiveItem(
      _InlineItem.node(SoftBreakNode(span: _span(pos, pos + 1))),
    );
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
      _appendActiveItem(
        _InlineItem.node(HardBreakNode(span: _span(pos, pos + 2))),
      );
      return _skipLeadingSpacesAfterNewline(pos + 2);
    }
    if (isAsciiPunctuation(next)) {
      if (next == 0x3A) {
        _sawEmojiColon = true;
        _sawAutolinkCandidate = true;
      } else if (next == 0x40 || next == 0x2E) {
        _sawAutolinkCandidate = true;
        _sawSmartPunct = true;
      } else if (next == 0x22 || next == 0x27 || next == 0x2D) {
        _sawSmartPunct = true;
      }
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
          _appendActiveItem(
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
      _sawAutolinkCandidate = true;
      _sawEmojiColon = true;
      _sawSmartPunct = true;
      _appendText(decoded.text, _span(pos, decoded.nextIndex));
      return decoded.nextIndex;
    }
    _appendText('&', _span(pos, pos + 1));
    return pos + 1;
  }

  int _handleInlineMath(int pos) {
    if (_noValidClosingDollar ||
        pos + 1 >= input.length ||
        input.codeUnitAt(pos + 1) == 0x24) {
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
            _appendActiveItem(
              _InlineItem.node(MathInlineNode(latex, span: _span(pos, i + 1))),
            );
            return i + 1;
          }
        }
      }
      i++;
    }
    _noValidClosingDollar = true;
    _appendText(r'$', _span(pos, pos + 1));
    return pos + 1;
  }

  int _handleOpenAngle(int pos) {
    // 1. CommonMark URI autolink or email autolink.
    final ({String href, String label, int nextIndex})? auto =
        _matchAngleAutolink(pos);
    if (auto != null) {
      _appendActiveItem(
        _InlineItem.node(
          resolver._makeLinkNode(
            rawDestination: auto.href,
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
      if (options.inlineBreaks && _isBrTag(rawHtml)) {
        _appendActiveItem(
          _InlineItem.node(InlineBreakNode(span: _span(pos, htmlEnd))),
        );
        return htmlEnd;
      }
      if (options.explicitHeadingIds || options.headingSlugs) {
        final RegExpMatch? anchorMatch = _anchorTagPattern.firstMatch(rawHtml);
        if (anchorMatch != null &&
            _matchesCaseInsensitiveAt(input, htmlEnd, '</a>')) {
          final String rawId =
              (anchorMatch.group(1) ?? anchorMatch.group(2)) ?? '';
          final String id = decodeHtmlEntities(rawId);
          if (id.isNotEmpty) {
            _appendActiveItem(
              _InlineItem.node(
                AnchorInlineNode(id, span: _span(pos, htmlEnd + 4)),
              ),
            );
            return htmlEnd + 4;
          }
        }
      }
      if (options.figureBlocks &&
          _matchesCaseInsensitiveAt(rawHtml, 0, '<picture')) {
        final int closePic = _indexOfAsciiIgnoreCase(input, '</picture>', pos);
        if (closePic != -1) {
          final String fullPic = input.substring(pos, closePic + 10);
          final PictureInlineNode? picNode = _tryParsePicture(
            fullPic,
            _span(pos, closePic + 10),
          );
          if (picNode != null) {
            resolver._recordImageUrl(picNode.lightSource);
            resolver._recordImageUrl(picNode.darkSource);
            _appendActiveItem(_InlineItem.node(picNode));
            return closePic + 10;
          }
        }
      }
      if ((options.figureBlocks || options.kbd || options.headingSlugs) &&
          rawHtml.length >= 6 &&
          _matchesCaseInsensitiveAt(rawHtml, 0, '<img')) {
        final int afterName = rawHtml.codeUnitAt(4);
        if (afterName == 0x20 ||
            afterName == 0x09 ||
            afterName == 0x0A ||
            afterName == 0x0D) {
          final ImageNode? imgNode = _tryParseImgTag(
            rawHtml,
            _span(pos, htmlEnd),
          );
          if (imgNode != null) {
            _appendActiveItem(_InlineItem.node(imgNode));
            return htmlEnd;
          }
        }
      }
      if (options.kbd && _equalsAsciiIgnoreCase(rawHtml, '<kbd>')) {
        final int closeKbd = _indexOfAsciiIgnoreCase(input, '</kbd>', htmlEnd);
        if (closeKbd != -1) {
          final String inner = input.substring(htmlEnd, closeKbd);
          _appendActiveItem(
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
      _appendActiveItem(
        _InlineItem.node(RawHtmlInlineNode(rawHtml, span: _span(pos, htmlEnd))),
      );
      return htmlEnd;
    }

    _appendText('<', _span(pos, pos + 1));
    return pos + 1;
  }

  PictureInlineNode? _tryParsePicture(String html, SourceSpan span) {
    final RegExpMatch? darkMatch = _pictureDarkSrcsetPattern.firstMatch(html);
    final RegExpMatch? imgMatch = _pictureImgSrcPattern.firstMatch(html);
    if (darkMatch == null || imgMatch == null) {
      return null;
    }
    final RegExpMatch? altMatch = _pictureAltPattern.firstMatch(
      imgMatch.group(0)!,
    );
    final String rawLight = decodeHtmlEntities(imgMatch.group(1)!);
    final String rawDark = decodeHtmlEntities(darkMatch.group(1)!);
    final String alt = altMatch == null
        ? ''
        : decodeHtmlEntities(altMatch.group(1)!);
    return PictureInlineNode(
      lightSource: resolver._sanitizeDestination(rawLight),
      darkSource: resolver._sanitizeDestination(rawDark),
      alt: alt,
      span: span,
    );
  }

  ImageNode? _tryParseImgTag(String rawHtml, SourceSpan span) {
    final int len = rawHtml.length;
    int i = 4;
    String? src;
    String alt = '';
    String? title;
    int? width;
    int? height;

    while (i < len) {
      while (i < len && _isInlineHtmlWs(rawHtml.codeUnitAt(i))) {
        i++;
      }
      if (i >= len || rawHtml.codeUnitAt(i) == 0x3E) {
        break;
      }
      if (rawHtml.codeUnitAt(i) == 0x2F) {
        i++;
        continue;
      }
      final int nameStart = i;
      while (i < len && _isHtmlAttrNameChar(rawHtml.codeUnitAt(i))) {
        i++;
      }
      if (i == nameStart) {
        break;
      }
      final String name = rawHtml.substring(nameStart, i).toLowerCase();
      while (i < len && _isInlineHtmlWs(rawHtml.codeUnitAt(i))) {
        i++;
      }
      String value = '';
      if (i < len && rawHtml.codeUnitAt(i) == 0x3D) {
        i++;
        while (i < len && _isInlineHtmlWs(rawHtml.codeUnitAt(i))) {
          i++;
        }
        if (i < len) {
          final int q = rawHtml.codeUnitAt(i);
          if (q == 0x22 || q == 0x27) {
            i++;
            final int valStart = i;
            while (i < len && rawHtml.codeUnitAt(i) != q) {
              i++;
            }
            value = rawHtml.substring(valStart, i);
            if (i < len && rawHtml.codeUnitAt(i) == q) {
              i++;
            }
          } else {
            final int valStart = i;
            while (i < len &&
                !_isInlineHtmlWs(rawHtml.codeUnitAt(i)) &&
                rawHtml.codeUnitAt(i) != 0x3E) {
              i++;
            }
            if (i > valStart &&
                rawHtml.codeUnitAt(i - 1) == 0x2F &&
                i < len &&
                rawHtml.codeUnitAt(i) == 0x3E) {
              value = rawHtml.substring(valStart, i - 1);
            } else {
              value = rawHtml.substring(valStart, i);
            }
          }
        }
      }
      final String decoded = decodeHtmlEntities(value);
      switch (name) {
        case 'src':
          src = decoded;
        case 'alt':
          alt = decoded;
        case 'title':
          title = decoded;
        case 'width':
          width = _parseHtmlDimension(decoded);
        case 'height':
          height = _parseHtmlDimension(decoded);
        default:
          break;
      }
    }

    if (src == null) {
      return null;
    }
    return resolver._makeImageNode(
      rawDestination: src,
      alt: alt,
      title: title,
      width: width,
      height: height,
      children: alt.isEmpty
          ? const <MarkdownInlineNode>[]
          : <MarkdownInlineNode>[TextNode(alt, span: span)],
      span: span,
    );
  }

  ({String href, String label, int nextIndex})? _matchAngleAutolink(int pos) {
    if (pos >= _lastGtPos) {
      return null;
    }
    final int len = input.length;
    int close = -1;
    // Fast fail without scanning to EOF if newline, '<', or control/space occurs
    // before any closing '>' (neither URI nor email autolinks allow them).
    for (int i = pos + 1; i < len && i <= _lastGtPos; i++) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x3E) {
        close = i;
        break;
      }
      if (cu <= 0x20 || cu == 0x7F || cu == 0x3C) {
        return null;
      }
    }
    if (close <= pos + 1) {
      return null;
    }
    final String inside = input.substring(pos + 1, close);
    if (_uriAutolinkPattern.hasMatch(inside)) {
      return (href: inside, label: inside, nextIndex: close + 1);
    }
    if (_emailAutolinkPattern.hasMatch(inside)) {
      return (href: 'mailto:$inside', label: inside, nextIndex: close + 1);
    }
    return null;
  }

  int? _matchRawHtmlInline(int pos) {
    if (pos >= _lastGtPos) {
      return null;
    }
    final int len = input.length;
    if (pos + 2 >= len) {
      return null;
    }
    final int second = input.codeUnitAt(pos + 1);
    if (second == 0x21) {
      // '!'
      if (input.startsWith('<!-->', pos)) {
        return pos + 5;
      }
      if (input.startsWith('<!--->', pos)) {
        return pos + 6;
      }
      if (input.startsWith('<!--', pos)) {
        if (_noCommentClose) {
          return null;
        }
        final int end = input.indexOf('-->', pos + 4);
        if (end != -1) {
          return end + 3;
        }
        _noCommentClose = true;
        return null;
      }
      if (input.startsWith('<![CDATA[', pos)) {
        if (_noCdataClose) {
          return null;
        }
        final int end = input.indexOf(']]>', pos + 9);
        if (end != -1) {
          return end + 3;
        }
        _noCdataClose = true;
        return null;
      }
      if (_isHtmlAsciiAlpha(input.codeUnitAt(pos + 2))) {
        int i = pos + 3;
        while (i < len && _isHtmlAsciiAlpha(input.codeUnitAt(i))) {
          i++;
        }
        if (i < len && _isInlineHtmlWs(input.codeUnitAt(i))) {
          final int gt = input.indexOf('>', i + 1);
          if (gt != -1) {
            return gt + 1;
          }
        }
      }
      return null;
    }
    if (second == 0x3F) {
      // '?' Processing instruction `<?...?>`.
      if (_noPiClose) {
        return null;
      }
      final int end = input.indexOf('?>', pos + 2);
      if (end != -1) {
        return end + 2;
      }
      _noPiClose = true;
      return null;
    }
    return _scanInlineHtmlTagEnd(pos);
  }

  int? _scanInlineHtmlTagEnd(int pos) {
    final int len = input.length;
    int i = pos + 1;
    if (i >= len) {
      return null;
    }
    final int first = input.codeUnitAt(i);
    if (first == 0x2F) {
      // Closing tag `</tagname [ws]*>`
      i++;
      if (i >= len || !_isHtmlAsciiAlpha(input.codeUnitAt(i))) {
        return null;
      }
      i++;
      while (i < len && _isHtmlTagNameChar(input.codeUnitAt(i))) {
        i++;
      }
      while (i < len && _isInlineHtmlWs(input.codeUnitAt(i))) {
        i++;
      }
      if (i < len && input.codeUnitAt(i) == 0x3E) {
        return i + 1;
      }
      return null;
    }

    // Opening / self-closing tag `<tagname (attrs)* [ws]* /?>`
    if (!_isHtmlAsciiAlpha(first)) {
      return null;
    }
    i++;
    while (i < len && _isHtmlTagNameChar(input.codeUnitAt(i))) {
      i++;
    }

    int attrCount = 0;
    List<int>? visitedBoundaries;
    int? failFrom;
    while (i < len) {
      final int wsStart = i;
      while (i < len && _isInlineHtmlWs(input.codeUnitAt(i))) {
        i++;
      }
      if (i >= len) {
        failFrom = wsStart;
        break;
      }
      final int cu = input.codeUnitAt(i);
      if (cu == 0x2F) {
        if (i + 1 < len && input.codeUnitAt(i + 1) == 0x3E) {
          return i + 2;
        }
        failFrom = wsStart;
        break;
      }
      if (cu == 0x3E) {
        return i + 1;
      }
      if (i == wsStart || !_isHtmlAttrNameStart(cu)) {
        failFrom = wsStart;
        break;
      }
      if (_failedAttrBoundaries != null && _failedAttrBoundaries!.contains(i)) {
        failFrom = wsStart;
        break;
      }
      attrCount++;
      if (attrCount > 64) {
        visitedBoundaries ??= <int>[];
        visitedBoundaries.add(i);
      }

      i++;
      while (i < len && _isHtmlAttrNameChar(input.codeUnitAt(i))) {
        i++;
      }
      final int afterName = i;
      int wsEq = i;
      while (wsEq < len && _isInlineHtmlWs(input.codeUnitAt(wsEq))) {
        wsEq++;
      }
      if (wsEq < len && input.codeUnitAt(wsEq) == 0x3D) {
        i = wsEq + 1;
        while (i < len && _isInlineHtmlWs(input.codeUnitAt(i))) {
          i++;
        }
        if (i >= len) {
          failFrom = afterName;
          break;
        }
        final int q = input.codeUnitAt(i);
        if (q == 0x27) {
          if (i + 1 >= _noClosingSingleQuoteFrom) {
            failFrom = afterName;
            break;
          }
          final int closeQ = input.indexOf('\'', i + 1);
          if (closeQ == -1) {
            if (i + 1 < _noClosingSingleQuoteFrom) {
              _noClosingSingleQuoteFrom = i + 1;
            }
            failFrom = afterName;
            break;
          }
          i = closeQ + 1;
        } else if (q == 0x22) {
          if (i + 1 >= _noClosingDoubleQuoteFrom) {
            failFrom = afterName;
            break;
          }
          final int closeQ = input.indexOf('"', i + 1);
          if (closeQ == -1) {
            if (i + 1 < _noClosingDoubleQuoteFrom) {
              _noClosingDoubleQuoteFrom = i + 1;
            }
            failFrom = afterName;
            break;
          }
          i = closeQ + 1;
        } else {
          final int valStart = i;
          while (i < len) {
            final int ch = input.codeUnitAt(i);
            if (_isInlineHtmlWs(ch) ||
                ch == 0x22 ||
                ch == 0x27 ||
                ch == 0x3D ||
                ch == 0x3C ||
                ch == 0x3E ||
                ch == 0x60) {
              break;
            }
            i++;
          }
          if (i == valStart) {
            failFrom = afterName;
            break;
          }
        }
      } else {
        i = afterName;
      }
    }

    if (failFrom != null && visitedBoundaries != null) {
      (_failedAttrBoundaries ??= <int>{}).addAll(visitedBoundaries);
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
          _appendActiveItem(_InlineItem.node(fnRef));
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
          ..bracketSourcePos = pos
          ..delimStackLen = _delimiterIndices.length
          ..savedDelimTail = _delimTail;
    final int idx = _appendActiveItem(item);
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
    bool resolvedByRefDef = false;

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
          resolvedByRefDef = true;
        }
      }
    }

    if (matched && resolvedByRefDef) {
      final int expandedBytes =
          (destination?.length ?? 0) + (title?.length ?? 0);
      if (!resolver.tryConsumeExpandedBytes(expandedBytes)) {
        matched = false;
      }
    }

    if (!matched) {
      _appendText(']', _span(pos, pos + 1));
      return pos + 1;
    }

    final int maxAllowedInside =
        budgets.maxNestingDepth - _bracketIndices.length - 1;

    // Process emphasis strictly inside `[openerItemIdx + 1 ..]` in O(active).
    final int firstInsideDelim = opener.savedDelimTail == -1
        ? _delimHead
        : _nextDelim[opener.savedDelimTail];
    if (firstInsideDelim != -1) {
      _processEmphasis(
        bottomDelimPos: opener.savedDelimTail,
        firstCandidateDelimPos: firstInsideDelim,
        maxAllowedDepth: maxAllowedInside < 0 ? 0 : maxAllowedInside,
      );
    }

    // Collect active nodes strictly after `opener` and measure depth.
    int maxChildDepth = 0;
    final List<MarkdownInlineNode> rawChildren = <MarkdownInlineNode>[];
    int cur = opener.nextActive;
    while (cur != -1) {
      final _InlineItem childItem = _items[cur];
      final MarkdownInlineNode n = childItem.node;
      if (childItem.inlineDepth > maxChildDepth) {
        maxChildDepth = childItem.inlineDepth;
      }
      if (n is! TextNode || n.text.isNotEmpty) {
        rawChildren.add(n);
      }
      cur = childItem.nextActive;
    }
    final List<MarkdownInlineNode> children = freezeList(
      _coalesceTextNodes(rawChildren),
    );

    // Truncate delimiter lists in O(1) back to opener.delimStackLen.
    _delimiterIndices.length = opener.delimStackLen;
    _prevDelim.length = opener.delimStackLen;
    _nextDelim.length = opener.delimStackLen;
    _delimTail = opener.savedDelimTail;
    if (_delimTail != -1) {
      _nextDelim[_delimTail] = -1;
    } else {
      _delimHead = -1;
    }

    // Unlink `opener` and everything after it from active items in O(1).
    final int beforeOpener = opener.prevActive;
    if (beforeOpener != -1) {
      _items[beforeOpener].nextActive = -1;
      _activeTail = beforeOpener;
    } else {
      _activeHead = -1;
      _activeTail = -1;
    }

    final int newDepth = 1 + maxChildDepth;
    if (isImage) {
      final String alt = _extractAltText(children);
      _appendActiveItem(
        _InlineItem.node(
          resolver._makeImageNode(
            rawDestination: destination ?? '',
            alt: alt,
            title: title,
            children: children,
            span: _span(opener.bracketSourcePos, afterBracket),
          ),
          inlineDepth: newDepth,
        ),
      );
    } else {
      // Links cannot contain other links: deactivate all ancestor non-image brackets.
      for (final int bIdx in _bracketIndices) {
        if (!_items[bIdx].bracketIsImage) {
          _items[bIdx].bracketActive = false;
        }
      }
      _appendActiveItem(
        _InlineItem.node(
          resolver._makeLinkNode(
            rawDestination: destination ?? '',
            title: title,
            children: children,
            isAutolink: false,
            span: _span(opener.bracketSourcePos, afterBracket),
          ),
          inlineDepth: newDepth,
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
      return (destination: '', title: null, nextIndex: i + 1);
    }

    if (input.codeUnitAt(i) == 0x3C) {
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

    final bool canOpen;
    final bool canClose;

    if (delimCu == 0x5F) {
      canOpen = leftFlanking && (!rightFlanking || beforePunct);
      canClose = rightFlanking && (!leftFlanking || afterPunct);
    } else if (delimCu == 0x7E) {
      canOpen = leftFlanking;
      canClose = rightFlanking;
    } else {
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
    _appendDelimiter(item);
    return end;
  }

  void _processEmphasis({
    required int bottomDelimPos,
    required int firstCandidateDelimPos,
    required int maxAllowedDepth,
  }) {
    final Map<int, int> openersBottom = <int, int>{};
    int depthFloorDelimPos = bottomDelimPos;

    int currentPos = firstCandidateDelimPos;
    while (currentPos != -1) {
      final int closerItemIdx = _delimiterIndices[currentPos];
      final _InlineItem closer = _items[closerItemIdx];
      if (!closer.isDelimiter || !closer.canClose || closer.delimCount == 0) {
        currentPos = _nextDelim[currentPos];
        continue;
      }

      final int key =
          (closer.delimChar << 4) |
          ((closer.origCount % 3) << 1) |
          (closer.canOpen ? 1 : 0);
      int bottomLimit = openersBottom[key] ?? bottomDelimPos;
      if (depthFloorDelimPos > bottomLimit) {
        bottomLimit = depthFloorDelimPos;
      }

      int openerPos = _prevDelim[currentPos];
      int foundOpenerPos = -1;

      while (openerPos > bottomLimit) {
        final int openerItemIdx = _delimiterIndices[openerPos];
        final _InlineItem opener = _items[openerItemIdx];
        if (!opener.isDelimiter ||
            !opener.canOpen ||
            opener.delimCount == 0 ||
            opener.delimChar != closer.delimChar) {
          openerPos = _prevDelim[openerPos];
          continue;
        }

        if (closer.delimChar == 0x7E ||
            closer.delimChar == 0x3D ||
            closer.delimChar == 0x5E) {
          if (opener.origCount != closer.origCount) {
            openerPos = _prevDelim[openerPos];
            continue;
          }
        }

        if ((closer.delimChar == 0x2A || closer.delimChar == 0x5F) &&
            (opener.canClose || closer.canOpen) &&
            ((opener.origCount + closer.origCount) % 3 == 0) &&
            !(opener.origCount % 3 == 0 && closer.origCount % 3 == 0)) {
          openerPos = _prevDelim[openerPos];
          continue;
        }

        foundOpenerPos = openerPos;
        break;
      }

      if (foundOpenerPos == -1) {
        openersBottom[key] = currentPos - 1;
        final int nextPos = _nextDelim[currentPos];
        if (!closer.canOpen) {
          closer.isDelimiter = false;
          _unlinkDelim(currentPos);
        }
        currentPos = nextPos;
        continue;
      }

      final int openerItemIdx = _delimiterIndices[foundOpenerPos];
      final _InlineItem opener = _items[openerItemIdx];

      // Measure interior nesting depth BEFORE mutating/unlinking so exceeded
      // delimiters remain cleanly untouched as literal text in O(N).
      int maxChildDepth = 0;
      bool exceedsDepth = false;
      int cur = opener.nextActive;
      while (cur != -1 && cur != closerItemIdx) {
        final int d = _items[cur].inlineDepth;
        if (d > maxChildDepth) {
          maxChildDepth = d;
          if (1 + maxChildDepth > maxAllowedDepth) {
            exceedsDepth = true;
            break;
          }
        }
        cur = _items[cur].nextActive;
      }

      if (exceedsDepth || 1 + maxChildDepth > maxAllowedDepth) {
        if (foundOpenerPos > depthFloorDelimPos) {
          depthFloorDelimPos = foundOpenerPos;
        }
        openersBottom[key] = currentPos - 1;
        final int nextPos = _nextDelim[currentPos];
        if (!closer.canOpen) {
          closer.isDelimiter = false;
          _unlinkDelim(currentPos);
        }
        currentPos = nextPos;
        continue;
      }

      final int useCount;
      if (closer.delimChar == 0x7E) {
        useCount = opener.delimCount;
      } else if (closer.delimChar == 0x3D) {
        useCount = 2;
      } else if (closer.delimChar == 0x5E) {
        useCount = 1;
      } else {
        useCount = (opener.delimCount >= 2 && closer.delimCount >= 2) ? 2 : 1;
      }

      opener.delimCount -= useCount;
      closer.delimCount -= useCount;

      final String delimStr = _repeatDelimChar(opener.delimChar, useCount);
      opener.node = TextNode(
        _repeatDelimChar(opener.delimChar, opener.delimCount),
        span: opener.node.span,
      );
      closer.node = TextNode(
        _repeatDelimChar(closer.delimChar, closer.delimCount),
        span: closer.node.span,
      );

      // Drop all interior delimiters strictly between foundOpenerPos and
      // currentPos in O(1) via doubly-linked delimiter chain.
      _nextDelim[foundOpenerPos] = currentPos;
      _prevDelim[currentPos] = foundOpenerPos;

      // Collect interior active nodes between openerItemIdx and closerItemIdx.
      final List<MarkdownInlineNode> rawChildren = <MarkdownInlineNode>[];
      cur = opener.nextActive;
      while (cur != -1 && cur != closerItemIdx) {
        final MarkdownInlineNode n = _items[cur].node;
        if (n is! TextNode || n.text.isNotEmpty) {
          rawChildren.add(n);
        }
        cur = _items[cur].nextActive;
      }
      final List<MarkdownInlineNode> children = freezeList(
        _coalesceTextNodes(rawChildren),
      );

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

      // Splice wrapped node into active item list between openerItemIdx and
      // closerItemIdx in O(1), unlinking all interior items without shifting.
      final int wrappedIdx = _items.length;
      _items.add(
        _InlineItem.node(wrapped, inlineDepth: 1 + maxChildDepth)
          ..prevActive = openerItemIdx
          ..nextActive = closerItemIdx,
      );
      opener.nextActive = wrappedIdx;
      closer.prevActive = wrappedIdx;

      if (opener.delimCount == 0) {
        opener.isDelimiter = false;
        opener.isText = false;
        _unlinkDelim(foundOpenerPos);
      }
      if (closer.delimCount == 0) {
        closer.isDelimiter = false;
        closer.isText = false;
        final int nextPos = _nextDelim[currentPos];
        _unlinkDelim(currentPos);
        currentPos = nextPos;
      }
    }
  }

  List<MarkdownInlineNode> _collectActiveNodesCoalesced(int headIdx) {
    final List<MarkdownInlineNode> result = <MarkdownInlineNode>[];
    int cur = headIdx;
    while (cur != -1) {
      final _InlineItem item = _items[cur];
      final MarkdownInlineNode n = item.node;
      if (n is! TextNode || n.text.isNotEmpty) {
        result.add(n);
      }
      cur = item.nextActive;
    }
    return _coalesceTextNodes(result);
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
            resolver._makeLinkNode(
              rawDestination: match.url,
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
              resolver._makeLinkNode(
                rawDestination: match.url,
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
            resolver._makeLinkNode(
              rawDestination: emailMatch.href,
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
      if (!t.text.contains(':')) {
        return <MarkdownInlineNode>[t];
      }
      final String replaced = t.text.replaceAllMapped(
        _emojiShortcodePattern,
        (Match m) => emojiShortcodes[m.group(1)!] ?? m.group(0)!,
      );
      if (identical(replaced, t.text)) {
        return <MarkdownInlineNode>[t];
      }
      return <MarkdownInlineNode>[TextNode(replaced, span: t.span)];
    });
  }

  List<MarkdownInlineNode> _applySmartPunctuation(
    List<MarkdownInlineNode> nodes,
  ) {
    return _mapTextNodes(nodes, (TextNode t) {
      String s = t.text;
      bool changed = false;
      if (s.contains('--')) {
        s = s.replaceAll('---', '\u2014').replaceAll('--', '\u2013');
        changed = true;
      }
      if (s.contains('...')) {
        s = s.replaceAll('...', '\u2026');
        changed = true;
      }
      if (s.contains('"') || s.contains("'")) {
        s = _smartQuotes(s);
        changed = true;
      }
      if (!changed) {
        return <MarkdownInlineNode>[t];
      }
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
    final RegExp? abbrPattern = resolver.abbrPattern;
    if (abbrPattern == null) {
      return nodes;
    }
    return _mapTextNodes(nodes, (TextNode t) {
      final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
      int last = 0;
      for (final Match m in abbrPattern.allMatches(t.text)) {
        final String abbr = m.group(1)!;
        final String? title = resolver.abbreviations[abbr];
        if (title == null || !resolver.tryConsumeExpandedBytes(title.length)) {
          break;
        }
        if (m.start > last) {
          out.add(TextNode(t.text.substring(last, m.start), span: t.span));
        }
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
            createBlockedLinkNodeFromExisting(
              node,
              children: _mapTextNodes(node.children, fn),
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

LinkNode createBlockedLinkNodeFromExisting(
  LinkNode existing, {
  required List<MarkdownInlineNode> children,
}) {
  if (isBlockedLinkNode(existing)) {
    return createBlockedLinkNode(
      title: existing.title,
      children: children,
      isAutolink: existing.isAutolink,
      span: existing.span,
    );
  }
  return LinkNode(
    destination: existing.destination,
    title: existing.title,
    children: children,
    isAutolink: existing.isAutolink,
    span: existing.span,
  );
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

bool _isHtmlAsciiAlpha(int cu) =>
    (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A);

bool _isHtmlTagNameChar(int cu) =>
    _isHtmlAsciiAlpha(cu) || (cu >= 0x30 && cu <= 0x39) || cu == 0x2D;

bool _isHtmlAttrNameStart(int cu) =>
    _isHtmlAsciiAlpha(cu) || cu == 0x5F || cu == 0x3A;

bool _isHtmlAttrNameChar(int cu) =>
    _isHtmlTagNameChar(cu) || cu == 0x5F || cu == 0x3A || cu == 0x2E;

bool _isInlineHtmlWs(int cu) =>
    cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;

bool _isBrTag(String rawHtml) {
  final int len = rawHtml.length;
  if (len < 4 || rawHtml.codeUnitAt(len - 1) != 0x3E) {
    return false;
  }
  if (rawHtml.codeUnitAt(0) != 0x3C) {
    return false;
  }
  final int b = rawHtml.codeUnitAt(1);
  final int r = rawHtml.codeUnitAt(2);
  if ((b != 0x62 && b != 0x42) || (r != 0x72 && r != 0x52)) {
    return false;
  }
  int i = 3;
  while (i < len - 1 && _isInlineHtmlWs(rawHtml.codeUnitAt(i))) {
    i++;
  }
  if (i == len - 1) {
    return true;
  }
  return i == len - 2 && rawHtml.codeUnitAt(i) == 0x2F;
}

bool _equalsAsciiIgnoreCase(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    int ca = a.codeUnitAt(i);
    int cb = b.codeUnitAt(i);
    if (ca >= 0x41 && ca <= 0x5A) {
      ca += 0x20;
    }
    if (cb >= 0x41 && cb <= 0x5A) {
      cb += 0x20;
    }
    if (ca != cb) {
      return false;
    }
  }
  return true;
}

int _indexOfAsciiIgnoreCase(String haystack, String lowerNeedle, int start) {
  final int nLen = lowerNeedle.length;
  final int limit = haystack.length - nLen;
  for (int i = start; i <= limit; i++) {
    bool match = true;
    for (int j = 0; j < nLen; j++) {
      int ch = haystack.codeUnitAt(i + j);
      if (ch >= 0x41 && ch <= 0x5A) {
        ch += 0x20;
      }
      if (ch != lowerNeedle.codeUnitAt(j)) {
        match = false;
        break;
      }
    }
    if (match) {
      return i;
    }
  }
  return -1;
}

int? _parseHtmlDimension(String raw) {
  String s = raw.trim();
  if (s.isEmpty) {
    return null;
  }
  if (s.length > 2) {
    final int c1 = s.codeUnitAt(s.length - 2);
    final int c2 = s.codeUnitAt(s.length - 1);
    if ((c1 == 0x70 || c1 == 0x50) && (c2 == 0x78 || c2 == 0x58)) {
      s = s.substring(0, s.length - 2).trimRight();
    }
  }
  final int? intVal = int.tryParse(s);
  if (intVal != null) {
    return (intVal > 0 && intVal <= 100000) ? intVal : null;
  }
  final double? val = double.tryParse(s);
  if (val == null || !val.isFinite || val <= 0 || val > 100000) {
    return null;
  }
  final int rounded = val.round();
  return (rounded > 0 && rounded <= 100000) ? rounded : null;
}

final RegExp _uriAutolinkPattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\x00-\x20\x7F<>]*$',
);

final RegExp _emailAutolinkPattern = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
);

final RegExp _emojiShortcodePattern = RegExp(r':([a-z0-9_+-]+):');

final RegExp _anchorTagPattern = RegExp(
  r'''^<a\s+(?:id|name)\s*=\s*(?:"([^"]+)"|'([^']+)')\s*>$''',
  caseSensitive: false,
);

final RegExp _pictureDarkSrcsetPattern = RegExp(
  r'''prefers-color-scheme\s*:\s*dark[^>]*srcset\s*=\s*["']([^"']+)["']''',
  caseSensitive: false,
);

final RegExp _pictureImgSrcPattern = RegExp(
  r'''<img\b[^>]*src\s*=\s*["']([^"']+)["'][^>]*>''',
  caseSensitive: false,
);

final RegExp _pictureAltPattern = RegExp(
  r'''alt\s*=\s*["']([^"']*)["']''',
  caseSensitive: false,
);
