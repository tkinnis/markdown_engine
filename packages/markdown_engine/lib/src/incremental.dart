import 'package:meta/meta.dart';

import 'ast.dart';
import 'block_parser.dart';
import 'document.dart';
import 'engine.dart';
import 'inline_parser.dart';
import 'options.dart';
import 'slugs.dart';

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

    if (prevDoc.source == newSource) {
      return IncrementalParseResult(
        document: prevDoc,
        reusedBlockCount: prevDoc.blocks.length,
        reparsedBlockCount: 0,
      );
    }

    final String oldNorm = normalizeMarkdownSource(prevDoc.source);
    final String newNorm = normalizeMarkdownSource(newSource);

    // Compute exact common prefix and non-overlapping common suffix.
    int prefixLen = 0;
    final int minLen = oldNorm.length < newNorm.length
        ? oldNorm.length
        : newNorm.length;
    while (prefixLen < minLen &&
        oldNorm.codeUnitAt(prefixLen) == newNorm.codeUnitAt(prefixLen)) {
      prefixLen++;
    }
    if (editStartOffset != null && editStartOffset < prefixLen) {
      prefixLen = editStartOffset < 0 ? 0 : editStartOffset;
    }

    int suffixLen = 0;
    while (suffixLen < minLen - prefixLen &&
        oldNorm.codeUnitAt(oldNorm.length - 1 - suffixLen) ==
            newNorm.codeUnitAt(newNorm.length - 1 - suffixLen)) {
      suffixLen++;
    }

    final int oldDirtyEndLimit = oldNorm.length - suffixLen;
    final int newDirtyEndLimit = newNorm.length - suffixLen;

    // Identify reusable prefix blocks strictly separated by blank lines
    // before `prefixLen`.
    final List<MarkdownBlockNode> prevBlocks = prevDoc.blocks;
    final List<MarkdownBlockNode> prefixReused = <MarkdownBlockNode>[];
    int dirtyOldStart = 0;
    int dirtyStartLine = 1;

    for (final MarkdownBlockNode block in prevBlocks) {
      if (block is FootnoteSectionNode) {
        break;
      }
      if (!_isSafePrefixReuse(block, oldNorm, newNorm, prefixLen)) {
        break;
      }
      prefixReused.add(block);
      dirtyOldStart = block.span.endOffset;
      dirtyStartLine = block.span.endLine + 1;
      // Advance over blank separator line(s) up to prefixLen if aligned.
      while (dirtyOldStart < prefixLen &&
          oldNorm.codeUnitAt(dirtyOldStart) == 0x0A) {
        dirtyOldStart++;
        dirtyStartLine++;
      }
    }

    // Check if frontmatter was touched or newly introduced.
    if (effective.frontmatter &&
        prefixReused.isEmpty &&
        (prevDoc.frontmatter != null ||
            newNorm.startsWith('---') ||
            newNorm.startsWith('+++'))) {
      return _fullReparse(newSource, effective);
    }

    // Identify reusable suffix blocks strictly after a blank line in suffix.
    final int offsetDelta = newNorm.length - oldNorm.length;
    final List<MarkdownBlockNode> suffixCandidates = <MarkdownBlockNode>[];
    int dirtyOldEnd = oldNorm.length;

    for (int i = prevBlocks.length - 1; i >= prefixReused.length; i--) {
      final MarkdownBlockNode block = prevBlocks[i];
      if (block is FootnoteSectionNode) {
        continue;
      }
      if (!_isSafeSuffixReuse(
        block,
        oldNorm,
        oldDirtyEndLimit,
        dirtyOldStart,
      )) {
        break;
      }
      suffixCandidates.add(block);
      dirtyOldEnd = block.span.startOffset;
      while (dirtyOldEnd > oldDirtyEndLimit &&
          oldNorm.codeUnitAt(dirtyOldEnd - 1) == 0x0A) {
        dirtyOldEnd--;
      }
    }
    final List<MarkdownBlockNode> suffixOrder = suffixCandidates.reversed
        .toList(growable: false);

    final int dirtyNewStart = dirtyOldStart;
    final int dirtyNewEnd = dirtyOldEnd + offsetDelta;
    if (dirtyNewStart > dirtyNewEnd ||
        dirtyNewEnd > newNorm.length ||
        dirtyOldStart > dirtyOldEnd ||
        dirtyOldEnd > oldNorm.length ||
        (prefixReused.isEmpty && suffixOrder.isEmpty)) {
      return _fullReparse(newSource, effective);
    }

    final String oldDirtySlice = oldNorm.substring(dirtyOldStart, dirtyOldEnd);
    final String newDirtySlice = newNorm.substring(dirtyNewStart, dirtyNewEnd);

    // If link definitions, footnote definitions, or abbreviations might reside
    // in or be affected by the dirty slice, verify cleanly.
    if (prevDoc.footnotes.isNotEmpty ||
        _looksLikeDefinition(oldDirtySlice) ||
        _looksLikeDefinition(newDirtySlice)) {
      return _fullReparse(newSource, effective);
    }

    final String dirtyIdPrefix = _pickDisjointIdPrefix(
      prefixReused,
      suffixOrder,
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
    // (if any existed in reused prefix/suffix).
    final Phase1Result resolvedSlicePhase1 = Phase1Result(
      blocks: dirtyPhase1.blocks,
      frontmatter: dirtyPhase1.frontmatter,
      linkDefinitions: prevDoc.linkDefinitions,
      footnoteDefinitions: const <String, RawFootnoteDef>{},
      abbreviations: const <String, String>{},
      normalizedSource: dirtyPhase1.normalizedSource,
    );
    final Phase2Result dirtyPhase2 = parseInlines(
      resolvedSlicePhase1,
      sliceOptions,
    );

    // Compute line delta for shifted suffix blocks.
    final int oldDirtyLines = _countNewlines(oldDirtySlice);
    final int newDirtyLines = _countNewlines(newDirtySlice);
    final int lineDelta = newDirtyLines - oldDirtyLines;

    final List<MarkdownBlockNode> shiftedSuffix = suffixOrder
        .map((MarkdownBlockNode b) => b.shiftSpan(offsetDelta, lineDelta))
        .toList(growable: false);

    // If heading slugs are enabled and headings changed across prefix/dirty/suffix,
    // recompute outline and heading slugs if any slug collision is possible.
    final List<MarkdownBlockNode> combined = <MarkdownBlockNode>[
      ...prefixReused,
      ...dirtyPhase2.blocks,
      ...shiftedSuffix,
    ];

    final List<MarkdownBlockNode> oldMiddleBlocks = prevBlocks.sublist(
      prefixReused.length,
      prevBlocks.length - suffixOrder.length,
    );
    final bool headingsChanged =
        _containsHeading(oldMiddleBlocks) ||
        _containsHeading(dirtyPhase2.blocks);

    final List<MarkdownBlockNode> finalBlocks;
    final List<MarkdownOutlineItem> outline;
    if (effective.headingSlugs && headingsChanged) {
      final ({
        List<MarkdownBlockNode> blocks,
        List<MarkdownOutlineItem> outline,
      })
      rebuilt = _recomputeSlugsAndOutline(combined, effective);
      finalBlocks = rebuilt.blocks;
      outline = rebuilt.outline;
    } else {
      finalBlocks = combined;
      outline = _collectOutlineFromBlocks(combined);
    }

    final List<String> remoteImages =
        prevDoc.remoteImageAddresses.isEmpty && !newDirtySlice.contains('http')
        ? const <String>[]
        : _collectRemoteImages(finalBlocks);
    final MarkdownDocument resultDoc = MarkdownDocument(
      source: newSource,
      options: effective,
      blocks: finalBlocks,
      frontmatter: prevDoc.frontmatter,
      outline: outline,
      footnotes: prevDoc.footnotes,
      remoteImageAddresses: remoteImages,
      linkDefinitions: prevDoc.linkDefinitions,
    );

    final int _ = newDirtyEndLimit;
    return IncrementalParseResult(
      document: resultDoc,
      reusedBlockCount: prefixReused.length + shiftedSuffix.length,
      reparsedBlockCount: dirtyPhase2.blocks.length,
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

  bool _looksLikeDefinition(String slice) {
    return slice.contains(']:');
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
    List<MarkdownBlockNode> prefix,
    List<MarkdownBlockNode> suffix,
  ) {
    int gen = 1;
    while (true) {
      final String candidate = 'inc$gen-';
      bool collision = false;
      for (final MarkdownBlockNode b in prefix) {
        if (b.blockId.startsWith(candidate)) {
          collision = true;
          break;
        }
      }
      if (!collision) {
        for (final MarkdownBlockNode b in suffix) {
          if (b.blockId.startsWith(candidate)) {
            collision = true;
            break;
          }
        }
      }
      if (!collision) {
        return candidate;
      }
      gen++;
    }
  }

  bool _containsHeading(List<MarkdownBlockNode> blocks) {
    for (final MarkdownBlockNode b in blocks) {
      if (b is HeadingNode) {
        return true;
      }
      if (b is BlockQuoteNode && _containsHeading(b.children)) {
        return true;
      }
      if (b is AlertNode && _containsHeading(b.children)) {
        return true;
      }
      if (b is DetailsBlockNode && _containsHeading(b.children)) {
        return true;
      }
    }
    return false;
  }
}

({List<MarkdownBlockNode> blocks, List<MarkdownOutlineItem> outline})
_recomputeSlugsAndOutline(
  List<MarkdownBlockNode> blocks,
  MarkdownOptions options,
) {
  final HeadingSlugGenerator gen = HeadingSlugGenerator();
  final List<MarkdownOutlineItem> outline = <MarkdownOutlineItem>[];

  MarkdownBlockNode visitBlock(MarkdownBlockNode b) {
    if (b is HeadingNode) {
      final String slug = (options.explicitHeadingIds && b.explicitId != null)
          ? b.explicitId!
          : gen.generate(b.text);
      outline.add(
        MarkdownOutlineItem(
          text: b.text,
          level: b.level,
          line: b.span.startLine,
          slug: slug,
          span: b.span,
        ),
      );
      if (slug == b.slug) {
        return b;
      }
      return HeadingNode(
        blockId: b.blockId,
        level: b.level,
        text: b.text,
        slug: slug,
        explicitId: b.explicitId,
        children: b.children,
        isSetext: b.isSetext,
        span: b.span,
      );
    }
    return b;
  }

  final List<MarkdownBlockNode> updated = blocks
      .map(visitBlock)
      .toList(growable: false);
  return (blocks: updated, outline: outline);
}

List<MarkdownOutlineItem> _collectOutlineFromBlocks(
  List<MarkdownBlockNode> blocks,
) {
  final List<MarkdownOutlineItem> out = <MarkdownOutlineItem>[];
  void walk(List<MarkdownBlockNode> list) {
    for (final MarkdownBlockNode b in list) {
      if (b is HeadingNode) {
        out.add(
          MarkdownOutlineItem(
            text: b.text,
            level: b.level,
            line: b.span.startLine,
            slug: b.slug ?? slugifyHeadingText(b.text),
            span: b.span,
          ),
        );
      } else if (b is BlockQuoteNode) {
        walk(b.children);
      } else if (b is AlertNode) {
        walk(b.children);
      } else if (b is DetailsBlockNode) {
        walk(b.children);
      }
    }
  }

  walk(blocks);
  return out;
}

List<String> _collectRemoteImages(List<MarkdownBlockNode> blocks) {
  final List<String> result = <String>[];
  final Set<String> seen = <String>{};

  void addUrl(String url) {
    final String lower = url.toLowerCase();
    if ((lower.startsWith('http://') || lower.startsWith('https://')) &&
        seen.add(url)) {
      result.add(url);
    }
  }

  void walkInlines(List<MarkdownInlineNode> inlines) {
    for (final MarkdownInlineNode n in inlines) {
      if (n is ImageNode) {
        addUrl(n.destination);
        walkInlines(n.children);
      } else if (n is PictureInlineNode) {
        addUrl(n.lightSource);
        addUrl(n.darkSource);
      } else if (n is LinkNode) {
        walkInlines(n.children);
      } else if (n is EmphasisNode) {
        walkInlines(n.children);
      } else if (n is StrongNode) {
        walkInlines(n.children);
      } else if (n is StrikethroughNode) {
        walkInlines(n.children);
      }
    }
  }

  void walkBlocks(List<MarkdownBlockNode> list) {
    for (final MarkdownBlockNode b in list) {
      switch (b) {
        case ParagraphNode():
          walkInlines(b.children);
        case HeadingNode():
          walkInlines(b.children);
        case BlockQuoteNode():
          walkBlocks(b.children);
        case AlertNode():
          walkBlocks(b.children);
        case ListNode():
          for (final ListItemNode item in b.items) {
            walkBlocks(item.children);
          }
        case ListItemNode():
          walkBlocks(b.children);
        case TableNode():
          for (final TableCellNode cell in b.headers) {
            walkInlines(cell.children);
          }
          for (final List<TableCellNode> row in b.rows) {
            for (final TableCellNode cell in row) {
              walkInlines(cell.children);
            }
          }
        case DetailsBlockNode():
          walkInlines(b.summaryInlines);
          walkBlocks(b.children);
        case AlignedBlockNode():
          walkBlocks(b.children);
        case FigureBlockNode():
          walkBlocks(b.children);
          walkInlines(b.captionInlines);
        case DefinitionListNode():
          for (final DefinitionGroup g in b.groups) {
            walkInlines(g.term);
            for (final List<MarkdownBlockNode> def in g.definitions) {
              walkBlocks(def);
            }
          }
        case FootnoteDefinitionNode():
          walkBlocks(b.children);
        case FootnoteSectionNode():
          for (final FootnoteDefinitionNode d in b.definitions) {
            walkBlocks(d.children);
          }
        default:
          break;
      }
    }
  }

  walkBlocks(blocks);
  return result;
}
