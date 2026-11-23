import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Entry point for the `markdown_engine_flutter` example application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(MarkdownBuiltInRenderers.warmUp());
  runApp(const MarkdownExampleApp());
}

/// Interactive standalone example showcasing zero-reparse Light/Dark switching,
/// out-of-the-box `tex_math_flutter` OpenType math and `pele_dart` Mermaid
/// diagrams, LLM streaming simulation, and optional custom builder overrides.
final class MarkdownExampleApp extends StatefulWidget {
  /// Creates the example application.
  const MarkdownExampleApp({super.key});

  @override
  State<MarkdownExampleApp> createState() => _MarkdownExampleAppState();
}

final class _MarkdownExampleAppState extends State<MarkdownExampleApp> {
  static const String _showcaseMarkdown = r'''
---
title: markdown_engine_flutter Showcase
spec: CommonMark 0.31.2 + GFM 0.29
tags: [flutter, slivers, tex-math, mermaid, streaming]
---

# Native Flutter Markdown Rendering

This document renders directly into Flutter slivers with **zero WebViews**, built-in OpenType TeX math (`tex_math_flutter`), offline vector Mermaid diagrams (`pele_dart`), native `SelectionArea`, and **zero re-parses** when toggling Light and Dark themes.

## Out-of-the-Box Math & Mermaid (Zero Custom Builders)

Inline formulas align on the alphabetic baseline automatically: Euler's identity $e^{i\pi} + 1 = 0$ and \(\alpha + \beta = \gamma\) sit inline with surrounding prose.

Display equations render natively from `NewCMMath-Regular.otf` glyph paths:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

Fenced `mermaid` blocks render offline via `pele_dart` and `vector_graphics` with zero builder configuration:

```mermaid
flowchart LR
  Source["Markdown Text"] --> Parser["Pure-Dart AST"]
  Parser --> Math["tex_math_flutter"]
  Parser --> Mermaid["pele_dart Vector"]
```

> [!NOTE]
> Toggling the sun/moon theme button updates `MarkdownTheme`, TeX math colors, and Mermaid palettes immediately while keeping `controller.parseCount` at `1`.

> [!TIP]
> Press <kbd>Cmd</kbd>+<kbd>C</kbd> after dragging across paragraphs, tables, or inline `code` spans to copy clean text.

> [!IMPORTANT]
> Unsafe links such as [blocked script](javascript:alert(1)) are strictly non-interactive at the Flutter rendering boundary.

> [!WARNING]
> Remote images default to `MarkdownImagePolicy.block` or `ask` so untrusted Markdown never leaks network requests.

> [!CAUTION]
> Always pass `MarkdownOptions.extended()` when enabling frontmatter, alerts, `<details>`, and abbreviations (`MarkdownOptions()` already enables `math: true` by default).

## GFM Table & Task List

| Capability | Engine | Status |
| :--- | :---: | ---: |
| Sliver Virtualization | `SliverMarkdownDocument` | Ready |
| Built-in TeX Math | `tex_math_flutter` | Active |
| Built-in Mermaid | `pele_dart` + `vector_graphics` | Active |

- [x] CommonMark 0.31.2 & GFM 0.29 parity
- [x] Out-of-the-box OpenType TeX math & vector Mermaid diagrams
- [x] Baseline-aligned `<kbd>` chips, ==highlights==, H~2~O, and 2^10^

## Collapsible Details, Definitions & Footnotes

<details>
<summary>Inspect interactive disclosure block</summary>

Expanded body content supports **rich formatting**, inline `code`, inline math $\sum_{i=1}^n i = \frac{n(n+1)}{2}$, and ==highlighted text==[^1].

</details>

`MarkdownView`
: Virtualized Flutter widget with default, `.document`, and `.streaming` constructors.

`MarkdownBuiltInRenderers`
: Pre-warms `NewCMMath-Regular.otf` and the `pele_dart` diagram registry cleanly via `warmUp()`.

Visit [the project documentation](https://tkinnis.github.io/markdown_engine/) or inspect AST abbreviations with tooltip semantics.

*[AST]: Abstract Syntax Tree

![Remote Architecture Preview](https://example.com/architecture.png)

```dart
final MarkdownEngine engine = MarkdownEngine(
  defaultOptions: const MarkdownOptions.extended(),
);
final MarkdownDocument doc = engine.parse('# Pure Dart');
```

[^1]: Footnotes automatically wire jump and return anchors inside `MarkdownController`.
''';

  static const String _hooksMarkdown = r'''
# Optional Custom Renderer Overrides

Out-of-the-box TeX math (`tex_math_flutter`) and Mermaid vector diagrams (`pele_dart`) require **zero builders** (`enableBuiltInMath: true` and `enableBuiltInMermaid: true` by default). Pass `MarkdownBuilderDelegates` overrides only when your app needs bespoke styling, compact pills, or custom callout decorators:

Inline math overridden via `mathInlineBuilder`: Euler's identity $e^{i\pi} + 1 = 0$ renders here inside a custom compact chip.

Display math overridden via `mathBlockBuilder`:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

Diagram blocks overridden via `diagramBuilder` (return `null` for any language to fall through cleanly to `BuiltInMermaidDiagram` or `codeBlockBuilder`):

```mermaid
flowchart LR
  Source["Markdown Text"] --> AST["Sealed AST"]
  AST --> Hook["Optional diagramBuilder"]
```

Non-diagram languages fall through cleanly to `codeBlockBuilder`:

```dart
Widget buildView(String source) {
  // Zero builders needed for built-in OpenType math & Mermaid diagrams!
  return MarkdownView(
    source,
    options: const MarkdownOptions.extended(),
  );
}
```
''';

  static const List<String> _streamChunks = <String>[
    '# Streaming Assistant Response\n\n',
    'Incoming chunks freeze completed prefix blocks ',
    'while re-parsing only the active trailing slice ',
    'with built-in math like ',
    r'$O(|T|)$ ',
    'complexity.\n\n',
    '> [!TIP]\n> Settled blocks preserve their `blockId` keys across ',
    'every frame.\n\n',
    '\$\$\n',
    r'\Delta t_{\text{chunk}} \propto |T|',
    '\n\$\$\n\n',
    '```mermaid\n',
    'flowchart LR\n',
    '  Chunk["Token Chunk"] --> Tail["Active Tail"]\n',
    '  Tail --> Settled["Frozen Prefix"]\n',
    '```\n\n',
    '| Phase | Behavior |\n| :--- | :--- |\n',
    '| Settled | Frozen immutable AST |\n',
    '| Active tail | Reparsed incrementally |\n\n',
    '```dart\nfinal controller = StreamingMarkdownController();\n',
    'controller.append(chunk);\n```\n',
  ];

  bool _isDark = false;
  int _tabIndex = 0;
  bool _showcaseRemoteImagesApproved = false;
  String? _statusMessage;

  late final MarkdownController _showcaseController;
  MarkdownBuilderDelegates? _cachedShowcaseDelegates;
  bool? _cachedRemoteApproved;

  @override
  void initState() {
    super.initState();
    unawaited(MarkdownBuiltInRenderers.warmUp());
    _showcaseController = MarkdownController();
  }

  @override
  void dispose() {
    _showcaseController.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    setState(() {
      _isDark = !_isDark;
    });
  }

  void _setStatus(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  void _handleShowcaseLinkTap(String destination, String? title) {
    _setStatus('Tapped safe link: $destination');
  }

  void _handleShowcaseLoadRemoteImages() {
    setState(() {
      _showcaseRemoteImagesApproved = true;
      _statusMessage = 'Remote image loading approved for showcase view.';
    });
  }

  MarkdownBuilderDelegates get _showcaseDelegates {
    final MarkdownBuilderDelegates? cached = _cachedShowcaseDelegates;
    if (cached != null &&
        _cachedRemoteApproved == _showcaseRemoteImagesApproved) {
      return cached;
    }
    final MarkdownBuilderDelegates next = MarkdownBuilderDelegates(
      imagePolicy: MarkdownImagePolicy.ask,
      remoteImagesApproved: _showcaseRemoteImagesApproved,
      onLoadRemoteImages: _handleShowcaseLoadRemoteImages,
      onTapLink: _handleShowcaseLinkTap,
    );
    _cachedShowcaseDelegates = next;
    _cachedRemoteApproved = _showcaseRemoteImagesApproved;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0284C7),
      brightness: _isDark ? Brightness.dark : Brightness.light,
    );
    final MarkdownThemeData markdownTheme = _isDark
        ? const MarkdownThemeData.dark()
        : const MarkdownThemeData.light();

    return MaterialApp(
      title: 'markdown_engine_flutter Example',
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('markdown_engine_flutter Example'),
          actions: <Widget>[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: AnimatedBuilder(
                  animation: _showcaseController,
                  builder: (BuildContext context, Widget? child) {
                    return Chip(
                      key: const Key('parse-count-chip'),
                      label: Text('Parses: ${_showcaseController.parseCount}'),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              key: const Key('theme-toggle-button'),
              onPressed: _toggleTheme,
              tooltip: _isDark ? 'Switch to light mode' : 'Switch to dark mode',
              icon: Icon(_isDark ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
        ),
        body: MarkdownTheme(
          data: markdownTheme,
          child: Column(
            children: <Widget>[
              if (_statusMessage != null)
                Container(
                  width: double.infinity,
                  color: scheme.secondaryContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: <Widget>[
                    _buildShowcaseTab(),
                    const _ExampleStreamingTab(chunks: _streamChunks),
                    _buildHooksTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (int idx) {
            setState(() {
              _tabIndex = idx;
            });
          },
          destinations: const <NavigationDestination>[
            NavigationDestination(
              key: Key('tab-showcase'),
              icon: Icon(Icons.article_outlined),
              label: 'Showcase',
            ),
            NavigationDestination(
              key: Key('tab-streaming'),
              icon: Icon(Icons.bolt_outlined),
              label: 'LLM Stream',
            ),
            NavigationDestination(
              key: Key('tab-hooks'),
              icon: Icon(Icons.extension_outlined),
              label: 'Custom Hooks',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowcaseTab() {
    return MarkdownView(
      _showcaseMarkdown,
      options: const MarkdownOptions.extended(),
      controller: _showcaseController,
      padding: const EdgeInsets.all(20.0),
      delegates: _showcaseDelegates,
    );
  }

  static const MarkdownBuilderDelegates _hooksDelegates =
      MarkdownBuilderDelegates(
        mathInlineBuilder: _buildCustomInlineMathChip,
        mathBlockBuilder: _buildCustomMathCallout,
        diagramBuilder: _buildCustomDiagramDecorator,
        codeBlockBuilder: _buildCustomCodeBlock,
      );

  Widget _buildHooksTab() {
    return const MarkdownView(
      _hooksMarkdown,
      options: MarkdownOptions.extended(),
      padding: EdgeInsets.all(20.0),
      delegates: _hooksDelegates,
    );
  }
}

InlineSpan _buildCustomInlineMathChip(
  BuildContext context,
  MathInlineNode node,
  TextStyle style,
  GestureRecognizer? linkRecognizer,
) {
  final MarkdownThemeData theme = MarkdownTheme.of(context);
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5.0),
        border: Border.all(color: theme.accent.withValues(alpha: 0.32)),
      ),
      child: Text(
        'TeX(${node.latex})',
        style: style.copyWith(
          color: theme.accent,
          fontWeight: FontWeight.w600,
          fontSize: (style.fontSize ?? theme.fontSize) * 0.88,
        ),
      ),
    ),
  );
}

Widget _buildCustomMathCallout(BuildContext context, MathBlockNode node) {
  final MarkdownThemeData theme = MarkdownTheme.of(context);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14.0),
    decoration: BoxDecoration(
      color: theme.accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8.0),
      border: Border.all(color: theme.accent.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          'Custom Display Math Hook',
          style: TextStyle(
            color: theme.accent,
            fontSize: 12.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6.0),
        Text(node.latex.trim(), style: theme.codeTextStyle()),
      ],
    ),
  );
}

Widget? _buildCustomDiagramDecorator(BuildContext context, CodeBlockNode node) {
  if (node.language != 'mermaid') {
    return null;
  }
  final MarkdownThemeData theme = MarkdownTheme.of(context);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14.0),
    decoration: BoxDecoration(
      color: theme.alertPalette.tip.background,
      borderRadius: BorderRadius.circular(8.0),
      border: Border.all(color: theme.alertPalette.tip.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Custom Diagram Decorator (mermaid)',
          style: TextStyle(
            color: theme.alertPalette.tip.foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6.0),
        Text(node.literal.trim(), style: theme.codeTextStyle()),
      ],
    ),
  );
}

Widget _buildCustomCodeBlock(BuildContext context, CodeBlockNode node) {
  final MarkdownThemeData theme = MarkdownTheme.of(context);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12.0),
    decoration: BoxDecoration(
      color: theme.codeBackground,
      borderRadius: BorderRadius.circular(8.0),
      border: Border.all(color: theme.accent.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Custom Code Hook (${node.language ?? 'plain'})',
          style: TextStyle(
            color: theme.accent,
            fontSize: 12.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6.0),
        Text(node.literal.trim(), style: theme.codeTextStyle()),
      ],
    ),
  );
}

final class _ExampleStreamingTab extends StatefulWidget {
  const _ExampleStreamingTab({required this.chunks});

  final List<String> chunks;

  @override
  State<_ExampleStreamingTab> createState() => _ExampleStreamingTabState();
}

final class _ExampleStreamingTabState extends State<_ExampleStreamingTab> {
  late final StreamingMarkdownController _streamController;
  Timer? _streamTimer;
  int _nextChunkIndex = 0;

  @override
  void initState() {
    super.initState();
    _streamController = StreamingMarkdownController(
      options: const MarkdownOptions.extended(),
    )..addListener(_onStreamChanged);
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _streamController
      ..removeListener(_onStreamChanged)
      ..dispose();
    super.dispose();
  }

  void _onStreamChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _stepStreamChunk() {
    if (_nextChunkIndex < widget.chunks.length) {
      _streamController.append(widget.chunks[_nextChunkIndex]);
      _nextChunkIndex++;
      if (_nextChunkIndex >= widget.chunks.length) {
        _streamController.finish();
        _streamTimer?.cancel();
        _streamTimer = null;
      }
      setState(() {});
    }
  }

  void _startAutoStream() {
    if (_nextChunkIndex >= widget.chunks.length) {
      _resetStream();
    }
    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(const Duration(milliseconds: 180), (
      Timer timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _stepStreamChunk();
      if (_nextChunkIndex >= widget.chunks.length) {
        timer.cancel();
      }
    });
    setState(() {});
  }

  void _resetStream() {
    _streamTimer?.cancel();
    _streamTimer = null;
    _nextChunkIndex = 0;
    _streamController.reset();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton(
                key: const Key('start-stream-button'),
                onPressed: _startAutoStream,
                child: const Text('Start Stream'),
              ),
              OutlinedButton(
                key: const Key('step-chunk-button'),
                onPressed: _nextChunkIndex < widget.chunks.length
                    ? _stepStreamChunk
                    : null,
                child: const Text('Step Chunk'),
              ),
              TextButton(
                key: const Key('reset-stream-button'),
                onPressed: _resetStream,
                child: const Text('Reset'),
              ),
              Text(
                'Settled: ${_streamController.settledBlockCount} · '
                'Active: ${_streamController.activeBlocks.length}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Divider(height: 1.0),
        Expanded(
          child: MarkdownView.streaming(
            controller: _streamController,
            padding: const EdgeInsets.all(20.0),
          ),
        ),
      ],
    );
  }
}
