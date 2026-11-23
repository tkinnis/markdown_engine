import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

/// Immutable reading position inside a rendered [MarkdownDocument].
@immutable
final class MarkdownReadingPlace {
  /// Creates a [MarkdownReadingPlace].
  const MarkdownReadingPlace({
    required this.blockIndex,
    this.blockId,
    this.offsetFraction = 0.0,
  }) : assert(blockIndex >= 0, 'blockIndex must be non-negative'),
       assert(
         offsetFraction >= 0.0 && offsetFraction <= 1.0,
         'offsetFraction must be between 0.0 and 1.0',
       );

  /// Initial reading position at the start of the first block.
  static const MarkdownReadingPlace start = MarkdownReadingPlace(blockIndex: 0);

  /// Zero-based index of the active top-level block in the document.
  final int blockIndex;

  /// Optional stable [MarkdownBlockNode.blockId] of the active block.
  final String? blockId;

  /// Fractional scroll progression within the active block (`0.0` to `1.0`).
  final double offsetFraction;

  /// Returns a copy with selected fields replaced.
  MarkdownReadingPlace copyWith({
    int? blockIndex,
    String? blockId,
    double? offsetFraction,
  }) {
    return MarkdownReadingPlace(
      blockIndex: blockIndex ?? this.blockIndex,
      blockId: blockId ?? this.blockId,
      offsetFraction: offsetFraction ?? this.offsetFraction,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownReadingPlace &&
          blockIndex == other.blockIndex &&
          blockId == other.blockId &&
          offsetFraction == other.offsetFraction;

  @override
  int get hashCode => Object.hash(blockIndex, blockId, offsetFraction);

  @override
  String toString() =>
      'MarkdownReadingPlace(blockIndex: $blockIndex, blockId: $blockId, '
      'offsetFraction: ${offsetFraction.toStringAsFixed(2)})';
}

/// Controller coordinating parsed document state, heading outline navigation,
/// parse telemetry, and reading position across Markdown widgets.
final class MarkdownController extends ChangeNotifier {
  /// Creates a [MarkdownController], optionally seeded with [initialDocument].
  MarkdownController({MarkdownDocument? initialDocument})
    : _document = initialDocument ?? const MarkdownDocument(source: '');

  MarkdownDocument _document;
  int _parseCount = 0;
  MarkdownReadingPlace _readingPlace = MarkdownReadingPlace.start;
  ScrollController? _scrollController;
  final Map<String, BuildContext> _anchorContexts = <String, BuildContext>{};
  final Map<String, BuildContext> _blockContexts = <String, BuildContext>{};
  bool _isDisposed = false;
  bool _pendingPostFrameNotify = false;

  /// Most recent [MarkdownDocument] attached to this controller.
  MarkdownDocument get document => _document;

  /// Heading outline entries extracted from [document].
  List<MarkdownOutlineItem> get outline => _document.outline;

  /// Cumulative number of full parses performed by the attached view.
  int get parseCount => _parseCount;

  /// Current tracked reading position inside [document].
  MarkdownReadingPlace get readingPlace => _readingPlace;

  /// Currently attached [ScrollController], if any.
  ScrollController? get scrollController => _scrollController;

  /// Attaches a [ScrollController] to enable programmatic scrolling and reading
  /// progress synchronization.
  void attachScrollController(ScrollController controller) {
    if (identical(_scrollController, controller)) {
      return;
    }
    _scrollController?.removeListener(_handleScrollChange);
    _scrollController = controller;
    _scrollController!.addListener(_handleScrollChange);
  }

  /// Detaches a previously attached [ScrollController].
  void detachScrollController(ScrollController controller) {
    if (!identical(_scrollController, controller)) {
      return;
    }
    _scrollController?.removeListener(_handleScrollChange);
    _scrollController = null;
  }

  /// Records a new [document] snapshot and optionally increments [parseCount].
  void updateDocument(
    MarkdownDocument document, {
    bool incrementParseCount = false,
  }) {
    if (_isDisposed) {
      return;
    }
    final bool docChanged = !identical(_document, document);
    _document = document;
    if (incrementParseCount) {
      _parseCount++;
    }
    if (docChanged || incrementParseCount) {
      _notifySafely();
    }
  }

  /// Registers a mounted [BuildContext] for an anchor slug or ID (headings,
  /// `<a id="...">`, or footnote anchors).
  void registerAnchor(String slug, BuildContext context) {
    if (_isDisposed || slug.isEmpty) {
      return;
    }
    _anchorContexts[_normalizeAnchor(slug)] = context;
  }

  /// Unregisters a previously registered anchor [BuildContext].
  void unregisterAnchor(String slug, BuildContext context) {
    final String key = _normalizeAnchor(slug);
    if (identical(_anchorContexts[key], context)) {
      _anchorContexts.remove(key);
    }
  }

  /// Registers a mounted [BuildContext] for a top-level block [blockId].
  void registerBlock(String blockId, BuildContext context) {
    if (_isDisposed || blockId.isEmpty) {
      return;
    }
    _blockContexts[blockId] = context;
  }

  /// Unregisters a previously registered top-level block [BuildContext].
  void unregisterBlock(String blockId, BuildContext context) {
    if (identical(_blockContexts[blockId], context)) {
      _blockContexts.remove(blockId);
    }
  }

  /// Scrolls to the heading, inline anchor (`<a id="...">`), or footnote
  /// matching [slug].
  ///
  /// Returns `true` if a matching target was located in [document] or among
  /// currently mounted anchors.
  Future<bool> scrollToAnchor(
    String slug, {
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (_isDisposed) {
      return false;
    }
    final String key = _normalizeAnchor(slug);
    if (key.isEmpty) {
      return false;
    }

    final int? targetBlockIndex = _findBlockIndexForAnchor(key);
    final BuildContext? mountedAnchor = _anchorContexts[key];
    if (mountedAnchor != null && mountedAnchor.mounted) {
      if (targetBlockIndex != null) {
        final MarkdownBlockNode block = _document.blocks[targetBlockIndex];
        _setReadingPlace(
          MarkdownReadingPlace(
            blockIndex: targetBlockIndex,
            blockId: block.blockId,
          ),
        );
      }
      await Scrollable.ensureVisible(
        mountedAnchor,
        duration: duration,
        curve: curve,
        alignment: 0.05,
      );
      return true;
    }

    if (targetBlockIndex == null) {
      return false;
    }
    final MarkdownBlockNode block = _document.blocks[targetBlockIndex];
    final bool jumped = await jumpToPlace(
      MarkdownReadingPlace(
        blockIndex: targetBlockIndex,
        blockId: block.blockId,
      ),
      duration: duration,
      curve: curve,
    );
    if (_isDisposed) {
      return jumped;
    }
    final BuildContext? postJumpContext = _anchorContexts[key];
    if (postJumpContext != null && postJumpContext.mounted) {
      await Scrollable.ensureVisible(
        postJumpContext,
        duration: duration,
        curve: curve,
        alignment: 0.05,
      );
    }
    return true;
  }

  /// Scrolls to the top-level block containing 1-based source [line].
  ///
  /// Returns `true` when [document] contains at least one block.
  Future<bool> scrollToLine(
    int line, {
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) async {
    final List<MarkdownBlockNode> blocks = _document.blocks;
    if (_isDisposed || blocks.isEmpty) {
      return false;
    }

    final int clampedLine = line < 1 ? 1 : line;
    int targetIndex = blocks.length - 1;
    double fraction = 0.0;

    for (int i = 0; i < blocks.length; i++) {
      final SourceSpan span = blocks[i].span;
      if (span.startLine <= 0) {
        continue;
      }
      if (clampedLine <= span.endLine) {
        targetIndex = i;
        if (clampedLine >= span.startLine && span.endLine > span.startLine) {
          fraction =
              ((clampedLine - span.startLine) / (span.endLine - span.startLine))
                  .clamp(0.0, 1.0);
        }
        break;
      }
    }

    return jumpToPlace(
      MarkdownReadingPlace(
        blockIndex: targetIndex,
        blockId: blocks[targetIndex].blockId,
        offsetFraction: fraction,
      ),
      duration: duration,
      curve: curve,
    );
  }

  /// Moves the attached scroll view and [readingPlace] to [place].
  Future<bool> jumpToPlace(
    MarkdownReadingPlace place, {
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
  }) async {
    final List<MarkdownBlockNode> blocks = _document.blocks;
    if (_isDisposed || blocks.isEmpty) {
      return false;
    }

    int resolvedIndex = place.blockIndex.clamp(0, blocks.length - 1);
    final String? requestedId = place.blockId;
    if (requestedId != null) {
      for (int i = 0; i < blocks.length; i++) {
        if (blocks[i].blockId == requestedId) {
          resolvedIndex = i;
          break;
        }
      }
    }

    final MarkdownBlockNode targetBlock = blocks[resolvedIndex];
    final MarkdownReadingPlace resolvedPlace = MarkdownReadingPlace(
      blockIndex: resolvedIndex,
      blockId: targetBlock.blockId,
      offsetFraction: place.offsetFraction.clamp(0.0, 1.0),
    );
    _setReadingPlace(resolvedPlace);

    final BuildContext? blockCtx = _blockContexts[targetBlock.blockId];
    if (blockCtx != null && blockCtx.mounted) {
      await Scrollable.ensureVisible(
        blockCtx,
        duration: duration,
        curve: curve,
        alignment: 0.0,
      );
      return true;
    }

    final ScrollController? sc = _scrollController;
    if (sc != null && sc.hasClients && sc.position.hasContentDimensions) {
      final double maxExtent = sc.position.maxScrollExtent;
      final double ratio = blocks.length <= 1
          ? resolvedPlace.offsetFraction
          : ((resolvedIndex + resolvedPlace.offsetFraction) / blocks.length)
                .clamp(0.0, 1.0);
      final double targetOffset = (maxExtent * ratio).clamp(
        sc.position.minScrollExtent,
        maxExtent,
      );
      if (duration == Duration.zero) {
        sc.jumpTo(targetOffset);
      } else {
        await sc.animateTo(targetOffset, duration: duration, curve: curve);
      }
    }
    return true;
  }

  void _handleScrollChange() {
    if (_isDisposed) {
      return;
    }
    final ScrollController? sc = _scrollController;
    final List<MarkdownBlockNode> blocks = _document.blocks;
    if (sc == null ||
        !sc.hasClients ||
        !sc.position.hasContentDimensions ||
        blocks.isEmpty) {
      return;
    }
    final double maxExtent = sc.position.maxScrollExtent;
    final double progress = maxExtent <= 0.0
        ? 0.0
        : (sc.offset / maxExtent).clamp(0.0, 1.0);
    final double scaled = progress * blocks.length;
    final int index = scaled.floor().clamp(0, blocks.length - 1);
    final double fraction = (scaled - index).clamp(0.0, 1.0);
    _setReadingPlace(
      MarkdownReadingPlace(
        blockIndex: index,
        blockId: blocks[index].blockId,
        offsetFraction: fraction,
      ),
    );
  }

  void _setReadingPlace(MarkdownReadingPlace next) {
    if (_readingPlace == next) {
      return;
    }
    _readingPlace = next;
    _notifySafely();
  }

  void _notifySafely() {
    if (_isDisposed || !hasListeners) {
      return;
    }
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_pendingPostFrameNotify) {
        return;
      }
      _pendingPostFrameNotify = true;
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        _pendingPostFrameNotify = false;
        if (!_isDisposed && hasListeners) {
          notifyListeners();
        }
      });
      return;
    }
    notifyListeners();
  }

  int? _findBlockIndexForAnchor(String normalizedSlug) {
    final List<MarkdownBlockNode> blocks = _document.blocks;
    for (int i = 0; i < blocks.length; i++) {
      if (_blockMatchesAnchor(blocks[i], normalizedSlug)) {
        return i;
      }
    }
    return null;
  }

  bool _blockMatchesAnchor(MarkdownBlockNode block, String normalizedSlug) {
    switch (block) {
      case HeadingNode():
        if (block.slug != null &&
            _normalizeAnchor(block.slug!) == normalizedSlug) {
          return true;
        }
        if (block.explicitId != null &&
            _normalizeAnchor(block.explicitId!) == normalizedSlug) {
          return true;
        }
        if (_normalizeAnchor(slugifyHeadingText(block.text)) ==
            normalizedSlug) {
          return true;
        }
        return _inlinesMatchAnchor(block.children, normalizedSlug);
      case ParagraphNode():
        return _inlinesMatchAnchor(block.children, normalizedSlug);
      case BlockQuoteNode():
        return block.children.any(
          (MarkdownBlockNode c) => _blockMatchesAnchor(c, normalizedSlug),
        );
      case AlertNode():
        return block.children.any(
          (MarkdownBlockNode c) => _blockMatchesAnchor(c, normalizedSlug),
        );
      case ListNode():
        return block.items.any(
          (ListItemNode item) => _blockMatchesAnchor(item, normalizedSlug),
        );
      case ListItemNode():
        return block.children.any(
          (MarkdownBlockNode c) => _blockMatchesAnchor(c, normalizedSlug),
        );
      case DetailsBlockNode():
        return _inlinesMatchAnchor(block.summaryInlines, normalizedSlug) ||
            block.children.any(
              (MarkdownBlockNode c) => _blockMatchesAnchor(c, normalizedSlug),
            );
      case AlignedBlockNode():
        return block.children.any(
          (MarkdownBlockNode c) => _blockMatchesAnchor(c, normalizedSlug),
        );
      case FigureBlockNode():
        return _inlinesMatchAnchor(block.captionInlines, normalizedSlug) ||
            block.children.any(
              (MarkdownBlockNode c) => _blockMatchesAnchor(c, normalizedSlug),
            );
      case DefinitionListNode():
        for (final DefinitionGroup g in block.groups) {
          if (_inlinesMatchAnchor(g.term, normalizedSlug)) {
            return true;
          }
          for (final List<MarkdownBlockNode> def in g.definitions) {
            if (def.any(
              (MarkdownBlockNode c) => _blockMatchesAnchor(c, normalizedSlug),
            )) {
              return true;
            }
          }
        }
        return false;
      case FootnoteDefinitionNode():
        return _normalizeAnchor('fn-${block.label}') == normalizedSlug ||
            block.children.any(
              (MarkdownBlockNode c) => _blockMatchesAnchor(c, normalizedSlug),
            );
      case FootnoteSectionNode():
        return block.definitions.any(
          (FootnoteDefinitionNode d) => _blockMatchesAnchor(d, normalizedSlug),
        );
      case FrontmatterNode():
      case CodeBlockNode():
      case TableNode():
      case ThematicBreakNode():
      case HtmlBlockNode():
      case MathBlockNode():
        return false;
    }
  }

  bool _inlinesMatchAnchor(
    List<MarkdownInlineNode> inlines,
    String normalizedSlug,
  ) {
    for (final MarkdownInlineNode node in inlines) {
      switch (node) {
        case AnchorInlineNode():
          if (_normalizeAnchor(node.id) == normalizedSlug) {
            return true;
          }
        case FootnoteRefNode():
          final String suffix = node.occurrenceIndex > 1
              ? '-${node.occurrenceIndex}'
              : '';
          if (_normalizeAnchor('fnref-${node.label}$suffix') ==
              normalizedSlug) {
            return true;
          }
        case EmphasisNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case StrongNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case StrikethroughNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case HighlightNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case SubscriptNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case SuperscriptNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case LinkNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case KbdInlineNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case AbbrInlineNode():
          if (_inlinesMatchAnchor(node.children, normalizedSlug)) {
            return true;
          }
        case ImageNode():
        case TextNode():
        case SoftBreakNode():
        case HardBreakNode():
        case InlineBreakNode():
        case CodeSpanNode():
        case MathInlineNode():
        case PictureInlineNode():
        case RawHtmlInlineNode():
          break;
      }
    }
    return false;
  }

  static String _normalizeAnchor(String raw) {
    final String trimmed = raw.trim();
    final String withoutHash = trimmed.startsWith('#')
        ? trimmed.substring(1)
        : trimmed;
    return withoutHash.toLowerCase();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scrollController?.removeListener(_handleScrollChange);
    _scrollController = null;
    _anchorContexts.clear();
    _blockContexts.clear();
    super.dispose();
  }
}
