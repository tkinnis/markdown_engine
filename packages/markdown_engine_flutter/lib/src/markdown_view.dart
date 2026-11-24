import 'package:flutter/foundation.dart'
    show ValueListenable, precisionErrorTolerance;
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
import 'fast_text.dart';
import 'sliver_markdown_document.dart';
import 'streaming_canvas.dart';
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

final class _MarkdownViewPayload {
  const _MarkdownViewPayload({
    required this.document,
    required this.theme,
    required this.delegates,
    required this.controller,
    required this.showFrontmatter,
    required this.remoteImagesApproved,
    required this.onRequestLoadRemoteImages,
    required this.padding,
    required this.isStreamActive,
    required this.addAutomaticKeepAlives,
    required this.addRepaintBoundaries,
    required this.useStreamingCanvas,
    this.canvasListenable,
    required this.revision,
  });

  final MarkdownDocument document;
  final MarkdownThemeData? theme;
  final MarkdownBuilderDelegates delegates;
  final MarkdownController? controller;
  final bool showFrontmatter;
  final bool remoteImagesApproved;
  final VoidCallback onRequestLoadRemoteImages;
  final EdgeInsetsGeometry padding;
  final bool isStreamActive;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool useStreamingCanvas;
  final ValueListenable<MarkdownStreamingCanvasPayload>? canvasListenable;
  final int revision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MarkdownViewPayload && revision == other.revision;

  @override
  int get hashCode => revision.hashCode;
}

final class _MarkdownViewState extends State<MarkdownView> {
  late MarkdownDocument _document;
  ScrollController? _ownedScrollController;
  bool _remoteImagesApprovedLocally = false;
  bool _lastStreamFinished = false;
  int _payloadRevision = 0;
  late final ValueNotifier<_MarkdownViewPayload> _payloadNotifier;
  final Map<String, ValueNotifier<MarkdownBlockNode>> _slotNotifiers =
      <String, ValueNotifier<MarkdownBlockNode>>{};
  List<MarkdownBlockNode> _lastStreamBlocks = const <MarkdownBlockNode>[];
  int _lastSettledScanStart = 0;
  bool _hadNonScrollingFallback = false;
  bool _hasMountedContent = false;
  bool? _lastPayloadStreamActive;
  MarkdownOptions? _lastPayloadDocOptions;
  MarkdownThemeData? _lastPayloadTheme;
  MarkdownBuilderDelegates? _lastPayloadDelegates;
  MarkdownController? _lastPayloadController;
  bool? _lastPayloadShowFrontmatter;
  bool? _lastPayloadRemoteImagesApproved;
  bool? _lastPayloadUseCanvas;
  ValueNotifier<MarkdownStreamingCanvasPayload>? _canvasNotifier;
  int _canvasRevision = 0;
  bool _lastUsedStreamingCanvas = false;
  int _settledCanvasCheckedCount = 0;
  bool _settledCanvasSupported = true;
  EdgeInsetsGeometry? _lastPayloadPadding;
  _MarkdownSelectionContainerDelegate? _selectionDelegate;

  Widget? _cachedRootContent;
  bool? _cachedSelectable;
  FocusNode? _cachedFocusNode;
  bool? _cachedScrollable;
  ScrollController? _cachedScrollController;
  ScrollPhysics? _cachedPhysics;
  bool? _cachedShrinkWrap;
  double? _cachedCacheExtent;
  bool? _cachedHadAncestorRegistrar;
  bool? _cachedHasMaterialLocalizations;
  bool? _cachedHasSelectableRegionEnv;
  bool? _cachedHasStreamingController;

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

  void _disposeSlotNotifiers() {
    for (final ValueNotifier<MarkdownBlockNode> notifier
        in _slotNotifiers.values) {
      notifier.dispose();
    }
    _slotNotifiers.clear();
    _lastStreamBlocks = const <MarkdownBlockNode>[];
    _lastSettledScanStart = 0;
  }

  ValueNotifier<MarkdownBlockNode> _slotListenableFor(MarkdownBlockNode block) {
    final ValueNotifier<MarkdownBlockNode>? existing =
        _slotNotifiers[block.blockId];
    if (existing != null) {
      if (!identical(existing.value, block)) {
        existing.value = block;
      }
      return existing;
    }
    return _slotNotifiers[block.blockId] = ValueNotifier<MarkdownBlockNode>(
      block,
    );
  }

  MarkdownStreamingCanvasPayload _buildCanvasPayload() =>
      MarkdownStreamingCanvasPayload(
        document: _document,
        themeOverride: widget.theme,
        padding: widget.padding,
        showFrontmatter: widget.showFrontmatter,
        revision: ++_canvasRevision,
      );

  bool _computeUseStreamingCanvas(
    StreamingMarkdownController streamCtrl,
    List<MarkdownBlockNode> blocks, {
    required bool resetCanvasCache,
  }) {
    if (widget.controller != null ||
        !canUseStreamingCanvasDelegates(widget.delegates)) {
      _settledCanvasCheckedCount = 0;
      _settledCanvasSupported = true;
      return false;
    }
    if (resetCanvasCache || blocks.length < _settledCanvasCheckedCount) {
      _settledCanvasCheckedCount = 0;
      _settledCanvasSupported = true;
    }
    if (blocks.isEmpty) {
      return _lastUsedStreamingCanvas;
    }
    if (blocks.length == 1) {
      return false;
    }
    if (!_settledCanvasSupported) {
      return false;
    }
    final int settledEnd = streamCtrl.settledPrefixBlockCount.clamp(
      0,
      blocks.length,
    );
    while (_settledCanvasCheckedCount < settledEnd) {
      if (!isCanvasSupportedBlock(
        blocks[_settledCanvasCheckedCount],
        widget.delegates,
        showFrontmatter: widget.showFrontmatter,
      )) {
        _settledCanvasSupported = false;
        return false;
      }
      _settledCanvasCheckedCount++;
    }
    final bool canTrustPrevStreamBlocks =
        !resetCanvasCache && _lastPayloadUseCanvas == true;
    for (int i = settledEnd; i < blocks.length; i++) {
      final MarkdownBlockNode block = blocks[i];
      if (canTrustPrevStreamBlocks &&
          i < _lastStreamBlocks.length &&
          identical(block, _lastStreamBlocks[i])) {
        continue;
      }
      if (!isCanvasSupportedBlock(
        block,
        widget.delegates,
        showFrontmatter: widget.showFrontmatter,
      )) {
        return false;
      }
    }
    return true;
  }

  _MarkdownViewPayload _buildPayload({
    required int revision,
    required bool useStreamingCanvas,
  }) {
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    final bool isStreamingMode = streamCtrl != null;
    final bool isActiveStream = isStreamingMode && !streamCtrl.isFinished;
    return _MarkdownViewPayload(
      document: _document,
      theme: widget.theme,
      delegates: widget.delegates,
      controller: widget.controller,
      showFrontmatter: widget.showFrontmatter,
      remoteImagesApproved: _effectiveRemoteImagesApproved,
      onRequestLoadRemoteImages: _approveRemoteImagesLocally,
      padding: widget.padding,
      isStreamActive: isActiveStream,
      addAutomaticKeepAlives: !isStreamingMode,
      addRepaintBoundaries: isStreamingMode,
      useStreamingCanvas: useStreamingCanvas,
      canvasListenable: useStreamingCanvas ? _canvasNotifier : null,
      revision: revision,
    );
  }

  void _recordStreamPayloadMeta(
    StreamingMarkdownController streamCtrl,
    bool isActiveStream,
    bool approved, {
    required bool useStreamingCanvas,
  }) {
    final List<MarkdownBlockNode> blocks = _document.blocks;
    _lastStreamBlocks = blocks;
    _lastSettledScanStart = streamCtrl.settledPrefixBlockCount.clamp(
      0,
      blocks.length,
    );
    _lastPayloadTheme = widget.theme;
    _lastPayloadDelegates = widget.delegates;
    _lastPayloadController = widget.controller;
    _lastPayloadShowFrontmatter = widget.showFrontmatter;
    _lastPayloadRemoteImagesApproved = approved;
    _lastPayloadPadding = widget.padding;
    _lastPayloadStreamActive = isActiveStream;
    _lastPayloadDocOptions = _document.options;
    _lastPayloadUseCanvas = useStreamingCanvas;
  }

  void _pushPayload({bool forceSliver = false}) {
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl == null) {
      _lastUsedStreamingCanvas = false;
      _lastPayloadUseCanvas = false;
      _payloadNotifier.value = _buildPayload(
        revision: ++_payloadRevision,
        useStreamingCanvas: false,
      );
      return;
    }

    final List<MarkdownBlockNode> blocks = _document.blocks;
    if (blocks.isEmpty) {
      _disposeSlotNotifiers();
    }

    final bool isActiveStream = !streamCtrl.isFinished;
    final bool approved = _effectiveRemoteImagesApproved;
    final bool nonCanvasConfigChanged =
        forceSliver ||
        !widget.scrollable ||
        _hadNonScrollingFallback ||
        _lastPayloadDelegates != widget.delegates ||
        !identical(_lastPayloadController, widget.controller) ||
        _lastPayloadShowFrontmatter != widget.showFrontmatter ||
        _lastPayloadRemoteImagesApproved != approved ||
        _lastPayloadDocOptions != _document.options;

    final bool useCanvas = _computeUseStreamingCanvas(
      streamCtrl,
      blocks,
      resetCanvasCache: nonCanvasConfigChanged,
    );
    _lastUsedStreamingCanvas = useCanvas;

    if (useCanvas) {
      final MarkdownStreamingCanvasPayload canvasPayload =
          _buildCanvasPayload();
      final ValueNotifier<MarkdownStreamingCanvasPayload>? existingCanvas =
          _canvasNotifier;
      if (existingCanvas == null) {
        _canvasNotifier = ValueNotifier<MarkdownStreamingCanvasPayload>(
          canvasPayload,
        );
      } else {
        existingCanvas.value = canvasPayload;
      }
      final bool modeTransition =
          nonCanvasConfigChanged || _lastPayloadUseCanvas != true;
      if (modeTransition) {
        _recordStreamPayloadMeta(
          streamCtrl,
          isActiveStream,
          approved,
          useStreamingCanvas: true,
        );
        _payloadNotifier.value = _buildPayload(
          revision: ++_payloadRevision,
          useStreamingCanvas: true,
        );
      } else {
        _lastStreamBlocks = blocks;
        _lastSettledScanStart = streamCtrl.settledPrefixBlockCount.clamp(
          0,
          blocks.length,
        );
      }
      return;
    }

    final bool configChanged =
        nonCanvasConfigChanged ||
        _lastPayloadUseCanvas != false ||
        _lastPayloadTheme != widget.theme ||
        _lastPayloadPadding != widget.padding ||
        _lastPayloadStreamActive != isActiveStream;

    final int newLen = blocks.length;
    final int prevLen = _lastStreamBlocks.length;
    bool structuralChange = configChanged || newLen != prevLen;
    if (!structuralChange && newLen > 0) {
      final int scanFrom = _lastSettledScanStart.clamp(0, newLen - 1);
      for (int i = newLen - 1; i >= scanFrom; i--) {
        if (blocks[i].blockId != _lastStreamBlocks[i].blockId) {
          structuralChange = true;
          break;
        }
      }
    }

    final int updateScanStart = _lastSettledScanStart.clamp(0, newLen);
    for (int i = newLen - 1; i >= updateScanStart; i--) {
      final MarkdownBlockNode block = blocks[i];
      final ValueNotifier<MarkdownBlockNode>? slot =
          _slotNotifiers[block.blockId];
      if (slot != null && !identical(slot.value, block)) {
        slot.value = block;
      }
    }
    if (updateScanStart > 0 && !isActiveStream) {
      for (int i = updateScanStart - 1; i >= 0; i--) {
        final MarkdownBlockNode block = blocks[i];
        final ValueNotifier<MarkdownBlockNode>? slot =
            _slotNotifiers[block.blockId];
        if (slot != null && !identical(slot.value, block)) {
          slot.value = block;
        }
      }
    }

    _lastStreamBlocks = blocks;
    _lastSettledScanStart = streamCtrl.settledPrefixBlockCount.clamp(0, newLen);

    if (structuralChange) {
      _recordStreamPayloadMeta(
        streamCtrl,
        isActiveStream,
        approved,
        useStreamingCanvas: false,
      );
      _payloadNotifier.value = _buildPayload(
        revision: ++_payloadRevision,
        useStreamingCanvas: false,
      );
    }
  }

  String? _provideStreamingNormalizedSource() {
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl == null || streamCtrl.isFinished) {
      return null;
    }
    return _document.source;
  }

  bool _isStreamActive() {
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    return streamCtrl != null && !streamCtrl.isFinished;
  }

  String _provideFullPlainText() => _document.toPlainText();

  static bool _hasVisibleBlocks(MarkdownDocument doc, bool showFrontmatter) {
    final List<MarkdownBlockNode> blocks = doc.blocks;
    if (blocks.isEmpty) {
      return false;
    }
    if (showFrontmatter) {
      return true;
    }
    for (int i = 0; i < blocks.length; i++) {
      if (blocks[i] is! FrontmatterNode) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _attachControllers();
    _initializeDocument();
    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    _lastStreamFinished = streamCtrl?.isFinished ?? false;
    final bool useCanvas =
        streamCtrl != null &&
        _computeUseStreamingCanvas(
          streamCtrl,
          _document.blocks,
          resetCanvasCache: true,
        );
    _lastUsedStreamingCanvas = useCanvas;
    if (useCanvas) {
      _canvasNotifier = ValueNotifier<MarkdownStreamingCanvasPayload>(
        _buildCanvasPayload(),
      );
    }
    _payloadNotifier = ValueNotifier<_MarkdownViewPayload>(
      _buildPayload(
        revision: ++_payloadRevision,
        useStreamingCanvas: useCanvas,
      ),
    );
    if (streamCtrl != null) {
      _recordStreamPayloadMeta(
        streamCtrl,
        !streamCtrl.isFinished,
        _effectiveRemoteImagesApproved,
        useStreamingCanvas: useCanvas,
      );
    }
    _attachStreamListeners();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedRootContent = null;
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
      _disposeSlotNotifiers();
      if (!identical(
            oldWidget.streamingController,
            widget.streamingController,
          ) ||
          modeChanged) {
        _hasMountedContent = false;
        _lastUsedStreamingCanvas = false;
        _settledCanvasCheckedCount = 0;
        _settledCanvasSupported = true;
      }
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
      _pushPayload();
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
      _pushPayload();
      return;
    }

    final StreamingMarkdownController? streamCtrl = widget.streamingController;
    if (streamCtrl != null) {
      final MarkdownDocument latest = streamCtrl.currentDocument;
      _lastStreamFinished = streamCtrl.isFinished;
      if (modeChanged ||
          !identical(_document, latest) ||
          !identical(oldWidget.controller, widget.controller) ||
          oldWidget.showFrontmatter != widget.showFrontmatter) {
        _document = latest;
        widget.controller?.updateDocument(
          _document,
          showFrontmatter: widget.showFrontmatter,
        );
        if (modeChanged || latest.blocks.isEmpty) {
          _selectionDelegate?.clearSelectAllState();
        }
      }
    }
    _pushPayload();
  }

  @override
  void dispose() {
    _detachStreamListeners(widget);
    _detachControllers(widget);
    _disposeSlotNotifiers();
    _canvasNotifier?.dispose();
    _canvasNotifier = null;
    _payloadNotifier.dispose();
    _selectionDelegate?.dispose();
    _selectionDelegate = null;
    _ownedScrollController?.dispose();
    _ownedScrollController = null;
    _cachedRootContent = null;
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
    final bool finished = streamCtrl.isFinished;
    if (identical(latest, _document) && finished == _lastStreamFinished) {
      return;
    }

    final bool wasReset = latest.blocks.isEmpty && _document.blocks.isNotEmpty;

    _document = latest;
    _lastStreamFinished = finished;
    if (wasReset) {
      _selectionDelegate?.clearSelectAllState();
      _remoteImagesApprovedLocally = false;
    }
    widget.controller?.updateDocument(
      latest,
      showFrontmatter: widget.showFrontmatter,
    );

    if (!_hasMountedContent &&
        _hasVisibleBlocks(latest, widget.showFrontmatter)) {
      _hasMountedContent = true;
      setState(() {
        _cachedRootContent = null;
        _pushPayload();
      });
    } else {
      _pushPayload();
    }
  }

  void _approveRemoteImagesLocally() {
    if (!_remoteImagesApprovedLocally) {
      _remoteImagesApprovedLocally = true;
      _pushPayload();
    }
  }

  _MarkdownSelectionContainerDelegate _ensureSelectionDelegate() {
    final _MarkdownSelectionContainerDelegate delegate = _selectionDelegate ??=
        _MarkdownSelectionContainerDelegate();
    delegate.fullPlainTextProvider = _provideFullPlainText;
    return delegate;
  }

  Widget _buildScrollableShell() {
    return CustomScrollView(
      controller: _effectiveScrollController,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      // Keeps compatibility down to Flutter 3.32 before scrollCacheExtent.
      // ignore: deprecated_member_use
      cacheExtent: widget.cacheExtent,
      slivers: <Widget>[
        _SliverPayloadHost(payloadListenable: _payloadNotifier),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasVisible = _hasVisibleBlocks(
      _document,
      widget.showFrontmatter,
    );
    if (hasVisible) {
      _hasMountedContent = true;
    } else if (!_hasMountedContent || widget.streamingController == null) {
      _cachedRootContent = null;
      return const SizedBox.shrink();
    }

    final SelectionRegistrar? ancestorRegistrar = widget.selectable
        ? SelectionContainer.maybeOf(context)
        : null;
    final bool hadAncestorRegistrar = ancestorRegistrar != null;
    final bool hasMaterialLocalizations =
        widget.selectable && !hadAncestorRegistrar
        ? Localizations.of<MaterialLocalizations>(
                context,
                MaterialLocalizations,
              ) !=
              null
        : false;
    final bool hasSelectableRegionEnv =
        widget.selectable && !hadAncestorRegistrar && !hasMaterialLocalizations
        ? (MediaQuery.maybeOf(context) != null &&
              Overlay.maybeOf(context) != null)
        : false;

    final bool hasStreamingCtrl = widget.streamingController != null;
    final Widget? cached = _cachedRootContent;
    if (cached != null &&
        _cachedSelectable == widget.selectable &&
        identical(_cachedFocusNode, widget.focusNode) &&
        _cachedScrollable == widget.scrollable &&
        identical(_cachedScrollController, widget.scrollController) &&
        _cachedPhysics == widget.physics &&
        _cachedShrinkWrap == widget.shrinkWrap &&
        _cachedCacheExtent == widget.cacheExtent &&
        _cachedHadAncestorRegistrar == hadAncestorRegistrar &&
        _cachedHasMaterialLocalizations == hasMaterialLocalizations &&
        _cachedHasSelectableRegionEnv == hasSelectableRegionEnv &&
        _cachedHasStreamingController == hasStreamingCtrl) {
      return cached;
    }

    final Widget content;
    if (!widget.scrollable) {
      content = _NonScrollingPayloadHost(
        payloadListenable: _payloadNotifier,
        streamingNormalizedSourceProvider: _provideStreamingNormalizedSource,
      );
    } else {
      content = LayoutBuilder(
        builder: (BuildContext layoutContext, BoxConstraints constraints) {
          if (constraints.hasBoundedHeight || widget.shrinkWrap) {
            return _buildScrollableShell();
          }
          _hadNonScrollingFallback = true;
          return _NonScrollingPayloadHost(
            payloadListenable: _payloadNotifier,
            streamingNormalizedSourceProvider:
                _provideStreamingNormalizedSource,
          );
        },
      );
    }

    final Widget scopedContent = MarkdownStreamingHostScope(
      normalizedSourceProvider: _provideStreamingNormalizedSource,
      isStreamActiveProvider: _isStreamActive,
      slotListenableFor: hasStreamingCtrl ? _slotListenableFor : null,
      child: content,
    );

    final Widget built;
    if (!widget.selectable) {
      built = scopedContent;
    } else {
      final Widget selectableContent = SelectionContainer(
        delegate: _ensureSelectionDelegate(),
        child: scopedContent,
      );
      if (hadAncestorRegistrar) {
        built = selectableContent;
      } else if (hasMaterialLocalizations) {
        built = SelectionArea(
          focusNode: widget.focusNode,
          child: selectableContent,
        );
      } else if (hasSelectableRegionEnv) {
        built = SelectableRegion(
          focusNode: widget.focusNode,
          selectionControls: emptyTextSelectionControls,
          child: selectableContent,
        );
      } else {
        built = scopedContent;
      }
    }

    _cachedRootContent = built;
    _cachedSelectable = widget.selectable;
    _cachedFocusNode = widget.focusNode;
    _cachedScrollable = widget.scrollable;
    _cachedScrollController = widget.scrollController;
    _cachedPhysics = widget.physics;
    _cachedShrinkWrap = widget.shrinkWrap;
    _cachedCacheExtent = widget.cacheExtent;
    _cachedHadAncestorRegistrar = hadAncestorRegistrar;
    _cachedHasMaterialLocalizations = hasMaterialLocalizations;
    _cachedHasSelectableRegionEnv = hasSelectableRegionEnv;
    _cachedHasStreamingController = hasStreamingCtrl;
    return built;
  }
}

final class _MarkdownSelectionContainerDelegate
    extends StaticSelectionContainerDelegate {
  static const double _kVerticalThreshold = 3.0;

  bool _isSelectAllActive = false;
  final Set<Selectable> _selectAllDispatched = <Selectable>{};
  final Map<Selectable, Rect> _cachedOrderRects =
      Map<Selectable, Rect>.identity();
  String Function()? fullPlainTextProvider;

  Rect _screenRectFor(Selectable s) {
    final Rect? cached = _cachedOrderRects[s];
    if (cached != null) {
      return cached;
    }
    final List<Rect> boxes = s.boundingBoxes;
    if (boxes.isEmpty) {
      return _cachedOrderRects[s] = MatrixUtils.transformRect(
        s.getTransformTo(null),
        Rect.fromLTWH(0.0, 0.0, s.size.width, s.size.height),
      );
    }
    Rect local = boxes.first;
    for (int i = 1; i < boxes.length; i++) {
      local = local.expandToInclude(boxes[i]);
    }
    return _cachedOrderRects[s] = MatrixUtils.transformRect(
      s.getTransformTo(null),
      local,
    );
  }

  @override
  Comparator<Selectable> get compareOrder => _compareCachedOrder;

  int _compareCachedOrder(Selectable a, Selectable b) {
    final Rect rectA = _screenRectFor(a);
    final Rect rectB = _screenRectFor(b);
    if ((rectA.top - rectB.top < _kVerticalThreshold &&
            rectA.bottom - rectB.bottom > -_kVerticalThreshold) ||
        (rectB.top - rectA.top < _kVerticalThreshold &&
            rectB.bottom - rectA.bottom > -_kVerticalThreshold)) {
      if (rectA.left - rectB.left < precisionErrorTolerance &&
          rectA.right - rectB.right > -precisionErrorTolerance) {
        return -1;
      }
      if (rectB.left - rectA.left < precisionErrorTolerance &&
          rectB.right - rectA.right > -precisionErrorTolerance) {
        return 1;
      }
      if ((rectA.left - rectB.left).abs() > precisionErrorTolerance) {
        return rectA.left > rectB.left ? 1 : -1;
      }
      return rectA.right > rectB.right ? 1 : -1;
    }
    if ((rectA.top - rectB.top).abs() > _kVerticalThreshold) {
      return rectA.top > rectB.top ? 1 : -1;
    }
    return rectA.bottom > rectB.bottom ? 1 : -1;
  }

  void clearSelectAllState() {
    _isSelectAllActive = false;
    _selectAllDispatched.clear();
  }

  @override
  void remove(Selectable selectable) {
    _selectAllDispatched.remove(selectable);
    _cachedOrderRects.remove(selectable);
    super.remove(selectable);
  }

  @override
  void didChangeSelectables() {
    _cachedOrderRects.clear();
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
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    _cachedOrderRects.clear();
    try {
      return super.dispatchSelectionEvent(event);
    } finally {
      _cachedOrderRects.clear();
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
    _cachedOrderRects.clear();
    super.dispose();
  }
}

final class _SliverPayloadHost extends StatefulWidget {
  const _SliverPayloadHost({required this.payloadListenable});

  final ValueListenable<_MarkdownViewPayload> payloadListenable;

  @override
  State<_SliverPayloadHost> createState() => _SliverPayloadHostState();
}

final class _SliverPayloadHostState extends State<_SliverPayloadHost> {
  late MarkdownThemeData _ambientTheme;
  late MarkdownRenderEnvironment _environment;

  @override
  void initState() {
    super.initState();
    widget.payloadListenable.addListener(_onPayloadChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambientTheme = MarkdownTheme.of(context);
    _environment = MarkdownRenderEnvironment.resolve(context);
  }

  @override
  void didUpdateWidget(_SliverPayloadHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.payloadListenable, widget.payloadListenable)) {
      oldWidget.payloadListenable.removeListener(_onPayloadChanged);
      widget.payloadListenable.addListener(_onPayloadChanged);
    }
  }

  @override
  void dispose() {
    widget.payloadListenable.removeListener(_onPayloadChanged);
    super.dispose();
  }

  void _onPayloadChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final _MarkdownViewPayload p = widget.payloadListenable.value;
    if (p.useStreamingCanvas && p.canvasListenable != null) {
      return MarkdownStreamingSliverAdapter(
        key: const ValueKey<String>('markdown-streaming-canvas-sliver'),
        child: MarkdownStreamingCanvasLeaf(
          listenable: p.canvasListenable!,
          ambientTheme: _ambientTheme,
          environment: _environment,
        ),
      );
    }
    return SliverMarkdownDocument(
      key: const ValueKey<String>('markdown-settled-sliver'),
      document: p.document,
      theme: p.theme,
      delegates: p.delegates,
      controller: p.controller,
      showFrontmatter: p.showFrontmatter,
      padding: p.padding == EdgeInsets.zero ? null : p.padding,
      addAutomaticKeepAlives: p.addAutomaticKeepAlives,
      addRepaintBoundaries: p.addRepaintBoundaries,
      remoteImagesApproved: p.remoteImagesApproved,
      onRequestLoadRemoteImages: p.onRequestLoadRemoteImages,
    );
  }
}

final class _NonScrollingPayloadHost extends StatefulWidget {
  const _NonScrollingPayloadHost({
    required this.payloadListenable,
    required this.streamingNormalizedSourceProvider,
  });

  final ValueListenable<_MarkdownViewPayload> payloadListenable;
  final String? Function() streamingNormalizedSourceProvider;

  @override
  State<_NonScrollingPayloadHost> createState() =>
      _NonScrollingPayloadHostState();
}

final class _NonScrollingPayloadHostState
    extends State<_NonScrollingPayloadHost> {
  late MarkdownThemeData _ambientTheme;
  late MarkdownRenderEnvironment _environment;

  @override
  void initState() {
    super.initState();
    widget.payloadListenable.addListener(_onPayloadChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambientTheme = MarkdownTheme.of(context);
    _environment = MarkdownRenderEnvironment.resolve(context);
  }

  @override
  void didUpdateWidget(_NonScrollingPayloadHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.payloadListenable, widget.payloadListenable)) {
      oldWidget.payloadListenable.removeListener(_onPayloadChanged);
      widget.payloadListenable.addListener(_onPayloadChanged);
    }
  }

  @override
  void dispose() {
    widget.payloadListenable.removeListener(_onPayloadChanged);
    super.dispose();
  }

  void _onPayloadChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final _MarkdownViewPayload p = widget.payloadListenable.value;
    if (p.useStreamingCanvas && p.canvasListenable != null) {
      return MarkdownStreamingCanvasLeaf(
        listenable: p.canvasListenable!,
        ambientTheme: _ambientTheme,
        environment: _environment,
      );
    }
    final MarkdownThemeData resolvedTheme = p.theme ?? _ambientTheme;
    final MarkdownRenderEnvironment env = _environment;
    final List<MarkdownBlockNode> visibleBlocks =
        SliverMarkdownDocument.visibleBlocksFor(
          p.document,
          showFrontmatter: p.showFrontmatter,
        );
    if (visibleBlocks.isEmpty) {
      return const SizedBox.shrink();
    }
    final MarkdownUrlPolicy resolvedPolicy = p.delegates.resolveUrlPolicy(
      p.document.options.urlPolicy,
    );
    final MarkdownBlockRenderContext renderContext = MarkdownBlockRenderContext(
      theme: resolvedTheme,
      delegates: p.delegates,
      urlPolicy: resolvedPolicy,
      controller: p.controller,
      remoteImagesApproved: p.remoteImagesApproved,
      onRequestLoadRemoteImages: p.onRequestLoadRemoteImages,
      streamingNormalizedSourceProvider: p.isStreamActive
          ? widget.streamingNormalizedSourceProvider
          : null,
      environment: env,
      resolvedBodyStyle: env.resolveTextStyle(resolvedTheme.bodyTextStyle()),
    );

    final Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < visibleBlocks.length; i++)
          buildTopLevelMarkdownBlockWidget(
            context,
            key: ValueKey<String>(visibleBlocks[i].blockId),
            node: visibleBlocks[i],
            renderContext: renderContext,
            bottomSpacing: i == visibleBlocks.length - 1
                ? 0.0
                : resolvedTheme.blockSpacing,
          ),
      ],
    );

    if (p.padding == EdgeInsets.zero) {
      return column;
    }
    return Padding(padding: p.padding, child: column);
  }
}
