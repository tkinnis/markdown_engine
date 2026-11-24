import 'package:flutter/foundation.dart' show ValueListenable;
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

  MarkdownBlockRenderContext? _blockCacheContext;
  final List<MarkdownBlockNode?> _cachedBlockNodes = <MarkdownBlockNode?>[];
  final List<Widget?> _cachedInnerWidgets = <Widget?>[];
  final List<Widget?> _cachedTopWidgets = <Widget?>[];
  final List<bool> _cachedHasBottomSpacing = <bool>[];

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
        if (_cachedBlockNodes.length > _visibleBlocks.length) {
          _cachedBlockNodes.length = _visibleBlocks.length;
          _cachedInnerWidgets.length = _visibleBlocks.length;
          _cachedTopWidgets.length = _visibleBlocks.length;
          _cachedHasBottomSpacing.length = _visibleBlocks.length;
        }
      }
    }
  }

  @override
  void dispose() {
    _cachedSliver = null;
    _clearPerBlockCache();
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

    final Widget? cached = _cachedSliver;
    if (cached != null &&
        _cachedRenderContext == renderContext &&
        _cachedPadding == widget.padding &&
        _cachedTrailingBlockSpacing == widget.trailingBlockSpacing &&
        _cachedKeepAlives == widget.addAutomaticKeepAlives &&
        _cachedRepaintBoundaries == widget.addRepaintBoundaries) {
      return cached;
    }

    final bool trailingSpacing = widget.trailingBlockSpacing;
    if (_blockCacheContext != renderContext) {
      _clearPerBlockCache();
      _blockCacheContext = renderContext;
    }

    final bool isStreamActive =
        streamScope?.isStreamActiveProvider() ??
        (widget.streamingNormalizedSource != null);
    final ValueListenable<MarkdownBlockNode> Function(MarkdownBlockNode block)?
    slotListenableFor = streamScope?.slotListenableFor;
    final double blockSpacing = resolvedTheme.blockSpacing;

    final Widget listSliver = SliverList(
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
