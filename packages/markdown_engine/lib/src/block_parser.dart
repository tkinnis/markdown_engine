import 'ast.dart';
import 'budgets.dart';
import 'frontmatter.dart';
import 'options.dart';
import 'unicode.dart';
import 'url_utils.dart';

/// Phase 1 parser output containing the structural block tree (with raw inline
/// payloads ready for Phase 2) and extracted document-level tables.
final class Phase1Result {
  /// Creates a [Phase1Result].
  const Phase1Result({
    required this.blocks,
    required this.frontmatter,
    required this.linkDefinitions,
    required this.footnoteDefinitions,
    required this.abbreviations,
    required this.normalizedSource,
    this.idPrefix = '',
    this.totalBlockCount = 0,
  });

  /// Top-level block builders/nodes produced by Phase 1.
  final List<RawBlock> blocks;

  /// Extracted frontmatter node if present and enabled.
  final FrontmatterNode? frontmatter;

  /// First-wins link reference definitions keyed by normalized label.
  final Map<String, MarkdownLinkDefinition> linkDefinitions;

  /// Footnote definitions keyed by raw label in definition order.
  final Map<String, RawFootnoteDef> footnoteDefinitions;

  /// Extracted abbreviation definitions (`*[ABBR]: Title`).
  final Map<String, String> abbreviations;

  /// Line-ending and NUL normalized source string.
  final String normalizedSource;

  /// Block ID prefix used during Phase 1 (forwarded to Phase 2).
  final String idPrefix;

  /// Total blocks opened during Phase 1 (including nested containers).
  final int totalBlockCount;
}

/// Intermediate Phase 1 block representation carrying raw inline text before
/// Phase 2 inline resolution.
sealed class RawBlock {
  const RawBlock({
    required this.blockId,
    required this.span,
    this.endsWithBlankLine = false,
  });

  final String blockId;
  final SourceSpan span;
  final bool endsWithBlankLine;
}

/// Intermediate Phase 1 paragraph node.
final class RawParagraph extends RawBlock {
  const RawParagraph({
    required super.blockId,
    required super.span,
    required this.rawText,
    super.endsWithBlankLine,
  });

  final String rawText;
}

/// Intermediate Phase 1 heading node.
final class RawHeading extends RawBlock {
  const RawHeading({
    required super.blockId,
    required super.span,
    required this.level,
    required this.rawText,
    required this.isSetext,
    this.explicitId,
    super.endsWithBlankLine,
  });

  final int level;
  final String rawText;
  final bool isSetext;
  final String? explicitId;
}

/// Intermediate Phase 1 code block node.
final class RawCodeBlock extends RawBlock {
  const RawCodeBlock({
    required super.blockId,
    required super.span,
    required this.info,
    required this.language,
    required this.literal,
    required this.isFenced,
    required this.codeUnitOffset,
    super.endsWithBlankLine,
  });

  final String info;
  final String? language;
  final String literal;
  final bool isFenced;
  final int codeUnitOffset;
}

/// Intermediate Phase 1 thematic break node.
final class RawThematicBreak extends RawBlock {
  const RawThematicBreak({
    required super.blockId,
    required super.span,
    super.endsWithBlankLine,
  });
}

/// Intermediate Phase 1 HTML block node.
final class RawHtmlBlock extends RawBlock {
  const RawHtmlBlock({
    required super.blockId,
    required super.span,
    required this.literal,
    required this.blockType,
    super.endsWithBlankLine,
  });

  final String literal;
  final int blockType;
}

/// Intermediate Phase 1 display math block node.
final class RawMathBlock extends RawBlock {
  const RawMathBlock({
    required super.blockId,
    required super.span,
    required this.latex,
    super.endsWithBlankLine,
  });

  final String latex;
}

/// Intermediate Phase 1 blockquote container.
final class RawBlockQuote extends RawBlock {
  const RawBlockQuote({
    required super.blockId,
    required super.span,
    required this.children,
    super.endsWithBlankLine,
  });

  final List<RawBlock> children;
}

/// Intermediate Phase 1 GitHub-style alert container.
final class RawAlert extends RawBlock {
  const RawAlert({
    required super.blockId,
    required super.span,
    required this.kind,
    required this.title,
    required this.children,
    super.endsWithBlankLine,
  });

  final AlertKind kind;
  final String title;
  final List<RawBlock> children;
}

/// Intermediate Phase 1 list container.
final class RawList extends RawBlock {
  const RawList({
    required super.blockId,
    required super.span,
    required this.ordered,
    required this.start,
    required this.tight,
    required this.delimiter,
    required this.items,
    super.endsWithBlankLine,
  });

  final bool ordered;
  final int start;
  final bool tight;
  final String delimiter;
  final List<RawListItem> items;
}

/// Intermediate Phase 1 list item container.
final class RawListItem extends RawBlock {
  const RawListItem({
    required super.blockId,
    required super.span,
    required this.taskState,
    required this.children,
    super.endsWithBlankLine,
  });

  final bool? taskState;
  final List<RawBlock> children;
}

/// Intermediate Phase 1 table node.
final class RawTable extends RawBlock {
  const RawTable({
    required super.blockId,
    required super.span,
    required this.alignments,
    required this.headerCells,
    required this.rows,
    super.endsWithBlankLine,
  });

  final List<TableAlignment> alignments;
  final List<String> headerCells;
  final List<List<String>> rows;
}

/// Intermediate Phase 1 definition group.
final class RawDefGroup {
  const RawDefGroup({
    required this.termRaw,
    required this.definitions,
    required this.span,
  });

  final String termRaw;
  final List<List<RawBlock>> definitions;
  final SourceSpan span;
}

/// Intermediate Phase 1 definition list node.
final class RawDefinitionList extends RawBlock {
  const RawDefinitionList({
    required super.blockId,
    required super.span,
    required this.groups,
    super.endsWithBlankLine,
  });

  final List<RawDefGroup> groups;
}

/// Intermediate Phase 1 footnote definition node.
final class RawFootnoteDef extends RawBlock {
  const RawFootnoteDef({
    required super.blockId,
    required super.span,
    required this.label,
    required this.children,
    super.endsWithBlankLine,
  });

  final String label;
  final List<RawBlock> children;
}

/// Intermediate Phase 1 `<details>` disclosure block.
final class RawDetailsBlock extends RawBlock {
  const RawDetailsBlock({
    required super.blockId,
    required super.span,
    required this.summaryRaw,
    required this.initiallyOpen,
    required this.children,
    super.endsWithBlankLine,
  });

  final String summaryRaw;
  final bool initiallyOpen;
  final List<RawBlock> children;
}

/// Intermediate Phase 1 aligned container block.
final class RawAlignedBlock extends RawBlock {
  const RawAlignedBlock({
    required super.blockId,
    required super.span,
    required this.alignment,
    required this.children,
    super.endsWithBlankLine,
  });

  final TableAlignment alignment;
  final List<RawBlock> children;
}

/// Intermediate Phase 1 figure container block.
final class RawFigureBlock extends RawBlock {
  const RawFigureBlock({
    required super.blockId,
    required super.span,
    required this.children,
    required this.captionRaw,
    super.endsWithBlankLine,
  });

  final List<RawBlock> children;
  final String? captionRaw;
}

/// Intermediate Phase 1 frontmatter wrapper block.
final class RawFrontmatter extends RawBlock {
  const RawFrontmatter({
    required super.blockId,
    required super.span,
    required this.node,
  });

  final FrontmatterNode node;
}

/// Normalizes line endings (`\r\n`/`\r` -> `\n`) and NUL (`\u0000` -> `\uFFFD`)
/// per CommonMark Section 2.1.
String normalizeMarkdownSource(String source) {
  if (!source.contains('\r') && !source.contains('\x00')) {
    return source;
  }
  StringBuffer? out;
  int last = 0;
  for (int i = 0; i < source.length; i++) {
    final int cu = source.codeUnitAt(i);
    if (cu == 0x0D) {
      out ??= StringBuffer();
      if (i > last) {
        out.write(source.substring(last, i));
      }
      out.writeCharCode(0x0A);
      if (i + 1 < source.length && source.codeUnitAt(i + 1) == 0x0A) {
        i++;
      }
      last = i + 1;
    } else if (cu == 0x00) {
      out ??= StringBuffer();
      if (i > last) {
        out.write(source.substring(last, i));
      }
      out.writeCharCode(0xFFFD);
      last = i + 1;
    }
  }
  if (out == null) {
    return source;
  }
  if (last < source.length) {
    out.write(source.substring(last));
  }
  return out.toString();
}

/// Executes Phase 1 block parsing on [source] with [options], returning raw
/// AST structure plus document-wide link/footnote/abbreviation definitions.
Phase1Result parseBlocks(
  String source,
  MarkdownOptions options, {
  int baseOffset = 0,
  int baseLine = 1,
  String idPrefix = '',
  MarkdownBudgets? budgetsOverride,
}) {
  final String normalized = normalizeMarkdownSource(source);
  final MarkdownBudgets budgets = budgetsOverride ?? options.effectiveBudgets;

  FrontmatterNode? frontmatterNode;
  int bodyStartOffset = 0;
  int bodyStartLine = baseLine;

  if (options.frontmatter && baseOffset == 0) {
    final ParsedFrontmatter? parsed = tryParseFrontmatter(normalized);
    if (parsed != null) {
      frontmatterNode = parsed.node;
      bodyStartOffset = parsed.bodyStartOffset;
      bodyStartLine = parsed.bodyStartLine;
    }
  }

  final List<_SourceLine> lines = _splitLines(
    normalized,
    startOffset: bodyStartOffset,
    startLine: bodyStartLine,
    baseOffset: baseOffset,
  );

  final _BlockEngine engine = _BlockEngine(
    options: options,
    budgets: budgets,
    idPrefix: idPrefix,
  );
  engine.processLines(lines);
  return engine.finalize(
    normalizedSource: normalized,
    frontmatter: frontmatterNode,
  );
}

List<_SourceLine> _splitLines(
  String normalized, {
  required int startOffset,
  required int startLine,
  required int baseOffset,
}) {
  final List<_SourceLine> result = <_SourceLine>[];
  if (startOffset >= normalized.length) {
    return result;
  }
  int cursor = startOffset;
  int lineNumber = startLine;
  while (cursor < normalized.length) {
    final int nl = normalized.indexOf('\n', cursor);
    if (nl == -1) {
      result.add(
        _SourceLine(
          text: normalized.substring(cursor),
          startOffset: baseOffset + cursor,
          endOffset: baseOffset + normalized.length,
          lineNumber: lineNumber,
        ),
      );
      break;
    }
    result.add(
      _SourceLine(
        text: normalized.substring(cursor, nl),
        startOffset: baseOffset + cursor,
        endOffset: baseOffset + nl + 1,
        lineNumber: lineNumber,
      ),
    );
    cursor = nl + 1;
    lineNumber++;
  }
  return result;
}

final class _SourceLine {
  const _SourceLine({
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.lineNumber,
  });

  final String text;
  final int startOffset;
  final int endOffset;
  final int lineNumber;
}

final class _LineCursor {
  _LineCursor(this.line)
    : index = 0,
      column = 0,
      pendingTabSpaces = 0,
      firstNonSpaceIndex = 0,
      firstNonSpaceColumn = 0,
      firstNonSpacePendingSpaces = 0,
      indent = 0,
      blank = false;

  final _SourceLine line;
  int index;
  int column;
  int pendingTabSpaces;

  int firstNonSpaceIndex;
  int firstNonSpaceColumn;
  int firstNonSpacePendingSpaces;
  int indent;
  bool blank;

  String get raw => line.text;

  bool get isAtEnd => pendingTabSpaces == 0 && index >= raw.length;

  void findNextNonSpace() {
    int i = index;
    int col = column;
    int pending = pendingTabSpaces;
    if (pending > 0) {
      col += pending;
      pending = 0;
    }
    while (i < raw.length) {
      final int cu = raw.codeUnitAt(i);
      if (cu == 0x20) {
        i++;
        col++;
      } else if (cu == 0x09) {
        col += 4 - (col % 4);
        i++;
      } else {
        break;
      }
    }
    blank = i >= raw.length;
    firstNonSpaceIndex = i;
    firstNonSpaceColumn = col;
    firstNonSpacePendingSpaces = pending;
    indent = col - column;
  }

  void advanceToNextNonSpace() {
    index = firstNonSpaceIndex;
    column = firstNonSpaceColumn;
    pendingTabSpaces = firstNonSpacePendingSpaces;
  }

  void advanceOffset(int chars) {
    for (int k = 0; k < chars && index < raw.length; k++) {
      final int cu = raw.codeUnitAt(index);
      if (cu == 0x09) {
        column += 4 - (column % 4);
      } else {
        column++;
      }
      index++;
      pendingTabSpaces = 0;
    }
  }

  void advanceColumns(int count) {
    int remaining = count;
    if (pendingTabSpaces > 0) {
      final int take = remaining < pendingTabSpaces
          ? remaining
          : pendingTabSpaces;
      pendingTabSpaces -= take;
      column += take;
      remaining -= take;
    }
    while (remaining > 0 && index < raw.length) {
      final int cu = raw.codeUnitAt(index);
      if (cu == 0x20) {
        index++;
        column++;
        remaining--;
      } else if (cu == 0x09) {
        final int tabWidth = 4 - (column % 4);
        if (tabWidth <= remaining) {
          index++;
          column += tabWidth;
          remaining -= tabWidth;
        } else {
          index++;
          column += remaining;
          pendingTabSpaces = tabWidth - remaining;
          remaining = 0;
        }
      } else {
        break;
      }
    }
  }

  int peekCodeUnitAtNonSpace([int offset = 0]) {
    final int pos = firstNonSpaceIndex + offset;
    if (pos >= raw.length) {
      return -1;
    }
    return raw.codeUnitAt(pos);
  }

  String restOfLine() {
    if (pendingTabSpaces == 0) {
      return index >= raw.length ? '' : raw.substring(index);
    }
    return '${' ' * pendingTabSpaces}${index >= raw.length ? '' : raw.substring(index)}';
  }

  String restAfterNonSpace() {
    return firstNonSpaceIndex >= raw.length
        ? ''
        : raw.substring(firstNonSpaceIndex);
  }
}

sealed class _OpenBlock {
  _OpenBlock({
    required this.blockId,
    required this.startOffset,
    required this.startLine,
  }) : endOffset = startOffset,
       endLine = startLine;

  final String blockId;
  final int startOffset;
  int endOffset;
  final int startLine;
  int endLine;

  bool isOpen = true;
  bool lastLineBlank = false;
  bool endsWithBlank = false;

  bool get isContainer => false;
  bool get acceptsLines => false;

  void extendSpan(_SourceLine line) {
    endOffset = line.endOffset;
    endLine = line.lineNumber;
  }
}

final class _DocOpenBlock extends _OpenBlock {
  _DocOpenBlock() : super(blockId: 'doc', startOffset: 0, startLine: 1);

  final List<_OpenBlock> children = <_OpenBlock>[];

  @override
  bool get isContainer => true;
}

final class _BlockQuoteOpenBlock extends _OpenBlock {
  _BlockQuoteOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
  });

  final List<_OpenBlock> children = <_OpenBlock>[];

  @override
  bool get isContainer => true;
}

final class _ListOpenBlock extends _OpenBlock {
  _ListOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
    required this.ordered,
    required this.start,
    required this.delimiter,
    required this.bulletChar,
  });

  final bool ordered;
  final int start;
  final String delimiter;
  final int bulletChar;
  final List<_ListItemOpenBlock> items = <_ListItemOpenBlock>[];
  bool tight = true;

  @override
  bool get isContainer => true;
}

final class _ListItemOpenBlock extends _OpenBlock {
  _ListItemOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
    required this.contentIndent,
    required this.ordered,
    required this.start,
    required this.delimiter,
    required this.bulletChar,
  });

  final int contentIndent;
  final bool ordered;
  final int start;
  final String delimiter;
  final int bulletChar;
  final List<_OpenBlock> children = <_OpenBlock>[];
  bool hadContentLine = false;
  bool hadBlankBeforeChild = false;
  bool hasBlankBetweenChildren = false;
  bool startedBlank = false;
  bool closedBySecondBlank = false;

  @override
  bool get isContainer => true;
}

final class _FootnoteDefOpenBlock extends _OpenBlock {
  _FootnoteDefOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
    required this.label,
  });

  final String label;
  final List<_OpenBlock> children = <_OpenBlock>[];
  bool hadBlankLine = false;

  @override
  bool get isContainer => true;
}

final class _ParagraphOpenBlock extends _OpenBlock {
  _ParagraphOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
  });

  final List<String> lines = <String>[];
  final List<_SourceLine> sourceLines = <_SourceLine>[];
  bool hadPredecessorBlankLine = false;

  @override
  bool get acceptsLines => true;
}

final class _HeadingOpenBlock extends _OpenBlock {
  _HeadingOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
    required this.level,
    required this.rawText,
    required this.isSetext,
    this.explicitId,
  });

  final int level;
  final String rawText;
  final bool isSetext;
  final String? explicitId;
}

final class _CodeOpenBlock extends _OpenBlock {
  _CodeOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
    required this.isFenced,
    this.fenceChar = 0,
    this.fenceLength = 0,
    this.fenceIndent = 0,
    this.info = '',
    this.codeUnitOffset = 0,
  });

  final bool isFenced;
  final int fenceChar;
  final int fenceLength;
  final int fenceIndent;
  final String info;
  final int codeUnitOffset;
  final List<String> lines = <String>[];

  @override
  bool get acceptsLines => true;
}

final class _MathOpenBlock extends _OpenBlock {
  _MathOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
    required this.singleLineLatex,
  }) : isClosed = singleLineLatex != null;

  final String? singleLineLatex;
  final List<String> lines = <String>[];
  bool isClosed;

  @override
  bool get acceptsLines => !isClosed;
}

final class _HtmlOpenBlock extends _OpenBlock {
  _HtmlOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
    required this.blockType,
  });

  final int blockType;
  final List<String> lines = <String>[];

  @override
  bool get acceptsLines => true;
}

final class _ThematicBreakOpenBlock extends _OpenBlock {
  _ThematicBreakOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
  });
}

final class _TableOpenBlock extends _OpenBlock {
  _TableOpenBlock({
    required super.blockId,
    required super.startOffset,
    required super.startLine,
    required this.alignments,
    required this.headerCells,
  });

  final List<TableAlignment> alignments;
  final List<String> headerCells;
  final List<List<String>> rows = <List<String>>[];

  @override
  bool get acceptsLines => true;
}

final class _BlockEngine {
  _BlockEngine({
    required this.options,
    required this.budgets,
    this.idPrefix = '',
  });

  final MarkdownOptions options;
  final MarkdownBudgets budgets;
  final String idPrefix;

  final _DocOpenBlock _root = _DocOpenBlock();
  final List<_OpenBlock> _stack = <_OpenBlock>[];
  final Map<String, MarkdownLinkDefinition> _linkDefinitions =
      <String, MarkdownLinkDefinition>{};
  final Map<String, RawFootnoteDef> _footnoteDefs = <String, RawFootnoteDef>{};
  final Map<String, String> _abbreviations = <String, String>{};

  int _idCounter = 0;
  int _blockCount = 0;
  int _subIdCounter = 0;
  bool _budgetExceeded = false;

  String _nextId(String prefix) {
    _idCounter++;
    return '$idPrefix$prefix-$_idCounter';
  }

  bool _canOpenBlock([int count = 1]) {
    if (_blockCount + count > budgets.maxBlocks) {
      _budgetExceeded = true;
      return false;
    }
    return true;
  }

  void processLines(List<_SourceLine> lines) {
    _stack.add(_root);
    for (final _SourceLine line in lines) {
      if (_budgetExceeded ||
          (_blockCount >= budgets.maxBlocks && _stack.length == 1)) {
        break;
      }
      _incorporateLine(line);
    }
    _closeStackDownTo(0, null);
  }

  Phase1Result finalize({
    required String normalizedSource,
    required FrontmatterNode? frontmatter,
  }) {
    final List<RawBlock> topBlocks = <RawBlock>[];
    if (frontmatter != null && budgets.maxBlocks > 0) {
      topBlocks.add(
        RawFrontmatter(
          blockId: frontmatter.blockId,
          span: frontmatter.span,
          node: frontmatter,
        ),
      );
    }
    for (final _OpenBlock child in _root.children) {
      if (topBlocks.length >= budgets.maxBlocks) {
        break;
      }
      final RawBlock? built = _buildBlock(child, isTopLevel: true);
      if (built != null) {
        topBlocks.add(built);
      }
    }
    final List<RawBlock> transformed = _postProcessBlocks(topBlocks);
    return Phase1Result(
      blocks: freezeList(transformed),
      frontmatter: frontmatter,
      linkDefinitions: freezeMap(_linkDefinitions),
      footnoteDefinitions: freezeMap(_footnoteDefs),
      abbreviations: freezeMap(_abbreviations),
      normalizedSource: normalizedSource,
      idPrefix: idPrefix,
      totalBlockCount: _blockCount,
    );
  }

  void _incorporateLine(_SourceLine line) {
    final _LineCursor cursor = _LineCursor(line);
    int matchedDepth = 0;
    bool allMatched = true;

    // Step 1: check open containers along the active stack.
    for (int d = 1; d < _stack.length; d++) {
      final _OpenBlock container = _stack[d];
      if (!container.isContainer) {
        break;
      }
      cursor.findNextNonSpace();

      if (container is _BlockQuoteOpenBlock) {
        if (cursor.indent <= 3 && cursor.peekCodeUnitAtNonSpace() == 0x3E) {
          cursor.advanceToNextNonSpace();
          cursor.advanceOffset(1);
          if (!cursor.isAtEnd) {
            if (cursor.pendingTabSpaces > 0) {
              cursor.advanceColumns(1);
            } else {
              final int nextCu = cursor.raw.codeUnitAt(cursor.index);
              if (nextCu == 0x20 || nextCu == 0x09) {
                cursor.advanceColumns(1);
              }
            }
          }
          container.extendSpan(line);
          matchedDepth = d;
        } else {
          allMatched = false;
          break;
        }
      } else if (container is _ListOpenBlock) {
        // Keep `matchedDepth` at the list's parent until a child list item
        // actually matches, so a failed list item closes the list cleanly
        // unless a sibling list item of the same type opens in Step 2.
      } else if (container is _ListItemOpenBlock) {
        if (cursor.blank) {
          if (container.children.isEmpty && container.startedBlank) {
            allMatched = false;
            break;
          }
          cursor.advanceToNextNonSpace();
          matchedDepth = d;
        } else if (cursor.indent >= container.contentIndent) {
          cursor.advanceColumns(container.contentIndent);
          container.extendSpan(line);
          matchedDepth = d;
        } else {
          allMatched = false;
          break;
        }
      } else if (container is _FootnoteDefOpenBlock) {
        if (cursor.blank) {
          cursor.advanceToNextNonSpace();
          matchedDepth = d;
        } else if (cursor.indent >= 4) {
          cursor.advanceColumns(4);
          container.extendSpan(line);
          matchedDepth = d;
        } else {
          allMatched = false;
          break;
        }
      }
    }

    final int lastMatched = matchedDepth;
    final _OpenBlock oldTip = _stack.last;
    final bool oldTipWasParagraph = oldTip is _ParagraphOpenBlock;
    final bool oldTipWasTable = oldTip is _TableOpenBlock;

    // An indented code block closes immediately when indent < 4 on a non-blank
    // line (or when an ancestor container failed), allowing Step 2 starters.
    if (oldTip is _CodeOpenBlock && !oldTip.isFenced) {
      cursor.findNextNonSpace();
      if (!allMatched || (!cursor.blank && cursor.indent < 4)) {
        _popLeaf();
      }
    }

    // Step 2: check block starters unless inside an unbroken code block,
    // HTML block, or math block whose ancestor containers all matched.
    final _OpenBlock tipBeforeStarters = _stack.last;
    final bool insideUnbrokenVerbatim =
        allMatched &&
        (tipBeforeStarters is _CodeOpenBlock ||
            tipBeforeStarters is _HtmlOpenBlock ||
            tipBeforeStarters is _MathOpenBlock);

    bool closedUnmatched = false;
    bool keepCheckingStarters = !insideUnbrokenVerbatim;

    void closeUnmatchedIfNeeded() {
      if (!closedUnmatched) {
        closedUnmatched = true;
        _closeStackDownTo(lastMatched, line);
      }
    }

    while (keepCheckingStarters) {
      cursor.findNextNonSpace();
      final _OpenBlock currentContainer = closedUnmatched
          ? _stack.last
          : _stack[lastMatched];
      final int containerDepth = closedUnmatched
          ? _stack.length - 1
          : lastMatched;
      final bool atMaxDepth = containerDepth >= budgets.maxNestingDepth;

      if (cursor.indent < 4) {
        final int firstCu = cursor.peekCodeUnitAtNonSpace();

        // 1. Blockquote (`>`), subject to maxNestingDepth.
        if (firstCu == 0x3E && !atMaxDepth) {
          if (!_canOpenBlock()) {
            return;
          }
          closeUnmatchedIfNeeded();
          cursor.advanceToNextNonSpace();
          cursor.advanceOffset(1);
          if (!cursor.isAtEnd) {
            if (cursor.pendingTabSpaces > 0) {
              cursor.advanceColumns(1);
            } else {
              final int nextCu = cursor.raw.codeUnitAt(cursor.index);
              if (nextCu == 0x20 || nextCu == 0x09) {
                cursor.advanceColumns(1);
              }
            }
          }
          _addChild(
            _BlockQuoteOpenBlock(
              blockId: _nextId('quote'),
              startOffset: line.startOffset,
              startLine: line.lineNumber,
            ),
            line,
          );
          continue;
        }

        // 2. ATX Heading (`#`).
        if (firstCu == 0x23) {
          final _AtxMatch? atx = _matchAtxHeading(cursor);
          if (atx != null) {
            if (!_canOpenBlock()) {
              return;
            }
            closeUnmatchedIfNeeded();
            _addChild(
              _HeadingOpenBlock(
                blockId: _nextId('heading'),
                startOffset: line.startOffset,
                startLine: line.lineNumber,
                level: atx.level,
                rawText: atx.content,
                isSetext: false,
                explicitId: atx.explicitId,
              ),
              line,
            );
            _popLeaf();
            return;
          }
        }

        // 3. Fenced Code Block (``` or ~~~).
        if (firstCu == 0x60 || firstCu == 0x7E) {
          final _FenceOpenMatch? fence = _matchFenceOpen(cursor);
          if (fence != null) {
            if (!_canOpenBlock()) {
              return;
            }
            closeUnmatchedIfNeeded();
            _addChild(
              _CodeOpenBlock(
                blockId: _nextId('code'),
                startOffset: line.startOffset,
                startLine: line.lineNumber,
                isFenced: true,
                fenceChar: fence.fenceChar,
                fenceLength: fence.fenceLength,
                fenceIndent: fence.indent,
                info: fence.info,
                codeUnitOffset: line.endOffset,
              ),
              line,
            );
            return;
          }
        }

        // 4. Display Math Block (`$$`).
        if (options.math && firstCu == 0x24) {
          final _MathOpenMatch? mathMatch = _matchMathOpen(cursor);
          if (mathMatch != null) {
            if (!_canOpenBlock()) {
              return;
            }
            closeUnmatchedIfNeeded();
            final _MathOpenBlock mathBlock = _MathOpenBlock(
              blockId: _nextId('math'),
              startOffset: line.startOffset,
              startLine: line.lineNumber,
              singleLineLatex: mathMatch.singleLineLatex,
            );
            _addChild(mathBlock, line);
            if (mathBlock.isClosed) {
              _popLeaf();
            }
            return;
          }
        }

        // 5. HTML Block (Conditions 1..7).
        if (firstCu == 0x3C) {
          final bool tipIsActivePara = !closedUnmatched && oldTipWasParagraph;
          final int? htmlType = _matchHtmlBlockStart(
            cursor.restAfterNonSpace(),
            allowType7: !tipIsActivePara,
          );
          if (htmlType != null) {
            if (!_canOpenBlock()) {
              return;
            }
            closeUnmatchedIfNeeded();
            final _HtmlOpenBlock htmlBlock = _HtmlOpenBlock(
              blockId: _nextId('html'),
              startOffset: line.startOffset,
              startLine: line.lineNumber,
              blockType: htmlType,
            );
            final String fullLine = cursor.restOfLine();
            htmlBlock.lines.add(fullLine);
            htmlBlock.extendSpan(line);
            _addChild(htmlBlock, line);
            if (htmlType <= 5 && _matchHtmlBlockEnd(htmlType, fullLine)) {
              _popLeaf();
            }
            return;
          }
        }

        // 6. Setext Heading Underline (`===` or `---`) on an active paragraph.
        if (!closedUnmatched &&
            allMatched &&
            oldTip is _ParagraphOpenBlock &&
            (firstCu == 0x3D || firstCu == 0x2D)) {
          final int? setextLevel = _matchSetextUnderlineSpan(
            cursor.raw,
            cursor.firstNonSpaceIndex,
          );
          if (setextLevel != null) {
            final String remaining = _extractLinkDefsFromParagraph(oldTip);
            if (remaining.isNotEmpty) {
              final _OpenBlock parent = _stack[_stack.length - 2];
              _stack.removeLast();
              _removeLastChild(parent);
              final _SetextHeadingText parsedSetext = _extractExplicitId(
                remaining,
                enabled: options.explicitHeadingIds,
              );
              final _HeadingOpenBlock heading = _HeadingOpenBlock(
                blockId: _nextId('heading'),
                startOffset: oldTip.startOffset,
                startLine: oldTip.startLine,
                level: setextLevel,
                rawText: parsedSetext.text,
                isSetext: true,
                explicitId: parsedSetext.explicitId,
              )..extendSpan(line);
              _addChild(heading, line);
              _popLeaf();
              return;
            }
          }
        }

        // 7. GFM Pipe Table Delimiter Row interrupting an active paragraph.
        if (options.gfmTables &&
            !closedUnmatched &&
            allMatched &&
            oldTip is _ParagraphOpenBlock &&
            (firstCu == 0x7C || firstCu == 0x2D || firstCu == 0x3A)) {
          final List<TableAlignment>? alignments = _matchTableDelimiterRowSpan(
            cursor.raw,
            cursor.firstNonSpaceIndex,
            maxColumns: budgets.maxTableColumns,
          );
          if (alignments != null &&
              alignments.length <= budgets.maxTableColumns) {
            final _TableIntercept? table = _tryConvertParagraphTailToTable(
              oldTip,
              alignments,
              line,
            );
            if (table != null) {
              return;
            }
          }
        }

        // 8. Thematic Break (`***`, `---`, `___`).
        if (firstCu == 0x2A || firstCu == 0x2D || firstCu == 0x5F) {
          if (_matchThematicBreakSpan(cursor.raw, cursor.firstNonSpaceIndex)) {
            if (!_canOpenBlock()) {
              return;
            }
            closeUnmatchedIfNeeded();
            _addChild(
              _ThematicBreakOpenBlock(
                blockId: _nextId('hr'),
                startOffset: line.startOffset,
                startLine: line.lineNumber,
              ),
              line,
            );
            _popLeaf();
            return;
          }
        }

        // 9. Footnote Definition (`[^label]: ...`) when not interrupting paragraph.
        if (options.footnotes &&
            firstCu == 0x5B &&
            !(!closedUnmatched && oldTipWasParagraph) &&
            !atMaxDepth) {
          final _FootnoteStartMatch? fn = _matchFootnoteStart(cursor);
          if (fn != null) {
            if (!_canOpenBlock()) {
              return;
            }
            closeUnmatchedIfNeeded();
            cursor.advanceToNextNonSpace();
            cursor.advanceOffset(fn.consumedChars);
            final _FootnoteDefOpenBlock fnBlock = _FootnoteDefOpenBlock(
              blockId: _nextId('fn'),
              startOffset: line.startOffset,
              startLine: line.lineNumber,
              label: fn.label,
            );
            _addChild(fnBlock, line);
            continue;
          }
        }

        // 10. List Item (`-`, `+`, `*`, `1.`, `1)`).
        if (firstCu == 0x2D ||
            firstCu == 0x2B ||
            firstCu == 0x2A ||
            isAsciiDigit(firstCu)) {
          final bool tipIsMatchedParagraph =
              !closedUnmatched && allMatched && oldTipWasParagraph;
          final _ListMarkerMatch? marker = _matchListMarker(
            cursor,
            interruptingParagraph: tipIsMatchedParagraph,
          );
          if (marker != null && !atMaxDepth) {
            final _OpenBlock tipBeforeList = closedUnmatched
                ? _stack.last
                : _stack[lastMatched];
            final _OpenBlock? prevLastChild = _lastChildOf(tipBeforeList);
            final bool reusesExistingList =
                (tipBeforeList is _ListOpenBlock &&
                    tipBeforeList.ordered == marker.ordered &&
                    tipBeforeList.delimiter == marker.delimiter &&
                    tipBeforeList.bulletChar == marker.bulletChar) ||
                (prevLastChild is _ListOpenBlock &&
                    prevLastChild.ordered == marker.ordered &&
                    prevLastChild.delimiter == marker.delimiter &&
                    prevLastChild.bulletChar == marker.bulletChar);
            if (!_canOpenBlock(reusesExistingList ? 1 : 2)) {
              return;
            }
            closeUnmatchedIfNeeded();
            final int contentIndent = marker.indent + marker.padding;
            cursor.advanceToNextNonSpace();
            cursor.advanceOffset(marker.markerChars);
            cursor.advanceColumns(marker.spacesAfterMarkerConsumed);

            _ListOpenBlock? listBlock;
            final _OpenBlock tipNow = _stack.last;
            final _OpenBlock? lastChild = _lastChildOf(tipNow);
            if (tipNow is _ListOpenBlock &&
                tipNow.ordered == marker.ordered &&
                tipNow.delimiter == marker.delimiter &&
                tipNow.bulletChar == marker.bulletChar) {
              listBlock = tipNow;
            } else if (lastChild is _ListOpenBlock &&
                lastChild.ordered == marker.ordered &&
                lastChild.delimiter == marker.delimiter &&
                lastChild.bulletChar == marker.bulletChar) {
              // Reopen immediately preceding list of the same marker type.
              if (lastChild.items.isNotEmpty &&
                  lastChild.items.last.endsWithBlank) {
                lastChild.tight = false;
              }
              _stack.add(lastChild);
              listBlock = lastChild;
            } else {
              if (tipNow is _ListOpenBlock) {
                _closeTopBlock(line);
              }
              listBlock = _ListOpenBlock(
                blockId: _nextId('list'),
                startOffset: line.startOffset,
                startLine: line.lineNumber,
                ordered: marker.ordered,
                start: marker.start,
                delimiter: marker.delimiter,
                bulletChar: marker.bulletChar,
              );
              _addChild(listBlock, line);
            }

            final _ListItemOpenBlock itemBlock = _ListItemOpenBlock(
              blockId: _nextId('item'),
              startOffset: line.startOffset,
              startLine: line.lineNumber,
              contentIndent: contentIndent,
              ordered: marker.ordered,
              start: marker.start,
              delimiter: marker.delimiter,
              bulletChar: marker.bulletChar,
            );
            cursor.findNextNonSpace();
            if (cursor.blank) {
              itemBlock.startedBlank = true;
              _addChild(itemBlock, line);
              return;
            }
            _addChild(itemBlock, line);
            continue;
          }
        }
      }

      // 11. Indented Code Block (`indent >= 4`).
      final bool tipIsParagraph = !closedUnmatched && oldTipWasParagraph;
      if (cursor.indent >= 4 &&
          !cursor.blank &&
          !tipIsParagraph &&
          !oldTipWasTable) {
        if (!_canOpenBlock()) {
          return;
        }
        closeUnmatchedIfNeeded();
        cursor.advanceColumns(4);
        final _CodeOpenBlock code = _CodeOpenBlock(
          blockId: _nextId('code'),
          startOffset: line.startOffset,
          startLine: line.lineNumber,
          isFenced: false,
          codeUnitOffset: line.startOffset,
        );
        code.lines.add(cursor.restOfLine());
        code.extendSpan(line);
        _addChild(code, line);
        return;
      }

      keepCheckingStarters = false;
      final _ = currentContainer;
    }

    // Step 3: handle remaining text for the current leaf or container tip.
    if (!closedUnmatched && !allMatched) {
      // Check lazy paragraph continuation.
      if (oldTip is _ParagraphOpenBlock && !cursor.blank) {
        // Lazy paragraph continuation (must not be a blank line).
        cursor.advanceToNextNonSpace();
        oldTip.lines.add(cursor.restOfLine());
        oldTip.sourceLines.add(line);
        oldTip.extendSpan(line);
        _clearLastLineBlankUpTo(oldTip);
        return;
      }
      closeUnmatchedIfNeeded();
    }

    final _OpenBlock tip = _stack.last;

    if (tip is _CodeOpenBlock) {
      if (tip.isFenced) {
        cursor.findNextNonSpace();
        if (cursor.indent <= 3 &&
            _matchFenceClose(
              cursor.restAfterNonSpace(),
              tip.fenceChar,
              tip.fenceLength,
            )) {
          tip.extendSpan(line);
          _popLeaf();
          return;
        }
        // Strip up to opening fence indent spaces.
        cursor.advanceColumns(tip.fenceIndent);
        tip.lines.add(cursor.restOfLine());
        tip.extendSpan(line);
        return;
      } else {
        // Indented code block.
        cursor.findNextNonSpace();
        if (cursor.blank) {
          cursor.advanceColumns(4);
          tip.lines.add(cursor.restOfLine());
          tip.lastLineBlank = true;
          tip.extendSpan(line);
          return;
        }
        if (cursor.indent >= 4) {
          cursor.advanceColumns(4);
          tip.lines.add(cursor.restOfLine());
          tip.lastLineBlank = false;
          tip.extendSpan(line);
          return;
        }
        _popLeaf();
      }
    }

    if (tip is _MathOpenBlock) {
      cursor.findNextNonSpace();
      if (cursor.indent <= 3 && _matchMathClose(cursor.restAfterNonSpace())) {
        tip.extendSpan(line);
        tip.isClosed = true;
        _popLeaf();
        return;
      }
      tip.lines.add(cursor.restOfLine());
      tip.extendSpan(line);
      return;
    }

    if (tip is _HtmlOpenBlock) {
      if (tip.blockType >= 6) {
        cursor.findNextNonSpace();
        if (cursor.blank) {
          _popLeaf();
          _markBlankLineOnStack(line);
          return;
        }
      }
      final String text = cursor.restOfLine();
      tip.lines.add(text);
      tip.extendSpan(line);
      if (tip.blockType <= 5 && _matchHtmlBlockEnd(tip.blockType, text)) {
        _popLeaf();
      }
      return;
    }

    if (tip is _TableOpenBlock) {
      cursor.findNextNonSpace();
      if (cursor.blank) {
        _popLeaf();
        _markBlankLineOnStack(line);
        return;
      }
      if (tip.rows.length < budgets.maxTableRows) {
        final List<String> rowCells = _splitTableRow(
          cursor.restOfLine(),
          maxColumns: tip.alignments.length,
        );
        tip.rows.add(rowCells);
        tip.extendSpan(line);
        return;
      } else {
        _popLeaf();
      }
    }

    final _OpenBlock activeTip = _stack.last;
    cursor.findNextNonSpace();

    if (cursor.blank) {
      if (activeTip is _ParagraphOpenBlock) {
        _popLeaf();
      }
      _markBlankLineOnStack(line);
      return;
    }

    if (activeTip is _ParagraphOpenBlock) {
      cursor.advanceToNextNonSpace();
      activeTip.lines.add(cursor.restOfLine());
      activeTip.sourceLines.add(line);
      activeTip.extendSpan(line);
      _clearLastLineBlankUpTo(activeTip);
      return;
    }

    // Open a new paragraph (unless block budget exceeded).
    if (!_canOpenBlock()) {
      return;
    }
    cursor.advanceToNextNonSpace();
    final _ParagraphOpenBlock para = _ParagraphOpenBlock(
      blockId: _nextId('para'),
      startOffset: line.startOffset,
      startLine: line.lineNumber,
    );
    if (activeTip is _ListItemOpenBlock) {
      if (activeTip.hadBlankBeforeChild && activeTip.children.isNotEmpty) {
        activeTip.hasBlankBetweenChildren = true;
      }
      activeTip.hadBlankBeforeChild = false;
      activeTip.hadContentLine = true;
    } else if (activeTip is _FootnoteDefOpenBlock) {
      activeTip.hadBlankLine = false;
    }
    para.lines.add(cursor.restOfLine());
    para.sourceLines.add(line);
    para.extendSpan(line);
    _clearLastLineBlankUpTo(para);
    _addChild(para, line);
  }

  _TableIntercept? _tryConvertParagraphTailToTable(
    _ParagraphOpenBlock para,
    List<TableAlignment> alignments,
    _SourceLine delimiterLine,
  ) {
    // First consume any leading link reference definitions from the paragraph!
    final String remaining = _extractLinkDefsFromParagraph(para);
    if (remaining.isEmpty) {
      return null;
    }
    final List<String> remainingLines = remaining.split('\n');
    final String headerLine = remainingLines.last;
    final List<String> headerCells = _splitTableRow(
      headerLine,
      maxColumns: alignments.length + 1,
    );
    if (headerCells.length != alignments.length) {
      return null;
    }
    // Check that either header or delimiter line actually contains a pipe
    // unless multi-column. Single-column table without pipes would shadow
    // setext heading, which was already checked before tables.
    if (!headerLine.contains('|') && !delimiterLine.text.contains('|')) {
      return null;
    }

    final _OpenBlock parent = _stack[_stack.length - 2];
    if (remainingLines.length == 1) {
      // Whole paragraph becomes the table header (replaces para, net 0 blocks).
      final int tableStartOffset = para.startOffset;
      final int tableStartLine = para.startLine;
      _stack.removeLast();
      _removeLastChild(parent);
      _blockCount--;
      final _TableOpenBlock table = _TableOpenBlock(
        blockId: _nextId('table'),
        startOffset: tableStartOffset,
        startLine: tableStartLine,
        alignments: alignments,
        headerCells: headerCells,
      )..extendSpan(delimiterLine);
      _addChild(table, delimiterLine);
      return _TableIntercept(table);
    } else {
      if (!_canOpenBlock()) {
        return null;
      }
      // Split preceding lines into closed paragraph, then open table.
      final int headerSourceLineIdx = para.sourceLines.length - 1;
      final _SourceLine headerSrcLine = para.sourceLines[headerSourceLineIdx];
      para.lines
        ..clear()
        ..addAll(remainingLines.sublist(0, remainingLines.length - 1));
      if (headerSourceLineIdx > 0) {
        para.endOffset = para.sourceLines[headerSourceLineIdx - 1].endOffset;
        para.endLine = para.sourceLines[headerSourceLineIdx - 1].lineNumber;
        para.sourceLines.removeRange(
          headerSourceLineIdx,
          para.sourceLines.length,
        );
      }
      _popLeaf();
      final _TableOpenBlock table = _TableOpenBlock(
        blockId: _nextId('table'),
        startOffset: headerSrcLine.startOffset,
        startLine: headerSrcLine.lineNumber,
        alignments: alignments,
        headerCells: headerCells,
      )..extendSpan(delimiterLine);
      _addChild(table, delimiterLine);
      return _TableIntercept(table);
    }
  }

  void _addChild(_OpenBlock child, _SourceLine line) {
    final _OpenBlock parent = _stack.last;
    if (parent is _ListItemOpenBlock) {
      if ((parent.hadBlankBeforeChild ||
              (parent.children.isNotEmpty &&
                  parent.children.last is _ListOpenBlock &&
                  parent.children.last.endsWithBlank)) &&
          parent.children.isNotEmpty) {
        parent.hasBlankBetweenChildren = true;
      }
      parent.hadBlankBeforeChild = false;
      parent.hadContentLine = true;
      parent.children.add(child);
    } else if (parent is _ListOpenBlock && child is _ListItemOpenBlock) {
      if (parent.items.isNotEmpty && parent.items.last.endsWithBlank) {
        parent.tight = false;
      }
      parent.items.add(child);
    } else if (parent is _DocOpenBlock) {
      parent.children.add(child);
    } else if (parent is _BlockQuoteOpenBlock) {
      parent.children.add(child);
    } else if (parent is _FootnoteDefOpenBlock) {
      parent.children.add(child);
    }
    _stack.add(child);
    _blockCount++;
    child.extendSpan(line);
  }

  void _removeLastChild(_OpenBlock parent) {
    if (parent is _DocOpenBlock && parent.children.isNotEmpty) {
      parent.children.removeLast();
    } else if (parent is _BlockQuoteOpenBlock && parent.children.isNotEmpty) {
      parent.children.removeLast();
    } else if (parent is _ListItemOpenBlock && parent.children.isNotEmpty) {
      parent.children.removeLast();
    } else if (parent is _FootnoteDefOpenBlock && parent.children.isNotEmpty) {
      parent.children.removeLast();
    }
  }

  _OpenBlock? _lastChildOf(_OpenBlock parent) {
    if (parent is _DocOpenBlock && parent.children.isNotEmpty) {
      return parent.children.last;
    }
    if (parent is _BlockQuoteOpenBlock && parent.children.isNotEmpty) {
      return parent.children.last;
    }
    if (parent is _ListItemOpenBlock && parent.children.isNotEmpty) {
      return parent.children.last;
    }
    if (parent is _FootnoteDefOpenBlock && parent.children.isNotEmpty) {
      return parent.children.last;
    }
    return null;
  }

  void _popLeaf() {
    if (_stack.length <= 1) {
      return;
    }
    final _OpenBlock closed = _stack.removeLast();
    _finalizeOpenBlock(closed);
  }

  void _closeTopBlock(_SourceLine? line) {
    if (_stack.length <= 1) {
      return;
    }
    final _OpenBlock closed = _stack.removeLast();
    _finalizeOpenBlock(closed);
  }

  void _closeStackDownTo(int targetDepth, _SourceLine? line) {
    while (_stack.length - 1 > targetDepth) {
      _closeTopBlock(line);
    }
  }

  void _markBlankLineOnStack(_SourceLine line) {
    final _OpenBlock tip = _stack.last;
    tip.lastLineBlank = true;
    tip.endsWithBlank = true;
    if (tip is _ListItemOpenBlock) {
      if (tip.children.isNotEmpty) {
        tip.hadBlankBeforeChild = true;
      }
    } else if (tip is _ListOpenBlock) {
      if (tip.items.isNotEmpty) {
        tip.items.last.endsWithBlank = true;
      }
    } else if (tip is _FootnoteDefOpenBlock) {
      tip.hadBlankLine = true;
    }
    // Propagate blank line marker to direct list item parent if its last child
    // ended on a blank line (except inside blockquote/code/html).
    for (int i = _stack.length - 1; i >= 1; i--) {
      final _OpenBlock b = _stack[i];
      if (b is _ListItemOpenBlock && i == _stack.length - 1) {
        b.endsWithBlank = true;
      } else if (b is _ListOpenBlock && i == _stack.length - 2) {
        if (b.items.isNotEmpty) {
          b.items.last.endsWithBlank = true;
        }
      }
    }
  }

  void _clearLastLineBlankUpTo(_OpenBlock node) {
    for (int i = _stack.length - 1; i >= 1; i--) {
      _stack[i].lastLineBlank = false;
      _stack[i].endsWithBlank = false;
    }
  }

  void _finalizeOpenBlock(_OpenBlock block) {
    block.isOpen = false;
    if (block is _ParagraphOpenBlock) {
      final String remaining = _extractLinkDefsFromParagraph(block);
      block.lines
        ..clear()
        ..add(remaining);
    } else if (block is _BlockQuoteOpenBlock) {
      // A blank line inside a blockquote (`>`) does not propagate out as a
      // blank line separating outer list items.
      block.endsWithBlank = false;
      _extendFromChildren(block, block.children);
    } else if (block is _ListItemOpenBlock) {
      _extendFromChildren(block, block.children);
      if (block.children.isNotEmpty &&
          block.children.last is _ListOpenBlock &&
          block.children.last.endsWithBlank) {
        block.endsWithBlank = true;
      }
      if (block.hasBlankBetweenChildren) {
        // Parent list becomes loose when item contains >= 2 direct blocks
        // separated by a blank line.
        final _OpenBlock parent = _stack.last;
        if (parent is _ListOpenBlock) {
          parent.tight = false;
        }
      }
    } else if (block is _ListOpenBlock) {
      _extendFromChildren(block, block.items);
      if (block.items.isNotEmpty && block.items.last.endsWithBlank) {
        block.endsWithBlank = true;
      }
      // Check item-to-item blank lines and internal child blank lines.
      for (int i = 0; i < block.items.length; i++) {
        final _ListItemOpenBlock item = block.items[i];
        if (item.hasBlankBetweenChildren) {
          block.tight = false;
          break;
        }
        if (i + 1 < block.items.length) {
          final _ListItemOpenBlock nextItem = block.items[i + 1];
          if (item.endsWithBlank ||
              (item.children.isNotEmpty && item.children.last.endsWithBlank)) {
            block.tight = false;
            break;
          }
          if (item.children.isEmpty &&
              item.startLine + 1 < nextItem.startLine) {
            block.tight = false;
            break;
          }
        }
      }
    } else if (block is _FootnoteDefOpenBlock) {
      _extendFromChildren(block, block.children);
    }

    if (_stack.length > 1) {
      final _OpenBlock parent = _stack.last;
      if (block.endOffset > parent.endOffset) {
        parent.endOffset = block.endOffset;
      }
      if (block.endLine > parent.endLine) {
        parent.endLine = block.endLine;
      }
    }
  }

  void _extendFromChildren(_OpenBlock parent, List<_OpenBlock> children) {
    if (children.isEmpty) {
      return;
    }
    final _OpenBlock last = children.last;
    if (last.endOffset > parent.endOffset) {
      parent.endOffset = last.endOffset;
    }
    if (last.endLine > parent.endLine) {
      parent.endLine = last.endLine;
    }
  }

  String _extractLinkDefsFromParagraph(_ParagraphOpenBlock para) {
    if (para.lines.isEmpty) {
      return '';
    }
    final String firstTrimmed = para.lines.first.trimLeft();
    if (firstTrimmed.isEmpty || firstTrimmed.codeUnitAt(0) != 0x5B) {
      return para.lines.length == 1
          ? para.lines.first.trimRight()
          : para.lines.join('\n').trimRight();
    }
    String text = para.lines.length == 1
        ? para.lines.first
        : para.lines.join('\n');
    while (text.isNotEmpty) {
      final _LinkDefMatch? match = _parseLeadingLinkDef(
        text,
        baseOffset: para.startOffset,
        baseLine: para.startLine,
      );
      if (match == null) {
        break;
      }
      final String norm = normalizeLinkLabel(match.label);
      if (norm.isNotEmpty &&
          _linkDefinitions.length < _maxLinkDefinitions &&
          !_linkDefinitions.containsKey(norm)) {
        _linkDefinitions[norm] = MarkdownLinkDefinition(
          label: match.label,
          normalizedLabel: norm,
          destination: match.destination,
          title: match.title,
          span: SourceSpan(
            startOffset: para.startOffset,
            endOffset: para.startOffset + match.consumedLength,
            startLine: para.startLine,
            endLine: para.startLine,
          ),
        );
      }
      text = text.substring(match.consumedLength);
    }
    return text.trimRight();
  }

  RawBlock? _buildBlock(_OpenBlock block, {required bool isTopLevel}) {
    final SourceSpan span = SourceSpan(
      startOffset: block.startOffset,
      endOffset: block.endOffset,
      startLine: block.startLine,
      endLine: block.endLine,
    );

    if (block is _ParagraphOpenBlock) {
      final String text =
          (block.lines.length == 1 ? block.lines.first : block.lines.join('\n'))
              .trimRight();
      if (text.isEmpty) {
        return null;
      }
      // Check abbreviation definition `*[ABBR]: Title`.
      if (options.abbreviations && isTopLevel && text.contains('*[')) {
        final String? remaining = _extractAbbreviationDefs(text);
        if (remaining == null) {
          return null;
        }
        if (remaining != text) {
          return RawParagraph(
            blockId: block.blockId,
            span: span,
            rawText: remaining,
            endsWithBlankLine: block.endsWithBlank,
          );
        }
      }
      return RawParagraph(
        blockId: block.blockId,
        span: span,
        rawText: text,
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _HeadingOpenBlock) {
      return RawHeading(
        blockId: block.blockId,
        span: span,
        level: block.level,
        rawText: block.rawText,
        isSetext: block.isSetext,
        explicitId: block.explicitId,
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _CodeOpenBlock) {
      if (block.isFenced) {
        final String literal = block.lines.isEmpty
            ? ''
            : '${block.lines.join('\n')}\n';
        final String unescapedInfo = unescapeMarkdownString(block.info.trim());
        final String? lang = _firstWordBeforeSpaceOrTab(unescapedInfo);
        return RawCodeBlock(
          blockId: block.blockId,
          span: span,
          info: unescapedInfo,
          language: lang,
          literal: literal,
          isFenced: true,
          codeUnitOffset: block.codeUnitOffset,
          endsWithBlankLine: block.endsWithBlank,
        );
      } else {
        int end = block.lines.length;
        while (end > 0 && block.lines[end - 1].trim().isEmpty) {
          end--;
        }
        final String literal = end == 0
            ? ''
            : '${block.lines.sublist(0, end).join('\n')}\n';
        return RawCodeBlock(
          blockId: block.blockId,
          span: span,
          info: '',
          language: null,
          literal: literal,
          isFenced: false,
          codeUnitOffset: block.codeUnitOffset,
          endsWithBlankLine: block.endsWithBlank,
        );
      }
    }

    if (block is _MathOpenBlock) {
      final String latex =
          block.singleLineLatex ?? block.lines.join('\n').trim();
      return RawMathBlock(
        blockId: block.blockId,
        span: span,
        latex: latex,
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _HtmlOpenBlock) {
      final String literal = '${block.lines.join('\n')}\n';
      return RawHtmlBlock(
        blockId: block.blockId,
        span: span,
        literal: literal,
        blockType: block.blockType,
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _ThematicBreakOpenBlock) {
      return RawThematicBreak(
        blockId: block.blockId,
        span: span,
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _TableOpenBlock) {
      final List<List<String>> frozenRows = <List<String>>[
        for (final List<String> row in block.rows) freezeList(row),
      ];
      return RawTable(
        blockId: block.blockId,
        span: span,
        alignments: freezeList(block.alignments),
        headerCells: freezeList(block.headerCells),
        rows: freezeList(frozenRows),
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _BlockQuoteOpenBlock) {
      final List<RawBlock> children = <RawBlock>[];
      for (final _OpenBlock c in block.children) {
        final RawBlock? built = _buildBlock(c, isTopLevel: false);
        if (built != null) {
          children.add(built);
        }
      }
      if (options.alerts) {
        final RawAlert? alert = _tryExtractAlert(
          blockId: block.blockId,
          span: span,
          children: children,
          endsWithBlank: block.endsWithBlank,
        );
        if (alert != null) {
          return alert;
        }
      }
      return RawBlockQuote(
        blockId: block.blockId,
        span: span,
        children: freezeList(children),
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _ListOpenBlock) {
      final List<RawListItem> items = <RawListItem>[];
      for (final _ListItemOpenBlock item in block.items) {
        final RawBlock? built = _buildBlock(item, isTopLevel: false);
        if (built is RawListItem) {
          items.add(built);
        }
      }
      return RawList(
        blockId: block.blockId,
        span: span,
        ordered: block.ordered,
        start: block.start,
        tight: block.tight,
        delimiter: block.delimiter,
        items: freezeList(items),
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _ListItemOpenBlock) {
      final List<RawBlock> children = <RawBlock>[];
      for (final _OpenBlock c in block.children) {
        final RawBlock? built = _buildBlock(c, isTopLevel: false);
        if (built != null) {
          children.add(built);
        }
      }
      bool? taskState;
      if (options.gfmTaskLists && children.isNotEmpty) {
        final RawBlock first = children.first;
        if (first is RawParagraph) {
          final ({bool checked, String rest})? task = _extractTaskMarker(
            first.rawText,
          );
          if (task != null) {
            taskState = task.checked;
            children[0] = RawParagraph(
              blockId: first.blockId,
              span: first.span,
              rawText: task.rest,
              endsWithBlankLine: first.endsWithBlankLine,
            );
          }
        }
      }
      return RawListItem(
        blockId: block.blockId,
        span: span,
        taskState: taskState,
        children: freezeList(children),
        endsWithBlankLine: block.endsWithBlank,
      );
    }

    if (block is _FootnoteDefOpenBlock) {
      final List<RawBlock> children = <RawBlock>[];
      for (final _OpenBlock c in block.children) {
        final RawBlock? built = _buildBlock(c, isTopLevel: false);
        if (built != null) {
          children.add(built);
        }
      }
      if (!_footnoteDefs.containsKey(block.label)) {
        _footnoteDefs[block.label] = RawFootnoteDef(
          blockId: block.blockId,
          span: span,
          label: block.label,
          children: freezeList(children),
          endsWithBlankLine: block.endsWithBlank,
        );
      }
      return null;
    }

    return null;
  }

  String? _extractAbbreviationDefs(String text) {
    final List<String> lines = text.split('\n');
    final List<String> remaining = <String>[];
    for (final String line in lines) {
      if (_abbreviations.length < _maxAbbreviations && line.contains('*[')) {
        final RegExpMatch? m = _abbrDefPattern.firstMatch(line.trim());
        if (m != null) {
          final String abbr = m.group(1)!.trim();
          final String title = m.group(2)!.trim();
          if (abbr.isNotEmpty) {
            _abbreviations[abbr] = title;
            continue;
          }
        }
      }
      remaining.add(line);
    }
    if (remaining.isEmpty) {
      return null;
    }
    return remaining.length == 1 ? remaining.first : remaining.join('\n');
  }

  List<RawBlock> _postProcessBlocks(List<RawBlock> blocks) {
    List<RawBlock> current = blocks;
    if (options.definitionLists) {
      current = _extractDefinitionLists(current);
    }
    if (options.detailsBlocks ||
        options.figureBlocks ||
        options.alignedBlocks) {
      current = _extractHtmlContainerExtensions(current);
    }
    return current;
  }

  List<RawBlock> _extractDefinitionLists(List<RawBlock> blocks) {
    final List<RawBlock> out = <RawBlock>[];
    int i = 0;
    while (i < blocks.length) {
      final RawBlock b = blocks[i];
      if (b is RawParagraph && b.rawText.contains('\n:')) {
        final List<String> lines = b.rawText.split('\n');
        int firstColonIdx = -1;
        for (int k = 1; k < lines.length; k++) {
          if (_isDefListStarterLine(lines[k])) {
            firstColonIdx = k;
            break;
          }
        }
        if (firstColonIdx >= 1) {
          final List<RawDefGroup> groups = <RawDefGroup>[];
          String term = lines.sublist(0, firstColonIdx).join('\n').trim();
          final List<List<RawBlock>> defs = <List<RawBlock>>[];
          final List<String> currentDefLines = <String>[];

          void flushDef() {
            if (currentDefLines.isNotEmpty &&
                (defs.isEmpty || _canOpenBlock())) {
              if (defs.isNotEmpty) {
                _blockCount++;
              }
              defs.add(<RawBlock>[
                RawParagraph(
                  blockId: _nextId('defp'),
                  span: b.span,
                  rawText: currentDefLines.join('\n').trim(),
                ),
              ]);
              currentDefLines.clear();
            } else {
              currentDefLines.clear();
            }
          }

          for (int k = firstColonIdx; k < lines.length; k++) {
            final String line = lines[k];
            if (line.startsWith(':')) {
              flushDef();
              currentDefLines.add(_stripColonPrefix(line));
            } else if (currentDefLines.isNotEmpty) {
              currentDefLines.add(line);
            } else {
              // New term inside same contiguous paragraph.
              term = line.trim();
            }
          }
          flushDef();

          // Attach indented code blocks or follow-up `: ...` paragraphs.
          int endOffset = b.span.endOffset;
          int endLine = b.span.endLine;
          int j = i + 1;
          while (j < blocks.length) {
            final RawBlock next = blocks[j];
            if (next is RawCodeBlock && !next.isFenced && defs.isNotEmpty) {
              final String bodyText = next.literal.trimRight();
              final int remainingBlocks = (budgets.maxBlocks - _blockCount) < 1
                  ? 1
                  : budgets.maxBlocks - _blockCount;
              final Phase1Result sub = parseBlocks(
                bodyText,
                options.copyWith(definitionLists: false, frontmatter: false),
                baseOffset: next.span.startOffset,
                baseLine: next.span.startLine,
                idPrefix: '${idPrefix}dlsub-${++_subIdCounter}-',
                budgetsOverride: budgets.copyWith(maxBlocks: remainingBlocks),
              );
              _blockCount += sub.totalBlockCount;
              defs.last.addAll(sub.blocks);
              endOffset = next.span.endOffset;
              endLine = next.span.endLine;
              j++;
              continue;
            }
            if (next is RawParagraph && next.rawText.startsWith(':')) {
              for (final String l in next.rawText.split('\n')) {
                if (l.startsWith(':')) {
                  if (!_canOpenBlock()) {
                    break;
                  }
                  _blockCount++;
                  defs.add(<RawBlock>[
                    RawParagraph(
                      blockId: _nextId('defp'),
                      span: next.span,
                      rawText: _stripColonPrefix(l),
                    ),
                  ]);
                } else if (defs.isNotEmpty && defs.last.last is RawParagraph) {
                  final RawParagraph prevP = defs.last.last as RawParagraph;
                  defs.last[defs.last.length - 1] = RawParagraph(
                    blockId: prevP.blockId,
                    span: next.span,
                    rawText: '${prevP.rawText}\n$l',
                  );
                }
              }
              endOffset = next.span.endOffset;
              endLine = next.span.endLine;
              j++;
              continue;
            }
            break;
          }

          final List<List<RawBlock>> frozenDefs = <List<RawBlock>>[
            for (final List<RawBlock> d in defs) freezeList(d),
          ];
          groups.add(
            RawDefGroup(
              termRaw: term,
              definitions: freezeList(frozenDefs),
              span: SourceSpan(
                startOffset: b.span.startOffset,
                endOffset: endOffset,
                startLine: b.span.startLine,
                endLine: endLine,
              ),
            ),
          );

          // Merge consecutive RawDefinitionList groups if adjacent.
          if (out.isNotEmpty && out.last is RawDefinitionList) {
            final RawDefinitionList prevList = out.last as RawDefinitionList;
            out[out.length - 1] = RawDefinitionList(
              blockId: prevList.blockId,
              span: SourceSpan(
                startOffset: prevList.span.startOffset,
                endOffset: endOffset,
                startLine: prevList.span.startLine,
                endLine: endLine,
              ),
              groups: freezeList(<RawDefGroup>[...prevList.groups, ...groups]),
            );
          } else {
            out.add(
              RawDefinitionList(
                blockId: _nextId('dl'),
                span: SourceSpan(
                  startOffset: b.span.startOffset,
                  endOffset: endOffset,
                  startLine: b.span.startLine,
                  endLine: endLine,
                ),
                groups: freezeList(groups),
              ),
            );
          }
          i = j;
          continue;
        }
      }
      out.add(b);
      i++;
    }
    return out;
  }

  List<RawBlock> _extractHtmlContainerExtensions(List<RawBlock> blocks) {
    final List<RawBlock> out = <RawBlock>[];
    int i = 0;
    while (i < blocks.length) {
      final RawBlock b = blocks[i];
      if (options.detailsBlocks && b is RawHtmlBlock) {
        final ({bool open, String summary})? openDetails = _parseDetailsOpen(
          b.literal,
        );
        if (openDetails != null) {
          final bool open = openDetails.open;
          String summary = openDetails.summary;
          final List<RawBlock> inner = <RawBlock>[];
          int j = i + 1;
          bool closed = false;
          while (j < blocks.length) {
            final RawBlock nb = blocks[j];
            if (nb is RawHtmlBlock && _isClosingTag(nb.literal, '</details>')) {
              closed = true;
              break;
            }
            if (summary.isEmpty && nb is RawHtmlBlock) {
              final String? sumBody = _extractTagBody(
                nb.literal,
                '<summary>',
                '</summary>',
              );
              if (sumBody != null) {
                summary = sumBody;
                j++;
                continue;
              }
            }
            inner.add(nb);
            j++;
          }
          if (closed) {
            out.add(
              RawDetailsBlock(
                blockId: _nextId('details'),
                span: SourceSpan(
                  startOffset: b.span.startOffset,
                  endOffset: blocks[j].span.endOffset,
                  startLine: b.span.startLine,
                  endLine: blocks[j].span.endLine,
                ),
                summaryRaw: summary,
                initiallyOpen: open,
                children: freezeList(inner),
              ),
            );
            i = j + 1;
            continue;
          }
        }
      }

      if (options.figureBlocks && b is RawHtmlBlock) {
        if (_isFigureOpen(b.literal)) {
          final List<RawBlock> inner = <RawBlock>[];
          String? caption;
          int j = i + 1;
          bool closed = false;
          while (j < blocks.length) {
            final RawBlock nb = blocks[j];
            if (nb is RawHtmlBlock && _isClosingTag(nb.literal, '</figure>')) {
              closed = true;
              break;
            }
            if (nb is RawHtmlBlock) {
              final String? capBody = _extractTagBody(
                nb.literal,
                '<figcaption>',
                '</figcaption>',
              );
              if (capBody != null) {
                caption = capBody;
                j++;
                continue;
              }
            }
            inner.add(nb);
            j++;
          }
          if (closed) {
            out.add(
              RawFigureBlock(
                blockId: _nextId('figure'),
                span: SourceSpan(
                  startOffset: b.span.startOffset,
                  endOffset: blocks[j].span.endOffset,
                  startLine: b.span.startLine,
                  endLine: blocks[j].span.endLine,
                ),
                children: freezeList(inner),
                captionRaw: caption,
              ),
            );
            i = j + 1;
            continue;
          }
        }
      }

      if (options.alignedBlocks && b is RawHtmlBlock) {
        final TableAlignment? align = _parseDivAlign(b.literal);
        if (align != null) {
          final List<RawBlock> inner = <RawBlock>[];
          int j = i + 1;
          bool closed = false;
          while (j < blocks.length) {
            final RawBlock nb = blocks[j];
            if (nb is RawHtmlBlock && _isClosingTag(nb.literal, '</div>')) {
              closed = true;
              break;
            }
            inner.add(nb);
            j++;
          }
          if (closed) {
            out.add(
              RawAlignedBlock(
                blockId: _nextId('align'),
                span: SourceSpan(
                  startOffset: b.span.startOffset,
                  endOffset: blocks[j].span.endOffset,
                  startLine: b.span.startLine,
                  endLine: blocks[j].span.endLine,
                ),
                alignment: align,
                children: freezeList(inner),
              ),
            );
            i = j + 1;
            continue;
          }
        }
      }

      out.add(b);
      i++;
    }
    return out;
  }

  RawAlert? _tryExtractAlert({
    required String blockId,
    required SourceSpan span,
    required List<RawBlock> children,
    required bool endsWithBlank,
  }) {
    if (children.isEmpty) {
      return null;
    }
    final RawBlock first = children.first;
    if (first is! RawParagraph || !first.rawText.startsWith('[!')) {
      return null;
    }
    final int nl = first.rawText.indexOf('\n');
    final String firstLine = nl == -1
        ? first.rawText
        : first.rawText.substring(0, nl);
    final RegExpMatch? match = _alertLinePattern.firstMatch(firstLine);
    if (match == null) {
      return null;
    }
    final String upper = match.group(1)!.toUpperCase();
    final (AlertKind kind, String title) = switch (upper) {
      'NOTE' => (AlertKind.note, 'Note'),
      'TIP' => (AlertKind.tip, 'Tip'),
      'IMPORTANT' => (AlertKind.important, 'Important'),
      'WARNING' => (AlertKind.warning, 'Warning'),
      'CAUTION' => (AlertKind.caution, 'Caution'),
      _ => (AlertKind.note, 'Note'),
    };

    final List<RawBlock> bodyChildren = <RawBlock>[];
    if (nl != -1) {
      bodyChildren.add(
        RawParagraph(
          blockId: first.blockId,
          span: first.span,
          rawText: first.rawText.substring(nl + 1),
          endsWithBlankLine: first.endsWithBlankLine,
        ),
      );
    }
    if (children.length > 1) {
      bodyChildren.addAll(children.sublist(1));
    }
    return RawAlert(
      blockId: blockId,
      span: span,
      kind: kind,
      title: title,
      children: freezeList(bodyChildren),
      endsWithBlankLine: endsWithBlank,
    );
  }

  ({bool checked, String rest})? _extractTaskMarker(String rawText) {
    if (rawText.length < 4 || rawText.codeUnitAt(0) != 0x5B) {
      return null;
    }
    final int stateCu = rawText.codeUnitAt(1);
    if (rawText.codeUnitAt(2) != 0x5D) {
      return null;
    }
    final int afterCu = rawText.codeUnitAt(3);
    if (afterCu != 0x20 && afterCu != 0x09) {
      return null;
    }
    if (stateCu == 0x20) {
      return (checked: false, rest: rawText.substring(4));
    }
    if (stateCu == 0x78 || stateCu == 0x58) {
      return (checked: true, rest: rawText.substring(4));
    }
    return null;
  }

  _AtxMatch? _matchAtxHeading(_LineCursor cursor) {
    final String text = cursor.restAfterNonSpace();
    int hashes = 0;
    while (hashes < text.length &&
        hashes < 7 &&
        text.codeUnitAt(hashes) == 0x23) {
      hashes++;
    }
    if (hashes == 0 || hashes > 6) {
      return null;
    }
    if (hashes < text.length) {
      final int after = text.codeUnitAt(hashes);
      if (after != 0x20 && after != 0x09) {
        return null;
      }
    }
    String content = text.substring(hashes);
    // Strip leading spaces/tabs.
    int start = 0;
    while (start < content.length &&
        (content.codeUnitAt(start) == 0x20 ||
            content.codeUnitAt(start) == 0x09)) {
      start++;
    }
    // Strip trailing spaces/tabs.
    int end = content.length;
    while (end > start &&
        (content.codeUnitAt(end - 1) == 0x20 ||
            content.codeUnitAt(end - 1) == 0x09)) {
      end--;
    }
    // Strip optional closing sequence of `#`s preceded by space/tab or at start.
    int hashEnd = end;
    while (hashEnd > start && content.codeUnitAt(hashEnd - 1) == 0x23) {
      hashEnd--;
    }
    if (hashEnd < end) {
      if (hashEnd == start) {
        end = start;
      } else if (content.codeUnitAt(hashEnd - 1) == 0x20 ||
          content.codeUnitAt(hashEnd - 1) == 0x09) {
        end = hashEnd;
        while (end > start &&
            (content.codeUnitAt(end - 1) == 0x20 ||
                content.codeUnitAt(end - 1) == 0x09)) {
          end--;
        }
      }
    }
    content = content.substring(start, end);
    final _SetextHeadingText parsed = _extractExplicitId(
      content,
      enabled: options.explicitHeadingIds,
    );
    return _AtxMatch(
      level: hashes,
      content: parsed.text,
      explicitId: parsed.explicitId,
    );
  }

  _SetextHeadingText _extractExplicitId(
    String content, {
    required bool enabled,
  }) {
    if (!enabled || content.length < 4) {
      return _SetextHeadingText(text: content, explicitId: null);
    }
    int end = content.length;
    while (end > 0) {
      final int cu = content.codeUnitAt(end - 1);
      if (cu != 0x20 && cu != 0x09) {
        break;
      }
      end--;
    }
    if (end < 4 || content.codeUnitAt(end - 1) != 0x7D) {
      return _SetextHeadingText(text: content, explicitId: null);
    }
    final int idEnd = end - 1;
    int i = idEnd - 1;
    while (i >= 0 && _isExplicitIdChar(content.codeUnitAt(i))) {
      i--;
    }
    if (i < 1 ||
        i + 1 >= idEnd ||
        content.codeUnitAt(i) != 0x23 ||
        content.codeUnitAt(i - 1) != 0x7B) {
      return _SetextHeadingText(text: content, explicitId: null);
    }
    return _SetextHeadingText(
      text: content.substring(0, i - 1).trimRight(),
      explicitId: content.substring(i + 1, idEnd),
    );
  }

  _FenceOpenMatch? _matchFenceOpen(_LineCursor cursor) {
    final String text = cursor.restAfterNonSpace();
    if (text.length < 3) {
      return null;
    }
    final int fenceChar = text.codeUnitAt(0);
    if (fenceChar != 0x60 && fenceChar != 0x7E) {
      return null;
    }
    int fenceLen = 0;
    while (fenceLen < text.length && text.codeUnitAt(fenceLen) == fenceChar) {
      fenceLen++;
    }
    if (fenceLen < 3) {
      return null;
    }
    final String info = text.substring(fenceLen);
    if (fenceChar == 0x60 && info.contains('`')) {
      return null;
    }
    return _FenceOpenMatch(
      fenceChar: fenceChar,
      fenceLength: fenceLen,
      indent: cursor.indent,
      info: info.trim(),
    );
  }

  bool _matchFenceClose(String text, int fenceChar, int minLength) {
    int i = 0;
    while (i < text.length && text.codeUnitAt(i) == fenceChar) {
      i++;
    }
    if (i < minLength) {
      return false;
    }
    while (i < text.length) {
      final int cu = text.codeUnitAt(i);
      if (cu != 0x20 && cu != 0x09) {
        return false;
      }
      i++;
    }
    return true;
  }

  _MathOpenMatch? _matchMathOpen(_LineCursor cursor) {
    final String text = cursor.restAfterNonSpace();
    if (!text.startsWith(r'$$')) {
      return null;
    }
    final String rest = text.substring(2).trim();
    if (rest.isEmpty) {
      return const _MathOpenMatch(singleLineLatex: null);
    }
    if (rest.endsWith(r'$$') && rest.length >= 2) {
      return _MathOpenMatch(
        singleLineLatex: rest.substring(0, rest.length - 2).trim(),
      );
    }
    return null;
  }

  bool _matchMathClose(String text) {
    if (!text.startsWith(r'$$')) {
      return false;
    }
    return text.substring(2).trim().isEmpty;
  }

  int? _matchSetextUnderlineSpan(String raw, int start) {
    if (start >= raw.length) {
      return null;
    }
    final int marker = raw.codeUnitAt(start);
    if (marker != 0x3D && marker != 0x2D) {
      return null;
    }
    int i = start;
    while (i < raw.length && raw.codeUnitAt(i) == marker) {
      i++;
    }
    while (i < raw.length) {
      final int cu = raw.codeUnitAt(i);
      if (cu != 0x20 && cu != 0x09) {
        return null;
      }
      i++;
    }
    return marker == 0x3D ? 1 : 2;
  }

  bool _matchThematicBreakSpan(String raw, int start) {
    if (raw.length - start < 3) {
      return false;
    }
    final int marker = raw.codeUnitAt(start);
    if (marker != 0x2A && marker != 0x2D && marker != 0x5F) {
      return false;
    }
    int count = 0;
    for (int i = start; i < raw.length; i++) {
      final int cu = raw.codeUnitAt(i);
      if (cu == marker) {
        count++;
      } else if (cu != 0x20 && cu != 0x09) {
        return false;
      }
    }
    return count >= 3;
  }

  _FootnoteStartMatch? _matchFootnoteStart(_LineCursor cursor) {
    final String text = cursor.restAfterNonSpace();
    if (text.length < 5 ||
        text.codeUnitAt(0) != 0x5B ||
        text.codeUnitAt(1) != 0x5E) {
      return null;
    }
    int i = 2;
    while (i < text.length) {
      final int cu = text.codeUnitAt(i);
      if (cu == 0x5D) {
        break;
      }
      if (cu == 0x5B || isAsciiWhitespace(cu)) {
        return null;
      }
      i++;
    }
    if (i <= 2 || i + 1 >= text.length || text.codeUnitAt(i) != 0x5D) {
      return null;
    }
    if (text.codeUnitAt(i + 1) != 0x3A) {
      return null;
    }
    final String label = text.substring(2, i);
    // Consume `[^label]:` plus optional whitespace after `:`.
    int afterColon = i + 2;
    while (afterColon < text.length &&
        (text.codeUnitAt(afterColon) == 0x20 ||
            text.codeUnitAt(afterColon) == 0x09)) {
      afterColon++;
    }
    return _FootnoteStartMatch(label: label, consumedChars: afterColon);
  }

  _ListMarkerMatch? _matchListMarker(
    _LineCursor cursor, {
    required bool interruptingParagraph,
  }) {
    final String raw = cursor.raw;
    final int startIdx = cursor.firstNonSpaceIndex;
    if (startIdx >= raw.length) {
      return null;
    }
    final int first = raw.codeUnitAt(startIdx);
    bool ordered = false;
    int start = 1;
    int markerChars = 0;
    int bulletChar = 0;
    String delimiter = '';

    if (first == 0x2D || first == 0x2B || first == 0x2A) {
      // Check that `-` or `*` isn't a thematic break on this line!
      if (_matchThematicBreakSpan(raw, startIdx)) {
        return null;
      }
      ordered = false;
      bulletChar = first;
      delimiter = first == 0x2D ? '-' : (first == 0x2B ? '+' : '*');
      markerChars = 1;
    } else if (isAsciiDigit(first)) {
      int digits = 0;
      int val = 0;
      while (startIdx + digits < raw.length &&
          digits < 9 &&
          isAsciiDigit(raw.codeUnitAt(startIdx + digits))) {
        val = val * 10 + (raw.codeUnitAt(startIdx + digits) - 0x30);
        digits++;
      }
      if (digits == 0 || startIdx + digits >= raw.length) {
        return null;
      }
      final int delimCu = raw.codeUnitAt(startIdx + digits);
      if (delimCu != 0x2E && delimCu != 0x29) {
        return null;
      }
      if (interruptingParagraph && val != 1) {
        return null;
      }
      ordered = true;
      start = val;
      delimiter = delimCu == 0x2E ? '.' : ')';
      markerChars = digits + 1;
    } else {
      return null;
    }

    // Must be followed by at least one space/tab or EOL.
    final int colAfterMarker = cursor.firstNonSpaceColumn + markerChars;
    int idx = startIdx + markerChars;
    int spaces = 0;
    int tempCol = colAfterMarker;
    while (idx < raw.length) {
      final int cu = raw.codeUnitAt(idx);
      if (cu == 0x20) {
        spaces++;
        tempCol++;
        idx++;
      } else if (cu == 0x09) {
        final int tabW = 4 - (tempCol % 4);
        spaces += tabW;
        tempCol += tabW;
        idx++;
      } else {
        break;
      }
    }

    final bool isBlankAfterMarker = idx >= raw.length;
    if (!isBlankAfterMarker && spaces == 0) {
      return null;
    }
    if (interruptingParagraph && isBlankAfterMarker) {
      return null;
    }

    final int consumedSpaces = (isBlankAfterMarker || spaces >= 5) ? 1 : spaces;
    return _ListMarkerMatch(
      ordered: ordered,
      start: start,
      delimiter: delimiter,
      bulletChar: bulletChar,
      indent: cursor.indent,
      markerChars: markerChars,
      padding: markerChars + consumedSpaces,
      spacesAfterMarkerConsumed: consumedSpaces,
    );
  }
}

final class _TableIntercept {
  const _TableIntercept(this.table);
  final _TableOpenBlock table;
}

final class _AtxMatch {
  const _AtxMatch({
    required this.level,
    required this.content,
    required this.explicitId,
  });

  final int level;
  final String content;
  final String? explicitId;
}

final class _SetextHeadingText {
  const _SetextHeadingText({required this.text, required this.explicitId});

  final String text;
  final String? explicitId;
}

final class _FenceOpenMatch {
  const _FenceOpenMatch({
    required this.fenceChar,
    required this.fenceLength,
    required this.indent,
    required this.info,
  });

  final int fenceChar;
  final int fenceLength;
  final int indent;
  final String info;
}

final class _MathOpenMatch {
  const _MathOpenMatch({required this.singleLineLatex});

  final String? singleLineLatex;
}

final class _FootnoteStartMatch {
  const _FootnoteStartMatch({required this.label, required this.consumedChars});

  final String label;
  final int consumedChars;
}

final class _ListMarkerMatch {
  const _ListMarkerMatch({
    required this.ordered,
    required this.start,
    required this.delimiter,
    required this.bulletChar,
    required this.indent,
    required this.markerChars,
    required this.padding,
    required this.spacesAfterMarkerConsumed,
  });

  final bool ordered;
  final int start;
  final String delimiter;
  final int bulletChar;
  final int indent;
  final int markerChars;
  final int padding;
  final int spacesAfterMarkerConsumed;
}

const int _maxLinkDefinitions = 65536;
const int _maxAbbreviations = 512;

final RegExp _abbrDefPattern = RegExp(r'^\*\[([^\]]+)\]:\s*(.+)$');
final RegExp _alertLinePattern = RegExp(
  r'^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*$',
  caseSensitive: false,
);
final RegExp _wordOpenPattern = RegExp(r'\bopen\b');
final RegExp _divAlignPattern = RegExp(
  r'''^<div\s+align\s*=\s*["']?(left|center|right)["']?\s*>$''',
  caseSensitive: false,
);

String? _firstWordBeforeSpaceOrTab(String text) {
  if (text.isEmpty) {
    return null;
  }
  for (int i = 0; i < text.length; i++) {
    final int cu = text.codeUnitAt(i);
    if (cu == 0x20 || cu == 0x09) {
      return i == 0 ? '' : text.substring(0, i);
    }
  }
  return text;
}

bool _isExplicitIdChar(int cu) {
  return (cu >= 0x41 && cu <= 0x5A) ||
      (cu >= 0x61 && cu <= 0x7A) ||
      (cu >= 0x30 && cu <= 0x39) ||
      cu == 0x5F ||
      cu == 0x2E ||
      cu == 0x3A ||
      cu == 0x2D;
}

bool _isRegExpWs(int cu) {
  return cu == 0x20 ||
      cu == 0x09 ||
      cu == 0x0A ||
      cu == 0x0D ||
      cu == 0x0B ||
      cu == 0x0C;
}

bool _isDefListStarterLine(String line) {
  if (line.isEmpty || line.codeUnitAt(0) != 0x3A) {
    return false;
  }
  return line.length == 1 || _isRegExpWs(line.codeUnitAt(1));
}

String _stripColonPrefix(String line) {
  int i = 1;
  int removedWs = 0;
  while (i < line.length && removedWs < 3 && _isRegExpWs(line.codeUnitAt(i))) {
    i++;
    removedWs++;
  }
  return line.substring(i);
}

bool _startsWithAsciiIgnoreCase(String s, int offset, String lowerPrefix) {
  if (offset + lowerPrefix.length > s.length) {
    return false;
  }
  for (int i = 0; i < lowerPrefix.length; i++) {
    int cu = s.codeUnitAt(offset + i);
    if (cu >= 0x41 && cu <= 0x5A) {
      cu += 0x20;
    }
    if (cu != lowerPrefix.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

bool _isClosingTag(String literal, String lowerTag) {
  final String trimmed = literal.trim();
  return trimmed.length == lowerTag.length &&
      _startsWithAsciiIgnoreCase(trimmed, 0, lowerTag);
}

String? _extractTagBody(String literal, String lowerOpen, String lowerClose) {
  final String trimmed = literal.trim();
  if (trimmed.length < lowerOpen.length + lowerClose.length ||
      !_startsWithAsciiIgnoreCase(trimmed, 0, lowerOpen) ||
      !_startsWithAsciiIgnoreCase(
        trimmed,
        trimmed.length - lowerClose.length,
        lowerClose,
      )) {
    return null;
  }
  return trimmed
      .substring(lowerOpen.length, trimmed.length - lowerClose.length)
      .trim();
}

({bool open, String summary})? _parseDetailsOpen(String literal) {
  final String trimmed = literal.trim();
  if (trimmed.length < 9 ||
      !_startsWithAsciiIgnoreCase(trimmed, 0, '<details')) {
    return null;
  }
  final int afterName = trimmed.codeUnitAt(8);
  if (afterName != 0x3E && !_isRegExpWs(afterName)) {
    return null;
  }
  final int gt = trimmed.indexOf('>', 8);
  if (gt == -1) {
    return null;
  }
  final bool open =
      gt > 8 &&
      _wordOpenPattern.hasMatch(trimmed.substring(8, gt).toLowerCase());
  int afterGt = gt + 1;
  while (afterGt < trimmed.length && _isRegExpWs(trimmed.codeUnitAt(afterGt))) {
    afterGt++;
  }
  if (afterGt >= trimmed.length) {
    return (open: open, summary: '');
  }
  final String? summary = _extractTagBody(
    trimmed.substring(afterGt),
    '<summary>',
    '</summary>',
  );
  if (summary == null) {
    return null;
  }
  return (open: open, summary: summary);
}

bool _isFigureOpen(String literal) {
  final String trimmed = literal.trim();
  if (trimmed.length < 8 ||
      !_startsWithAsciiIgnoreCase(trimmed, 0, '<figure') ||
      !trimmed.endsWith('>')) {
    return false;
  }
  final int afterName = trimmed.codeUnitAt(7);
  if (afterName != 0x3E && !_isRegExpWs(afterName)) {
    return false;
  }
  return trimmed.indexOf('>', 7) == trimmed.length - 1;
}

TableAlignment? _parseDivAlign(String literal) {
  final String trimmed = literal.trim();
  if (trimmed.length < 16 ||
      trimmed.length > 64 ||
      !_startsWithAsciiIgnoreCase(trimmed, 0, '<div') ||
      !trimmed.endsWith('>')) {
    return null;
  }
  final RegExpMatch? m = _divAlignPattern.firstMatch(trimmed);
  if (m == null) {
    return null;
  }
  return switch (m.group(1)!.toLowerCase()) {
    'left' => TableAlignment.left,
    'center' => TableAlignment.center,
    'right' => TableAlignment.right,
    _ => null,
  };
}

// =============================================================================
// HTML Block Condition Matching (CommonMark 0.31.2 Section 4.6)
// =============================================================================

final RegExp _htmlType1Open = RegExp(
  r'^<(?:pre|script|style|textarea)(?:[\x20\x09>]|$)',
  caseSensitive: false,
);

final RegExp _htmlType1Close = RegExp(
  r'</(?:pre|script|style|textarea)>',
  caseSensitive: false,
);

final RegExp _htmlType4Open = RegExp(r'^<![A-Za-z]');

final RegExp _htmlType6Open = RegExp(
  r'^</?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:[\x20\x09]|/?>|$)',
  caseSensitive: false,
);

bool _isHtmlTagNameStart(int cu) =>
    (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A);

bool _isHtmlTagNameChar(int cu) =>
    _isHtmlTagNameStart(cu) || (cu >= 0x30 && cu <= 0x39) || cu == 0x2D;

bool _isHtmlAttrNameStart(int cu) =>
    _isHtmlTagNameStart(cu) || cu == 0x5F || cu == 0x3A;

bool _isHtmlAttrNameChar(int cu) =>
    _isHtmlTagNameChar(cu) || cu == 0x5F || cu == 0x3A || cu == 0x2E;

/// Linear-time Type 7 HTML open/close block matcher (CommonMark 0.31.2 §4.6).
bool _isHtmlType7Open(String rest) {
  final int len = rest.length;
  if (len < 3 || rest.codeUnitAt(0) != 0x3C) {
    return false;
  }
  int i = 1;
  if (rest.codeUnitAt(i) == 0x2F) {
    i++;
    if (i >= len || !_isHtmlTagNameStart(rest.codeUnitAt(i))) {
      return false;
    }
    i++;
    while (i < len && _isHtmlTagNameChar(rest.codeUnitAt(i))) {
      i++;
    }
    while (i < len &&
        (rest.codeUnitAt(i) == 0x20 || rest.codeUnitAt(i) == 0x09)) {
      i++;
    }
    if (i >= len || rest.codeUnitAt(i) != 0x3E) {
      return false;
    }
    i++;
    while (i < len) {
      final int cu = rest.codeUnitAt(i);
      if (cu != 0x20 && cu != 0x09) {
        return false;
      }
      i++;
    }
    return true;
  }

  if (!_isHtmlTagNameStart(rest.codeUnitAt(i))) {
    return false;
  }
  i++;
  while (i < len && _isHtmlTagNameChar(rest.codeUnitAt(i))) {
    i++;
  }
  while (i < len) {
    int ws = 0;
    while (i < len &&
        (rest.codeUnitAt(i) == 0x20 || rest.codeUnitAt(i) == 0x09)) {
      i++;
      ws++;
    }
    if (i >= len) {
      return false;
    }
    final int cu = rest.codeUnitAt(i);
    if (cu == 0x2F) {
      i++;
      if (i >= len || rest.codeUnitAt(i) != 0x3E) {
        return false;
      }
      i++;
      break;
    }
    if (cu == 0x3E) {
      i++;
      break;
    }
    if (ws == 0 || !_isHtmlAttrNameStart(cu)) {
      return false;
    }
    i++;
    while (i < len && _isHtmlAttrNameChar(rest.codeUnitAt(i))) {
      i++;
    }
    int eqWs = i;
    while (eqWs < len &&
        (rest.codeUnitAt(eqWs) == 0x20 || rest.codeUnitAt(eqWs) == 0x09)) {
      eqWs++;
    }
    if (eqWs < len && rest.codeUnitAt(eqWs) == 0x3D) {
      i = eqWs + 1;
      while (i < len &&
          (rest.codeUnitAt(i) == 0x20 || rest.codeUnitAt(i) == 0x09)) {
        i++;
      }
      if (i >= len) {
        return false;
      }
      final int q = rest.codeUnitAt(i);
      if (q == 0x22 || q == 0x27) {
        i++;
        while (i < len) {
          final int ch = rest.codeUnitAt(i);
          if (ch == 0x0A || ch == 0x0D) {
            return false;
          }
          if (ch == q) {
            break;
          }
          i++;
        }
        if (i >= len) {
          return false;
        }
        i++;
      } else {
        int valLen = 0;
        while (i < len) {
          final int ch = rest.codeUnitAt(i);
          if (ch == 0x20 ||
              ch == 0x09 ||
              ch == 0x0A ||
              ch == 0x0D ||
              ch == 0x22 ||
              ch == 0x27 ||
              ch == 0x3D ||
              ch == 0x3C ||
              ch == 0x3E ||
              ch == 0x60) {
            break;
          }
          i++;
          valLen++;
        }
        if (valLen == 0) {
          return false;
        }
      }
    }
  }
  if (i == 0 || rest.codeUnitAt(i - 1) != 0x3E) {
    return false;
  }
  while (i < len) {
    final int cu = rest.codeUnitAt(i);
    if (cu != 0x20 && cu != 0x09) {
      return false;
    }
    i++;
  }
  return true;
}

int? _matchHtmlBlockStart(String rest, {required bool allowType7}) {
  if (rest.isEmpty || rest.codeUnitAt(0) != 0x3C) {
    return null;
  }
  if (_htmlType1Open.hasMatch(rest)) {
    return 1;
  }
  if (rest.startsWith('<!--')) {
    return 2;
  }
  if (rest.startsWith('<?')) {
    return 3;
  }
  if (_htmlType4Open.hasMatch(rest)) {
    return 4;
  }
  if (rest.startsWith('<![CDATA[')) {
    return 5;
  }
  if (_htmlType6Open.hasMatch(rest)) {
    return 6;
  }
  if (allowType7 && _isHtmlType7Open(rest)) {
    return 7;
  }
  return null;
}

bool _matchHtmlBlockEnd(int blockType, String line) {
  switch (blockType) {
    case 1:
      return _htmlType1Close.hasMatch(line);
    case 2:
      return line.contains('-->');
    case 3:
      return line.contains('?>');
    case 4:
      return line.contains('>');
    case 5:
      return line.contains(']]>');
    default:
      return false;
  }
}

// =============================================================================
// Link Reference Definition Parser (CommonMark 0.31.2 Section 4.7)
// =============================================================================

final class _LinkDefMatch {
  const _LinkDefMatch({
    required this.label,
    required this.destination,
    required this.title,
    required this.consumedLength,
  });

  final String label;
  final String destination;
  final String? title;
  final int consumedLength;
}

_LinkDefMatch? _parseLeadingLinkDef(
  String text, {
  required int baseOffset,
  required int baseLine,
}) {
  final int len = text.length;
  int i = 0;
  // Optional 0-3 spaces already stripped on first line of paragraph, check anyway.
  int spaces = 0;
  while (i < len && spaces < 3 && text.codeUnitAt(i) == 0x20) {
    i++;
    spaces++;
  }
  if (i >= len || text.codeUnitAt(i) != 0x5B) {
    return null;
  }
  i++;
  final int labelStart = i;
  int labelLength = 0;
  bool hasNonSpace = false;
  while (i < len) {
    final int cu = text.codeUnitAt(i);
    if (cu == 0x5C && i + 1 < len) {
      final int next = text.codeUnitAt(i + 1);
      if (isAsciiPunctuation(next)) {
        labelLength += 2;
        hasNonSpace = true;
        i += 2;
        if (labelLength > 999) {
          return null;
        }
        continue;
      }
    }
    if (cu == 0x5B) {
      return null;
    }
    if (cu == 0x5D) {
      break;
    }
    if (!isAsciiWhitespace(cu)) {
      hasNonSpace = true;
    }
    labelLength++;
    if (labelLength > 999) {
      return null;
    }
    i++;
  }
  if (i >= len || text.codeUnitAt(i) != 0x5D || !hasNonSpace) {
    return null;
  }
  final String label = text.substring(labelStart, i);
  i++;
  if (i >= len || text.codeUnitAt(i) != 0x3A) {
    return null;
  }
  i++;

  // Optional spaces/tabs and up to one newline.
  final ({int index, bool crossedNewline, bool hadWhitespace}) ws1 =
      _skipOptSpacesAndOneNewline(text, i);
  i = ws1.index;
  if (i >= len) {
    return null;
  }

  // Parse link destination.
  final ({String destination, int nextIndex})? dest = _parseLinkDestination(
    text,
    i,
  );
  if (dest == null) {
    return null;
  }
  i = dest.nextIndex;
  final int afterDestIndex = i;

  // Check if followed by whitespace/newline and optional title.
  final ({int index, bool crossedNewline, bool hadWhitespace}) ws2 =
      _skipOptSpacesAndOneNewline(text, i);

  int endWithoutTitle = afterDestIndex;
  // Verify end of line after destination if no title is parsed.
  final int? eolAfterDest = _consumeSpacesToLineEnd(text, afterDestIndex);

  String? title;
  int consumed = -1;

  if (ws2.hadWhitespace && ws2.index < len) {
    final int tStart = ws2.index;
    final int openCu = text.codeUnitAt(tStart);
    if (openCu == 0x22 || openCu == 0x27 || openCu == 0x28) {
      final ({String title, int nextIndex})? parsedTitle = _parseLinkTitle(
        text,
        tStart,
      );
      if (parsedTitle != null) {
        final int? eolAfterTitle = _consumeSpacesToLineEnd(
          text,
          parsedTitle.nextIndex,
        );
        if (eolAfterTitle != null) {
          title = unescapeMarkdownString(parsedTitle.title);
          consumed = eolAfterTitle;
        }
      }
    }
  }

  if (consumed == -1) {
    if (eolAfterDest == null) {
      return null;
    }
    endWithoutTitle = eolAfterDest;
    consumed = endWithoutTitle;
  }

  return _LinkDefMatch(
    label: label,
    destination: unescapeMarkdownString(dest.destination),
    title: title,
    consumedLength: consumed,
  );
}

({int index, bool crossedNewline, bool hadWhitespace})
_skipOptSpacesAndOneNewline(String text, int start) {
  int i = start;
  bool crossed = false;
  bool hadWs = false;
  while (i < text.length) {
    final int cu = text.codeUnitAt(i);
    if (cu == 0x20 || cu == 0x09) {
      hadWs = true;
      i++;
    } else if (cu == 0x0A && !crossed) {
      hadWs = true;
      crossed = true;
      i++;
    } else {
      break;
    }
  }
  return (index: i, crossedNewline: crossed, hadWhitespace: hadWs);
}

int? _consumeSpacesToLineEnd(String text, int start) {
  int i = start;
  while (i < text.length) {
    final int cu = text.codeUnitAt(i);
    if (cu == 0x20 || cu == 0x09) {
      i++;
    } else if (cu == 0x0A) {
      return i + 1;
    } else {
      return null;
    }
  }
  return i;
}

({String destination, int nextIndex})? _parseLinkDestination(
  String text,
  int start,
) {
  final int len = text.length;
  if (start >= len) {
    return null;
  }
  if (text.codeUnitAt(start) == 0x3C) {
    int i = start + 1;
    final StringBuffer out = StringBuffer();
    while (i < len) {
      final int cu = text.codeUnitAt(i);
      if (cu == 0x0A || cu == 0x0D || cu == 0x3C) {
        return null;
      }
      if (cu == 0x5C && i + 1 < len) {
        final int next = text.codeUnitAt(i + 1);
        if (isAsciiPunctuation(next)) {
          out
            ..writeCharCode(cu)
            ..writeCharCode(next);
          i += 2;
          continue;
        }
      }
      if (cu == 0x3E) {
        return (destination: out.toString(), nextIndex: i + 1);
      }
      out.writeCharCode(cu);
      i++;
    }
    return null;
  }

  // Unbracketed destination.
  int i = start;
  int parenDepth = 0;
  while (i < len) {
    final int cu = text.codeUnitAt(i);
    if (isAsciiControl(cu) || cu == 0x20) {
      break;
    }
    if (cu == 0x5C && i + 1 < len) {
      final int next = text.codeUnitAt(i + 1);
      if (isAsciiPunctuation(next)) {
        i += 2;
        continue;
      }
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
  if (i == start || parenDepth != 0) {
    return null;
  }
  return (destination: text.substring(start, i), nextIndex: i);
}

({String title, int nextIndex})? _parseLinkTitle(String text, int start) {
  final int len = text.length;
  if (start >= len) {
    return null;
  }
  final int open = text.codeUnitAt(start);
  final int close = open == 0x28 ? 0x29 : open;
  int i = start + 1;
  while (i < len) {
    final int cu = text.codeUnitAt(i);
    if (cu == 0x5C && i + 1 < len) {
      final int next = text.codeUnitAt(i + 1);
      if (isAsciiPunctuation(next)) {
        i += 2;
        continue;
      }
    }
    if (cu == close) {
      return (title: text.substring(start + 1, i), nextIndex: i + 1);
    }
    if (open == 0x28 && cu == 0x28) {
      return null;
    }
    i++;
  }
  return null;
}

// =============================================================================
// GFM Table Parsing Helpers
// =============================================================================

List<TableAlignment>? _matchTableDelimiterRowSpan(
  String raw,
  int start, {
  required int maxColumns,
}) {
  int end = raw.length;
  while (end > start) {
    final int cu = raw.codeUnitAt(end - 1);
    if (cu != 0x20 && cu != 0x09) {
      break;
    }
    end--;
  }
  if (end <= start) {
    return null;
  }
  bool hasDash = false;
  for (int i = start; i < end; i++) {
    final int cu = raw.codeUnitAt(i);
    if (cu == 0x2D) {
      hasDash = true;
    } else if (cu != 0x7C && cu != 0x3A && cu != 0x20 && cu != 0x09) {
      return null;
    }
  }
  if (!hasDash) {
    return null;
  }
  int s = start;
  int e = end;
  if (raw.codeUnitAt(s) == 0x7C) {
    s++;
  }
  if (e > s && raw.codeUnitAt(e - 1) == 0x7C) {
    e--;
  }
  final List<TableAlignment> alignments = <TableAlignment>[];
  int cellStart = s;
  for (int i = s; i <= e; i++) {
    if (i == e || raw.codeUnitAt(i) == 0x7C) {
      int cs = cellStart;
      int ce = i;
      while (cs < ce &&
          (raw.codeUnitAt(cs) == 0x20 || raw.codeUnitAt(cs) == 0x09)) {
        cs++;
      }
      while (ce > cs &&
          (raw.codeUnitAt(ce - 1) == 0x20 || raw.codeUnitAt(ce - 1) == 0x09)) {
        ce--;
      }
      if (cs >= ce) {
        return null;
      }
      final bool leftColon = raw.codeUnitAt(cs) == 0x3A;
      final bool rightColon = raw.codeUnitAt(ce - 1) == 0x3A;
      final int innerStart = leftColon ? cs + 1 : cs;
      final int innerEnd = rightColon ? ce - 1 : ce;
      if (innerEnd <= innerStart) {
        return null;
      }
      for (int k = innerStart; k < innerEnd; k++) {
        if (raw.codeUnitAt(k) != 0x2D) {
          return null;
        }
      }
      if (alignments.length >= maxColumns) {
        return null;
      }
      if (leftColon && rightColon) {
        alignments.add(TableAlignment.center);
      } else if (leftColon) {
        alignments.add(TableAlignment.left);
      } else if (rightColon) {
        alignments.add(TableAlignment.right);
      } else {
        alignments.add(TableAlignment.none);
      }
      cellStart = i + 1;
    }
  }
  return alignments.isEmpty ? null : alignments;
}

/// Splits a pipe-delimited GFM table row into trimmed cells, unescaping `\|`
/// to `|` per `cmark-gfm` (`S_row_from_string`) while leaving `\\|` as `\\` +
/// cell separator. Stops once [maxColumns] cells are extracted.
List<String> _splitTableRow(
  String line, {
  bool unescapePipes = true,
  int? maxColumns,
}) {
  int start = 0;
  int end = line.length;
  while (start < end && isAsciiWhitespace(line.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isAsciiWhitespace(line.codeUnitAt(end - 1))) {
    end--;
  }
  if (start < end && line.codeUnitAt(start) == 0x7C) {
    start++;
  }
  // Check trailing unescaped pipe.
  if (end > start && line.codeUnitAt(end - 1) == 0x7C) {
    int backslashes = 0;
    int k = end - 2;
    while (k >= start && line.codeUnitAt(k) == 0x5C) {
      backslashes++;
      k--;
    }
    if (backslashes.isEven) {
      end--;
    }
  }

  final List<String> cells = <String>[];
  StringBuffer? current;
  int cellSliceStart = start;
  int i = start;
  while (i < end) {
    final int cu = line.codeUnitAt(i);
    if (cu == 0x5C && i + 1 < end) {
      final int next = line.codeUnitAt(i + 1);
      if (next == 0x7C || next == 0x5C) {
        current ??= StringBuffer();
        if (i > cellSliceStart) {
          current.write(line.substring(cellSliceStart, i));
        }
        if (next == 0x7C) {
          current.write(unescapePipes ? '|' : r'\|');
        } else {
          current.write(r'\\');
        }
        i += 2;
        cellSliceStart = i;
        continue;
      }
    }
    if (cu == 0x7C) {
      final String cellText;
      if (current == null) {
        cellText = line.substring(cellSliceStart, i).trim();
      } else {
        if (i > cellSliceStart) {
          current.write(line.substring(cellSliceStart, i));
        }
        cellText = current.toString().trim();
        current.clear();
      }
      cells.add(cellText);
      if (maxColumns != null && cells.length >= maxColumns) {
        return cells;
      }
      i++;
      cellSliceStart = i;
      continue;
    }
    i++;
  }
  if (maxColumns == null || cells.length < maxColumns) {
    final String cellText;
    if (current == null) {
      cellText = line.substring(cellSliceStart, end).trim();
    } else {
      if (end > cellSliceStart) {
        current.write(line.substring(cellSliceStart, end));
      }
      cellText = current.toString().trim();
    }
    cells.add(cellText);
  }
  return cells;
}
