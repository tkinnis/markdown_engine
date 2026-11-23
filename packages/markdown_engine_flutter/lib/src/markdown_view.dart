import 'dart:async';

// Keeps SelectionArea compatibility with Flutter 3.32-3.50+ callers.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'block_renderer.dart';
import 'controller.dart';
import 'delegates.dart';
import 'sliver_markdown_document.dart';
import 'theme.dart';

/// High-performance Flutter Markdown viewer supporting lazy sliver
/// virtualization, zero-reparse theme switching, pre-parsed documents, and
/// live incremental streaming.
final class MarkdownView extends StatefulWidget {
  /// Creates a [MarkdownView] that parses [data] once in widget state and only
  /// re-parses when [data], [options], or [engine] changes.
  const MarkdownView(
    String data, {
    super.key,
    this.options,
    this.engine = const MarkdownEngine(),
    this.controller,
    this.theme,
    this.delegates = const MarkdownBuilderDelegates(),
    this.selectable = true,
    this.scrollable = true,
    this.showFrontmatter = true,
    this.padding = EdgeInsets.zero,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.cacheExtent,
    // ignore: prefer_initializing_formals
  }) : data = data,
       document = null,
       streamingController = null,
       streamListenable = null,
       streamPollInterval = null;

  /// Creates a [MarkdownView] displaying an already-parsed [MarkdownDocument]
  /// with zero parsing work inside the widget.
  const MarkdownView.document({
    super.key,
    required MarkdownDocument document,
    this.controller,
    this.theme,
    this.delegates = const MarkdownBuilderDelegates(),
    this.selectable = true,
    this.scrollable = true,
    this.showFrontmatter = true,
    this.padding = EdgeInsets.zero,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.cacheExtent,
  }) : data = null,
       // ignore: prefer_initializing_formals
       document = document,
       options = null,
       engine = const MarkdownEngine(),
       streamingController = null,
       streamListenable = null,
       streamPollInterval = null;

  /// Creates a [MarkdownView] bound to an incremental
  /// [StreamingMarkdownController], smoothly updating settled prefix blocks and
  /// active trailing blocks as chunks arrive.
  const MarkdownView.streaming({
    super.key,
    required StreamingMarkdownController controller,
    MarkdownController? markdownController,
    Listenable? listenable,
    Duration? pollInterval = const Duration(milliseconds: 32),
    this.theme,
    this.delegates = const MarkdownBuilderDelegates(),
    this.selectable = true,
    this.scrollable = true,
    this.showFrontmatter = true,
    this.padding = EdgeInsets.zero,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.cacheExtent,
  }) : data = null,
       document = null,
       options = null,
       engine = const MarkdownEngine(),
       streamingController = controller,
       controller = markdownController,
       streamListenable = listenable,
       streamPollInterval = pollInterval;

  /// Raw Markdown source text when constructed with the default constructor.
  final String? data;

  /// Pre-parsed [MarkdownDocument] when constructed via [MarkdownView.document].
  final MarkdownDocument? document;

  /// Incremental streaming controller when constructed via
  /// [MarkdownView.streaming].
  final StreamingMarkdownController? streamingController;

  /// Optional external [Listenable] notifying [MarkdownView.streaming] when new
  /// chunks are appended to [streamingController].
  final Listenable? streamListenable;

  /// Polling interval used by [MarkdownView.streaming] to pick up chunks
  /// appended to [streamingController] without an external [streamListenable].
  final Duration? streamPollInterval;

  /// Optional per-widget [MarkdownOptions] overriding [engine] defaults.
  final MarkdownOptions? options;

  /// Pure-Dart [MarkdownEngine] instance used when parsing [data].
  final MarkdownEngine engine;

  /// Optional [MarkdownController] exposing parsed outline, parse counts,
  /// reading position, and anchor navigation.
  final MarkdownController? controller;

  /// Optional [MarkdownThemeData] overriding the ambient [MarkdownTheme].
  final MarkdownThemeData? theme;

  /// Pluggable builders and security delegates for links, math, diagrams, code,
  /// and images.
  final MarkdownBuilderDelegates delegates;

  /// Whether rendered text participates in text selection via [SelectionArea].
  final bool selectable;

  /// Whether the view builds a virtualized [CustomScrollView] (`true`) or a
  /// compact non-scrolling [Column] (`false`).
  final bool scrollable;

  /// Whether leading YAML/TOML [FrontmatterNode] metadata cards are rendered.
  final bool showFrontmatter;

  /// Outer padding around the rendered Markdown blocks.
  final EdgeInsetsGeometry padding;

  /// Optional caller-owned [ScrollController] used when [scrollable] is `true`.
  final ScrollController? scrollController;

  /// Optional [ScrollPhysics] forwarded to the internal [CustomScrollView].
  final ScrollPhysics? physics;

  /// Whether the internal [CustomScrollView] shrink-wraps its content extent.
  final bool shrinkWrap;

  /// Optional sliver cache extent forwarded to the internal [CustomScrollView].
  final double? cacheExtent;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

final class _MarkdownViewState extends State<MarkdownView> {
  late MarkdownDocument _document;
  ScrollController? _ownedScrollController;
  Timer? _streamPollTimer;
  bool _remoteImagesApprovedLocally = false;

  ScrollController get _effectiveScrollController {
    final ScrollController? external = widget.scrollController;
    if (external != null) {
      return external;
    }
    return _ownedScrollController ??= ScrollController();
  }

  @override
  void initState() {
    super.initState();
    _attachControllers();
    _initializeDocument();
    _attachStreamListeners();
  }

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.scrollController, widget.scrollController)) {
      _detachControllers(oldWidget);
      _attachControllers();
    }

    if (oldWidget.delegates.imagePolicy != widget.delegates.imagePolicy) {
      _remoteImagesApprovedLocally = false;
    }

    final bool modeChanged =
        (oldWidget.data != null) != (widget.data != null) ||
        (oldWidget.document != null) != (widget.document != null) ||
        (oldWidget.streamingController != null) !=
            (widget.streamingController != null);

    if (!identical(oldWidget.streamListenable, widget.streamListenable) ||
        !identical(oldWidget.streamingController, widget.streamingController) ||
        oldWidget.streamPollInterval != widget.streamPollInterval ||
        modeChanged) {
      _detachStreamListeners(oldWidget);
      _attachStreamListeners();
    }

    if (widget.data != null) {
      if (modeChanged ||
          oldWidget.data != widget.data ||
          oldWidget.options != widget.options ||
          oldWidget.engine != widget.engine) {
        _document = widget.engine.parse(widget.data!, options: widget.options);
        widget.controller?.updateDocument(_document, incrementParseCount: true);
      } else if (!identical(oldWidget.controller, widget.controller)) {
        widget.controller?.updateDocument(_document);
      }
      return;
    }

    if (widget.document != null) {
      if (modeChanged ||
          !identical(oldWidget.document, widget.document) ||
          !identical(oldWidget.controller, widget.controller)) {
        _document = widget.document!;
        widget.controller?.updateDocument(_document);
      }
      return;
    }

    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl != null) {
      final MarkdownDocument latest = streamCtrl.currentDocument;
      if (modeChanged ||
          !identical(_document, latest) ||
          !identical(oldWidget.controller, widget.controller)) {
        _document = latest;
        widget.controller?.updateDocument(_document);
      }
      if (!streamCtrl.isFinished && _streamPollTimer == null) {
        _startStreamPollTimer();
      }
    }
  }

  @override
  void dispose() {
    _detachStreamListeners(widget);
    _detachControllers(widget);
    _ownedScrollController?.dispose();
    _ownedScrollController = null;
    super.dispose();
  }

  void _initializeDocument() {
    if (widget.data != null) {
      _document = widget.engine.parse(widget.data!, options: widget.options);
      widget.controller?.updateDocument(_document, incrementParseCount: true);
      return;
    }
    if (widget.document != null) {
      _document = widget.document!;
      widget.controller?.updateDocument(_document);
      return;
    }
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl != null) {
      _document = streamCtrl.currentDocument;
      widget.controller?.updateDocument(_document);
      return;
    }
    _document = const MarkdownDocument(source: '');
    widget.controller?.updateDocument(_document);
  }

  void _attachControllers() {
    if (widget.controller != null) {
      widget.controller!.attachScrollController(_effectiveScrollController);
    }
  }

  void _detachControllers(MarkdownView targetWidget) {
    final MarkdownController? ctrl = targetWidget.controller;
    if (ctrl == null) {
      return;
    }
    final ScrollController? sc =
        targetWidget.scrollController ?? _ownedScrollController;
    if (sc != null) {
      ctrl.detachScrollController(sc);
    }
  }

  void _attachStreamListeners() {
    if (widget.streamingController == null) {
      return;
    }
    widget.streamListenable?.addListener(_syncFromStream);
    _startStreamPollTimer();
  }

  void _detachStreamListeners(MarkdownView targetWidget) {
    targetWidget.streamListenable?.removeListener(_syncFromStream);
    _streamPollTimer?.cancel();
    _streamPollTimer = null;
  }

  void _startStreamPollTimer() {
    _streamPollTimer?.cancel();
    _streamPollTimer = null;
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    final Duration? interval = widget.streamPollInterval;
    if (streamCtrl == null ||
        interval == null ||
        interval <= Duration.zero ||
        streamCtrl.isFinished) {
      return;
    }
    _streamPollTimer = Timer.periodic(interval, _onStreamPollTick);
  }

  void _onStreamPollTick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl == null) {
      timer.cancel();
      return;
    }
    _syncFromStream();
    if (streamCtrl.isFinished) {
      timer.cancel();
      if (identical(_streamPollTimer, timer)) {
        _streamPollTimer = null;
      }
    }
  }

  void _syncFromStream() {
    if (!mounted) {
      return;
    }
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl == null) {
      return;
    }
    final MarkdownDocument latest = streamCtrl.currentDocument;
    if (!identical(latest, _document)) {
      setState(() {
        _document = latest;
      });
      widget.controller?.updateDocument(latest);
    }
  }

  void _approveRemoteImagesLocally() {
    if (!_remoteImagesApprovedLocally) {
      setState(() {
        _remoteImagesApprovedLocally = true;
      });
    }
  }

  Widget _buildNonScrollingColumn(
    BuildContext context,
    List<MarkdownBlockNode> visibleBlocks,
    MarkdownDocument activeDocument,
    MarkdownThemeData resolvedTheme,
  ) {
    final MarkdownUrlPolicy resolvedPolicy = widget.delegates.resolveUrlPolicy(
      activeDocument.options.urlPolicy,
    );
    final MarkdownBlockRenderContext renderContext = MarkdownBlockRenderContext(
      theme: resolvedTheme,
      delegates: widget.delegates,
      urlPolicy: resolvedPolicy,
      controller: widget.controller,
      remoteImagesApproved: _remoteImagesApprovedLocally,
      onRequestLoadRemoteImages: _approveRemoteImagesLocally,
    );

    final Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < visibleBlocks.length; i++)
          MarkdownTopLevelBlockWidget(
            key: ValueKey<String>(visibleBlocks[i].blockId),
            node: visibleBlocks[i],
            renderContext: renderContext,
            bottomSpacing: i == visibleBlocks.length - 1
                ? 0.0
                : resolvedTheme.blockSpacing,
          ),
      ],
    );

    if (widget.padding == EdgeInsets.zero) {
      return column;
    }
    return Padding(padding: widget.padding, child: column);
  }

  Widget _buildScrollableView(
    MarkdownDocument activeDocument,
    MarkdownThemeData resolvedTheme,
  ) {
    final Widget sliver = SliverMarkdownDocument(
      document: activeDocument,
      theme: resolvedTheme,
      delegates: widget.delegates,
      controller: widget.controller,
      showFrontmatter: widget.showFrontmatter,
      padding: widget.padding == EdgeInsets.zero ? null : widget.padding,
      remoteImagesApproved: _remoteImagesApprovedLocally,
      onRequestLoadRemoteImages: _approveRemoteImagesLocally,
    );

    return CustomScrollView(
      controller: _effectiveScrollController,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      // Keeps compatibility down to Flutter 3.32 before scrollCacheExtent.
      // ignore: deprecated_member_use
      cacheExtent: widget.cacheExtent,
      slivers: <Widget>[sliver],
    );
  }

  @override
  Widget build(BuildContext context) {
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl != null) {
      final MarkdownDocument latest = streamCtrl.currentDocument;
      if (!identical(latest, _document)) {
        _document = latest;
        widget.controller?.updateDocument(latest);
      }
    }

    final MarkdownDocument activeDocument = _document;
    final MarkdownThemeData resolvedTheme =
        widget.theme ?? MarkdownTheme.of(context);
    final List<MarkdownBlockNode> visibleBlocks =
        SliverMarkdownDocument.visibleBlocksFor(
          activeDocument,
          showFrontmatter: widget.showFrontmatter,
        );

    if (visibleBlocks.isEmpty) {
      return const SizedBox.shrink();
    }

    final Widget content;
    if (!widget.scrollable) {
      content = _buildNonScrollingColumn(
        context,
        visibleBlocks,
        activeDocument,
        resolvedTheme,
      );
    } else {
      content = LayoutBuilder(
        builder: (BuildContext layoutContext, BoxConstraints constraints) {
          if (constraints.hasBoundedHeight || widget.shrinkWrap) {
            return _buildScrollableView(activeDocument, resolvedTheme);
          }
          return _buildNonScrollingColumn(
            layoutContext,
            visibleBlocks,
            activeDocument,
            resolvedTheme,
          );
        },
      );
    }

    if (!widget.selectable) {
      return content;
    }
    if (SelectionContainer.maybeOf(context) != null) {
      return content;
    }
    return SelectionArea(child: content);
  }
}
