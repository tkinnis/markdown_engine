# markdown_engine_flutter

[![CI](https://img.shields.io/github/actions/workflow/status/tkinnis/markdown_engine/ci.yml?branch=main&label=CI&logo=github)](https://github.com/tkinnis/markdown_engine/actions/workflows/ci.yml) [![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-0ea5e9)](https://tkinnis.github.io/markdown_engine/) [![CommonMark 0.31.2](https://img.shields.io/badge/spec-CommonMark%200.31.2-0284c7)](https://github.com/tkinnis/markdown_engine/blob/main/REFERENCE.md) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Pure-Dart Flutter sliver rendering widgets, widgets-first and Material theming, background isolate document reading, native text selection, security-gated links and images, and live streaming Markdown support built on [markdown_engine](https://github.com/tkinnis/markdown_engine/tree/main/packages/markdown_engine).

## Highlights

* **Zero-Reparse Theme Switching & Incremental Updates**: `MarkdownView` caches the parsed AST in widget state, reuses untouched blocks automatically via `IncrementalMarkdownParser` on `data` edits (preserving stateful block widgets such as `<details>`), and performs zero re-parses when `MarkdownTheme` flips Light/Dark modes.
* **Lazy Sliver Virtualization & Full-Document Selection**: `SliverMarkdownDocument` materializes only visible top-level blocks via `SliverChildBuilderDelegate` keyed by `node.blockId` (`addAutomaticKeepAlives: true`), works inside both `MaterialApp` (`SelectionArea`) and `WidgetsApp` (`SelectableRegion`), accepts an optional `focusNode`, excludes UI chrome (`Copy` buttons, bullets, alert badges) from selection, and exports full `document.toPlainText()` on `Cmd+A` / Select All across off-screen slivers.
* **Push-Based LLM Streaming**: `MarkdownView.streaming` subscribes directly to `StreamingMarkdownController.addListener` with zero polling timers, freezing settled prefix blocks while updating only the active trailing slice (including post-`finish()` `reset()` / `append()` reuse).
* **Background Isolate `ValueListenable` Reader**: `MarkdownDocumentReader` implements `ValueListenable<MarkdownDocument>` (`value`, `hasRead`), parses short inputs (`< 4096` UTF-16 code units) synchronously, offloads larger documents to `Isolate.run` with in-flight deduplication and latest-wins coalescing, and falls back synchronously on `IsolateSpawnException`.
* **Defense-in-Depth Security & Accessibility**: Enforces `MarkdownUrlPolicy` (defaulting to strict scheme/host checks) on interactive links and images, gates remote/external images via `MarkdownImagePolicy` (`block`, `ask`, `load` with `remoteImagesApproved` scoping per document), and provides screen-reader `Semantics` (`headingLevel`, table header traits, single-speak `<abbr>` tooltips, link traits) and keyboard `FocusableActionDetector` controls.
* **Rich Native Widgets**: Supports headings with anchor registration and `MarkdownController.readingPlaceNotifier` tracking, aligned GFM tables, task list checkboxes, all five GitHub Alerts (`NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`), YAML/TOML frontmatter cards, interactive collapsible `<details>`/`<summary>`, figures, aligned blocks, definition lists, footnotes with back-links, `<kbd>`, `<abbr>`, `<u>`/`<small>`/`<q>`, sized `<img width height>`, `<picture>`, and code blocks with language badges and copy buttons.

## Installation

Add `markdown_engine_flutter` with the Flutter CLI (requires Dart `^3.8.0` and Flutter `>=3.32.0`):

```bash
flutter pub add markdown_engine_flutter
```

Importing `package:markdown_engine_flutter/markdown_engine_flutter.dart` also re-exports core `markdown_engine` types (`MarkdownEngine`, `MarkdownOptions`, `MarkdownDocument`, `MarkdownUrlPolicy`, `StreamingMarkdownController`, and AST node types) in a single import.

## Quick Start

Wrap your subtree with `MarkdownTheme` (or inherit automatically from the ambient Material `Theme`) and render documents with `MarkdownView`:

```dart
import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

Widget buildReader(BuildContext context, MarkdownController controller) {
  return MarkdownTheme(
    data: MarkdownThemeData.fromTheme(context),
    child: MarkdownView(
      '# Hello, Flutter Markdown\n\n> [!TIP]\n> Built natively with slivers.',
      options: const MarkdownOptions.extended(),
      controller: controller,
      padding: const EdgeInsets.all(20.0),
      delegates: MarkdownBuilderDelegates(
        imagePolicy: MarkdownImagePolicy.ask,
        onTapLink: (String destination, String? title) {
          // Handle relative documents or internal anchors.
        },
        onOpenWebLink: (Uri uri) {
          // Open validated http/https URIs in an external browser.
        },
      ),
    ),
  );
}
```

Use `MarkdownView.document(document: preParsed)` to render a pre-parsed `MarkdownDocument` with zero parsing work inside the widget, or compose `SliverMarkdownDocument` directly inside your own `CustomScrollView`. For bounded cards, chat bubbles, or popovers, pass `scrollable: false`.

## Streaming LLM Responses

Bind `MarkdownView.streaming` directly to a `StreamingMarkdownController` for zero-poll push-driven UI updates as chunks arrive:

```dart
final StreamingMarkdownController stream = StreamingMarkdownController(
  options: const MarkdownOptions.extended(),
);

// Inside your build method:
Widget buildStreamingBubble() {
  return MarkdownView.streaming(
    controller: stream,
    padding: const EdgeInsets.all(16.0),
  );
}

// As tokens arrive:
void onToken(String chunk) {
  stream.append(chunk);
}

void onComplete() {
  stream.finish();
}
```

## Background Isolate Reading (`MarkdownDocumentReader`)

Offload large Markdown files (`>= 4096` code units by default) onto a background isolate with automatic latest-wins coalescing while keeping short edits synchronous:

```dart
final MarkdownDocumentReader reader = MarkdownDocumentReader(
  engine: const MarkdownEngine(defaultOptions: MarkdownOptions.extended()),
);

await reader.update(largeMarkdownText);

// Render the settled AST with zero parsing inside the widget:
Widget buildLoadedDocument() {
  return ListenableBuilder(
    listenable: reader,
    builder: (BuildContext context, Widget? child) {
      return MarkdownView.document(document: reader.document);
    },
  );
}
```

## Companion Adapters (`tex_math_flutter` & `pele_dart`)

Plug native math rendering from [tex_math_flutter](https://pub.dev/packages/tex_math_flutter) and native Mermaid diagrams from `pele_dart` directly into `MarkdownBuilderDelegates` without introducing WebViews or heavy dependencies:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
// import 'package:tex_math_flutter/tex_math_flutter.dart';
// import 'package:pele_dart/pele_dart.dart';

MarkdownBuilderDelegates buildEcosystemDelegates() {
  return MarkdownBuilderDelegates(
    mathInlineBuilder: (
      BuildContext context,
      MathInlineNode node,
      TextStyle style,
      GestureRecognizer? linkRecognizer,
    ) {
      // With tex_math_flutter:
      // return TexMathSpan(node.latex, style: style);
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Text(node.latex, style: style),
      );
    },
    mathBlockBuilder: (BuildContext context, MathBlockNode node) {
      // With tex_math_flutter:
      // return TexMath(node.latex, overflow: TexMathOverflow.scroll);
      return Text(node.latex);
    },
    diagramBuilder: (BuildContext context, CodeBlockNode node) {
      if (node.language == 'mermaid') {
        // With pele_dart:
        // return PeleMermaidDiagram(source: node.literal);
        return Text('Mermaid diagram (${node.literal.length} chars)');
      }
      return null;
    },
  );
}
```

## License & Documentation

* **`markdown_engine_flutter`**: Copyright (c) 2026 Tony Kinnis — [MIT License](LICENSE).
* [Repository README](https://github.com/tkinnis/markdown_engine/blob/main/README.md) · [API Manual](https://github.com/tkinnis/markdown_engine/blob/main/doc/API_MANUAL.md) · [Architecture](https://github.com/tkinnis/markdown_engine/blob/main/doc/ARCHITECTURE.md)
