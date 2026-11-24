# ![markdown_engine](doc/images/markdown_engine_logo.svg)

[![CI](https://img.shields.io/github/actions/workflow/status/tkinnis/markdown_engine/ci.yml?branch=main&label=CI&logo=github)](https://github.com/tkinnis/markdown_engine/actions/workflows/ci.yml) [![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-0ea5e9)](https://tkinnis.github.io/markdown_engine/) [![CommonMark 0.31.2](https://img.shields.io/badge/CommonMark%200.31.2-652%2F652-0284c7)](doc/COVERAGE.md) [![GFM 0.29.0](https://img.shields.io/badge/GFM%200.29.0.gfm.13-670%2F670%20%2B%2030%2F30-7c3aed)](doc/COVERAGE.md) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**`markdown_engine`** is a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, immutable sealed AST, HTML/plain-text/JSON exporter, incremental and streaming engine, and Flutter rendering suite built without a WebView or JavaScript runtime.

## Quick Start

### Pure Dart ([`markdown_engine`](packages/markdown_engine/README.md))

Install `markdown_engine` (requires Dart `^3.8.0`, `package:meta` as its sole runtime dependency):

```bash
dart pub add markdown_engine
```

Parse CommonMark, GFM, or extended Markdown synchronously into an immutable `MarkdownDocument` (`const MarkdownOptions()` enables all 23 extensions out of the box, while `.commonMark()` and `.gfm()` keep strict specification defaults) and export HTML, plain text, or JSON metadata:

```dart
import 'package:markdown_engine/markdown_engine.dart';

void main() {
  const MarkdownEngine engine = MarkdownEngine();
  final MarkdownDocument document = engine.parse('''
# Hello, Markdown

Supports **GFM tables**, ~~strikethrough~~, task lists, ==highlights==, math $E = mc^2$, and `code`.

- [x] CommonMark 0.31.2 parity
- [x] Incremental diff reuse & streaming
''');

  print(document.toHtml());
  print(document.outline.first.slug); // hello-markdown
}
```

### Flutter ([`markdown_engine_flutter`](packages/markdown_engine_flutter/README.md))

Install `markdown_engine_flutter` (requires Dart `^3.13.0` and Flutter `>=3.47.0`):

```bash
flutter pub add markdown_engine_flutter
```

Render Markdown with built-in native OpenType TeX math (`tex_math_flutter`), vector Mermaid diagrams (`pele_dart` + `vector_graphics`), zero-reparse theme switching, lazy sliver virtualization (`SliverMarkdownDocument`), outline navigation (`MarkdownController`), privacy-first remote image gating (`MarkdownImagePolicy`), and live streaming (`MarkdownView.streaming`):

```dart
import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

Widget buildMarkdownSample(BuildContext context, MarkdownController controller) {
  return MarkdownTheme(
    data: MarkdownThemeData.fromTheme(context),
    child: MarkdownView(
      '# Hello, Flutter Markdown\n\n> [!TIP]\n> Built natively with virtualized slivers.',
      controller: controller,
      delegates: MarkdownBuilderDelegates(
        imagePolicy: MarkdownImagePolicy.ask,
        onTapLink: (String destination, String? title) {
          if (destination.startsWith('#')) {
            controller.scrollToAnchor(destination.substring(1));
          }
        },
        onOpenWebLink: (Uri uri) {
          // Open validated http/https URIs externally.
        },
      ),
    ),
  );
}
```

Use `MarkdownView.document(document: preParsed)` alongside `MarkdownDocumentReader` (which implements `ValueListenable<MarkdownDocument>`, automatically offloads documents `>= 4096` code units to a background isolate with latest-wins coalescing, and falls back synchronously on `IsolateSpawnException`) or `MarkdownView.streaming(controller: streamController)` for zero-poll push-based token feeds. Pass an optional `focusNode` for keyboard Select-All (`Cmd+A`) and Copy across virtualized slivers.

## Incremental Editing & Streaming Feeds

### Incremental Document Diffing (`IncrementalMarkdownParser`)

Avoid full-document reparses in live editors by reusing blank-line-isolated unchanged prefix and suffix blocks with preserved `blockId` values, $O(1)$ edit-offset windowing (`editStartOffset`, `editOldEndOffset`, `editNewEndOffset`), and $O(1)$ lazy span shifting:

```dart
import 'package:markdown_engine/markdown_engine.dart';

void main() {
  const IncrementalMarkdownParser incremental = IncrementalMarkdownParser(
    engine: MarkdownEngine(defaultOptions: MarkdownOptions.gfm()),
  );

  final IncrementalParseResult first = incremental.parseIncremental(
    '# Architecture\n\nFirst paragraph.\n\nSecond paragraph.\n',
  );
  final IncrementalParseResult updated = incremental.parseIncremental(
    '# Architecture\n\nEdited paragraph.\n\nSecond paragraph.\n',
    previousResult: first,
    editStartOffset: 16,
    editOldEndOffset: 32,
    editNewEndOffset: 33,
  );

  print('Reused ${updated.reusedBlockCount} blocks, reparsed ${updated.reparsedBlockCount}.');
}
```

### Streaming Chunked Accumulation (`StreamingMarkdownController`)

Accumulate chunked responses (such as token-by-token SSE or LLM streams) while freezing settled prefix blocks (`settledBlocks`, aligned via `settledPrefixBlockCount`), notifying pure-Dart push listeners (`addListener`/`removeListener`), and re-parsing only the active trailing slice:

```dart
import 'package:markdown_engine/markdown_engine.dart';

void main() {
  final StreamingMarkdownController controller = StreamingMarkdownController(
    options: const MarkdownOptions.gfm(),
  );

  for (final String chunk in const <String>[
    '# Streaming ',
    'Guide\n\n',
    'Completed paragraph.\n\n',
    'Trailing *active* chunk.',
  ]) {
    final MarkdownDocument snapshot = controller.append(chunk);
    print('Settled: ${controller.settledBlockCount}, total: ${snapshot.blocks.length}');
  }

  final MarkdownDocument finalDoc = controller.finish();
  print(finalDoc.toHtml());
}
```

## Highlights & Security

* **Two-Phase CommonMark & GFM Engine**: Implements strict CommonMark `0.31.2` and `github/cmark-gfm 0.29.0.gfm.13` block structuring, flanking delimiter resolution, Unicode punctuation/case folding, HTML5 entities, pipe tables, strikethrough, task lists, autolinks, and `tagfilter`, powered by an ASCII structural lookup table (`LUT`) + single-backtick inline fast paths, linear text coalescing, and mid-paragraph / open-code streaming fast paths.
* **Complete Out-of-the-Box `MarkdownOptions()` & Strict Spec Presets**: Default `const MarkdownOptions()` enables all 23 extensions out of the box (`gfmTables`, `gfmStrikethrough`, `gfmTaskLists`, `gfmAutolinks`, `gfmTagFilter`, `footnotes`, `alerts`, `frontmatter`, `definitionLists`, `math`, `headingSlugs`, `highlight`, `subscript`, `superscript`, `emoji`, `smartPunctuation`, `explicitHeadingIds`, `detailsBlocks`, `figureBlocks`, `alignedBlocks`, `kbd`, `abbreviations`, `inlineBreaks` — all individually opt-out), while `MarkdownOptions.commonMark()` and `MarkdownOptions.gfm()` stay strictly specification-scoped (`MarkdownOptions.extended()` matches default `MarkdownOptions()`).
* **Dart 3 Sealed AST & Lazy Document Metadata**: 18 `MarkdownBlockNode` and 20 `MarkdownInlineNode` immutable sealed subtypes with pooled `blockId` identity, UTF-16 `SourceSpan` tracking, exhaustive `switch` support, and lazy `source`, `outline`, and `remoteImageAddresses` computation on `MarkdownDocument`.
* **Defense-in-Depth Security**: Enforces `MarkdownUrlPolicy.strict()` by default on `MarkdownOptions()` (with an ASCII URL fast path allowing `http`, `https`, `mailto`, relative, and `#fragment` URLs while blocking protocol-relative `//`, userinfo `@`, `javascript:`, `vbscript:`, unsafe `data:`, and Unicode/control-char obfuscated URIs), GFM `tagfilter`, a linear-time HTML5 state-machine sanitizer (`sanitizeHtml: true` stripping `<script>`, `<style>`, `<noscript>`, `<template>`, `<iframe>`, `<svg>`, `<math>`, `<form>`, `<meta>`, `on*` handlers, `srcdoc`, and unsafe CSS `url(...)`), bounded inline emphasis nesting, and `MarkdownBudgets` (`maxInputLength`, `maxNestingDepth`, `maxBlocks`, `maxTableColumns`, `maxTableRows`, `maxHtmlBytes`, `maxTokens`, `maxOutputBytes`). See [`SECURITY.md`](SECURITY.md).

* **Flutter Sliver Rendering Suite (`markdown_engine_flutter`)**: Built-in native OpenType TeX math (`tex_math_flutter`) and vector Mermaid diagrams (`pele_dart` + `vector_graphics`) with `MarkdownBuiltInRenderers.warmUp()`, default-on web-safe persistent background Mermaid worker (`usePersistentMermaidIsolate = true`, `isMermaidWorkerActive`, opt-out via `false` for one-shot `compute()`, and `dispose()`), and dual entry+byte LRU caches (`1,024` entries / `8 MiB` math and `128` entries / `16 MiB` Mermaid, configurable via `MarkdownBuiltInRenderers.configureCaches(...)` / `resetCacheDefaults()` with byte telemetry), zero-reparse Light/Dark `MarkdownTheme` switching (preserving math layouts and theming Mermaid palettes reactively), automatic incremental diffing inside `MarkdownView` edits, child widget memoization, fast simple-prose leaf rendering (`FastMarkdownText`, `MarkdownParagraphLeaf`, `MarkdownHorizontalOverflowBox`), lazy `SliverMarkdownDocument` virtualization keyed by `blockId` (`addAutomaticKeepAlives: true`), zero-poll hybrid two-sliver streaming tail canvas in `MarkdownView.streaming` (keeping settled `TexMath`, Mermaid, alerts, `<details>`, and custom builders frozen in `SliverMarkdownDocument` while streaming trailing prose/lists/tables on `MarkdownStreamingCanvasLeaf` with visible-viewport prefix `ui.Picture` reuse and cross-sliver `SelectionArea` selection), `WidgetsApp`-safe selection with full-document `Cmd+A` / Copy and excluded UI chrome, background isolate `ValueListenable` loading via `MarkdownDocumentReader`, `readingPlaceNotifier` & `scrollToAnchor` navigation via `MarkdownController`, `Semantics` & `FocusableActionDetector` accessibility, and `MarkdownImagePolicy` (`block`, `ask`, `load`) privacy controls.

## Built-In Ecosystem Integration & Custom Overrides

`markdown_engine_flutter` includes native OpenType TeX math and vector Mermaid diagram rendering out of the box without embedding a WebView, while keeping `MarkdownBuilderDelegates` open for opt-outs or custom overrides:

* **Built-In LaTeX Math ([`tex_math`](https://github.com/tkinnis/tex_math) / `tex_math_flutter`)**: Default `MarkdownOptions()` parses `$...$` / `\(...\)` into `MathInlineNode` and `$$...$$` / `\[...\]` into `MathBlockNode`, and `markdown_engine_flutter` renders both natively via `tex_math_flutter` (`NewCMMath-Regular.otf`, dual `1,024`-entry / `8 MiB` LRU cache, baseline inline alignment, `TexMathOverflow.scroll`, and safe error widgets). Call `MarkdownBuiltInRenderers.warmUp()` to pre-load the font off the UI thread, tune budgets with `MarkdownBuiltInRenderers.configureCaches(...)`, set `enableBuiltInMath: false` to restore monospace fallbacks, or supply `mathInlineBuilder` / `mathBlockBuilder` to override.
* **Built-In Mermaid Diagrams ([`pele_dart`](https://github.com/tkinnis/pele_dart))**: Fenced `mermaid` `CodeBlockNode`s render automatically via `pele_dart` + `vector_graphics` on a web-safe persistent pre-warmed background isolate by default (`MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true`, `isMermaidWorkerActive`, opt-out via `false` to shut down the worker immediately and use one-shot `compute()`, and `dispose()` for clean worker teardown) with dual `128`-entry / `16 MiB` LRU caching, theme-reactive `PelePalette` colors, and calm preview cards while streaming unclosed fences. Set `enableBuiltInMermaid: false` or provide a custom `MarkdownBuilderDelegates.diagramBuilder` (`(context, CodeBlockNode node)`) to override.
* **Desktop Viewer ([`Siren`](https://github.com/tkinnis/siren))**: Part of the pure-Dart Markdown, math, and diagram documentation toolchain alongside `tex_math`, `pele_dart`, and `siren`.

## Specification Parity & Native AOT Benchmarks

Verified offline against vendored upstream specifications tracked in [`REFERENCE.md`](REFERENCE.md) (`dart run tool/verify_spec.dart --strict` and [`doc/COVERAGE.md`](doc/COVERAGE.md)):

| Suite | Specification Fixture | Passed | Failed | Disabled | Total | Pass Rate |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: |
| `commonmark` | CommonMark `0.31.2` (`spec.json`) | 652 | 0 | 0 | 652 | **100.0%** |
| `gfm_spec` | `cmark-gfm 0.29.0.gfm.13` (`test/spec.txt`) | 670 | 0 | 2 | 672 | **100.0%** |
| `gfm_extensions` | `cmark-gfm 0.29.0.gfm.13` (`test/extensions.txt`) | 30 | 0 | 0 | 30 | **100.0%** |

Native Dart AOT timings on Apple M4 (`arm64`, macOS 15.6, Dart `3.13.5`) under `MarkdownOptions.gfm()` — see [`doc/BENCHMARKS.md`](doc/BENCHMARKS.md) for the full head-to-head scoreboard (`package:markdown`, `flutter_md`, `flutter_markdown_plus`), adversarial benchmarks, persistent vs one-shot Mermaid isolate measurements, hybrid mixed-content streaming telemetry, charts, real macOS `--profile` Impeller frame timings (`0.93 ms` scroll p50 / `0.43 ms` streaming p50, `0` jank frames), and CI regression ceilings:

| Workload | Payload | Mean | Median (p50) | Throughput (p50) | Highlights |
| :--- | ---: | ---: | ---: | ---: | :--- |
| `small_doc_parse_and_html` | 937 B (18 lines) | 8.76 us | **8.68 us** | 102.92 MB/s | Full GFM parse + `toHtml()` (`24.41x` vs `package:markdown`) |
| `medium_doc_parse_and_html` | 24.7 KB (479 lines) | 283.51 us | **286.44 us** | 84.05 MB/s | Sub-ms README parse + `toHtml()` (`20.95x` vs `package:markdown`) |
| `large_doc_5000_lines_parse` | 168.9 KB (4,996 lines) | 1.331 ms | **1.310 ms** | 125.90 MB/s | Full AST parse (`1,458` blocks, `34.06x` vs `package:markdown`) |
| `incremental_single_paragraph_edit` | 168.9 KB (4,996 lines) | 15.90 us | **14.92 us** | 11056.68 MB/s | **87.82x faster** vs own full parse, **1,457/1,458 (99.93%)** blocks reused |
| `streaming_llm_50_chunks_per_chunk` | 2.1 KB / 50 chunks | 1.15 us | **1.10 us** | 37.44 MB/s | Avg/chunk (`55.00 us` total, **14/15** settled, `241.76x` vs `package:markdown`) |

## Workspace Packages

| Component | Path | Role |
| :--- | :--- | :--- |
| **`markdown_engine`** | [`packages/markdown_engine/`](packages/markdown_engine/README.md) | Pure-Dart CommonMark/GFM parser, sealed AST, HTML/text/JSON exporters, extensions, incremental/streaming parsers, and security budgets (`meta` only, Dart `^3.8.0`). |
| **`markdown_engine_flutter`** | [`packages/markdown_engine_flutter/`](packages/markdown_engine_flutter/README.md) | Flutter `MarkdownView` (`.document`, `.streaming`), built-in `tex_math_flutter` math & `pele_dart` + `vector_graphics` Mermaid renderers (`MarkdownBuiltInRenderers`), virtualized `SliverMarkdownDocument`, `MarkdownTheme` / `MarkdownAlertPalette`, `MarkdownController`, `MarkdownDocumentReader` isolate loader, `MarkdownBuilderDelegates`, and `SelectionArea` (`>=3.47.0`, Dart `^3.13.0`). |
| **Flutter Example** | [`packages/markdown_engine_flutter/example/`](packages/markdown_engine_flutter/example/lib/main.dart) | Standalone Flutter application demonstrating `MarkdownView` and `MarkdownTheme`. |
| **Studio Workbench** | [`studio/`](studio/README.md) | macOS desktop comparison and inspection workbench (`>=3.47.0`, Dart `^3.13.0`). |
| **Verification Corpus** | [`corpus/`](corpus/README.md) | Vendored CommonMark `0.31.2` (`652` examples) and GFM `0.29.0.gfm.13` (`672` + `30` examples) fixtures plus extension, security, and streaming suites. |
| **Reference & Coverage** | [`REFERENCE.md`](REFERENCE.md) · [`doc/COVERAGE.md`](doc/COVERAGE.md) | Pinned upstream specifications, SHA-256 integrity hashes, and live spec compliance reports. |

## Documentation

| Guide | Description |
| :--- | :--- |
| **[Architecture & Design](doc/ARCHITECTURE.md)** | Two-phase CommonMark/GFM pipeline, sealed AST, HTML sanitizer, URL policy, incremental/streaming design, and Flutter separation. |
| **[API Manual](doc/API_MANUAL.md)** | Complete public API reference across `markdown_engine` and `markdown_engine_flutter`. |
| **[Studio Guide](doc/STUDIO_GUIDE.md)** | macOS workbench layout, headless widget tests, and CLI verification tools. |
| **[Reference Pins](REFERENCE.md)** | Pinned CommonMark `0.31.2` and `cmark-gfm` `0.29.0.gfm.13` specs and SHA-256 digests. |
| **[Coverage Matrix](doc/COVERAGE.md)** | Live CommonMark and GFM specification parity breakdown. |
| **[Benchmarks](doc/BENCHMARKS.md)** | Native Dart AOT measurements, incremental/streaming telemetry, charts, and regression ceilings. |
| **[Reference Sync](doc/REFERENCE_SYNC.md)** | Procedure for verifying and refreshing vendored specification fixtures. |
| **[Releasing](doc/RELEASING.md)** | Lockstep versioning checks, release tagging, and pub.dev publishing order. |
| **[Security Policy](SECURITY.md)** | Input budgets, URL scheme allowlisting, HTML sanitization, and vulnerability reporting. |

## License

* **`markdown_engine` & `markdown_engine_flutter`**: Copyright (c) 2026 Tony Kinnis — [MIT License](LICENSE).
