import 'ast.dart';
import 'ast_walkers.dart';
import 'block_parser.dart';
import 'document.dart';
import 'engine.dart';
import 'inline_parser.dart';
import 'options.dart';
import 'slugs.dart';

/// Incremental streaming Markdown parser tailored for token-by-token feeds such
/// as LLM completions, freezing settled top-level blocks and re-parsing only
/// the active trailing slice on each chunk.
final class StreamingMarkdownController {
  /// Creates a [StreamingMarkdownController].
  StreamingMarkdownController({
    this.engine = const MarkdownEngine(),
    MarkdownOptions? options,
  }) : _options = options {
    _currentDocument = MarkdownDocument(
      source: '',
      options: effectiveOptions,
      blocks: const <MarkdownBlockNode>[],
      normalizedSource: '',
      html: '',
    );
  }

  /// Engine used for parsing active slices and final reconciliation.
  final MarkdownEngine engine;

  final MarkdownOptions? _options;

  final StringBuffer _buffer = StringBuffer();
  final StringBuffer _settledNormalizedPrefix = StringBuffer();
  final StringBuffer _tailBuffer = StringBuffer();
  final List<MarkdownBlockNode> _settledBlocks = <MarkdownBlockNode>[];
  List<MarkdownBlockNode> _activeBlocks = const <MarkdownBlockNode>[];
  int _safeSettledCount = 0;
  int _settledOffset = 0;
  int _settledLine = 1;
  int _tailGroupId = 0;
  MarkdownFrontmatter? _frontmatter;
  bool _hasDefinitions = false;
  bool _isFinished = false;
  bool _pendingCr = false;
  bool _sawNormalization = false;
  int _fenceChar = 0;
  int _fenceLength = 0;
  int _defScanLineStartInTail = 0;
  final HeadingSlugGenerator _settledSlugs = HeadingSlugGenerator();
  final List<MarkdownOutlineItem> _settledOutline = <MarkdownOutlineItem>[];
  final List<String> _settledRemoteImages = <String>[];
  final Set<String> _settledRemoteImageSet = <String>{};
  final List<void Function()> _listeners = <void Function()>[];
  bool _isDisposed = false;
  late MarkdownDocument _currentDocument;

  /// Effective [MarkdownOptions] used by this controller.
  MarkdownOptions get effectiveOptions => _options ?? engine.defaultOptions;

  /// Raw accumulated Markdown source text received so far.
  String get buffer => _buffer.toString();

  /// Current incremental [MarkdownDocument] snapshot.
  MarkdownDocument get currentDocument => _currentDocument;

  /// Alias for [currentDocument].
  MarkdownDocument get document => _currentDocument;

  /// Frozen top-level blocks already finalized earlier in the stream.
  List<MarkdownBlockNode> get settledBlocks =>
      List<MarkdownBlockNode>.unmodifiable(_settledBlocks);

  /// Trailing active blocks currently open/re-parsed on new chunks.
  List<MarkdownBlockNode> get activeBlocks =>
      List<MarkdownBlockNode>.unmodifiable(_activeBlocks);

  /// Count of settled top-level blocks currently frozen.
  int get settledBlockCount => _settledBlocks.length;

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

  void _notifyListeners() {
    if (_listeners.isEmpty) {
      return;
    }
    final List<void Function()> snapshot = List<void Function()>.of(_listeners);
    for (final void Function() listener in snapshot) {
      listener();
    }
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
    if (_buffer.length + chunk.length > opts.maxInputLength) {
      throw RangeError.value(
        _buffer.length + chunk.length,
        'buffer.length',
        'Input exceeds maxInputLength (${opts.maxInputLength}).',
      );
    }
    if (_isFinished) {
      _isFinished = false;
      if (_settledBlocks.length > _safeSettledCount) {
        _settledBlocks.length = _safeSettledCount;
      }
    }
    _buffer.write(chunk);
    _appendNormalizedChunk(chunk);
    _reparseTail();
    _notifyListeners();
    return _currentDocument;
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
    _isFinished = false;
    final String newNorm = normalizeMarkdownSource(fullText);
    _buffer
      ..clear()
      ..write(fullText);
    _sawNormalization = !identical(newNorm, fullText);
    _pendingCr = false;

    final String settledPrefix = _settledOffset > 0
        ? _settledNormalizedPrefix.toString()
        : '';
    if (_settledOffset > 0 &&
        newNorm.length >= _settledOffset &&
        newNorm.startsWith(settledPrefix)) {
      if (_settledBlocks.length > _safeSettledCount) {
        _settledBlocks.length = _safeSettledCount;
      }
      final String tail = newNorm.substring(_settledOffset);
      _tailBuffer
        ..clear()
        ..write(tail);
      _defScanLineStartInTail = 0;
      _fenceChar = 0;
      _fenceLength = 0;
      _scanTailForDefinitionsAndFences(tail, 0);
      _reparseTail(fullSourceOverride: fullText, fullNormOverride: newNorm);
    } else {
      _clearParsingState();
      _tailBuffer.write(newNorm);
      _scanTailForDefinitionsAndFences(newNorm, 0);
      _reparseTail(fullSourceOverride: fullText, fullNormOverride: newNorm);
    }
    _notifyListeners();
    return _currentDocument;
  }

  /// Finalizes the stream, producing the exact same semantic AST and HTML as
  /// `MarkdownEngine.parse(buffer)` while preserving settled block IDs when
  /// possible.
  MarkdownDocument finish() {
    _isFinished = true;
    final MarkdownOptions opts = effectiveOptions;
    final String fullSource = _buffer.toString();
    if (fullSource.isEmpty) {
      _clearParsingState();
      _currentDocument = MarkdownDocument(
        source: fullSource,
        options: opts,
        blocks: const <MarkdownBlockNode>[],
        normalizedSource: '',
        html: '',
      );
      _notifyListeners();
      return _currentDocument;
    }

    if (_hasDefinitions || _settledBlocks.isEmpty) {
      final MarkdownDocument finalDoc = engine.parse(fullSource, options: opts);
      _settledBlocks
        ..clear()
        ..addAll(finalDoc.blocks);
      _activeBlocks = const <MarkdownBlockNode>[];
      _safeSettledCount = 0;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = finalDoc.frontmatter;
      _currentDocument = finalDoc;
      _notifyListeners();
      return finalDoc;
    }

    if (_settledBlocks.length > _safeSettledCount) {
      _settledBlocks.length = _safeSettledCount;
    }

    final String tailSlice = _tailBuffer.toString();
    final MarkdownOptions tailOpts = _settledOffset == 0
        ? opts
        : opts.copyWith(frontmatter: false);
    final Phase1Result phase1 = parseBlocks(
      tailSlice,
      tailOpts,
      baseOffset: _settledOffset,
      baseLine: _settledLine,
      idPrefix: _tailGroupId == 0 ? '' : 's$_tailGroupId-',
    );

    if (phase1.linkDefinitions.isNotEmpty ||
        phase1.footnoteDefinitions.isNotEmpty ||
        phase1.abbreviations.isNotEmpty) {
      _hasDefinitions = true;
      final MarkdownDocument finalDoc = engine.parse(fullSource, options: opts);
      _settledBlocks
        ..clear()
        ..addAll(finalDoc.blocks);
      _activeBlocks = const <MarkdownBlockNode>[];
      _safeSettledCount = 0;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = finalDoc.frontmatter;
      _currentDocument = finalDoc;
      _notifyListeners();
      return finalDoc;
    }

    final Phase2Result phase2 = parseInlines(
      phase1,
      tailOpts,
      slugGenerator: _settledSlugs.clone(),
    );
    _settledBlocks.addAll(phase2.blocks);
    _activeBlocks = const <MarkdownBlockNode>[];

    final List<MarkdownOutlineItem> outline;
    if (phase2.outline.isEmpty) {
      outline = freezeList(List<MarkdownOutlineItem>.of(_settledOutline));
    } else {
      outline = freezeList(<MarkdownOutlineItem>[
        ..._settledOutline,
        ...phase2.outline,
      ]);
    }

    final List<String> remoteImages = _mergeRemoteImages(
      _settledRemoteImages,
      _settledRemoteImageSet,
      phase2.remoteImageAddresses,
    );

    _currentDocument = MarkdownDocument(
      source: fullSource,
      options: opts,
      blocks: freezeList(List<MarkdownBlockNode>.of(_settledBlocks)),
      frontmatter: _frontmatter,
      outline: outline,
      footnotes: phase2.footnotes,
      remoteImageAddresses: remoteImages,
      linkDefinitions: phase1.linkDefinitions,
      abbreviations: phase1.abbreviations,
      normalizedSource: _sawNormalization ? null : fullSource,
    );
    _notifyListeners();
    return _currentDocument;
  }

  /// Clears all buffered text and settled blocks back to an empty state.
  void reset() {
    _buffer.clear();
    _clearParsingState();
    _isFinished = false;
    _currentDocument = MarkdownDocument(
      source: '',
      options: effectiveOptions,
      blocks: const <MarkdownBlockNode>[],
      normalizedSource: '',
      html: '',
    );
    _notifyListeners();
  }

  void _clearParsingState() {
    _settledNormalizedPrefix.clear();
    _tailBuffer.clear();
    _settledBlocks.clear();
    _activeBlocks = const <MarkdownBlockNode>[];
    _safeSettledCount = 0;
    _settledOffset = 0;
    _settledLine = 1;
    _tailGroupId = 0;
    _frontmatter = null;
    _hasDefinitions = false;
    _pendingCr = false;
    _sawNormalization = false;
    _fenceChar = 0;
    _fenceLength = 0;
    _defScanLineStartInTail = 0;
    _settledSlugs.reset();
    _settledOutline.clear();
    _settledRemoteImages.clear();
    _settledRemoteImageSet.clear();
  }

  void _appendNormalizedChunk(String chunk) {
    final int beforeLen = _tailBuffer.length;
    int chunkStart = 0;
    if (_pendingCr) {
      _pendingCr = false;
      if (chunk.codeUnitAt(0) == 0x0A) {
        chunkStart = 1;
      }
    }
    if (chunkStart < chunk.length) {
      final bool hasCr = chunk.indexOf('\r', chunkStart) != -1;
      final bool hasNul = chunk.indexOf('\x00', chunkStart) != -1;
      if (!hasCr && !hasNul) {
        _tailBuffer.write(
          chunkStart == 0 ? chunk : chunk.substring(chunkStart),
        );
      } else {
        _sawNormalization = true;
        for (int i = chunkStart; i < chunk.length; i++) {
          final int cu = chunk.codeUnitAt(i);
          if (cu == 0x0D) {
            _tailBuffer.writeCharCode(0x0A);
            if (i + 1 < chunk.length) {
              if (chunk.codeUnitAt(i + 1) == 0x0A) {
                i++;
              }
            } else {
              _pendingCr = true;
            }
          } else if (cu == 0x00) {
            _tailBuffer.writeCharCode(0xFFFD);
          } else {
            _tailBuffer.writeCharCode(cu);
          }
        }
      }
    }

    if (!_hasDefinitions && _tailBuffer.length > beforeLen) {
      final String tailNow = _tailBuffer.toString();
      _scanTailForDefinitionsAndFences(tailNow, _defScanLineStartInTail);
    }
  }

  void _scanTailForDefinitionsAndFences(String tail, int fromOffset) {
    int lineStart = fromOffset < 0 ? 0 : fromOffset;
    final int len = tail.length;
    while (lineStart < len) {
      final int nl = tail.indexOf('\n', lineStart);
      final int lineEnd = nl == -1 ? len : nl;
      if (nl != -1) {
        // Update fenced code tracking on complete lines.
        final ({int fenceChar, int fenceLen})? fence = _matchFenceLine(
          tail,
          lineStart,
          lineEnd,
        );
        if (_fenceChar == 0) {
          if (fence != null) {
            _fenceChar = fence.fenceChar;
            _fenceLength = fence.fenceLen;
          } else if (!_hasDefinitions &&
              lineLooksLikeDefinition(tail, lineStart, lineEnd)) {
            _hasDefinitions = true;
          }
        } else {
          if (fence != null &&
              fence.fenceChar == _fenceChar &&
              fence.fenceLen >= _fenceLength &&
              _isTrailingWsOnly(tail, lineStart, lineEnd, fence)) {
            _fenceChar = 0;
            _fenceLength = 0;
          }
        }
        lineStart = nl + 1;
        _defScanLineStartInTail = lineStart;
      } else {
        // Partial last line (no '\n' yet): do not commit fence state yet, just
        // check outside fences for an active definition line.
        if (_fenceChar == 0 &&
            !_hasDefinitions &&
            lineLooksLikeDefinition(tail, lineStart, lineEnd)) {
          _hasDefinitions = true;
        }
        break;
      }
    }
  }

  ({int fenceChar, int fenceLen})? _matchFenceLine(
    String s,
    int start,
    int end,
  ) {
    int i = start;
    int spaces = 0;
    while (i < end && spaces < 3 && s.codeUnitAt(i) == 0x20) {
      spaces++;
      i++;
    }
    if (i >= end) {
      return null;
    }
    final int ch = s.codeUnitAt(i);
    if (ch != 0x60 && ch != 0x7E) {
      return null;
    }
    int count = 0;
    while (i < end && s.codeUnitAt(i) == ch) {
      count++;
      i++;
    }
    if (count < 3) {
      return null;
    }
    if (ch == 0x60) {
      for (int k = i; k < end; k++) {
        if (s.codeUnitAt(k) == 0x60) {
          return null;
        }
      }
    }
    return (fenceChar: ch, fenceLen: count);
  }

  bool _isTrailingWsOnly(
    String s,
    int start,
    int end,
    ({int fenceChar, int fenceLen}) fence,
  ) {
    int i = start;
    int spaces = 0;
    while (i < end && spaces < 3 && s.codeUnitAt(i) == 0x20) {
      spaces++;
      i++;
    }
    while (i < end && s.codeUnitAt(i) == fence.fenceChar) {
      i++;
    }
    while (i < end) {
      final int cu = s.codeUnitAt(i);
      if (cu != 0x20 && cu != 0x09) {
        return false;
      }
      i++;
    }
    return true;
  }

  void _reparseTail({String? fullSourceOverride, String? fullNormOverride}) {
    final MarkdownOptions opts = effectiveOptions;
    final String fullSource = fullSourceOverride ?? _buffer.toString();
    if (_buffer.isEmpty) {
      _activeBlocks = const <MarkdownBlockNode>[];
      _currentDocument = MarkdownDocument(
        source: fullSource,
        options: opts,
        blocks: const <MarkdownBlockNode>[],
        normalizedSource: '',
        html: '',
      );
      return;
    }

    if (_hasDefinitions) {
      final MarkdownDocument doc = engine.parse(fullSource, options: opts);
      _settledBlocks.clear();
      _safeSettledCount = 0;
      _activeBlocks = doc.blocks;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = doc.frontmatter;
      _settledNormalizedPrefix.clear();
      _settledSlugs.reset();
      _settledOutline.clear();
      _settledRemoteImages.clear();
      _settledRemoteImageSet.clear();
      _currentDocument = doc;
      return;
    }

    final String tailSlice = _tailBuffer.toString();
    if (tailSlice.isEmpty && _settledBlocks.isEmpty) {
      _activeBlocks = const <MarkdownBlockNode>[];
      _currentDocument = MarkdownDocument(
        source: fullSource,
        options: opts,
        blocks: const <MarkdownBlockNode>[],
        normalizedSource:
            fullNormOverride ?? (_sawNormalization ? null : fullSource),
        html: '',
      );
      return;
    }

    final MarkdownOptions tailOpts = _settledOffset == 0
        ? opts
        : opts.copyWith(frontmatter: false);
    final Phase1Result phase1 = parseBlocks(
      tailSlice,
      tailOpts,
      baseOffset: _settledOffset,
      baseLine: _settledLine,
      idPrefix: _tailGroupId == 0 ? '' : 's$_tailGroupId-',
    );

    if (phase1.linkDefinitions.isNotEmpty ||
        phase1.footnoteDefinitions.isNotEmpty ||
        phase1.abbreviations.isNotEmpty) {
      _hasDefinitions = true;
      final MarkdownDocument doc = engine.parse(fullSource, options: opts);
      _settledBlocks.clear();
      _safeSettledCount = 0;
      _activeBlocks = doc.blocks;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = doc.frontmatter;
      _settledNormalizedPrefix.clear();
      _settledSlugs.reset();
      _settledOutline.clear();
      _settledRemoteImages.clear();
      _settledRemoteImageSet.clear();
      _currentDocument = doc;
      return;
    }

    if (_settledOffset == 0 && phase1.frontmatter != null) {
      _frontmatter = phase1.frontmatter!.frontmatter;
    }

    final Phase2Result phase2 = parseInlines(
      phase1,
      tailOpts,
      slugGenerator: _settledSlugs.clone(),
    );
    final List<MarkdownBlockNode> tailBlocks = phase2.blocks;

    // Settle leading blocks in `tailBlocks` that are guaranteed immutable by
    // having a blank-line boundary and a subsequent block following them.
    int newlySettled = 0;
    int nextSettledOffset = _settledOffset;
    int nextSettledLine = _settledLine;
    while (newlySettled + 1 < tailBlocks.length) {
      final MarkdownBlockNode candidate = tailBlocks[newlySettled];
      final MarkdownBlockNode nextBlock = tailBlocks[newlySettled + 1];
      if (!_canSettleBlock(candidate, nextBlock, tailSlice, opts)) {
        break;
      }
      _settledBlocks.add(candidate);
      collectSettledBlockOutlineAndSlugs(
        candidate,
        opts,
        _settledSlugs,
        _settledOutline,
      );
      collectRemoteImagesInto(
        <MarkdownBlockNode>[candidate],
        _settledRemoteImages,
        _settledRemoteImageSet,
      );
      newlySettled++;
      int newStart = candidate.span.endOffset;
      int newLine = candidate.span.endLine + 1;
      final int localEndMax = nextBlock.span.startOffset - _settledOffset;
      while (newStart - _settledOffset < localEndMax &&
          newStart - _settledOffset < tailSlice.length &&
          tailSlice.codeUnitAt(newStart - _settledOffset) == 0x0A) {
        newStart++;
        newLine++;
      }
      nextSettledOffset = newStart;
      nextSettledLine = newLine;
    }

    Phase2Result activeResult = phase2;
    if (newlySettled > 0) {
      final int consumed = nextSettledOffset - _settledOffset;
      String remaining = '';
      if (consumed > 0 && consumed <= tailSlice.length) {
        _settledNormalizedPrefix.write(tailSlice.substring(0, consumed));
        remaining = tailSlice.substring(consumed);
        _tailBuffer
          ..clear()
          ..write(remaining);
        _defScanLineStartInTail = _defScanLineStartInTail > consumed
            ? _defScanLineStartInTail - consumed
            : 0;
      } else {
        remaining = _tailBuffer.toString();
      }
      _settledOffset = nextSettledOffset;
      _settledLine = nextSettledLine;
      _safeSettledCount = _settledBlocks.length;
      _tailGroupId++;
      if (remaining.isNotEmpty) {
        final MarkdownOptions activeOpts = _settledOffset == 0
            ? opts
            : opts.copyWith(frontmatter: false);
        final Phase1Result freshTailP1 = parseBlocks(
          remaining,
          activeOpts,
          baseOffset: _settledOffset,
          baseLine: _settledLine,
          idPrefix: 's$_tailGroupId-',
        );
        activeResult = parseInlines(
          freshTailP1,
          activeOpts,
          slugGenerator: _settledSlugs.clone(),
        );
        _activeBlocks = activeResult.blocks;
      } else {
        _activeBlocks = const <MarkdownBlockNode>[];
      }
    } else {
      _activeBlocks = tailBlocks.sublist(newlySettled);
    }

    final List<MarkdownBlockNode> allBlocks = freezeList(<MarkdownBlockNode>[
      ..._settledBlocks,
      ..._activeBlocks,
    ]);

    final List<MarkdownOutlineItem> outline;
    if (activeResult.outline.isEmpty) {
      outline = _settledOutline.isEmpty
          ? const <MarkdownOutlineItem>[]
          : freezeList(List<MarkdownOutlineItem>.of(_settledOutline));
    } else if (_settledOutline.isEmpty) {
      outline = activeResult.outline;
    } else {
      final int firstActiveStart = _activeBlocks.isEmpty
          ? _settledOffset
          : _activeBlocks.first.span.startOffset;
      outline = freezeList(<MarkdownOutlineItem>[
        ..._settledOutline,
        for (final MarkdownOutlineItem item in activeResult.outline)
          if (item.span.startOffset >= firstActiveStart) item,
      ]);
    }

    final List<String> remoteImages = _activeBlocks.isEmpty
        ? freezeList(List<String>.of(_settledRemoteImages))
        : (activeResult.remoteImageAddresses.isEmpty
              ? freezeList(List<String>.of(_settledRemoteImages))
              : _mergeRemoteImages(
                  _settledRemoteImages,
                  _settledRemoteImageSet,
                  collectRemoteImagesFromBlocks(_activeBlocks),
                ));

    _currentDocument = MarkdownDocument(
      source: fullSource,
      options: opts,
      blocks: allBlocks,
      frontmatter: _frontmatter,
      outline: outline,
      footnotes: activeResult.footnotes,
      remoteImageAddresses: remoteImages,
      linkDefinitions: phase1.linkDefinitions,
      abbreviations: phase1.abbreviations,
      normalizedSource:
          fullNormOverride ?? (_sawNormalization ? null : fullSource),
    );
  }

  List<String> _mergeRemoteImages(
    List<String> settled,
    Set<String> settledSet,
    List<String> tailImages,
  ) {
    if (tailImages.isEmpty) {
      return settled.isEmpty
          ? const <String>[]
          : freezeList(List<String>.of(settled));
    }
    if (settled.isEmpty) {
      return freezeList(tailImages);
    }
    final List<String> merged = List<String>.of(settled);
    for (final String url in tailImages) {
      if (!settledSet.contains(url) && !merged.contains(url)) {
        merged.add(url);
      }
    }
    return freezeList(merged);
  }

  bool _canSettleBlock(
    MarkdownBlockNode candidate,
    MarkdownBlockNode next,
    String tailSlice,
    MarkdownOptions opts,
  ) {
    if (candidate is FrontmatterNode) {
      return true;
    }
    final int localEnd = candidate.span.endOffset - _settledOffset;
    final int localNextStart = next.span.startOffset - _settledOffset;
    if (localEnd <= 0 || localEnd >= localNextStart) {
      return false;
    }
    if (localEnd >= tailSlice.length ||
        tailSlice.codeUnitAt(localEnd - 1) != 0x0A ||
        tailSlice.codeUnitAt(localEnd) != 0x0A) {
      return false;
    }
    // Lists followed by blank lines could still receive another item if
    // `next` is a list; settle only once a non-list block follows.
    if (candidate is ListNode && next is ListNode) {
      return false;
    }
    // Never freeze HTML/Details/Figure/Aligned containers prematurely if
    // extended container blocks are enabled and could merge with adjacent HTML.
    if (isPotentialHtmlContainerBoundary(candidate, opts)) {
      return false;
    }
    // Definition lists can absorb subsequent `: ` paragraphs.
    if (opts.definitionLists && candidate is DefinitionListNode) {
      return false;
    }
    return true;
  }
}
