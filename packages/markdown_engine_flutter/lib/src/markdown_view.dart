// Keeps MaterialLocalizations/SelectionArea compatibility with Flutter 3.32-3.50+ callers.
// ignore: deprecated_member_use
import 'package:flutter/material.dart'
    show MaterialLocalizations, SelectionArea;
import 'package:flutter/rendering.dart';
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
  /// Creates a [MarkdownView] that parses [data] once in widget state and
  /// incrementally updates on subsequent [data] edits.
  const MarkdownView(
    String data, {
    super.key,
    this.options,
    this.engine = const MarkdownEngine(),
    this.controller,
    this.theme,
    this.delegates = const MarkdownBuilderDelegates(),
    this.selectable = true,
    this.focusNode,
    this.scrollable = true,
    this.showFrontmatter = true,
    this.remoteImagesApproved = false,
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
    this.focusNode,
    this.scrollable = true,
    this.showFrontmatter = true,
    this.remoteImagesApproved = false,
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
  /// [StreamingMarkdownController], subscribing directly to its push
  /// notifications without polling timers.
  const MarkdownView.streaming({
    super.key,
    required StreamingMarkdownController controller,
    MarkdownController? markdownController,
    Listenable? listenable,
    Duration? pollInterval,
    this.theme,
    this.delegates = const MarkdownBuilderDelegates(),
    this.selectable = true,
    this.focusNode,
    this.scrollable = true,
    this.showFrontmatter = true,
    this.remoteImagesApproved = false,
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

  /// Optional extra [Listenable] notifying [MarkdownView.streaming] alongside
  /// [StreamingMarkdownController]'s built-in push listener notifications.
  final Listenable? streamListenable;

  /// Deprecated no-op retained for source compatibility;
  /// [MarkdownView.streaming] uses push notifications from
  /// [StreamingMarkdownController] with zero polling timers.
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

  /// Whether rendered text participates in text selection via [SelectionArea]
  /// or [SelectableRegion].
  final bool selectable;

  /// Optional [FocusNode] forwarded to the enclosing [SelectionArea] or
  /// [SelectableRegion] for keyboard shortcuts such as Select All and Copy.
  final FocusNode? focusNode;

  /// Whether the view builds a virtualized [CustomScrollView] (`true`) or a
  /// compact non-scrolling [Column] (`false`).
  final bool scrollable;

  /// Whether leading YAML/TOML [FrontmatterNode] metadata cards are rendered.
  final bool showFrontmatter;

  /// Whether remote images are approved by the caller when
  /// [MarkdownBuilderDelegates.imagePolicy] is [MarkdownImagePolicy.ask].
  final bool remoteImagesApproved;

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
  bool _remoteImagesApprovedLocally = false;
  _MarkdownSelectionContainerDelegate? _selectionDelegate;

  ScrollController get _effectiveScrollController {
    final ScrollController? external = widget.scrollController;
    if (external != null) {
      return external;
    }
    return _ownedScrollController ??= ScrollController();
  }

  bool get _effectiveRemoteImagesApproved =>
      widget.remoteImagesApproved ||
      widget.delegates.remoteImagesApproved ||
      _remoteImagesApprovedLocally;

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
        !identical(oldWidget.scrollController, widget.scrollController) ||
        oldWidget.scrollable != widget.scrollable ||
        oldWidget.showFrontmatter != widget.showFrontmatter) {
      _detachControllers(oldWidget);
      if (!widget.scrollable || widget.scrollController != null) {
        _ownedScrollController?.dispose();
        _ownedScrollController = null;
      }
      _attachControllers();
    }

    final bool modeChanged =
        (oldWidget.data != null) != (widget.data != null) ||
        (oldWidget.document != null) != (widget.document != null) ||
        (oldWidget.streamingController != null) !=
            (widget.streamingController != null);

    if (oldWidget.delegates.imagePolicy != widget.delegates.imagePolicy ||
        modeChanged ||
        (oldWidget.remoteImagesApproved && !widget.remoteImagesApproved) ||
        (oldWidget.delegates.remoteImagesApproved &&
            !widget.delegates.remoteImagesApproved) ||
        (widget.data != null && oldWidget.data != widget.data) ||
        (widget.document != null &&
            !identical(oldWidget.document, widget.document)) ||
        (widget.streamingController != null &&
            !identical(
              oldWidget.streamingController,
              widget.streamingController,
            ))) {
      _remoteImagesApprovedLocally = false;
    }

    if (oldWidget.selectable && !widget.selectable) {
      _selectionDelegate?.dispose();
      _selectionDelegate = null;
    }

    if (!identical(oldWidget.streamListenable, widget.streamListenable) ||
        !identical(oldWidget.streamingController, widget.streamingController) ||
        modeChanged) {
      _detachStreamListeners(oldWidget);
      _attachStreamListeners();
    }

    if (widget.data != null) {
      final bool compatibleForIncremental =
          !modeChanged &&
          oldWidget.data != null &&
          oldWidget.options == widget.options &&
          oldWidget.engine == widget.engine;
      if (compatibleForIncremental && oldWidget.data != widget.data) {
        final IncrementalParseResult result =
            IncrementalMarkdownParser(engine: widget.engine).parseIncremental(
              widget.data!,
              previousDocument: _document,
              options: widget.options,
            );
        _document = result.document;
        widget.controller?.updateDocument(
          _document,
          incrementParseCount: true,
          showFrontmatter: widget.showFrontmatter,
        );
        _selectionDelegate?.clearSelectAllState();
      } else if (modeChanged ||
          oldWidget.data != widget.data ||
          oldWidget.options != widget.options ||
          oldWidget.engine != widget.engine) {
        _document = widget.engine.parse(widget.data!, options: widget.options);
        widget.controller?.updateDocument(
          _document,
          incrementParseCount: true,
          showFrontmatter: widget.showFrontmatter,
        );
        _selectionDelegate?.clearSelectAllState();
      } else if (!identical(oldWidget.controller, widget.controller) ||
          oldWidget.showFrontmatter != widget.showFrontmatter) {
        widget.controller?.updateDocument(
          _document,
          showFrontmatter: widget.showFrontmatter,
        );
      }
      return;
    }

    if (widget.document != null) {
      final bool docChanged =
          modeChanged || !identical(oldWidget.document, widget.document);
      if (docChanged ||
          !identical(oldWidget.controller, widget.controller) ||
          oldWidget.showFrontmatter != widget.showFrontmatter) {
        _document = widget.document!;
        widget.controller?.updateDocument(
          _document,
          showFrontmatter: widget.showFrontmatter,
        );
        if (docChanged) {
          _selectionDelegate?.clearSelectAllState();
        }
      }
      return;
    }

    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl != null) {
      final MarkdownDocument latest = streamCtrl.currentDocument;
      if (modeChanged ||
          !identical(_document, latest) ||
          !identical(oldWidget.controller, widget.controller) ||
          oldWidget.showFrontmatter != widget.showFrontmatter) {
        _document = latest;
        widget.controller?.updateDocument(
          _document,
          showFrontmatter: widget.showFrontmatter,
        );
        if (modeChanged || latest.source.isEmpty) {
          _selectionDelegate?.clearSelectAllState();
        }
      }
    }
  }

  @override
  void dispose() {
    _detachStreamListeners(widget);
    _detachControllers(widget);
    _selectionDelegate?.dispose();
    _selectionDelegate = null;
    _ownedScrollController?.dispose();
    _ownedScrollController = null;
    super.dispose();
  }

  void _initializeDocument() {
    if (widget.data != null) {
      _document = widget.engine.parse(widget.data!, options: widget.options);
      widget.controller?.updateDocument(
        _document,
        incrementParseCount: true,
        showFrontmatter: widget.showFrontmatter,
      );
      return;
    }
    if (widget.document != null) {
      _document = widget.document!;
      widget.controller?.updateDocument(
        _document,
        showFrontmatter: widget.showFrontmatter,
      );
      return;
    }
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl != null) {
      _document = streamCtrl.currentDocument;
      widget.controller?.updateDocument(
        _document,
        showFrontmatter: widget.showFrontmatter,
      );
      return;
    }
    _document = const MarkdownDocument(source: '');
    widget.controller?.updateDocument(
      _document,
      showFrontmatter: widget.showFrontmatter,
    );
  }

  void _attachControllers() {
    if (widget.controller != null && widget.scrollable) {
      widget.controller!.attachScrollController(
        _effectiveScrollController,
        owner: this,
        showFrontmatter: widget.showFrontmatter,
      );
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
      ctrl.detachScrollController(sc, owner: this);
    }
  }

  void _attachStreamListeners() {
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl == null) {
      return;
    }
    streamCtrl.addListener(_syncFromStream);
    widget.streamListenable?.addListener(_syncFromStream);
  }

  void _detachStreamListeners(MarkdownView targetWidget) {
    targetWidget.streamingController?.removeListener(_syncFromStream);
    targetWidget.streamListenable?.removeListener(_syncFromStream);
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
      final bool wasReset =
          latest.source.isEmpty && _document.source.isNotEmpty;
      setState(() {
        _document = latest;
        if (wasReset) {
          _remoteImagesApprovedLocally = false;
        }
      });
      if (wasReset) {
        _selectionDelegate?.clearSelectAllState();
      }
      widget.controller?.updateDocument(
        latest,
        showFrontmatter: widget.showFrontmatter,
      );
    }
  }

  void _approveRemoteImagesLocally() {
    if (!_remoteImagesApprovedLocally) {
      setState(() {
        _remoteImagesApprovedLocally = true;
      });
    }
  }

  _MarkdownSelectionContainerDelegate _ensureSelectionDelegate(
    MarkdownDocument activeDocument,
  ) {
    final _MarkdownSelectionContainerDelegate delegate = _selectionDelegate ??=
        _MarkdownSelectionContainerDelegate();
    delegate.fullPlainTextProvider = () => activeDocument.toPlainText();
    return delegate;
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
      remoteImagesApproved: _effectiveRemoteImagesApproved,
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
      remoteImagesApproved: _effectiveRemoteImagesApproved,
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

    final SelectionRegistrar? ancestorRegistrar = SelectionContainer.maybeOf(
      context,
    );
    final Widget selectableContent = SelectionContainer(
      delegate: _ensureSelectionDelegate(activeDocument),
      child: content,
    );
    if (ancestorRegistrar != null) {
      return selectableContent;
    }

    final bool hasMaterialLocalizations =
        Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) !=
        null;
    if (hasMaterialLocalizations) {
      return SelectionArea(
        focusNode: widget.focusNode,
        child: selectableContent,
      );
    }

    if (MediaQuery.maybeOf(context) != null &&
        Overlay.maybeOf(context) != null) {
      return SelectableRegion(
        focusNode: widget.focusNode,
        selectionControls: emptyTextSelectionControls,
        child: selectableContent,
      );
    }

    return content;
  }
}

final class _MarkdownSelectionContainerDelegate
    extends StaticSelectionContainerDelegate {
  bool _isSelectAllActive = false;
  final Set<Selectable> _selectAllDispatched = <Selectable>{};
  String Function()? fullPlainTextProvider;

  void clearSelectAllState() {
    _isSelectAllActive = false;
    _selectAllDispatched.clear();
  }

  @override
  void remove(Selectable selectable) {
    _selectAllDispatched.remove(selectable);
    super.remove(selectable);
  }

  @override
  void didChangeSelectables() {
    super.didChangeSelectables();
    if (_isSelectAllActive) {
      for (final Selectable selectable in selectables) {
        if (_selectAllDispatched.add(selectable)) {
          dispatchSelectionEventToChild(
            selectable,
            const SelectAllSelectionEvent(),
          );
        }
      }
      currentSelectionStartIndex = selectables.isEmpty ? -1 : 0;
      currentSelectionEndIndex = selectables.isEmpty
          ? -1
          : selectables.length - 1;
    }
  }

  @override
  SelectionResult handleSelectAll(SelectAllSelectionEvent event) {
    _isSelectAllActive = true;
    _selectAllDispatched
      ..clear()
      ..addAll(selectables);
    return super.handleSelectAll(event);
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    clearSelectAllState();
    return super.handleClearSelection(event);
  }

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    clearSelectAllState();
    return super.handleSelectionEdgeUpdate(event);
  }

  @override
  SelectionResult handleSelectWord(SelectWordSelectionEvent event) {
    clearSelectAllState();
    return super.handleSelectWord(event);
  }

  @override
  SelectionResult handleSelectParagraph(SelectParagraphSelectionEvent event) {
    clearSelectAllState();
    return super.handleSelectParagraph(event);
  }

  @override
  SelectionResult handleGranularlyExtendSelection(
    GranularlyExtendSelectionEvent event,
  ) {
    clearSelectAllState();
    return super.handleGranularlyExtendSelection(event);
  }

  @override
  SelectionResult handleDirectionallyExtendSelection(
    DirectionallyExtendSelectionEvent event,
  ) {
    clearSelectAllState();
    return super.handleDirectionallyExtendSelection(event);
  }

  @override
  SelectedContent? getSelectedContent() {
    if (_isSelectAllActive) {
      final String fullText = fullPlainTextProvider?.call() ?? '';
      return fullText.isEmpty ? null : SelectedContent(plainText: fullText);
    }
    return super.getSelectedContent();
  }

  @override
  void dispose() {
    _selectAllDispatched.clear();
    super.dispose();
  }
}
