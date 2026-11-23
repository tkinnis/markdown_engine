import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show BindingBase, ValueListenable, ValueNotifier, kDebugMode;
import 'package:flutter/rendering.dart'
    show
        RenderAbstractViewport,
        RenderSliver,
        RenderSliverMultiBoxAdaptor,
        RevealedOffset;
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
  final ValueNotifier<MarkdownReadingPlace> _readingPlaceNotifier =
      ValueNotifier<MarkdownReadingPlace>(MarkdownReadingPlace.start);
  ScrollController? _scrollController;
  Object? _scrollOwner;
  bool _showFrontmatter = true;
  final Map<String, List<BuildContext>> _anchorContexts =
      <String, List<BuildContext>>{};
  final Map<String, List<BuildContext>> _blockContexts =
      <String, List<BuildContext>>{};
  Map<String, int>? _blockIdToIndexCache;
  List<int>? _visibleDocIndicesCache;
  Map<int, int>? _docIndexToVisibleIndexCache;
  bool _isDisposed = false;
  bool _pendingPostFrameNotify = false;
  bool _pendingPostFramePlaceNotify = false;
  bool _pendingPostFrameScrollSync = false;

  /// Most recent [MarkdownDocument] attached to this controller.
  MarkdownDocument get document => _document;

  /// Heading outline entries extracted from [document].
  List<MarkdownOutlineItem> get outline => _document.outline;

  /// Cumulative number of full parses performed by the attached view.
  int get parseCount => _parseCount;

  /// Current tracked reading position inside [document].
  MarkdownReadingPlace get readingPlace => _readingPlace;

  /// Dedicated listenable emitting updates only when [readingPlace] changes,
  /// avoiding document/outline rebuilds during scrolling.
  ValueListenable<MarkdownReadingPlace> get readingPlaceNotifier =>
      _readingPlaceNotifier;

  /// Currently attached [ScrollController], if any.
  ScrollController? get scrollController => _scrollController;

  /// Whether leading [FrontmatterNode] blocks are visible in the attached view.
  bool get showFrontmatter => _showFrontmatter;

  /// Attaches a [ScrollController] to enable programmatic scrolling and reading
  /// progress synchronization.
  ///
  /// Passing a distinct [owner] token prevents an unmounting widget from
  /// detaching a replacement widget's shared [ScrollController] listener.
  void attachScrollController(
    ScrollController controller, {
    Object? owner,
    bool? showFrontmatter,
  }) {
    final Object effectiveOwner = owner ?? controller;
    if (showFrontmatter != null && _showFrontmatter != showFrontmatter) {
      _showFrontmatter = showFrontmatter;
      _visibleDocIndicesCache = null;
      _docIndexToVisibleIndexCache = null;
    }
    if (!identical(_scrollController, controller)) {
      _scrollController?.removeListener(_handleScrollChange);
      _scrollController = controller;
      _scrollController!.addListener(_handleScrollChange);
    }
    _scrollOwner = effectiveOwner;
  }

  /// Detaches a previously attached [ScrollController] when owned by [owner].
  void detachScrollController(ScrollController controller, {Object? owner}) {
    if (!identical(_scrollController, controller)) {
      return;
    }
    final Object effectiveOwner = owner ?? controller;
    if (!identical(_scrollOwner, effectiveOwner)) {
      return;
    }
    _scrollController?.removeListener(_handleScrollChange);
    _scrollController = null;
    _scrollOwner = null;
  }

  /// Records a new [document] snapshot and optionally increments [parseCount].
  void updateDocument(
    MarkdownDocument document, {
    bool incrementParseCount = false,
    bool? showFrontmatter,
  }) {
    if (_isDisposed) {
      return;
    }
    final bool docChanged = !identical(_document, document);
    final bool frontmatterChanged =
        showFrontmatter != null && _showFrontmatter != showFrontmatter;
    _document = document;
    if (showFrontmatter != null) {
      _showFrontmatter = showFrontmatter;
    }
    if (docChanged) {
      _blockIdToIndexCache = null;
      _visibleDocIndicesCache = null;
      _docIndexToVisibleIndexCache = null;
    } else if (frontmatterChanged) {
      _visibleDocIndicesCache = null;
      _docIndexToVisibleIndexCache = null;
    }
    if (incrementParseCount) {
      _parseCount++;
    }
    if (docChanged || incrementParseCount || frontmatterChanged) {
      _notifySafely();
    }
  }

  /// Registers a mounted [BuildContext] for an anchor slug or ID (headings,
  /// `<a id="...">`, or footnote anchors).
  void registerAnchor(String slug, BuildContext context) {
    if (_isDisposed || slug.isEmpty) {
      return;
    }
    final String key = _normalizeAnchor(slug);
    if (key.isEmpty) {
      return;
    }
    _registerContext(_anchorContexts, key, context);
  }

  /// Unregisters a previously registered anchor [BuildContext].
  void unregisterAnchor(String slug, BuildContext context) {
    final String key = _normalizeAnchor(slug);
    if (key.isEmpty) {
      return;
    }
    _unregisterContext(_anchorContexts, key, context);
  }

  /// Registers a mounted [BuildContext] for a top-level block [blockId].
  void registerBlock(String blockId, BuildContext context) {
    if (_isDisposed || blockId.isEmpty) {
      return;
    }
    _registerContext(_blockContexts, blockId, context);
  }

  /// Unregisters a previously registered top-level block [BuildContext].
  void unregisterBlock(String blockId, BuildContext context) {
    _unregisterContext(_blockContexts, blockId, context);
  }

  /// Scrolls to the heading, inline anchor (`<a id="...">`), or footnote
  /// matching [slug].
  ///
  /// Returns `true` only when a matching target was located and reached
  /// cleanly in the viewport.
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
    final BuildContext? mountedAnchor = _activeContext(_anchorContexts, key);
    if (mountedAnchor != null) {
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
        alignment: 0.0,
      );
      return !_isDisposed;
    }

    if (targetBlockIndex == null) {
      return false;
    }
    final MarkdownBlockNode targetBlock = _document.blocks[targetBlockIndex];
    final int? targetVisibleIdx = _visibleIndexForDocIndex(targetBlockIndex);
    if (targetVisibleIdx == null) {
      return false;
    }

    final BuildContext? mountedBlock = _activeContext(
      _blockContexts,
      targetBlock.blockId,
    );
    if (mountedBlock != null) {
      await Scrollable.ensureVisible(
        mountedBlock,
        duration: duration,
        curve: curve,
        alignment: 0.0,
      );
      if (_isDisposed) {
        return false;
      }
      final BuildContext? revealedAnchor = _activeContext(_anchorContexts, key);
      if (revealedAnchor == null) {
        return false;
      }
      await Scrollable.ensureVisible(
        revealedAnchor,
        duration: duration,
        curve: curve,
        alignment: 0.0,
      );
      return !_isDisposed;
    }

    final ScrollController? sc = _scrollController;
    if (sc == null || !sc.hasClients || !sc.position.hasContentDimensions) {
      return false;
    }

    final int visibleCount = _visibleDocIndices().length;
    if (visibleCount == 0) {
      return false;
    }

    double lowOffset = sc.position.minScrollExtent;
    double highOffset = sc.position.maxScrollExtent;
    int lowIdx = 0;
    int highIdx = visibleCount - 1;

    final double initialRatio = visibleCount <= 1
        ? 0.0
        : (targetVisibleIdx / visibleCount).clamp(0.0, 1.0);
    double nextOffset = (lowOffset + (highOffset - lowOffset) * initialRatio)
        .clamp(sc.position.minScrollExtent, sc.position.maxScrollExtent);

    const int maxHops = 12;
    for (int hop = 0; hop < maxHops; hop++) {
      sc.jumpTo(nextOffset);
      await WidgetsBinding.instance.endOfFrame;
      if (_isDisposed || !sc.hasClients || !sc.position.hasContentDimensions) {
        return false;
      }

      final BuildContext? postJumpAnchor = _activeContext(_anchorContexts, key);
      if (postJumpAnchor != null) {
        await Scrollable.ensureVisible(
          postJumpAnchor,
          duration: duration,
          curve: curve,
          alignment: 0.0,
        );
        return !_isDisposed;
      }

      final BuildContext? postJumpBlock = _activeContext(
        _blockContexts,
        targetBlock.blockId,
      );
      if (postJumpBlock != null) {
        await Scrollable.ensureVisible(
          postJumpBlock,
          duration: duration,
          curve: curve,
          alignment: 0.0,
        );
        if (_isDisposed) {
          return false;
        }
        final BuildContext? revealedAnchor = _activeContext(
          _anchorContexts,
          key,
        );
        if (revealedAnchor == null) {
          return false;
        }
        await Scrollable.ensureVisible(
          revealedAnchor,
          duration: duration,
          curve: curve,
          alignment: 0.0,
        );
        return !_isDisposed;
      }

      final List<_MountedBlockMetrics> mounted = _measureMountedBlocks(sc);
      if (mounted.isEmpty) {
        break;
      }

      _MountedBlockMetrics minMounted = mounted.first;
      _MountedBlockMetrics maxMounted = mounted.first;
      for (int i = 1; i < mounted.length; i++) {
        final _MountedBlockMetrics item = mounted[i];
        if (item.visibleIndex < minMounted.visibleIndex) {
          minMounted = item;
        }
        if (item.visibleIndex > maxMounted.visibleIndex) {
          maxMounted = item;
        }
      }

      final double minExt = sc.position.minScrollExtent;
      final double maxExt = sc.position.maxScrollExtent;
      if (highIdx == visibleCount - 1) {
        highOffset = maxExt;
      }

      if (maxMounted.visibleIndex < targetVisibleIdx) {
        if (maxMounted.visibleIndex >= lowIdx) {
          lowIdx = maxMounted.visibleIndex;
          lowOffset = maxMounted.topOffset + maxMounted.height;
        }
        if (highIdx <= lowIdx || highOffset < lowOffset) {
          highIdx = visibleCount - 1;
          highOffset = maxExt;
        }
        final double frac =
            (targetVisibleIdx - lowIdx) / math.max(1, highIdx - lowIdx);
        double candidate =
            lowOffset + frac * math.max(0.0, highOffset - lowOffset);
        final double minStep = math.max(
          sc.position.viewportDimension * 0.5,
          48.0,
        );
        if (candidate <= sc.offset + 1.0 && highIdx < visibleCount - 1) {
          // Recover from stale upper brackets if earlier async widgets resized.
          highIdx = visibleCount - 1;
          highOffset = maxExt;
          final double resetFrac =
              (targetVisibleIdx - lowIdx) / math.max(1, highIdx - lowIdx);
          candidate =
              lowOffset + resetFrac * math.max(0.0, highOffset - lowOffset);
        }
        if (candidate <= sc.offset + 1.0) {
          candidate = math.min(maxExt, sc.offset + minStep);
        }
        nextOffset = candidate.clamp(minExt, maxExt);
      } else if (minMounted.visibleIndex > targetVisibleIdx) {
        if (minMounted.visibleIndex <= highIdx) {
          highIdx = minMounted.visibleIndex;
          highOffset = minMounted.topOffset;
        }
        if (highIdx <= lowIdx || lowOffset > highOffset) {
          lowIdx = 0;
          lowOffset = minExt;
        }
        final double frac =
            (targetVisibleIdx - lowIdx) / math.max(1, highIdx - lowIdx);
        double candidate =
            lowOffset + frac * math.max(0.0, highOffset - lowOffset);
        final double minStep = math.max(
          sc.position.viewportDimension * 0.5,
          48.0,
        );
        if (candidate >= sc.offset - 1.0 && lowIdx > 0) {
          // Recover from stale lower brackets if earlier async widgets resized.
          lowIdx = 0;
          lowOffset = minExt;
          final double resetFrac =
              (targetVisibleIdx - lowIdx) / math.max(1, highIdx - lowIdx);
          candidate =
              lowOffset + resetFrac * math.max(0.0, highOffset - lowOffset);
        }
        if (candidate >= sc.offset - 1.0) {
          candidate = math.max(minExt, sc.offset - minStep);
        }
        nextOffset = candidate.clamp(minExt, maxExt);
      } else {
        break;
      }

      if ((nextOffset - sc.offset).abs() < 0.5) {
        break;
      }
    }

    final BuildContext? finalAnchor = _activeContext(_anchorContexts, key);
    if (finalAnchor == null) {
      return false;
    }
    await Scrollable.ensureVisible(
      finalAnchor,
      duration: duration,
      curve: curve,
      alignment: 0.0,
    );
    return !_isDisposed;
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
      final int? byId = _indexForBlockId(requestedId);
      if (byId != null) {
        resolvedIndex = byId;
      }
    }

    final MarkdownBlockNode targetBlock = blocks[resolvedIndex];
    final MarkdownReadingPlace resolvedPlace = MarkdownReadingPlace(
      blockIndex: resolvedIndex,
      blockId: targetBlock.blockId,
      offsetFraction: place.offsetFraction.clamp(0.0, 1.0),
    );
    _setReadingPlace(resolvedPlace);

    final BuildContext? blockCtx = _activeContext(
      _blockContexts,
      targetBlock.blockId,
    );
    if (blockCtx != null) {
      await Scrollable.ensureVisible(
        blockCtx,
        duration: duration,
        curve: curve,
        alignment: 0.0,
      );
      return !_isDisposed;
    }

    final ScrollController? sc = _scrollController;
    if (sc != null && sc.hasClients && sc.position.hasContentDimensions) {
      final List<int> visibleIndices = _visibleDocIndices();
      final int visibleCount = visibleIndices.length;
      if (visibleCount == 0) {
        return true;
      }
      int resolvedVisibleIdx = _visibleIndexForDocIndex(resolvedIndex) ?? 0;
      if (_visibleIndexForDocIndex(resolvedIndex) == null) {
        for (int v = 0; v < visibleCount; v++) {
          resolvedVisibleIdx = v;
          if (visibleIndices[v] >= resolvedIndex) {
            break;
          }
        }
      }
      final double maxExtent = sc.position.maxScrollExtent;
      final double ratio = visibleCount <= 1
          ? resolvedPlace.offsetFraction
          : ((resolvedVisibleIdx + resolvedPlace.offsetFraction) / visibleCount)
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
    return !_isDisposed;
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

    final List<_MountedBlockMetrics> mounted = _measureMountedBlocks(sc);
    final List<int> visibleIndices = _visibleDocIndices();
    if (visibleIndices.isEmpty) {
      return;
    }
    if (mounted.isNotEmpty) {
      final double offset = sc.offset;
      _MountedBlockMetrics? bestBefore;
      _MountedBlockMetrics? bestAfter;
      double minTop = mounted.first.topOffset;
      double maxBottom = mounted.first.topOffset + mounted.first.height;
      for (final _MountedBlockMetrics item in mounted) {
        if (item.topOffset < minTop) {
          minTop = item.topOffset;
        }
        final double bottom = item.topOffset + item.height;
        if (bottom > maxBottom) {
          maxBottom = bottom;
        }
        if (item.topOffset <= offset + 0.5) {
          if (bestBefore == null ||
              item.topOffset > bestBefore.topOffset ||
              (item.topOffset == bestBefore.topOffset &&
                  item.blockIndex > bestBefore.blockIndex)) {
            bestBefore = item;
          }
        } else {
          if (bestAfter == null ||
              item.topOffset < bestAfter.topOffset ||
              (item.topOffset == bestAfter.topOffset &&
                  item.blockIndex < bestAfter.blockIndex)) {
            bestAfter = item;
          }
        }
      }

      final double viewportDim = sc.position.hasViewportDimension
          ? sc.position.viewportDimension
          : 0.0;
      if (bestBefore != null &&
          offset >= minTop - viewportDim &&
          (offset <= bestBefore.topOffset + bestBefore.height + 0.5 ||
              (bestBefore.visibleIndex == visibleIndices.length - 1 &&
                  offset <= maxBottom + viewportDim))) {
        final double height = bestBefore.height > 1.0 ? bestBefore.height : 1.0;
        final double fraction = ((offset - bestBefore.topOffset) / height)
            .clamp(0.0, 1.0);
        _setReadingPlace(
          MarkdownReadingPlace(
            blockIndex: bestBefore.blockIndex,
            blockId: bestBefore.blockId,
            offsetFraction: fraction,
          ),
        );
        return;
      }

      if (bestBefore == null &&
          bestAfter != null &&
          (bestAfter.visibleIndex == 0 ||
              bestAfter.topOffset - offset <= viewportDim)) {
        _setReadingPlace(
          MarkdownReadingPlace(
            blockIndex: bestAfter.blockIndex,
            blockId: bestAfter.blockId,
            offsetFraction: 0.0,
          ),
        );
        return;
      }

      // Mounted blocks are stale from before a large jump; refine once this
      // frame finishes laying out the target sliver region.
      _schedulePostFrameScrollSync();
    }

    final double maxExtent = sc.position.maxScrollExtent;
    final double progress = maxExtent <= 0.0
        ? 0.0
        : (sc.offset / maxExtent).clamp(0.0, 1.0);
    final double scaled = progress * visibleIndices.length;
    final int visiblePos = scaled.floor().clamp(0, visibleIndices.length - 1);
    final int docIndex = visibleIndices[visiblePos];
    final double fraction = (scaled - visiblePos).clamp(0.0, 1.0);
    _setReadingPlace(
      MarkdownReadingPlace(
        blockIndex: docIndex,
        blockId: blocks[docIndex].blockId,
        offsetFraction: fraction,
      ),
    );
  }

  List<_MountedBlockMetrics> _measureMountedBlocks(ScrollController sc) {
    if (_blockContexts.isEmpty ||
        !sc.hasClients ||
        !sc.position.hasContentDimensions) {
      return const <_MountedBlockMetrics>[];
    }
    final ScrollPosition targetPosition = sc.position;
    final List<_MountedBlockMetrics> measured = <_MountedBlockMetrics>[];
    final List<String> keys = List<String>.of(_blockContexts.keys);

    for (final String blockId in keys) {
      final int? docIndex = _indexForBlockId(blockId);
      if (docIndex == null) {
        continue;
      }
      final int? visibleIndex = _visibleIndexForDocIndex(docIndex);
      if (visibleIndex == null) {
        continue;
      }
      final BuildContext? ctx = _activeContext(_blockContexts, blockId);
      if (ctx == null) {
        continue;
      }
      final RenderObject? ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
        continue;
      }
      final ScrollableState? scrollable = Scrollable.maybeOf(ctx);
      if (scrollable == null ||
          !identical(scrollable.position, targetPosition)) {
        continue;
      }
      final RenderAbstractViewport? viewport = RenderAbstractViewport.maybeOf(
        ro,
      );
      if (viewport == null || !_isActiveInViewport(ro, viewport)) {
        continue;
      }
      final RevealedOffset revealed = viewport.getOffsetToReveal(ro, 0.0);
      if (!revealed.offset.isFinite) {
        continue;
      }
      measured.add(
        _MountedBlockMetrics(
          blockIndex: docIndex,
          visibleIndex: visibleIndex,
          blockId: blockId,
          topOffset: revealed.offset,
          height: ro.size.height,
        ),
      );
    }
    return measured;
  }

  static bool _isActiveInViewport(
    RenderObject target,
    RenderAbstractViewport viewport,
  ) {
    RenderObject child = target;
    while (child.parent != null && !identical(child.parent, viewport)) {
      final RenderObject parent = child.parent!;
      if (parent is RenderSliverMultiBoxAdaptor &&
          child is RenderBox &&
          !parent.paintsChild(child)) {
        return false;
      }
      if (parent is RenderSliver && parent.childScrollOffset(child) == null) {
        return false;
      }
      child = parent;
    }
    return identical(child.parent, viewport);
  }

  void _registerContext(
    Map<String, List<BuildContext>> map,
    String key,
    BuildContext context,
  ) {
    final List<BuildContext> list = map.putIfAbsent(
      key,
      () => <BuildContext>[],
    );
    list.removeWhere((BuildContext c) => !c.mounted);
    if (!list.any((BuildContext c) => identical(c, context))) {
      list.add(context);
    }
  }

  void _unregisterContext(
    Map<String, List<BuildContext>> map,
    String key,
    BuildContext context,
  ) {
    final List<BuildContext>? list = map[key];
    if (list == null) {
      return;
    }
    list.removeWhere((BuildContext c) => identical(c, context) || !c.mounted);
    if (list.isEmpty) {
      map.remove(key);
    }
  }

  BuildContext? _activeContext(
    Map<String, List<BuildContext>> map,
    String key,
  ) {
    final List<BuildContext>? list = map[key];
    if (list == null || list.isEmpty) {
      return null;
    }
    for (int i = list.length - 1; i >= 0; i--) {
      final BuildContext candidate = list[i];
      if (candidate.mounted) {
        return candidate;
      }
      list.removeAt(i);
    }
    if (list.isEmpty) {
      map.remove(key);
    }
    return null;
  }

  int? _indexForBlockId(String blockId) {
    Map<String, int>? cache = _blockIdToIndexCache;
    if (cache == null) {
      final List<MarkdownBlockNode> blocks = _document.blocks;
      cache = <String, int>{
        for (int i = 0; i < blocks.length; i++) blocks[i].blockId: i,
      };
      _blockIdToIndexCache = cache;
    }
    return cache[blockId];
  }

  List<int> _visibleDocIndices() {
    final List<int>? cached = _visibleDocIndicesCache;
    if (cached != null) {
      return cached;
    }
    final List<MarkdownBlockNode> blocks = _document.blocks;
    final List<int> indices = <int>[];
    final Map<int, int> reverse = <int, int>{};
    for (int i = 0; i < blocks.length; i++) {
      if (!_showFrontmatter && blocks[i] is FrontmatterNode) {
        continue;
      }
      reverse[i] = indices.length;
      indices.add(i);
    }
    _visibleDocIndicesCache = indices;
    _docIndexToVisibleIndexCache = reverse;
    return indices;
  }

  int? _visibleIndexForDocIndex(int docIndex) {
    if (_docIndexToVisibleIndexCache == null) {
      _visibleDocIndices();
    }
    return _docIndexToVisibleIndexCache![docIndex];
  }

  SchedulerBinding? _safeSchedulerBinding() {
    SchedulerBinding? binding;
    assert(() {
      if (BindingBase.debugBindingType() != null) {
        binding = SchedulerBinding.instance;
      }
      return true;
    }());
    if (!kDebugMode) {
      try {
        binding = SchedulerBinding.instance;
      } on Object {
        binding = null;
      }
    }
    return binding;
  }

  void _setReadingPlace(MarkdownReadingPlace next) {
    if (_readingPlace == next) {
      return;
    }
    _readingPlace = next;
    final SchedulerBinding? binding = _safeSchedulerBinding();
    if (binding != null) {
      final SchedulerPhase phase = binding.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks ||
          phase == SchedulerPhase.midFrameMicrotasks) {
        if (_pendingPostFramePlaceNotify) {
          return;
        }
        _pendingPostFramePlaceNotify = true;
        binding.addPostFrameCallback((Duration _) {
          _pendingPostFramePlaceNotify = false;
          if (!_isDisposed) {
            _readingPlaceNotifier.value = _readingPlace;
          }
        });
        return;
      }
    }
    _readingPlaceNotifier.value = next;
  }

  void _schedulePostFrameScrollSync() {
    if (_isDisposed || _pendingPostFrameScrollSync) {
      return;
    }
    final SchedulerBinding? binding = _safeSchedulerBinding();
    if (binding == null) {
      return;
    }
    _pendingPostFrameScrollSync = true;
    binding.addPostFrameCallback((Duration _) {
      _pendingPostFrameScrollSync = false;
      _handleScrollChange();
    });
  }

  void _notifySafely() {
    if (_isDisposed || !hasListeners) {
      return;
    }
    final SchedulerBinding? binding = _safeSchedulerBinding();
    if (binding != null) {
      final SchedulerPhase phase = binding.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks ||
          phase == SchedulerPhase.midFrameMicrotasks) {
        if (_pendingPostFrameNotify) {
          return;
        }
        _pendingPostFrameNotify = true;
        binding.addPostFrameCallback((Duration _) {
          _pendingPostFrameNotify = false;
          if (!_isDisposed && hasListeners) {
            notifyListeners();
          }
        });
        return;
      }
    }
    notifyListeners();
  }

  int? _findBlockIndexForAnchor(String normalizedSlug) {
    final List<MarkdownBlockNode> blocks = _document.blocks;
    for (int i = 0; i < blocks.length; i++) {
      if (!_showFrontmatter && blocks[i] is FrontmatterNode) {
        continue;
      }
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
      case TableNode():
        for (final TableCellNode cell in block.headers) {
          if (_inlinesMatchAnchor(cell.children, normalizedSlug)) {
            return true;
          }
        }
        for (final List<TableCellNode> row in block.rows) {
          for (final TableCellNode cell in row) {
            if (_inlinesMatchAnchor(cell.children, normalizedSlug)) {
              return true;
            }
          }
        }
        return false;
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
    _scrollOwner = null;
    _anchorContexts.clear();
    _blockContexts.clear();
    _blockIdToIndexCache = null;
    _visibleDocIndicesCache = null;
    _docIndexToVisibleIndexCache = null;
    _readingPlaceNotifier.dispose();
    super.dispose();
  }
}

final class _MountedBlockMetrics {
  const _MountedBlockMetrics({
    required this.blockIndex,
    required this.visibleIndex,
    required this.blockId,
    required this.topOffset,
    required this.height,
  });

  final int blockIndex;
  final int visibleIndex;
  final String blockId;
  final double topOffset;
  final double height;
}
