import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'block_renderer.dart';
import 'controller.dart';
import 'delegates.dart';
import 'theme.dart';

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
  late Map<String, int> _idToIndex;

  Widget? _cachedSliver;
  MarkdownBlockRenderContext? _cachedRenderContext;
  EdgeInsetsGeometry? _cachedPadding;
  bool? _cachedTrailingBlockSpacing;
  bool? _cachedKeepAlives;
  bool? _cachedRepaintBoundaries;

  @override
  void initState() {
    super.initState();
    _rebuildIndexCache();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
        _idToIndex = <String, int>{
          for (int i = 0; i < _visibleBlocks.length; i++)
            _visibleBlocks[i].blockId: i,
        };
        _cachedSliver = null;
      }
    }
  }

  @override
  void dispose() {
    _cachedSliver = null;
    super.dispose();
  }

  void _rebuildIndexCache() {
    _visibleBlocks = SliverMarkdownDocument.visibleBlocksFor(
      widget.document,
      showFrontmatter: widget.showFrontmatter,
      startBlockIndex: widget.startBlockIndex,
      endBlockIndex: widget.endBlockIndex,
    );
    _idToIndex = <String, int>{
      for (int i = 0; i < _visibleBlocks.length; i++)
        _visibleBlocks[i].blockId: i,
    };
    _cachedSliver = null;
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
        widget.theme ?? MarkdownTheme.of(context);
    final MarkdownUrlPolicy resolvedPolicy = widget.delegates.resolveUrlPolicy(
      widget.document.options.urlPolicy,
    );
    final MarkdownBlockRenderContext renderContext = MarkdownBlockRenderContext(
      theme: resolvedTheme,
      delegates: widget.delegates,
      urlPolicy: resolvedPolicy,
      controller: widget.controller,
      remoteImagesApproved: widget.remoteImagesApproved,
      onRequestLoadRemoteImages: widget.onRequestLoadRemoteImages,
      streamingNormalizedSource: widget.streamingNormalizedSource,
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

    final Map<String, int> idToIndex = _idToIndex;
    final bool trailingSpacing = widget.trailingBlockSpacing;
    final Widget listSliver = SliverList(
      delegate: SliverChildBuilderDelegate(
        (BuildContext itemContext, int index) {
          final MarkdownBlockNode block = blocks[index];
          final bool isLast = index == blocks.length - 1;
          return MarkdownTopLevelBlockWidget(
            key: ValueKey<String>(block.blockId),
            node: block,
            renderContext: renderContext,
            bottomSpacing: (isLast && !trailingSpacing)
                ? 0.0
                : resolvedTheme.blockSpacing,
          );
        },
        childCount: blocks.length,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        findChildIndexCallback: (Key key) {
          if (key is ValueKey<String>) {
            return idToIndex[key.value];
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
