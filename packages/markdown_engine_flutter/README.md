# markdown_engine_flutter

[![CI](https://img.shields.io/github/actions/workflow/status/tkinnis/markdown_engine/ci.yml?branch=main&label=CI&logo=github)](https://github.com/tkinnis/markdown_engine/actions/workflows/ci.yml) [![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-0ea5e9)](https://tkinnis.github.io/markdown_engine/) [![CommonMark 0.31.2](https://img.shields.io/badge/spec-CommonMark%200.31.2-0284c7)](https://github.com/tkinnis/markdown_engine/blob/main/REFERENCE.md) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](https://github.com/tkinnis/markdown_engine/blob/main/packages/markdown_engine_flutter/LICENSE)

Flutter rendering widgets, built-in OpenType TeX math (`tex_math_flutter`) and vector Mermaid diagrams (`pele_dart`), Material and widgets-first theming, background isolate loading, native text selection, and live streaming support built on [`markdown_engine`](https://pub.dev/packages/markdown_engine).

## Highlights

* **Built-In Math & Mermaid**: Renders inline and display LaTeX math via `tex_math_flutter` and fenced `mermaid` blocks via `pele_dart` + `vector_graphics` out of the box with dual-budget LRU caching and zero boilerplate builders.
* **Zero-Reparse Theme Switching**: Caches parsed AST blocks across widget updates and re-derives colors and Mermaid palettes reactively when `MarkdownTheme` switches between Light and Dark modes.
* **Lazy Sliver Virtualization**: `SliverMarkdownDocument` materializes only visible blocks keyed by `blockId`, preserves stateful `<details>` disclosures and active selections off-screen, and caches block extents for smooth scrolling.
* **Push-Based Streaming Views**: `MarkdownView.streaming` binds directly to `StreamingMarkdownController` without polling timers, freezing settled rich blocks in place while streaming trailing text cleanly.
* **Background Isolate Document Reader**: `MarkdownDocumentReader` implements `ValueListenable<MarkdownDocument>`, parsing short texts synchronously and offloading inputs of `4096` or more code units to an isolate with latest-wins coalescing.
* **Full-Document Selection & Accessibility**: Integrates with `SelectionArea` (`MaterialApp`) and `SelectableRegion` (`WidgetsApp`), excludes UI chrome from copies, supports `Cmd+A` across off-screen slivers, and exposes screen-reader `Semantics`.
* **Defense-in-Depth Security**: Enforces `MarkdownUrlPolicy` on interactive links and gates remote images via `MarkdownImagePolicy` (`block`, `ask`, `load`) per document.
* **Rich Native Widgets**: Renders headings with anchor navigation, GFM tables, task lists, GitHub alerts, frontmatter cards, `<details>`, `<figure>`, definition lists, footnotes, `<kbd>`, `<abbr>` tooltips, `<picture>`, and HTML tables/blocks natively.

## Installation

Add `markdown_engine_flutter` with the Flutter CLI (requires Dart `^3.13.0` and Flutter `>=3.47.0`):

```bash
flutter pub add markdown_engine_flutter
```

Importing `package:markdown_engine_flutter/markdown_engine_flutter.dart` also re-exports core types from `markdown_engine` (`MarkdownEngine`, `MarkdownOptions`, `MarkdownDocument`, `MarkdownUrlPolicy`, `StreamingMarkdownController`, and AST nodes) in a single import.

## Quick Start

Wrap your subtree with `MarkdownTheme` (or inherit from Material `Theme`) and render documents with `MarkdownView`:

```dart
import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

Widget buildReader(BuildContext context, MarkdownController controller) {
  return MarkdownTheme(
    data: MarkdownThemeData.fromTheme(context),
    child: MarkdownView(
      '# Hello, Flutter Markdown\n\n> [!TIP]\n> Built natively with slivers.',
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

Use `MarkdownView.document(document: preParsed)` to display a pre-parsed `MarkdownDocument` with zero parsing work inside the widget, or compose `SliverMarkdownDocument` inside your own `CustomScrollView`. For bounded cards, chat bubbles, or popovers, pass `scrollable: false`.

## Streaming LLM Responses

Bind `MarkdownView.streaming` directly to a `StreamingMarkdownController` for zero-poll push-driven UI updates as chunks arrive:

```dart
final StreamingMarkdownController stream = StreamingMarkdownController();

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

Offload large Markdown files (`>= 4096` UTF-16 code units by default) onto a background isolate with automatic latest-wins coalescing while keeping short edits synchronous:

```dart
final MarkdownDocumentReader reader = MarkdownDocumentReader();

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

`markdown_engine_flutter` renders inline (`$...$`, `\(...\)`) and display (`$$...$$`, `\[...\]`) TeX formulas alongside fenced `mermaid` code blocks automatically. Pre-warm the font and diagram registry at startup, disable either built-in renderer, or supply custom builders via `MarkdownBuilderDelegates`:

```dart
import 'dart:async' show unawaited;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

void initMarkdownRenderers() {
  // Optional: pre-loads NewCMMath-Regular.otf and primes pele_dart off the UI thread.
  unawaited(MarkdownBuiltInRenderers.warmUp());
}

// Disable built-in renderers to fall back to raw monospace chips and code blocks:
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

### Mermaid Worker Pool & Cache Controls

When `MarkdownBuiltInRenderers.usePersistentMermaidIsolate` is `true` (default), cold Mermaid compiles use one persistent pre-warmed primary isolate for sequential renders and lazily spin up auxiliary burst isolates up to `maxMermaidConcurrentWorkers` on concurrent load. Burst isolates tear down automatically after `15` seconds idle, while web targets fall back safely to `compute()`.

| Member | Type / Signature | Default & Behavior |
| :--- | :--- | :--- |
| `usePersistentMermaidIsolate` | `static bool` | `true` by default. Setting `false` shuts down all active workers immediately and routes cold compiles to one-shot `compute()`. |
| `defaultMaxMermaidConcurrentWorkers` | `static int get` | Platform cap: `min(4, max(1, Platform.numberOfProcessors - 1))` on IO (`1` primary + up to `3` burst) and `1` on web. |
| `maxMermaidConcurrentWorkers` | `static int` | Defaults to `defaultMaxMermaidConcurrentWorkers`. Throws `RangeError` if `< 1`; `1` disables auxiliary burst workers. |
| `activeMermaidWorkerCount` | `static int get` | Active or starting primary and burst worker isolates (`0` when stopped or on web). |
| `isMermaidWorkerActive` | `static bool get` | `true` when `activeMermaidWorkerCount > 0`. |
| `warmUp()` | `static Future<void>` | Pre-loads `NewCMMath-Regular.otf` and primes `pele_dart` (spawning only the persistent primary isolate when enabled). |
| `configureCaches(...)` | `static void` | Tunes LRU limits (defaults: `1,024` entries / `8 MiB` math; `128` entries / `16 MiB` Mermaid) and evicts excess entries. |
| `resetCacheDefaults()` / `clearCaches()` | `static void` | Restores default LRU budgets or clears cached entries and telemetry counters. |
| `dispose()` | `static Future<void>` | Shuts down all active workers, cancels idle timers, and clears pending compile state without changing `usePersistentMermaidIsolate`. |

Inspect live cache usage and hit ratios anytime via `mathCacheBytes`, `mathCacheLength`, `mathCacheHitCount`, `mathLayoutCount`, `mermaidCacheBytes`, `mermaidCacheLength`, `mermaidCacheHitCount`, and `mermaidRenderCount`.

## License & Documentation

* **`markdown_engine_flutter`**: Copyright (c) 2026 Tony Kinnis — [MIT License](https://github.com/tkinnis/markdown_engine/blob/main/packages/markdown_engine_flutter/LICENSE).
* [Repository README](https://github.com/tkinnis/markdown_engine/blob/main/README.md) · [API Manual](https://github.com/tkinnis/markdown_engine/blob/main/doc/API_MANUAL.md) · [Architecture](https://github.com/tkinnis/markdown_engine/blob/main/doc/ARCHITECTURE.md) · [Coverage Matrix](https://github.com/tkinnis/markdown_engine/blob/main/doc/COVERAGE.md) · [Benchmarks](https://github.com/tkinnis/markdown_engine/blob/main/doc/BENCHMARKS.md) · [Security Policy](https://github.com/tkinnis/markdown_engine/blob/main/SECURITY.md)
