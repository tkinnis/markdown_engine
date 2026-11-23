import 'package:meta/meta.dart';

import 'ast.dart';
import 'ast_walkers.dart';
import 'block_parser.dart';
import 'document.dart';
import 'engine.dart';
import 'inline_parser.dart';
import 'options.dart';

/// Result returned by [IncrementalMarkdownParser.parseIncremental], reporting
/// the resulting [MarkdownDocument] and block reuse telemetry.
@immutable
final class IncrementalParseResult {
  /// Creates an [IncrementalParseResult].
  const IncrementalParseResult({
    required this.document,
    required this.reusedBlockCount,
    required this.reparsedBlockCount,
  });

  /// Resulting parsed document.
  final MarkdownDocument document;

  /// Number of unchanged top-level AST blocks reused with preserved `blockId`s.
  final int reusedBlockCount;

  /// Number of newly parsed top-level AST blocks in this update.
  final int reparsedBlockCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IncrementalParseResult &&
          document == other.document &&
          reusedBlockCount == other.reusedBlockCount &&
          reparsedBlockCount == other.reparsedBlockCount;

  @override
  int get hashCode =>
      Object.hash(document, reusedBlockCount, reparsedBlockCount);

  @override
  String toString() =>
      'IncrementalParseResult(blocks: ${document.blocks.length}, '
      'reused: $reusedBlockCount, reparsed: $reparsedBlockCount)';
}

/// Incremental Markdown parser that reuses unchanged top-level AST blocks
/// (preserving their stable [MarkdownBlockNode.blockId]s) when edits stay
/// isolated from frontmatter, link definitions, and footnote definitions.
final class IncrementalMarkdownParser {
  /// Creates an [IncrementalMarkdownParser].
  const IncrementalMarkdownParser({this.engine = const MarkdownEngine()});

  /// Underlying [MarkdownEngine] used to parse dirty slices or full fallbacks.
  final MarkdownEngine engine;

  /// Incrementally parses [newSource] against [previousDocument] (or
  /// [previousResult]).
  IncrementalParseResult parseIncremental(
    String newSource, {
    MarkdownDocument? previousDocument,
    IncrementalParseResult? previousResult,
    int? editStartOffset,
    int? editOldEndOffset,
    int? editNewEndOffset,
    MarkdownOptions? options,
  }) {
    final MarkdownDocument? prevDoc =
        previousDocument ?? previousResult?.document;
    final MarkdownOptions effective =
        options ?? prevDoc?.options ?? engine.defaultOptions;

    if (newSource.length > effective.maxInputLength) {
      throw RangeError.value(
        newSource.length,
        'newSource.length',
        'Input exceeds maxInputLength (${effective.maxInputLength}).',
      );
    }

    if (prevDoc == null ||
        prevDoc.options != effective ||
        prevDoc.blocks.isEmpty ||
        newSource.isEmpty) {
      final MarkdownDocument full = engine.parse(newSource, options: effective);
      return IncrementalParseResult(
        document: full,
        reusedBlockCount: 0,
        reparsedBlockCount: full.blocks.length,
      );
    }

    if (identical(prevDoc.source, newSource)) {
      return IncrementalParseResult(
        document: prevDoc,
        reusedBlockCount: prevDoc.blocks.length,
        reparsedBlockCount: 0,
      );
    }

    final String oldNorm =
        cachedNormalizedSource(prevDoc) ??
        normalizeMarkdownSource(prevDoc.source);
    final bool oldNormUnchanged = identical(oldNorm, prevDoc.source);

    late final String newNorm;
    int prefixLen;
    int oldDirtyEndLimit;
    int newDirtyEndLimit;

    if (oldNormUnchanged &&
        editStartOffset != null &&
        editOldEndOffset != null &&
        editNewEndOffset != null &&
        editStartOffset >= 0 &&
        editStartOffset <= editOldEndOffset &&
        editStartOffset <= editNewEndOffset &&
        editOldEndOffset <= oldNorm.length &&
        editNewEndOffset <= newSource.length &&
        oldNorm.length - editOldEndOffset ==
            newSource.length - editNewEndOffset &&
        _hasNoCrOrNul(newSource, editStartOffset, editNewEndOffset)) {
      if (editStartOffset == editOldEndOffset &&
          editStartOffset == editNewEndOffset &&
          prevDoc.source == newSource) {
        return IncrementalParseResult(
          document: prevDoc,
          reusedBlockCount: prevDoc.blocks.length,
          reparsedBlockCount: 0,
        );
      }
      newNorm = newSource;
      prefixLen = editStartOffset;
      oldDirtyEndLimit = editOldEndOffset;
      newDirtyEndLimit = editNewEndOffset;
    } else if (oldNormUnchanged &&
        editStartOffset != null &&
        editOldEndOffset == null &&
        editNewEndOffset == null &&
        editStartOffset >= 0 &&
        editStartOffset <= oldNorm.length &&
        editStartOffset <= newSource.length) {
      final int minLen = oldNorm.length < newSource.length
          ? oldNorm.length
          : newSource.length;
      final int suffixLen = _commonSuffixLen(
        oldNorm,
        newSource,
        minLen - editStartOffset,
      );
      final int candidateNewDirtyEnd = newSource.length - suffixLen;
      if (_hasNoCrOrNul(newSource, editStartOffset, candidateNewDirtyEnd)) {
        newNorm = newSource;
        prefixLen = editStartOffset;
        oldDirtyEndLimit = oldNorm.length - suffixLen;
        newDirtyEndLimit = candidateNewDirtyEnd;
      } else {
        newNorm = normalizeMarkdownSource(newSource);
        final int normMinLen = oldNorm.length < newNorm.length
            ? oldNorm.length
            : newNorm.length;
        prefixLen = _commonPrefixLen(oldNorm, newNorm);
        if (editStartOffset < prefixLen) {
          prefixLen = editStartOffset;
        }
        final int normSuffixLen = _commonSuffixLen(
          oldNorm,
          newNorm,
          normMinLen - prefixLen,
        );
        oldDirtyEndLimit = oldNorm.length - normSuffixLen;
        newDirtyEndLimit = newNorm.length - normSuffixLen;
      }
    } else if (oldNormUnchanged && editStartOffset == null) {
      prefixLen = _commonPrefixLen(oldNorm, newSource);
      if (prefixLen == oldNorm.length && oldNorm.length == newSource.length) {
        return IncrementalParseResult(
          document: prevDoc,
          reusedBlockCount: prevDoc.blocks.length,
          reparsedBlockCount: 0,
        );
      }
      final int minLen = oldNorm.length < newSource.length
          ? oldNorm.length
          : newSource.length;
      final int suffixLen = _commonSuffixLen(
        oldNorm,
        newSource,
        minLen - prefixLen,
      );
      final int candidateNewDirtyEnd = newSource.length - suffixLen;
      if (_hasNoCrOrNul(newSource, prefixLen, candidateNewDirtyEnd)) {
        newNorm = newSource;
        oldDirtyEndLimit = oldNorm.length - suffixLen;
        newDirtyEndLimit = candidateNewDirtyEnd;
      } else {
        newNorm = normalizeMarkdownSource(newSource);
        final int normMinLen = oldNorm.length < newNorm.length
            ? oldNorm.length
            : newNorm.length;
        prefixLen = _commonPrefixLen(oldNorm, newNorm);
        final int normSuffixLen = _commonSuffixLen(
          oldNorm,
          newNorm,
          normMinLen - prefixLen,
        );
        oldDirtyEndLimit = oldNorm.length - normSuffixLen;
        newDirtyEndLimit = newNorm.length - normSuffixLen;
      }
    } else {
      newNorm = normalizeMarkdownSource(newSource);
      if (oldNorm == newNorm && prevDoc.source == newSource) {
        return IncrementalParseResult(
          document: prevDoc,
          reusedBlockCount: prevDoc.blocks.length,
          reparsedBlockCount: 0,
        );
      }
      final int minLen = oldNorm.length < newNorm.length
          ? oldNorm.length
          : newNorm.length;
      prefixLen = _commonPrefixLen(oldNorm, newNorm);
      if (editStartOffset != null && editStartOffset < prefixLen) {
        prefixLen = editStartOffset < 0 ? 0 : editStartOffset;
      }
      final int suffixLen = _commonSuffixLen(
        oldNorm,
        newNorm,
        minLen - prefixLen,
      );
      oldDirtyEndLimit = oldNorm.length - suffixLen;
      newDirtyEndLimit = newNorm.length - suffixLen;
    }

    // Binary-search reusable prefix/suffix blocks in O(log B) instead of
    // linearly scanning all document blocks.
    final List<MarkdownBlockNode> prevBlocks = rawDocumentBlocks(prevDoc);
    final int searchLimit =
        prevBlocks.isNotEmpty && prevBlocks.last is FootnoteSectionNode
        ? prevBlocks.length - 1
        : prevBlocks.length;

    int lo = 0;
    int hi = searchLimit;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (prevBlocks[mid].span.endOffset < prefixLen) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    int prefixCount = lo;
    while (prefixCount > 0 &&
        !_isSafePrefixReuse(
          prevBlocks[prefixCount - 1],
          oldNorm,
          newNorm,
          prefixLen,
        )) {
      prefixCount--;
    }

    // Check if frontmatter was touched or newly introduced.
    if (effective.frontmatter &&
        prefixCount == 0 &&
        (prevDoc.frontmatter != null ||
            newNorm.startsWith('---') ||
            newNorm.startsWith('+++'))) {
      return _fullReparse(newSource, effective);
    }

    int dirtyOldStart = 0;
    int dirtyStartLine = 1;
    if (prefixCount > 0) {
      final MarkdownBlockNode lastPrefix = prevBlocks[prefixCount - 1];
      dirtyOldStart = lastPrefix.span.endOffset;
      dirtyStartLine = lastPrefix.span.endLine + 1;
      while (dirtyOldStart < prefixLen &&
          oldNorm.codeUnitAt(dirtyOldStart) == 0x0A) {
        dirtyOldStart++;
        dirtyStartLine++;
      }
    }

    // Identify reusable suffix blocks in O(log B).
    final int offsetDelta = newNorm.length - oldNorm.length;
    lo = prefixCount;
    hi = searchLimit;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      final int s = prevBlocks[mid].span.startOffset;
      if (s > oldDirtyEndLimit && s > dirtyOldStart) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    int suffixStartIdx = lo;
    while (suffixStartIdx < searchLimit &&
        !_isSafeSuffixReuse(
          prevBlocks[suffixStartIdx],
          oldNorm,
          oldDirtyEndLimit,
          dirtyOldStart,
        )) {
      suffixStartIdx++;
    }

    // Apply container-merge boundary guards at prefix/suffix edges so loose
    // lists, definition lists, and HTML containers (<details>/<figure>/<div align>)
    // cannot fail to merge or pair across the dirty slice boundary.
    while (prefixCount > 0 &&
        (isPotentialHtmlContainerBoundary(
              prevBlocks[prefixCount - 1],
              effective,
            ) ||
            _mayInteractWithPrefixContainer(
              prevBlocks[prefixCount - 1],
              oldNorm,
              newNorm,
              dirtyOldStart,
              oldDirtyEndLimit,
              newDirtyEndLimit,
            ))) {
      prefixCount--;
      if (prefixCount > 0) {
        final MarkdownBlockNode b = prevBlocks[prefixCount - 1];
        dirtyOldStart = b.span.endOffset;
        dirtyStartLine = b.span.endLine + 1;
        while (dirtyOldStart < prefixLen &&
            oldNorm.codeUnitAt(dirtyOldStart) == 0x0A) {
          dirtyOldStart++;
          dirtyStartLine++;
        }
      } else {
        dirtyOldStart = 0;
        dirtyStartLine = 1;
      }
    }

    int dirtyOldEnd = suffixStartIdx < searchLimit
        ? prevBlocks[suffixStartIdx].span.startOffset
        : oldNorm.length;
    while (dirtyOldEnd > oldDirtyEndLimit &&
        oldNorm.codeUnitAt(dirtyOldEnd - 1) == 0x0A) {
      dirtyOldEnd--;
    }

    while (suffixStartIdx < searchLimit &&
        (isPotentialHtmlContainerBoundary(
              prevBlocks[suffixStartIdx],
              effective,
            ) ||
            _mayInteractWithSuffixContainer(
              prevBlocks[suffixStartIdx],
              oldNorm,
              newNorm,
              dirtyOldStart,
              dirtyOldEnd,
              dirtyOldEnd + offsetDelta,
            ))) {
      suffixStartIdx++;
      dirtyOldEnd = suffixStartIdx < searchLimit
          ? prevBlocks[suffixStartIdx].span.startOffset
          : oldNorm.length;
      while (dirtyOldEnd > oldDirtyEndLimit &&
          oldNorm.codeUnitAt(dirtyOldEnd - 1) == 0x0A) {
        dirtyOldEnd--;
      }
    }

    final int dirtyNewStart = dirtyOldStart;
    final int dirtyNewEnd = dirtyOldEnd + offsetDelta;
    final int suffixCount = searchLimit - suffixStartIdx;
    if (dirtyNewStart > dirtyNewEnd ||
        dirtyNewEnd > newNorm.length ||
        dirtyOldStart > dirtyOldEnd ||
        dirtyOldEnd > oldNorm.length ||
        (prefixCount == 0 && suffixCount == 0)) {
      return _fullReparse(newSource, effective);
    }

    final String oldDirtySlice = oldNorm.substring(dirtyOldStart, dirtyOldEnd);
    final String newDirtySlice = newNorm.substring(dirtyNewStart, dirtyNewEnd);

    // If link/footnote/abbreviation definitions might reside in or be affected
    // by the dirty slice, fall back cleanly to full parse.
    if (prevDoc.footnotes.isNotEmpty ||
        mightContainDefinitionLine(oldDirtySlice) ||
        mightContainDefinitionLine(newDirtySlice)) {
      return _fullReparse(newSource, effective);
    }

    if ((effective.detailsBlocks ||
            effective.figureBlocks ||
            effective.alignedBlocks) &&
        (oldDirtySlice.contains('<') || newDirtySlice.contains('<'))) {
      for (int k = 0; k < prefixCount; k++) {
        if (prevBlocks[k] is HtmlBlockNode) {
          return _fullReparse(newSource, effective);
        }
      }
      for (int k = suffixStartIdx; k < searchLimit; k++) {
        if (prevBlocks[k] is HtmlBlockNode) {
          return _fullReparse(newSource, effective);
        }
      }
    }

    final int? prevIdGen = cachedIdGeneration(prevDoc);
    final int nextIdGen = prevIdGen != null ? prevIdGen + 1 : 0;
    final String dirtyIdPrefix = prevIdGen != null
        ? 'inc$nextIdGen-'
        : _pickDisjointIdPrefix(
            prevBlocks,
            prefixCount,
            suffixStartIdx,
            searchLimit,
          );

    // Parse only the dirty slice (avoiding frontmatter unless dirtyStart == 0).
    final MarkdownOptions sliceOptions = dirtyNewStart == 0
        ? effective
        : effective.copyWith(frontmatter: false);
    final Phase1Result dirtyPhase1 = parseBlocks(
      newDirtySlice,
      sliceOptions,
      baseOffset: dirtyNewStart,
      baseLine: dirtyStartLine,
      idPrefix: dirtyIdPrefix,
    );

    if (dirtyPhase1.linkDefinitions.isNotEmpty ||
        dirtyPhase1.footnoteDefinitions.isNotEmpty ||
        dirtyPhase1.abbreviations.isNotEmpty) {
      return _fullReparse(newSource, effective);
    }

    // Resolve inlines inside the dirty slice using document link definitions
    // AND document abbreviations.
    final Phase1Result resolvedSlicePhase1 = Phase1Result(
      blocks: dirtyPhase1.blocks,
      frontmatter: dirtyPhase1.frontmatter,
      linkDefinitions: prevDoc.linkDefinitions,
      footnoteDefinitions: const <String, RawFootnoteDef>{},
      abbreviations: prevDoc.abbreviations,
      normalizedSource: dirtyPhase1.normalizedSource,
      idPrefix: dirtyPhase1.idPrefix,
    );
    final Phase2Result dirtyPhase2 = parseInlines(
      resolvedSlicePhase1,
      sliceOptions,
    );

    // Compute line delta for shifted suffix blocks (O(1) lazy shift per block).
    final int oldDirtyLines = _countNewlines(oldDirtySlice);
    final int newDirtyLines = _countNewlines(newDirtySlice);
    final int lineDelta = newDirtyLines - oldDirtyLines;

    final List<MarkdownBlockNode> dirtyBlocks = dirtyPhase2.blocks;
    final int dirtyCount = dirtyBlocks.length;
    final int totalLen = prefixCount + dirtyCount + suffixCount;
    final List<MarkdownBlockNode> combined;
    if (totalLen == 0) {
      combined = const <MarkdownBlockNode>[];
    } else {
      final MarkdownBlockNode sentinel = prefixCount > 0
          ? prevBlocks[0]
          : (dirtyCount > 0 ? dirtyBlocks[0] : prevBlocks[suffixStartIdx]);
      final List<MarkdownBlockNode> fixed = List<MarkdownBlockNode>.filled(
        totalLen,
        sentinel,
        growable: false,
      );
      for (int i = 0; i < prefixCount; i++) {
        fixed[i] = prevBlocks[i];
      }
      for (int i = 0; i < dirtyCount; i++) {
        fixed[prefixCount + i] = dirtyBlocks[i];
      }
      final int suffixDest = prefixCount + dirtyCount;
      for (int i = 0; i < suffixCount; i++) {
        fixed[suffixDest + i] = prevBlocks[suffixStartIdx + i].shiftSpan(
          offsetDelta,
          lineDelta,
        );
      }
      combined = fixed;
    }

    bool oldMiddleHadHeading = false;
    for (int i = prefixCount; i < suffixStartIdx; i++) {
      if (blockContainsHeading(prevBlocks[i])) {
        oldMiddleHadHeading = true;
        break;
      }
    }
    final bool headingsChanged =
        oldMiddleHadHeading || containsHeadingInBlocks(dirtyBlocks);

    final List<MarkdownBlockNode> finalBlocks;
    final List<MarkdownOutlineItem> outline;
    if (!headingsChanged) {
      finalBlocks = wrapFixedUnmodifiableList(combined);
      outline = _shiftUnchangedOutline(
        rawDocumentOutline(prevDoc),
        dirtyOldStart: dirtyOldStart,
        dirtyOldEnd: dirtyOldEnd,
        offsetDelta: offsetDelta,
        lineDelta: lineDelta,
      );
    } else if (effective.headingSlugs) {
      final ({
        List<MarkdownBlockNode> blocks,
        List<MarkdownOutlineItem> outline,
      })
      rebuilt = recomputeSlugsAndOutline(combined, effective);
      finalBlocks = freezeList(rebuilt.blocks);
      outline = freezeList(rebuilt.outline);
    } else {
      finalBlocks = wrapFixedUnmodifiableList(combined);
      outline = freezeList(
        collectOutlineFromBlocks(combined, options: effective),
      );
    }

    final List<String> prevRemoteImages = rawDocumentRemoteImages(prevDoc);
    final List<String> remoteImages;
    if (prevRemoteImages.isEmpty && dirtyPhase2.remoteImageAddresses.isEmpty) {
      remoteImages = const <String>[];
    } else {
      final List<String> oldMiddleImages = suffixStartIdx > prefixCount
          ? collectRemoteImagesFromBlocks(
              prevBlocks.sublist(prefixCount, suffixStartIdx),
            )
          : const <String>[];
      if (oldMiddleImages.isEmpty && dirtyPhase2.remoteImageAddresses.isEmpty) {
        remoteImages = prevRemoteImages;
      } else {
        remoteImages = freezeList(collectRemoteImagesFromBlocks(finalBlocks));
      }
    }

    final MarkdownDocument resultDoc = MarkdownDocument(
      source: newSource,
      options: effective,
      blocks: finalBlocks,
      frontmatter: prevDoc.frontmatter,
      outline: outline,
      footnotes: prevDoc.footnotes,
      remoteImageAddresses: remoteImages,
      linkDefinitions: prevDoc.linkDefinitions,
      abbreviations: prevDoc.abbreviations,
      normalizedSource: newNorm,
      idGeneration: prevIdGen != null ? nextIdGen : null,
    );

    final int _ = newDirtyEndLimit;
    return IncrementalParseResult(
      document: resultDoc,
      reusedBlockCount: prefixCount + suffixCount,
      reparsedBlockCount: dirtyCount,
    );
  }

  IncrementalParseResult _fullReparse(
    String newSource,
    MarkdownOptions effective,
  ) {
    final MarkdownDocument full = engine.parse(newSource, options: effective);
    return IncrementalParseResult(
      document: full,
      reusedBlockCount: 0,
      reparsedBlockCount: full.blocks.length,
    );
  }

  bool _isSafePrefixReuse(
    MarkdownBlockNode block,
    String oldNorm,
    String newNorm,
    int prefixLen,
  ) {
    final int end = block.span.endOffset;
    if (end <= 0 || end >= prefixLen) {
      return false;
    }
    // Must end on a newline AND have a blank line strictly inside common prefix
    // after the block so the edit cannot convert the trailing line into a
    // setext heading, table header, list continuation, or paragraph merge.
    if (end >= oldNorm.length ||
        oldNorm.codeUnitAt(end - 1) != 0x0A ||
        oldNorm.codeUnitAt(end) != 0x0A ||
        newNorm.codeUnitAt(end) != 0x0A) {
      return false;
    }
    return prefixLen > end;
  }

  bool _isSafeSuffixReuse(
    MarkdownBlockNode block,
    String oldNorm,
    int oldDirtyEndLimit,
    int dirtyOldStart,
  ) {
    final int start = block.span.startOffset;
    if (start <= dirtyOldStart || start <= oldDirtyEndLimit) {
      return false;
    }
    // Require a blank line strictly after `oldDirtyEndLimit` and immediately
    // before `block.span.startOffset`.
    if (start < 2 ||
        oldNorm.codeUnitAt(start - 1) != 0x0A ||
        oldNorm.codeUnitAt(start - 2) != 0x0A) {
      return false;
    }
    return start - 2 >= oldDirtyEndLimit;
  }

  bool _mayInteractWithPrefixContainer(
    MarkdownBlockNode block,
    String oldNorm,
    String newNorm,
    int dirtyOldStart,
    int oldDirtyEndLimit,
    int newDirtyEndLimit,
  ) {
    if (block is ListNode) {
      return _firstNonSpaceLineCouldMergeList(
            oldNorm,
            dirtyOldStart,
            oldDirtyEndLimit,
          ) ||
          _firstNonSpaceLineCouldMergeList(
            newNorm,
            dirtyOldStart,
            newDirtyEndLimit,
          );
    }
    if (block is DefinitionListNode) {
      return _firstNonSpaceLineCouldMergeDefList(
            oldNorm,
            dirtyOldStart,
            oldDirtyEndLimit,
          ) ||
          _firstNonSpaceLineCouldMergeDefList(
            newNorm,
            dirtyOldStart,
            newDirtyEndLimit,
          );
    }
    return false;
  }

  bool _mayInteractWithSuffixContainer(
    MarkdownBlockNode block,
    String oldNorm,
    String newNorm,
    int dirtyOldStart,
    int dirtyOldEnd,
    int dirtyNewEnd,
  ) {
    if (block is ListNode) {
      return _lastNonEmptyLineCouldMergeList(
            oldNorm,
            dirtyOldStart,
            dirtyOldEnd,
          ) ||
          _lastNonEmptyLineCouldMergeList(newNorm, dirtyOldStart, dirtyNewEnd);
    }
    return false;
  }

  bool _firstNonSpaceLineCouldMergeList(String text, int start, int limit) {
    int i = start;
    while (i < limit && text.codeUnitAt(i) == 0x0A) {
      i++;
    }
    if (i >= limit) {
      return false;
    }
    return _lineStartsWithListOrIndent(text, i, limit);
  }

  bool _lastNonEmptyLineCouldMergeList(String text, int start, int end) {
    if (end <= start) {
      return false;
    }
    int i = end;
    while (i > start && text.codeUnitAt(i - 1) == 0x0A) {
      i--;
    }
    if (i <= start) {
      return false;
    }
    // Check last block in dirty slice (after last `\n\n` or from start).
    int blockStart = text.lastIndexOf('\n\n', i - 1);
    blockStart = blockStart < start ? start : blockStart + 2;
    while (blockStart < i && text.codeUnitAt(blockStart) == 0x0A) {
      blockStart++;
    }
    if (blockStart >= i) {
      return false;
    }
    return _lineStartsWithListOrIndent(text, blockStart, i);
  }

  bool _lineStartsWithListOrIndent(String text, int lineStart, int limit) {
    int i = lineStart;
    int spaces = 0;
    while (i < limit && i < text.length) {
      final int cu = text.codeUnitAt(i);
      if (cu == 0x20) {
        spaces++;
        i++;
      } else if (cu == 0x09) {
        return true;
      } else {
        break;
      }
    }
    if (spaces >= 2) {
      return true;
    }
    if (i >= limit || i >= text.length) {
      return false;
    }
    final int first = text.codeUnitAt(i);
    if (first == 0x2D || first == 0x2B || first == 0x2A) {
      return i + 1 >= text.length ||
          text.codeUnitAt(i + 1) == 0x20 ||
          text.codeUnitAt(i + 1) == 0x09 ||
          text.codeUnitAt(i + 1) == 0x0A;
    }
    if (first >= 0x30 && first <= 0x39) {
      int k = i;
      int digits = 0;
      while (k < limit &&
          k < text.length &&
          digits < 9 &&
          text.codeUnitAt(k) >= 0x30 &&
          text.codeUnitAt(k) <= 0x39) {
        k++;
        digits++;
      }
      if (k < text.length &&
          (text.codeUnitAt(k) == 0x2E || text.codeUnitAt(k) == 0x29)) {
        return true;
      }
    }
    return false;
  }

  bool _firstNonSpaceLineCouldMergeDefList(String text, int start, int limit) {
    int i = start;
    while (i < limit && text.codeUnitAt(i) == 0x0A) {
      i++;
    }
    if (i >= limit || i >= text.length) {
      return false;
    }
    final int cu = text.codeUnitAt(i);
    return cu == 0x3A || cu == 0x20 || cu == 0x09;
  }

  int _countNewlines(String s) {
    int count = 0;
    for (int i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) == 0x0A) {
        count++;
      }
    }
    return count;
  }

  String _pickDisjointIdPrefix(
    List<MarkdownBlockNode> blocks,
    int prefixEnd,
    int suffixStart,
    int suffixEnd,
  ) {
    int maxGen = 0;
    void scanRange(int from, int to) {
      for (int i = from; i < to; i++) {
        final String id = blocks[i].blockId;
        if (id.length > 4 &&
            id.codeUnitAt(0) == 0x69 &&
            id.codeUnitAt(1) == 0x6E &&
            id.codeUnitAt(2) == 0x63) {
          final int dash = id.indexOf('-', 3);
          if (dash > 3) {
            final int? g = int.tryParse(id.substring(3, dash));
            if (g != null && g > maxGen) {
              maxGen = g;
            }
          }
        }
      }
    }

    scanRange(0, prefixEnd);
    scanRange(suffixStart, suffixEnd);
    return 'inc${maxGen + 1}-';
  }

  List<MarkdownOutlineItem> _shiftUnchangedOutline(
    List<MarkdownOutlineItem> prevOutline, {
    required int dirtyOldStart,
    required int dirtyOldEnd,
    required int offsetDelta,
    required int lineDelta,
  }) {
    if (prevOutline.isEmpty ||
        (offsetDelta == 0 && lineDelta == 0) ||
        prevOutline.last.span.startOffset < dirtyOldEnd) {
      return prevOutline;
    }
    final int len = prevOutline.length;
    final List<MarkdownOutlineItem> out = List<MarkdownOutlineItem>.filled(
      len,
      prevOutline[0],
      growable: false,
    );
    for (int i = 0; i < len; i++) {
      final MarkdownOutlineItem item = prevOutline[i];
      out[i] = item.span.startOffset >= dirtyOldEnd
          ? MarkdownOutlineItem(
              text: item.text,
              level: item.level,
              line: item.line + lineDelta,
              slug: item.slug,
              span: item.span.shift(offsetDelta, lineDelta),
            )
          : item;
    }
    return wrapFixedUnmodifiableList(out);
  }
}

bool _hasNoCrOrNul(String text, int start, int end) {
  for (int i = start; i < end; i++) {
    final int cu = text.codeUnitAt(i);
    if (cu == 0x0D || cu == 0x00) {
      return false;
    }
  }
  return true;
}

int _commonPrefixLen(String a, String b) {
  final int minLen = a.length < b.length ? a.length : b.length;
  int p = 0;
  if (minLen >= 16384) {
    const int step = 8192;
    while (p + step <= minLen && b.startsWith(a.substring(p, p + step), p)) {
      p += step;
    }
  }
  final int minLen8 = minLen - 7;
  while (p < minLen8) {
    final int diff =
        (a.codeUnitAt(p) ^ b.codeUnitAt(p)) |
        (a.codeUnitAt(p + 1) ^ b.codeUnitAt(p + 1)) |
        (a.codeUnitAt(p + 2) ^ b.codeUnitAt(p + 2)) |
        (a.codeUnitAt(p + 3) ^ b.codeUnitAt(p + 3)) |
        (a.codeUnitAt(p + 4) ^ b.codeUnitAt(p + 4)) |
        (a.codeUnitAt(p + 5) ^ b.codeUnitAt(p + 5)) |
        (a.codeUnitAt(p + 6) ^ b.codeUnitAt(p + 6)) |
        (a.codeUnitAt(p + 7) ^ b.codeUnitAt(p + 7));
    if (diff != 0) {
      break;
    }
    p += 8;
  }
  while (p < minLen && a.codeUnitAt(p) == b.codeUnitAt(p)) {
    p++;
  }
  return p;
}

int _commonSuffixLen(String a, String b, int maxSuffix) {
  if (maxSuffix <= 0) {
    return 0;
  }
  final int aLen = a.length;
  final int bLen = b.length;
  int s = 0;
  if (maxSuffix >= 16384) {
    const int step = 8192;
    while (s + step <= maxSuffix &&
        b.startsWith(a.substring(aLen - s - step, aLen - s), bLen - s - step)) {
      s += step;
    }
  }
  int ai = aLen - 1 - s;
  int bi = bLen - 1 - s;
  final int maxS8 = maxSuffix - 7;
  while (s < maxS8) {
    final int diff =
        (a.codeUnitAt(ai) ^ b.codeUnitAt(bi)) |
        (a.codeUnitAt(ai - 1) ^ b.codeUnitAt(bi - 1)) |
        (a.codeUnitAt(ai - 2) ^ b.codeUnitAt(bi - 2)) |
        (a.codeUnitAt(ai - 3) ^ b.codeUnitAt(bi - 3)) |
        (a.codeUnitAt(ai - 4) ^ b.codeUnitAt(bi - 4)) |
        (a.codeUnitAt(ai - 5) ^ b.codeUnitAt(bi - 5)) |
        (a.codeUnitAt(ai - 6) ^ b.codeUnitAt(bi - 6)) |
        (a.codeUnitAt(ai - 7) ^ b.codeUnitAt(bi - 7));
    if (diff != 0) {
      break;
    }
    s += 8;
    ai -= 8;
    bi -= 8;
  }
  while (s < maxSuffix && a.codeUnitAt(ai) == b.codeUnitAt(bi)) {
    s++;
    ai--;
    bi--;
  }
  return s;
}
