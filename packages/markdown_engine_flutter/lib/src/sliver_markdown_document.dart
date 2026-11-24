import 'dart:math' as math;
import 'dart:typed_data' show Float64List;

import 'package:flutter/foundation.dart'
    show ValueListenable, precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'block_renderer.dart';
import 'controller.dart';
import 'delegates.dart';
import 'fast_text.dart';
import 'theme.dart';

/// Package-internal scope supplying lazy streaming normalized-source,
/// active-stream checks, and per-block listenables to [SliverMarkdownDocument]
/// without triggering full sliver rebuilds on mid-block token appends.
final class MarkdownStreamingHostScope extends InheritedWidget {
  /// Creates a [MarkdownStreamingHostScope].
  const MarkdownStreamingHostScope({
    super.key,
    required this.normalizedSourceProvider,
    required this.isStreamActiveProvider,
    this.slotListenableFor,
    required super.child,
  });

  /// Returns active normalized streaming source when streaming is unfinished.
  final String? Function() normalizedSourceProvider;

  /// Returns whether the stream is currently active (unfinished).
  final bool Function() isStreamActiveProvider;

  /// Optional provider returning a per-block listenable keyed by `blockId`.
  final ValueListenable<MarkdownBlockNode> Function(MarkdownBlockNode block)?
  slotListenableFor;

  /// Retrieves the closest [MarkdownStreamingHostScope] without registering
  /// an inherited dependency (callbacks are stable across the view's lifetime).
  static MarkdownStreamingHostScope? readOnly(BuildContext context) {
    return context.getInheritedWidgetOfExactType<MarkdownStreamingHostScope>();
  }

  @override
  bool updateShouldNotify(MarkdownStreamingHostScope oldWidget) =>
      normalizedSourceProvider != oldWidget.normalizedSourceProvider ||
      isStreamActiveProvider != oldWidget.isStreamActiveProvider ||
      slotListenableFor != oldWidget.slotListenableFor;
}

/// Virtualized sliver rendering top-level blocks of a [MarkdownDocument] on
/// demand via [SliverChildBuilderDelegate], keyed by
/// [MarkdownBlockNode.blockId] for state preservation across incremental edits.
final class SliverMarkdownDocument extends StatefulWidget {
  /// Creates a [SliverMarkdownDocument].
  const SliverMarkdownDocument({
    super.key,
    required this.document,
    this.theme,
    this.delegates = const MarkdownBuilderDelegates(),
    this.controller,
    this.showFrontmatter = true,
    this.padding,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.remoteImagesApproved = false,
    this.onRequestLoadRemoteImages,
    this.startBlockIndex = 0,
    this.endBlockIndex,
    this.trailingBlockSpacing = false,
    this.streamingNormalizedSource,
  });

  /// Parsed immutable [MarkdownDocument] whose blocks are lazily materialized.
  final MarkdownDocument document;

  /// Optional theme overriding the ambient [MarkdownTheme].
  final MarkdownThemeData? theme;

  /// Pluggable builders and security callbacks for links, math, diagrams, code,
  /// and images.
  final MarkdownBuilderDelegates delegates;

  /// Optional [MarkdownController] receiving anchor and block registrations.
  final MarkdownController? controller;

  /// Whether leading [FrontmatterNode] metadata cards are shown.
  final bool showFrontmatter;

  /// Optional outer padding wrapped around the sliver via [SliverPadding].
  final EdgeInsetsGeometry? padding;

  /// Whether off-screen block widgets are kept alive automatically.
  ///
  /// Defaults to `true` so `_SelectionKeepAlive` preserves active off-screen
  /// drag selections cleanly across sliver scrolling.
  final bool addAutomaticKeepAlives;

  /// Whether each top-level block is wrapped in a [RepaintBoundary].
  final bool addRepaintBoundaries;

  /// Whether remote images have been approved locally in
  /// [MarkdownImagePolicy.ask] mode.
  final bool remoteImagesApproved;

  /// Optional callback invoked when the user requests loading remote images.
  final VoidCallback? onRequestLoadRemoteImages;

  /// Inclusive starting index inside `document.blocks` for sliced rendering.
  final int startBlockIndex;

  /// Optional exclusive ending index inside `document.blocks` for sliced
  /// rendering (`null` renders through the end of `document.blocks`).
  final int? endBlockIndex;

  /// Whether the final block in this sliver appends `theme.blockSpacing` below
  /// it (for example when followed by an active streaming tail sliver).
  final bool trailingBlockSpacing;

  /// Normalized source text for unfinished active-tail streaming blocks, or
  /// `null` for settled or complete documents.
  final String? streamingNormalizedSource;

  /// Returns the visible top-level blocks for [document] honoring
  /// [showFrontmatter] and optional `[startBlockIndex, endBlockIndex)` slice
  /// bounds.
  static List<MarkdownBlockNode> visibleBlocksFor(
    MarkdownDocument document, {
    required bool showFrontmatter,
    int startBlockIndex = 0,
    int? endBlockIndex,
  }) {
    final List<MarkdownBlockNode> allBlocks = document.blocks;
    final int clampedStart = startBlockIndex.clamp(0, allBlocks.length);
    final int clampedEnd = (endBlockIndex ?? allBlocks.length).clamp(
      clampedStart,
      allBlocks.length,
    );
    final List<MarkdownBlockNode> slice =
        (clampedStart == 0 && clampedEnd == allBlocks.length)
        ? allBlocks
        : allBlocks.sublist(clampedStart, clampedEnd);

    if (showFrontmatter || slice.isEmpty) {
      return slice;
    }
    if (document.frontmatter == null && slice.first is! FrontmatterNode) {
      return slice;
    }
    if (slice.first is! FrontmatterNode &&
        !slice.any((MarkdownBlockNode b) => b is FrontmatterNode)) {
      return slice;
    }
    return slice
        .where((MarkdownBlockNode b) => b is! FrontmatterNode)
        .toList(growable: false);
  }

  @override
  State<SliverMarkdownDocument> createState() => _SliverMarkdownDocumentState();
}

final class _SliverMarkdownDocumentState extends State<SliverMarkdownDocument> {
  late List<MarkdownBlockNode> _visibleBlocks;
  Map<String, int>? _idToIndex;
  MarkdownThemeData? _ambientTheme;
  MarkdownRenderEnvironment? _ambientEnvironment;

  Widget? _cachedSliver;
  MarkdownBlockRenderContext? _cachedRenderContext;
  EdgeInsetsGeometry? _cachedPadding;
  bool? _cachedTrailingBlockSpacing;
  bool? _cachedKeepAlives;
  bool? _cachedRepaintBoundaries;
  bool? _cachedIsStreamActive;

  MarkdownBlockRenderContext? _blockCacheContext;
  final List<MarkdownBlockNode?> _cachedBlockNodes = <MarkdownBlockNode?>[];
  final List<Widget?> _cachedInnerWidgets = <Widget?>[];
  final List<Widget?> _cachedTopWidgets = <Widget?>[];
  final List<bool> _cachedHasBottomSpacing = <bool>[];
  final _MarkdownSliverExtentCache _extentCache = _MarkdownSliverExtentCache();

  @override
  void initState() {
    super.initState();
    _rebuildIndexCache();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambientTheme = widget.theme == null ? MarkdownTheme.of(context) : null;
    _ambientEnvironment = MarkdownRenderEnvironment.resolve(context);
    _cachedSliver = null;
  }

  @override
  void didUpdateWidget(SliverMarkdownDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document) ||
        oldWidget.showFrontmatter != widget.showFrontmatter ||
        oldWidget.startBlockIndex != widget.startBlockIndex ||
        oldWidget.endBlockIndex != widget.endBlockIndex) {
      final List<MarkdownBlockNode> nextBlocks =
          SliverMarkdownDocument.visibleBlocksFor(
            widget.document,
            showFrontmatter: widget.showFrontmatter,
            startBlockIndex: widget.startBlockIndex,
            endBlockIndex: widget.endBlockIndex,
          );
      if (!_blockListsIdentical(_visibleBlocks, nextBlocks)) {
        _visibleBlocks = nextBlocks;
        _idToIndex = null;
        _cachedSliver = null;
        _extentCache.resetForBlocks(_visibleBlocks.length);
        if (_cachedBlockNodes.length > _visibleBlocks.length) {
          _cachedBlockNodes.length = _visibleBlocks.length;
          _cachedInnerWidgets.length = _visibleBlocks.length;
          _cachedTopWidgets.length = _visibleBlocks.length;
          _cachedHasBottomSpacing.length = _visibleBlocks.length;
        }
      }
    }
    if (oldWidget.trailingBlockSpacing != widget.trailingBlockSpacing) {
      _extentCache.invalidateIndex(_visibleBlocks.length - 1);
      _cachedSliver = null;
    }
  }

  @override
  void dispose() {
    _cachedSliver = null;
    _clearPerBlockCache();
    _extentCache.release();
    super.dispose();
  }

  void _clearPerBlockCache() {
    _cachedBlockNodes.clear();
    _cachedInnerWidgets.clear();
    _cachedTopWidgets.clear();
    _cachedHasBottomSpacing.clear();
  }

  void _rebuildIndexCache() {
    _visibleBlocks = SliverMarkdownDocument.visibleBlocksFor(
      widget.document,
      showFrontmatter: widget.showFrontmatter,
      startBlockIndex: widget.startBlockIndex,
      endBlockIndex: widget.endBlockIndex,
    );
    _idToIndex = null;
    _cachedSliver = null;
    _clearPerBlockCache();
    _extentCache.resetForBlocks(_visibleBlocks.length);
  }

  static bool _blockListsIdentical(
    List<MarkdownBlockNode> a,
    List<MarkdownBlockNode> b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final List<MarkdownBlockNode> blocks = _visibleBlocks;
    if (blocks.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final MarkdownThemeData resolvedTheme =
        widget.theme ?? (_ambientTheme ??= MarkdownTheme.of(context));
    final MarkdownRenderEnvironment env = _ambientEnvironment ??=
        MarkdownRenderEnvironment.resolve(context);
    final MarkdownUrlPolicy resolvedPolicy = widget.delegates.resolveUrlPolicy(
      widget.document.options.urlPolicy,
    );
    final MarkdownStreamingHostScope? streamScope =
        MarkdownStreamingHostScope.readOnly(context);
    final MarkdownBlockRenderContext renderContext = MarkdownBlockRenderContext(
      theme: resolvedTheme,
      delegates: widget.delegates,
      urlPolicy: resolvedPolicy,
      controller: widget.controller,
      remoteImagesApproved: widget.remoteImagesApproved,
      onRequestLoadRemoteImages: widget.onRequestLoadRemoteImages,
      streamingNormalizedSource: widget.streamingNormalizedSource,
      streamingNormalizedSourceProvider: streamScope?.normalizedSourceProvider,
      environment: env,
      resolvedBodyStyle: env.resolveTextStyle(resolvedTheme.bodyTextStyle()),
    );

    final bool isStreamActive =
        streamScope?.isStreamActiveProvider() ??
        (widget.streamingNormalizedSource != null);

    final Widget? cached = _cachedSliver;
    if (cached != null &&
        _cachedRenderContext == renderContext &&
        _cachedPadding == widget.padding &&
        _cachedTrailingBlockSpacing == widget.trailingBlockSpacing &&
        _cachedKeepAlives == widget.addAutomaticKeepAlives &&
        _cachedRepaintBoundaries == widget.addRepaintBoundaries &&
        _cachedIsStreamActive == isStreamActive) {
      return cached;
    }

    final bool trailingSpacing = widget.trailingBlockSpacing;
    if (_blockCacheContext != renderContext) {
      _clearPerBlockCache();
      _blockCacheContext = renderContext;
      _extentCache.resetForBlocks(blocks.length);
    }

    final ValueListenable<MarkdownBlockNode> Function(MarkdownBlockNode block)?
    slotListenableFor = streamScope?.slotListenableFor;
    final double blockSpacing = resolvedTheme.blockSpacing;

    final Widget listSliver = _MarkdownSliverList(
      extentCache: _extentCache,
      cacheGeneration: _extentCache.generation,
      delegate: SliverChildBuilderDelegate(
        (BuildContext itemContext, int index) {
          final MarkdownBlockNode block = blocks[index];
          final bool hasBottomSpacing =
              !(index == blocks.length - 1 && !trailingSpacing);
          final bool isMermaidBlock =
              block is CodeBlockNode &&
              block.language?.toLowerCase() == 'mermaid';
          if (slotListenableFor != null) {
            final Widget? existingTop = index < _cachedTopWidgets.length
                ? _cachedTopWidgets[index]
                : null;
            final bool mermaidStateChanged =
                isMermaidBlock &&
                existingTop is _StreamingBlockSlot &&
                existingTop.isStreamActive != isStreamActive;
            if (!mermaidStateChanged &&
                index < _cachedBlockNodes.length &&
                _cachedBlockNodes[index]?.blockId == block.blockId &&
                existingTop != null &&
                _cachedHasBottomSpacing[index] == hasBottomSpacing) {
              if (!identical(_cachedBlockNodes[index], block)) {
                slotListenableFor(block);
                _cachedBlockNodes[index] = block;
              }
              return existingTop;
            }
            final Widget slotWidget = _StreamingBlockSlot(
              key: ValueKey<String>(block.blockId),
              blockListenable: slotListenableFor(block),
              renderContext: renderContext,
              bottomSpacing: hasBottomSpacing ? blockSpacing : 0.0,
              isStreamActive: isStreamActive,
            );
            while (_cachedBlockNodes.length <= index) {
              _cachedBlockNodes.add(null);
              _cachedInnerWidgets.add(null);
              _cachedTopWidgets.add(null);
              _cachedHasBottomSpacing.add(false);
            }
            _cachedBlockNodes[index] = block;
            _cachedTopWidgets[index] = slotWidget;
            _cachedHasBottomSpacing[index] = hasBottomSpacing;
            return slotWidget;
          }

          final bool isStreamingMermaid = isStreamActive && isMermaidBlock;

          if (!isStreamingMermaid &&
              index < _cachedBlockNodes.length &&
              identical(_cachedBlockNodes[index], block)) {
            final Widget? cachedTop = _cachedTopWidgets[index];
            if (cachedTop != null &&
                _cachedHasBottomSpacing[index] == hasBottomSpacing) {
              return cachedTop;
            }
            final Widget? cachedInner = _cachedInnerWidgets[index];
            if (cachedInner != null) {
              final Widget rebuiltTop = buildTopLevelMarkdownBlockWidget(
                itemContext,
                key: ValueKey<String>(block.blockId),
                node: block,
                renderContext: renderContext,
                bottomSpacing: hasBottomSpacing ? blockSpacing : 0.0,
                prebuiltInner: cachedInner,
              );
              _cachedTopWidgets[index] = rebuiltTop;
              _cachedHasBottomSpacing[index] = hasBottomSpacing;
              return rebuiltTop;
            }
          }

          final Widget inner = buildMarkdownBlockWidget(
            itemContext,
            block,
            renderContext,
            isTopLevel: true,
          );
          final Widget top = buildTopLevelMarkdownBlockWidget(
            itemContext,
            key: ValueKey<String>(block.blockId),
            node: block,
            renderContext: renderContext,
            bottomSpacing: hasBottomSpacing ? blockSpacing : 0.0,
            prebuiltInner: inner,
          );

          while (_cachedBlockNodes.length <= index) {
            _cachedBlockNodes.add(null);
            _cachedInnerWidgets.add(null);
            _cachedTopWidgets.add(null);
            _cachedHasBottomSpacing.add(false);
          }
          if (isStreamingMermaid) {
            _cachedBlockNodes[index] = null;
            _cachedInnerWidgets[index] = null;
            _cachedTopWidgets[index] = null;
          } else {
            _cachedBlockNodes[index] = block;
            _cachedInnerWidgets[index] = inner;
            _cachedTopWidgets[index] = top;
            _cachedHasBottomSpacing[index] = hasBottomSpacing;
          }
          return top;
        },
        childCount: blocks.length,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        findChildIndexCallback: (Key key) {
          if (key is ValueKey<String>) {
            final Map<String, int> map = _idToIndex ??= <String, int>{
              for (int i = 0; i < blocks.length; i++) blocks[i].blockId: i,
            };
            return map[key.value];
          }
          return null;
        },
      ),
    );

    final EdgeInsetsGeometry? pad = widget.padding;
    final Widget built = pad != null
        ? SliverPadding(padding: pad, sliver: listSliver)
        : listSliver;

    _cachedSliver = built;
    _cachedRenderContext = renderContext;
    _cachedPadding = pad;
    _cachedTrailingBlockSpacing = trailingSpacing;
    _cachedKeepAlives = widget.addAutomaticKeepAlives;
    _cachedRepaintBoundaries = widget.addRepaintBoundaries;
    _cachedIsStreamActive = isStreamActive;
    return built;
  }
}

final class _StreamingBlockSlot extends StatefulWidget {
  const _StreamingBlockSlot({
    super.key,
    required this.blockListenable,
    required this.renderContext,
    required this.bottomSpacing,
    required this.isStreamActive,
  });

  final ValueListenable<MarkdownBlockNode> blockListenable;
  final MarkdownBlockRenderContext renderContext;
  final double bottomSpacing;
  final bool isStreamActive;

  @override
  State<_StreamingBlockSlot> createState() => _StreamingBlockSlotState();
}

final class _StreamingBlockSlotState extends State<_StreamingBlockSlot> {
  MarkdownBlockNode? _cachedNode;
  MarkdownBlockRenderContext? _cachedRenderContext;
  Widget? _cachedInner;

  @override
  void initState() {
    super.initState();
    widget.blockListenable.addListener(_onBlockChanged);
  }

  @override
  void didUpdateWidget(_StreamingBlockSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.blockListenable, widget.blockListenable)) {
      oldWidget.blockListenable.removeListener(_onBlockChanged);
      widget.blockListenable.addListener(_onBlockChanged);
      _cachedNode = null;
      _cachedInner = null;
    }
    if (oldWidget.isStreamActive != widget.isStreamActive &&
        _cachedNode is CodeBlockNode &&
        (_cachedNode! as CodeBlockNode).language?.toLowerCase() == 'mermaid') {
      _cachedNode = null;
      _cachedInner = null;
    }
  }

  @override
  void dispose() {
    widget.blockListenable.removeListener(_onBlockChanged);
    super.dispose();
  }

  void _onBlockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final MarkdownBlockNode node = widget.blockListenable.value;
    final bool isStreamingMermaid =
        widget.isStreamActive &&
        node is CodeBlockNode &&
        node.language?.toLowerCase() == 'mermaid';

    final Widget inner;
    if (!isStreamingMermaid &&
        _cachedInner != null &&
        identical(_cachedNode, node) &&
        _cachedRenderContext == widget.renderContext) {
      inner = _cachedInner!;
    } else {
      inner = buildMarkdownBlockWidget(
        context,
        node,
        widget.renderContext,
        isTopLevel: true,
      );
      if (isStreamingMermaid) {
        _cachedNode = null;
        _cachedInner = null;
      } else {
        _cachedNode = node;
        _cachedRenderContext = widget.renderContext;
        _cachedInner = inner;
      }
    }

    return buildTopLevelMarkdownBlockWidget(
      context,
      node: node,
      renderContext: widget.renderContext,
      bottomSpacing: widget.bottomSpacing,
      prebuiltInner: inner,
    );
  }
}

/// Reusable `Float64List`-backed measured-extent cache shared between
/// [_SliverMarkdownDocumentState], [_MarkdownSliverList], and
/// [_RenderMarkdownSliverList].
final class _MarkdownSliverExtentCache {
  Float64List _extents = Float64List(0);
  int _blockCount = 0;
  int _measuredCount = 0;
  double _measuredSum = 0.0;
  int _highestMeasuredIndex = -1;
  double? _lastCrossAxisExtent;
  int _generation = 0;

  int get generation => _generation;

  void resetForBlocks(int count) {
    if (count <= 0) {
      _blockCount = 0;
      _measuredCount = 0;
      _measuredSum = 0.0;
      _highestMeasuredIndex = -1;
      _generation += 1;
      return;
    }
    if (_extents.length < count) {
      _extents = Float64List(count);
    }
    _extents.fillRange(0, count, -1.0);
    _blockCount = count;
    _measuredCount = 0;
    _measuredSum = 0.0;
    _highestMeasuredIndex = -1;
    _generation += 1;
  }

  void release() {
    _extents = Float64List(0);
    _blockCount = 0;
    _measuredCount = 0;
    _measuredSum = 0.0;
    _highestMeasuredIndex = -1;
    _lastCrossAxisExtent = null;
    _generation += 1;
  }

  void invalidateIndex(int index) {
    if (index < 0 || index >= _blockCount) {
      return;
    }
    final double previous = _extents[index];
    if (previous >= 0.0) {
      _measuredCount -= 1;
      _measuredSum = _measuredCount <= 0
          ? 0.0
          : math.max(0.0, _measuredSum - previous);
      _extents[index] = -1.0;
    }
    _generation += 1;
  }

  void syncCrossAxisExtent(double crossAxisExtent) {
    final double normalized = crossAxisExtent.isFinite ? crossAxisExtent : -1.0;
    if (_lastCrossAxisExtent == normalized) {
      return;
    }
    _lastCrossAxisExtent = normalized;
    if (_measuredCount > 0) {
      _extents.fillRange(0, _blockCount, -1.0);
      _measuredCount = 0;
      _measuredSum = 0.0;
      _highestMeasuredIndex = -1;
    }
  }

  void recordExtent(int index, double extent) {
    if (index < 0 || index >= _blockCount || !extent.isFinite || extent < 0.0) {
      return;
    }
    final double previous = _extents[index];
    if (previous == extent) {
      return;
    }
    if (previous >= 0.0) {
      _measuredSum = math.max(0.0, _measuredSum + (extent - previous));
    } else {
      _measuredCount += 1;
      _measuredSum += extent;
    }
    _extents[index] = extent;
    if (index > _highestMeasuredIndex) {
      _highestMeasuredIndex = index;
    }
  }

  double? estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
    int? childCount,
  ) {
    if (childCount == null || childCount <= 0) {
      return null;
    }
    if (constraints != null) {
      syncCrossAxisExtent(constraints.crossAxisExtent);
    }
    final double minBound = leadingScrollOffset < 0.0
        ? trailingScrollOffset - leadingScrollOffset
        : trailingScrollOffset;
    if (lastIndex >= childCount - 1) {
      return minBound;
    }
    final double rawFallbackAvg =
        lastIndex >= firstIndex && trailingScrollOffset > leadingScrollOffset
        ? (trailingScrollOffset - leadingScrollOffset) /
              (lastIndex - firstIndex + 1)
        : 0.0;
    final double fallbackAvg = rawFallbackAvg.isFinite && rawFallbackAvg > 0.0
        ? rawFallbackAvg
        : 0.0;
    final double avg = _measuredCount > 0
        ? (_measuredSum <= 0.0 ? 0.0 : _measuredSum / _measuredCount)
        : fallbackAvg;

    double estimated = trailingScrollOffset;
    final int tailStart = lastIndex + 1;
    final int limit = math.min(childCount, _blockCount);
    final int measuredEnd = math.min(limit, _highestMeasuredIndex + 1);
    int unmeasuredCount = childCount - tailStart;
    for (int i = tailStart; i < measuredEnd; i++) {
      final double ext = _extents[i];
      if (ext >= 0.0) {
        estimated += ext;
        unmeasuredCount -= 1;
      }
    }
    if (unmeasuredCount > 0) {
      estimated += unmeasuredCount * avg;
    }
    return estimated < minBound ? minBound : estimated;
  }
}

final class _MarkdownSliverList extends SliverList {
  const _MarkdownSliverList({
    required super.delegate,
    required this.extentCache,
    required this.cacheGeneration,
  });

  final _MarkdownSliverExtentCache extentCache;
  final int cacheGeneration;

  @override
  _RenderMarkdownSliverList createRenderObject(BuildContext context) {
    return _RenderMarkdownSliverList(
      extentCache,
      cacheGeneration,
      childManager: context as SliverMultiBoxAdaptorElement,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMarkdownSliverList renderObject,
  ) {
    renderObject.updateExtentCache(extentCache, cacheGeneration);
  }

  @override
  double? estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    return extentCache.estimateMaxScrollOffset(
      constraints,
      firstIndex,
      lastIndex,
      leadingScrollOffset,
      trailingScrollOffset,
      delegate.estimatedChildCount,
    );
  }
}

/// [RenderSliverList] subclass that batches leading-child scroll-offset
/// corrections when `scrollOffset < precisionErrorTolerance` (for example under
/// fast upward ballistic flings) so [RenderViewport] never exceeds
/// `maxLayoutCycles`, and records measured child extents into
/// [_MarkdownSliverExtentCache].
final class _RenderMarkdownSliverList extends RenderSliverList {
  _RenderMarkdownSliverList(
    this._extentCache,
    this._cacheGeneration, {
    required super.childManager,
  });

  _MarkdownSliverExtentCache _extentCache;
  int _cacheGeneration;
  int _consecutiveCorrectionCycles = 0;

  void updateExtentCache(
    _MarkdownSliverExtentCache extentCache,
    int cacheGeneration,
  ) {
    final bool changed =
        !identical(_extentCache, extentCache) ||
        _cacheGeneration != cacheGeneration;
    _extentCache = extentCache;
    _cacheGeneration = cacheGeneration;
    if (changed) {
      markNeedsLayout();
    }
  }

  @override
  void detach() {
    _consecutiveCorrectionCycles = 0;
    super.detach();
  }

  double _computeBatchTarget(SliverConstraints constraints) {
    if (_consecutiveCorrectionCycles >= 3) {
      return double.infinity;
    }
    final double vp = constraints.viewportMainAxisExtent;
    final double remPaint = constraints.remainingPaintExtent;
    final double remCache = constraints.remainingCacheExtent;
    final double overscroll = constraints.overlap < 0.0
        ? -constraints.overlap
        : 0.0;
    final bool finiteMetrics =
        vp.isFinite && remPaint.isFinite && remCache.isFinite;
    final double needed;
    if (finiteMetrics) {
      final double unconsumedAbove = math.max(0.0, vp - remPaint);
      final double distanceToTop = math.max(overscroll, unconsumedAbove);
      final double rawTrailingCache =
          (remCache - remPaint) + constraints.cacheOrigin;
      final double trailingCache = (remCache == 0.0 && overscroll > 0.0)
          ? 250.0
          : math.max(0.0, rawTrailingCache);
      final double remainingCacheMargin = math.max(
        0.0,
        trailingCache - constraints.scrollOffset,
      );
      needed = distanceToTop + remainingCacheMargin + 1.0;
    } else {
      needed = overscroll + 250.0;
    }
    final double scale = (1 << _consecutiveCorrectionCycles).toDouble();
    final double floor = _consecutiveCorrectionCycles == 0
        ? 0.0
        : (vp.isFinite ? vp * scale : 250.0 * scale);
    return math.max(needed * scale, floor);
  }

  void _recordMeasuredExtents() {
    RenderBox? child = firstChild;
    while (child != null) {
      if (child.hasSize) {
        _extentCache.recordExtent(indexOf(child), paintExtentOf(child));
      }
      child = childAfter(child);
    }
  }

  @override
  void performLayout() {
    final SliverConstraints constraints = this.constraints;
    _extentCache.syncCrossAxisExtent(constraints.crossAxisExtent);
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    final double scrollOffset =
        constraints.scrollOffset + constraints.cacheOrigin;
    assert(scrollOffset >= 0.0);
    final double remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);
    final double targetEndScrollOffset = scrollOffset + remainingExtent;
    final BoxConstraints childConstraints = constraints.asBoxConstraints();
    int leadingGarbage = 0;
    int trailingGarbage = 0;
    bool reachedEnd = false;

    if (firstChild == null) {
      if (!addInitialChild()) {
        _consecutiveCorrectionCycles = 0;
        geometry = SliverGeometry.zero;
        childManager.didFinishLayout();
        return;
      }
    }

    RenderBox? leadingChildWithLayout;
    RenderBox? trailingChildWithLayout;

    RenderBox? earliestUsefulChild = firstChild;

    if (childScrollOffset(firstChild!) == null) {
      int leadingChildrenWithoutLayoutOffset = 0;
      while (earliestUsefulChild != null &&
          childScrollOffset(earliestUsefulChild) == null) {
        earliestUsefulChild = childAfter(earliestUsefulChild);
        leadingChildrenWithoutLayoutOffset += 1;
      }
      collectGarbage(leadingChildrenWithoutLayoutOffset, 0);
      if (firstChild == null) {
        if (!addInitialChild()) {
          _consecutiveCorrectionCycles = 0;
          geometry = SliverGeometry.zero;
          childManager.didFinishLayout();
          return;
        }
      }
    }

    // Loop 1: Find the last child that is at or before scrollOffset.
    double pendingCorrectionFromLoop1 = 0.0;
    earliestUsefulChild = firstChild;
    for (
      double earliestScrollOffset = childScrollOffset(earliestUsefulChild!)!;
      earliestScrollOffset > scrollOffset;
      earliestScrollOffset = childScrollOffset(earliestUsefulChild)!
    ) {
      earliestUsefulChild = insertAndLayoutLeadingChild(
        childConstraints,
        parentUsesSize: true,
      );
      if (earliestUsefulChild == null) {
        final SliverMultiBoxAdaptorParentData childParentData =
            firstChild!.parentData! as SliverMultiBoxAdaptorParentData;
        childParentData.layoutOffset = 0.0;

        if (scrollOffset == 0.0) {
          firstChild!.layout(childConstraints, parentUsesSize: true);
          earliestUsefulChild = firstChild;
          leadingChildWithLayout = earliestUsefulChild;
          trailingChildWithLayout ??= earliestUsefulChild;
          break;
        } else {
          _consecutiveCorrectionCycles += 1;
          geometry = SliverGeometry(scrollOffsetCorrection: -scrollOffset);
          return;
        }
      }

      final double firstChildScrollOffset =
          earliestScrollOffset - paintExtentOf(firstChild!);
      if (firstChildScrollOffset < -precisionErrorTolerance) {
        final SliverMultiBoxAdaptorParentData childParentData =
            firstChild!.parentData! as SliverMultiBoxAdaptorParentData;
        childParentData.layoutOffset = 0.0;
        final double correction = -firstChildScrollOffset;
        if (scrollOffset >= precisionErrorTolerance) {
          _consecutiveCorrectionCycles += 1;
          geometry = SliverGeometry(scrollOffsetCorrection: correction);
          return;
        }
        // When scrollOffset < precisionErrorTolerance, continue into Loop 2 to
        // batch leading prepends in the same layout pass.
        pendingCorrectionFromLoop1 = correction;
        leadingChildWithLayout = earliestUsefulChild;
        trailingChildWithLayout ??= earliestUsefulChild;
        break;
      }

      final SliverMultiBoxAdaptorParentData childParentData =
          earliestUsefulChild.parentData! as SliverMultiBoxAdaptorParentData;
      childParentData.layoutOffset = firstChildScrollOffset < 0.0
          ? 0.0
          : firstChildScrollOffset;
      assert(earliestUsefulChild == firstChild);
      leadingChildWithLayout = earliestUsefulChild;
      trailingChildWithLayout ??= earliestUsefulChild;
    }

    assert(childScrollOffset(firstChild!)! > -precisionErrorTolerance);

    // Loop 2: When scrollOffset is at zero, walk back to index 0 (or until the
    // accumulated correction covers the overscroll and trailing cache margin).
    if (scrollOffset < precisionErrorTolerance) {
      final double batchTarget = _computeBatchTarget(constraints);
      double totalCorrection = pendingCorrectionFromLoop1;
      if (totalCorrection > precisionErrorTolerance &&
          (indexOf(firstChild!) == 0 || totalCorrection >= batchTarget)) {
        _consecutiveCorrectionCycles += 1;
        geometry = SliverGeometry(scrollOffsetCorrection: totalCorrection);
        return;
      }
      while (indexOf(firstChild!) > 0) {
        final double earliestScrollOffset = childScrollOffset(firstChild!)!;
        final RenderBox? leading = insertAndLayoutLeadingChild(
          childConstraints,
          parentUsesSize: true,
        );
        if (leading == null) {
          break;
        }
        earliestUsefulChild = leading;
        final double firstChildScrollOffset =
            earliestScrollOffset - paintExtentOf(firstChild!);
        final SliverMultiBoxAdaptorParentData childParentData =
            firstChild!.parentData! as SliverMultiBoxAdaptorParentData;
        if (firstChildScrollOffset < -precisionErrorTolerance) {
          totalCorrection += -firstChildScrollOffset;
          childParentData.layoutOffset = 0.0;
        } else {
          childParentData.layoutOffset = firstChildScrollOffset < 0.0
              ? 0.0
              : firstChildScrollOffset;
          leadingChildWithLayout = earliestUsefulChild;
          trailingChildWithLayout ??= earliestUsefulChild;
        }
        if (totalCorrection > precisionErrorTolerance &&
            (indexOf(firstChild!) == 0 || totalCorrection >= batchTarget)) {
          _consecutiveCorrectionCycles += 1;
          geometry = SliverGeometry(scrollOffsetCorrection: totalCorrection);
          return;
        }
      }
      if (totalCorrection > precisionErrorTolerance) {
        _consecutiveCorrectionCycles += 1;
        geometry = SliverGeometry(scrollOffsetCorrection: totalCorrection);
        return;
      }
    }

    assert(earliestUsefulChild == firstChild);
    assert(childScrollOffset(earliestUsefulChild!)! <= scrollOffset);

    if (leadingChildWithLayout == null) {
      earliestUsefulChild!.layout(childConstraints, parentUsesSize: true);
      leadingChildWithLayout = earliestUsefulChild;
      trailingChildWithLayout = earliestUsefulChild;
    }
    trailingChildWithLayout ??= firstChild;

    bool inLayoutRange = true;
    RenderBox? child = earliestUsefulChild;
    int index = indexOf(child!);
    double endScrollOffset = childScrollOffset(child)! + paintExtentOf(child);
    bool advance() {
      assert(child != null);
      if (child == trailingChildWithLayout) {
        inLayoutRange = false;
      }
      child = childAfter(child!);
      if (child == null) {
        inLayoutRange = false;
      }
      index += 1;
      if (!inLayoutRange) {
        if (child == null || indexOf(child!) != index) {
          child = insertAndLayoutChild(
            childConstraints,
            after: trailingChildWithLayout,
            parentUsesSize: true,
          );
          if (child == null) {
            return false;
          }
        } else {
          child!.layout(childConstraints, parentUsesSize: true);
        }
        trailingChildWithLayout = child;
      }
      assert(child != null);
      final SliverMultiBoxAdaptorParentData childParentData =
          child!.parentData! as SliverMultiBoxAdaptorParentData;
      childParentData.layoutOffset = endScrollOffset;
      assert(childParentData.index == index);
      endScrollOffset = childScrollOffset(child!)! + paintExtentOf(child!);
      return true;
    }

    while (endScrollOffset < scrollOffset) {
      leadingGarbage += 1;
      if (!advance()) {
        assert(leadingGarbage == childCount);
        assert(child == null);
        collectGarbage(leadingGarbage - 1, 0);
        assert(firstChild == lastChild);
        _recordMeasuredExtents();
        final double extent =
            childScrollOffset(lastChild!)! + paintExtentOf(lastChild!);
        _consecutiveCorrectionCycles = 0;
        geometry = SliverGeometry(scrollExtent: extent, maxPaintExtent: extent);
        return;
      }
    }

    while (endScrollOffset < targetEndScrollOffset) {
      if (!advance()) {
        reachedEnd = true;
        break;
      }
    }

    if (child != null) {
      child = childAfter(child!);
      while (child != null) {
        trailingGarbage += 1;
        child = childAfter(child!);
      }
    }

    collectGarbage(leadingGarbage, trailingGarbage);
    _recordMeasuredExtents();

    assert(debugAssertChildListIsNonEmptyAndContiguous());
    final double estimatedMaxScrollOffset;
    if (reachedEnd) {
      estimatedMaxScrollOffset = endScrollOffset;
    } else {
      estimatedMaxScrollOffset = childManager.estimateMaxScrollOffset(
        constraints,
        firstIndex: indexOf(firstChild!),
        lastIndex: indexOf(lastChild!),
        leadingScrollOffset: childScrollOffset(firstChild!),
        trailingScrollOffset: endScrollOffset,
      );
      assert(
        estimatedMaxScrollOffset >=
            endScrollOffset - childScrollOffset(firstChild!)!,
      );
    }
    final double paintExtent = calculatePaintOffset(
      constraints,
      from: childScrollOffset(firstChild!)!,
      to: endScrollOffset,
    );
    final double cacheExtent = calculateCacheOffset(
      constraints,
      from: childScrollOffset(firstChild!)!,
      to: endScrollOffset,
    );
    final double targetEndScrollOffsetForPaint =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    _consecutiveCorrectionCycles = 0;
    geometry = SliverGeometry(
      scrollExtent: estimatedMaxScrollOffset,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: estimatedMaxScrollOffset,
      hasVisualOverflow:
          endScrollOffset > targetEndScrollOffsetForPaint ||
          constraints.scrollOffset > 0.0,
    );

    if (estimatedMaxScrollOffset == endScrollOffset) {
      childManager.setDidUnderflow(true);
    }
    childManager.didFinishLayout();
  }
}
