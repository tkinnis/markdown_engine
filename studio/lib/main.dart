import 'dart:async';

import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

import 'studio_builders.dart';
import 'studio_inspector.dart';
import 'studio_outline_panel.dart';
import 'studio_presets.dart';
import 'studio_streaming_pane.dart';

/// Entry point for the `markdown_engine` macOS inspection and streaming
/// workbench.
void main() {
  runApp(const MarkdownStudioApp());
}

/// Root widget for the `markdown_engine_studio` macOS desktop application.
final class MarkdownStudioApp extends StatefulWidget {
  /// Creates the studio workbench application.
  ///
  /// When [initialSource] is omitted, the workbench opens with the default
  /// `CommonMark & GFM Showcase` preset.
  const MarkdownStudioApp({super.key, this.initialSource});

  /// Optional custom Markdown source pre-populated in the editor pane.
  final String? initialSource;

  @override
  State<MarkdownStudioApp> createState() => _MarkdownStudioAppState();
}

final class _StudioStreamTelemetry extends ChangeNotifier {
  int appliedChunks = 0;
  int chunkIntervalMs = 100;
  int lastChunkParseMicros = 0;
  int totalParseMicros = 0;
  String lastChunkText = '';
  bool isPlaying = false;

  void notify() => notifyListeners();
}

final class _MarkdownStudioAppState extends State<MarkdownStudioApp> {
  static const double _wideOutlineBreakpoint = 1120.0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late StudioPresetId _selectedPresetId;
  late MarkdownOptions _activeOptions;
  late final TextEditingController _editorController;
  late final ValueNotifier<String> _editorTextNotifier;
  late final MarkdownController _markdownController;
  late final ScrollController _previewScrollController;
  late final StreamingMarkdownController _streamController;
  late final _StudioStreamTelemetry _streamTelemetry;
  late final ValueNotifier<({String? message, bool isError})> _statusNotifier;

  bool _isDark = false;
  bool _isStreamingMode = false;
  bool _showOutlineSidebar = true;
  bool _showInspectorPane = true;
  bool _remoteImagesApproved = false;
  StudioInspectorTab _inspectorTab = StudioInspectorTab.ast;

  MarkdownDocument? _lastAuditedDoc;
  MarkdownUrlPolicy? _lastAuditedPolicy;
  StudioLinkAudit? _cachedLinkAudit;

  Timer? _streamTimer;

  @override
  void initState() {
    super.initState();
    _selectedPresetId = StudioPresetId.showcase;
    final StudioPreset initialPreset = studioPresetById(_selectedPresetId);
    _activeOptions = initialPreset.options;
    final String initialText = widget.initialSource ?? initialPreset.source;
    _editorController = TextEditingController(text: initialText)
      ..addListener(_handleEditorChanged);
    _editorTextNotifier = ValueNotifier<String>(initialText);
    _markdownController = MarkdownController();
    _previewScrollController = ScrollController();
    _streamController = StreamingMarkdownController(
      options: const MarkdownOptions.extended(),
    );
    _streamTelemetry = _StudioStreamTelemetry();
    _statusNotifier = ValueNotifier<({String? message, bool isError})>((
      message: null,
      isError: false,
    ));
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _editorController
      ..removeListener(_handleEditorChanged)
      ..dispose();
    _editorTextNotifier.dispose();
    _markdownController.dispose();
    _previewScrollController.dispose();
    _streamController.dispose();
    _streamTelemetry.dispose();
    _statusNotifier.dispose();
    super.dispose();
  }

  void _handleEditorChanged() {
    final String nextText = _editorController.text;
    if (_editorTextNotifier.value == nextText) {
      return;
    }
    _editorTextNotifier.value = nextText;
    if (_remoteImagesApproved) {
      setState(() {
        _remoteImagesApproved = false;
      });
    }
  }

  void _selectPreset(StudioPresetId? nextId) {
    if (nextId == null) {
      return;
    }
    final StudioPreset preset = studioPresetById(nextId);
    _stopStreamTimer();
    setState(() {
      _selectedPresetId = nextId;
      _activeOptions = preset.options;
      _isStreamingMode = false;
      _remoteImagesApproved = false;
    });
    _editorController.text = preset.source;
    _editorTextNotifier.value = preset.source;
    _showStatus('Loaded preset: ${preset.label}');
    _resetPreviewScroll();
  }

  void _toggleTheme() {
    setState(() {
      _isDark = !_isDark;
    });
  }

  void _toggleStreamingMode() {
    setState(() {
      _isStreamingMode = !_isStreamingMode;
      _remoteImagesApproved = false;
      if (!_isStreamingMode) {
        _stopStreamTimer();
      }
    });
    if (!_isStreamingMode) {
      _showStatus('Switched to Live Editor mode.');
    } else {
      _markdownController.updateDocument(_streamController.currentDocument);
      _showStatus(
        'Switched to LLM Streaming Simulator mode. Press Play or Step.',
      );
    }
    _resetPreviewScroll();
  }

  void _toggleOutline(bool isWideViewport) {
    if (isWideViewport) {
      setState(() {
        _showOutlineSidebar = !_showOutlineSidebar;
      });
    } else {
      final ScaffoldState? scaffold = _scaffoldKey.currentState;
      if (scaffold != null) {
        if (scaffold.isDrawerOpen) {
          scaffold.closeDrawer();
        } else {
          scaffold.openDrawer();
        }
      }
    }
  }

  void _toggleInspector() {
    setState(() {
      _showInspectorPane = !_showInspectorPane;
    });
  }

  void _stopStreamTimer() {
    _streamTimer?.cancel();
    _streamTimer = null;
    if (_streamTelemetry.isPlaying) {
      _streamTelemetry.isPlaying = false;
      _streamTelemetry.notify();
    }
  }

  void _stepStreamChunk() {
    if (_streamTelemetry.appliedChunks >= studioStreamingChunks.length) {
      _stopStreamTimer();
      return;
    }
    final String chunk = studioStreamingChunks[_streamTelemetry.appliedChunks];
    final Stopwatch stopwatch = Stopwatch()..start();
    _streamController.append(chunk);
    _streamTelemetry.appliedChunks++;
    if (_streamTelemetry.appliedChunks >= studioStreamingChunks.length) {
      _streamController.finish();
      _streamTimer?.cancel();
      _streamTimer = null;
      _streamTelemetry.isPlaying = false;
    }
    stopwatch.stop();
    final int elapsedMicros = stopwatch.elapsedMicroseconds;
    _streamTelemetry
      ..lastChunkParseMicros = elapsedMicros
      ..totalParseMicros += elapsedMicros
      ..lastChunkText = chunk
      ..notify();
    _markdownController.updateDocument(_streamController.currentDocument);
  }

  void _toggleStreamPlayPause() {
    if (_streamTimer != null) {
      _stopStreamTimer();
      return;
    }
    if (_streamTelemetry.appliedChunks >= studioStreamingChunks.length) {
      _resetStream();
    }
    _startStreamTimer();
  }

  void _startStreamTimer() {
    _streamTimer?.cancel();
    _streamTelemetry.isPlaying = true;
    _streamTelemetry.notify();
    _streamTimer = Timer.periodic(
      Duration(milliseconds: _streamTelemetry.chunkIntervalMs),
      (Timer timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        _stepStreamChunk();
        if (_streamTelemetry.appliedChunks >= studioStreamingChunks.length) {
          timer.cancel();
        }
      },
    );
  }

  void _updateChunkInterval(int nextIntervalMs) {
    final bool wasPlaying = _streamTimer != null;
    _streamTelemetry
      ..chunkIntervalMs = nextIntervalMs
      ..notify();
    if (wasPlaying) {
      _startStreamTimer();
    }
  }

  void _resetStream() {
    _streamTimer?.cancel();
    _streamTimer = null;
    _streamTelemetry
      ..isPlaying = false
      ..appliedChunks = 0
      ..lastChunkParseMicros = 0
      ..totalParseMicros = 0
      ..lastChunkText = ''
      ..notify();
    _streamController.reset();
    _markdownController.updateDocument(_streamController.currentDocument);
    if (_remoteImagesApproved) {
      setState(() {
        _remoteImagesApproved = false;
      });
    }
    _resetPreviewScroll();
    _showStatus('Streaming simulator reset.');
  }

  void _finishStream() {
    _streamTimer?.cancel();
    _streamTimer = null;
    final Stopwatch stopwatch = Stopwatch()..start();
    while (_streamTelemetry.appliedChunks < studioStreamingChunks.length) {
      final String chunk =
          studioStreamingChunks[_streamTelemetry.appliedChunks];
      _streamController.append(chunk);
      _streamTelemetry.lastChunkText = chunk;
      _streamTelemetry.appliedChunks++;
    }
    _streamController.finish();
    stopwatch.stop();
    final int elapsedMicros = stopwatch.elapsedMicroseconds;
    _streamTelemetry
      ..isPlaying = false
      ..lastChunkParseMicros = elapsedMicros
      ..totalParseMicros += elapsedMicros
      ..notify();
    _markdownController.updateDocument(_streamController.currentDocument);
  }

  void _resetPreviewScroll() {
    if (_previewScrollController.hasClients) {
      _previewScrollController.jumpTo(0.0);
    }
  }

  void _showStatus(
    String message, {
    bool isError = false,
    bool showSnackBar = false,
  }) {
    _statusNotifier.value = (message: message, isError: isError);
    if (showSnackBar) {
      final ScaffoldMessengerState? messenger =
          _scaffoldMessengerKey.currentState;
      if (messenger != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
      }
    }
  }

  void _handleLinkTap(
    String destination,
    String? title,
    MarkdownUrlPolicy policy,
  ) {
    final bool allowed = policy.isAllowed(destination);
    if (!allowed) {
      _showStatus(
        'MarkdownUrlPolicy blocked destination: $destination',
        isError: true,
        showSnackBar: true,
      );
      return;
    }
    if (destination.startsWith('#')) {
      _showStatus(
        'MarkdownUrlPolicy allowed anchor jump: $destination',
        showSnackBar: true,
      );
      return;
    }
    final String titleSuffix = title != null && title.isNotEmpty
        ? ' ("$title")'
        : '';
    _showStatus(
      'MarkdownUrlPolicy allowed link: $destination$titleSuffix',
      showSnackBar: true,
    );
  }

  StudioLinkAudit _memoizedLinkAudit(
    MarkdownDocument doc,
    MarkdownUrlPolicy policy,
  ) {
    if (!identical(_lastAuditedDoc, doc) || _lastAuditedPolicy != policy) {
      _lastAuditedDoc = doc;
      _lastAuditedPolicy = policy;
      _cachedLinkAudit = auditDocumentLinks(doc, policy);
    }
    return _cachedLinkAudit!;
  }

  ThemeData _buildMaterialTheme(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0284C7),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final MarkdownThemeData markdownTheme = _isDark
        ? const MarkdownThemeData.dark()
        : const MarkdownThemeData.light();
    final MarkdownUrlPolicy activeUrlPolicy = _isStreamingMode
        ? _streamController.effectiveOptions.urlPolicy
        : _activeOptions.urlPolicy;
    final MarkdownBuilderDelegates delegates = buildStudioDelegates(
      theme: markdownTheme,
      urlPolicy: activeUrlPolicy,
      remoteImagesApproved: _remoteImagesApproved,
      onTapLink: (String destination, String? title) =>
          _handleLinkTap(destination, title, activeUrlPolicy),
      onLoadRemoteImages: () {
        setState(() {
          _remoteImagesApproved = true;
        });
        _showStatus(
          'Remote image loading approved for current view (MarkdownImagePolicy.ask).',
          showSnackBar: true,
        );
      },
    );

    return MaterialApp(
      title: 'markdown_engine Studio',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: _buildMaterialTheme(Brightness.light),
      darkTheme: _buildMaterialTheme(Brightness.dark),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool isWide = constraints.maxWidth >= _wideOutlineBreakpoint;
          final ColorScheme scheme = Theme.of(context).colorScheme;
          return Scaffold(
            key: _scaffoldKey,
            drawer: isWide
                ? null
                : Drawer(
                    width: 280.0,
                    child: SafeArea(
                      child: StudioOutlinePanel(
                        controller: _markdownController,
                        onJumpToHeading: (MarkdownOutlineItem item) {
                          _scaffoldKey.currentState?.closeDrawer();
                          _showStatus(
                            'Jumped to outline heading #${item.slug} (L${item.line}).',
                          );
                        },
                        onClose: () => _scaffoldKey.currentState?.closeDrawer(),
                      ),
                    ),
                  ),
            body: MarkdownTheme(
              data: markdownTheme,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildToolbar(context, scheme, isWide: isWide),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            flex: 3,
                            child: _isStreamingMode
                                ? ListenableBuilder(
                                    listenable: _streamTelemetry,
                                    builder:
                                        (BuildContext context, Widget? child) {
                                          final int applied =
                                              _streamTelemetry.appliedChunks;
                                          return StudioStreamingPane(
                                            streamController: _streamController,
                                            isPlaying:
                                                _streamTelemetry.isPlaying,
                                            appliedChunkCount: applied,
                                            totalChunkCount:
                                                studioStreamingChunks.length,
                                            chunkIntervalMs: _streamTelemetry
                                                .chunkIntervalMs,
                                            lastChunkParseMicros:
                                                _streamTelemetry
                                                    .lastChunkParseMicros,
                                            averageChunkParseMicros:
                                                applied == 0
                                                ? 0
                                                : (_streamTelemetry
                                                              .totalParseMicros /
                                                          applied)
                                                      .round(),
                                            lastChunkText:
                                                _streamTelemetry.lastChunkText,
                                            onTogglePlayPause:
                                                _toggleStreamPlayPause,
                                            onStep: _stepStreamChunk,
                                            onReset: _resetStream,
                                            onFinish: _finishStream,
                                            onIntervalChanged:
                                                _updateChunkInterval,
                                          );
                                        },
                                  )
                                : _buildEditorPane(context, scheme),
                          ),
                          const VerticalDivider(width: 1.0),
                          if (isWide && _showOutlineSidebar) ...<Widget>[
                            SizedBox(
                              width: 215.0,
                              child: StudioOutlinePanel(
                                controller: _markdownController,
                                onJumpToHeading: (MarkdownOutlineItem item) =>
                                    _showStatus(
                                      'Jumped to outline heading #${item.slug} (L${item.line}).',
                                    ),
                                onClose: () => _toggleOutline(true),
                              ),
                            ),
                            const VerticalDivider(width: 1.0),
                          ],
                          Expanded(
                            flex: _showInspectorPane ? 4 : 6,
                            child: _buildPreviewPane(
                              context,
                              scheme,
                              markdownTheme: markdownTheme,
                              delegates: delegates,
                              urlPolicy: activeUrlPolicy,
                              isWide: isWide,
                            ),
                          ),
                          if (_showInspectorPane) ...<Widget>[
                            const VerticalDivider(width: 1.0),
                            Expanded(
                              flex: 3,
                              child: StudioInspectorPane(
                                controller: _markdownController,
                                activeTab: _inspectorTab,
                                onTabChanged: (StudioInspectorTab tab) {
                                  setState(() {
                                    _inspectorTab = tab;
                                  });
                                },
                                onNotify: (String message) =>
                                    _showStatus(message),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    ColorScheme scheme, {
    required bool isWide,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Wrap(
        spacing: 10.0,
        runSpacing: 8.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.article_rounded, color: scheme.primary, size: 20.0),
              const SizedBox(width: 7.0),
              Text(
                'markdown_engine Studio',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          Container(
            height: 32.0,
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<StudioPresetId>(
                key: const Key('studio-preset-dropdown'),
                value: _selectedPresetId,
                isDense: true,
                borderRadius: BorderRadius.circular(8.0),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
                items: studioPresets
                    .map(
                      (StudioPreset preset) => DropdownMenuItem<StudioPresetId>(
                        value: preset.id,
                        child: Text(preset.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _selectPreset,
              ),
            ),
          ),
          FilterChip(
            key: const Key('studio-streaming-toggle'),
            selected: _isStreamingMode,
            showCheckmark: false,
            avatar: Icon(
              _isStreamingMode ? Icons.bolt_rounded : Icons.stream_rounded,
              size: 16.0,
            ),
            label: const Text('Streaming Mode'),
            onSelected: (bool _) => _toggleStreamingMode(),
            visualDensity: VisualDensity.compact,
          ),
          FilterChip(
            key: const Key('studio-outline-toggle'),
            selected: isWide && _showOutlineSidebar,
            showCheckmark: false,
            avatar: const Icon(Icons.toc_rounded, size: 16.0),
            label: ListenableBuilder(
              listenable: _markdownController,
              builder: (BuildContext context, Widget? child) {
                return Text('Outline (${_markdownController.outline.length})');
              },
            ),
            onSelected: (bool _) => _toggleOutline(isWide),
            visualDensity: VisualDensity.compact,
          ),
          FilterChip(
            key: const Key('studio-inspector-toggle'),
            selected: _showInspectorPane,
            showCheckmark: false,
            avatar: const Icon(Icons.code_rounded, size: 16.0),
            label: const Text('Inspector'),
            onSelected: (bool _) => _toggleInspector(),
            visualDensity: VisualDensity.compact,
          ),
          ListenableBuilder(
            listenable: _markdownController,
            builder: (BuildContext context, Widget? child) {
              return Container(
                key: const Key('studio-parse-count'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 9.0,
                  vertical: 5.0,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.speed_rounded,
                      size: 14.0,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 5.0),
                    Text(
                      'Parses: ${_markdownController.parseCount}',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSecondaryContainer,
                        fontFamily: 'SF Mono',
                        fontFamilyFallback:
                            MarkdownThemeData.defaultCodeFontFallback,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          OutlinedButton.icon(
            key: const Key('studio-theme-toggle'),
            onPressed: _toggleTheme,
            icon: Icon(
              _isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 16.0,
            ),
            label: Text(_isDark ? 'Light' : 'Dark'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 6.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorPane(BuildContext context, ColorScheme scheme) {
    final StudioPreset preset = studioPresetById(_selectedPresetId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.edit_note_rounded, size: 16.0, color: scheme.primary),
              const SizedBox(width: 6.0),
              Expanded(
                child: Text(
                  'Markdown Source',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: _editorTextNotifier,
                builder: (BuildContext context, String text, Widget? child) {
                  final int lines = text.isEmpty
                      ? 0
                      : '\n'.allMatches(text).length + 1;
                  return Text(
                    '$lines L · ${text.length} ch',
                    style: TextStyle(
                      fontSize: 11.0,
                      color: scheme.onSurfaceVariant,
                      fontFamily: 'SF Mono',
                      fontFamilyFallback:
                          MarkdownThemeData.defaultCodeFontFallback,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              key: const Key('studio-source-editor'),
              controller: _editorController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                fontFamily: 'SF Mono',
                fontFamilyFallback: MarkdownThemeData.defaultCodeFontFallback,
                fontSize: 13.0,
                height: 1.5,
                color: scheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Type CommonMark or GFM Markdown...',
                helperText: preset.description,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(12.0),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPane(
    BuildContext context,
    ColorScheme scheme, {
    required MarkdownThemeData markdownTheme,
    required MarkdownBuilderDelegates delegates,
    required MarkdownUrlPolicy urlPolicy,
    required bool isWide,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: ListenableBuilder(
            listenable: _markdownController,
            builder: (BuildContext context, Widget? child) {
              final MarkdownDocument doc = _markdownController.document;
              final StudioLinkAudit audit = _memoizedLinkAudit(doc, urlPolicy);
              final int totalBlocks = doc.blocks.length;
              return Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _isStreamingMode
                            ? Icons.auto_awesome_rounded
                            : Icons.visibility_rounded,
                        size: 16.0,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6.0),
                      Text(
                        _isStreamingMode
                            ? 'Streaming Preview'
                            : 'Virtualized Preview',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  ValueListenableBuilder<MarkdownReadingPlace>(
                    valueListenable: _markdownController.readingPlaceNotifier,
                    builder:
                        (
                          BuildContext context,
                          MarkdownReadingPlace place,
                          Widget? child,
                        ) {
                          final int activeBlock = totalBlocks == 0
                              ? 0
                              : (place.blockIndex + 1).clamp(1, totalBlocks);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(5.0),
                            ),
                            child: Text(
                              'Block $activeBlock/$totalBlocks',
                              style: TextStyle(
                                fontSize: 11.0,
                                color: scheme.onSurfaceVariant,
                                fontFamily: 'SF Mono',
                                fontFamilyFallback:
                                    MarkdownThemeData.defaultCodeFontFallback,
                              ),
                            ),
                          );
                        },
                  ),
                  Container(
                    key: const Key('studio-url-policy-badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.0,
                      vertical: 2.0,
                    ),
                    decoration: BoxDecoration(
                      color: audit.blockedOrSanitizedCount > 0
                          ? scheme.errorContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(5.0),
                    ),
                    child: Text(
                      audit.totalCount == 0
                          ? 'MarkdownUrlPolicy: strict'
                          : 'MarkdownUrlPolicy: ${audit.allowedCount} allowed · ${audit.blockedOrSanitizedCount} blocked',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: audit.blockedOrSanitizedCount > 0
                            ? scheme.onErrorContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (!isWide)
                    TextButton.icon(
                      onPressed: () => _toggleOutline(false),
                      icon: const Icon(Icons.toc_rounded, size: 14.0),
                      label: Text('Outline (${doc.outline.length})'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                        textStyle: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        ValueListenableBuilder<({String? message, bool isError})>(
          valueListenable: _statusNotifier,
          builder:
              (
                BuildContext context,
                ({String? message, bool isError}) status,
                Widget? child,
              ) {
                final String? message = status.message;
                if (message == null) {
                  return const SizedBox.shrink();
                }
                final bool isError = status.isError;
                return Container(
                  key: const Key('studio-status-banner'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  decoration: BoxDecoration(
                    color: isError
                        ? scheme.errorContainer
                        : scheme.primaryContainer.withValues(alpha: 0.6),
                    border: Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        isError
                            ? Icons.gpp_bad_rounded
                            : Icons.verified_user_rounded,
                        size: 15.0,
                        color: isError
                            ? scheme.onErrorContainer
                            : scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w500,
                            color: isError
                                ? scheme.onErrorContainer
                                : scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _statusNotifier.value = (
                            message: null,
                            isError: false,
                          );
                        },
                        tooltip: 'Dismiss status',
                        icon: const Icon(Icons.close_rounded, size: 15.0),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 24.0,
                          minHeight: 24.0,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                );
              },
        ),
        Expanded(
          child: Container(
            color: scheme.surface,
            child: _isStreamingMode
                ? _buildStreamingMarkdownView(
                    markdownTheme: markdownTheme,
                    delegates: delegates,
                  )
                : ValueListenableBuilder<String>(
                    valueListenable: _editorTextNotifier,
                    builder:
                        (BuildContext context, String source, Widget? child) {
                          return MarkdownView(
                            source,
                            options: _activeOptions,
                            controller: _markdownController,
                            scrollController: _previewScrollController,
                            theme: markdownTheme,
                            delegates: delegates,
                            padding: const EdgeInsets.all(20.0),
                          );
                        },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStreamingMarkdownView({
    required MarkdownThemeData markdownTheme,
    required MarkdownBuilderDelegates delegates,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        MarkdownView.streaming(
          controller: _streamController,
          markdownController: _markdownController,
          scrollController: _previewScrollController,
          theme: markdownTheme,
          delegates: delegates,
          padding: const EdgeInsets.all(20.0),
        ),
        ListenableBuilder(
          listenable: _streamTelemetry,
          builder: (BuildContext context, Widget? child) {
            if (_streamController.currentDocument.blocks.isNotEmpty) {
              return const SizedBox.shrink();
            }
            return IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.bolt_rounded,
                        size: 36.0,
                        color: markdownTheme.accent,
                      ),
                      const SizedBox(height: 10.0),
                      Text(
                        'Ready to stream Markdown chunks',
                        style: TextStyle(
                          fontSize: 15.0,
                          fontWeight: FontWeight.w700,
                          color: markdownTheme.foreground,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        'Use Play or Step in the left pane to observe settled block freezing and microsecond tail parses.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.0,
                          color: markdownTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
