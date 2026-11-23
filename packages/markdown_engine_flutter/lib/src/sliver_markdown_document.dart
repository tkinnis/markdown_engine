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

  /// Returns the visible top-level blocks for [document] honoring
  /// [showFrontmatter].
  static List<MarkdownBlockNode> visibleBlocksFor(
    MarkdownDocument document, {
    required bool showFrontmatter,
  }) {
    final List<MarkdownBlockNode> blocks = document.blocks;
    if (showFrontmatter || blocks.isEmpty) {
      return blocks;
    }
    if (blocks.first is! FrontmatterNode &&
        !blocks.any((MarkdownBlockNode b) => b is FrontmatterNode)) {
      return blocks;
    }
    return blocks
        .where((MarkdownBlockNode b) => b is! FrontmatterNode)
        .toList(growable: false);
  }

  @override
  State<SliverMarkdownDocument> createState() => _SliverMarkdownDocumentState();
}

final class _SliverMarkdownDocumentState extends State<SliverMarkdownDocument> {
  late List<MarkdownBlockNode> _visibleBlocks;
  late Map<String, int> _idToIndex;

  @override
  void initState() {
    super.initState();
    _rebuildIndexCache();
  }

  @override
  void didUpdateWidget(SliverMarkdownDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document) ||
        oldWidget.showFrontmatter != widget.showFrontmatter) {
      _rebuildIndexCache();
    }
  }

  void _rebuildIndexCache() {
    _visibleBlocks = SliverMarkdownDocument.visibleBlocksFor(
      widget.document,
      showFrontmatter: widget.showFrontmatter,
    );
    _idToIndex = <String, int>{
      for (int i = 0; i < _visibleBlocks.length; i++)
        _visibleBlocks[i].blockId: i,
    };
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
    );

    final Widget sliver = SliverList(
      delegate: SliverChildBuilderDelegate(
        (BuildContext itemContext, int index) {
          final MarkdownBlockNode block = blocks[index];
          final bool isLast = index == blocks.length - 1;
          return MarkdownTopLevelBlockWidget(
            key: ValueKey<String>(block.blockId),
            node: block,
            renderContext: renderContext,
            bottomSpacing: isLast ? 0.0 : resolvedTheme.blockSpacing,
          );
        },
        childCount: blocks.length,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        findChildIndexCallback: (Key key) {
          if (key is ValueKey<String>) {
            return _idToIndex[key.value];
          }
          return null;
        },
      ),
    );

    final EdgeInsetsGeometry? pad = widget.padding;
    if (pad != null) {
      return SliverPadding(padding: pad, sliver: sliver);
    }
    return sliver;
  }
}
