import 'ast.dart';
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
      html: '',
    );
  }

  /// Engine used for parsing active slices and final reconciliation.
  final MarkdownEngine engine;

  final MarkdownOptions? _options;

  final StringBuffer _buffer = StringBuffer();
  String _normalizedBuffer = '';
  final List<MarkdownBlockNode> _settledBlocks = <MarkdownBlockNode>[];
  List<MarkdownBlockNode> _activeBlocks = const <MarkdownBlockNode>[];
  int _settledOffset = 0;
  int _settledLine = 1;
  int _tailGeneration = 0;
  MarkdownFrontmatter? _frontmatter;
  bool _hasDefinitions = false;
  bool _isFinished = false;
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

  /// Appends [chunk] to the stream buffer and incrementally updates only the
  /// unsettled trailing blocks.
  MarkdownDocument append(String chunk) {
    if (chunk.isEmpty) {
      return _currentDocument;
    }
    _isFinished = false;
    _buffer.write(chunk);
    final String fullSource = _buffer.toString();
    _reparseTail(fullSource);
    return _currentDocument;
  }

  /// Replaces the entire stream text with [fullText], preserving already
  /// settled prefix blocks when [fullText] retains the exact settled prefix.
  MarkdownDocument replaceText(String fullText) {
    _isFinished = false;
    final String newNorm = normalizeMarkdownSource(fullText);
    _buffer
      ..clear()
      ..write(fullText);

    if (_settledOffset > 0 &&
        newNorm.length >= _settledOffset &&
        _normalizedBuffer.length >= _settledOffset &&
        newNorm.substring(0, _settledOffset) ==
            _normalizedBuffer.substring(0, _settledOffset)) {
      _reparseTail(fullText);
    } else {
      _settledBlocks.clear();
      _activeBlocks = const <MarkdownBlockNode>[];
      _settledOffset = 0;
      _settledLine = 1;
      _tailGeneration = 0;
      _frontmatter = null;
      _hasDefinitions = false;
      _reparseTail(fullText);
    }
    return _currentDocument;
  }

  /// Finalizes the stream, producing the exact same semantic AST and HTML as
  /// `MarkdownEngine.parse(buffer)`.
  MarkdownDocument finish() {
    _isFinished = true;
    final String fullSource = _buffer.toString();
    final MarkdownDocument finalDoc = engine.parse(
      fullSource,
      options: effectiveOptions,
    );
    _settledBlocks
      ..clear()
      ..addAll(finalDoc.blocks);
    _activeBlocks = const <MarkdownBlockNode>[];
    _normalizedBuffer = normalizeMarkdownSource(fullSource);
    _settledOffset = _normalizedBuffer.length;
    _frontmatter = finalDoc.frontmatter;
    _currentDocument = finalDoc;
    return finalDoc;
  }

  /// Clears all buffered text and settled blocks back to an empty state.
  void reset() {
    _buffer.clear();
    _normalizedBuffer = '';
    _settledBlocks.clear();
    _activeBlocks = const <MarkdownBlockNode>[];
    _settledOffset = 0;
    _settledLine = 1;
    _tailGeneration = 0;
    _frontmatter = null;
    _hasDefinitions = false;
    _isFinished = false;
    _currentDocument = MarkdownDocument(
      source: '',
      options: effectiveOptions,
      blocks: const <MarkdownBlockNode>[],
      html: '',
    );
  }

  void _reparseTail(String fullSource) {
    final MarkdownOptions opts = effectiveOptions;
    if (fullSource.length > opts.maxInputLength) {
      throw RangeError.value(
        fullSource.length,
        'buffer.length',
        'Input exceeds maxInputLength (${opts.maxInputLength}).',
      );
    }

    _normalizedBuffer = normalizeMarkdownSource(fullSource);
    if (_normalizedBuffer.isEmpty) {
      _activeBlocks = const <MarkdownBlockNode>[];
      _currentDocument = MarkdownDocument(
        source: fullSource,
        options: opts,
        blocks: const <MarkdownBlockNode>[],
        html: '',
      );
      return;
    }

    // If the document uses definitions/footnotes/references, full document
    // resolution ensures late-arriving definitions resolve accurately; still
    // freeze settled prefix blocks when no definitions exist.
    if (_hasDefinitions || _normalizedBuffer.contains(']:')) {
      _hasDefinitions = true;
      final MarkdownDocument doc = engine.parse(fullSource, options: opts);
      _settledBlocks.clear();
      _activeBlocks = doc.blocks;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = doc.frontmatter;
      _currentDocument = doc;
      return;
    }

    final String tailSlice = _normalizedBuffer.substring(_settledOffset);
    final MarkdownOptions tailOpts = _settledOffset == 0
        ? opts
        : opts.copyWith(frontmatter: false);
    _tailGeneration++;
    final Phase1Result phase1 = parseBlocks(
      tailSlice,
      tailOpts,
      baseOffset: _settledOffset,
      baseLine: _settledLine,
      idPrefix: _settledBlocks.isEmpty ? '' : 's$_tailGeneration-',
    );

    if (phase1.linkDefinitions.isNotEmpty ||
        phase1.footnoteDefinitions.isNotEmpty ||
        phase1.abbreviations.isNotEmpty) {
      _hasDefinitions = true;
      final MarkdownDocument doc = engine.parse(fullSource, options: opts);
      _settledBlocks.clear();
      _activeBlocks = doc.blocks;
      _settledOffset = 0;
      _settledLine = 1;
      _frontmatter = doc.frontmatter;
      _currentDocument = doc;
      return;
    }

    if (_settledOffset == 0 && phase1.frontmatter != null) {
      _frontmatter = phase1.frontmatter!.frontmatter;
    }

    final Phase2Result phase2 = parseInlines(phase1, tailOpts);
    final List<MarkdownBlockNode> tailBlocks = phase2.blocks;

    // Settle leading blocks in `tailBlocks` that are guaranteed immutable by
    // having a blank-line boundary and a subsequent block following them.
    int newlySettled = 0;
    while (newlySettled + 1 < tailBlocks.length) {
      final MarkdownBlockNode candidate = tailBlocks[newlySettled];
      final MarkdownBlockNode nextBlock = tailBlocks[newlySettled + 1];
      if (!_canSettleBlock(candidate, nextBlock)) {
        break;
      }
      _settledBlocks.add(candidate);
      newlySettled++;
      int newStart = candidate.span.endOffset;
      int newLine = candidate.span.endLine + 1;
      while (newStart < nextBlock.span.startOffset &&
          newStart < _normalizedBuffer.length &&
          _normalizedBuffer.codeUnitAt(newStart) == 0x0A) {
        newStart++;
        newLine++;
      }
      _settledOffset = newStart;
      _settledLine = newLine;
    }

    _activeBlocks = tailBlocks.sublist(newlySettled);
    final List<MarkdownBlockNode> allBlocks = <MarkdownBlockNode>[
      ..._settledBlocks,
      ..._activeBlocks,
    ];

    final List<MarkdownOutlineItem> outline = _buildOutline(allBlocks);
    final List<String> remoteImages = _collectRemoteImages(allBlocks);
    _currentDocument = MarkdownDocument(
      source: fullSource,
      options: opts,
      blocks: allBlocks,
      frontmatter: _frontmatter,
      outline: outline,
      footnotes: phase2.footnotes,
      remoteImageAddresses: remoteImages,
      linkDefinitions: phase1.linkDefinitions,
    );
  }

  bool _canSettleBlock(MarkdownBlockNode candidate, MarkdownBlockNode next) {
    if (candidate is FrontmatterNode) {
      return true;
    }
    final int end = candidate.span.endOffset;
    if (end <= 0 || end >= next.span.startOffset) {
      return false;
    }
    if (end >= _normalizedBuffer.length ||
        _normalizedBuffer.codeUnitAt(end - 1) != 0x0A ||
        _normalizedBuffer.codeUnitAt(end) != 0x0A) {
      return false;
    }
    // Lists followed by blank lines could still receive another item if
    // `next` is a list of the same type; settle only once a non-list block
    // follows or `candidate` is not a list.
    if (candidate is ListNode && next is ListNode) {
      return false;
    }
    // Never freeze HTML/Details/Figure/Aligned containers prematurely if
    // extended container blocks are enabled and could merge with adjacent HTML.
    if ((effectiveOptions.detailsBlocks ||
            effectiveOptions.figureBlocks ||
            effectiveOptions.alignedBlocks) &&
        candidate is HtmlBlockNode) {
      return false;
    }
    // Definition lists can absorb subsequent `: ` paragraphs.
    if (effectiveOptions.definitionLists && candidate is DefinitionListNode) {
      return false;
    }
    return true;
  }

  List<MarkdownOutlineItem> _buildOutline(List<MarkdownBlockNode> blocks) {
    final List<MarkdownOutlineItem> items = <MarkdownOutlineItem>[];
    void walk(List<MarkdownBlockNode> list) {
      for (final MarkdownBlockNode b in list) {
        if (b is HeadingNode) {
          items.add(
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
    return items;
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
}
