import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Entry point for the `markdown_engine_flutter` example application.
void main() {
  runApp(const MarkdownExampleApp());
}

/// Interactive standalone example showcasing zero-reparse Light/Dark switching,
/// virtualized GFM/extensions rendering, LLM streaming simulation, and
/// pluggable math/diagram/code hooks.
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
tags: [flutter, slivers, zero-reparse, streaming]
---

# Native Flutter Markdown Rendering

This document renders directly into Flutter slivers with **zero WebViews**, native `SelectionArea`, and **zero re-parses** when toggling Light and Dark themes.

> [!NOTE]
> Toggling the sun/moon theme button updates `MarkdownTheme` colors immediately while keeping `controller.parseCount` at `1`.

> [!TIP]
> Press <kbd>Cmd</kbd>+<kbd>C</kbd> after dragging across paragraphs, tables, or inline `code` spans to copy clean text.

> [!IMPORTANT]
> Unsafe links such as [blocked script](javascript:alert(1)) are strictly non-interactive at the Flutter rendering boundary.

> [!WARNING]
> Remote images default to `MarkdownImagePolicy.block` or `ask` so untrusted Markdown never leaks network requests.

> [!CAUTION]
> Always pass `MarkdownOptions.extended()` when enabling alerts, frontmatter, math, `<details>`, and abbreviations.

## GFM Table & Task List

| Capability | Alignment | Status |
| :--- | :---: | ---: |
| Sliver Virtualization | Center | Ready |
| Incremental Streaming | Center | Ready |
| URL & Image Gating | Center | Active |

- [x] CommonMark 0.31.2 & GFM 0.29 parity
- [x] Baseline-aligned inline math & `<kbd>` chips
- [ ] Connect your `tex_math_flutter` and `pele_dart` builders

## Collapsible Details, Definitions & Footnotes

<details>
<summary>Inspect interactive disclosure block</summary>

Expanded body content supports **rich formatting**, inline `code`, and ==highlighted text== with H~2~O and 2^10^ notation[^1].

</details>

`MarkdownView`
: Virtualized Flutter widget with default, `.document`, and `.streaming` constructors.

`SliverMarkdownDocument`
: Lazily builds visible top-level blocks keyed by `node.blockId`.

Visit [the project documentation](https://tkinnis.github.io/markdown_engine/) or inspect AST abbreviations with tooltip semantics.

*[AST]: Abstract Syntax Tree

![Remote Architecture Preview](https://example.com/architecture.png)

```dart
final MarkdownEngine engine = MarkdownEngine(
  defaultOptions: MarkdownOptions.extended(),
);
final MarkdownDocument doc = engine.parse('# Pure Dart');
```

[^1]: Footnotes automatically wire jump and return anchors inside `MarkdownController`.
''';

  static const String _hooksMarkdown = r'''
# Pluggable Math, Diagram & Code Hooks

Inline math plugs into `mathInlineBuilder` with alphabetic baseline alignment: Euler's identity $e^{i\pi} + 1 = 0$ sits inline with surrounding prose.

Display equations plug into `mathBlockBuilder`:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

Fenced diagram blocks (such as `mermaid`) route to `diagramBuilder` before falling back to `codeBlockBuilder`:

```mermaid
flowchart LR
  Source[Markdown Text] --> AST[Sealed AST]
  AST --> Sliver[SliverMarkdownDocument]
```

Non-diagram languages fall through cleanly to `codeBlockBuilder`:

```dart
Widget buildView(String source) {
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
    'while re-parsing only the active trailing slice.\n\n',
    '> [!TIP]\n> Settled blocks preserve their `blockId` keys across ',
    'every frame.\n\n',
    '| Phase | Behavior |\n| :--- | :--- |\n',
    '| Settled | Frozen immutable AST |\n',
    '| Active tail | Reparsed incrementally |\n\n',
    '```dart\nfinal controller = StreamingMarkdownController();\n',
    'controller.append(chunk);\n```\n',
  ];

  bool _isDark = false;
  int _tabIndex = 0;
  String? _statusMessage;

  late final MarkdownController _showcaseController;
  late final StreamingMarkdownController _streamController;
  late final ValueNotifier<int> _streamTick;
  Timer? _streamTimer;
  int _nextChunkIndex = 0;

  @override
  void initState() {
    super.initState();
    _showcaseController = MarkdownController();
    _streamController = StreamingMarkdownController(
      options: const MarkdownOptions.extended(),
    );
    _streamTick = ValueNotifier<int>(0);
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _showcaseController.dispose();
    _streamTick.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    setState(() {
      _isDark = !_isDark;
    });
  }

  void _stepStreamChunk() {
    if (_nextChunkIndex < _streamChunks.length) {
      _streamController.append(_streamChunks[_nextChunkIndex]);
      _nextChunkIndex++;
      if (_nextChunkIndex >= _streamChunks.length) {
        _streamController.finish();
        _streamTimer?.cancel();
        _streamTimer = null;
      }
      _streamTick.value++;
      setState(() {});
    }
  }

  void _startAutoStream() {
    if (_nextChunkIndex >= _streamChunks.length) {
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
      if (_nextChunkIndex >= _streamChunks.length) {
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
    _streamTick.value++;
    setState(() {});
  }

  void _setStatus(String message) {
    setState(() {
      _statusMessage = message;
    });
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
                    _buildStreamingTab(scheme),
                    _buildHooksTab(markdownTheme),
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
      delegates: MarkdownBuilderDelegates(
        imagePolicy: MarkdownImagePolicy.ask,
        onLoadRemoteImages: () =>
            _setStatus('Remote image load requested via ask policy.'),
        onTapLink: (String destination, String? title) =>
            _setStatus('Tapped safe link: $destination'),
      ),
    );
  }

  Widget _buildStreamingTab(ColorScheme scheme) {
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
                onPressed: _nextChunkIndex < _streamChunks.length
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
            listenable: _streamTick,
            pollInterval: null,
            padding: const EdgeInsets.all(20.0),
          ),
        ),
      ],
    );
  }

  Widget _buildHooksTab(MarkdownThemeData theme) {
    return MarkdownView(
      _hooksMarkdown,
      options: const MarkdownOptions.extended(),
      padding: const EdgeInsets.all(20.0),
      delegates: MarkdownBuilderDelegates(
        mathInlineBuilder:
            (
              BuildContext context,
              MathInlineNode node,
              TextStyle style,
              GestureRecognizer? linkRecognizer,
            ) {
              return WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5.0),
                  ),
                  child: Text(
                    'TeX(${node.latex})',
                    style: style.copyWith(
                      color: theme.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: (style.fontSize ?? theme.fontSize) * 0.9,
                    ),
                  ),
                ),
              );
            },
        mathBlockBuilder: (BuildContext context, MathBlockNode node) {
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
                Text(node.latex, style: theme.codeTextStyle()),
              ],
            ),
          );
        },
        diagramBuilder: (BuildContext context, CodeBlockNode node) {
          if (node.language != 'mermaid') {
            return null;
          }
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
                  'Diagram Hook (mermaid)',
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
        },
        codeBlockBuilder: (BuildContext context, CodeBlockNode node) {
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
        },
      ),
    );
  }
}
