import 'dart:collection';
import 'dart:typed_data';

import 'ast.dart';
import 'ast_walkers.dart';
import 'block_parser.dart';
import 'budgets.dart';
import 'document.dart';
import 'engine.dart';
import 'inline_parser.dart';
import 'options.dart';

final class _PrefixedBlockList extends ListBase<MarkdownBlockNode>
    with PackageUnmodifiableListMixin<MarkdownBlockNode> {
  _PrefixedBlockList(this._prefix, this._prefixLength, this._suffix);

  final List<MarkdownBlockNode> _prefix;
  final int _prefixLength;
  final List<MarkdownBlockNode> _suffix;

  @override
  bool get isEmpty => false;

  @override
  bool get isNotEmpty => true;

  @override
  int get length => _prefixLength + _suffix.length;

  @override
  MarkdownBlockNode operator [](int index) {
    return index < _prefixLength
        ? _prefix[index]
        : _suffix[index - _prefixLength];
  }
}

final Uint8List _streamBlockStarterLut = _buildStreamBlockStarterLut();

Uint8List _buildStreamBlockStarterLut() {
  final Uint8List lut = Uint8List(128);
  lut[0x3E] = 1; // '>'
  lut[0x23] = 1; // '#'
  lut[0x60] = 1; // '`'
  lut[0x7E] = 1; // '~'
  lut[0x24] = 1; // '$'
  lut[0x5C] = 1; // '\'
  lut[0x3C] = 1; // '<'
  lut[0x3D] = 1; // '='
  lut[0x2D] = 1; // '-'
  lut[0x7C] = 1; // '|'
  lut[0x3A] = 1; // ':'
  lut[0x2A] = 1; // '*'
  lut[0x5F] = 1; // '_'
  lut[0x5B] = 1; // '['
  lut[0x2B] = 1; // '+'
  for (int c = 0x30; c <= 0x39; c++) {
    lut[c] = 1; // '0'..'9'
  }
  return lut;
}

/// Incremental streaming Markdown parser tailored for token-by-token feeds such
/// as LLM completions, freezing settled top-level blocks and re-parsing only
/// the active trailing slice on each chunk.
final class StreamingMarkdownController {
  /// Creates a [StreamingMarkdownController].
  StreamingMarkdownController({
    this.engine = const MarkdownEngine(),
    MarkdownOptions? options,
  }) : _options = options {
    _currentDocument = createFrozenDocument(
      source: '',
      options: effectiveOptions,
      blocks: emptyFrozenBlockList,
      outline: const <MarkdownOutlineItem>[],
      footnotes: const <FootnoteDefinitionNode>[],
      remoteImageAddresses: const <String>[],
      normalizedSource: '',
      html: '',
    );
  }

  static const List<String> _settledIdPrefixes = <String>[
    's0-',
    's1-',
    's2-',
    's3-',
    's4-',
    's5-',
    's6-',
    's7-',
    's8-',
    's9-',
    's10-',
    's11-',
    's12-',
    's13-',
    's14-',
    's15-',
    's16-',
    's17-',
    's18-',
    's19-',
    's20-',
    's21-',
    's22-',
    's23-',
    's24-',
    's25-',
    's26-',
    's27-',
    's28-',
    's29-',
    's30-',
    's31-',
  ];

  /// Engine used for parsing active slices and final reconciliation.
  final MarkdownEngine engine;

  final MarkdownOptions? _options;

  static const int _fastNone = 0;
  static const int _fastPara = 1;
  static const int _fastCode = 2;
  static const int _fastQuote = 3;
  static const int _fastList = 4;
  static const int _fastTable = 5;

  List<String> _rawChunks = <String>[];
  int _rawLength = 0;
  String _tail = '';
  List<MarkdownBlockNode> _settledBlocks = <MarkdownBlockNode>[];
  bool _settledShared = false;
  List<MarkdownBlockNode> _settledSnapshot = emptyFrozenBlockList;
  bool _settledSnapshotDirty = false;
  List<MarkdownBlockNode> _activeBlocks = emptyFrozenBlockList;
  int _safeSettledCount = 0;
  int _settledOffset = 0;
  int _settledLine = 1;
  int _tailGroupId = 0;
  String _tailIdPrefix = '';
  MarkdownFrontmatter? _frontmatter;
  bool _hasDefinitions = false;
  bool _isFinished = false;
  bool _pendingCr = false;
  bool _sawNormalization = false;
  int _fastTailKind = _fastNone;
  int _fastParaRawStart = 0;
  int _fastCodeBodyStart = 0;
  int _fastCodeFenceChar = 0;
  bool _fastCodeEndedWithNl = false;
  int _fastTableLastLineStart = 0;
  bool _fastTableEndedWithNl = false;
  List<String> _settledHeadingTexts = <String>[];
  final List<void Function()> _listeners = <void Function()>[];
  bool _isDisposed = false;
  late MarkdownDocument _currentDocument;
  ReusableBlockInlineResolver? _reusableBlockResolver;
  ReusableNormalizedBlockParser? _reusableBlockParser;

  /// Effective [MarkdownOptions] used by this controller.
  MarkdownOptions get effectiveOptions => _options ?? engine.defaultOptions;

  ReusableBlockInlineResolver get _blockInlineResolver =>
      _reusableBlockResolver ??= ReusableBlockInlineResolver(effectiveOptions);

  ReusableNormalizedBlockParser get _blockParser =>
      _reusableBlockParser ??= ReusableNormalizedBlockParser(effectiveOptions);

  /// Raw accumulated Markdown source text received so far.
  String get buffer {
    if (_rawChunks.isEmpty) {
      return '';
    }
    if (_rawChunks.length == 1) {
      return _rawChunks[0];
    }
    return _rawChunks.join();
  }

  /// Current incremental [MarkdownDocument] snapshot.
  MarkdownDocument get currentDocument => _currentDocument;

  /// Alias for [currentDocument].
  MarkdownDocument get document => _currentDocument;

  /// Frozen top-level blocks already finalized earlier in the stream.
  List<MarkdownBlockNode> get settledBlocks => _settledBlocksView();

  /// Trailing active blocks currently open/re-parsed on new chunks.
  List<MarkdownBlockNode> get activeBlocks => _activeBlocks;

  /// Count of settled top-level blocks currently frozen.
  int get settledBlockCount => _settledBlocks.length;

  /// Exact prefix length of `currentDocument.blocks` whose block objects are
  /// frozen and identical by reference across subsequent active-tail chunks.
  ///
  /// Returns `0` when no blocks have settled yet or when link, footnote, or
  /// abbreviation definitions force full-document reparsing during active
  /// streaming (`!isFinished`). When positive, `0 <= settledPrefixBlockCount <=
  /// currentDocument.blocks.length`, every index `0 <= i < settledPrefixBlockCount`
  /// satisfies `identical(currentDocument.blocks[i], settledBlocks[i])`
  /// (inclusive of any leading [FrontmatterNode] when `options.frontmatter` is
  /// enabled), and `currentDocument.blocks.sublist(settledPrefixBlockCount)`
  /// matches `activeBlocks`. After [finish] completes without a subsequent
  /// [append], [replaceText], or [reset], this equals
  /// `currentDocument.blocks.length`.
  int get settledPrefixBlockCount {
    if (_hasDefinitions && !_isFinished) {
      return 0;
    }
    final int docLen = rawDocumentBlocks(_currentDocument).length;
    return _settledBlocks.length <= docLen ? _settledBlocks.length : docLen;
  }

  /// Whether [finish] has been called without a subsequent [reset].
  bool get isFinished => _isFinished;

  /// Rendered HTML for the current document state.
  String get html => _currentDocument.toHtml();

  /// Registers a callback notified whenever [append], [replaceText], [finish],
  /// or [reset] updates the controller state.
  void addListener(void Function() listener) {
    if (_isDisposed) {
      return;
    }
    _listeners.add(listener);
  }

  /// Removes a previously registered [listener].
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Releases registered listeners.
  void dispose() {
    _isDisposed = true;
    _listeners.clear();
  }

  @pragma('vm:never-inline')
  void _notifyListeners() {
    if (_listeners.isEmpty) {
      return;
    }
    final List<void Function()> snapshot = List<void Function()>.of(_listeners);
    for (final void Function() listener in snapshot) {
      listener();
    }
  }

  List<MarkdownBlockNode> _settledBlocksView() {
    if (_settledSnapshotDirty) {
      _settledSnapshotDirty = false;
      _settledSnapshot = _settledBlocks.isEmpty
          ? emptyFrozenBlockList
          : freezeFreshList(List<MarkdownBlockNode>.of(_settledBlocks));
    }
    return _settledSnapshot;
  }

  void _resetSettledBlocks() {
    if (_settledShared) {
      _settledBlocks = <MarkdownBlockNode>[];
      _settledShared = false;
    } else {
      _settledBlocks.clear();
    }
  }

  void _truncateSettledBlocks(int targetLen) {
    if (_settledShared) {
      _settledBlocks = _settledBlocks.sublist(0, targetLen);
      _settledShared = false;
    } else {
      _settledBlocks.length = targetLen;
    }
  }

  @pragma('vm:prefer-inline')
  List<MarkdownBlockNode> _buildAllBlocks() {
    final int settledLen = _settledBlocks.length;
    if (settledLen == 0) {
      return _activeBlocks;
    }
    if (_activeBlocks.isEmpty) {
      return _settledBlocksView();
    }
    _settledShared = true;
    return _PrefixedBlockList(_settledBlocks, settledLen, _activeBlocks);
  }

  @pragma('vm:never-inline')
  static Never _throwInputLimit(int nextLen, int maxLen) {
    throw RangeError.value(
      nextLen,
      'buffer.length',
      'Input exceeds maxInputLength ($maxLen).',
    );
  }

  static bool _hasSafeFastBudgets(MarkdownOptions opts, int nextTailLen) {
    final MarkdownBudgets budgets = opts.effectiveBudgets;
    return budgets.maxTokens >= 4096 &&
        budgets.maxOutputBytes >= 16384 &&
        nextTailLen * 4 < budgets.maxTokens &&
        nextTailLen * 16 < budgets.maxOutputBytes;
  }

  static String _extractFastInlineSlice(String nextTail, int rawStart) {
    final int tailLen = nextTail.length;
    if (rawStart >= tailLen) {
      return '';
    }
    final int lastCu = nextTail.codeUnitAt(tailLen - 1);
    final bool cleanEnd = lastCu > 0x20 && lastCu < 0x80;
    if (rawStart == 0 && cleanEnd) {
      return nextTail;
    }
    final String slice = rawStart == 0
        ? nextTail
        : nextTail.substring(rawStart);
    return cleanEnd ? slice : slice.trimRight();
  }

  static bool _startsWithTablePipe(String s, int start, int end) {
    int i = start;
    int indent = 0;
    while (i < end) {
      final int cu = s.codeUnitAt(i);
      if (cu == 0x20) {
        indent++;
        if (indent > 3) {
          return false;
        }
        i++;
      } else if (cu == 0x09) {
        indent += 4 - (indent % 4);
        if (indent > 3) {
          return false;
        }
        i++;
      } else {
        return cu == 0x7C;
      }
    }
    return false;
  }

  bool _appendFastPara(
    String chunk,
    MarkdownOptions opts, {
    required bool trailingNewline,
  }) {
    final int nextLen = _tail.length + chunk.length;
    if (!_hasSafeFastBudgets(opts, nextLen)) {
      return false;
    }
    final String nextTail = '$_tail$chunk';
    _tail = nextTail;
    if (trailingNewline) {
      _fastTailKind = _fastNone;
    }
    final String rawText = _extractFastInlineSlice(nextTail, _fastParaRawStart);
    final ParagraphNode prevPara = _activeBlocks[0] as ParagraphNode;
    final SourceSpan newSpan = createUncheckedSpan(
      startOffset: prevPara.span.startOffset,
      endOffset: _settledOffset + nextLen,
      startLine: prevPara.span.startLine,
      endLine: prevPara.span.endLine,
    );
    _activeBlocks = freezeFreshList(<MarkdownBlockNode>[
      createFrozenParagraphNode(
        blockId: prevPara.blockId,
        children: _blockInlineResolver.parseParagraph(rawText, newSpan),
        span: newSpan,
      ),
    ]);
    return true;
  }

  bool _tryFastQuoteAppend(String chunk, MarkdownOptions opts) {
    final int nextLen = _tail.length + chunk.length;
    if (!_hasSafeFastBudgets(opts, nextLen)) {
      return false;
    }
    final String nextTail = '$_tail$chunk';
    _tail = nextTail;
    final String rawText = _extractFastInlineSlice(nextTail, _fastParaRawStart);
    final BlockQuoteNode prevQuote = _activeBlocks[0] as BlockQuoteNode;
    final ParagraphNode prevPara =
        rawBlockQuoteChildren(prevQuote)[0] as ParagraphNode;
    final int endOff = _settledOffset + nextLen;
    final SourceSpan newQuoteSpan = createUncheckedSpan(
      startOffset: prevQuote.span.startOffset,
      endOffset: endOff,
      startLine: prevQuote.span.startLine,
      endLine: prevQuote.span.endLine,
    );
    final SourceSpan newParaSpan = createUncheckedSpan(
      startOffset: prevPara.span.startOffset,
      endOffset: endOff,
      startLine: prevPara.span.startLine,
      endLine: prevPara.span.endLine,
    );
    final ParagraphNode nextPara = createFrozenParagraphNode(
      blockId: prevPara.blockId,
      children: _blockInlineResolver.parseParagraph(rawText, newParaSpan),
      span: newParaSpan,
    );
    _activeBlocks = freezeFreshList(<MarkdownBlockNode>[
      createFrozenBlockQuoteNode(
        blockId: prevQuote.blockId,
        children: freezeFreshList(<MarkdownBlockNode>[nextPara]),
        span: newQuoteSpan,
      ),
    ]);
    return true;
  }

  bool _tryFastListAppend(String chunk, MarkdownOptions opts) {
    final int nextLen = _tail.length + chunk.length;
    if (!_hasSafeFastBudgets(opts, nextLen)) {
      return false;
    }
    final String nextTail = '$_tail$chunk';
    _tail = nextTail;
    final String rawText = _extractFastInlineSlice(nextTail, _fastParaRawStart);
    final ListNode prevList = _activeBlocks[0] as ListNode;
    final List<ListItemNode> prevItems = rawListItems(prevList);
    final ListItemNode prevLastItem = prevItems[prevItems.length - 1];
    final List<MarkdownBlockNode> prevItemChildren = rawListItemChildren(
      prevLastItem,
    );
    final ParagraphNode prevLastPara =
        prevItemChildren[prevItemChildren.length - 1] as ParagraphNode;
    final int endOff = _settledOffset + nextLen;
    final SourceSpan newParaSpan = createUncheckedSpan(
      startOffset: prevLastPara.span.startOffset,
      endOffset: endOff,
      startLine: prevLastPara.span.startLine,
      endLine: prevLastPara.span.endLine,
    );
    final ParagraphNode nextPara = createFrozenParagraphNode(
      blockId: prevLastPara.blockId,
      children: _blockInlineResolver.parseParagraph(rawText, newParaSpan),
      span: newParaSpan,
    );
    final List<MarkdownBlockNode> nextItemChildren;
    if (prevItemChildren.length == 1) {
      nextItemChildren = freezeFreshList(<MarkdownBlockNode>[nextPara]);
    } else {
      final List<MarkdownBlockNode> copied = List<MarkdownBlockNode>.of(
        prevItemChildren,
      );
      copied[copied.length - 1] = nextPara;
      nextItemChildren = freezeFreshList(copied);
    }
    final SourceSpan newItemSpan = createUncheckedSpan(
      startOffset: prevLastItem.span.startOffset,
      endOffset: endOff,
      startLine: prevLastItem.span.startLine,
      endLine: prevLastItem.span.endLine,
    );
    final ListItemNode nextLastItem = createFrozenListItemNode(
      blockId: prevLastItem.blockId,
      taskState: prevLastItem.taskState,
      children: nextItemChildren,
      span: newItemSpan,
    );
    final List<ListItemNode> nextItems;
    if (prevItems.length == 1) {
      nextItems = freezeFreshList(<ListItemNode>[nextLastItem]);
    } else {
      final List<ListItemNode> copied = List<ListItemNode>.of(prevItems);
      copied[copied.length - 1] = nextLastItem;
      nextItems = freezeFreshList(copied);
    }
    final SourceSpan newListSpan = createUncheckedSpan(
      startOffset: prevList.span.startOffset,
      endOffset: endOff,
      startLine: prevList.span.startLine,
      endLine: prevList.span.endLine,
    );
    _activeBlocks = freezeFreshList(<MarkdownBlockNode>[
      createFrozenListNode(
        blockId: prevList.blockId,
        ordered: prevList.ordered,
        start: prevList.start,
        tight: prevList.tight,
        delimiter: prevList.delimiter,
        items: nextItems,
        span: newListSpan,
      ),
    ]);
    return true;
  }

  bool _tryFastTableAppend(
    String chunk,
    int nlCount,
    int firstNlIdx,
    MarkdownOptions opts,
  ) {
    if (nlCount > 1) {
      return false;
    }
    final int chunkLen = chunk.length;
    final int oldTailLen = _tail.length;
    final int nextLen = oldTailLen + chunkLen;
    if (!_hasSafeFastBudgets(opts, nextLen)) {
      return false;
    }
    final TableNode prevTable = _activeBlocks[0] as TableNode;
    final List<TableAlignment> alignments = prevTable.alignments;
    final int colCount = alignments.length;
    final List<List<TableCellNode>> prevRows = rawTableRows(prevTable);
    final int maxRows = opts.effectiveBudgets.maxTableRows;

    if (_fastTableEndedWithNl) {
      if (nlCount == 0) {
        if (prevRows.length >= maxRows ||
            !_startsWithTablePipe(chunk, 0, chunkLen)) {
          return false;
        }
        final String nextTail = '$_tail$chunk';
        _tail = nextTail;
        _fastTableEndedWithNl = false;
        _fastTableLastLineStart = oldTailLen;
        final List<String> cells = splitTableRowSpan(
          nextTail,
          oldTailLen,
          nextLen,
          maxColumns: colCount,
        );
        final SourceSpan newSpan = createUncheckedSpan(
          startOffset: prevTable.span.startOffset,
          endOffset: _settledOffset + nextLen,
          startLine: prevTable.span.startLine,
          endLine: prevTable.span.endLine + 1,
        );
        final List<TableCellNode> builtRow = _blockInlineResolver
            .resolveTableRow(cells, alignments, newSpan);
        _publishFastTable(
          prevTable,
          alignments,
          freezeFreshList(<List<TableCellNode>>[...prevRows, builtRow]),
          newSpan,
        );
        return true;
      }
      if (firstNlIdx == chunkLen - 1 &&
          firstNlIdx > 0 &&
          prevRows.length < maxRows &&
          _startsWithTablePipe(chunk, 0, firstNlIdx)) {
        final String nextTail = '$_tail$chunk';
        _tail = nextTail;
        _fastTableEndedWithNl = true;
        _fastTableLastLineStart = nextLen;
        final List<String> cells = splitTableRowSpan(
          nextTail,
          oldTailLen,
          oldTailLen + firstNlIdx,
          maxColumns: colCount,
        );
        final SourceSpan newSpan = createUncheckedSpan(
          startOffset: prevTable.span.startOffset,
          endOffset: _settledOffset + nextLen,
          startLine: prevTable.span.startLine,
          endLine: prevTable.span.endLine + 1,
        );
        final List<TableCellNode> builtRow = _blockInlineResolver
            .resolveTableRow(cells, alignments, newSpan);
        _publishFastTable(
          prevTable,
          alignments,
          freezeFreshList(<List<TableCellNode>>[...prevRows, builtRow]),
          newSpan,
        );
        return true;
      }
      return false;
    }

    if (prevRows.isEmpty) {
      return false;
    }

    if (nlCount == 0) {
      final String nextTail = '$_tail$chunk';
      _tail = nextTail;
      final List<String> cells = splitTableRowSpan(
        nextTail,
        _fastTableLastLineStart,
        nextLen,
        maxColumns: colCount,
      );
      final SourceSpan newSpan = createUncheckedSpan(
        startOffset: prevTable.span.startOffset,
        endOffset: _settledOffset + nextLen,
        startLine: prevTable.span.startLine,
        endLine: prevTable.span.endLine,
      );
      final List<TableCellNode> builtRow = _blockInlineResolver.resolveTableRow(
        cells,
        alignments,
        newSpan,
      );
      final List<List<TableCellNode>> nextRows = List<List<TableCellNode>>.of(
        prevRows,
      );
      nextRows[nextRows.length - 1] = builtRow;
      _publishFastTable(
        prevTable,
        alignments,
        freezeFreshList(nextRows),
        newSpan,
      );
      return true;
    }

    if (firstNlIdx == chunkLen - 1) {
      final int prevRowStart = _fastTableLastLineStart;
      final String nextTail = '$_tail$chunk';
      _tail = nextTail;
      _fastTableEndedWithNl = true;
      _fastTableLastLineStart = nextLen;
      final SourceSpan newSpan = createUncheckedSpan(
        startOffset: prevTable.span.startOffset,
        endOffset: _settledOffset + nextLen,
        startLine: prevTable.span.startLine,
        endLine: prevTable.span.endLine,
      );
      final List<List<TableCellNode>> nextRows;
      if (firstNlIdx == 0) {
        nextRows = prevRows;
      } else {
        final List<String> cells = splitTableRowSpan(
          nextTail,
          prevRowStart,
          nextLen - 1,
          maxColumns: colCount,
        );
        final List<TableCellNode> builtRow = _blockInlineResolver
            .resolveTableRow(cells, alignments, newSpan);
        final List<List<TableCellNode>> copied = List<List<TableCellNode>>.of(
          prevRows,
        );
        copied[copied.length - 1] = builtRow;
        nextRows = freezeFreshList(copied);
      }
      _publishFastTable(prevTable, alignments, nextRows, newSpan);
      return true;
    }

    if (prevRows.length >= maxRows ||
        !_startsWithTablePipe(chunk, firstNlIdx + 1, chunkLen)) {
      return false;
    }
    final int prevRowStart = _fastTableLastLineStart;
    final int nlPos = oldTailLen + firstNlIdx;
    final String nextTail = '$_tail$chunk';
    _tail = nextTail;
    _fastTableEndedWithNl = false;
    _fastTableLastLineStart = nlPos + 1;
    final SourceSpan newSpan = createUncheckedSpan(
      startOffset: prevTable.span.startOffset,
      endOffset: _settledOffset + nextLen,
      startLine: prevTable.span.startLine,
      endLine: prevTable.span.endLine + 1,
    );
    final List<List<TableCellNode>> nextRows;
    if (firstNlIdx == 0) {
      final List<String> newRowCells = splitTableRowSpan(
        nextTail,
        nlPos + 1,
        nextLen,
        maxColumns: colCount,
      );
      final List<TableCellNode> newBuiltRow = _blockInlineResolver
          .resolveTableRow(newRowCells, alignments, newSpan);
      nextRows = freezeFreshList(<List<TableCellNode>>[
        ...prevRows,
        newBuiltRow,
      ]);
    } else {
      final List<String> updatedLastCells = splitTableRowSpan(
        nextTail,
        prevRowStart,
        nlPos,
        maxColumns: colCount,
      );
      final List<String> newRowCells = splitTableRowSpan(
        nextTail,
        nlPos + 1,
        nextLen,
        maxColumns: colCount,
      );
      final List<TableCellNode> updatedLastRow = _blockInlineResolver
          .resolveTableRow(updatedLastCells, alignments, newSpan);
      final List<TableCellNode> newBuiltRow = _blockInlineResolver
          .resolveTableRow(newRowCells, alignments, newSpan, reset: false);
      nextRows = freezeFreshList(<List<TableCellNode>>[
        for (int i = 0; i < prevRows.length - 1; i++) prevRows[i],
        updatedLastRow,
        newBuiltRow,
      ]);
    }
    _publishFastTable(prevTable, alignments, nextRows, newSpan);
    return true;
  }

  void _publishFastTable(
    TableNode prevTable,
    List<TableAlignment> alignments,
    List<List<TableCellNode>> nextRows,
    SourceSpan newSpan,
  ) {
    _activeBlocks = freezeFreshList(<MarkdownBlockNode>[
      createFrozenTableNode(
        blockId: prevTable.blockId,
        alignments: alignments,
        headers: rawTableHeaders(prevTable),
        rows: nextRows,
        span: newSpan,
      ),
    ]);
  }

  @pragma('vm:never-inline')
  void _advanceSettledTailState(
    String nextTail,
    int nextSettledOffset,
    int nextSettledLine,
  ) {
    _settledSnapshotDirty = true;
    _tail = nextTail;
    _settledOffset = nextSettledOffset;
    _settledLine = nextSettledLine;
    _safeSettledCount = _settledBlocks.length;
    final int nextGroup = ++_tailGroupId;
    _tailIdPrefix = nextGroup < _settledIdPrefixes.length
        ? _settledIdPrefixes[nextGroup]
        : 's$nextGroup-';
  }

  /// Appends [chunk] to the stream buffer and incrementally updates only the
  /// unsettled trailing blocks.
  ///
  /// Throws [RangeError] without mutating internal state if appending [chunk]
  /// would exceed `effectiveOptions.maxInputLength`.
  MarkdownDocument append(String chunk) {
    if (chunk.isEmpty) {
      return _currentDocument;
    }
    final MarkdownOptions opts = effectiveOptions;
    final int nextLen = _rawLength + chunk.length;
    if (nextLen > opts.maxInputLength) {
      _throwInputLimit(nextLen, opts.maxInputLength);
    }
    final bool wasFinished = _isFinished;
    if (wasFinished) {
      _reopenAfterFinish();
    }
    _rawChunks.add(chunk);
    _rawLength = nextLen;

    final int chunkLen = chunk.length;
    int nlCount = 0;
    int firstNlIdx = -1;
    bool needsNorm = _pendingCr;
    if (!needsNorm) {
      for (int i = 0; i < chunkLen; i++) {
        final int cu = chunk.codeUnitAt(i);
        if (cu <= 0x0D) {
          if (cu == 0x0A) {
            if (nlCount == 0) {
              firstNlIdx = i;
            }
            nlCount++;
          } else if (cu == 0x0D || cu == 0x00) {
            needsNorm = true;
            break;
          }
        }
      }
    }

    bool publish = true;
    bool handled = false;
    if (!wasFinished && !needsNorm && _fastTailKind != _fastNone) {
      switch (_fastTailKind) {
        case _fastPara:
          if (nlCount == 0) {
            handled = _appendFastPara(chunk, opts, trailingNewline: false);
          } else if (nlCount == 1 && firstNlIdx == chunkLen - 1) {
            handled = _appendFastPara(chunk, opts, trailingNewline: true);
          }
        case _fastCode:
          handled = _tryFastOpenCodeAppend(chunk, nlCount);
        case _fastQuote:
          if (nlCount == 0) {
            handled = _tryFastQuoteAppend(chunk, opts);
          }
        case _fastList:
          if (nlCount == 0) {
            handled = _tryFastListAppend(chunk, opts);
          }
        case _fastTable:
          handled = _tryFastTableAppend(chunk, nlCount, firstNlIdx, opts);
      }
    }
    if (!handled) {
      if (_hasDefinitions) {
        _tail = '';
        _reparseTailColdFallback(opts);
        publish = false;
      } else {
        if (!needsNorm) {
          _tail = _tail.isEmpty ? chunk : '$_tail$chunk';
        } else {
          _appendNormalizedChunk(chunk);
        }
        publish = _reparseTail(opts);
      }
    }
    if (publish) {
      _publishTailDocument(opts);
    }
    if (_listeners.isNotEmpty) {
      _notifyListeners();
    }
    return _currentDocument;
  }

  @pragma('vm:never-inline')
  void _reopenAfterFinish() {
    _isFinished = false;
    _fastTailKind = _fastNone;
    if (_settledBlocks.length > _safeSettledCount) {
      _truncateSettledBlocks(_safeSettledCount);
      _settledSnapshotDirty = true;
    }
  }

  bool _tryFastOpenCodeAppend(String chunk, int nlCount) {
    final int fc = _fastCodeFenceChar;
    final int len = chunk.length;
    int newLines = 0;
    bool prevNl = _fastCodeEndedWithNl;
    if (nlCount == 0) {
      if (chunk.contains(fc == 0x60 ? '`' : '~')) {
        return false;
      }
      if (prevNl) {
        newLines = 1;
        prevNl = false;
      }
    } else {
      for (int i = 0; i < len; i++) {
        final int cu = chunk.codeUnitAt(i);
        if (cu == fc) {
          return false;
        }
        if (prevNl) {
          newLines++;
          prevNl = false;
        }
        if (cu == 0x0A) {
          prevNl = true;
        }
      }
    }
    _fastCodeEndedWithNl = prevNl;
    final String nextTail = '$_tail$chunk';
    _tail = nextTail;
    final String body = nextTail.substring(_fastCodeBodyStart);
    final String literal = body.isEmpty ? '' : (prevNl ? body : '$body\n');
    final CodeBlockNode prevCode = _activeBlocks[0] as CodeBlockNode;
    final SourceSpan newSpan = createUncheckedSpan(
      startOffset: prevCode.span.startOffset,
      endOffset: _settledOffset + nextTail.length,
      startLine: prevCode.span.startLine,
      endLine: prevCode.span.endLine + newLines,
    );
    _activeBlocks = freezeFreshList(<MarkdownBlockNode>[
      CodeBlockNode(
        blockId: prevCode.blockId,
        info: prevCode.info,
        language: prevCode.language,
        literal: literal,
        isFenced: true,
        codeUnitOffset: prevCode.codeUnitOffset,
        span: newSpan,
      ),
    ]);
    return true;
  }

  void _publishTailDocument(MarkdownOptions opts) {
    _currentDocument = createStreamingDocument(
      sourceChunks: _rawChunks,
      sourceChunkCount: _rawChunks.length,
      sourceLength: _rawLength,
      options: opts,
      blocks: _buildAllBlocks(),
      frontmatter: _frontmatter,
      hasBlocks: _settledBlocks.isNotEmpty || _activeBlocks.isNotEmpty,
    );
  }

  /// Replaces the entire stream text with [fullText], preserving already
  /// settled prefix blocks when [fullText] retains the exact settled prefix.
  MarkdownDocument replaceText(String fullText) {
    final MarkdownOptions opts = effectiveOptions;
    if (fullText.length > opts.maxInputLength) {
      throw RangeError.value(
        fullText.length,
        'buffer.length',
        'Input exceeds maxInputLength (${opts.maxInputLength}).',
      );
    }
    final String settledPrefix = _settledOffset > 0
        ? (_sawNormalization
              ? normalizeMarkdownSource(buffer).substring(0, _settledOffset)
              : buffer.substring(0, _settledOffset))
        : '';
    _isFinished = false;
    final String newNorm = normalizeMarkdownSource(fullText);
    _rawChunks = fullText.isEmpty ? <String>[] : <String>[fullText];
    _rawLength = fullText.length;
    _sawNormalization = !identical(newNorm, fullText);
    _pendingCr = false;

    if (_settledOffset > 0 &&
        newNorm.length >= _settledOffset &&
        newNorm.startsWith(settledPrefix)) {
      if (_settledBlocks.length > _safeSettledCount) {
        _truncateSettledBlocks(_safeSettledCount);
        _settledSnapshotDirty = true;
      }
      _tail = newNorm.substring(_settledOffset);
    } else {
      _clearParsingState();
      _tail = newNorm;
    }
    if (_rawLength == 0 ||
        _hasDefinitions ||
        (_tail.isEmpty && _settledBlocks.isEmpty)) {
      _reparseTailColdFallback(
        opts,
        fullSourceOverride: fullText,
        fullNormOverride: newNorm,
      );
    } else if (_reparseTail(opts)) {
      _currentDocument = createStreamingDocument(
        source: fullText,
        options: opts,
        blocks: _buildAllBlocks(),
        frontmatter: _frontmatter,
        hasBlocks: _settledBlocks.isNotEmpty || _activeBlocks.isNotEmpty,
        normalizedSource: newNorm,
      );
    }
    _notifyListeners();
    return _currentDocument;
  }

  /// Finalizes the stream, producing the exact same semantic AST and HTML as
  /// `MarkdownEngine.parse(buffer)` while preserving settled block IDs when
  /// possible.
  MarkdownDocument finish() {
    _isFinished = true;
    _fastTailKind = _fastNone;
    final MarkdownOptions opts = effectiveOptions;
    final String fullSource = buffer;
    if (fullSource.isEmpty) {
      _clearParsingState();
      _currentDocument = createFrozenDocument(
        source: fullSource,
        options: opts,
        blocks: emptyFrozenBlockList,
        outline: const <MarkdownOutlineItem>[],
        footnotes: const <FootnoteDefinitionNode>[],
        remoteImageAddresses: const <String>[],
        normalizedSource: '',
        html: '',
      );
      _notifyListeners();
      return _currentDocument;
    }

    if (_hasDefinitions || _settledBlocks.isEmpty) {
      final MarkdownDocument finalDoc = engine.parse(fullSource, options: opts);
      _resetSettledBlocks();
      _settledBlocks.addAll(finalDoc.blocks);
      _settledSnapshotDirty = true;
      _activeBlocks = emptyFrozenBlockList;
      _safeSettledCount = 0;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = finalDoc.frontmatter;
      _currentDocument = finalDoc;
      _notifyListeners();
      return finalDoc;
    }

    if (_settledBlocks.length > _safeSettledCount) {
      _truncateSettledBlocks(_safeSettledCount);
    }

    final String tailSlice = _tail;
    final Phase1Result phase1 = _blockParser.parse(
      tailSlice,
      baseOffset: _settledOffset,
      baseLine: _settledLine,
      idPrefix: _tailIdPrefix,
    );

    if (phase1.linkDefinitions.isNotEmpty ||
        phase1.footnoteDefinitions.isNotEmpty ||
        phase1.abbreviations.isNotEmpty) {
      _hasDefinitions = true;
      final MarkdownDocument finalDoc = engine.parse(fullSource, options: opts);
      _resetSettledBlocks();
      _settledBlocks.addAll(finalDoc.blocks);
      _settledSnapshotDirty = true;
      _activeBlocks = emptyFrozenBlockList;
      _safeSettledCount = 0;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = finalDoc.frontmatter;
      _currentDocument = finalDoc;
      _notifyListeners();
      return finalDoc;
    }

    final Phase2Result phase2 = _blockInlineResolver.parse(
      phase1,
      seedHeadingTexts: phase1.hasHeading && _settledHeadingTexts.isNotEmpty
          ? _settledHeadingTexts
          : null,
      seedHeadingCount: _settledHeadingTexts.length,
    );
    _settledBlocks.addAll(phase2.blocks);
    _settledSnapshotDirty = true;
    _activeBlocks = emptyFrozenBlockList;

    _currentDocument = createFrozenDocument(
      source: fullSource,
      options: opts,
      blocks: _settledBlocksView(),
      frontmatter: _frontmatter,
      footnotes: phase2.footnotes,
      linkDefinitions: phase1.linkDefinitions,
      abbreviations: phase1.abbreviations,
      normalizedSource: _sawNormalization ? null : fullSource,
    );
    _notifyListeners();
    return _currentDocument;
  }

  /// Clears all buffered text and settled blocks back to an empty state.
  void reset() {
    _rawChunks = <String>[];
    _rawLength = 0;
    _clearParsingState();
    _isFinished = false;
    _currentDocument = createFrozenDocument(
      source: '',
      options: effectiveOptions,
      blocks: emptyFrozenBlockList,
      outline: const <MarkdownOutlineItem>[],
      footnotes: const <FootnoteDefinitionNode>[],
      remoteImageAddresses: const <String>[],
      normalizedSource: '',
      html: '',
    );
    _notifyListeners();
  }

  void _clearParsingState() {
    _tail = '';
    _resetSettledBlocks();
    _settledSnapshot = emptyFrozenBlockList;
    _settledSnapshotDirty = false;
    _activeBlocks = emptyFrozenBlockList;
    _safeSettledCount = 0;
    _settledOffset = 0;
    _settledLine = 1;
    _tailGroupId = 0;
    _tailIdPrefix = '';
    _frontmatter = null;
    _hasDefinitions = false;
    _pendingCr = false;
    _sawNormalization = false;
    _fastTailKind = _fastNone;
    _fastParaRawStart = 0;
    _fastTableLastLineStart = 0;
    _fastTableEndedWithNl = false;
    _settledHeadingTexts = <String>[];
  }

  @pragma('vm:never-inline')
  void _appendNormalizedChunk(String chunk) {
    int chunkStart = 0;
    if (_pendingCr) {
      _pendingCr = false;
      if (chunk.codeUnitAt(0) == 0x0A) {
        chunkStart = 1;
      }
    }
    if (chunkStart < chunk.length) {
      bool needsNorm = false;
      for (int i = chunkStart; i < chunk.length; i++) {
        final int cu = chunk.codeUnitAt(i);
        if (cu == 0x0D || cu == 0x00) {
          needsNorm = true;
          break;
        }
      }
      if (!needsNorm) {
        final String clean = chunkStart == 0
            ? chunk
            : chunk.substring(chunkStart);
        _tail = _tail.isEmpty ? clean : '$_tail$clean';
      } else {
        _sawNormalization = true;
        final StringBuffer buf = StringBuffer(_tail);
        for (int i = chunkStart; i < chunk.length; i++) {
          final int cu = chunk.codeUnitAt(i);
          if (cu == 0x0D) {
            buf.writeCharCode(0x0A);
            if (i + 1 < chunk.length) {
              if (chunk.codeUnitAt(i + 1) == 0x0A) {
                i++;
              }
            } else {
              _pendingCr = true;
            }
          } else if (cu == 0x00) {
            buf.writeCharCode(0xFFFD);
          } else {
            buf.writeCharCode(cu);
          }
        }
        _tail = buf.toString();
      }
    }
  }

  bool _reparseTail(MarkdownOptions opts) {
    final String tailSlice = _tail;
    if (tailSlice.isEmpty && _settledBlocks.isEmpty) {
      _reparseTailColdFallback(opts);
      return false;
    }

    final Phase1Result phase1 = _blockParser.parse(
      tailSlice,
      baseOffset: _settledOffset,
      baseLine: _settledLine,
      idPrefix: _tailIdPrefix,
    );

    if (phase1.linkDefinitions.isNotEmpty ||
        phase1.footnoteDefinitions.isNotEmpty ||
        phase1.abbreviations.isNotEmpty) {
      _hasDefinitions = true;
      _reparseTailColdFallback(opts);
      return false;
    }

    if (_settledOffset == 0 && phase1.frontmatter != null) {
      _frontmatter = phase1.frontmatter!.frontmatter;
    }

    final bool trackHeadings = opts.headingSlugs && phase1.hasHeading;
    final Phase2Result phase2 = _blockInlineResolver.parse(
      phase1,
      seedHeadingTexts: trackHeadings && _settledHeadingTexts.isNotEmpty
          ? _settledHeadingTexts
          : null,
      seedHeadingCount: _settledHeadingTexts.length,
    );
    final List<MarkdownBlockNode> tailBlocks = phase2.blocks;

    if (tailBlocks.length > 1) {
      _settleLeadingTailBlocks(
        tailBlocks,
        tailSlice,
        opts,
        tailHadHeading: trackHeadings,
      );
    } else {
      _activeBlocks = tailBlocks;
    }

    _fastTailKind = _fastNone;
    if (!_pendingCr && _activeBlocks.length == 1) {
      _updateFastTailEligibility(phase1, opts);
    }
    return true;
  }

  @pragma('vm:never-inline')
  void _updateFastTailEligibility(Phase1Result phase1, MarkdownOptions opts) {
    final String tail = _tail;
    final int tailLen = tail.length;
    if (tailLen == 0 || !_hasSafeFastBudgets(opts, tailLen)) {
      return;
    }
    final MarkdownBlockNode onlyBlock = _activeBlocks[0];
    if (onlyBlock.span.endOffset != _settledOffset + tailLen) {
      return;
    }

    if (onlyBlock is ParagraphNode) {
      if (tail.codeUnitAt(tailLen - 1) != 0x0A) {
        final int localStart = onlyBlock.span.startOffset - _settledOffset;
        if (localStart >= 0 &&
            localStart < tailLen &&
            tail.lastIndexOf('\n') < localStart) {
          final int safeStart = _findSafeInlineRawStart(
            tail,
            localStart,
            tailLen,
            allowShortFenceChars: true,
          );
          if (safeStart >= 0) {
            _fastParaRawStart = safeStart;
            _fastTailKind = _fastPara;
          }
        }
      }
      return;
    }

    if (onlyBlock is CodeBlockNode) {
      if (onlyBlock.isFenced && phase1.blocks.isNotEmpty) {
        final RawBlock lastRaw = phase1.blocks.last;
        if (lastRaw is RawCodeBlock &&
            lastRaw.blockId == onlyBlock.blockId &&
            lastRaw.isFenced &&
            !lastRaw.isClosed &&
            lastRaw.fenceIndent == 0) {
          final int localBodyStart = onlyBlock.codeUnitOffset - _settledOffset;
          if (localBodyStart > 0 &&
              localBodyStart <= tailLen &&
              tail.codeUnitAt(localBodyStart - 1) == 0x0A) {
            _fastTailKind = _fastCode;
            _fastCodeBodyStart = localBodyStart;
            _fastCodeFenceChar = lastRaw.fenceChar;
            _fastCodeEndedWithNl = tail.codeUnitAt(tailLen - 1) == 0x0A;
          }
        }
      }
      return;
    }

    if (onlyBlock is BlockQuoteNode) {
      if (tail.codeUnitAt(tailLen - 1) != 0x0A &&
          onlyBlock.span.startLine == onlyBlock.span.endLine &&
          !tail.contains('\n') &&
          phase1.blocks.isNotEmpty) {
        final List<MarkdownBlockNode> children = rawBlockQuoteChildren(
          onlyBlock,
        );
        final RawBlock lastRaw = phase1.blocks.last;
        if (children.length == 1 &&
            children[0] is ParagraphNode &&
            children[0].span.endOffset == _settledOffset + tailLen &&
            lastRaw is RawBlockQuote &&
            lastRaw.blockId == onlyBlock.blockId &&
            lastRaw.children.length == 1 &&
            lastRaw.children[0] is RawParagraph) {
          final String rawText = (lastRaw.children[0] as RawParagraph).rawText;
          final int trimmedEnd = _trimRightEnd(tail, 0, tailLen);
          final int rawStart = trimmedEnd - rawText.length;
          if (rawText.isNotEmpty &&
              rawStart >= 0 &&
              tail.startsWith(rawText, rawStart) &&
              _findSafeInlineRawStart(
                    tail,
                    rawStart,
                    tailLen,
                    allowShortFenceChars: false,
                  ) >=
                  0) {
            _fastParaRawStart = rawStart;
            _fastTailKind = _fastQuote;
          }
        }
      }
      return;
    }

    if (onlyBlock is ListNode) {
      if (tail.codeUnitAt(tailLen - 1) != 0x0A && phase1.blocks.isNotEmpty) {
        final List<ListItemNode> items = rawListItems(onlyBlock);
        if (items.isEmpty) {
          return;
        }
        final ListItemNode lastItem = items[items.length - 1];
        if (lastItem.span.endOffset != _settledOffset + tailLen) {
          return;
        }
        final List<MarkdownBlockNode> itemChildren = rawListItemChildren(
          lastItem,
        );
        if (itemChildren.isEmpty ||
            itemChildren[itemChildren.length - 1] is! ParagraphNode) {
          return;
        }
        final ParagraphNode lastPara =
            itemChildren[itemChildren.length - 1] as ParagraphNode;
        if (lastPara.span.endOffset != _settledOffset + tailLen ||
            lastPara.span.startLine != lastPara.span.endLine) {
          return;
        }
        final int localParaStart = lastPara.span.startOffset - _settledOffset;
        if (localParaStart < 0 ||
            localParaStart >= tailLen ||
            tail.lastIndexOf('\n') >= localParaStart) {
          return;
        }
        final RawBlock lastRaw = phase1.blocks.last;
        if (lastRaw is! RawList || lastRaw.blockId != onlyBlock.blockId) {
          return;
        }
        if (lastRaw.items.length != items.length) {
          return;
        }
        final RawListItem rawLastItem = lastRaw.items[lastRaw.items.length - 1];
        if (rawLastItem.children.length != itemChildren.length ||
            rawLastItem.children[rawLastItem.children.length - 1]
                is! RawParagraph) {
          return;
        }
        final String rawText =
            (rawLastItem.children[rawLastItem.children.length - 1]
                    as RawParagraph)
                .rawText;
        final int trimmedEnd = _trimRightEnd(tail, localParaStart, tailLen);
        final int rawStart = trimmedEnd - rawText.length;
        if (rawText.isNotEmpty &&
            rawStart >= localParaStart &&
            tail.startsWith(rawText, rawStart) &&
            _findSafeInlineRawStart(
                  tail,
                  rawStart,
                  tailLen,
                  allowShortFenceChars: false,
                ) >=
                0) {
          _fastParaRawStart = rawStart;
          _fastTailKind = _fastList;
        }
      }
      return;
    }

    if (onlyBlock is TableNode) {
      if (onlyBlock.alignments.isEmpty || phase1.blocks.isEmpty) {
        return;
      }
      final RawBlock lastRaw = phase1.blocks.last;
      if (lastRaw is! RawTable || lastRaw.blockId != onlyBlock.blockId) {
        return;
      }
      if (tail.codeUnitAt(tailLen - 1) == 0x0A) {
        if (tailLen >= 2 && tail.codeUnitAt(tailLen - 2) != 0x0A) {
          _fastTableEndedWithNl = true;
          _fastTableLastLineStart = tailLen;
          _fastTailKind = _fastTable;
        }
      } else if (rawTableRows(onlyBlock).isNotEmpty) {
        final int lastLineStart = tail.lastIndexOf('\n') + 1;
        if (_startsWithTablePipe(tail, lastLineStart, tailLen)) {
          _fastTableEndedWithNl = false;
          _fastTableLastLineStart = lastLineStart;
          _fastTailKind = _fastTable;
        }
      }
    }
  }

  static int _trimRightEnd(String tail, int minIndex, int tailLen) {
    int end = tailLen;
    while (end > minIndex) {
      final int cu = tail.codeUnitAt(end - 1);
      if (cu == 0x20 || cu == 0x09) {
        end--;
      } else if (cu <= 0x20 || cu >= 0x80) {
        return minIndex + tail.substring(minIndex, end).trimRight().length;
      } else {
        break;
      }
    }
    return end;
  }

  static int _findSafeInlineRawStart(
    String tail,
    int localStart,
    int tailLen, {
    required bool allowShortFenceChars,
  }) {
    int firstNonSpace = localStart;
    while (firstNonSpace < tailLen &&
        (tail.codeUnitAt(firstNonSpace) == 0x20 ||
            tail.codeUnitAt(firstNonSpace) == 0x09)) {
      firstNonSpace++;
    }
    if (firstNonSpace >= tailLen) {
      return -1;
    }
    final int firstCu = tail.codeUnitAt(firstNonSpace);
    if (firstCu >= 128 || _streamBlockStarterLut[firstCu] == 0) {
      return firstNonSpace;
    }
    if (allowShortFenceChars && (firstCu == 0x60 || firstCu == 0x7E)) {
      int p = firstNonSpace + 1;
      final int limit = firstNonSpace + 3 < tailLen
          ? firstNonSpace + 3
          : tailLen;
      while (p < limit && tail.codeUnitAt(p) == firstCu) {
        p++;
      }
      if (p < limit) {
        return firstNonSpace;
      }
    }
    return -1;
  }

  void _settleLeadingTailBlocks(
    List<MarkdownBlockNode> tailBlocks,
    String tailSlice,
    MarkdownOptions opts, {
    required bool tailHadHeading,
  }) {
    int newlySettled = 0;
    final int baseOff = _settledOffset;
    final int tailLen = tailSlice.length;
    int nextSettledOffset = baseOff;
    int nextSettledLine = _settledLine;
    while (newlySettled + 1 < tailBlocks.length) {
      final MarkdownBlockNode candidate = tailBlocks[newlySettled];
      final MarkdownBlockNode nextBlock = tailBlocks[newlySettled + 1];
      int localEnd = candidate.span.endOffset - baseOff;
      final int localNextStart = nextBlock.span.startOffset - baseOff;
      if (candidate is! FrontmatterNode) {
        if (localEnd <= 0 ||
            localEnd >= localNextStart ||
            localEnd >= tailLen ||
            tailSlice.codeUnitAt(localEnd - 1) != 0x0A ||
            tailSlice.codeUnitAt(localEnd) != 0x0A) {
          break;
        }
        if ((candidate is ListNode && nextBlock is ListNode) ||
            ((candidate is HtmlBlockNode || candidate is DefinitionListNode) &&
                _mustDeferBoundary(candidate, opts))) {
          break;
        }
      }
      _settledBlocks.add(candidate);
      if (tailHadHeading) {
        _recordSettledBlockHeadings(candidate, opts);
      }
      newlySettled++;
      int newLine = candidate.span.endLine + 1;
      final int nlLimit = localNextStart < tailLen ? localNextStart : tailLen;
      while (localEnd < nlLimit && tailSlice.codeUnitAt(localEnd) == 0x0A) {
        localEnd++;
        newLine++;
      }
      nextSettledOffset = baseOff + localEnd;
      nextSettledLine = newLine;
    }

    if (newlySettled > 0) {
      final int consumed = nextSettledOffset - baseOff;
      _advanceSettledTailState(
        consumed > 0 && consumed <= tailLen
            ? tailSlice.substring(consumed)
            : _tail,
        nextSettledOffset,
        nextSettledLine,
      );
      _activeBlocks = tailBlocks.length - newlySettled == 1
          ? freezeFreshList(<MarkdownBlockNode>[tailBlocks[newlySettled]])
          : freezeFreshList(tailBlocks.sublist(newlySettled));
    } else {
      _activeBlocks = tailBlocks;
    }
  }

  @pragma('vm:never-inline')
  static bool _mustDeferBoundary(
    MarkdownBlockNode candidate,
    MarkdownOptions opts,
  ) {
    if (candidate is HtmlBlockNode) {
      return opts.detailsBlocks || opts.figureBlocks || opts.alignedBlocks;
    }
    return opts.definitionLists && candidate is DefinitionListNode;
  }

  @pragma('vm:never-inline')
  void _recordSettledBlockHeadings(
    MarkdownBlockNode candidate,
    MarkdownOptions opts,
  ) {
    if (candidate is HeadingNode) {
      if (opts.headingSlugs &&
          !(opts.explicitHeadingIds && candidate.explicitId != null)) {
        _settledHeadingTexts.add(candidate.text);
      }
    } else if (candidate is! ParagraphNode &&
        candidate is! CodeBlockNode &&
        candidate is! TableNode &&
        candidate is! ThematicBreakNode &&
        candidate is! FrontmatterNode &&
        blockContainsHeading(candidate)) {
      collectSettledHeadingTexts(candidate, opts, _settledHeadingTexts);
    }
  }

  @pragma('vm:never-inline')
  void _reparseTailColdFallback(
    MarkdownOptions opts, {
    String? fullSourceOverride,
    String? fullNormOverride,
  }) {
    if (_rawLength == 0) {
      _activeBlocks = emptyFrozenBlockList;
      _fastTailKind = _fastNone;
      _currentDocument = createFrozenDocument(
        source: '',
        options: opts,
        blocks: emptyFrozenBlockList,
        outline: const <MarkdownOutlineItem>[],
        footnotes: const <FootnoteDefinitionNode>[],
        remoteImageAddresses: const <String>[],
        normalizedSource: '',
        html: '',
      );
      return;
    }
    if (_hasDefinitions) {
      final String fullSource = fullSourceOverride ?? buffer;
      final MarkdownDocument doc = engine.parse(fullSource, options: opts);
      _resetSettledBlocks();
      _settledSnapshot = emptyFrozenBlockList;
      _settledSnapshotDirty = false;
      _safeSettledCount = 0;
      _activeBlocks = doc.blocks;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = doc.frontmatter;
      _settledHeadingTexts = <String>[];
      _fastTailKind = _fastNone;
      _currentDocument = doc;
      return;
    }
    _activeBlocks = emptyFrozenBlockList;
    _fastTailKind = _fastNone;
    _currentDocument = createFrozenDocument(
      source: fullSourceOverride,
      sourceChunks: fullSourceOverride == null ? _rawChunks : null,
      sourceChunkCount: fullSourceOverride == null ? _rawChunks.length : 0,
      sourceLength: fullSourceOverride == null ? _rawLength : 0,
      options: opts,
      blocks: emptyFrozenBlockList,
      outline: const <MarkdownOutlineItem>[],
      footnotes: const <FootnoteDefinitionNode>[],
      remoteImageAddresses: const <String>[],
      normalizedSource: fullNormOverride,
      html: '',
    );
  }
}
