# ![markdown_engine](doc/images/markdown_engine_logo.svg)

[![CI](https://img.shields.io/github/actions/workflow/status/tkinnis/markdown_engine/ci.yml?branch=main&label=CI&logo=github)](https://github.com/tkinnis/markdown_engine/actions/workflows/ci.yml) [![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-0ea5e9)](https://tkinnis.github.io/markdown_engine/) [![CommonMark 0.31.2](https://img.shields.io/badge/CommonMark%200.31.2-652%2F652-0284c7)](doc/COVERAGE.md) [![GFM 0.29.0](https://img.shields.io/badge/GFM%200.29.0.gfm.13-670%2F670%20%2B%2030%2F30-7c3aed)](doc/COVERAGE.md) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**`markdown_engine`** is a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, immutable syntax tree, exporter, incremental streaming engine, and Flutter rendering suite built without a WebView or JavaScript runtime.

## Quick Start

### Pure Dart ([`markdown_engine`](packages/markdown_engine/README.md))

Install `markdown_engine` (requires Dart `^3.8.0`, with `package:meta` as its sole runtime dependency):

```bash
dart pub add markdown_engine
```

Parse Markdown synchronously into an immutable `MarkdownDocument`, then export HTML, plain text, or JSON metadata. Default `const MarkdownOptions()` enables all 23 extensions out of the box, while `.commonMark()` and `.gfm()` enforce strict specification defaults.

```dart
import 'package:markdown_engine/markdown_engine.dart';

void main() {
  const MarkdownEngine engine = MarkdownEngine();
  final MarkdownDocument document = engine.parse(r'''
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

Render Markdown with native OpenType TeX math, offline vector Mermaid diagrams, zero-reparse Light/Dark themes, lazy sliver virtualization, outline navigation, and privacy-first image controls:

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

Choose the right entry point for your workload:

* **Inline source**: `MarkdownView(source)` parses once in widget state and applies incremental block diffing automatically on subsequent edits.
* **Pre-parsed or large files**: Pair `MarkdownView.document` with `MarkdownDocumentReader` to parse inputs of `4096` or more UTF-16 code units in a background isolate.
* **Live streams**: Bind `MarkdownView.streaming` to a `StreamingMarkdownController` for zero-poll push updates, and pass an optional `focusNode` for keyboard Select-All (`Cmd+A`) and Copy across slivers.

## Incremental Editing & Streaming Feeds

### Incremental Document Diffing (`IncrementalMarkdownParser`)

Avoid full-document reparses in live editors. `IncrementalMarkdownParser` isolates edited lines via constant-time edit offsets, reuses unchanged prefix and suffix AST blocks with stable `blockId` values, and shifts trailing spans lazily:

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

Accumulate chunked SSE or LLM responses while freezing settled prefix blocks in place. Listeners receive synchronous push notifications on every chunk while only the active trailing slice reparses:

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

* **Two-Phase CommonMark & GFM Engine**: Implements strict CommonMark `0.31.2` and `github/cmark-gfm 0.29.0.gfm.13` block structuring, flanking emphasis rules, Unicode punctuation, HTML5 entities, tables, strikethrough, task lists, autolinks, and `tagfilter`.
* **Complete Defaults & Strict Presets**: Default `MarkdownOptions()` enables all 23 extensions out of the box (each individually opt-out), while `.commonMark()` and `.gfm()` remain strictly specification-scoped.
* **Dart 3 Sealed AST**: Exposes 18 `MarkdownBlockNode` and 20 `MarkdownInlineNode` immutable subtypes with `SourceSpan` tracking, exhaustive `switch` support, and lazy `outline` and `remoteImageAddresses` getters.
* **Defense-in-Depth Security**: Enforces `MarkdownUrlPolicy.strict()` by default, GFM `tagfilter`, a linear-time HTML sanitizer (`sanitizeHtml: true`), bounded inline nesting, and configurable `MarkdownBudgets` caps. See [`SECURITY.md`](SECURITY.md).
* **Virtualized Flutter Rendering**: Materializes only visible blocks in `SliverMarkdownDocument`, switches Light/Dark themes with zero re-parses, and gates remote images via `MarkdownImagePolicy` (`block`, `ask`, `load`).
* **Native Math, Mermaid & Selection**: Includes built-in `tex_math_flutter` OpenType math, background-isolate `pele_dart` Mermaid rendering, cross-sliver `SelectionArea` support, and screen-reader `Semantics`.

## Built-In Ecosystem Integration & Custom Overrides

`markdown_engine_flutter` renders math formulas and Mermaid diagrams out of the box with no WebView or boilerplate builders, while keeping `MarkdownBuilderDelegates` open for overrides:

* **Built-In LaTeX Math ([`tex_math`](https://github.com/tkinnis/tex_math) / `tex_math_flutter`)**: Renders inline (`$...$`, `\(...\)`) and display (`$$...$$`, `\[...\]`) math natively using `NewCMMath-Regular.otf` and a dual-budget LRU cache (`1,024` entries / `8 MiB`). Set `enableBuiltInMath: false` or provide `mathInlineBuilder` / `mathBlockBuilder` to override.
* **Built-In Mermaid Diagrams ([`pele_dart`](https://github.com/tkinnis/pele_dart))**: Compiles fenced `mermaid` code blocks via `pele_dart` and `vector_graphics` on a bounded lazy burst worker isolate pool with theme-reactive palettes and a `128`-entry / `16 MiB` LRU cache. Call `MarkdownBuiltInRenderers.warmUp()` ahead of first paint, tune budgets via `configureCaches(...)`, set `enableBuiltInMermaid: false`, or supply `diagramBuilder` to customize.

## Specification Parity & Native AOT Benchmarks

Verified offline against vendored upstream specifications tracked in [`REFERENCE.md`](REFERENCE.md) via `dart run tool/verify_spec.dart --strict` (full report in [`doc/COVERAGE.md`](doc/COVERAGE.md)):

| Suite | Specification Fixture | Passed | Failed | Disabled | Total | Pass Rate |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: |
| `commonmark` | CommonMark `0.31.2` (`spec.json`) | 652 | 0 | 0 | 652 | **100.0%** |
| `gfm_spec` | `cmark-gfm 0.29.0.gfm.13` (`test/spec.txt`) | 670 | 0 | 2 | 672 | **100.0%** |
| `gfm_extensions` | `cmark-gfm 0.29.0.gfm.13` (`test/extensions.txt`) | 30 | 0 | 0 | 30 | **100.0%** |

Native Dart AOT measurements (`tool/compare/bin/compare_parsers_aot.dart`) on Apple M4 (`arm64`, macOS `15.6`, Dart `3.13.5`) under `MarkdownOptions.gfm()`. See [`doc/BENCHMARKS.md`](doc/BENCHMARKS.md) for the two-tier Flutter scoreboard (`package:markdown`, `flutter_md`, `flutter_markdown_plus`), adversarial benchmarks, Mermaid isolate measurements, macOS `--profile` Impeller frame timings (`0.77 ms` scroll p50 / `0.29 ms` streaming p50, `0` jank frames), and CI regression ceilings:

| Workload | Payload | Mean | Median (p50) | Throughput (p50) | Highlights |
| :--- | ---: | ---: | ---: | ---: | :--- |
| `small_doc_parse_and_html` | 937 B (18 lines) | 8.67 us | **8.52 us** | 104.91 MB/s | Full GFM parse + `toHtml()` (`23.87x` vs `package:markdown`; CI ceiling `<= 2.000 ms`) |
| `medium_doc_parse_and_html` | 24.7 KB (479 lines) | 277.29 us | **277.56 us** | 86.74 MB/s | Sub-ms README parse + `toHtml()` (`19.63x` vs `package:markdown`; CI ceiling `<= 30.000 ms`) |
| `large_doc_5000_lines_parse` | 168.9 KB (4,996 lines) | 1.313 ms | **1.290 ms** | 127.91 MB/s | Full AST parse (`1,458` blocks, `30.28x` vs `package:markdown`; CI ceiling `<= 200.000 ms`) |
| `incremental_single_paragraph_edit` | 168.9 KB (4,996 lines) | 15.22 us | **14.76 us** | 11176.53 MB/s | **87.38x faster** vs own full parse, **1,457/1,458 (99.93%)** blocks reused (CI ceiling `<= 25.000 ms`) |
| `streaming_llm_50_chunks_per_chunk` | 2.1 KB / 50 chunks | 0.87 us | **0.86 us** | 47.77 MB/s | Avg/chunk (`43.00 us` total, **14/15** settled, `264.38x` vs `package:markdown`; CI ceiling `<= 5.000 ms`) |

## Workspace Packages

| Component | Path | Role |
| :--- | :--- | :--- |
| **`markdown_engine`** | [`packages/markdown_engine/`](packages/markdown_engine/README.md) | Pure-Dart CommonMark/GFM parser, sealed AST, HTML/text/JSON exporters, incremental/streaming parsers, and security budgets (`meta` only, Dart `^3.8.0`). |
| **`markdown_engine_flutter`** | [`packages/markdown_engine_flutter/`](packages/markdown_engine_flutter/README.md) | Flutter `MarkdownView`, `SliverMarkdownDocument`, built-in math and Mermaid renderers, theming, `MarkdownController`, `MarkdownDocumentReader`, and selection (`>=3.47.0`, Dart `^3.13.0`). |
| **Flutter Example** | [`packages/markdown_engine_flutter/example/`](https://github.com/tkinnis/markdown_engine/blob/main/packages/markdown_engine_flutter/example/lib/main.dart) | Standalone Flutter application demonstrating `MarkdownView` and `MarkdownTheme`. |
| **Studio Workbench** | [`studio/`](studio/README.md) | macOS desktop comparison and inspection workbench (`>=3.47.0`, Dart `^3.13.0`). |
| **Verification Corpus** | [`corpus/`](corpus/README.md) | Vendored CommonMark `0.31.2` (`652` examples) and GFM `0.29.0.gfm.13` (`672` + `30` examples) fixtures plus extension, security, and streaming suites. |
| **Reference & Coverage** | [`REFERENCE.md`](REFERENCE.md) · [`doc/COVERAGE.md`](doc/COVERAGE.md) | Pinned upstream specifications, SHA-256 integrity hashes, and live spec compliance reports. |

## Documentation

| Guide | Description |
| :--- | :--- |
| **[Architecture & Design](doc/ARCHITECTURE.md)** | Two-phase CommonMark/GFM pipeline, sealed AST, HTML sanitizer, URL policy, incremental/streaming design, and Flutter rendering layers. |
| **[API Manual](doc/API_MANUAL.md)** | Complete public API reference across `markdown_engine` and `markdown_engine_flutter`. |
| **[Studio Guide](doc/STUDIO_GUIDE.md)** | macOS workbench layout, headless widget tests, and CLI verification tools. |
| **[Reference Pins](REFERENCE.md)** | Pinned CommonMark `0.31.2` and `cmark-gfm` `0.29.0.gfm.13` specs and SHA-256 digests. |
| **[Coverage Matrix](doc/COVERAGE.md)** | Live CommonMark and GFM specification parity breakdown. |
| **[Benchmarks](doc/BENCHMARKS.md)** | Native Dart AOT measurements, incremental/streaming telemetry, charts, and regression ceilings. |
| **[Reference Sync](doc/REFERENCE_SYNC.md)** | Procedure for checking upstream releases and refreshing vendored specification fixtures. |
| **[Releasing](doc/RELEASING.md)** | Lockstep versioning checks, release tagging, and pub.dev publishing order. |
| **[Security Policy](SECURITY.md)** | Input budgets, URL scheme allowlisting, HTML sanitization, and vulnerability reporting. |

## License

* **`markdown_engine` & `markdown_engine_flutter`**: Copyright (c) 2026 Tony Kinnis — [MIT License](LICENSE).
