# Repository Guidelines for `markdown_engine`

This document defines the architectural invariants, monorepo boundaries, reference tracking rules, and quality gates for contributors and automated engineering workflows in **`markdown_engine`**.

---

## 1. Project Purpose & Workspace Layout

`markdown_engine` is a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, AST/HTML/text/JSON exporter, incremental streaming parser, and Flutter rendering suite built without a WebView or JavaScript runtime.

| Path | Role | SDK / Publishing |
| :--- | :--- | :--- |
| `packages/markdown_engine/` | Pure-Dart block and inline parser, immutable AST, HTML/text/JSON exporters, GFM and Markdown extensions, streaming diff engine, security sanitization, and budget guards. | Pure Dart (`^3.8.0`), `meta` only, published to pub.dev. |
| `packages/markdown_engine_flutter/` | Flutter `MarkdownView` / sliver / selection / theming widgets, built-in `tex_math_flutter` OpenType math & `pele_dart` + `vector_graphics` Mermaid renderers, streaming controller, and interactive hooks built atop `markdown_engine`. | Flutter (`>=3.47.0`, Dart `^3.13.0`), depends on `markdown_engine`, `tex_math_flutter`, `pele_dart`, `vector_graphics`, and `vector_graphics_compiler`, published to pub.dev. |
| `packages/markdown_engine_flutter/example/` | Standalone Flutter example app exercising `MarkdownView`, built-in math/Mermaid rendering, custom builder overrides, and `MarkdownTheme`. | Flutter (`>=3.47.0`, Dart `^3.13.0`), `publish_to: none`. |
| `studio/` | macOS desktop comparison and inspection workbench (`studio/macos/`). | Flutter (`>=3.47.0`, Dart `^3.13.0`), `publish_to: none`. |
| `tool/` | Lockstep version checks (`check_versions.dart`), spec verification and coverage generation (`verify_spec.dart`), reference hash checks (`sync_reference.dart`), native AOT benchmarks (`benchmark_suite.dart`), macOS profile benchmark runner (`run_macos_profile_benchmark.dart`), and head-to-head comparison suite (`tool/compare/`). | Dart CLI dev tooling. |
| `corpus/` | Vendored official `CommonMark 0.31.2` (`652` examples) and `GFM 0.29.0.gfm.13` (`672` spec + `30` extension examples) fixtures plus extension, security, and streaming test suites. | Verification fixtures. |
| `doc/` | Engineering documentation and Docsify portal (`ARCHITECTURE.md`, `API_MANUAL.md`, `COVERAGE.md`, `BENCHMARKS.md`, `STUDIO_GUIDE.md`, `REFERENCE_SYNC.md`, `RELEASING.md`). | GitHub Pages site source. |

---

## 2. Core Architectural Invariants

### A. Pure-Dart SDK Boundary (`packages/markdown_engine/lib/`)

* **Strict Core Imports**: Code under `packages/markdown_engine/lib/` must never import `package:flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*`.
* **Minimal Dependencies**: `packages/markdown_engine/pubspec.yaml` `dependencies:` contains strictly `meta: ^1.16.0`. Do not add third-party parser, HTML, or DOM packages to `packages/markdown_engine`.
* **Zero File I/O, Determinism & Lazy Document Metadata**: `MarkdownEngine` runs synchronously on caller-provided strings with zero filesystem access, zero network calls, and zero global mutable state across parses. Parser-built `MarkdownDocument` instances defer `source`, `outline`, and `remoteImageAddresses` lazily until read (`createFrozenDocument` / `createStreamingDocument`), inline resolution uses linear text coalescing (`_coalesceTextNodes`) plus an ASCII structural LUT and single-backtick fast path, and `StreamingMarkdownController.append` fast-paths mid-paragraph and open-fenced-code appends.
* **Complete Out-of-the-Box `MarkdownOptions()`**: `const MarkdownOptions()` enables all 23 extension flags by default (`gfmTables`, `gfmStrikethrough`, `gfmTaskLists`, `gfmAutolinks`, `gfmTagFilter`, `footnotes`, `alerts`, `frontmatter`, `definitionLists`, `math`, `headingSlugs`, `highlight`, `subscript`, `superscript`, `emoji`, `smartPunctuation`, `explicitHeadingIds`, `detailsBlocks`, `figureBlocks`, `alignedBlocks`, `kbd`, `abbreviations`, `inlineBreaks`, all individually opt-out) with `MarkdownUrlPolicy.strict()`, while `MarkdownOptions.commonMark()` and `MarkdownOptions.gfm()` remain strict specification presets.
* **Dart `^3.8.0` Syntax Compatibility**: Never use Dart 3.12+ private named-parameter shorthands (`this._field`) in `packages/markdown_engine`; use explicit initializer lists instead.

### B. Flutter Compatibility & Integration (`packages/markdown_engine_flutter/lib/`)

* **Flutter `>=3.47.0` & `widgets.dart`-First Layering**: Import `package:flutter/widgets.dart` as the primary UI layer and scope any `package:flutter/material.dart` imports (`ColorScheme`, `Theme`, `SelectionArea`, `Tooltip`) with explicit `show` clauses while targeting Flutter `>=3.47.0` and Dart `^3.13.0` (compatible through Flutter `3.50+`). Simple prose and streaming blocks use `FastMarkdownText` / `MarkdownParagraphLeaf` / `MarkdownHorizontalOverflowBox` and tail-isolated `RenderMarkdownStreamingCanvas` (`MarkdownStreamingCanvasLeaf` with visible-viewport prefix `ui.Picture` reuse and native selection) alongside `SliverMarkdownDocument` fallback for math, Mermaid, custom builders, and interactive blocks. Built-in OpenType math (`tex_math_flutter`) and vector Mermaid (`pele_dart` + `vector_graphics`) renderers enforce dual entry+byte LRU budgets (`BuiltInMathCache`: `1,024` entries / `8 MiB`; `BuiltInMermaidCache`: `128` entries / `16 MiB`, configurable via `MarkdownBuiltInRenderers.configureCaches(...)` / `resetCacheDefaults()` with byte telemetry) and are verified by both widget tests and deterministic golden pixel tests (`packages/markdown_engine_flutter/test/golden_rendering_test.dart` and `packages/markdown_engine_flutter/test/goldens/`).

### C. Spec Parity, Security & Standards

* **CommonMark & GFM Spec Parity**: Core block/inline behavior under `MarkdownOptions.commonMark()` and `MarkdownOptions.gfm()` (`table`, `strikethrough`, `autolink`, `tagfilter`, `tasklist`, `footnotes`) targets exact parity with `corpus/spec/commonmark_0.31.2.json`, `corpus/spec/gfm_0.29.0_spec.txt`, and `corpus/spec/gfm_0.29.0_extensions.txt`.
* **Defensive Hardening & Budgets**: Enforce input length, nesting depth, URL scheme sanitization, and HTML filtering bounds cleanly without throwing unhandled exceptions on hostile Markdown inputs.
* **Dart 3 Standards**: Enable `strict-casts`, `strict-inference`, `strict-raw-types`, `always_declare_return_types`, `directives_ordering`, and `prefer_single_quotes`. Write dartdoc comments on every public API symbol and avoid `print()` calls in `lib/`.

### D. Reference Pinning & Lockstep Versioning

* **[`REFERENCE.md`](REFERENCE.md) is the single source of truth** for pinned `CommonMark 0.31.2`, `github/cmark-gfm 0.29.0.gfm.13`, example counts, and SHA-256 integrity digests of all vendored files in `corpus/spec/`.
* **Lockstep Package Versions**: `packages/markdown_engine/pubspec.yaml`, `packages/markdown_engine_flutter/pubspec.yaml`, the top `## <version>` heading in both package `CHANGELOG.md` files, and `packages/markdown_engine_flutter`'s `markdown_engine: ^<version>` dependency must always agree, enforced by `tool/check_versions.dart`.

---

## 3. Quality Gates & Verification

Before completing any task or committing changes, verify all workspace gates pass with zero errors, warnings, or infos:

1. **Formatting**:
   ```bash
   dart format --output=none --set-exit-if-changed packages tool studio
   ```
2. **Static Analysis**:
   ```bash
   dart analyze --fatal-infos
   ```
3. **Package, Example & Studio Tests**:
   ```bash
   (cd packages/markdown_engine && dart test && dart run example/main.dart && dart doc --dry-run)
   (cd packages/markdown_engine_flutter && flutter test && dart doc --dry-run)
   (cd packages/markdown_engine_flutter/example && flutter test)
   (cd studio && flutter test)
   ```
4. **Version Lockstep, Reference Integrity, Spec Parity & Benchmarks**:
   ```bash
   dart run tool/check_versions.dart
   dart run tool/sync_reference.dart --verify
   dart run tool/verify_spec.dart --strict
   dart run tool/benchmark_suite.dart --check-regressions
   ```
5. **Publish Readiness**:
   ```bash
   (cd packages/markdown_engine && dart pub publish --dry-run)
   (cd packages/markdown_engine_flutter && flutter pub publish --dry-run)
   ```

---

## 4. Reference Sync, Documentation & Commit Rules

* Follow [`doc/REFERENCE_SYNC.md`](doc/REFERENCE_SYNC.md) and `.agents/skills/sync-reference-commonmark/SKILL.md` when updating pinned CommonMark or `cmark-gfm` spec fixtures, regenerating `doc/COVERAGE.md` or `doc/BENCHMARKS.md`.
* Keep every Markdown prose paragraph on a single line without hard-wrapped line breaks inside paragraphs.
* Never commit private filesystem paths, third-party `node_modules/`, or unverified coverage/benchmark counts.
* Use **Conventional Commits** (`feat(parser): ...`, `fix(gfm): ...`, `docs(reference): ...`, `chore(ci): ...`) and omit automated tool credits, trailer attributions, or synthetic author tags from commit messages, PR descriptions, and code comments.
