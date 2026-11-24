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

/// Phase 2 resolution output containing finalized immutable AST blocks and
/// ordered footnotes.
final class Phase2Result {
  /// Creates a [Phase2Result].
  const Phase2Result({required this.blocks, required this.footnotes});

  /// Finalized top-level block AST nodes.
  final List<MarkdownBlockNode> blocks;

  /// Referenced footnotes in first-citation order (followed by any unreferenced
  /// definitions if inspected via `MarkdownDocument.footnotes`).
  final List<FootnoteDefinitionNode> footnotes;
}

/// Resolves inline syntax, links, images, emphasis, autolinks, math, footnotes,
/// slugs, and extensions across a Phase 1 block tree.
Phase2Result parseInlines(
  Phase1Result phase1,
  MarkdownOptions options, {
  HeadingSlugGenerator? slugGenerator,
  List<String>? seedHeadingTexts,
  int seedHeadingCount = 0,
}) {
  final _InlineResolver resolver = _InlineResolver(
    options: options,
    budgets: options.effectiveBudgets,
    linkDefinitions: phase1.linkDefinitions,
    rawFootnotes: phase1.footnoteDefinitions,
    abbreviations: phase1.abbreviations,
    idPrefix: phase1.idPrefix,
    seedSlugs: slugGenerator,
    seedHeadingTexts: seedHeadingTexts,
    seedHeadingCount: seedHeadingCount,
  );
  return resolver.resolveDocument(phase1.blocks);
}

/// Reusable inline resolver for single-paragraph streaming updates without
/// reallocating resolver/scanner state on every chunk.
final class ReusableParagraphInlineResolver {
  /// Creates a reusable paragraph inline resolver for fixed `options`.
  ReusableParagraphInlineResolver(MarkdownOptions options)
    : _resolver = _InlineResolver(
        options: options,
        budgets: options.effectiveBudgets,
        linkDefinitions: const <String, MarkdownLinkDefinition>{},
        rawFootnotes: const <String, RawFootnoteDef>{},
        abbreviations: const <String, String>{},
        idPrefix: '',
      );

  final _InlineResolver _resolver;

  /// Parses inline children of a single paragraph using cached scratch buffers.
  List<MarkdownInlineNode> parse(String input, SourceSpan span) {
    _resolver.resetCounters();
    return _resolver._parseInlineString(input, span);
  }
}

/// Reusable document-level inline resolver for streaming active-tail parses,
/// avoiding re-allocating scanner buffers on every non-paragraph chunk.
final class ReusableBlockInlineResolver {
  /// Creates a reusable document-level inline resolver for fixed `options`.
  ReusableBlockInlineResolver(MarkdownOptions options)
    : _resolver = _InlineResolver(
        options: options,
        budgets: options.effectiveBudgets,
        linkDefinitions: const <String, MarkdownLinkDefinition>{},
        rawFootnotes: const <String, RawFootnoteDef>{},
        abbreviations: const <String, String>{},
        idPrefix: '',
      );

  final _InlineResolver _resolver;

  /// Resolves all inlines across [phase1] reusing internal scratch buffers.
  Phase2Result parse(
    Phase1Result phase1, {
    HeadingSlugGenerator? slugGenerator,
    List<String>? seedHeadingTexts,
    int seedHeadingCount = 0,
  }) {
    _resolver.resetForDocument(
      phase1,
      seedSlugs: slugGenerator,
      seedHeadingTexts: seedHeadingTexts,
      seedHeadingCount: seedHeadingCount,
    );
    return _resolver.resolveDocument(phase1.blocks);
  }

  /// Resolves inline nodes for a single paragraph string reusing internal
  /// scratch buffers.
  List<MarkdownInlineNode> parseParagraph(String input, SourceSpan span) {
    _resolver.resetForParagraph();
    return _resolver._parseInlineString(input, span);
  }
}

const int _maxAbbrPatternKeys = 512;

// 128-byte ASCII LUT cached per structural feature-bit combination:
//   0 = plain ASCII byte (never starts an inline construct or post-pass)
//   1 = structural inline delimiter / trigger
//   2 = post-pass candidate (':', '@', '.', '"', '\'', '-')
final List<Uint8List?> _structuralLutCache = List<Uint8List?>.filled(16, null);

Uint8List _getStructuralLut(MarkdownOptions options) {
  final int key =
      ((options.gfmStrikethrough || options.subscript) ? 1 : 0) |
      (options.highlight ? 2 : 0) |
      (options.superscript ? 4 : 0) |
      (options.math ? 8 : 0);
  return _structuralLutCache[key] ??= _buildStructuralLut(options);
}

Uint8List _buildStructuralLut(MarkdownOptions options) {
  final Uint8List lut = Uint8List(128);
  // Post-processing trigger bytes (disjoint from all structural bytes).
  lut[0x3A] = 2; // ':' (emoji or ://)
  lut[0x40] = 2; // '@' (email autolink)
  lut[0x2E] = 2; // '.' (www. or ...)
  lut[0x22] = 2; // '"' (smart quote)
  lut[0x27] = 2; // '\'' (smart quote)
  lut[0x2D] = 2; // '-' (-- / ---)
  // Structural inline bytes.
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

final Uint8List _asciiFlankLut = _buildAsciiFlankLut();

Uint8List _buildAsciiFlankLut() {
  final Uint8List lut = Uint8List(128);
  lut[0x20] = 1;
  lut[0x09] = 1;
  lut[0x0A] = 1;
  lut[0x0C] = 1;
  lut[0x0D] = 1;
  for (int cu = 0x21; cu <= 0x2F; cu++) {
    lut[cu] = 2;
  }
  for (int cu = 0x3A; cu <= 0x40; cu++) {
    lut[cu] = 2;
  }
  for (int cu = 0x5B; cu <= 0x60; cu++) {
    lut[cu] = 2;
  }
  for (int cu = 0x7B; cu <= 0x7E; cu++) {
    lut[cu] = 2;
  }
  return lut;
}

bool _isEmojiShortcodeChar(int cu) =>
    (cu >= 0x61 && cu <= 0x7A) ||
    (cu >= 0x30 && cu <= 0x39) ||
    cu == 0x5F ||
    cu == 0x2B ||
    cu == 0x2D;

bool _hasEmojiShortcodeCandidate(String input, int colonPos, int len) {
  if (colonPos + 2 >= len ||
      !_isEmojiShortcodeChar(input.codeUnitAt(colonPos + 1))) {
    return false;
  }
  int j = colonPos + 2;
  while (j < len) {
    final int c = input.codeUnitAt(j);
    if (c == 0x3A) {
      return true;
    }
    if (!_isEmojiShortcodeChar(c)) {
      return false;
    }
    j++;
  }
  return false;
}

final class _InlineResolver {
  _InlineResolver({
    required this.options,
    required this.budgets,
    required this.linkDefinitions,
    required this.rawFootnotes,
    required this.abbreviations,
    required this.idPrefix,
    HeadingSlugGenerator? seedSlugs,
    List<String>? seedHeadingTexts,
    int seedHeadingCount = 0,
  }) : _seedSlugs = seedSlugs,
       _seedHeadingTexts = seedHeadingTexts ?? _emptySeedHeadingTexts,
       _seedHeadingCount = seedHeadingCount,
       structuralLut = _getStructuralLut(options);

  static final List<String> _emptySeedHeadingTexts = <String>[];

  final MarkdownOptions options;
  final MarkdownBudgets budgets;
  Map<String, MarkdownLinkDefinition> linkDefinitions;
  Map<String, RawFootnoteDef> rawFootnotes;
  Map<String, String> abbreviations;
  String idPrefix;
  final Uint8List structuralLut;
  _InlineScanner? _scanner;

  HeadingSlugGenerator? _seedSlugs;
  List<String> _seedHeadingTexts;
  int _seedHeadingCount;
  HeadingSlugBatch? _slugBatch;

  // Footnote citation tracking in order of first reference (lazy).
  List<String>? _citedFootnoteOrder;
  Map<String, int>? _footnoteIndexByLabel;
  Map<String, int>? _footnoteRefCountByLabel;
  Map<String, FootnoteDefinitionNode>? _resolvedFootnotes;

  int _synthCounter = 0;
  int _totalTokens = 0;
  int _expandedOutputBytes = 0;
  RegExp? _cachedAbbrPattern;

  void resetCounters() {
    _synthCounter = 0;
    _totalTokens = 0;
    _expandedOutputBytes = 0;
  }

  void resetForDocument(
    Phase1Result phase1, {
    HeadingSlugGenerator? seedSlugs,
    List<String>? seedHeadingTexts,
    int seedHeadingCount = 0,
  }) {
    linkDefinitions = phase1.linkDefinitions;
    rawFootnotes = phase1.footnoteDefinitions;
    abbreviations = phase1.abbreviations;
    idPrefix = phase1.idPrefix;
    _seedSlugs = seedSlugs;
    _seedHeadingTexts = seedHeadingTexts ?? _emptySeedHeadingTexts;
    _seedHeadingCount = seedHeadingCount;
    _slugBatch = null;
    _citedFootnoteOrder?.clear();
    _footnoteIndexByLabel?.clear();
    _footnoteRefCountByLabel?.clear();
    _resolvedFootnotes?.clear();
    _cachedAbbrPattern = null;
    resetCounters();
  }

  void resetForParagraph() {
    linkDefinitions = const <String, MarkdownLinkDefinition>{};
    rawFootnotes = const <String, RawFootnoteDef>{};
    abbreviations = const <String, String>{};
    idPrefix = '';
    _seedSlugs = null;
    _seedHeadingTexts = _emptySeedHeadingTexts;
    _seedHeadingCount = 0;
    _slugBatch = null;
    _cachedAbbrPattern = null;
    resetCounters();
  }

  _InlineScanner get scanner => _scanner ??= _InlineScanner(resolver: this);

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
    if (rawFootnotes.isEmpty) {
      return Phase2Result(
        blocks: resolvedBlocks,
        footnotes: const <FootnoteDefinitionNode>[],
      );
    }

    final List<String>? citedOrder = _citedFootnoteOrder;
    final Map<String, int>? indexByLabel = _footnoteIndexByLabel;
    final Map<String, int>? refCountByLabel = _footnoteRefCountByLabel;
    final Map<String, FootnoteDefinitionNode> resolvedFootnotes =
        _resolvedFootnotes ??= <String, FootnoteDefinitionNode>{};

    // Resolve cited footnotes iteratively so footnote-in-footnote references
    // are discovered in citation order without risking cycles.
    if (citedOrder != null) {
      int queueIdx = 0;
      while (queueIdx < citedOrder.length) {
        final String label = citedOrder[queueIdx];
        queueIdx++;
        final RawFootnoteDef? rawDef = rawFootnotes[label];
        if (rawDef == null) {
          continue;
        }
        final List<MarkdownBlockNode> body = _resolveBlockList(rawDef.children);
        resolvedFootnotes[label] = createFrozenFootnoteDefinitionNode(
          blockId: rawDef.blockId,
          span: rawDef.span,
          label: rawDef.label,
          index: indexByLabel![label]!,
          referenceCount: refCountByLabel![label] ?? 1,
          children: body,
        );
      }
    }

    // Update final referenceCounts in case footnotes referenced earlier ones.
    final List<FootnoteDefinitionNode> orderedCited =
        <FootnoteDefinitionNode>[];
    if (citedOrder != null) {
      for (final String label in citedOrder) {
        final FootnoteDefinitionNode? def = resolvedFootnotes[label];
        if (def != null) {
          orderedCited.add(
            createFrozenFootnoteDefinitionNode(
              blockId: def.blockId,
              span: def.span,
              label: def.label,
              index: indexByLabel![label]!,
              referenceCount: refCountByLabel![label] ?? 1,
              children: def.children,
            ),
          );
        }
      }
    }

    final List<MarkdownBlockNode> finalBlocks;
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
      finalBlocks = freezeFreshList(<MarkdownBlockNode>[
        ...resolvedBlocks,
        createFrozenFootnoteSectionNode(
          blockId: '${idPrefix}footnote-section',
          definitions: freezeFreshList(orderedCited),
          span: SourceSpan(
            startOffset: minStartOffset,
            endOffset: maxEndOffset,
            startLine: minStartLine,
            endLine: maxEndLine,
          ),
        ),
      ]);
    } else {
      finalBlocks = resolvedBlocks;
    }

    // Also resolve unreferenced footnote definitions for `document.footnotes`.
    final List<FootnoteDefinitionNode> allFootnotes = <FootnoteDefinitionNode>[
      ...orderedCited,
    ];
    for (final MapEntry<String, RawFootnoteDef> entry in rawFootnotes.entries) {
      if (indexByLabel == null || !indexByLabel.containsKey(entry.key)) {
        final RawFootnoteDef rawDef = entry.value;
        allFootnotes.add(
          createFrozenFootnoteDefinitionNode(
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
      footnotes: freezeFreshList(allFootnotes),
    );
  }

  List<MarkdownBlockNode> _resolveBlockList(List<RawBlock> rawBlocks) {
    final int len = rawBlocks.length;
    if (len == 0) {
      return emptyFrozenBlockList;
    }
    if (len == 1) {
      return freezeFreshList(<MarkdownBlockNode>[_resolveBlock(rawBlocks[0])]);
    }
    final List<MarkdownBlockNode> out = <MarkdownBlockNode>[
      for (int i = 0; i < len; i++) _resolveBlock(rawBlocks[i]),
    ];
    return freezeFreshList(out);
  }

  HeadingNode _buildResolvedHeading({
    required String blockId,
    required SourceSpan span,
    required int level,
    required String rawText,
    String? explicitId,
    required bool isSetext,
  }) {
    final List<MarkdownInlineNode> children = _parseInlineString(rawText, span);
    final String plain = children.length == 1 && children[0] is TextNode
        ? (children[0] as TextNode).text
        : _extractPlainText(children);
    String? slug;
    HeadingSlugBatch? slugBatch;
    if (options.explicitHeadingIds && explicitId != null) {
      slug = explicitId;
    } else if (options.headingSlugs) {
      slugBatch = _slugBatch ??= HeadingSlugBatch(
        _seedSlugs,
        _seedHeadingTexts,
        _seedHeadingCount,
      );
    }
    return createFrozenHeadingNode(
      blockId: blockId,
      span: span,
      level: level,
      text: plain,
      slug: slug,
      slugBatch: slugBatch,
      explicitId: explicitId,
      children: children,
      isSetext: isSetext,
    );
  }

  MarkdownBlockNode _resolveBlock(RawBlock raw) {
    switch (raw) {
      case RawFrontmatter():
        return raw.node;
      case RawParagraph():
        return createFrozenParagraphNode(
          blockId: raw.blockId,
          span: raw.span,
          children: _parseInlineString(raw.rawText, raw.span),
        );
      case RawHeading():
        return _buildResolvedHeading(
          blockId: raw.blockId,
          span: raw.span,
          level: raw.level,
          rawText: raw.rawText,
          explicitId: raw.explicitId,
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
        return createFrozenBlockQuoteNode(
          blockId: raw.blockId,
          span: raw.span,
          children: _resolveBlockList(raw.children),
        );
      case RawAlert():
        return createFrozenAlertNode(
          blockId: raw.blockId,
          span: raw.span,
          kind: raw.kind,
          title: raw.title,
          children: _resolveBlockList(raw.children),
        );
      case RawList():
        return createFrozenListNode(
          blockId: raw.blockId,
          span: raw.span,
          ordered: raw.ordered,
          start: raw.start,
          tight: raw.tight,
          delimiter: raw.delimiter,
          items: freezeFreshList(<ListItemNode>[
            for (int i = 0; i < raw.items.length; i++)
              createFrozenListItemNode(
                blockId: raw.items[i].blockId,
                span: raw.items[i].span,
                taskState: raw.items[i].taskStateCode < 0
                    ? null
                    : raw.items[i].taskStateCode != 0,
                children: _resolveBlockList(raw.items[i].children),
              ),
          ]),
        );
      case RawListItem():
        return createFrozenListItemNode(
          blockId: raw.blockId,
          span: raw.span,
          taskState: raw.taskStateCode < 0 ? null : raw.taskStateCode != 0,
          children: _resolveBlockList(raw.children),
        );
      case RawTable():
        return _resolveTable(raw);
      case RawDefinitionList():
        return _resolveDefinitionList(raw);
      case RawFootnoteDef():
        return createFrozenFootnoteDefinitionNode(
          blockId: raw.blockId,
          span: raw.span,
          label: raw.label,
          index: 0,
          referenceCount: 0,
          children: _resolveBlockList(raw.children),
        );
      case RawDetailsBlock():
        return _resolveDetailsBlock(raw);
      case RawAlignedBlock():
        return createFrozenAlignedBlockNode(
          blockId: raw.blockId,
          span: raw.span,
          alignment: raw.alignment,
          children: _resolveBlockList(raw.children),
        );
      case RawFigureBlock():
        return _resolveFigureBlock(raw);
    }
  }

  static final List<List<TableCellNode>> _emptyTableRows =
      <List<TableCellNode>>[];

  TableNode _resolveTable(RawTable raw) {
    final int colCount = raw.alignments.length;
    final List<TableCellNode> headers;
    if (colCount == 0) {
      headers = emptyFrozenTableCellList;
    } else if (colCount == 1) {
      final String cellText = raw.headerCells.isNotEmpty
          ? raw.headerCells[0]
          : '';
      headers = freezeSingleton<TableCellNode>(
        createFrozenTableCellNode(
          children: _parseInlineString(cellText, raw.span),
          alignment: raw.alignments[0],
          span: raw.span,
        ),
      );
    } else {
      headers = freezeFreshList(<TableCellNode>[
        for (int c = 0; c < colCount; c++)
          createFrozenTableCellNode(
            children: _parseInlineString(
              c < raw.headerCells.length ? raw.headerCells[c] : '',
              raw.span,
            ),
            alignment: raw.alignments[c],
            span: raw.span,
          ),
      ]);
    }
    final int rowCount = raw.rows.length;
    final List<List<TableCellNode>> rows;
    if (rowCount == 0) {
      rows = freezeFreshList(_emptyTableRows);
    } else {
      final List<List<TableCellNode>> builtRows = <List<TableCellNode>>[
        for (int r = 0; r < rowCount; r++)
          if (colCount == 0)
            emptyFrozenTableCellList
          else if (colCount == 1)
            freezeSingleton<TableCellNode>(
              createFrozenTableCellNode(
                children: _parseInlineString(
                  raw.rows[r].isNotEmpty ? raw.rows[r][0] : '',
                  raw.span,
                ),
                alignment: raw.alignments[0],
                span: raw.span,
              ),
            )
          else
            freezeFreshList(<TableCellNode>[
              for (int c = 0; c < colCount; c++)
                createFrozenTableCellNode(
                  children: _parseInlineString(
                    c < raw.rows[r].length ? raw.rows[r][c] : '',
                    raw.span,
                  ),
                  alignment: raw.alignments[c],
                  span: raw.span,
                ),
            ]),
      ];
      rows = freezeFreshList(builtRows);
    }
    return createFrozenTableNode(
      blockId: raw.blockId,
      span: raw.span,
      alignments: raw.alignments,
      headers: headers,
      rows: rows,
    );
  }

  DefinitionListNode _resolveDefinitionList(RawDefinitionList raw) {
    final List<DefinitionGroup> groups = <DefinitionGroup>[
      for (final RawDefGroup g in raw.groups)
        createFrozenDefinitionGroup(
          term: _parseInlineString(g.termRaw, g.span),
          definitions: freezeFreshList(<List<MarkdownBlockNode>>[
            for (final List<RawBlock> d in g.definitions) _resolveBlockList(d),
          ]),
          span: g.span,
        ),
    ];
    return createFrozenDefinitionListNode(
      blockId: raw.blockId,
      span: raw.span,
      groups: freezeFreshList(groups),
    );
  }

  DetailsBlockNode _resolveDetailsBlock(RawDetailsBlock raw) {
    final List<MarkdownInlineNode> sumInlines = _parseInlineString(
      raw.summaryRaw,
      raw.span,
    );
    return createFrozenDetailsBlockNode(
      blockId: raw.blockId,
      span: raw.span,
      summary: _extractPlainText(sumInlines),
      summaryInlines: sumInlines,
      initiallyOpen: raw.initiallyOpen,
      children: _resolveBlockList(raw.children),
    );
  }

  FigureBlockNode _resolveFigureBlock(RawFigureBlock raw) {
    final String? cap = raw.captionRaw;
    final List<MarkdownInlineNode> capInlines = cap == null
        ? emptyFrozenInlineList
        : _parseInlineString(cap, raw.span);
    return createFrozenFigureBlockNode(
      blockId: raw.blockId,
      span: raw.span,
      children: _resolveBlockList(raw.children),
      caption: cap == null ? null : _extractPlainText(capInlines),
      captionInlines: capInlines,
    );
  }

  @pragma('vm:never-inline')
  static String _normalizeCodeSpanSpaces(String raw) {
    if (raw.contains('\n')) {
      raw = raw.replaceAll('\n', ' ');
    }
    if (raw.length >= 2 &&
        raw.codeUnitAt(0) == 0x20 &&
        raw.codeUnitAt(raw.length - 1) == 0x20) {
      for (int k = 0; k < raw.length; k++) {
        if (raw.codeUnitAt(k) != 0x20) {
          return raw.substring(1, raw.length - 1);
        }
      }
    }
    return raw;
  }

  List<MarkdownInlineNode> _parseInlineString(
    String input,
    SourceSpan blockSpan,
  ) {
    if (input.isEmpty) {
      return emptyFrozenInlineList;
    }
    if (_totalTokens >= budgets.maxTokens) {
      return freezeSingleton<MarkdownInlineNode>(
        TextNode(input, span: blockSpan),
      );
    }

    // Zero-alloc plain-text pre-scan: skip _InlineScanner when no structural
    // delimiter/marker exists and detect exact post-processing triggers in 1 pass.
    final int len = input.length;
    final Uint8List lut = structuralLut;
    int firstStructPos = -1;
    int btStart = -1;
    int btEnd = -1;
    List<int>? btSpans;
    bool hasAutolink = false;
    bool hasEmojiColon = false;
    bool hasSmartPunct = false;
    for (int i = 0; i < len; i++) {
      final int cu = input.codeUnitAt(i);
      if (cu < 128) {
        final int cls = lut[cu];
        if (cls == 0) {
          continue;
        }
        if (cls == 1) {
          // Single '=' in prose never forms highlight (`==`); skip false hits.
          if (cu == 0x3D && !(i + 1 < len && input.codeUnitAt(i + 1) == 0x3D)) {
            continue;
          }
          // '&' followed by non-entity starter (e.g. '& ') never decodes.
          if (cu == 0x26) {
            if (i + 2 >= len) {
              continue;
            }
            final int next = input.codeUnitAt(i + 1);
            if (next != 0x23 &&
                !((next >= 0x41 && next <= 0x5A) ||
                    (next >= 0x61 && next <= 0x7A))) {
              continue;
            }
          }
          // Track isolated single-backtick spans inline so prose with code
          // spans avoids _InlineScanner + _InlineItem allocations.
          if (cu == 0x60 && i + 1 < len && input.codeUnitAt(i + 1) != 0x60) {
            final int close = input.indexOf('`', i + 1);
            if (close != -1 &&
                (close + 1 >= len || input.codeUnitAt(close + 1) != 0x60)) {
              if (btStart == -1) {
                btStart = i;
                btEnd = close;
              } else {
                btSpans ??= <int>[btStart, btEnd];
                btSpans.add(i);
                btSpans.add(close);
              }
              i = close;
              continue;
            }
          }
          firstStructPos = btStart != -1 ? btStart : i;
          break;
        }
        if (cu == 0x40) {
          hasAutolink = true;
        } else if (cu == 0x3A) {
          if (i + 2 < len &&
              input.codeUnitAt(i + 1) == 0x2F &&
              input.codeUnitAt(i + 2) == 0x2F) {
            hasAutolink = true;
          } else if (!hasEmojiColon &&
              _hasEmojiShortcodeCandidate(input, i, len)) {
            hasEmojiColon = true;
          }
        } else if (cu == 0x2E) {
          if (!hasAutolink && i >= 3 && _matchesWwwPrefixBeforeDot(input, i)) {
            hasAutolink = true;
          }
          if (!hasSmartPunct &&
              i + 2 < len &&
              input.codeUnitAt(i + 1) == 0x2E &&
              input.codeUnitAt(i + 2) == 0x2E) {
            hasSmartPunct = true;
          }
        } else if (cu == 0x22 || cu == 0x27) {
          hasSmartPunct = true;
        } else if (cu == 0x2D) {
          if (!hasSmartPunct &&
              i + 1 < len &&
              input.codeUnitAt(i + 1) == 0x2D) {
            hasSmartPunct = true;
          }
        }
      }
    }

    if (firstStructPos == -1) {
      final bool runAutolinks = options.gfmAutolinks && hasAutolink;
      final bool runEmoji = options.emoji && hasEmojiColon;
      final bool runSmart = options.smartPunctuation && hasSmartPunct;
      final bool runAbbr = options.abbreviations && abbreviations.isNotEmpty;
      final bool noPost = !runAutolinks && !runEmoji && !runSmart && !runAbbr;
      if (btStart == -1) {
        _totalTokens++;
        final List<MarkdownInlineNode> singleList =
            freezeSingleton<MarkdownInlineNode>(
              TextNode(input, span: blockSpan),
            );
        if (noPost) {
          return singleList;
        }
        return (scanner..reset(input, blockSpan))._finishPostPasses(
          singleList,
          runAutolinks: runAutolinks,
          runEmoji: runEmoji,
          runSmart: runSmart,
          runAbbr: runAbbr,
        );
      }
      if (btSpans != null) {
        final List<MarkdownInlineNode>? multi = _tryBuildMultiBacktickNodes(
          input,
          blockSpan,
          btSpans,
          len,
        );
        if (multi != null) {
          if (noPost) {
            return freezeFreshList(multi);
          }
          return (scanner..reset(input, blockSpan))._finishPostPasses(
            multi,
            runAutolinks: runAutolinks,
            runEmoji: runEmoji,
            runSmart: runSmart,
            runAbbr: runAbbr,
          );
        }
        firstStructPos = btStart;
      } else {
        final int neededTokens =
            1 + (btStart > 0 ? 1 : 0) + (btEnd + 1 < len ? 1 : 0);
        if (_totalTokens + neededTokens <= budgets.maxTokens) {
          _totalTokens += neededTokens;
          String raw = input.substring(btStart + 1, btEnd);
          if (raw.contains('\n') ||
              (raw.length >= 2 &&
                  raw.codeUnitAt(0) == 0x20 &&
                  raw.codeUnitAt(raw.length - 1) == 0x20)) {
            raw = _normalizeCodeSpanSpaces(raw);
          }
          if (btStart == 0 && btEnd + 1 >= len) {
            return freezeSingleton<MarkdownInlineNode>(
              CodeSpanNode(raw, span: blockSpan),
            );
          }
          final int base = blockSpan.startOffset;
          final int sLine = blockSpan.startLine;
          final int eLine = blockSpan.endLine;
          final List<MarkdownInlineNode> nodes = <MarkdownInlineNode>[
            if (btStart > 0)
              TextNode(
                input.substring(0, btStart),
                span: createUncheckedSpan(
                  startOffset: base,
                  endOffset: base + btStart,
                  startLine: sLine,
                  endLine: eLine,
                ),
              ),
            CodeSpanNode(
              raw,
              span: createUncheckedSpan(
                startOffset: base + btStart,
                endOffset: base + btEnd + 1,
                startLine: sLine,
                endLine: eLine,
              ),
            ),
            if (btEnd + 1 < len)
              TextNode(
                input.substring(btEnd + 1),
                span: createUncheckedSpan(
                  startOffset: base + btEnd + 1,
                  endOffset: base + len,
                  startLine: sLine,
                  endLine: eLine,
                ),
              ),
          ];
          if (noPost) {
            return freezeFreshList(nodes);
          }
          return (scanner..reset(input, blockSpan))._finishPostPasses(
            nodes,
            runAutolinks: runAutolinks,
            runEmoji: runEmoji,
            runSmart: runSmart,
            runAbbr: runAbbr,
          );
        }
        firstStructPos = btStart;
      }
    }

    final _InlineScanner sc = scanner..reset(input, blockSpan);
    return sc.parse(
      firstStructPos: firstStructPos,
      sawAutolinkCandidate: hasAutolink,
      sawEmojiColon: hasEmojiColon,
      sawSmartPunct: hasSmartPunct,
    );
  }

  List<MarkdownInlineNode>? _tryBuildMultiBacktickNodes(
    String input,
    SourceSpan blockSpan,
    List<int> btSpans,
    int len,
  ) {
    final int pairCount = btSpans.length;
    int neededTokens = pairCount >> 1;
    int cursor = 0;
    for (int k = 0; k < pairCount; k += 2) {
      if (btSpans[k] > cursor) {
        neededTokens++;
      }
      cursor = btSpans[k + 1] + 1;
    }
    if (cursor < len) {
      neededTokens++;
    }
    if (_totalTokens + neededTokens > budgets.maxTokens) {
      return null;
    }
    _totalTokens += neededTokens;
    final int base = blockSpan.startOffset;
    final int sLine = blockSpan.startLine;
    final int eLine = blockSpan.endLine;
    final List<MarkdownInlineNode> nodes = <MarkdownInlineNode>[];
    cursor = 0;
    for (int k = 0; k < pairCount; k += 2) {
      final int s = btSpans[k];
      final int e = btSpans[k + 1];
      if (s > cursor) {
        nodes.add(
          TextNode(
            input.substring(cursor, s),
            span: createUncheckedSpan(
              startOffset: base + cursor,
              endOffset: base + s,
              startLine: sLine,
              endLine: eLine,
            ),
          ),
        );
      }
      String raw = input.substring(s + 1, e);
      if (raw.contains('\n') ||
          (raw.length >= 2 &&
              raw.codeUnitAt(0) == 0x20 &&
              raw.codeUnitAt(raw.length - 1) == 0x20)) {
        raw = _normalizeCodeSpanSpaces(raw);
      }
      nodes.add(
        CodeSpanNode(
          raw,
          span: createUncheckedSpan(
            startOffset: base + s,
            endOffset: base + e + 1,
            startLine: sLine,
            endLine: eLine,
          ),
        ),
      );
      cursor = e + 1;
    }
    if (cursor < len) {
      nodes.add(
        TextNode(
          input.substring(cursor),
          span: createUncheckedSpan(
            startOffset: base + cursor,
            endOffset: base + len,
            startLine: sLine,
            endLine: eLine,
          ),
        ),
      );
    }
    return nodes;
  }

  FootnoteRefNode? _registerFootnoteRef(String label, SourceSpan span) {
    if (!rawFootnotes.containsKey(label)) {
      return null;
    }
    final List<String> citedOrder = _citedFootnoteOrder ??= <String>[];
    final Map<String, int> indexByLabel = _footnoteIndexByLabel ??=
        <String, int>{};
    final Map<String, int> refCountByLabel = _footnoteRefCountByLabel ??=
        <String, int>{};
    int? index = indexByLabel[label];
    if (index == null) {
      citedOrder.add(label);
      index = citedOrder.length;
      indexByLabel[label] = index;
    }
    final int occurrence = (refCountByLabel[label] ?? 0) + 1;
    refCountByLabel[label] = occurrence;
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

  LinkNode _makeLinkNode({
    required String rawDestination,
    String? title,
    required List<MarkdownInlineNode> children,
    required bool isAutolink,
    required SourceSpan span,
  }) {
    if (!options.sanitizeUrls || options.urlPolicy.isAllowed(rawDestination)) {
      return createFrozenLinkNode(
        destination: rawDestination,
        title: title,
        children: children,
        isAutolink: isAutolink,
        span: span,
      );
    }
    if (rawDestination.trim().isNotEmpty) {
      return createBlockedLinkNode(
        title: title,
        children: children,
        isAutolink: isAutolink,
        span: span,
        frozen: true,
      );
    }
    return createFrozenLinkNode(
      destination: '',
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
    if (!options.sanitizeUrls || options.urlPolicy.isAllowed(rawDestination)) {
      return createFrozenImageNode(
        destination: rawDestination,
        alt: alt,
        title: title,
        width: width,
        height: height,
        children: children,
        span: span,
      );
    }
    if (rawDestination.trim().isNotEmpty) {
      return createBlockedImageNode(
        alt: alt,
        title: title,
        width: width,
        height: height,
        children: children,
        span: span,
        frozen: true,
      );
    }
    return createFrozenImageNode(
      destination: '',
      alt: alt,
      title: title,
      width: width,
      height: height,
      children: children,
      span: span,
    );
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
  _InlineItem.node(MarkdownInlineNode node, {this.inlineDepth = 0})
    : _node = node,
      itemSpan = node.span,
      isText = node is TextNode;

  _InlineItem.delim({
    required this.delimChar,
    required this.delimCount,
    required this.origCount,
    required this.canOpen,
    required this.canClose,
    required SourceSpan span,
  }) : _node = null,
       itemSpan = span,
       isText = true;

  MarkdownInlineNode? _node;
  final SourceSpan itemSpan;
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

  List<int>? _bracketIndices;
  Set<int>? _unmatchedBacktickLengths;
  Int32List? _openersBottom;
  String _parsedLinkDest = '';
  String _parsedLinkTitle = '';
  bool _hasParsedLinkTitle = false;
  String _parsedBracketLabel = '';

  int? _cachedLastGtPos;
  int _noClosingSingleQuoteFrom = 0;
  int _noClosingDoubleQuoteFrom = 0;
  Set<int>? _failedAttrBoundaries;
  bool _noCommentClose = false;
  bool _noPiClose = false;
  bool _noCdataClose = false;
  bool _noValidClosingDollar = false;
  bool _noClosingParenMath = false;
  bool _hasUnmatchedBackticks = false;
  bool _sawClosingDelim = false;
  bool _sawAutolinkCandidate = false;
  bool _sawEmojiColon = false;
  bool _sawSmartPunct = false;
  int _lastCollectedMaxDepth = 0;

  MarkdownOptions get options => resolver.options;
  MarkdownBudgets get budgets => resolver.budgets;

  void reset(String nextInput, SourceSpan nextSpan) {
    input = nextInput;
    blockSpan = nextSpan;
    if (_items.length > 1024) {
      _items.length = 0;
    } else if (_items.isNotEmpty) {
      _items.clear();
    }
    if (_delimiterIndices.isNotEmpty) {
      _delimiterIndices.clear();
      _prevDelim.clear();
      _nextDelim.clear();
    }
    _delimHead = -1;
    _delimTail = -1;
    _activeHead = -1;
    _activeTail = -1;
    _bracketIndices?.clear();
    if (_hasUnmatchedBackticks) {
      _unmatchedBacktickLengths?.clear();
      _hasUnmatchedBackticks = false;
    }
    _cachedLastGtPos = null;
    final int guardPos = nextInput.length + 1;
    _noClosingSingleQuoteFrom = guardPos;
    _noClosingDoubleQuoteFrom = guardPos;
    _failedAttrBoundaries = null;
    _noCommentClose = false;
    _noPiClose = false;
    _noCdataClose = false;
    _noValidClosingDollar = false;
    _noClosingParenMath = false;
    _sawClosingDelim = false;
    _sawAutolinkCandidate = false;
    _sawEmojiColon = false;
    _sawSmartPunct = false;
    _lastCollectedMaxDepth = 0;
  }

  int get _lastGtPos => _cachedLastGtPos ??= input.lastIndexOf('>');

  SourceSpan _span(int start, int end) {
    final int base = blockSpan.startOffset;
    return createUncheckedSpan(
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

  List<MarkdownInlineNode> parse({
    int firstStructPos = 0,
    bool sawAutolinkCandidate = false,
    bool sawEmojiColon = false,
    bool sawSmartPunct = false,
  }) {
    final int len = input.length;
    final Uint8List lut = resolver.structuralLut;
    int pos = 0;
    if (firstStructPos > 0) {
      resolver._totalTokens++;
      if (resolver._totalTokens > budgets.maxTokens) {
        _appendText(input, blockSpan);
        return _collectActiveSliceCoalesced(
          _activeHead,
          -1,
          freezeResult: true,
        );
      }
      _sawAutolinkCandidate = sawAutolinkCandidate;
      _sawEmojiColon = sawEmojiColon;
      _sawSmartPunct = sawSmartPunct;
      _appendText(input.substring(0, firstStructPos), _span(0, firstStructPos));
      pos = firstStructPos;
    }

    while (pos < len) {
      resolver._totalTokens++;
      if (resolver._totalTokens > budgets.maxTokens) {
        _appendText(input.substring(pos), _span(pos, len));
        break;
      }

      final int cu = input.codeUnitAt(pos);
      if (cu >= 128 || lut[cu] != 1) {
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
          pos = _tryHandleBang(pos, len);
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

    if (_delimHead != -1 && _sawClosingDelim) {
      _processEmphasis(
        bottomDelimPos: -1,
        firstCandidateDelimPos: _delimHead,
        maxAllowedDepth: budgets.maxNestingDepth,
      );
    }

    final bool runAutolinks = options.gfmAutolinks && _sawAutolinkCandidate;
    final bool runEmoji = options.emoji && _sawEmojiColon;
    final bool runSmart = options.smartPunctuation && _sawSmartPunct;
    final bool runAbbr =
        options.abbreviations && resolver.abbreviations.isNotEmpty;
    if (!runAutolinks && !runEmoji && !runSmart && !runAbbr) {
      return _collectActiveSliceCoalesced(_activeHead, -1, freezeResult: true);
    }

    return _finishPostPasses(
      _collectActiveSliceCoalesced(_activeHead, -1, freezeResult: false),
      runAutolinks: runAutolinks,
      runEmoji: runEmoji,
      runSmart: runSmart,
      runAbbr: runAbbr,
    );
  }

  @pragma('vm:never-inline')
  int _tryHandleBang(int pos, int len) {
    if (pos + 1 < len && input.codeUnitAt(pos + 1) == 0x5B) {
      if (options.footnotes &&
          resolver.rawFootnotes.isNotEmpty &&
          pos + 3 < len &&
          input.codeUnitAt(pos + 2) == 0x5E) {
        final int closeFn = _findFootnoteClose(pos + 3);
        if (closeFn != -1 &&
            resolver.rawFootnotes.containsKey(
              input.substring(pos + 3, closeFn),
            )) {
          _appendText('!', _span(pos, pos + 1));
          return pos + 1;
        }
      }
      return _handleOpenBracket(pos, isImage: true);
    }
    _appendText('!', _span(pos, pos + 1));
    return pos + 1;
  }

  @pragma('vm:never-inline')
  List<MarkdownInlineNode> _finishPostPasses(
    List<MarkdownInlineNode> nodes, {
    required bool runAutolinks,
    required bool runEmoji,
    required bool runSmart,
    required bool runAbbr,
  }) {
    if (runAutolinks) {
      nodes = _applyGfmAutolinks(nodes);
    }
    if (runEmoji) {
      nodes = _applyEmojiShortcodes(nodes);
    }
    if (runSmart) {
      nodes = _applySmartPunctuation(nodes);
    }
    if (runAbbr) {
      nodes = _applyAbbreviations(nodes);
    }
    return freezeFreshList(_coalesceTextNodes(nodes));
  }

  int _scanPlainText(int start) {
    final int len = input.length;
    final Uint8List lut = resolver.structuralLut;
    int i = start;
    while (i < len) {
      final int cu = input.codeUnitAt(i);
      if (cu < 128) {
        final int cls = lut[cu];
        if (cls == 0) {
          i++;
          continue;
        }
        if (cls == 1) {
          if (cu == 0x3D && !(i + 1 < len && input.codeUnitAt(i + 1) == 0x3D)) {
            i++;
            continue;
          }
          if (cu == 0x26) {
            if (i + 2 >= len) {
              i++;
              continue;
            }
            final int next = input.codeUnitAt(i + 1);
            if (next != 0x23 &&
                !((next >= 0x41 && next <= 0x5A) ||
                    (next >= 0x61 && next <= 0x7A))) {
              i++;
              continue;
            }
          }
          if (i > start) {
            break;
          }
        } else {
          if (cu == 0x40) {
            _sawAutolinkCandidate = true;
          } else if (cu == 0x3A) {
            if (i + 2 < len &&
                input.codeUnitAt(i + 1) == 0x2F &&
                input.codeUnitAt(i + 2) == 0x2F) {
              _sawAutolinkCandidate = true;
            } else if (!_sawEmojiColon &&
                _hasEmojiShortcodeCandidate(input, i, len)) {
              _sawEmojiColon = true;
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
      i++;
    }
    _appendText(input.substring(start, i), _span(start, i));
    return i;
  }

  void _appendText(String text, SourceSpan span) {
    if (text.isEmpty) {
      return;
    }
    _appendActiveItem(_InlineItem.node(TextNode(text, span: span)));
  }

  int _handleNewline(int pos) {
    int trailingSpaces = 0;
    int cur = _activeTail;
    while (cur != -1) {
      final _InlineItem item = _items[cur];
      if (!item.isText || item.isDelimiter || item.isBracket) {
        break;
      }
      final MarkdownInlineNode? rawNode = item._node;
      if (rawNode is! TextNode) {
        break;
      }
      final String text = rawNode.text;
      int k = text.length - 1;
      while (k >= 0 && text.codeUnitAt(k) == 0x20) {
        trailingSpaces++;
        k--;
      }
      if (k >= 0) {
        if (k + 1 < text.length) {
          item._node = TextNode(text.substring(0, k + 1), span: item.itemSpan);
        }
        break;
      }
      _popActiveTail();
      cur = _activeTail;
    }
    _appendActiveItem(
      _InlineItem.node(
        trailingSpaces >= 2
            ? HardBreakNode(span: _span(pos, pos + 1))
            : SoftBreakNode(span: _span(pos, pos + 1)),
      ),
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
    if (options.math && next == 0x28 && !_noClosingParenMath) {
      final int? end = _tryHandleParenInlineMath(pos);
      if (end != null) {
        return end;
      }
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
    final int len = input.length;
    while (i < len && input.codeUnitAt(i) == 0x60) {
      count++;
      i++;
    }
    if (_hasUnmatchedBackticks && _unmatchedBacktickLengths!.contains(count)) {
      _appendText(input.substring(pos, i), _span(pos, i));
      return i;
    }
    if (count == 1) {
      final int closeStart = input.indexOf('`', i);
      if (closeStart == -1) {
        _hasUnmatchedBackticks = true;
        (_unmatchedBacktickLengths ??= <int>{}).add(1);
        _appendText('`', _span(pos, i));
        return i;
      }
      if (closeStart + 1 >= len || input.codeUnitAt(closeStart + 1) != 0x60) {
        String raw = input.substring(i, closeStart);
        if (raw.contains('\n') ||
            (raw.length >= 2 &&
                raw.codeUnitAt(0) == 0x20 &&
                raw.codeUnitAt(raw.length - 1) == 0x20)) {
          raw = _InlineResolver._normalizeCodeSpanSpaces(raw);
        }
        _appendActiveItem(
          _InlineItem.node(CodeSpanNode(raw, span: _span(pos, closeStart + 1))),
        );
        return closeStart + 1;
      }
    }
    return _handleMultiBackticks(pos, i, count);
  }

  @pragma('vm:never-inline')
  int _handleMultiBackticks(int pos, int i, int count) {
    final int len = input.length;
    int search = i;
    bool sawNewline = false;
    while (search < len) {
      final int sc = input.codeUnitAt(search);
      if (sc == 0x0A) {
        sawNewline = true;
        search++;
      } else if (sc == 0x60) {
        int closeCount = 0;
        final int closeStart = search;
        while (search < len && input.codeUnitAt(search) == 0x60) {
          closeCount++;
          search++;
        }
        if (closeCount == count) {
          String raw = input.substring(i, closeStart);
          if (sawNewline ||
              (raw.length >= 2 &&
                  raw.codeUnitAt(0) == 0x20 &&
                  raw.codeUnitAt(raw.length - 1) == 0x20)) {
            raw = _InlineResolver._normalizeCodeSpanSpaces(raw);
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
    _hasUnmatchedBackticks = true;
    (_unmatchedBacktickLengths ??= <int>{}).add(count);
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

  int? _tryHandleParenInlineMath(int pos) {
    int i = pos + 2;
    final int len = input.length;
    while (i < len) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x5C && i + 1 < len) {
        final int after = input.codeUnitAt(i + 1);
        if (after == 0x29) {
          final String latex = input.substring(pos + 2, i).trim();
          if (latex.isEmpty) {
            return null;
          }
          _appendActiveItem(
            _InlineItem.node(MathInlineNode(latex, span: _span(pos, i + 2))),
          );
          return i + 2;
        }
        if (after == 0x28) {
          return null;
        }
        i += 2;
        continue;
      }
      i++;
    }
    _noClosingParenMath = true;
    return null;
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
            children: freezeSingleton<MarkdownInlineNode>(
              TextNode(auto.label, span: _span(pos + 1, auto.nextIndex - 1)),
            ),
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
      final int tagHint = rawHtml.length > 2
          ? (rawHtml.codeUnitAt(1) | 0x20)
          : 0;
      if (tagHint == 0x62 && options.inlineBreaks && _isBrTag(rawHtml)) {
        _appendActiveItem(
          _InlineItem.node(InlineBreakNode(span: _span(pos, htmlEnd))),
        );
        return htmlEnd;
      }
      if (tagHint == 0x61 &&
          (options.explicitHeadingIds || options.headingSlugs) &&
          rawHtml.length >= 4 &&
          rawHtml.codeUnitAt(2) <= 0x20) {
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
      if (tagHint == 0x70 &&
          options.figureBlocks &&
          _matchesCaseInsensitiveAt(rawHtml, 0, '<picture')) {
        final int closePic = _indexOfAsciiIgnoreCase(input, '</picture>', pos);
        if (closePic != -1) {
          final String fullPic = input.substring(pos, closePic + 10);
          final PictureInlineNode? picNode = _tryParsePicture(
            fullPic,
            _span(pos, closePic + 10),
          );
          if (picNode != null) {
            _appendActiveItem(_InlineItem.node(picNode));
            return closePic + 10;
          }
        }
      }
      if (tagHint == 0x69 &&
          (options.figureBlocks || options.kbd || options.headingSlugs) &&
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
      if (tagHint == 0x6B &&
          options.kbd &&
          _equalsAsciiIgnoreCase(rawHtml, '<kbd>')) {
        final int closeKbd = _indexOfAsciiIgnoreCase(input, '</kbd>', htmlEnd);
        if (closeKbd != -1) {
          final String inner = input.substring(htmlEnd, closeKbd);
          _appendActiveItem(
            _InlineItem.node(
              createFrozenKbdInlineNode(
                children: freezeSingleton<MarkdownInlineNode>(
                  TextNode(inner, span: _span(htmlEnd, closeKbd)),
                ),
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
          ? emptyFrozenInlineList
          : freezeSingleton<MarkdownInlineNode>(TextNode(alt, span: span)),
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
        resolver.rawFootnotes.isNotEmpty &&
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
    final List<int> brackets = _bracketIndices ??= <int>[];
    if (brackets.length >= budgets.maxNestingDepth) {
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
    brackets.add(idx);
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
    final List<int>? brackets = _bracketIndices;
    if (brackets == null || brackets.isEmpty) {
      _appendText(']', _span(pos, pos + 1));
      return pos + 1;
    }

    final int openerItemIdx = brackets.removeLast();
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
      final int inlineNext = _parseInlineLinkTarget(afterBracket);
      if (inlineNext != -1) {
        destination = _parsedLinkDest;
        title = _hasParsedLinkTitle ? _parsedLinkTitle : null;
        afterBracket = inlineNext;
        matched = true;
      }
    }

    // Case 2: Reference link/image (`[foo][bar]`, `[foo][]`, or `[foo]`).
    if (!matched && resolver.linkDefinitions.isNotEmpty) {
      String? refLabel;
      int nextAfterRef = afterBracket;

      if (afterBracket < input.length &&
          input.codeUnitAt(afterBracket) == 0x5B) {
        final int explicitNext = _parseBracketLabel(afterBracket);
        if (explicitNext != -1) {
          final String explicitLabel = _parsedBracketLabel;
          if (explicitLabel.isEmpty) {
            // Collapsed reference `[foo][]`.
            refLabel = input.substring(
              opener.bracketSourcePos + (isImage ? 2 : 1),
              pos,
            );
          } else {
            // Full reference `[foo][bar]`.
            refLabel = explicitLabel;
          }
          nextAfterRef = explicitNext;
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

    final int maxAllowedInside = budgets.maxNestingDepth - brackets.length - 1;

    // Process emphasis strictly inside `[openerItemIdx + 1 ..]` in O(active).
    final int firstInsideDelim = opener.savedDelimTail == -1
        ? _delimHead
        : _nextDelim[opener.savedDelimTail];
    if (firstInsideDelim != -1 && _sawClosingDelim) {
      _processEmphasis(
        bottomDelimPos: opener.savedDelimTail,
        firstCandidateDelimPos: firstInsideDelim,
        maxAllowedDepth: maxAllowedInside < 0 ? 0 : maxAllowedInside,
      );
    }

    // Collect active nodes strictly after `opener` and measure depth.
    final List<MarkdownInlineNode> children = _collectActiveSliceCoalesced(
      opener.nextActive,
      -1,
      freezeResult: true,
    );
    final int maxChildDepth = _lastCollectedMaxDepth;

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
      for (int i = 0; i < brackets.length; i++) {
        final int bIdx = brackets[i];
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

  int _parseInlineLinkTarget(int openParenPos) {
    final int len = input.length;
    int i = openParenPos + 1;
    while (i < len && isAsciiWhitespace(input.codeUnitAt(i))) {
      i++;
    }
    if (i >= len) {
      return -1;
    }

    String dest;
    final int firstCu = input.codeUnitAt(i);
    if (firstCu == 0x29) {
      _parsedLinkDest = '';
      _parsedLinkTitle = '';
      _hasParsedLinkTitle = false;
      return i + 1;
    }

    if (firstCu == 0x3C) {
      i = _parseAngleBracketDestination(i);
      if (i == -1) {
        return -1;
      }
      dest = _parsedLinkDest;
    } else {
      final int dStart = i;
      int parenDepth = 0;
      bool needsUnescape = false;
      while (i < len) {
        final int cu = input.codeUnitAt(i);
        if (isAsciiControl(cu) || cu == 0x20) {
          break;
        }
        if (cu == 0x5C &&
            i + 1 < len &&
            isAsciiPunctuation(input.codeUnitAt(i + 1))) {
          needsUnescape = true;
          i += 2;
          continue;
        }
        if (cu == 0x26) {
          needsUnescape = true;
        }
        if (cu == 0x28) {
          parenDepth++;
          if (parenDepth > 32) {
            return -1;
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
        return -1;
      }
      final String slice = input.substring(dStart, i);
      dest = needsUnescape ? unescapeMarkdownString(slice) : slice;
    }

    int wsCount = 0;
    while (i < len && isAsciiWhitespace(input.codeUnitAt(i))) {
      wsCount++;
      i++;
    }
    if (i >= len) {
      return -1;
    }
    final int nextCu = input.codeUnitAt(i);
    if (wsCount > 0 && (nextCu == 0x22 || nextCu == 0x27 || nextCu == 0x28)) {
      return _parseLinkTitleAndCloseParen(i, dest);
    }
    if (nextCu != 0x29) {
      return -1;
    }
    _parsedLinkDest = dest;
    _parsedLinkTitle = '';
    _hasParsedLinkTitle = false;
    return i + 1;
  }

  @pragma('vm:never-inline')
  int _parseAngleBracketDestination(int openAnglePos) {
    final int len = input.length;
    int i = openAnglePos + 1;
    final int dStart = i;
    bool needsUnescape = false;
    while (i < len) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x0A || cu == 0x3C) {
        return -1;
      }
      if (cu == 0x5C &&
          i + 1 < len &&
          isAsciiPunctuation(input.codeUnitAt(i + 1))) {
        needsUnescape = true;
        i += 2;
        continue;
      }
      if (cu == 0x26) {
        needsUnescape = true;
      }
      if (cu == 0x3E) {
        final String slice = input.substring(dStart, i);
        _parsedLinkDest = needsUnescape ? unescapeMarkdownString(slice) : slice;
        return i + 1;
      }
      i++;
    }
    return -1;
  }

  @pragma('vm:never-inline')
  int _parseLinkTitleAndCloseParen(int openQuotePos, String dest) {
    final int len = input.length;
    final int openCu = input.codeUnitAt(openQuotePos);
    final int closeChar = openCu == 0x28 ? 0x29 : openCu;
    int i = openQuotePos + 1;
    final int tStart = i;
    bool closedTitle = false;
    bool needsUnescapeTitle = false;
    String title = '';
    while (i < len) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x5C &&
          i + 1 < len &&
          isAsciiPunctuation(input.codeUnitAt(i + 1))) {
        needsUnescapeTitle = true;
        i += 2;
        continue;
      }
      if (cu == 0x26) {
        needsUnescapeTitle = true;
      }
      if (cu == closeChar) {
        final String rawTitle = input.substring(tStart, i);
        title = needsUnescapeTitle
            ? unescapeMarkdownString(rawTitle)
            : rawTitle;
        i++;
        closedTitle = true;
        break;
      }
      if (openCu == 0x28 && cu == 0x28) {
        return -1;
      }
      i++;
    }
    if (!closedTitle) {
      return -1;
    }
    while (i < len && isAsciiWhitespace(input.codeUnitAt(i))) {
      i++;
    }
    if (i >= len || input.codeUnitAt(i) != 0x29) {
      return -1;
    }
    _parsedLinkDest = dest;
    _parsedLinkTitle = title;
    _hasParsedLinkTitle = true;
    return i + 1;
  }

  int _parseBracketLabel(int openPos) {
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
          return -1;
        }
        continue;
      }
      if (cu == 0x5B) {
        return -1;
      }
      if (cu == 0x5D) {
        _parsedBracketLabel = input.substring(openPos + 1, i);
        return i + 1;
      }
      chars++;
      if (chars > 999) {
        return -1;
      }
      i++;
    }
    return -1;
  }

  int _handleDelimiterRun(int pos, int delimCu) {
    final int len = input.length;
    int end = pos + 1;
    while (end < len && input.codeUnitAt(end) == delimCu) {
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

    final bool beforeWs;
    final bool beforePunct;
    if (pos == 0) {
      beforeWs = true;
      beforePunct = false;
    } else {
      final int bcu = input.codeUnitAt(pos - 1);
      if (bcu < 128) {
        final int cls = _asciiFlankLut[bcu];
        beforeWs = cls == 1;
        beforePunct = cls == 2;
      } else {
        final int beforeCp = (bcu >= 0xDC00 && bcu <= 0xDFFF)
            ? codePointBefore(input, pos)
            : bcu;
        beforeWs = isUnicodeWhitespace(beforeCp);
        beforePunct = !beforeWs && isUnicodePunctuation(beforeCp);
      }
    }

    final bool afterWs;
    final bool afterPunct;
    if (end >= len) {
      afterWs = true;
      afterPunct = false;
    } else {
      final int acu = input.codeUnitAt(end);
      if (acu < 128) {
        final int cls = _asciiFlankLut[acu];
        afterWs = cls == 1;
        afterPunct = cls == 2;
      } else {
        final int afterCp = (acu >= 0xD800 && acu <= 0xDBFF)
            ? codePointAt(input, end)
            : acu;
        afterWs = isUnicodeWhitespace(afterCp);
        afterPunct = !afterWs && isUnicodePunctuation(afterCp);
      }
    }

    final bool leftFlanking =
        !afterWs && (!afterPunct || beforeWs || beforePunct);
    final bool rightFlanking =
        !beforeWs && (!beforePunct || afterWs || afterPunct);

    final bool canOpen;
    final bool canClose;

    if (delimCu == 0x5F) {
      canOpen = leftFlanking && (!rightFlanking || beforePunct);
      canClose = rightFlanking && (!leftFlanking || afterPunct);
    } else {
      canOpen = leftFlanking;
      canClose = rightFlanking;
    }
    if (canClose) {
      _sawClosingDelim = true;
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
    final int secondCandidate = _nextDelim[firstCandidateDelimPos];
    if (secondCandidate == -1) {
      return;
    }
    final Int32List openersBottom = _openersBottom ??= Int32List(30);
    bool openersBottomInitialized = false;
    int depthFloorDelimPos = bottomDelimPos;

    int currentPos = secondCandidate;
    while (currentPos != -1) {
      final int closerItemIdx = _delimiterIndices[currentPos];
      final _InlineItem closer = _items[closerItemIdx];
      if (!closer.isDelimiter || !closer.canClose || closer.delimCount == 0) {
        currentPos = _nextDelim[currentPos];
        continue;
      }

      int key = 0;
      int bottomLimit = depthFloorDelimPos;
      if (openersBottomInitialized) {
        final int delimSlot = switch (closer.delimChar) {
          0x2A => 0,
          0x5F => 1,
          0x7E => 2,
          0x3D => 3,
          _ => 4,
        };
        key =
            delimSlot * 6 +
            (closer.origCount % 3) * 2 +
            (closer.canOpen ? 1 : 0);
        final int ob = openersBottom[key];
        if (ob > bottomLimit) {
          bottomLimit = ob;
        }
      } else if (bottomDelimPos > bottomLimit) {
        bottomLimit = bottomDelimPos;
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
        if (!openersBottomInitialized) {
          openersBottom.fillRange(0, 30, bottomDelimPos);
          openersBottomInitialized = true;
          final int delimSlot = switch (closer.delimChar) {
            0x2A => 0,
            0x5F => 1,
            0x7E => 2,
            0x3D => 3,
            _ => 4,
          };
          key =
              delimSlot * 6 +
              (closer.origCount % 3) * 2 +
              (closer.canOpen ? 1 : 0);
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
        if (!openersBottomInitialized) {
          openersBottom.fillRange(0, 30, bottomDelimPos);
          openersBottomInitialized = true;
          final int delimSlot = switch (closer.delimChar) {
            0x2A => 0,
            0x5F => 1,
            0x7E => 2,
            0x3D => 3,
            _ => 4,
          };
          key =
              delimSlot * 6 +
              (closer.origCount % 3) * 2 +
              (closer.canOpen ? 1 : 0);
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

      // Drop all interior delimiters strictly between foundOpenerPos and
      // currentPos in O(1) via doubly-linked delimiter chain.
      _nextDelim[foundOpenerPos] = currentPos;
      _prevDelim[currentPos] = foundOpenerPos;

      // Collect interior active nodes between openerItemIdx and closerItemIdx.
      final List<MarkdownInlineNode> children = _collectActiveSliceCoalesced(
        opener.nextActive,
        closerItemIdx,
        freezeResult: true,
      );

      final SourceSpan emSpan = createUncheckedSpan(
        startOffset: opener.itemSpan.startOffset,
        endOffset: closer.itemSpan.endOffset,
        startLine: opener.itemSpan.startLine,
        endLine: closer.itemSpan.endLine,
      );

      final MarkdownInlineNode wrapped;
      if (opener.delimChar == 0x7E) {
        if (options.subscript && useCount == 1) {
          wrapped = createFrozenSubscriptNode(children: children, span: emSpan);
        } else {
          wrapped = createFrozenStrikethroughNode(
            children: children,
            span: emSpan,
          );
        }
      } else if (opener.delimChar == 0x3D) {
        wrapped = createFrozenHighlightNode(children: children, span: emSpan);
      } else if (opener.delimChar == 0x5E) {
        wrapped = createFrozenSuperscriptNode(children: children, span: emSpan);
      } else if (useCount == 2) {
        wrapped = createFrozenStrongNode(
          children: children,
          delimiter: _repeatDelimChar(opener.delimChar, 2),
          span: emSpan,
        );
      } else {
        wrapped = createFrozenEmphasisNode(
          children: children,
          delimiter: _repeatDelimChar(opener.delimChar, 1),
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

  List<MarkdownInlineNode> _collectActiveSliceCoalesced(
    int startIdx,
    int stopIdx, {
    required bool freezeResult,
  }) {
    int maxDepth = 0;
    TextNode? pending;
    StringBuffer? buf;
    SourceSpan? pendingSpan;
    List<MarkdownInlineNode>? out;

    int cur = startIdx;
    while (cur != -1 && cur != stopIdx) {
      final _InlineItem item = _items[cur];
      if (item.inlineDepth > maxDepth) {
        maxDepth = item.inlineDepth;
      }
      String? addText;
      SourceSpan? addSpan;
      TextNode? addTextNode;
      MarkdownInlineNode? nonTextNode;
      final MarkdownInlineNode? node = item._node;
      if (node == null) {
        final int dCount = item.delimCount;
        if (dCount > 0) {
          addText = _repeatDelimChar(item.delimChar, dCount);
          addSpan = item.itemSpan;
        }
      } else if (node is TextNode) {
        if (node.text.isNotEmpty) {
          addTextNode = node;
          addText = node.text;
          addSpan = node.span;
        }
      } else {
        nonTextNode = node;
      }
      if (addText != null) {
        final SourceSpan span = addSpan!;
        if (buf != null) {
          buf.write(addText);
          final SourceSpan prev = pendingSpan!;
          pendingSpan = createUncheckedSpan(
            startOffset: prev.startOffset,
            endOffset: span.endOffset,
            startLine: prev.startLine,
            endLine: span.endLine,
          );
        } else if (pending != null) {
          buf = StringBuffer(pending.text)..write(addText);
          final SourceSpan prev = pendingSpan!;
          pendingSpan = createUncheckedSpan(
            startOffset: prev.startOffset,
            endOffset: span.endOffset,
            startLine: prev.startLine,
            endLine: span.endLine,
          );
          pending = null;
        } else {
          pending = addTextNode ?? TextNode(addText, span: span);
          pendingSpan = span;
        }
      } else if (nonTextNode != null) {
        if (buf != null) {
          out ??= <MarkdownInlineNode>[];
          out.add(TextNode(buf.toString(), span: pendingSpan!));
          buf = null;
          pending = null;
          pendingSpan = null;
        } else if (pending != null) {
          out ??= <MarkdownInlineNode>[];
          out.add(pending);
          pending = null;
          pendingSpan = null;
        }
        out ??= <MarkdownInlineNode>[];
        out.add(nonTextNode);
      }
      cur = item.nextActive;
    }

    _lastCollectedMaxDepth = maxDepth;

    if (out == null) {
      final TextNode? only = buf != null
          ? TextNode(buf.toString(), span: pendingSpan!)
          : pending;
      if (only == null) {
        return emptyFrozenInlineList;
      }
      return freezeResult
          ? freezeSingleton<MarkdownInlineNode>(only)
          : <MarkdownInlineNode>[only];
    }

    if (buf != null) {
      out.add(TextNode(buf.toString(), span: pendingSpan!));
    } else if (pending != null) {
      out.add(pending);
    }
    if (!freezeResult) {
      return out;
    }
    if (out.length == 1) {
      return freezeSingleton<MarkdownInlineNode>(out[0]);
    }
    return freezeFreshList<MarkdownInlineNode>(out);
  }

  // ===========================================================================
  // GFM Extended Autolinks Post-Processor (cmark-gfm 0.29.0.gfm.13)
  // ===========================================================================

  List<MarkdownInlineNode> _applyGfmAutolinks(List<MarkdownInlineNode> nodes) {
    List<MarkdownInlineNode>? out;
    final int len = nodes.length;
    for (int idx = 0; idx < len; idx++) {
      final MarkdownInlineNode node = nodes[idx];
      if (node is TextNode) {
        final List<MarkdownInlineNode>? autolinked = _autolinkTextNodeOrNull(
          node,
        );
        if (autolinked != null) {
          out ??= nodes.sublist(0, idx);
          out.addAll(autolinked);
          continue;
        }
      } else if (node is EmphasisNode) {
        final List<MarkdownInlineNode> mapped = _applyGfmAutolinks(
          node.children,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, idx);
          out.add(
            createFrozenEmphasisNode(
              children: freezeFreshList(mapped),
              delimiter: node.delimiter,
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is StrongNode) {
        final List<MarkdownInlineNode> mapped = _applyGfmAutolinks(
          node.children,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, idx);
          out.add(
            createFrozenStrongNode(
              children: freezeFreshList(mapped),
              delimiter: node.delimiter,
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is StrikethroughNode) {
        final List<MarkdownInlineNode> mapped = _applyGfmAutolinks(
          node.children,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, idx);
          out.add(
            createFrozenStrikethroughNode(
              children: freezeFreshList(mapped),
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is HighlightNode) {
        final List<MarkdownInlineNode> mapped = _applyGfmAutolinks(
          node.children,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, idx);
          out.add(
            createFrozenHighlightNode(
              children: freezeFreshList(mapped),
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is SubscriptNode) {
        final List<MarkdownInlineNode> mapped = _applyGfmAutolinks(
          node.children,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, idx);
          out.add(
            createFrozenSubscriptNode(
              children: freezeFreshList(mapped),
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is SuperscriptNode) {
        final List<MarkdownInlineNode> mapped = _applyGfmAutolinks(
          node.children,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, idx);
          out.add(
            createFrozenSuperscriptNode(
              children: freezeFreshList(mapped),
              span: node.span,
            ),
          );
          continue;
        }
      }
      out?.add(node);
    }
    return out ?? nodes;
  }

  List<MarkdownInlineNode>? _autolinkTextNodeOrNull(TextNode node) {
    final String text = node.text;
    final int len = text.length;
    List<MarkdownInlineNode>? out;
    int lastEmit = 0;
    int i = 0;

    while (i < len) {
      final int cu = text.codeUnitAt(i);
      // 1. Check `www.`
      if ((cu == 0x77 || cu == 0x57) &&
          i + 3 < len &&
          text.codeUnitAt(i + 3) == 0x2E &&
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
          out ??= <MarkdownInlineNode>[];
          if (i > lastEmit) {
            out.add(TextNode(text.substring(lastEmit, i), span: node.span));
          }
          out.add(
            resolver._makeLinkNode(
              rawDestination: match.url,
              isAutolink: true,
              children: freezeSingleton<MarkdownInlineNode>(
                TextNode(match.label),
              ),
              span: node.span,
            ),
          );
          lastEmit = match.end;
          i = match.end;
          continue;
        }
      }

      // 2. Check `http://`, `https://`, `ftp://`
      if (((cu == 0x68 || cu == 0x48) &&
              i + 6 < len &&
              (text.codeUnitAt(i + 1) | 0x20) == 0x74) ||
          ((cu == 0x66 || cu == 0x46) &&
              i + 5 < len &&
              text.codeUnitAt(i + 3) == 0x3A)) {
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
            out ??= <MarkdownInlineNode>[];
            if (i > lastEmit) {
              out.add(TextNode(text.substring(lastEmit, i), span: node.span));
            }
            out.add(
              resolver._makeLinkNode(
                rawDestination: match.url,
                isAutolink: true,
                children: freezeSingleton<MarkdownInlineNode>(
                  TextNode(match.label),
                ),
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
          out ??= <MarkdownInlineNode>[];
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
              children: freezeSingleton<MarkdownInlineNode>(
                TextNode(emailMatch.label),
              ),
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

    if (out == null) {
      return null;
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
        return null;
      }
      final String replaced = t.text.replaceAllMapped(
        _emojiShortcodePattern,
        (Match m) => emojiShortcodes[m.group(1)!] ?? m.group(0)!,
      );
      if (identical(replaced, t.text)) {
        return null;
      }
      return freezeSingleton<MarkdownInlineNode>(
        TextNode(replaced, span: t.span),
      );
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
        return null;
      }
      return freezeSingleton<MarkdownInlineNode>(TextNode(s, span: t.span));
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
      List<MarkdownInlineNode>? out;
      int last = 0;
      for (final Match m in abbrPattern.allMatches(t.text)) {
        final String abbr = m.group(1)!;
        final String? title = resolver.abbreviations[abbr];
        if (title == null || !resolver.tryConsumeExpandedBytes(title.length)) {
          break;
        }
        out ??= <MarkdownInlineNode>[];
        if (m.start > last) {
          out.add(TextNode(t.text.substring(last, m.start), span: t.span));
        }
        out.add(
          createFrozenAbbrInlineNode(
            title: title,
            children: freezeSingleton<MarkdownInlineNode>(
              TextNode(abbr, span: t.span),
            ),
            span: t.span,
          ),
        );
        last = m.end;
      }
      if (out == null) {
        return null;
      }
      if (last < t.text.length) {
        out.add(TextNode(t.text.substring(last), span: t.span));
      }
      return out;
    });
  }

  List<MarkdownInlineNode> _mapTextNodes(
    List<MarkdownInlineNode> nodes,
    List<MarkdownInlineNode>? Function(TextNode) fn,
  ) {
    List<MarkdownInlineNode>? out;
    final int len = nodes.length;
    for (int i = 0; i < len; i++) {
      final MarkdownInlineNode node = nodes[i];
      if (node is TextNode) {
        final List<MarkdownInlineNode>? replacement = fn(node);
        if (replacement != null) {
          out ??= nodes.sublist(0, i);
          out.addAll(replacement);
          continue;
        }
      } else if (node is EmphasisNode) {
        final List<MarkdownInlineNode> mapped = _mapTextNodes(
          node.children,
          fn,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, i);
          out.add(
            createFrozenEmphasisNode(
              children: freezeFreshList(mapped),
              delimiter: node.delimiter,
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is StrongNode) {
        final List<MarkdownInlineNode> mapped = _mapTextNodes(
          node.children,
          fn,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, i);
          out.add(
            createFrozenStrongNode(
              children: freezeFreshList(mapped),
              delimiter: node.delimiter,
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is StrikethroughNode) {
        final List<MarkdownInlineNode> mapped = _mapTextNodes(
          node.children,
          fn,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, i);
          out.add(
            createFrozenStrikethroughNode(
              children: freezeFreshList(mapped),
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is HighlightNode) {
        final List<MarkdownInlineNode> mapped = _mapTextNodes(
          node.children,
          fn,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, i);
          out.add(
            createFrozenHighlightNode(
              children: freezeFreshList(mapped),
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is SubscriptNode) {
        final List<MarkdownInlineNode> mapped = _mapTextNodes(
          node.children,
          fn,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, i);
          out.add(
            createFrozenSubscriptNode(
              children: freezeFreshList(mapped),
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is SuperscriptNode) {
        final List<MarkdownInlineNode> mapped = _mapTextNodes(
          node.children,
          fn,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, i);
          out.add(
            createFrozenSuperscriptNode(
              children: freezeFreshList(mapped),
              span: node.span,
            ),
          );
          continue;
        }
      } else if (node is LinkNode && !node.isAutolink) {
        final List<MarkdownInlineNode> mapped = _mapTextNodes(
          node.children,
          fn,
        );
        if (!identical(mapped, node.children)) {
          out ??= nodes.sublist(0, i);
          out.add(
            createBlockedLinkNodeFromExisting(
              node,
              children: freezeFreshList(mapped),
            ),
          );
          continue;
        }
      }
      out?.add(node);
    }
    return out ?? nodes;
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
      frozen: true,
    );
  }
  return createFrozenLinkNode(
    destination: existing.destination,
    title: existing.title,
    children: children,
    isAutolink: existing.isAutolink,
    span: existing.span,
  );
}

List<MarkdownInlineNode> _coalesceTextNodes(List<MarkdownInlineNode> nodes) {
  final int len = nodes.length;
  if (len == 0) {
    return nodes;
  }
  if (len == 1) {
    final MarkdownInlineNode only = nodes[0];
    if (only is TextNode && only.text.isEmpty) {
      return emptyFrozenInlineList;
    }
    return nodes;
  }
  bool needsWork = false;
  bool prevWasText = false;
  for (int i = 0; i < len; i++) {
    final MarkdownInlineNode node = nodes[i];
    if (node is TextNode) {
      if (node.text.isEmpty || prevWasText) {
        needsWork = true;
        break;
      }
      prevWasText = true;
    } else {
      prevWasText = false;
    }
  }
  if (!needsWork) {
    return nodes;
  }

  final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
  TextNode? pending;
  StringBuffer? buf;
  SourceSpan? pendingSpan;

  for (int i = 0; i < len; i++) {
    final MarkdownInlineNode node = nodes[i];
    if (node is TextNode) {
      if (node.text.isEmpty) {
        continue;
      }
      if (buf != null) {
        buf.write(node.text);
        final SourceSpan prev = pendingSpan!;
        pendingSpan = createUncheckedSpan(
          startOffset: prev.startOffset,
          endOffset: node.span.endOffset,
          startLine: prev.startLine,
          endLine: node.span.endLine,
        );
      } else if (pending != null) {
        buf = StringBuffer(pending.text)..write(node.text);
        final SourceSpan prev = pendingSpan!;
        pendingSpan = createUncheckedSpan(
          startOffset: prev.startOffset,
          endOffset: node.span.endOffset,
          startLine: prev.startLine,
          endLine: node.span.endLine,
        );
        pending = null;
      } else {
        pending = node;
        pendingSpan = node.span;
      }
    } else {
      if (buf != null) {
        out.add(TextNode(buf.toString(), span: pendingSpan!));
        buf = null;
        pending = null;
        pendingSpan = null;
      } else if (pending != null) {
        out.add(pending);
        pending = null;
        pendingSpan = null;
      }
      out.add(node);
    }
  }
  if (buf != null) {
    out.add(TextNode(buf.toString(), span: pendingSpan!));
  } else if (pending != null) {
    out.add(pending);
  }
  return out;
}

String _extractPlainText(List<MarkdownInlineNode> nodes) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < nodes.length; i++) {
    out.write(nodes[i].toPlainText());
  }
  return out.toString();
}

String _extractAltText(List<MarkdownInlineNode> nodes) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < nodes.length; i++) {
    final MarkdownInlineNode node = nodes[i];
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
