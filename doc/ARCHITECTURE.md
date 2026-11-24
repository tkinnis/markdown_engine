# Architecture & Design

**`markdown_engine`** is a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, immutable syntax tree, HTML/text/JSON exporter, incremental streaming engine, and Flutter rendering suite ([`REFERENCE.md`](../REFERENCE.md)). Every stage of block structuring, inline delimiter resolution, sanitization, and serialization runs synchronously in memory without a WebView or JavaScript runtime.

---

## 1. Scope & Design Goals

* **Strict Pure-Dart Core Boundary**: Everything under `packages/markdown_engine/lib/` depends exclusively on `package:meta` (`^1.16.0`) and never imports `package:flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*`. `MarkdownEngine` executes synchronously on caller strings with zero filesystem, network, or global mutable state.
* **Specification-Driven Parity**: Core parsing targets exact HTML compliance with vendored CommonMark `0.31.2` (`652` examples) and `github/cmark-gfm 0.29.0.gfm.13` (`672` spec + `30` extension examples) fixtures in `corpus/spec/`, verified by `tool/verify_spec.dart` and summarized in [`doc/COVERAGE.md`](COVERAGE.md).
* **Dart 3 Sealed AST**: All 18 block node types extend `sealed class MarkdownBlockNode` and all 20 inline node types extend `sealed class MarkdownInlineNode`, providing exhaustive `switch` checks, structural value equality, and UTF-16 `SourceSpan` tracking.
* **Incremental & Streaming First**: `IncrementalMarkdownParser` and `StreamingMarkdownController` avoid quadratic reparses in live editors and token feeds while guaranteeing exact parity with full `MarkdownEngine.parse`.
* **Defense in Depth**: Configurable `MarkdownBudgets`, `MarkdownUrlPolicy` URI allowlisting, GFM `tagfilter`, and deep raw HTML sanitization (`sanitizeHtml: true`) bound untrusted Markdown deterministically.

---

## 2. Two-Phase CommonMark & GFM Pipeline

`MarkdownEngine.parse()` (`packages/markdown_engine/lib/src/engine.dart`) enforces `maxInputLength` upfront and runs the two-phase CommonMark parsing algorithm. Default `const MarkdownOptions()` enables all 23 GFM and optional extensions (individually opt-out), while `.commonMark()` and `.gfm()` remain strict specification presets.

```mermaid
flowchart LR
  Input["Markdown Input (UTF-16)"] --> Norm["Normalization & Frontmatter (frontmatter.dart)"]
  Norm --> P1["Phase 1: Block Structure (block_parser.dart)"]
  P1 -->|"RawBlock Tree + Link / Footnote / Abbr Tables"| P2["Phase 2: Inline Resolution (inline_parser.dart)"]
  P2 --> Doc["MarkdownDocument (Immutable AST + Outline + Footnotes)"]
  Doc --> Html["HtmlRenderer (html_renderer.dart + security.dart)"]
  Doc --> TextJson["toPlainText() & toJson()"]
  Doc --> Flutter["markdown_engine_flutter (Theme + Slivers)"]
```

| Stage | Primary Module | Responsibility |
| :--- | :--- | :--- |
| **Entry & Guard** | `engine.dart`, `budgets.dart` | Validates `source.length <= effective.maxInputLength` and dispatches Phase 1 and Phase 2 synchronously. |
| **Normalization & Frontmatter** | `block_parser.dart`, `frontmatter.dart` | Normalizes `\r\n` / `\r` endings to `\n`, replaces NUL (`U+0000`) with `U+FFFD`, and extracts leading YAML (`---`) or TOML (`+++`) frontmatter. |
| **Phase 1 — Block Structure** | `block_parser.dart` | Builds the open container tree, collects first-wins link/footnote/abbreviation definitions, assigns pooled `blockId`s, and transforms structured extension blocks. |
| **Phase 2 — Inline Resolution** | `inline_parser.dart`, `entities.dart`, `unicode.dart`, `emoji.dart`, `slugs.dart` | Resolves code spans, entities, emphasis/strikethrough delimiters, links, images, autolinks, inline math, footnotes, shortcodes, and heading slugs. |
| **Exporters & Sanitization** | `document.dart`, `html_renderer.dart`, `security.dart`, `url_utils.dart` | Builds immutable `MarkdownDocument` snapshots with lazy metadata and emits sanitized HTML, normalized plain text, and JSON. |

### Phase 1: Line-by-Line Container Stack & Post-Processing

* **Zero-Allocation Line Indexing**: `_splitLineRanges` indexes normalized line slices into a flat `Int32List` without allocating per-line `String` objects, scanning lines via a reusable `_LineCursor`.
* **Container Stack & Cold Openers**: Maintains an open-container stack (`_DocOpenBlock`, blockquotes, lists, list items, footnote definitions, code fences, HTML blocks 1–7, `$$...$$` and `\[...\]` display math, GFM pipe tables, ATX/setext headings, thematic breaks, and paragraphs), isolating cold openers (`_tryOpenFencedCode`, `_tryOpenFootnoteDef`, `_tryOpenListItem`, `_appendLiteralTipLine`, `_buildRareBlock`) off hot loops.
* **Definitions & Structured Post-Processing**: Extracts leading link reference definitions into a normalized first-wins table (`Unicode` case-folded, whitespace-collapsed) when paragraphs finalize, then transforms `alerts`, `definitionLists`, `detailsBlocks`, `figureBlocks`, and `alignedBlocks` during Phase 1 finalization so Phase 2 resolves their inlines uniformly.

### Phase 2: Delimiter Stack & Cross-Reference Resolution

* **Fast-Path Inline Scanning**: Uses a cached 128-byte structural ASCII lookup table (`_getStructuralLut`), single-backtick `indexOf` code-span fast paths, reusable resolvers (`ReusableBlockInlineResolver`), and single-pass linear text coalescing (`_coalesceTextNodes`).
* **Delimiter Stack & Entities**: Resolves `*`/`_`, `~`/`~~`, `==`, `~`, and `^` delimiters via CommonMark flanking rules backed by `unicode.dart`, alongside HTML5 named/numeric entities (`entities.dart`), links, images, CommonMark/GFM autolinks, inline math (`$...$`, `\(...\)`), `<kbd>`, `<abbr>`, `<picture>`, emoji shortcodes (`emoji.dart`), and smart punctuation.
* **Footnotes, Slugs & Lazy Document State**: Queues footnote citations (`[^label]`) iteratively in first-reference order (preventing cyclic recursion) to append `FootnoteSectionNode`, computes deduplicated slugs via `HeadingSlugGenerator` (`slugs.dart`), and defers `source`, `outline`, and `remoteImageAddresses` on `MarkdownDocument` via `_DocumentLazyState` until accessed.

---

## 3. Immutable Sealed AST Hierarchy

Every AST node in `packages/markdown_engine/lib/src/ast.dart` is `@immutable`, freezes child lists and frontmatter entries once at construction for `O(1)` getter access, implements structural `==` and `hashCode`, extracts plain text via `toPlainText()`, and supports `O(1)` lazy span relocation via `shiftSpan(offsetDelta, lineDelta)`.

```mermaid
flowchart TD
  Block["sealed class MarkdownBlockNode (blockId, span)"] --> CoreB["Core Blocks: Heading, Paragraph, CodeBlock, BlockQuote, List, ListItem, ThematicBreak, HtmlBlock"]
  Block --> GfmB["GFM & Extended Blocks: Table, Alert, Frontmatter, MathBlock, DefinitionList, DetailsBlock, AlignedBlock, FigureBlock, FootnoteDefinition, FootnoteSection"]
  Inline["sealed class MarkdownInlineNode (span)"] --> CoreI["Core Inlines: Text, SoftBreak, HardBreak, CodeSpan, Emphasis, Strong, Link, Image, RawHtmlInline"]
  Inline --> ExtI["GFM & Extended Inlines: Strikethrough, Highlight, Subscript, Superscript, MathInline, FootnoteRef, KbdInline, AbbrInline, AnchorInline, PictureInline, InlineBreak"]
```

* **18 `MarkdownBlockNode` Subtypes**: `FrontmatterNode`, `HeadingNode`, `ParagraphNode`, `CodeBlockNode`, `BlockQuoteNode`, `AlertNode`, `ListNode`, `ListItemNode`, `TableNode`, `ThematicBreakNode`, `HtmlBlockNode`, `DetailsBlockNode`, `AlignedBlockNode`, `FigureBlockNode`, `MathBlockNode`, `DefinitionListNode`, `FootnoteDefinitionNode`, and `FootnoteSectionNode`.
* **20 `MarkdownInlineNode` Subtypes**: `TextNode`, `SoftBreakNode`, `HardBreakNode`, `CodeSpanNode`, `EmphasisNode`, `StrongNode`, `StrikethroughNode`, `HighlightNode`, `SubscriptNode`, `SuperscriptNode`, `LinkNode`, `ImageNode`, `MathInlineNode`, `FootnoteRefNode`, `KbdInlineNode`, `AbbrInlineNode`, `AnchorInlineNode`, `PictureInlineNode`, `InlineBreakNode`, and `RawHtmlInlineNode`.
* **Pooled `blockId` Identity**: Every `MarkdownBlockNode` carries a deterministic `blockId` string drawn from precomputed `_precomputedBlockIds` (`b-0`..`b-4095`) to avoid hot string interpolation and keep UI widget state, selection anchors, and scroll positions stable across incremental updates.

---

## 4. HTML Sanitizer, URL Security Gate & Resource Budgets

Untrusted Markdown introduces three threat classes: executable URI schemes, raw HTML/XSS injection, and algorithmic complexity attacks. `markdown_engine` enforces layered controls across `security.dart`, `budgets.dart`, and `html_renderer.dart`:

### URL Security Gate (`MarkdownUrlPolicy`)

When `MarkdownOptions.sanitizeUrls` is enabled (the default across all presets), links, images, `<picture>` sources, and sanitized HTML URI attributes pass through `MarkdownUrlPolicy`:

* **Obfuscation Stripping & ASCII Fast Path**: Strips ASCII control characters (`<= 0x20`, `0x7F`), Unicode whitespace, and zero-width characters (`stripControlAndWhitespaceForUrl`), decodes HTML5 entities before scheme inspection, and fast-paths clean `http://`, `https://`, and `#fragment` URIs inside `MarkdownUrlPolicy.isAllowed`.
* **Strict vs. Blocklist Constructors**: `MarkdownUrlPolicy.strict()` (default on `MarkdownOptions()`) allows only `http`, `https`, and `mailto` plus relative/fragment URLs while rejecting protocol-relative (`//`, `\\`, `/\`, `\/`) and userinfo (`user:pass@host`) URLs; `MarkdownUrlPolicy()` blocks `javascript`, `vbscript`, and `data` via `defaultBlockedSchemes`.
* **Custom Policy Controls**: Supports custom `allowedSchemes`, case-insensitive `allowedHosts` (stripping ports and IPv6 brackets), `allowRelative` / `allowFragments` toggles, and `allowSafeImageDataUrls` (permitting base64 raster `png`/`jpeg`/`jpg`/`gif`/`webp` while keeping SVG and HTML `data:` URIs blocked).

### GFM Tagfilter & Linear HTML5 Sanitizer

* **GFM `tagfilter` (`gfmTagFilter: true`)**: Escapes the opening `<` of `<title>`, `<textarea>`, `<style>`, `<xmp>`, `<iframe>`, `<noembed>`, `<noframes>`, `<script>`, and `<plaintext>` tags to `&lt;` per the GFM `0.29` specification.
* **Linear-Time State-Machine HTML5 Sanitizer (`sanitizeHtml: true`)**: `sanitizeRawHtml()` runs a zero-backtracking state-machine tokenizer and allowlist sanitizer handling slash-separated attributes (`<img/src=x/...>`), `<` inside quoted attributes, and entity decoding before `urlPolicy.isAllowed` and CSS `url(...)` checks.
* **Active Content Stripping**: Strips dangerous elements (`<script>`, `<style>`, `<noscript>`, `<template>`, `<iframe>`, `<object>`, `<embed>`, `<applet>`, `<base>`, `<link>`, `<meta>`, `<title>`, `<textarea>`, `<xmp>`, `<noembed>`, `<noframes>`, `<plaintext>`, `<svg>`, `<math>`, `<form>`, `<frame>`, `<frameset>`), `on*` handlers, `srcdoc`, and unsafe URI attributes (`href`, `src`, `srcset`, `background`, `cite`, `ping`, `longdesc`, `poster`, `action`, `formaction`, `xlink:href`).

### Resource & Complexity Budgets (`MarkdownBudgets`)

| Budget Field | Default Limit | Protected Resource |
| :--- | ---: | :--- |
| `maxInputLength` | `500,000` UTF-16 code units | Maximum document length accepted per parse pass (throws `RangeError` if exceeded). |
| `maxNestingDepth` | `64` levels | Maximum nested container depth across blockquotes, lists, brackets, and inline emphasis delimiters. |
| `maxBlocks` | `50,000` blocks | Upper bound on top-level and nested block AST nodes produced per document. |
| `maxTableColumns` | `128` columns | Maximum column count accepted in a GFM pipe table (clamped on header and body rows). |
| `maxTableRows` | `10,000` body rows | Maximum body row count parsed in a single GFM pipe table. |
| `maxHtmlBytes` | `250,000` code units | Cumulative raw HTML emission budget before remaining raw HTML is escaped as text. |
| `maxTokens` | `500,000` tokens | Document-wide inline scanner and delimiter-stack work budget. |
| `maxOutputBytes` | `4,194,304` code units | Cumulative rendered output and reference/abbreviation expansion budget. |

---

## 5. Incremental & Streaming Architecture

### Incremental Editor Diffing (`IncrementalMarkdownParser`)

`IncrementalMarkdownParser` (`packages/markdown_engine/lib/src/incremental.dart`) minimizes reparsing cost when a document changes:

```mermaid
flowchart LR
  Diff["O(1) Edit-Offset Windowing / Prefix-Suffix Diff"] --> Prefix["O(log B) Binary-Search Reusable Prefix Blocks (Same blockId)"]
  Diff --> Dirty["Phase 1 + Phase 2 Parse Dirty Slice Only (Inject Definitions & Abbrs)"]
  Diff --> Suffix["O(log B) Binary-Search Reusable Suffix Blocks + O(1) Lazy shiftSpan"]
  Prefix --> Merge["Merge Blocks + Incremental Outline, Remote Images & Slug Reconcile"]
  Dirty --> Merge
  Suffix --> Merge
```

1. **Cached Normalization & `O(1)` Dirty Windowing**: Reuses `normalizedSource` cached on the previous `MarkdownDocument`, skips full re-normalization when the edited span has no `\r` or `\x00`, and isolates the dirty slice in `O(1)` when edit offsets are provided.
2. **Binary-Search Isolation & Container Guards**: Binary-searches leading and trailing reusable blocks in `O(log B)` and guards blank-line boundaries around `ListNode`, `DefinitionListNode`, `DetailsBlockNode`, `FigureBlockNode`, `AlignedBlockNode`, and `HtmlBlockNode` so edits cannot split or miss adjacent merges.
3. **Dirty Slice Parsing & `O(1)` Lazy Span Shifting**: Runs Phase 1 and Phase 2 only on the dirty slice (propagating `previousDocument.linkDefinitions` and `abbreviations`), shifts suffix blocks lazily while keeping every `blockId`, and updates `outline` and `remoteImageAddresses` incrementally.
4. **Safe Full-Reparse Fallbacks**: Falls back to `MarkdownEngine.parse` if `options` changed, frontmatter was touched or added, footnotes are active, or the dirty slice introduces or modifies definitions (`]:`).

### Streaming Token Accumulation (`StreamingMarkdownController`)

`StreamingMarkdownController` (`packages/markdown_engine/lib/src/streaming.dart`) accelerates chunked network or LLM token feeds without polling timers:

* **Frozen Settled Prefix & Push Listeners**: Maintains `_settledBlocks` and `_activeBlocks`, exposing `settledPrefixBlockCount` (`0` while active definitions force full reparses; equal to `currentDocument.blocks.length` on `finish()`) alongside pure-Dart `addListener`, `removeListener`, and `dispose` callbacks.
* **Blank-Line Settling**: Freezes completed active blocks into `_settledBlocks` (advancing `_settledOffset` and `_settledLine`) once followed by a blank line and a subsequent block outside mergeable lists, definition lists, or open HTML containers.
* **`O(chunk)` Tail Fast Paths**: Scans chunks linearly for `\n`, `\r`, and `\x00`, fast-paths mid-paragraph (`_appendFastPara` via `ReusableBlockInlineResolver.parseParagraph`), open fenced code (`_tryFastOpenCodeAppend`), single-line blockquotes, trailing list-item paragraphs, and open GFM pipe tables without full Phase 1 reparses, and emits `createStreamingDocument` snapshots with lazy metadata.
* **Prefix-Preserving `replaceText` & Exact `finish()`**: `replaceText` preserves matching settled prefix blocks, enforces `maxInputLength` before mutating state, and `finish()` reconciles exact `MarkdownEngine.parse` parity while keeping `_safeSettledCount` intact for post-finish `append()` or `reset()` reuse.

---

## 6. Flutter Rendering Separation (`Parse <-> Theme <-> Sliver`)

`packages/markdown_engine_flutter` decouples parsing, visual styling, and viewport layout into independent layers so theme switches never re-parse Markdown and large documents virtualize lazily:

```mermaid
flowchart LR
  Parse["Layer 1: Parse (IncrementalMarkdownParser / MarkdownDocumentReader / StreamingMarkdownController)"] --> AST["Immutable MarkdownDocument & Sealed Blocks (blockId)"]
  Theme["Layer 2: Theme (MarkdownTheme / MarkdownThemeData / MarkdownAlertPalette)"] --> Sliver["Layer 3: Slivers (SliverMarkdownDocument & MarkdownView)"]
  AST --> Sliver
  Ctrl["MarkdownController (readingPlaceNotifier)"] <--> Sliver
  Del["MarkdownBuilderDelegates & MarkdownImagePolicy"] --> Sliver
  Sliver --> Select["SelectionArea / SelectableRegion & Companion Adapters"]
```

### 6.1 Layer 1 — Parse, Streaming Modes & Isolate Offload

* **Cached Widget Parsing (`MarkdownView`)**: Parses `data` once in widget state, applies `IncrementalMarkdownParser` automatically inside `didUpdateWidget` on compatible edits (preserving stateful `<details>` and copy widgets), and performs zero re-parses on Light/Dark theme toggles. `MarkdownView.document` skips parsing entirely.
* **Hybrid Streaming Modes (`MarkdownView.streaming`)**: Subscribes to `StreamingMarkdownController` push listeners without `Timer.periodic` polling and selects dynamically among four layouts: `canvasFull` (full-document `MarkdownStreamingCanvasLeaf`), `hybridCanvasTail` (frozen settled-prefix `SliverMarkdownDocument` sliced at `settledPrefixBlockCount` plus trailing `MarkdownStreamingSliverAdapter` + `MarkdownStreamingCanvasLeaf`), `hybridWidgetTail` (settled prefix sliver plus slot-isolated trailing `SliverMarkdownDocument` while active blocks use rich/custom builders), and `widgetFull`.
* **Background Reader (`MarkdownDocumentReader`)**: Implements `ValueListenable<MarkdownDocument>`, parses short strings synchronously, offloads inputs `>= syncThreshold` (`4096`) to `Isolate.run` with in-flight deduplication and latest-wins coalescing, and falls back synchronously on `IsolateSpawnException`.

### 6.2 Layer 2 — Theme Tokens & Reactive Adapter Derivation

* **Widgets-First Footprint**: Built on `package:flutter/widgets.dart` with scoped `package:flutter/material.dart` `show` imports (`SelectionArea`, `Tooltip`, `ColorScheme`, `Theme`, `ThemeData`) targeting Flutter `>=3.47.0` and Dart `^3.13.0`.
* **Hoisted Render Environment**: `MarkdownRenderEnvironment` resolves ambient text scale, directionality, selection registrar, selection color, locale, `boldText`, and overlay presence once per view/sliver instead of per block.
* **Reactive Math & Mermaid Derivation**: `deriveTexMathThemeData` and `deriveMermaidTheme` (`pele.PelePalette`) map `MarkdownThemeData` colors dynamically so Light/Dark theme switches repaint math and re-palette Mermaid without re-parsing source text or re-running TeX layout.

### 6.3 Layer 3 — Virtualized Slivers, Fast Prose & Selection

* **Virtualized Sliver Layout (`SliverMarkdownDocument`)**: Stateful sliver backed by `RenderSliverList`, `SliverChildBuilderDelegate` keyed by `ValueKey<String>(block.blockId)` with `idToIndex` lookup, `Float64List` extent estimation, single-frame batched leading-child scroll-offset corrections (capped after `3` consecutive cycles), `addAutomaticKeepAlives: true`, and child memoization in `_MarkdownTopLevelBlockWidgetState` / `_MarkdownInlineTextState`.
* **Fast Leaf RenderBoxes & Streaming Canvas**: Eligible prose, code blocks, and table cells bypass heavy wrapper trees via `FastMarkdownText`, `MarkdownParagraphLeaf` (`RenderMarkdownParagraph`), `MarkdownHorizontalOverflowBox` (`RenderHorizontalOverflowBox`), and `buildFastSimpleInlineSpan`. `RenderMarkdownStreamingCanvas` maintains `O(tail)` incremental sync, dry-sync paint tracking, visible-viewport prefix `ui.Picture` reuse, and cross-sliver `Selectable` support.
* **Release-Safe Selection (`MarkdownRichText`)**: Guards `SelectionArea` behind `MaterialLocalizations` (falling back to `SelectableRegion` in `WidgetsApp`), backs `MarkdownRichText` with `_SafeRenderParagraph` tracking explicit layout readiness (never relying on `debugNeedsLayout` in profile/release), excludes UI chrome via `SelectionContainer.disabled`, and exports full `toPlainText()` on `Cmd+A` / Select All.
* **Navigation & Accessibility (`MarkdownController`)**: Tracks owner-scoped `ScrollController` attachments, isolates `readingPlaceNotifier` from document rebuilds via `RenderAbstractViewport` metrics, performs frame-synchronized `scrollToAnchor` convergence, and wires `Semantics` alongside keyboard `FocusableActionDetector` controls.

### 6.4 Built-In Math, Mermaid Worker Pool & Native HTML Rendering

| Subsystem | Module(s) | Architecture & Caching Behavior |
| :--- | :--- | :--- |
| **Built-In TeX Math** | `built_in_math.dart` (`tex_math_flutter`) | `BuiltInMathCache` stores `(font.signature, displayMode, latex)` `DisplayList`, spoken text, and error entries under a `1,024`-entry / `8 MiB` LRU budget, serving synchronous `TexMath.displayList` once `TexMathFontBundle.cachedMathFont` is warm. |
| **Built-In Mermaid & Worker Pool** | `built_in_mermaid.dart`, `built_in_mermaid_worker.dart` (`_io` / `_stub`) | `BuiltInMermaidCache` caches `(paletteKey, trimmedCode)` `vector_graphics` payloads under a `128`-entry / `16 MiB` LRU budget; `PersistentMermaidWorker` keeps `1` pre-warmed primary `Isolate` and lazily scales up to `maxMermaidConcurrentWorkers` auxiliary burst isolates (`15`s idle teardown, `TransferableTypedData` replies, web `compute()` fallback). |
| **Native HTML Block & Table Renderer** | `html_block_renderer.dart`, `inline_renderer.dart`, `block_renderer.dart` | `parseHtmlBlockFragment` tokenizes HTML fragments in linear time (`HtmlBlockEntry`) into native AST blocks (`<table>` with `<caption>`/`colspan`/`thead`/`tbody`/`tfoot`, `<dl>`, `<details>`, `<figure>`, `<center>`, `<div align>`, headings, lists, block-wrapping `<a id>`) within depth/row/column bounds, while `inline_renderer.dart` handles `<mark>`, `<sub>`, `<sup>`, `<abbr>`, `<kbd>`, `<u>`, `<small>`, `<q>`, `<code>`, `<picture>`, and `<img>`. |
| **Image & Link Security** | `delegates.dart`, `inline_renderer.dart`, `block_renderer.dart` | Enforces `MarkdownUrlPolicy` on interactive taps and `<picture>`/`<img>` sources, gates remote images via `MarkdownImagePolicy`, caches decoded `data:image/` payloads, and recycles/post-frame-disposes `TapGestureRecognizer`s. |

---

## 7. Verification & Monorepo Boundaries

| Workspace Area | Responsibility | Quality Gate |
| :--- | :--- | :--- |
| `packages/markdown_engine/` | Pure-Dart parser, AST, exporters, incremental/streaming (`meta` only, Dart `^3.8.0`). | `dart test`, `dart run example/main.dart`, `dart doc --dry-run`, `dart pub publish --dry-run` |
| `packages/markdown_engine_flutter/` | Flutter widgets, built-in `tex_math_flutter` + `pele_dart` renderers, theming, selection, and streaming helpers (`>=3.47.0`, Dart `^3.13.0`). | `flutter test`, `dart doc --dry-run`, `flutter pub publish --dry-run` |
| `packages/markdown_engine_flutter/example/` | Standalone Flutter example app exercising widgets and theming. | `flutter test` |
| `studio/` | macOS inspection workbench (`>=3.47.0`, Dart `^3.13.0`). | `flutter test` |
| `tool/` & `corpus/` | Spec verification (`verify_spec.dart`), SHA-256 reference integrity (`sync_reference.dart`), lockstep versions (`check_versions.dart`), and native AOT benchmarks (`benchmark_suite.dart`). | `dart analyze --fatal-infos`, `dart format --output=none --set-exit-if-changed` |
