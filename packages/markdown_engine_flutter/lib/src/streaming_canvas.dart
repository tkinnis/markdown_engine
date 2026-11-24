import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Picture, PictureRecorder, TextBox;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        MouseCursor,
        MouseTrackerAnnotation,
        PointerEnterEventListener,
        PointerExitEventListener;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart';

import 'delegates.dart';
import 'fast_text.dart';
import 'inline_renderer.dart';
import 'theme.dart';

/// Immutable snapshot delivered to [MarkdownStreamingCanvasLeaf] during
/// high-frequency plain/formatted streaming sessions.
@immutable
final class MarkdownStreamingCanvasPayload {
  /// Creates a [MarkdownStreamingCanvasPayload].
  const MarkdownStreamingCanvasPayload({
    required this.document,
    required this.themeOverride,
    required this.padding,
    required this.showFrontmatter,
    required this.revision,
  });

  /// Latest parsed Markdown document.
  final MarkdownDocument document;

  /// Optional theme override passed on `MarkdownView`.
  final MarkdownThemeData? themeOverride;

  /// Outer viewport padding around the streamed blocks.
  final EdgeInsetsGeometry padding;

  /// Whether leading frontmatter nodes should be displayed (always `false` in
  /// canvas mode since visible frontmatter cards use widget layout).
  final bool showFrontmatter;

  /// Monotonic payload revision for fast equality short-circuiting.
  final int revision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownStreamingCanvasPayload && revision == other.revision;

  @override
  int get hashCode => revision.hashCode;
}

/// Returns `true` when [delegates] defines no custom block or inline widget
/// builders that bypass direct canvas painting.
bool canUseStreamingCanvasDelegates(MarkdownBuilderDelegates delegates) =>
    delegates.diagramBuilder == null &&
    delegates.codeBlockBuilder == null &&
    delegates.mathBlockBuilder == null &&
    delegates.mathInlineBuilder == null &&
    delegates.imageBuilder == null;

/// Returns `true` when [block] and all of its descendants can be rendered
/// directly on [RenderMarkdownStreamingCanvas] with exact visual fidelity.
bool isCanvasSupportedBlock(
  MarkdownBlockNode block,
  MarkdownBuilderDelegates delegates, {
  bool showFrontmatter = true,
}) {
  switch (block) {
    case FrontmatterNode():
      return !showFrontmatter;
    case HeadingNode():
      return canBuildFastSimpleInlines(block.children);
    case ParagraphNode():
      return canBuildFastSimpleInlines(block.children);
    case ThematicBreakNode():
      return true;
    case BlockQuoteNode():
      for (int i = 0; i < block.children.length; i++) {
        if (!isCanvasSupportedBlock(
          block.children[i],
          delegates,
          showFrontmatter: showFrontmatter,
        )) {
          return false;
        }
      }
      return true;
    case ListNode():
      for (int i = 0; i < block.items.length; i++) {
        if (!isCanvasSupportedBlock(
          block.items[i],
          delegates,
          showFrontmatter: showFrontmatter,
        )) {
          return false;
        }
      }
      return true;
    case ListItemNode():
      for (int i = 0; i < block.children.length; i++) {
        if (!isCanvasSupportedBlock(
          block.children[i],
          delegates,
          showFrontmatter: showFrontmatter,
        )) {
          return false;
        }
      }
      return true;
    case CodeBlockNode():
      if (delegates.enableBuiltInMermaid &&
          block.language?.toLowerCase() == 'mermaid') {
        return false;
      }
      return true;
    case TableNode():
      for (int i = 0; i < block.headers.length; i++) {
        if (!canBuildFastSimpleInlines(block.headers[i].children)) {
          return false;
        }
      }
      for (int r = 0; r < block.rows.length; r++) {
        final List<TableCellNode> row = block.rows[r];
        for (int c = 0; c < row.length; c++) {
          if (!canBuildFastSimpleInlines(row[c].children)) {
            return false;
          }
        }
      }
      return true;
    case AlertNode():
    case HtmlBlockNode():
    case DetailsBlockNode():
    case AlignedBlockNode():
    case FigureBlockNode():
    case MathBlockNode():
    case DefinitionListNode():
    case FootnoteDefinitionNode():
    case FootnoteSectionNode():
      return false;
  }
}

/// Direct leaf widget rendering streamed Markdown blocks on
/// [RenderMarkdownStreamingCanvas] without an intermediate [StatefulWidget]
/// shell.
final class MarkdownStreamingCanvasLeaf extends LeafRenderObjectWidget {
  /// Creates a [MarkdownStreamingCanvasLeaf].
  const MarkdownStreamingCanvasLeaf({
    super.key,
    required this.listenable,
    required this.ambientTheme,
    required this.environment,
  });

  /// Streaming payload listenable driving direct `RenderBox` relayout.
  final ValueListenable<MarkdownStreamingCanvasPayload> listenable;

  /// Ambient theme resolved from enclosing `MarkdownTheme`.
  final MarkdownThemeData ambientTheme;

  /// Ambient text/selection/directionality environment.
  final MarkdownRenderEnvironment environment;

  @override
  RenderMarkdownStreamingCanvas createRenderObject(BuildContext context) {
    return RenderMarkdownStreamingCanvas(listenable, ambientTheme, environment);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMarkdownStreamingCanvas renderObject,
  ) {
    renderObject.updateConfig(
      listenable: listenable,
      ambientTheme: ambientTheme,
      environment: environment,
    );
  }
}

/// Sliver adapter forwarding exact [SliverConstraints.scrollOffset] and
/// [SliverConstraints.remainingPaintExtent] to [RenderMarkdownStreamingCanvas]
/// so off-screen blocks are skipped during `paint()`.
final class MarkdownStreamingSliverAdapter
    extends SingleChildRenderObjectWidget {
  /// Creates a [MarkdownStreamingSliverAdapter].
  const MarkdownStreamingSliverAdapter({super.key, super.child});

  @override
  RenderSliverSingleBoxAdapter createRenderObject(BuildContext context) =>
      _RenderMarkdownStreamingSliver();
}

final class _RenderMarkdownStreamingSliver
    extends RenderSliverSingleBoxAdapter {
  @override
  void performLayout() {
    final RenderBox? c = child;
    if (c == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    final SliverConstraints slConstraints = constraints;
    c.layout(slConstraints.asBoxConstraints(), parentUsesSize: true);
    final double childExtent = switch (slConstraints.axis) {
      Axis.horizontal => c.size.width,
      Axis.vertical => c.size.height,
    };
    final double paintedChildSize = calculatePaintOffset(
      slConstraints,
      from: 0.0,
      to: childExtent,
    );
    final double cacheExtent = calculateCacheOffset(
      slConstraints,
      from: 0.0,
      to: childExtent,
    );
    geometry = SliverGeometry(
      scrollExtent: childExtent,
      paintExtent: paintedChildSize,
      cacheExtent: cacheExtent,
      maxPaintExtent: childExtent,
      hitTestExtent: paintedChildSize,
      hasVisualOverflow:
          childExtent > slConstraints.remainingPaintExtent ||
          slConstraints.scrollOffset > 0.0,
    );
    setChildParentData(c, slConstraints, geometry!);
    if (c is RenderMarkdownStreamingCanvas) {
      c.updateViewportClipBand(
        slConstraints.scrollOffset,
        slConstraints.scrollOffset + slConstraints.remainingPaintExtent,
      );
    }
  }
}

final class _CanvasTextRun {
  const _CanvasTextRun({
    required this.painter,
    required this.dx,
    required this.dy,
    required this.plainText,
  });

  final TextPainter painter;
  final double dx;
  final double dy;
  final String plainText;

  double get width => painter.width;
  double get height => painter.height;
}

final class _CopyButtonTarget {
  const _CopyButtonTarget({
    required this.rect,
    required this.codeText,
    required this.blockId,
  });

  final Rect rect;
  final String codeText;
  final String blockId;
}

sealed class _CanvasNodeLayout {
  const _CanvasNodeLayout({required this.height, required this.textRuns});

  final double height;
  final List<_CanvasTextRun> textRuns;
}

final class _CanvasHeadingLayout extends _CanvasNodeLayout {
  const _CanvasHeadingLayout({
    required super.height,
    required super.textRuns,
    required this.painter,
    required this.topPad,
    required this.dividerY,
  });

  final TextPainter painter;
  final double topPad;
  final double? dividerY;
}

final class _CanvasParagraphLayout extends _CanvasNodeLayout {
  const _CanvasParagraphLayout({
    required super.height,
    required super.textRuns,
    required this.painter,
  });

  final TextPainter painter;
}

final class _CanvasThematicBreakLayout extends _CanvasNodeLayout {
  const _CanvasThematicBreakLayout()
    : super(height: 17.0, textRuns: const <_CanvasTextRun>[]);
}

final class _CanvasBlockQuoteLayout extends _CanvasNodeLayout {
  const _CanvasBlockQuoteLayout({
    required super.height,
    required super.textRuns,
    required this.width,
    required this.childOffsetsY,
    required this.children,
    required this.backgroundColor,
    required this.borderColor,
  });

  final double width;
  final List<double> childOffsetsY;
  final List<_CanvasNodeLayout> children;
  final Color backgroundColor;
  final Color borderColor;
}

final class _CanvasListItemLayout {
  const _CanvasListItemLayout({
    required this.offsetY,
    required this.height,
    required this.isTaskItem,
    required this.taskChecked,
    required this.checkboxSize,
    required this.checkboxTop,
    required this.bulletDepth,
    required this.bulletCenterY,
    required this.markerPainter,
    required this.markerDx,
    required this.contentDx,
    required this.childOffsetsY,
    required this.children,
  });

  final double offsetY;
  final double height;
  final bool isTaskItem;
  final bool taskChecked;
  final double checkboxSize;
  final double checkboxTop;
  final int? bulletDepth;
  final double bulletCenterY;
  final TextPainter? markerPainter;
  final double markerDx;
  final double contentDx;
  final List<double> childOffsetsY;
  final List<_CanvasNodeLayout> children;
}

final class _CanvasListLayout extends _CanvasNodeLayout {
  const _CanvasListLayout({
    required super.height,
    required super.textRuns,
    required this.items,
  });

  final List<_CanvasListItemLayout> items;
}

final class _CanvasCodeBlockLayout extends _CanvasNodeLayout {
  const _CanvasCodeBlockLayout({
    required super.height,
    required super.textRuns,
    required this.blockId,
    required this.width,
    required this.headerHeight,
    required this.badgeText,
    required this.badgePainter,
    required this.badgePillRect,
    required this.copyPainter,
    required this.copiedPainter,
    required this.copyRect,
    required this.codePainter,
    required this.codeText,
    required this.codeTop,
    required this.clipCode,
  });

  final String blockId;
  final double width;
  final double headerHeight;
  final String badgeText;
  final TextPainter badgePainter;
  final RRect badgePillRect;
  final TextPainter copyPainter;
  final TextPainter copiedPainter;
  final Rect copyRect;
  final TextPainter codePainter;
  final String codeText;
  final double codeTop;
  final bool clipCode;
}

final class _CanvasTableCellLayout {
  const _CanvasTableCellLayout({
    required this.painter,
    required this.dx,
    required this.dy,
  });

  final TextPainter painter;
  final double dx;
  final double dy;
}

final class _CanvasTableRowLayout {
  const _CanvasTableRowLayout({
    required this.top,
    required this.height,
    required this.isHeader,
    required this.isOddData,
    required this.cells,
  });

  final double top;
  final double height;
  final bool isHeader;
  final bool isOddData;
  final List<_CanvasTableCellLayout> cells;
}

final class _TableCellCache {
  const _TableCellCache({
    required this.node,
    required this.alignment,
    required this.painter,
    required this.intrinsicW,
    required this.plainText,
    required this.narrowWrapped,
  });

  final TableCellNode node;
  final TableAlignment alignment;
  final TextPainter painter;
  final double intrinsicW;
  final String plainText;
  final bool narrowWrapped;
}

final class _CanvasTableLayout extends _CanvasNodeLayout {
  const _CanvasTableLayout({
    required super.height,
    required super.textRuns,
    required this.totalWidth,
    required this.maxAvailableWidth,
    required this.colWidths,
    required this.rows,
    required this.cellCaches,
  });

  final double totalWidth;
  final double maxAvailableWidth;
  final List<double> colWidths;
  final List<_CanvasTableRowLayout> rows;
  final List<List<_TableCellCache>> cellCaches;
}

final class _CanvasTopBlockEntry {
  _CanvasTopBlockEntry({
    required this.block,
    required this.top,
    required this.layout,
    required this.cumulativeEndChars,
  }) : runCount = layout.textRuns.length,
       charCount = _sumRunChars(layout.textRuns);

  static int _sumRunChars(List<_CanvasTextRun> runs) {
    int total = 0;
    for (int i = 0; i < runs.length; i++) {
      if (i > 0) {
        total++;
      }
      total += runs[i].plainText.length;
    }
    return total;
  }

  static int nextCumulativeChars(int prevTotal, int runCount, int charCount) {
    if (runCount == 0) {
      return prevTotal;
    }
    return prevTotal > 0 ? prevTotal + 1 + charCount : charCount;
  }

  MarkdownBlockNode block;
  double top;
  _CanvasNodeLayout layout;
  int runCount;
  int charCount;
  int cumulativeEndChars;
}

final class _SelectableSlice {
  const _SelectableSlice({
    required this.painter,
    required this.offset,
    required this.plainText,
    required this.startOffset,
    required this.endOffset,
    required this.top,
    required this.bottom,
  });

  final TextPainter painter;
  final Offset offset;
  final String plainText;
  final int startOffset;
  final int endOffset;
  final double top;
  final double bottom;
}

/// High-speed leaf [RenderBox] painting plain and formatted Markdown streaming
/// documents directly from cached [TextPainter] block layouts with single
/// [Selectable] integration and zero widget-tree churn per chunk.
final class RenderMarkdownStreamingCanvas extends RenderBox
    implements MouseTrackerAnnotation {
  /// Creates a [RenderMarkdownStreamingCanvas].
  RenderMarkdownStreamingCanvas(
    this._listenable,
    this._ambientTheme,
    this._environment,
  ) {
    _registrar = _environment.selectionRegistrar;
    if (_registrar != null) {
      _selectable = _StreamingCanvasSelectable(this);
    }
  }

  ValueListenable<MarkdownStreamingCanvasPayload> _listenable;
  MarkdownThemeData _ambientTheme;
  MarkdownRenderEnvironment _environment;
  SelectionRegistrar? _registrar;
  _StreamingCanvasSelectable? _selectable;

  final List<_CanvasTopBlockEntry> _entries = <_CanvasTopBlockEntry>[];
  final Map<String, _CanvasTopBlockEntry> _entriesById =
      <String, _CanvasTopBlockEntry>{};
  final List<_SelectableSlice> _slices = <_SelectableSlice>[];
  final List<_CopyButtonTarget> _copyTargets = <_CopyButtonTarget>[];
  final Set<String> _copiedBlockIds = <String>{};
  final Map<String, Timer> _copyTimers = <String, Timer>{};

  bool _slicesDirty = true;
  bool _copyTargetsDirty = true;
  int _totalSelectableLength = 0;
  String? _cachedPlainText;
  String? _activeCopyPointerBlockId;

  double? _laidOutContentWidth;
  EdgeInsets? _laidOutPadding;
  MarkdownThemeData? _laidOutTheme;
  MarkdownRenderEnvironment? _laidOutEnv;
  _ResolvedCanvasStyles? _styles;
  double _totalHeight = 0.0;
  bool _hasViewportBand = false;
  double _viewportClipTop = 0.0;
  double _viewportClipBottom = double.infinity;
  ui.Picture? _viewportPic;
  double _viewportPicClipTop = double.nan;
  double _viewportPicClipBottom = double.nan;
  double _viewportPicMaxBottom = -1.0;
  double _viewportPicPadLeft = double.nan;
  int _stablePaintHits = 0;
  bool _pendingPaintAfterDrySync = false;

  void _invalidateViewportPicture() {
    _viewportPic?.dispose();
    _viewportPic = null;
    _viewportPicMaxBottom = -1.0;
    _stablePaintHits = 0;
  }

  /// Updates exact visible vertical band from enclosing sliver constraints so
  /// off-screen blocks are culled cleanly during `paint()`.
  void updateViewportClipBand(double top, double bottom) {
    _hasViewportBand = true;
    _viewportClipTop = top;
    _viewportClipBottom = bottom;
  }

  MarkdownThemeData get _effectiveTheme =>
      _listenable.value.themeOverride ?? _ambientTheme;

  TextDirection get _textDirection => _environment.textDirection;

  Color get _effectiveSelectionColor =>
      _environment.selectionColor ?? const Color(0x6633B5E5);

  /// Updates constructor-delivered dependencies from `_MarkdownStreamingCanvasLeaf`.
  void updateConfig({
    required ValueListenable<MarkdownStreamingCanvasPayload> listenable,
    required MarkdownThemeData ambientTheme,
    required MarkdownRenderEnvironment environment,
  }) {
    final bool listenableChanged = !identical(_listenable, listenable);
    final bool themeChanged = _ambientTheme != ambientTheme;
    final bool envChanged = _environment != environment;
    final bool registrarChanged = !identical(
      _registrar,
      environment.selectionRegistrar,
    );

    if (listenableChanged) {
      if (attached) {
        _listenable.removeListener(_onPayloadChanged);
      }
      _listenable = listenable;
      if (attached) {
        _listenable.addListener(_onPayloadChanged);
      }
    }

    _ambientTheme = ambientTheme;
    _environment = environment;

    if (registrarChanged) {
      _registrar = environment.selectionRegistrar;
      if (_registrar == null) {
        _selectable?.registrar = null;
        _selectable?.dispose();
        _selectable = null;
        markNeedsCompositingBitsUpdate();
      } else {
        final _StreamingCanvasSelectable selectable = _selectable ??=
            _StreamingCanvasSelectable(this);
        if (attached) {
          selectable.registrar = _registrar;
        }
      }
    }

    if (listenableChanged || themeChanged || envChanged) {
      markNeedsLayout();
    }
  }

  void _onPayloadChanged() {
    if (attached) {
      markNeedsLayout();
    }
  }

  @override
  MouseCursor get cursor =>
      _registrar != null ? SystemMouseCursors.text : MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  @override
  bool get validForMouseTracker => attached;

  @override
  bool get alwaysNeedsCompositing => _selectable?.hasHandleLayers ?? false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable.addListener(_onPayloadChanged);
    PaintingBinding.instance.systemFonts.addListener(_handleSystemFontsChange);
    if (_registrar != null) {
      (_selectable ??= _StreamingCanvasSelectable(this)).registrar = _registrar;
    }
  }

  @override
  void detach() {
    _listenable.removeListener(_onPayloadChanged);
    PaintingBinding.instance.systemFonts.removeListener(
      _handleSystemFontsChange,
    );
    _selectable?.registrar = null;
    _selectable?.clearHandleLayers();
    super.detach();
  }

  @override
  void dispose() {
    _invalidateViewportPicture();
    for (final Timer timer in _copyTimers.values) {
      timer.cancel();
    }
    _copyTimers.clear();
    _copiedBlockIds.clear();
    _selectable?.dispose();
    _selectable = null;
    _entries.clear();
    _entriesById.clear();
    _slices.clear();
    _copyTargets.clear();
    super.dispose();
  }

  void _handleSystemFontsChange() {
    _laidOutTheme = null;
    markNeedsLayout();
  }

  void _ensureLayoutSynced(double maxWidth) {
    final MarkdownStreamingCanvasPayload payload = _listenable.value;
    final MarkdownThemeData theme = payload.themeOverride ?? _ambientTheme;
    final MarkdownRenderEnvironment env = _environment;
    final EdgeInsets pad = payload.padding.resolve(env.textDirection);
    final double availWidth = maxWidth.isFinite ? maxWidth : 800.0;
    final double contentWidth = math.max(0.0, availWidth - pad.horizontal);
    final List<MarkdownBlockNode> rawBlocks = payload.document.blocks;

    final bool configInvalid =
        _laidOutContentWidth != contentWidth ||
        _laidOutPadding != pad ||
        _laidOutTheme != theme ||
        _laidOutEnv != env;

    if (configInvalid || _styles == null) {
      _styles = _ResolvedCanvasStyles(theme: theme, env: env);
    }

    _laidOutContentWidth = contentWidth;
    _laidOutPadding = pad;
    _laidOutTheme = theme;
    _laidOutEnv = env;

    if (rawBlocks.isEmpty) {
      final bool hadContent =
          _entries.isNotEmpty || _totalSelectableLength != 0;
      _entries.clear();
      _entriesById.clear();
      _invalidateViewportPicture();
      _totalHeight = pad.vertical;
      _totalSelectableLength = 0;
      _slices.clear();
      _copyTargets.clear();
      _slicesDirty = false;
      _copyTargetsDirty = false;
      _cachedPlainText = '';
      if (hadContent) {
        _selectable?.didUpdateContent();
        _pendingPaintAfterDrySync = true;
      }
      return;
    }

    if (configInvalid) {
      _entries.clear();
      _entriesById.clear();
      _invalidateViewportPicture();
    }

    final int count = rawBlocks.length;
    int firstDirty = 0;
    int firstDirtyRawIdx = 0;
    if (!configInvalid) {
      int visibleIdx = 0;
      for (int i = 0; i < count; i++) {
        final MarkdownBlockNode b = rawBlocks[i];
        if (!payload.showFrontmatter && b is FrontmatterNode) {
          firstDirtyRawIdx = i + 1;
          continue;
        }
        if (visibleIdx < _entries.length &&
            identical(_entries[visibleIdx].block, b)) {
          visibleIdx++;
          firstDirtyRawIdx = i + 1;
          continue;
        }
        break;
      }
      firstDirty = visibleIdx;
    }

    if (!configInvalid &&
        firstDirtyRawIdx == count &&
        firstDirty == _entries.length) {
      return;
    }

    final double blockSpacing = theme.blockSpacing;
    final int prevEntriesLen = _entries.length;
    double y = firstDirty == 0
        ? pad.top
        : _entries[firstDirty - 1].top +
              _entries[firstDirty - 1].layout.height +
              blockSpacing;
    int totalLen = firstDirty == 0
        ? 0
        : _entries[firstDirty - 1].cumulativeEndChars;

    final _ResolvedCanvasStyles styles = _styles!;
    bool anyVisualChange = configInvalid;
    double dirtyMinTop = configInvalid ? 0.0 : double.infinity;

    int visibleIdx = firstDirty;
    for (int i = firstDirtyRawIdx; i < count; i++) {
      final MarkdownBlockNode b = rawBlocks[i];
      if (!payload.showFrontmatter && b is FrontmatterNode) {
        continue;
      }
      final _CanvasTopBlockEntry? oldSlot = visibleIdx < prevEntriesLen
          ? _entries[visibleIdx]
          : null;
      final _CanvasTopBlockEntry? prev = _entriesById[b.blockId];
      final _CanvasNodeLayout layout;
      if (!configInvalid &&
          prev != null &&
          (identical(prev.block, b) ||
              (prev.block.span.length == b.span.length &&
                  _sameCanvasBlock(prev.block, b)))) {
        layout = prev.layout;
      } else {
        layout = styles.layoutBlock(
          b,
          contentWidth,
          listDepth: 0,
          previousNode: configInvalid ? null : prev?.block,
          previousLayout: configInvalid ? null : prev?.layout,
        );
      }

      if (oldSlot != null &&
          identical(layout, oldSlot.layout) &&
          oldSlot.top == y &&
          oldSlot.block.blockId == b.blockId) {
        oldSlot.block = b;
        totalLen = oldSlot.cumulativeEndChars;
        _entriesById[b.blockId] = oldSlot;
      } else {
        anyVisualChange = true;
        if (y < dirtyMinTop) {
          dirtyMinTop = y;
        }
        final int runCount = layout.textRuns.length;
        final int charCount = _CanvasTopBlockEntry._sumRunChars(
          layout.textRuns,
        );
        totalLen = _CanvasTopBlockEntry.nextCumulativeChars(
          totalLen,
          runCount,
          charCount,
        );
        if (oldSlot != null) {
          oldSlot
            ..block = b
            ..top = y
            ..layout = layout
            ..runCount = runCount
            ..charCount = charCount
            ..cumulativeEndChars = totalLen;
          _entriesById[b.blockId] = oldSlot;
        } else {
          final _CanvasTopBlockEntry entry = _CanvasTopBlockEntry(
            block: b,
            top: y,
            layout: layout,
            cumulativeEndChars: totalLen,
          );
          _entries.add(entry);
          _entriesById[b.blockId] = entry;
        }
      }
      y += layout.height + blockSpacing;
      visibleIdx++;
    }

    if (visibleIdx < _entries.length) {
      anyVisualChange = true;
      final double removedTop = _entries[visibleIdx].top;
      if (removedTop < dirtyMinTop) {
        dirtyMinTop = removedTop;
      }
      _entries.length = visibleIdx;
    }

    if (_entries.length < prevEntriesLen ||
        _entriesById.length > _entries.length + 16) {
      _entriesById.clear();
      for (int i = 0; i < _entries.length; i++) {
        final _CanvasTopBlockEntry entry = _entries[i];
        _entriesById[entry.block.blockId] = entry;
      }
    }

    if (_entries.isEmpty) {
      _totalHeight = pad.vertical;
      _totalSelectableLength = 0;
    } else {
      final _CanvasTopBlockEntry last = _entries.last;
      _totalHeight = last.top + last.layout.height + pad.bottom;
      _totalSelectableLength = totalLen;
    }

    if (anyVisualChange) {
      _slicesDirty = true;
      _copyTargetsDirty = true;
      _cachedPlainText = null;
      if (_viewportPic != null && dirtyMinTop <= _viewportPicMaxBottom) {
        _invalidateViewportPicture();
      }
      _selectable?.didUpdateContent();
      _pendingPaintAfterDrySync = true;
    }
  }

  void _ensureSlices() {
    if (!_slicesDirty) {
      return;
    }
    _slicesDirty = false;
    _slices.clear();
    final EdgeInsets pad =
        _laidOutPadding ?? _listenable.value.padding.resolve(_textDirection);
    final double baseX = pad.left;
    int offset = 0;
    for (int i = 0; i < _entries.length; i++) {
      final _CanvasTopBlockEntry entry = _entries[i];
      final List<_CanvasTextRun> runs = entry.layout.textRuns;
      for (int r = 0; r < runs.length; r++) {
        final _CanvasTextRun run = runs[r];
        if (offset > 0) {
          offset++;
        }
        final int len = run.plainText.length;
        final double runTop = entry.top + run.dy;
        _slices.add(
          _SelectableSlice(
            painter: run.painter,
            offset: Offset(baseX + run.dx, runTop),
            plainText: run.plainText,
            startOffset: offset,
            endOffset: offset + len,
            top: runTop,
            bottom: runTop + run.height,
          ),
        );
        offset += len;
      }
    }
    _totalSelectableLength = offset;
  }

  void _ensureCopyTargets() {
    if (!_copyTargetsDirty) {
      return;
    }
    _copyTargetsDirty = false;
    _copyTargets.clear();
    final EdgeInsets pad =
        _laidOutPadding ?? _listenable.value.padding.resolve(_textDirection);
    final double baseX = pad.left;
    for (int i = 0; i < _entries.length; i++) {
      final _CanvasTopBlockEntry entry = _entries[i];
      final _CanvasNodeLayout layout = entry.layout;
      if (layout is _CanvasCodeBlockLayout) {
        _copyTargets.add(
          _CopyButtonTarget(
            rect: layout.copyRect.shift(Offset(baseX, entry.top)),
            codeText: layout.codeText,
            blockId: layout.blockId,
          ),
        );
      } else {
        _collectCopyTargetsRecursive(layout, baseX, entry.top);
      }
    }
  }

  void _collectCopyTargetsRecursive(
    _CanvasNodeLayout layout,
    double dx,
    double dy,
  ) {
    if (layout is _CanvasCodeBlockLayout) {
      _copyTargets.add(
        _CopyButtonTarget(
          rect: layout.copyRect.shift(Offset(dx, dy)),
          codeText: layout.codeText,
          blockId: layout.blockId,
        ),
      );
      return;
    }
    if (layout is _CanvasBlockQuoteLayout) {
      for (int i = 0; i < layout.children.length; i++) {
        _collectCopyTargetsRecursive(
          layout.children[i],
          dx + 18.0,
          dy + layout.childOffsetsY[i],
        );
      }
      return;
    }
    if (layout is _CanvasListLayout) {
      for (int i = 0; i < layout.items.length; i++) {
        final _CanvasListItemLayout item = layout.items[i];
        for (int j = 0; j < item.children.length; j++) {
          _collectCopyTargetsRecursive(
            item.children[j],
            dx + item.contentDx,
            dy + item.offsetY + item.childOffsetsY[j],
          );
        }
      }
    }
  }

  String _getPlainText() {
    final String? cached = _cachedPlainText;
    if (cached != null) {
      return cached;
    }
    _ensureSlices();
    if (_slices.isEmpty) {
      return _cachedPlainText = '';
    }
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < _slices.length; i++) {
      if (i > 0) {
        sb.write('\n');
      }
      sb.write(_slices[i].plainText);
    }
    return _cachedPlainText = sb.toString();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    assert(debugHandleEvent(event, entry));
    if (event is PointerDownEvent) {
      _ensureCopyTargets();
      _activeCopyPointerBlockId = null;
      for (int i = 0; i < _copyTargets.length; i++) {
        if (_copyTargets[i].rect.inflate(4.0).contains(event.localPosition)) {
          _activeCopyPointerBlockId = _copyTargets[i].blockId;
          break;
        }
      }
    } else if (event is PointerUpEvent) {
      final String? pressedId = _activeCopyPointerBlockId;
      _activeCopyPointerBlockId = null;
      if (pressedId != null) {
        _ensureCopyTargets();
        for (int i = 0; i < _copyTargets.length; i++) {
          final _CopyButtonTarget target = _copyTargets[i];
          if (target.blockId == pressedId &&
              target.rect.inflate(4.0).contains(event.localPosition)) {
            _copyCode(target.blockId, target.codeText);
            break;
          }
        }
      }
    } else if (event is PointerCancelEvent) {
      _activeCopyPointerBlockId = null;
    }
  }

  void _copyCode(String blockId, String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    _copyTimers[blockId]?.cancel();
    _copiedBlockIds.add(blockId);
    _invalidateViewportPicture();
    _copyTimers[blockId] = Timer(const Duration(milliseconds: 1500), () {
      _copyTimers.remove(blockId);
      if (_copiedBlockIds.remove(blockId) && attached) {
        _invalidateViewportPicture();
        markNeedsPaint();
      }
    });
    markNeedsPaint();
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final double avail = hasSize && constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : 800.0;
    return math.min(avail, 200.0);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return hasSize && constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : 800.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _ensureLayoutSynced(width);
    return _totalHeight;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return computeMinIntrinsicHeight(width);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    _ensureLayoutSynced(constraints.maxWidth);
    final double w = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : (_laidOutContentWidth ?? 800.0) +
              (_laidOutPadding?.horizontal ?? 0.0);
    return constraints.constrain(Size(w, _totalHeight));
  }

  @override
  void performLayout() {
    _ensureLayoutSynced(constraints.maxWidth);
    final double w = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : (_laidOutContentWidth ?? 800.0) +
              (_laidOutPadding?.horizontal ?? 0.0);
    final Size prevSize = hasSize ? size : Size.zero;
    final Size nextSize = constraints.constrain(Size(w, _totalHeight));
    size = nextSize;
    if (_pendingPaintAfterDrySync) {
      _pendingPaintAfterDrySync = false;
      if (prevSize == nextSize) {
        markNeedsPaint();
      }
    }
    _selectable?.didChangeLayout();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_entries.isEmpty) {
      return;
    }
    config.isSemanticBoundary = true;
    config.textDirection = _textDirection;
    config.label = _getPlainText();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_entries.isEmpty) {
      _selectable?.pushLeaderLayers(context, offset);
      return;
    }

    final Canvas canvas = context.canvas;
    final EdgeInsets pad =
        _laidOutPadding ?? _listenable.value.padding.resolve(_textDirection);
    final _ResolvedCanvasStyles styles =
        _styles ??
        (_styles = _ResolvedCanvasStyles(
          theme: _effectiveTheme,
          env: _environment,
        ));
    final double leftX = offset.dx + pad.left;

    final double clipTop;
    final double clipBottom;
    if (_hasViewportBand) {
      clipTop = _viewportClipTop;
      clipBottom = _viewportClipBottom;
    } else {
      final Rect clipLocal = canvas.getLocalClipBounds();
      clipTop = clipLocal.top - offset.dy;
      clipBottom = clipLocal.bottom - offset.dy;
    }

    final bool hasSelection = _selectable?.hasSelection ?? false;
    final int? selStart = hasSelection
        ? math.min(_selectable!._start!, _selectable!._end!)
        : null;
    final int? selEnd = hasSelection
        ? math.max(_selectable!._start!, _selectable!._end!)
        : null;
    if (hasSelection) {
      _ensureSlices();
    }

    final bool canUsePictureCache =
        _hasViewportBand &&
        !hasSelection &&
        _copiedBlockIds.isEmpty &&
        clipBottom.isFinite &&
        _entries.last.top > clipBottom;

    if (canUsePictureCache) {
      final ui.Picture? cachedPic = _viewportPic;
      if (cachedPic != null &&
          _viewportPicClipTop == clipTop &&
          _viewportPicClipBottom == clipBottom &&
          _viewportPicPadLeft == pad.left) {
        _drawBoxLocalPicture(canvas, offset, cachedPic);
        _selectable?.pushLeaderLayers(context, offset);
        return;
      }
      _stablePaintHits++;
      if (_stablePaintHits >= 1) {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas picCanvas = Canvas(recorder);
        for (int i = 0; i < _entries.length; i++) {
          final _CanvasTopBlockEntry entry = _entries[i];
          final double top = entry.top;
          if (top > clipBottom) {
            break;
          }
          if (top + entry.layout.height < clipTop) {
            continue;
          }
          _paintLayout(picCanvas, entry.layout, Offset(pad.left, top), styles);
        }
        final ui.Picture pic = recorder.endRecording();
        _viewportPic?.dispose();
        _viewportPic = pic;
        _viewportPicClipTop = clipTop;
        _viewportPicClipBottom = clipBottom;
        _viewportPicMaxBottom = clipBottom;
        _viewportPicPadLeft = pad.left;
        _drawBoxLocalPicture(canvas, offset, pic);
        _selectable?.pushLeaderLayers(context, offset);
        return;
      }
    }

    for (int i = 0; i < _entries.length; i++) {
      final _CanvasTopBlockEntry entry = _entries[i];
      final double top = entry.top;
      final double bottom = top + entry.layout.height;
      if (bottom < clipTop) {
        continue;
      }
      if (top > clipBottom) {
        break;
      }
      _paintLayout(
        canvas,
        entry.layout,
        Offset(leftX, offset.dy + top),
        styles,
      );
    }

    if (hasSelection &&
        selStart != null &&
        selEnd != null &&
        selStart < selEnd) {
      final Paint selPaint = Paint()..color = _effectiveSelectionColor;
      for (int i = 0; i < _slices.length; i++) {
        final _SelectableSlice slice = _slices[i];
        if (slice.endOffset <= selStart || slice.startOffset >= selEnd) {
          continue;
        }
        if (slice.bottom < clipTop) {
          continue;
        }
        if (slice.top > clipBottom) {
          break;
        }
        final int localStart = math.max(0, selStart - slice.startOffset);
        final int localEnd = math.min(
          slice.plainText.length,
          selEnd - slice.startOffset,
        );
        if (localStart < localEnd) {
          final List<ui.TextBox> boxes = slice.painter.getBoxesForSelection(
            TextSelection(baseOffset: localStart, extentOffset: localEnd),
          );
          for (int b = 0; b < boxes.length; b++) {
            canvas.drawRect(
              boxes[b].toRect().shift(offset + slice.offset),
              selPaint,
            );
          }
        }
      }
    }

    _selectable?.pushLeaderLayers(context, offset);
  }

  void _drawBoxLocalPicture(Canvas canvas, Offset offset, ui.Picture picture) {
    if (offset == Offset.zero) {
      canvas.drawPicture(picture);
      return;
    }
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  void _paintLayout(
    Canvas canvas,
    _CanvasNodeLayout layout,
    Offset topLeft,
    _ResolvedCanvasStyles styles,
  ) {
    switch (layout) {
      case _CanvasHeadingLayout():
        layout.painter.paint(
          canvas,
          Offset(topLeft.dx, topLeft.dy + layout.topPad),
        );
        final double? divY = layout.dividerY;
        if (divY != null) {
          final double width = _laidOutContentWidth ?? size.width;
          canvas.drawRect(
            Rect.fromLTWH(topLeft.dx, topLeft.dy + divY, width, 1.0),
            styles.borderFillPaint,
          );
        }
      case _CanvasParagraphLayout():
        layout.painter.paint(canvas, topLeft);
      case _CanvasThematicBreakLayout():
        final double width = _laidOutContentWidth ?? size.width;
        canvas.drawRect(
          Rect.fromLTWH(topLeft.dx, topLeft.dy + 8.0, width, 1.0),
          styles.borderFillPaint,
        );
      case _CanvasBlockQuoteLayout():
        final Rect outerRect = Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy,
          layout.width,
          layout.height,
        );
        canvas.drawRect(outerRect, styles.quoteBgPaint);
        canvas.drawRect(
          Rect.fromLTWH(topLeft.dx, topLeft.dy, 4.0, layout.height),
          styles.quoteBorderPaint,
        );
        for (int i = 0; i < layout.children.length; i++) {
          _paintLayout(
            canvas,
            layout.children[i],
            Offset(topLeft.dx + 18.0, topLeft.dy + layout.childOffsetsY[i]),
            styles,
          );
        }
      case _CanvasListLayout():
        for (int i = 0; i < layout.items.length; i++) {
          final _CanvasListItemLayout item = layout.items[i];
          final double itemY = topLeft.dy + item.offsetY;
          if (item.isTaskItem) {
            final double bx = topLeft.dx + item.markerDx;
            final double by = itemY + item.checkboxTop;
            final RRect rrect = RRect.fromRectAndRadius(
              Rect.fromLTWH(bx, by, item.checkboxSize, item.checkboxSize),
              const Radius.circular(3.5),
            );
            if (item.taskChecked) {
              canvas.drawRRect(rrect, styles.accentFillPaint);
            }
            canvas.drawRRect(
              rrect,
              item.taskChecked
                  ? styles.accentStrokePaint
                  : styles.mutedStrokePaint,
            );
            if (item.taskChecked) {
              final Path checkPath = Path()
                ..moveTo(bx + 4.0, by + 8.3)
                ..lineTo(bx + 6.9, by + 11.2)
                ..lineTo(bx + 12.2, by + 5.2);
              canvas.drawPath(checkPath, styles.checkmarkStrokePaint);
            }
          } else if (item.bulletDepth != null) {
            final Offset center = Offset(
              topLeft.dx + item.markerDx + 9.0,
              itemY + item.bulletCenterY,
            );
            switch (item.bulletDepth!) {
              case 0:
                canvas.drawCircle(center, 2.5, styles.mutedFillPaint);
              case 1:
                canvas.drawCircle(center, 2.5, styles.mutedThinStrokePaint);
              default:
                canvas.drawRect(
                  Rect.fromCenter(center: center, width: 4.5, height: 4.5),
                  styles.mutedFillPaint,
                );
            }
          } else if (item.markerPainter != null) {
            item.markerPainter!.paint(
              canvas,
              Offset(topLeft.dx + item.markerDx, itemY),
            );
          }

          for (int j = 0; j < item.children.length; j++) {
            _paintLayout(
              canvas,
              item.children[j],
              Offset(
                topLeft.dx + item.contentDx,
                itemY + item.childOffsetsY[j],
              ),
              styles,
            );
          }
        }
      case _CanvasCodeBlockLayout():
        final Rect outerRect = Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy,
          layout.width,
          layout.height,
        );
        final RRect outerRRect = RRect.fromRectAndRadius(
          outerRect,
          const Radius.circular(8.0),
        );
        canvas.drawRRect(outerRRect, styles.codeBgPaint);
        canvas.drawRRect(outerRRect, styles.borderStrokePaint);

        canvas.drawRRect(
          layout.badgePillRect.shift(topLeft),
          styles.badgeBgPaint,
        );
        layout.badgePainter.paint(
          canvas,
          Offset(topLeft.dx + 19.0, topLeft.dy + 9.0),
        );

        final bool copied = _copiedBlockIds.contains(layout.blockId);
        final TextPainter copyTp = copied
            ? layout.copiedPainter
            : layout.copyPainter;
        copyTp.paint(
          canvas,
          Offset(
            topLeft.dx + layout.copyRect.right - 6.0 - copyTp.width,
            topLeft.dy + layout.copyRect.top + 2.0,
          ),
        );

        final double headerLineY = topLeft.dy + 1.0 + layout.headerHeight;
        canvas.drawRect(
          Rect.fromLTWH(
            topLeft.dx + 1.0,
            headerLineY,
            math.max(0.0, layout.width - 2.0),
            1.0,
          ),
          styles.borderFillPaint,
        );

        if (layout.clipCode) {
          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(
              topLeft.dx + 13.0,
              topLeft.dy + layout.codeTop,
              math.max(0.0, layout.width - 26.0),
              layout.codePainter.height,
            ),
          );
        }
        layout.codePainter.paint(
          canvas,
          Offset(topLeft.dx + 13.0, topLeft.dy + layout.codeTop),
        );
        if (layout.clipCode) {
          canvas.restore();
        }
      case _CanvasTableLayout():
        final bool clipH = layout.totalWidth > layout.maxAvailableWidth;
        if (clipH) {
          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(
              topLeft.dx,
              topLeft.dy,
              layout.maxAvailableWidth,
              layout.height,
            ),
          );
        }
        final Paint borderPaint = styles.borderStrokePaint;

        for (int r = 0; r < layout.rows.length; r++) {
          final _CanvasTableRowLayout row = layout.rows[r];
          final Rect rowRect = Rect.fromLTWH(
            topLeft.dx,
            topLeft.dy + row.top,
            layout.totalWidth,
            row.height,
          );
          if (row.isHeader) {
            canvas.drawRect(rowRect, styles.tableHeaderBgPaint);
          } else if (row.isOddData) {
            canvas.drawRect(rowRect, styles.tableStripeBgPaint);
          }
          for (int c = 0; c < row.cells.length; c++) {
            final _CanvasTableCellLayout cell = row.cells[c];
            cell.painter.paint(
              canvas,
              Offset(topLeft.dx + cell.dx, topLeft.dy + cell.dy),
            );
          }
        }

        // Outer border and interior grid lines.
        canvas.drawRect(
          Rect.fromLTWH(
            topLeft.dx + 0.5,
            topLeft.dy + 0.5,
            math.max(0.0, layout.totalWidth - 1.0),
            math.max(0.0, layout.height - 1.0),
          ),
          borderPaint,
        );
        double colX = 0.0;
        for (int c = 0; c < layout.colWidths.length - 1; c++) {
          colX += layout.colWidths[c];
          canvas.drawLine(
            Offset(topLeft.dx + colX, topLeft.dy),
            Offset(topLeft.dx + colX, topLeft.dy + layout.height),
            borderPaint,
          );
        }
        for (int r = 1; r < layout.rows.length; r++) {
          final double lineY = topLeft.dy + layout.rows[r].top;
          canvas.drawLine(
            Offset(topLeft.dx, lineY),
            Offset(topLeft.dx + layout.totalWidth, lineY),
            borderPaint,
          );
        }

        if (clipH) {
          canvas.restore();
        }
    }
  }
}

bool _sameSimpleInlines(
  List<MarkdownInlineNode> a,
  List<MarkdownInlineNode> b,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    final MarkdownInlineNode x = a[i];
    final MarkdownInlineNode y = b[i];
    if (x.runtimeType != y.runtimeType) {
      return false;
    }
    switch (x) {
      case TextNode():
        if (x.text != (y as TextNode).text) {
          return false;
        }
      case CodeSpanNode():
        if (x.literal != (y as CodeSpanNode).literal) {
          return false;
        }
      case SoftBreakNode():
      case HardBreakNode():
      case InlineBreakNode():
        continue;
      case EmphasisNode():
        if (!_sameSimpleInlines(x.children, (y as EmphasisNode).children)) {
          return false;
        }
      case StrongNode():
        if (!_sameSimpleInlines(x.children, (y as StrongNode).children)) {
          return false;
        }
      case StrikethroughNode():
        if (!_sameSimpleInlines(
          x.children,
          (y as StrikethroughNode).children,
        )) {
          return false;
        }
      case HighlightNode():
        if (!_sameSimpleInlines(x.children, (y as HighlightNode).children)) {
          return false;
        }
      case SubscriptNode():
      case SuperscriptNode():
      case LinkNode():
      case ImageNode():
      case PictureInlineNode():
      case MathInlineNode():
      case FootnoteRefNode():
      case KbdInlineNode():
      case AbbrInlineNode():
      case AnchorInlineNode():
      case RawHtmlInlineNode():
        return false;
    }
  }
  return true;
}

bool _sameCanvasBlockList(
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
    if (!_sameCanvasBlock(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

bool _sameCanvasBlock(MarkdownBlockNode a, MarkdownBlockNode b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.runtimeType != b.runtimeType) {
    return false;
  }
  switch (a) {
    case HeadingNode():
      final HeadingNode other = b as HeadingNode;
      return a.level == other.level &&
          _sameSimpleInlines(a.children, other.children);
    case ParagraphNode():
      return _sameSimpleInlines(a.children, (b as ParagraphNode).children);
    case ThematicBreakNode():
      return true;
    case CodeBlockNode():
      final CodeBlockNode other = b as CodeBlockNode;
      return a.language == other.language && a.literal == other.literal;
    case BlockQuoteNode():
      return _sameCanvasBlockList(a.children, (b as BlockQuoteNode).children);
    case ListNode():
      final ListNode other = b as ListNode;
      if (a.ordered != other.ordered ||
          a.start != other.start ||
          a.delimiter != other.delimiter ||
          a.tight != other.tight ||
          a.items.length != other.items.length) {
        return false;
      }
      for (int i = 0; i < a.items.length; i++) {
        if (!_sameCanvasBlock(a.items[i], other.items[i])) {
          return false;
        }
      }
      return true;
    case ListItemNode():
      final ListItemNode other = b as ListItemNode;
      return a.isTaskItem == other.isTaskItem &&
          a.taskState == other.taskState &&
          _sameCanvasBlockList(a.children, other.children);
    case TableNode():
      final TableNode other = b as TableNode;
      if (a.headers.length != other.headers.length ||
          a.rows.length != other.rows.length ||
          a.alignments.length != other.alignments.length) {
        return false;
      }
      for (int i = 0; i < a.alignments.length; i++) {
        if (a.alignments[i] != other.alignments[i]) {
          return false;
        }
      }
      for (int c = 0; c < a.headers.length; c++) {
        if (a.headers[c].alignment != other.headers[c].alignment ||
            !_sameSimpleInlines(
              a.headers[c].children,
              other.headers[c].children,
            )) {
          return false;
        }
      }
      for (int r = 0; r < a.rows.length; r++) {
        final List<TableCellNode> ra = a.rows[r];
        final List<TableCellNode> rb = other.rows[r];
        if (ra.length != rb.length) {
          return false;
        }
        for (int c = 0; c < ra.length; c++) {
          if (ra[c].alignment != rb[c].alignment ||
              !_sameSimpleInlines(ra[c].children, rb[c].children)) {
            return false;
          }
        }
      }
      return true;
    case FrontmatterNode():
    case AlertNode():
    case HtmlBlockNode():
    case DetailsBlockNode():
    case AlignedBlockNode():
    case FigureBlockNode():
    case MathBlockNode():
    case DefinitionListNode():
    case FootnoteDefinitionNode():
    case FootnoteSectionNode():
      return false;
  }
}

final class _ResolvedCanvasStyles {
  _ResolvedCanvasStyles({required this.theme, required this.env});

  final MarkdownThemeData theme;
  final MarkdownRenderEnvironment env;

  TextStyle? _bodyStyle;
  TextStyle get bodyStyle =>
      _bodyStyle ??= env.resolveTextStyle(theme.bodyTextStyle());

  TextStyle? _bodyCodeSpanStyle;
  TextStyle get bodyCodeSpanStyle =>
      _bodyCodeSpanStyle ??= _deriveCodeSpanStyle(bodyStyle, theme);

  TextStyle _deriveCodeSpanStyle(TextStyle base, MarkdownThemeData active) {
    final double baseSize = base.fontSize ?? active.fontSize;
    return base.copyWith(
      fontFamily: active.effectiveCodeFontFamily,
      fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
      fontSize: baseSize * 0.9,
      color: active.effectiveCodeForeground,
      backgroundColor: active.codeBackground,
    );
  }

  final List<TextStyle?> _headingStyles = List<TextStyle?>.filled(6, null);
  TextStyle headingStyleFor(int level) {
    final int idx = (level - 1).clamp(0, 5);
    return _headingStyles[idx] ??= env.resolveTextStyle(
      theme.headingTextStyle(level),
    );
  }

  MarkdownThemeData? _quoteTheme;
  MarkdownThemeData get quoteTheme =>
      _quoteTheme ??= theme.copyWith(foreground: theme.muted);

  TextStyle? _quoteBodyStyle;
  TextStyle get quoteBodyStyle =>
      _quoteBodyStyle ??= env.resolveTextStyle(quoteTheme.bodyTextStyle());

  TextStyle? _quoteCodeSpanStyle;
  TextStyle get quoteCodeSpanStyle =>
      _quoteCodeSpanStyle ??= _deriveCodeSpanStyle(quoteBodyStyle, quoteTheme);

  TextStyle? _markerStyle;
  TextStyle get markerStyle => _markerStyle ??= env.resolveTextStyle(
    theme.bodyTextStyle(color: theme.muted),
  );

  TextStyle? _codeStyle;
  TextStyle get codeStyle =>
      _codeStyle ??= env.resolveTextStyle(theme.codeTextStyle());

  TextStyle? _badgeStyle;
  TextStyle get badgeStyle => _badgeStyle ??= env.resolveTextStyle(
    TextStyle(
      color: theme.muted,
      fontSize: theme.codeFontSize * 0.8,
      fontWeight: FontWeight.w600,
      fontFamily: theme.effectiveCodeFontFamily,
      fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
    ),
  );

  TextStyle? _tableHeaderStyle;
  TextStyle get tableHeaderStyle => _tableHeaderStyle ??= env.resolveTextStyle(
    theme.bodyTextStyle().copyWith(fontWeight: FontWeight.w700),
  );

  TextStyle? _tableHeaderCodeSpanStyle;
  TextStyle get tableHeaderCodeSpanStyle => _tableHeaderCodeSpanStyle ??=
      _deriveCodeSpanStyle(tableHeaderStyle, theme);

  TextStyle? _tableBodyStyle;
  TextStyle get tableBodyStyle => _tableBodyStyle ??= env.resolveTextStyle(
    theme.bodyTextStyle().copyWith(fontWeight: FontWeight.w400),
  );

  TextStyle? _tableBodyCodeSpanStyle;
  TextStyle get tableBodyCodeSpanStyle =>
      _tableBodyCodeSpanStyle ??= _deriveCodeSpanStyle(tableBodyStyle, theme);

  Paint? _borderFillPaint;
  Paint get borderFillPaint => _borderFillPaint ??= Paint()
    ..color = theme.border
    ..isAntiAlias = false;

  Paint? _borderStrokePaint;
  Paint get borderStrokePaint => _borderStrokePaint ??= Paint()
    ..color = theme.border
    ..style = PaintingStyle.stroke
    ..isAntiAlias = false
    ..strokeWidth = 1.0;

  Paint? _codeBgPaint;
  Paint get codeBgPaint =>
      _codeBgPaint ??= Paint()..color = theme.codeBackground;

  Paint? _badgeBgPaint;
  Paint get badgeBgPaint =>
      _badgeBgPaint ??= Paint()..color = theme.border.withValues(alpha: 0.45);

  Paint? _quoteBgPaint;
  Paint get quoteBgPaint => _quoteBgPaint ??= Paint()
    ..color = theme.effectiveBlockquoteBackground
    ..isAntiAlias = false;

  Paint? _quoteBorderPaint;
  Paint get quoteBorderPaint => _quoteBorderPaint ??= Paint()
    ..color = theme.effectiveBlockquoteBorder
    ..isAntiAlias = false;

  Paint? _accentFillPaint;
  Paint get accentFillPaint =>
      _accentFillPaint ??= Paint()..color = theme.accent;

  Paint? _accentStrokePaint;
  Paint get accentStrokePaint => _accentStrokePaint ??= Paint()
    ..color = theme.accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  Paint? _mutedStrokePaint;
  Paint get mutedStrokePaint => _mutedStrokePaint ??= Paint()
    ..color = theme.muted
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  Paint? _mutedFillPaint;
  Paint get mutedFillPaint => _mutedFillPaint ??= Paint()..color = theme.muted;

  Paint? _mutedThinStrokePaint;
  Paint get mutedThinStrokePaint => _mutedThinStrokePaint ??= Paint()
    ..color = theme.muted
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.25;

  Paint? _checkmarkStrokePaint;
  Paint get checkmarkStrokePaint => _checkmarkStrokePaint ??= Paint()
    ..color = theme.brightness == Brightness.dark
        ? const Color(0xFF0F172A)
        : const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint? _tableHeaderBgPaint;
  Paint get tableHeaderBgPaint => _tableHeaderBgPaint ??= Paint()
    ..color = theme.effectiveTableHeaderBackground
    ..isAntiAlias = false;

  Paint? _tableStripeBgPaint;
  Paint get tableStripeBgPaint => _tableStripeBgPaint ??= Paint()
    ..color = theme.effectiveTableStripeBackground
    ..isAntiAlias = false;

  TextStyle? _copyTextStyle;
  TextStyle get _resolvedCopyStyle => _copyTextStyle ??= env.resolveTextStyle(
    TextStyle(
      color: theme.muted,
      fontSize: theme.fontSize * 0.78,
      fontWeight: FontWeight.w600,
      fontFamily: theme.fontFamily,
    ),
  );

  TextPainter? _copyPainter;
  TextPainter get copyPainter => _copyPainter ??= TextPainter(
    text: TextSpan(text: 'Copy', style: _resolvedCopyStyle),
    textDirection: env.textDirection,
    textScaler: env.textScaler,
    locale: env.locale,
  )..layout();

  TextPainter? _copiedPainter;
  TextPainter get copiedPainter => _copiedPainter ??= TextPainter(
    text: TextSpan(
      text: 'Copied',
      style: _resolvedCopyStyle.copyWith(color: theme.accent),
    ),
    textDirection: env.textDirection,
    textScaler: env.textScaler,
    locale: env.locale,
  )..layout();

  final Map<String, TextPainter> _badgePainters = <String, TextPainter>{};
  final Map<String, TextPainter> _orderedMarkerPainters =
      <String, TextPainter>{};

  TextPainter badgePainterFor(String badgeText) =>
      _badgePainters[badgeText] ??= TextPainter(
        text: TextSpan(text: badgeText, style: badgeStyle),
        textDirection: env.textDirection,
        textScaler: env.textScaler,
        locale: env.locale,
      )..layout();

  TextPainter orderedMarkerPainterFor(String label) =>
      _orderedMarkerPainters[label] ??= TextPainter(
        text: TextSpan(text: label, style: markerStyle),
        textAlign: TextAlign.right,
        textDirection: env.textDirection,
        textScaler: env.textScaler,
        locale: env.locale,
      )..layout(minWidth: 26.0, maxWidth: 26.0);

  TextPainter _newPainter({
    required InlineSpan span,
    TextAlign textAlign = TextAlign.start,
  }) {
    return TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: env.textDirection,
      textScaler: env.textScaler,
      locale: env.locale,
    );
  }

  _CanvasNodeLayout layoutBlock(
    MarkdownBlockNode node,
    double maxWidth, {
    required int listDepth,
    MarkdownBlockNode? previousNode,
    _CanvasNodeLayout? previousLayout,
    TextAlign textAlign = TextAlign.start,
    TextStyle? paragraphStyleOverride,
    MarkdownThemeData? themeOverride,
  }) {
    final MarkdownThemeData activeTheme = themeOverride ?? theme;
    switch (node) {
      case HeadingNode():
        final TextStyle effectiveStyle = themeOverride == null
            ? headingStyleFor(node.level)
            : env.resolveTextStyle(activeTheme.headingTextStyle(node.level));
        final ({InlineSpan span, String plainText}) built =
            buildFastSimpleInlineSpan(
              node.children,
              effectiveStyle,
              activeTheme,
            );
        final TextPainter tp;
        if (previousLayout is _CanvasHeadingLayout) {
          tp = previousLayout.painter
            ..text = built.span
            ..textAlign = textAlign
            ..layout(maxWidth: maxWidth);
        } else {
          tp = _newPainter(span: built.span, textAlign: textAlign)
            ..layout(maxWidth: maxWidth);
        }
        final double topPad = node.level <= 2 ? 8.0 : 4.0;
        final bool hasDivider = node.level <= 2;
        final double? dividerY = hasDivider ? topPad + tp.height + 6.0 : null;
        final double totalHeight =
            topPad + tp.height + (hasDivider ? 7.0 : 0.0);
        return _CanvasHeadingLayout(
          height: totalHeight,
          textRuns: <_CanvasTextRun>[
            _CanvasTextRun(
              painter: tp,
              dx: 0.0,
              dy: topPad,
              plainText: built.plainText,
            ),
          ],
          painter: tp,
          topPad: topPad,
          dividerY: dividerY,
        );

      case ParagraphNode():
        final TextStyle effStyle = paragraphStyleOverride ?? bodyStyle;
        final TextStyle? cachedCodeStyle =
            (paragraphStyleOverride == null ||
                identical(paragraphStyleOverride, _bodyStyle))
            ? bodyCodeSpanStyle
            : (identical(paragraphStyleOverride, _quoteBodyStyle)
                  ? quoteCodeSpanStyle
                  : null);
        final ({InlineSpan span, String plainText}) built =
            buildFastSimpleInlineSpan(
              node.children,
              effStyle,
              activeTheme,
              cachedCodeSpanStyle: cachedCodeStyle,
            );
        final TextPainter tp;
        if (previousLayout is _CanvasParagraphLayout) {
          tp = previousLayout.painter
            ..text = built.span
            ..textAlign = textAlign
            ..layout(maxWidth: maxWidth);
        } else {
          tp = _newPainter(span: built.span, textAlign: textAlign)
            ..layout(maxWidth: maxWidth);
        }
        return _CanvasParagraphLayout(
          height: tp.height,
          textRuns: <_CanvasTextRun>[
            _CanvasTextRun(
              painter: tp,
              dx: 0.0,
              dy: 0.0,
              plainText: built.plainText,
            ),
          ],
          painter: tp,
        );

      case ThematicBreakNode():
        return const _CanvasThematicBreakLayout();

      case BlockQuoteNode():
        final MarkdownThemeData quoteThemeResolved = themeOverride == null
            ? quoteTheme
            : activeTheme.copyWith(foreground: activeTheme.muted);
        final TextStyle quoteBodyResolved = themeOverride == null
            ? quoteBodyStyle
            : env.resolveTextStyle(quoteThemeResolved.bodyTextStyle());
        final double childMaxW = math.max(0.0, maxWidth - 30.0);
        final double gap = quoteThemeResolved.blockSpacing * 0.75;
        final List<_CanvasNodeLayout> childLayouts = <_CanvasNodeLayout>[];
        final List<double> childOffsetsY = <double>[];
        final List<_CanvasTextRun> allRuns = <_CanvasTextRun>[];
        final BlockQuoteNode? prevQuote = previousNode is BlockQuoteNode
            ? previousNode
            : null;
        final _CanvasBlockQuoteLayout? prevQuoteLayout =
            previousLayout is _CanvasBlockQuoteLayout ? previousLayout : null;
        double cy = 10.0;
        for (int i = 0; i < node.children.length; i++) {
          if (i > 0) {
            cy += gap;
          }
          final MarkdownBlockNode child = node.children[i];
          final _CanvasNodeLayout cl;
          if (prevQuote != null &&
              prevQuoteLayout != null &&
              i < prevQuote.children.length &&
              i < prevQuoteLayout.children.length &&
              (identical(prevQuote.children[i], child) ||
                  (prevQuote.children[i].span.length == child.span.length &&
                      _sameCanvasBlock(prevQuote.children[i], child)))) {
            cl = prevQuoteLayout.children[i];
          } else {
            cl = layoutBlock(
              child,
              childMaxW,
              listDepth: listDepth,
              previousNode: prevQuote != null && i < prevQuote.children.length
                  ? prevQuote.children[i]
                  : null,
              previousLayout:
                  prevQuoteLayout != null && i < prevQuoteLayout.children.length
                  ? prevQuoteLayout.children[i]
                  : null,
              textAlign: textAlign,
              paragraphStyleOverride: quoteBodyResolved,
              themeOverride: quoteThemeResolved,
            );
          }
          childOffsetsY.add(cy);
          childLayouts.add(cl);
          for (int r = 0; r < cl.textRuns.length; r++) {
            final _CanvasTextRun run = cl.textRuns[r];
            allRuns.add(
              _CanvasTextRun(
                painter: run.painter,
                dx: 18.0 + run.dx,
                dy: cy + run.dy,
                plainText: run.plainText,
              ),
            );
          }
          cy += cl.height;
        }
        final double totalHeight = math.max(20.0, cy + 10.0);
        return _CanvasBlockQuoteLayout(
          height: totalHeight,
          textRuns: allRuns,
          width: maxWidth,
          childOffsetsY: childOffsetsY,
          children: childLayouts,
          backgroundColor: activeTheme.effectiveBlockquoteBackground,
          borderColor: activeTheme.effectiveBlockquoteBorder,
        );

      case ListNode():
        return _layoutList(
          node,
          maxWidth,
          listDepth: listDepth,
          activeTheme: activeTheme,
          textAlign: textAlign,
          previousNode: previousNode is ListNode ? previousNode : null,
          previousLayout: previousLayout is _CanvasListLayout
              ? previousLayout
              : null,
        );

      case ListItemNode():
        return _layoutList(
          ListNode(
            blockId: node.blockId,
            items: <ListItemNode>[node],
            ordered: false,
            tight: false,
          ),
          maxWidth,
          listDepth: listDepth,
          activeTheme: activeTheme,
          textAlign: textAlign,
        );

      case CodeBlockNode():
        return _layoutCodeBlock(
          node,
          maxWidth,
          previousLayout: previousLayout is _CanvasCodeBlockLayout
              ? previousLayout
              : null,
        );

      case TableNode():
        return _layoutTable(
          node,
          maxWidth,
          activeTheme: activeTheme,
          previousNode: previousNode is TableNode ? previousNode : null,
          previousLayout: previousLayout is _CanvasTableLayout
              ? previousLayout
              : null,
        );

      case FrontmatterNode():
      case AlertNode():
      case HtmlBlockNode():
      case DetailsBlockNode():
      case AlignedBlockNode():
      case FigureBlockNode():
      case MathBlockNode():
      case DefinitionListNode():
      case FootnoteDefinitionNode():
      case FootnoteSectionNode():
        return _CanvasParagraphLayout(
          height: 0.0,
          textRuns: const <_CanvasTextRun>[],
          painter: _newPainter(span: const TextSpan(text: ''))..layout(),
        );
    }
  }

  _CanvasListLayout _layoutList(
    ListNode node,
    double maxWidth, {
    required int listDepth,
    required MarkdownThemeData activeTheme,
    required TextAlign textAlign,
    ListNode? previousNode,
    _CanvasListLayout? previousLayout,
  }) {
    final List<ListItemNode> items = node.items;
    if (items.isEmpty) {
      return const _CanvasListLayout(
        height: 0.0,
        textRuns: <_CanvasTextRun>[],
        items: <_CanvasListItemLayout>[],
      );
    }

    final bool canReuseItems =
        previousNode != null &&
        previousLayout != null &&
        previousNode.ordered == node.ordered &&
        previousNode.start == node.start &&
        previousNode.delimiter == node.delimiter &&
        previousNode.tight == node.tight;

    final double itemGap = node.tight ? 4.0 : 8.0;
    final double childGap = node.tight ? 4.0 : activeTheme.blockSpacing * 0.65;
    final double lineHeightPx = activeTheme.fontSize * activeTheme.lineHeight;
    final double bulletCenterY = lineHeightPx * 0.5;
    final int? sharedBulletDepth = node.ordered ? null : listDepth % 3;

    final List<_CanvasListItemLayout> itemLayouts = <_CanvasListItemLayout>[];
    final List<_CanvasTextRun> allRuns = <_CanvasTextRun>[];
    double y = 0.0;

    for (int i = 0; i < items.length; i++) {
      if (i > 0) {
        y += itemGap;
      }
      final ListItemNode item = items[i];
      final bool hasPrevItem =
          canReuseItems &&
          i < previousNode.items.length &&
          i < previousLayout.items.length;
      if (hasPrevItem &&
          (identical(previousNode.items[i], item) ||
              (previousNode.items[i].span.length == item.span.length &&
                  _sameCanvasBlock(previousNode.items[i], item)))) {
        final _CanvasListItemLayout prevItem = previousLayout.items[i];
        itemLayouts.add(
          prevItem.offsetY == y
              ? prevItem
              : _CanvasListItemLayout(
                  offsetY: y,
                  height: prevItem.height,
                  isTaskItem: prevItem.isTaskItem,
                  taskChecked: prevItem.taskChecked,
                  checkboxSize: prevItem.checkboxSize,
                  checkboxTop: prevItem.checkboxTop,
                  bulletDepth: prevItem.bulletDepth,
                  bulletCenterY: prevItem.bulletCenterY,
                  markerPainter: prevItem.markerPainter,
                  markerDx: prevItem.markerDx,
                  contentDx: prevItem.contentDx,
                  childOffsetsY: prevItem.childOffsetsY,
                  children: prevItem.children,
                ),
        );
        for (int j = 0; j < prevItem.children.length; j++) {
          final _CanvasNodeLayout cl = prevItem.children[j];
          final double cy = prevItem.childOffsetsY[j];
          for (int r = 0; r < cl.textRuns.length; r++) {
            final _CanvasTextRun run = cl.textRuns[r];
            allRuns.add(
              _CanvasTextRun(
                painter: run.painter,
                dx: prevItem.contentDx + run.dx,
                dy: y + cy + run.dy,
                plainText: run.plainText,
              ),
            );
          }
        }
        y += prevItem.height;
        continue;
      }

      final double markerWidth;
      const double markerDx = 0.0;
      TextPainter? markerPainter;
      int? bulletDepth;
      final bool isTask = item.isTaskItem;
      final bool checked = item.taskState ?? false;
      final double checkboxTop = math.max(0.0, (lineHeightPx - 16.0) * 0.5);

      if (isTask) {
        markerWidth = 16.0;
      } else if (node.ordered) {
        markerWidth = 26.0;
        markerPainter = orderedMarkerPainterFor(
          '${node.start + i}${node.delimiter}',
        );
      } else {
        markerWidth = 18.0;
        bulletDepth = sharedBulletDepth;
      }

      final double contentDx = markerWidth + 8.0;
      final double childMaxW = math.max(0.0, maxWidth - contentDx);
      final List<_CanvasNodeLayout> childLayouts = <_CanvasNodeLayout>[];
      final List<double> childOffsetsY = <double>[];
      final ListItemNode? prevItemNode = hasPrevItem
          ? previousNode.items[i]
          : null;
      final _CanvasListItemLayout? prevItemLayout = hasPrevItem
          ? previousLayout.items[i]
          : null;
      double cy = 0.0;

      for (int j = 0; j < item.children.length; j++) {
        if (j > 0) {
          cy += childGap;
        }
        final _CanvasNodeLayout cl = layoutBlock(
          item.children[j],
          childMaxW,
          listDepth: listDepth + 1,
          previousNode: prevItemNode != null && j < prevItemNode.children.length
              ? prevItemNode.children[j]
              : null,
          previousLayout:
              prevItemLayout != null && j < prevItemLayout.children.length
              ? prevItemLayout.children[j]
              : null,
          textAlign: textAlign,
          paragraphStyleOverride: bodyStyle,
          themeOverride: activeTheme,
        );
        childOffsetsY.add(cy);
        childLayouts.add(cl);
        for (int r = 0; r < cl.textRuns.length; r++) {
          final _CanvasTextRun run = cl.textRuns[r];
          allRuns.add(
            _CanvasTextRun(
              painter: run.painter,
              dx: contentDx + run.dx,
              dy: y + cy + run.dy,
              plainText: run.plainText,
            ),
          );
        }
        cy += cl.height;
      }

      final double minMarkerH = isTask
          ? checkboxTop + 16.0
          : (markerPainter?.height ?? lineHeightPx);
      final double itemHeight = math.max(minMarkerH, cy);
      itemLayouts.add(
        _CanvasListItemLayout(
          offsetY: y,
          height: itemHeight,
          isTaskItem: isTask,
          taskChecked: checked,
          checkboxSize: 16.0,
          checkboxTop: checkboxTop,
          bulletDepth: bulletDepth,
          bulletCenterY: bulletCenterY,
          markerPainter: markerPainter,
          markerDx: markerDx,
          contentDx: contentDx,
          childOffsetsY: childOffsetsY,
          children: childLayouts,
        ),
      );
      y += itemHeight;
    }

    return _CanvasListLayout(height: y, textRuns: allRuns, items: itemLayouts);
  }

  _CanvasCodeBlockLayout _layoutCodeBlock(
    CodeBlockNode node,
    double maxWidth, {
    _CanvasCodeBlockLayout? previousLayout,
  }) {
    final String? lang = node.language;
    final String badgeText = (lang != null && lang.isNotEmpty) ? lang : 'code';
    final String trimmed = node.literal.endsWith('\n')
        ? node.literal.substring(0, node.literal.length - 1)
        : node.literal;

    final TextPainter badgePainter = badgePainterFor(badgeText);
    final TextPainter copyTp = copyPainter;
    final TextPainter copiedTp = copiedPainter;

    final double badgePillH = badgePainter.height + 4.0;
    final double copyPillH = copyTp.height + 4.0;
    final double headerContentH = math.max(badgePillH, copyPillH);
    final double headerHeight = headerContentH + 12.0;

    final RRect badgePillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(13.0, 7.0, badgePainter.width + 12.0, badgePillH),
      const Radius.circular(4.0),
    );
    final double copyW = copyTp.width + 12.0;
    final Rect copyRect = Rect.fromLTWH(
      math.max(13.0, maxWidth - 13.0 - copyW),
      7.0 + (headerContentH - copyPillH) * 0.5,
      copyW,
      copyPillH,
    );

    final TextPainter codePainter;
    if (previousLayout != null) {
      codePainter = previousLayout.codePainter
        ..text = TextSpan(text: trimmed, style: codeStyle)
        ..layout(maxWidth: double.infinity);
    } else {
      codePainter = _newPainter(
        span: TextSpan(text: trimmed, style: codeStyle),
      )..layout(maxWidth: double.infinity);
    }

    final double codeTop = 1.0 + headerHeight + 1.0 + 12.0;
    final double totalHeight = codeTop + codePainter.height + 12.0 + 1.0;
    final bool clipCode = codePainter.width > math.max(0.0, maxWidth - 26.0);

    return _CanvasCodeBlockLayout(
      height: totalHeight,
      textRuns: <_CanvasTextRun>[
        _CanvasTextRun(
          painter: codePainter,
          dx: 13.0,
          dy: codeTop,
          plainText: trimmed,
        ),
      ],
      blockId: node.blockId,
      width: maxWidth,
      headerHeight: headerHeight,
      badgeText: badgeText,
      badgePainter: badgePainter,
      badgePillRect: badgePillRect,
      copyPainter: copyTp,
      copiedPainter: copiedTp,
      copyRect: copyRect,
      codePainter: codePainter,
      codeText: node.literal,
      codeTop: codeTop,
      clipCode: clipCode,
    );
  }

  _CanvasTableLayout _layoutTable(
    TableNode node,
    double maxWidth, {
    required MarkdownThemeData activeTheme,
    TableNode? previousNode,
    _CanvasTableLayout? previousLayout,
  }) {
    final List<TableCellNode> headers = node.headers;
    final List<List<TableCellNode>> rows = node.rows;
    final List<TableAlignment> alignments = node.alignments;

    int columnCount = headers.length;
    for (int r = 0; r < rows.length; r++) {
      if (rows[r].length > columnCount) {
        columnCount = rows[r].length;
      }
    }
    if (columnCount == 0) {
      return _CanvasTableLayout(
        height: 0.0,
        textRuns: const <_CanvasTextRun>[],
        totalWidth: 0.0,
        maxAvailableWidth: maxWidth,
        colWidths: const <double>[],
        rows: const <_CanvasTableRowLayout>[],
        cellCaches: const <List<_TableCellCache>>[],
      );
    }

    final int totalRows = 1 + rows.length;
    final List<double> colWidths = List<double>.filled(columnCount, 24.0);
    final List<List<_TableCellCache>> nextCaches = <List<_TableCellCache>>[];
    final List<List<_TableCellCache>>? prevCaches =
        (previousNode != null && previousLayout != null)
        ? previousLayout.cellCaches
        : null;

    TableAlignment resolveAlign(TableCellNode cell, int col) {
      if (cell.alignment != TableAlignment.none) {
        return cell.alignment;
      }
      return col < alignments.length ? alignments[col] : TableAlignment.none;
    }

    TextAlign textAlignFor(TableAlignment align) {
      switch (align) {
        case TableAlignment.left:
          return TextAlign.left;
        case TableAlignment.center:
          return TextAlign.center;
        case TableAlignment.right:
          return TextAlign.right;
        case TableAlignment.none:
          return TextAlign.start;
      }
    }

    for (int r = 0; r < totalRows; r++) {
      final bool isHeader = r == 0;
      final List<TableCellNode> sourceRow = isHeader ? headers : rows[r - 1];
      final TextStyle style = isHeader ? tableHeaderStyle : tableBodyStyle;
      final List<_TableCellCache>? prevRow =
          (prevCaches != null && r < prevCaches.length) ? prevCaches[r] : null;
      final List<_TableCellCache> rowCache = <_TableCellCache>[];

      for (int c = 0; c < columnCount; c++) {
        final TableCellNode cell = c < sourceRow.length
            ? sourceRow[c]
            : TableCellNode(
                alignment: c < alignments.length
                    ? alignments[c]
                    : TableAlignment.none,
              );
        final TableAlignment align = resolveAlign(cell, c);
        final _TableCellCache? cached = (prevRow != null && c < prevRow.length)
            ? prevRow[c]
            : null;
        if (cached != null &&
            !cached.narrowWrapped &&
            cached.alignment == align &&
            (identical(cached.node, cell) ||
                (cached.node.span.length == cell.span.length &&
                    _sameSimpleInlines(cached.node.children, cell.children)))) {
          rowCache.add(cached);
          if (cached.intrinsicW > colWidths[c]) {
            colWidths[c] = cached.intrinsicW;
          }
          continue;
        }
        final ({InlineSpan span, String plainText}) built =
            buildFastSimpleInlineSpan(
              cell.children,
              style,
              activeTheme,
              cachedCodeSpanStyle: isHeader
                  ? tableHeaderCodeSpanStyle
                  : tableBodyCodeSpanStyle,
            );
        final TextPainter tp;
        if (cached != null && cached.alignment == align) {
          tp = cached.painter
            ..text = built.span
            ..layout(maxWidth: 420.0);
        } else {
          tp = _newPainter(span: built.span, textAlign: textAlignFor(align))
            ..layout(maxWidth: 420.0);
        }
        final double intrinsicW = math.min(tp.maxIntrinsicWidth, 420.0) + 24.0;
        if (intrinsicW > colWidths[c]) {
          colWidths[c] = intrinsicW;
        }
        rowCache.add(
          _TableCellCache(
            node: cell,
            alignment: align,
            painter: tp,
            intrinsicW: intrinsicW,
            plainText: built.plainText,
            narrowWrapped: false,
          ),
        );
      }
      nextCaches.add(rowCache);
    }

    double totalWidth = 0.0;
    for (int c = 0; c < columnCount; c++) {
      totalWidth += colWidths[c];
    }

    final List<_CanvasTableRowLayout> rowLayouts = <_CanvasTableRowLayout>[];
    final List<_CanvasTextRun> allRuns = <_CanvasTextRun>[];
    double y = 0.0;

    for (int r = 0; r < totalRows; r++) {
      final List<_TableCellCache> rowCache = nextCaches[r];
      double maxCellH = 0.0;
      for (int c = 0; c < columnCount; c++) {
        final double cellMaxW = math.max(0.0, colWidths[c] - 24.0);
        final _TableCellCache item = rowCache[c];
        final TextPainter tp = item.painter;
        if (tp.width > cellMaxW) {
          tp.layout(maxWidth: cellMaxW);
          rowCache[c] = _TableCellCache(
            node: item.node,
            alignment: item.alignment,
            painter: tp,
            intrinsicW: item.intrinsicW,
            plainText: item.plainText,
            narrowWrapped: true,
          );
        }
        if (tp.height > maxCellH) {
          maxCellH = tp.height;
        }
      }
      final double rowHeight = maxCellH + 16.0;
      final List<_CanvasTableCellLayout> rowCells = <_CanvasTableCellLayout>[];
      double x = 0.0;
      for (int c = 0; c < columnCount; c++) {
        final double cw = colWidths[c];
        final _TableCellCache item = rowCache[c];
        final TextPainter tp = item.painter;
        final double innerW = math.max(0.0, cw - 24.0);
        final double alignOffsetX = switch (item.alignment) {
          TableAlignment.center => math.max(0.0, (innerW - tp.width) * 0.5),
          TableAlignment.right => math.max(0.0, innerW - tp.width),
          TableAlignment.left || TableAlignment.none => 0.0,
        };
        final double dx = x + 12.0 + alignOffsetX;
        final double dy = y + 8.0;
        rowCells.add(_CanvasTableCellLayout(painter: tp, dx: dx, dy: dy));
        allRuns.add(
          _CanvasTextRun(
            painter: tp,
            dx: dx,
            dy: dy,
            plainText: item.plainText,
          ),
        );
        x += cw;
      }
      rowLayouts.add(
        _CanvasTableRowLayout(
          top: y,
          height: rowHeight,
          isHeader: r == 0,
          isOddData: r > 0 && (r - 1).isOdd,
          cells: rowCells,
        ),
      );
      y += rowHeight;
    }

    return _CanvasTableLayout(
      height: y,
      textRuns: allRuns,
      totalWidth: totalWidth,
      maxAvailableWidth: maxWidth,
      colWidths: colWidths,
      rows: rowLayouts,
      cellCaches: nextCaches,
    );
  }
}

final class _StreamingCanvasSelectable extends ChangeNotifier
    with Selectable, SelectionRegistrant {
  _StreamingCanvasSelectable(this._box);

  final RenderMarkdownStreamingCanvas _box;
  int? _start;
  int? _end;
  LayerLink? _startHandleLink;
  LayerLink? _endHandleLink;
  final LayerHandle<LeaderLayer> _startHandleLayer = LayerHandle<LeaderLayer>();
  final LayerHandle<LeaderLayer> _endHandleLayer = LayerHandle<LeaderLayer>();
  SelectionGeometry _geometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: false,
  );

  bool get hasSelection => _start != null && _end != null;
  bool get hasHandleLayers =>
      (_startHandleLink != null && _geometry.startSelectionPoint != null) ||
      (_endHandleLink != null && _geometry.endSelectionPoint != null);

  @override
  SelectionGeometry get value => _geometry;

  @override
  int get contentLength => _box._totalSelectableLength;

  @override
  Size get size => _box.hasSize ? _box.size : Size.zero;

  @override
  List<Rect> get boundingBoxes =>
      _box.hasSize ? <Rect>[_box.paintBounds] : const <Rect>[];

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) =>
      _box.getTransformTo(ancestor);

  void clearHandleLayers() {
    _startHandleLink = null;
    _endHandleLink = null;
    _startHandleLayer.layer = null;
    _endHandleLayer.layer = null;
  }

  @override
  void dispose() {
    clearHandleLayers();
    super.dispose();
  }

  void didUpdateContent() {
    final int len = _box._totalSelectableLength;
    if (!hasSelection) {
      final SelectionGeometry next = SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: len > 0,
      );
      if (_geometry != next) {
        _geometry = next;
        notifyListeners();
      }
      return;
    }
    _start = _start!.clamp(0, len);
    _end = _end!.clamp(0, len);
  }

  void didChangeLayout() {
    if (hasSelection) {
      _updateGeometry();
    }
  }

  void _updateGeometry() {
    final bool hadHandles = hasHandleLayers;
    final SelectionGeometry next = _computeGeometry();
    if (_geometry != next) {
      _geometry = next;
      if (hadHandles != hasHandleLayers) {
        _box.markNeedsCompositingBitsUpdate();
      }
      notifyListeners();
    }
  }

  int _offsetForLocal(Offset local) {
    _box._ensureSlices();
    final List<_SelectableSlice> slices = _box._slices;
    if (slices.isEmpty) {
      return 0;
    }
    if (local.dy <= slices.first.top) {
      final _SelectableSlice first = slices.first;
      return first.startOffset +
          first.painter
              .getPositionForOffset(local - first.offset)
              .offset
              .clamp(0, first.plainText.length);
    }
    if (local.dy >= slices.last.bottom) {
      final _SelectableSlice last = slices.last;
      return last.startOffset +
          last.painter
              .getPositionForOffset(local - last.offset)
              .offset
              .clamp(0, last.plainText.length);
    }
    _SelectableSlice best = slices.first;
    double bestDist = double.infinity;
    for (int i = 0; i < slices.length; i++) {
      final _SelectableSlice s = slices[i];
      final double dyDist = local.dy < s.top
          ? s.top - local.dy
          : (local.dy > s.bottom ? local.dy - s.bottom : 0.0);
      final double right = s.offset.dx + s.painter.width;
      final double dxDist = local.dx < s.offset.dx
          ? s.offset.dx - local.dx
          : (local.dx > right ? local.dx - right : 0.0);
      final double dist = dyDist * 1024.0 + dxDist;
      if (dist < bestDist) {
        bestDist = dist;
        best = s;
        if (dist == 0.0) {
          break;
        }
      }
    }
    return best.startOffset +
        best.painter
            .getPositionForOffset(local - best.offset)
            .offset
            .clamp(0, best.plainText.length);
  }

  _SelectableSlice? _sliceForOffset(int offset) {
    _box._ensureSlices();
    final List<_SelectableSlice> slices = _box._slices;
    if (slices.isEmpty) {
      return null;
    }
    int lo = 0;
    int hi = slices.length - 1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      final _SelectableSlice s = slices[mid];
      if (offset < s.startOffset) {
        hi = mid - 1;
      } else if (offset > s.endOffset) {
        lo = mid + 1;
      } else {
        return s;
      }
    }
    return slices[lo.clamp(0, slices.length - 1)];
  }

  Offset _caretForOffset(int offset, {required double lineHeightFallback}) {
    final _SelectableSlice? slice = _sliceForOffset(offset);
    if (slice == null) {
      return Offset(0.0, lineHeightFallback);
    }
    final int localOff = (offset - slice.startOffset).clamp(
      0,
      slice.plainText.length,
    );
    final Offset caret = slice.painter.getOffsetForCaret(
      TextPosition(offset: localOff),
      Rect.zero,
    );
    return slice.offset +
        caret +
        Offset(0.0, slice.painter.preferredLineHeight);
  }

  double _lineHeightAtOffset(int offset) {
    final _SelectableSlice? slice = _sliceForOffset(offset);
    if (slice == null) {
      return 16.0;
    }
    return slice.painter.preferredLineHeight;
  }

  SelectionGeometry _computeGeometry() {
    final int len = _box._totalSelectableLength;
    final bool hasContent = len > 0;
    if (!hasSelection) {
      return SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: hasContent,
      );
    }
    final int start = _start!.clamp(0, len);
    final int end = _end!.clamp(0, len);
    if (!_box.hasSize || !hasContent) {
      return SelectionGeometry(
        status: start == end
            ? SelectionStatus.collapsed
            : SelectionStatus.uncollapsed,
        hasContent: hasContent,
      );
    }

    final double startLh = _lineHeightAtOffset(start);
    final double endLh = _lineHeightAtOffset(end);
    final Offset startCaret = _caretForOffset(
      start,
      lineHeightFallback: startLh,
    );
    final Offset endCaret = _caretForOffset(end, lineHeightFallback: endLh);
    final bool isReversed = start > end;
    final bool flipHandles =
        isReversed != (_box._textDirection == TextDirection.rtl);
    final bool collapsed = start == end;
    final (
      TextSelectionHandleType startType,
      TextSelectionHandleType endType,
    ) = switch ((collapsed, flipHandles)) {
      (true, _) => (
        TextSelectionHandleType.collapsed,
        TextSelectionHandleType.collapsed,
      ),
      (false, true) => (
        TextSelectionHandleType.right,
        TextSelectionHandleType.left,
      ),
      (false, false) => (
        TextSelectionHandleType.left,
        TextSelectionHandleType.right,
      ),
    };

    final List<Rect> rects = <Rect>[];
    if (!collapsed) {
      _box._ensureSlices();
      final int selA = math.min(start, end);
      final int selB = math.max(start, end);
      // Avoid enumerating all line boxes for Select All over large streams.
      final bool isSelectAll =
          selA == 0 && selB == len && _box._slices.length > 24;
      if (isSelectAll) {
        rects.add(_box.paintBounds);
      } else {
        for (int i = 0; i < _box._slices.length; i++) {
          final _SelectableSlice s = _box._slices[i];
          if (s.endOffset <= selA || s.startOffset >= selB) {
            continue;
          }
          final int la = math.max(0, selA - s.startOffset);
          final int lb = math.min(s.plainText.length, selB - s.startOffset);
          if (la < lb) {
            final List<ui.TextBox> boxes = s.painter.getBoxesForSelection(
              TextSelection(baseOffset: la, extentOffset: lb),
            );
            for (int b = 0; b < boxes.length; b++) {
              rects.add(boxes[b].toRect().shift(s.offset));
            }
          }
        }
      }
    }

    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: startCaret,
        lineHeight: startLh,
        handleType: startType,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: endCaret,
        lineHeight: endLh,
        handleType: endType,
      ),
      selectionRects: rects,
      status: collapsed
          ? SelectionStatus.collapsed
          : SelectionStatus.uncollapsed,
      hasContent: hasContent,
    );
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (identical(_startHandleLink, startHandle) &&
        identical(_endHandleLink, endHandle)) {
      return;
    }
    final bool hadHandles = hasHandleLayers;
    _startHandleLink = startHandle;
    _endHandleLink = endHandle;
    if (hadHandles != hasHandleLayers) {
      _box.markNeedsCompositingBitsUpdate();
    }
    _box.markNeedsPaint();
  }

  static void _paintNothing(PaintingContext context, Offset offset) {}

  void pushLeaderLayers(PaintingContext context, Offset offset) {
    final LayerLink? startLink = _startHandleLink;
    final SelectionPoint? startPt = _geometry.startSelectionPoint;
    if (startLink != null && startPt != null) {
      final LeaderLayer layer = _startHandleLayer.layer ??= LeaderLayer(
        link: startLink,
        offset: offset + startPt.localPosition,
      );
      layer
        ..link = startLink
        ..offset = offset + startPt.localPosition;
      context.pushLayer(layer, _paintNothing, Offset.zero);
    } else {
      _startHandleLayer.layer = null;
    }

    final LayerLink? endLink = _endHandleLink;
    final SelectionPoint? endPt = _geometry.endSelectionPoint;
    if (endLink != null && endPt != null) {
      final LeaderLayer layer = _endHandleLayer.layer ??= LeaderLayer(
        link: endLink,
        offset: offset + endPt.localPosition,
      );
      layer
        ..link = endLink
        ..offset = offset + endPt.localPosition;
      context.pushLayer(layer, _paintNothing, Offset.zero);
    } else {
      _endHandleLayer.layer = null;
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    if (!hasSelection) {
      return null;
    }
    final String text = _box._getPlainText();
    final int a = math.min(_start!, _end!).clamp(0, text.length);
    final int b = math.max(_start!, _end!).clamp(0, text.length);
    return SelectedContent(plainText: text.substring(a, b));
  }

  @override
  SelectedContentRange? getSelection() {
    if (!hasSelection) {
      return null;
    }
    return SelectedContentRange(startOffset: _start!, endOffset: _end!);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final int? prevStart = _start;
    final int? prevEnd = _end;
    final int len = _box._totalSelectableLength;
    late final SelectionResult result;

    switch (event.type) {
      case SelectionEventType.selectAll:
        _start = 0;
        _end = len;
        result = SelectionResult.none;
      case SelectionEventType.clear:
        _start = null;
        _end = null;
        result = SelectionResult.none;
      case SelectionEventType.selectWord:
        final SelectWordSelectionEvent wordEvent =
            event as SelectWordSelectionEvent;
        final Offset local = _box.globalToLocal(wordEvent.globalPosition);
        final int globalOff = _offsetForLocal(local);
        final _SelectableSlice? slice = _sliceForOffset(globalOff);
        if (slice == null) {
          _start = 0;
          _end = 0;
        } else {
          final int localOff = (globalOff - slice.startOffset).clamp(
            0,
            slice.plainText.length,
          );
          final TextRange word = slice.painter.getWordBoundary(
            TextPosition(offset: localOff),
          );
          _start = slice.startOffset + word.start;
          _end = slice.startOffset + word.end;
        }
        result = SelectionResult.end;
      case SelectionEventType.selectParagraph:
        final SelectParagraphSelectionEvent paraEvent =
            event as SelectParagraphSelectionEvent;
        final Offset local = _box.globalToLocal(paraEvent.globalPosition);
        final int globalOff = _offsetForLocal(local);
        final _SelectableSlice? slice = _sliceForOffset(globalOff);
        if (slice == null) {
          _start = 0;
          _end = len;
        } else {
          _start = slice.startOffset;
          _end = slice.endOffset;
        }
        result = paraEvent.absorb ? SelectionResult.next : SelectionResult.end;
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final SelectionEdgeUpdateEvent edgeEvent =
            event as SelectionEdgeUpdateEvent;
        final bool isEnd = edgeEvent.type == SelectionEventType.endEdgeUpdate;
        final Offset local = _box.globalToLocal(edgeEvent.globalPosition);
        final SelectionResult edgeResult = SelectionUtils.getResultBasedOnRect(
          _box.paintBounds,
          local,
        );
        final int targetOffset;
        switch (edgeResult) {
          case SelectionResult.previous:
            targetOffset = 0;
          case SelectionResult.next:
            targetOffset = len;
          case SelectionResult.end:
          case SelectionResult.pending:
          case SelectionResult.none:
            final Offset adjusted = SelectionUtils.adjustDragOffset(
              _box.paintBounds,
              local,
              direction: _box._textDirection,
            );
            final int globalOff = _offsetForLocal(adjusted);
            switch (edgeEvent.granularity) {
              case TextGranularity.word:
                final _SelectableSlice? slice = _sliceForOffset(globalOff);
                if (slice == null) {
                  targetOffset = globalOff;
                } else {
                  final int localOff = (globalOff - slice.startOffset).clamp(
                    0,
                    slice.plainText.length,
                  );
                  final TextRange word = slice.painter.getWordBoundary(
                    TextPosition(offset: localOff),
                  );
                  final int wStart = slice.startOffset + word.start;
                  final int wEnd = slice.startOffset + word.end;
                  final int? other = isEnd ? _start : _end;
                  if (other != null && globalOff < other) {
                    targetOffset = wStart;
                  } else if (other != null && globalOff > other) {
                    targetOffset = wEnd;
                  } else {
                    targetOffset = (globalOff - wStart) <= (wEnd - globalOff)
                        ? wStart
                        : wEnd;
                  }
                }
              case TextGranularity.paragraph:
                final _SelectableSlice? slice = _sliceForOffset(globalOff);
                if (slice == null) {
                  targetOffset = globalOff;
                } else {
                  final int? other = isEnd ? _start : _end;
                  targetOffset = (other != null && globalOff < other)
                      ? slice.startOffset
                      : slice.endOffset;
                }
              case TextGranularity.character:
              case TextGranularity.line:
              case TextGranularity.document:
                targetOffset = globalOff.clamp(0, len);
            }
        }
        if (isEnd) {
          _end = targetOffset;
          _start ??= targetOffset;
        } else {
          _start = targetOffset;
          _end ??= targetOffset;
        }
        result = edgeResult;
      case SelectionEventType.granularlyExtendSelection:
        final GranularlyExtendSelectionEvent ext =
            event as GranularlyExtendSelectionEvent;
        final int current =
            (ext.isEnd ? _end : _start) ?? (ext.forward ? 0 : len);
        final int next = (ext.forward ? current + 1 : current - 1).clamp(
          0,
          len,
        );
        if (ext.isEnd) {
          _end = next;
          _start ??= next;
        } else {
          _start = next;
          _end ??= next;
        }
        result = (ext.forward && next == len)
            ? SelectionResult.next
            : (!ext.forward && next == 0)
            ? SelectionResult.previous
            : SelectionResult.end;
      case SelectionEventType.directionallyExtendSelection:
        final DirectionallyExtendSelectionEvent ext =
            event as DirectionallyExtendSelectionEvent;
        final bool forward =
            ext.direction == SelectionExtendDirection.forward ||
            ext.direction == SelectionExtendDirection.nextLine;
        final int current = (ext.isEnd ? _end : _start) ?? 0;
        final int next = (forward ? len : 0);
        if (ext.isEnd) {
          _end = next;
          _start ??= next;
        } else {
          _start = next;
          _end ??= next;
        }
        result = next == current ? SelectionResult.none : SelectionResult.end;
    }

    if (prevStart != _start || prevEnd != _end) {
      _box.markNeedsPaint();
      _updateGeometry();
    }
    return result;
  }
}
