# markdown_engine

[![CI](https://img.shields.io/github/actions/workflow/status/tkinnis/markdown_engine/ci.yml?branch=main&label=CI&logo=github)](https://github.com/tkinnis/markdown_engine/actions/workflows/ci.yml) [![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-0ea5e9)](https://tkinnis.github.io/markdown_engine/) [![CommonMark 0.31.2](https://img.shields.io/badge/CommonMark%200.31.2-652%2F652-0284c7)](https://github.com/tkinnis/markdown_engine/blob/main/doc/COVERAGE.md) [![GFM 0.29.0](https://img.shields.io/badge/GFM%200.29.0.gfm.13-670%2F670%20%2B%2030%2F30-7c3aed)](https://github.com/tkinnis/markdown_engine/blob/main/doc/COVERAGE.md) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, immutable sealed AST, HTML/plain-text/JSON exporters, and incremental streaming engine with `package:meta` as its sole runtime dependency. Every stage runs synchronously in memory with zero Flutter, DOM, JavaScript, or filesystem imports.

## Installation

Add `markdown_engine` to any Dart or Flutter project (requires Dart `^3.8.0`):

```bash
dart pub add markdown_engine
```

If you are building a Flutter application and want ready-made Markdown widgets, Material `ColorScheme` theming, and `SelectionArea` support, use [`markdown_engine_flutter`](https://pub.dev/packages/markdown_engine_flutter).

## Quick Start

Configure a `MarkdownEngine` with `.commonMark()`, `.gfm()`, or `.extended()` options and parse synchronously into an immutable `MarkdownDocument`:

```dart
import 'package:markdown_engine/markdown_engine.dart';

void main() {
  const MarkdownEngine engine = MarkdownEngine(
    defaultOptions: MarkdownOptions.extended(),
  );

  final MarkdownDocument document = engine.parse('''---
title: Architecture Notes
---

# Overview

Pure-Dart **CommonMark 0.31.2** and **GFM** with ==highlight==, H~2~O, x^2^, and \$E = mc^2\$.

> [!NOTE]
> Supports footnotes[^1], tables, alerts, and definition lists.

[^1]: Verified against all official vendored fixtures.
''');

  print(document.frontmatter?['title']); // Architecture Notes
  print(document.outline.first.slug); // overview
  print(document.toHtml());
  print(document.toPlainText());
}
```

## Incremental Editing & Streaming

### Incremental Block Reuse (`IncrementalMarkdownParser`)

In live editors, `IncrementalMarkdownParser` diffs normalized text, reuses unchanged blank-line-isolated prefix and suffix blocks with preserved `blockId` values, shifts suffix `SourceSpan`s, and reparses only the dirty slice:

```dart
import 'package:markdown_engine/markdown_engine.dart';

void editInPlace() {
  const IncrementalMarkdownParser parser = IncrementalMarkdownParser(
    engine: MarkdownEngine(defaultOptions: MarkdownOptions.gfm()),
  );

  final IncrementalParseResult v1 = parser.parseIncremental(
    '# Guide\n\nParagraph one.\n\nParagraph two.\n',
  );
  final IncrementalParseResult v2 = parser.parseIncremental(
    '# Guide\n\nParagraph one (updated).\n\nParagraph two.\n',
    previousResult: v1,
    editStartOffset: 9,
  );

  assert(v2.reusedBlockCount == 2);
  assert(v2.reparsedBlockCount == 1);
}
```

### Streaming Token Feeds (`StreamingMarkdownController`)

For token-by-token SSE or LLM streams, `StreamingMarkdownController` freezes completed leading blocks in `settledBlocks` and re-parses only the active trailing slice on each `append()`, reconciling exact parity on `finish()`:

```dart
import 'package:markdown_engine/markdown_engine.dart';

MarkdownDocument streamReply(Iterable<String> chunks) {
  final StreamingMarkdownController controller = StreamingMarkdownController(
    options: const MarkdownOptions.gfm(),
  );

  for (final String chunk in chunks) {
    controller.append(chunk);
  }
  return controller.finish();
}
```

## Security & Resource Budgets

Process untrusted user or network Markdown safely with built-in URL validation, HTML sanitization, and deterministic complexity caps:

```dart
import 'package:markdown_engine/markdown_engine.dart';

const MarkdownOptions hardenedOptions = MarkdownOptions.gfm(
  sanitizeHtml: true,
  sanitizeUrls: true,
  urlPolicy: MarkdownUrlPolicy(
    allowedSchemes: <String>{'https', 'mailto'},
    allowRelative: false,
    allowFragments: true,
  ),
  budgets: MarkdownBudgets(
    maxInputLength: 100000,
    maxNestingDepth: 32,
    maxTableColumns: 32,
    maxTableRows: 500,
  ),
);
```

* **`MarkdownUrlPolicy`**: Strips ASCII control characters before scheme parsing, blocks `javascript:`, `vbscript:`, and `data:` by default, supports scheme and host allowlists, and offers opt-in raster image data URIs (`allowSafeImageDataUrls`) while keeping SVG data URIs blocked.
* **GFM `tagfilter` & `sanitizeHtml`**: Escapes disallowed GFM tags by default (`gfmTagFilter: true`), and when `sanitizeHtml: true` strips `<script>`, `<style>`, `<iframe>`, `<object>`, `<embed>`, `<svg>`, `<math>`, `<form>`, `on*` event handlers, `srcdoc`, unsafe inline CSS, and disallowed URI attributes.
* **`MarkdownBudgets`**: Enforces caps on `maxInputLength` (`500000`), `maxNestingDepth` (`64`), `maxBlocks` (`50000`), `maxTableColumns` (`128`), `maxTableRows` (`10000`), `maxHtmlBytes` (`250000`), and `maxTokens` (`500000`).

## Core API Summary

| Symbol | Role |
| :--- | :--- |
| `MarkdownEngine` | Stateless entry point exposing `parse`, `renderToHtml`, and `toPlainText`. |
| `MarkdownOptions` | Presets (`.commonMark()`, `.gfm()`, `.extended()`) and 26 feature/sanitization flags plus `budgets` and `urlPolicy`. |
| `MarkdownDocument` | Immutable parsed output exposing `blocks`, `frontmatter`, `outline`, `footnotes`, `remoteImageAddresses`, `linkDefinitions`, `toHtml()`, `toPlainText()`, and `toJson()`. |
| `HtmlRenderer` | Renders `List<MarkdownBlockNode>` to CommonMark/GFM HTML respecting sanitization and `maxHtmlBytes`. |
| `IncrementalMarkdownParser` / `IncrementalParseResult` | Reuses unchanged prefix/suffix AST blocks across targeted document edits. |
| `StreamingMarkdownController` | Accumulates streamed chunks with frozen `settledBlocks`, prefix-preserving `replaceText()`, and full-parity `finish()`. |
| `MarkdownBlockNode` / `MarkdownInlineNode` | Sealed Dart 3 AST hierarchies (18 block subtypes, 20 inline subtypes) with `SourceSpan`, `blockId`, `toPlainText()`, and `shiftSpan()`. |
| `HeadingSlugGenerator` / `slugifyHeadingText` | Deterministic GitHub-style heading anchor slug generation with collision deduplication. |

## Companion Packages

* **LaTeX Math ([`tex_math`](https://pub.dev/packages/tex_math) / [`tex_math_flutter`](https://pub.dev/packages/tex_math_flutter))**: Pass `MathInlineNode.latex` and `MathBlockNode.latex` (when `math: true`) straight into `TexMathEngine` or `TexMath` widgets for pure-Dart OpenType `MATH` typesetting.
* **Mermaid Diagrams ([`pele_dart`](https://pub.dev/packages/pele_dart))**: Match fenced `CodeBlockNode`s where `language == 'mermaid'` and render `literal` to pure-Dart SVG diagrams.

## Specification Parity & Native AOT Performance

Verified against the vendored CommonMark `0.31.2` and `github/cmark-gfm 0.29.0.gfm.13` test suites:

| Suite | Passed | Failed | Disabled | Total | Pass Rate |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `commonmark` (`0.31.2`) | 652 | 0 | 0 | 652 | **100.0%** |
| `gfm_spec` (`0.29.0.gfm.13`) | 670 | 0 | 2 | 672 | **100.0%** |
| `gfm_extensions` (`0.29.0.gfm.13`) | 30 | 0 | 0 | 30 | **100.0%** |

Native Dart AOT measurements on Apple M4 (`arm64`, macOS 15.6, Dart `3.13.5`) under `MarkdownOptions.gfm()`:

| Workload | Payload | Mean | Median (p50) | Throughput (p50) |
| :--- | ---: | ---: | ---: | ---: |
| `small_doc_parse_and_html` | 937 B (18 lines) | 28.30 us | **27.80 us** | 32.15 MB/s |
| `medium_doc_parse_and_html` | 24.7 KB (479 lines) | 1.060 ms | **999.36 us** | 24.09 MB/s |
| `large_doc_5000_lines_parse` | 168.9 KB (4,996 lines) | 7.038 ms | **7.013 ms** | 23.52 MB/s |
| `incremental_single_paragraph_edit` | 168.9 KB (1,457/1,458 reused, **4.01x**) | 1.717 ms | **1.747 ms** | 94.43 MB/s |
| `streaming_llm_50_chunks_per_chunk` | 2.1 KB / 50 chunks (14/15 settled) | 13.18 us | **13.29 us** | 3.09 MB/s |

## License & Additional Resources

* **`markdown_engine`**: Copyright (c) 2026 Tony Kinnis — [MIT License](LICENSE).
* [Repository README](https://github.com/tkinnis/markdown_engine/blob/main/README.md) · [API Manual](https://github.com/tkinnis/markdown_engine/blob/main/doc/API_MANUAL.md) · [Architecture](https://github.com/tkinnis/markdown_engine/blob/main/doc/ARCHITECTURE.md) · [Coverage Matrix](https://github.com/tkinnis/markdown_engine/blob/main/doc/COVERAGE.md) · [Benchmarks](https://github.com/tkinnis/markdown_engine/blob/main/doc/BENCHMARKS.md)
