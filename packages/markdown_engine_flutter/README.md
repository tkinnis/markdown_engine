# markdown_engine_flutter

[![CI](https://img.shields.io/github/actions/workflow/status/tkinnis/markdown_engine/ci.yml?branch=main&label=CI&logo=github)](https://github.com/tkinnis/markdown_engine/actions/workflows/ci.yml) [![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-0ea5e9)](https://tkinnis.github.io/markdown_engine/) [![CommonMark 0.31.2](https://img.shields.io/badge/spec-CommonMark%200.31.2-0284c7)](https://github.com/tkinnis/markdown_engine/blob/main/REFERENCE.md) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Pure-Dart Flutter sliver rendering widgets, built-in native OpenType TeX math (`tex_math_flutter`) and vector Mermaid diagrams (`pele_dart` + `vector_graphics`), widgets-first and Material theming, background isolate document reading, native text selection, security-gated links and images, and live streaming Markdown support built on [markdown_engine](https://github.com/tkinnis/markdown_engine/tree/main/packages/markdown_engine).

## Highlights

* **Out-of-the-Box LaTeX Math & Vector Mermaid Diagrams**: With default `MarkdownOptions()` (`math: true`) and `MarkdownBuilderDelegates` (`enableBuiltInMath: true`, `enableBuiltInMermaid: true`), inline (`$...$`, `\(...\)`) and display (`$$...$$`, `\[...\]`) TeX math renders natively via `tex_math_flutter` (`TexMath` + `NewCMMath-Regular.otf`) and fenced `mermaid` code blocks compile via `pele_dart` + `vector_graphics` (`VectorGraphic`) in background isolates with zero custom builder boilerplate, bounded LRU caches (`256` math / `128` Mermaid), calm streaming preview cards for unclosed Mermaid fences, and safe fallback widgets for invalid syntax.
* **Zero-Reparse Theme Switching & Block Memoization**: `MarkdownView` caches the parsed AST in widget state, reuses untouched blocks automatically via `IncrementalMarkdownParser` on `data` edits (preserving stateful block widgets such as `<details>`), memoizes top-level block and inline `RichText` subtrees, derives `TexMathThemeData` and `PelePalette` reactively from `MarkdownThemeData`, and performs zero re-parses or TeX relayouts when `MarkdownTheme` flips Light/Dark modes.
* **Lazy Sliver Virtualization & Full-Document Selection**: `SliverMarkdownDocument` materializes only visible top-level blocks via `SliverChildBuilderDelegate` keyed by `node.blockId` (`addAutomaticKeepAlives: true`), works inside both `MaterialApp` (`SelectionArea`) and `WidgetsApp` (`SelectableRegion`), accepts an optional `focusNode`, excludes UI chrome (`Copy` buttons, bullets, alert badges) from selection, and exports full `document.toPlainText()` on `Cmd+A` / Select All across off-screen slivers.
* **Push-Based Split-Sliver LLM Streaming**: `MarkdownView.streaming` subscribes directly to `StreamingMarkdownController.addListener` with zero polling timers and splits `CustomScrollView` into a settled-prefix `SliverMarkdownDocument` (aligned to `settledPrefixBlockCount`) plus a dedicated active tail sliver so trailing token appends never rebuild settled blocks (including post-`finish()` `reset()` / `append()` reuse).
* **Background Isolate `ValueListenable` Reader**: `MarkdownDocumentReader` implements `ValueListenable<MarkdownDocument>` (`value`, `hasRead`), parses short inputs (`< 4096` UTF-16 code units) synchronously, offloads larger documents to `Isolate.run` with in-flight deduplication and latest-wins coalescing, and falls back synchronously on `IsolateSpawnException`.
* **Defense-in-Depth Security & Accessibility**: Enforces `MarkdownUrlPolicy` (defaulting to strict scheme/host checks) on interactive links and images, gates remote/external images via `MarkdownImagePolicy` (`block`, `ask`, `load` with `remoteImagesApproved` scoping per document), and provides screen-reader `Semantics` (`headingLevel`, table header traits, spoken TeX labels, SVG `aria-label` diagram semantics, single-speak `<abbr>` tooltips, link traits) and keyboard `FocusableActionDetector` controls.
* **Rich Native Widgets**: Supports headings with anchor registration and `MarkdownController.readingPlaceNotifier` tracking, aligned GFM tables, task list checkboxes, all five GitHub Alerts (`NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`), YAML/TOML frontmatter cards, interactive collapsible `<details>`/`<summary>`, figures, aligned blocks, definition lists, footnotes with back-links, `<kbd>`, `<abbr>`, `<u>`/`<small>`/`<q>`, sized `<img width height>`, `<picture>`, and code blocks with language badges and copy buttons.

## Installation

Add `markdown_engine_flutter` with the Flutter CLI (requires Dart `^3.13.0` and Flutter `>=3.47.0`):

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

## Built-In Math & Mermaid Rendering (`MarkdownBuiltInRenderers`)

`markdown_engine_flutter` renders inline (`$...$`, `\(...\)`), display (`$$...$$`, `\[...\]`) TeX formulas and fenced `mermaid` code blocks automatically without configuring `mathInlineBuilder`, `mathBlockBuilder`, or `diagramBuilder`. Optionally pre-warm the OpenType math font and `pele_dart` diagram registry at startup, opt out via `enableBuiltInMath` / `enableBuiltInMermaid`, or override individual builders:

```dart
import 'dart:async' show unawaited;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

void initMarkdownRenderers() {
  // Optional: pre-loads NewCMMath-Regular.otf and primes pele_dart off the UI thread.
  unawaited(MarkdownBuiltInRenderers.warmUp());
}

// Disable built-in renderers to fall back to raw monospace chips/code blocks:
const MarkdownBuilderDelegates rawFallbackDelegates = MarkdownBuilderDelegates(
  enableBuiltInMath: false,
  enableBuiltInMermaid: false,
);

// Or override individual math / diagram renderers (custom builders take precedence):
MarkdownBuilderDelegates buildCustomOverrideDelegates() {
  return MarkdownBuilderDelegates(
    mathInlineBuilder: (
      BuildContext context,
      MathInlineNode node,
      TextStyle style,
      GestureRecognizer? linkRecognizer,
    ) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Text(node.latex, style: style),
      );
    },
    mathBlockBuilder: (BuildContext context, MathBlockNode node) {
      return Text(node.latex);
    },
    diagramBuilder: (BuildContext context, CodeBlockNode node) {
      if (node.language == 'graphviz') {
        return Text('Custom diagram (${node.literal.length} chars)');
      }
      // Returning null keeps built-in Mermaid rendering for `mermaid` fences.
      return null;
    },
  );
}
```

Use `MarkdownBuiltInRenderers.clearCaches()` and `MarkdownBuiltInRenderers.dispose()` during teardown or tests to release cached math display lists (`256` max entries), compiled Mermaid `vector_graphics` payloads (`128` max entries), and pending compilation state.

## License & Documentation

* **`markdown_engine_flutter`**: Copyright (c) 2026 Tony Kinnis — [MIT License](LICENSE).
* [Repository README](https://github.com/tkinnis/markdown_engine/blob/main/README.md) · [API Manual](https://github.com/tkinnis/markdown_engine/blob/main/doc/API_MANUAL.md) · [Architecture](https://github.com/tkinnis/markdown_engine/blob/main/doc/ARCHITECTURE.md)
