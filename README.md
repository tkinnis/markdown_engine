# ![markdown_engine](doc/images/markdown_engine_logo.svg)

[![CI](https://img.shields.io/github/actions/workflow/status/tkinnis/markdown_engine/ci.yml?branch=main&label=CI&logo=github)](https://github.com/tkinnis/markdown_engine/actions/workflows/ci.yml) [![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-0ea5e9)](https://tkinnis.github.io/markdown_engine/) [![CommonMark 0.31.2](https://img.shields.io/badge/CommonMark%200.31.2-652%2F652-0284c7)](doc/COVERAGE.md) [![GFM 0.29.0](https://img.shields.io/badge/GFM%200.29.0.gfm.13-670%2F670%20%2B%2030%2F30-7c3aed)](doc/COVERAGE.md) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**`markdown_engine`** is a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, immutable sealed AST, HTML/plain-text/JSON exporter, incremental and streaming engine, and Flutter rendering suite built without a WebView or JavaScript runtime.

## Quick Start

### Pure Dart ([`markdown_engine`](packages/markdown_engine/README.md))

Install `markdown_engine` (requires Dart `^3.8.0`, `package:meta` as its sole runtime dependency):

```bash
dart pub add markdown_engine
```

Parse CommonMark, GFM, or extended Markdown synchronously into an immutable `MarkdownDocument` and export HTML, plain text, or JSON metadata:

```dart
import 'package:markdown_engine/markdown_engine.dart';

void main() {
  const MarkdownEngine engine = MarkdownEngine(
    defaultOptions: MarkdownOptions.gfm(),
  );
  final MarkdownDocument document = engine.parse('''
# Hello, Markdown

Supports **GFM tables**, ~~strikethrough~~, task lists, and `code`.

- [x] CommonMark 0.31.2 parity
- [x] Incremental diff reuse & streaming
''');

  print(document.toHtml());
  print(document.outline.first.slug); // hello-markdown
}
```

### Flutter ([`markdown_engine_flutter`](packages/markdown_engine_flutter/README.md))

Install `markdown_engine_flutter` (requires Dart `^3.8.0` and Flutter `>=3.32.0`):

```bash
flutter pub add markdown_engine_flutter
```

Render Markdown with zero-reparse theme switching, lazy sliver virtualization (`SliverMarkdownDocument`), outline navigation (`MarkdownController`), privacy-first remote image gating (`MarkdownImagePolicy`), and live streaming (`MarkdownView.streaming`):

```dart
import 'package:flutter/material.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

Widget buildMarkdownSample(BuildContext context, MarkdownController controller) {
  return MarkdownTheme(
    data: MarkdownThemeData.fromTheme(context),
    child: MarkdownView(
      '# Hello, Flutter Markdown\n\n> [!TIP]\n> Built natively with virtualized slivers.',
      options: const MarkdownOptions.extended(),
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

Use `MarkdownView.document(document: preParsed)` alongside `MarkdownDocumentReader` (which automatically offloads documents `>= 4096` code units to a background isolate with latest-wins coalescing) or `MarkdownView.streaming(controller: streamController)` for live token feeds.

## Incremental Editing & Streaming Feeds

### Incremental Document Diffing (`IncrementalMarkdownParser`)

Avoid full-document reparses in live editors by reusing blank-line-isolated unchanged prefix and suffix blocks with preserved `blockId` values and shifted UTF-16 `SourceSpan`s:

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
  );

  print('Reused ${updated.reusedBlockCount} blocks, reparsed ${updated.reparsedBlockCount}.');
}
```

### Streaming Chunked Accumulation (`StreamingMarkdownController`)

Accumulate chunked responses (such as token-by-token SSE or LLM streams) while freezing settled prefix blocks (`settledBlocks`) and re-parsing only the active trailing slice:

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

* **Two-Phase CommonMark & GFM Engine**: Implements strict CommonMark `0.31.2` and `github/cmark-gfm 0.29.0.gfm.13` block structuring, flanking delimiter resolution, Unicode punctuation/case folding, HTML5 entities, pipe tables, strikethrough, task lists, autolinks, and `tagfilter`.
* **Rich Opt-In Extensions**: `MarkdownOptions.extended()` enables YAML/TOML frontmatter, GitHub alerts (`[!NOTE]`–`[!CAUTION]`), footnotes, PHP Markdown Extra definition lists, inline/display LaTeX math (`$...$` / `$$...$$`), highlight (`==mark==`), subscript (`~sub~`), superscript (`^sup^`), emoji shortcodes, smart punctuation, explicit heading IDs (`{#id}`), `<details>`, `<figure>`, `<div align="...">`, `<kbd>`, `<abbr>`, and `<picture>`.
* **Dart 3 Sealed AST**: 18 `MarkdownBlockNode` and 20 `MarkdownInlineNode` immutable sealed subtypes with stable `blockId` identity, UTF-16 `SourceSpan` tracking, and exhaustive `switch` support.
* **Defense-in-Depth Security**: Enforces `MarkdownUrlPolicy` (control-character stripping, default blocking of `javascript:`, `vbscript:`, and `data:`, optional scheme/host allowlists, and opt-in raster image data URIs), GFM `tagfilter`, deep HTML sanitization (`sanitizeHtml: true` stripping `<script>`, `<iframe>`, `<svg>`, `<math>`, `on*` handlers, `srcdoc`, and unsafe inline CSS), and `MarkdownBudgets` (`maxInputLength`, `maxNestingDepth`, `maxBlocks`, `maxTableColumns`, `maxTableRows`, `maxHtmlBytes`, `maxTokens`). See [`SECURITY.md`](SECURITY.md).

* **Flutter Sliver Rendering Suite (`markdown_engine_flutter`)**: Zero-reparse Light/Dark `MarkdownTheme` switching (`MarkdownThemeData.light()`/`.dark()`/`.fromTheme()`), lazy `SliverMarkdownDocument` virtualization keyed by `blockId`, `MarkdownView.document` and `MarkdownView.streaming`, background isolate loading via `MarkdownDocumentReader`, outline/anchor navigation via `MarkdownController` & `MarkdownReadingPlace`, and `MarkdownImagePolicy` (`block`, `ask`, `load`) privacy controls.

## Companion Ecosystem Integration

`markdown_engine` and `markdown_engine_flutter` compose cleanly with pure-Dart companion renderers via `MarkdownBuilderDelegates` without embedding a WebView:

* **LaTeX Math ([`tex_math`](https://github.com/tkinnis/tex_math) / `tex_math_flutter`)**: Enable `MarkdownOptions(math: true)` to parse `$...$` into `MathInlineNode` and `$$...$$` into `MathBlockNode`, then plug `TexMathSpan` into `MarkdownBuilderDelegates.mathInlineBuilder` (`(context, node, style, linkRecognizer)`) and `TexMath` into `mathBlockBuilder` (`(context, node)`) for OpenType `MATH` vector typesetting.
* **Mermaid Diagrams ([`pele_dart`](https://github.com/tkinnis/pele_dart))**: Plug a `MarkdownBuilderDelegates.diagramBuilder` (`(context, CodeBlockNode node)`) matching `node.language == 'mermaid'` to render `node.literal` synchronously to standalone SVG in pure Dart.
* **Desktop Viewer ([`Siren`](https://github.com/tkinnis/siren))**: Part of the pure-Dart Markdown, math, and diagram documentation toolchain alongside `tex_math`, `pele_dart`, and `siren`.

## Specification Parity & Native AOT Benchmarks

Verified offline against vendored upstream specifications tracked in [`REFERENCE.md`](REFERENCE.md) (`dart run tool/verify_spec.dart --strict` and [`doc/COVERAGE.md`](doc/COVERAGE.md)):

| Suite | Specification Fixture | Passed | Failed | Disabled | Total | Pass Rate |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: |
| `commonmark` | CommonMark `0.31.2` (`spec.json`) | 652 | 0 | 0 | 652 | **100.0%** |
| `gfm_spec` | `cmark-gfm 0.29.0.gfm.13` (`test/spec.txt`) | 670 | 0 | 2 | 672 | **100.0%** |
| `gfm_extensions` | `cmark-gfm 0.29.0.gfm.13` (`test/extensions.txt`) | 30 | 0 | 0 | 30 | **100.0%** |

Native Dart AOT timings on Apple M4 (`arm64`, macOS 15.6, Dart `3.13.5`) under `MarkdownOptions.gfm()` — see [`doc/BENCHMARKS.md`](doc/BENCHMARKS.md) for methodology, charts, and CI regression ceilings:

| Workload | Payload | Mean | Median (p50) | Throughput (p50) | Highlights |
| :--- | ---: | ---: | ---: | ---: | :--- |
| `small_doc_parse_and_html` | 937 B (18 lines) | 28.30 us | **27.80 us** | 32.15 MB/s | Full GFM parse + `toHtml()` |
| `medium_doc_parse_and_html` | 24.7 KB (479 lines) | 1.060 ms | **999.36 us** | 24.09 MB/s | Sub-ms README parse + `toHtml()` |
| `large_doc_5000_lines_parse` | 168.9 KB (4,996 lines) | 7.038 ms | **7.013 ms** | 23.52 MB/s | Full AST parse (1,458 blocks) |
| `incremental_single_paragraph_edit` | 168.9 KB (4,996 lines) | 1.717 ms | **1.747 ms** | 94.43 MB/s | **4.01x faster**, **1,457/1,458 (99.93%)** blocks reused |
| `streaming_llm_50_chunks_per_chunk` | 2.1 KB / 50 chunks | 13.18 us | **13.29 us** | 3.09 MB/s | Avg/chunk (`664.50 us` total, **14/15** settled) |

## Workspace Packages

| Component | Path | Role |
| :--- | :--- | :--- |
| **`markdown_engine`** | [`packages/markdown_engine/`](packages/markdown_engine/README.md) | Pure-Dart CommonMark/GFM parser, sealed AST, HTML/text/JSON exporters, extensions, incremental/streaming parsers, and security budgets (`meta` only, Dart `^3.8.0`). |
| **`markdown_engine_flutter`** | [`packages/markdown_engine_flutter/`](packages/markdown_engine_flutter/README.md) | Flutter `MarkdownView` (`.document`, `.streaming`), virtualized `SliverMarkdownDocument`, `MarkdownTheme` / `MarkdownAlertPalette`, `MarkdownController`, `MarkdownDocumentReader` isolate loader, `MarkdownBuilderDelegates`, and `SelectionArea` (`>=3.32.0`, Dart `^3.8.0`). |
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
