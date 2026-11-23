# Architecture & Design

**`markdown_engine`** is a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, immutable syntax tree, HTML/text/JSON exporter, incremental streaming engine, and Flutter rendering suite ([`REFERENCE.md`](../REFERENCE.md)). Every stage of block structuring, inline delimiter resolution, sanitization, and serialization runs synchronously in memory without a WebView or JavaScript runtime.

---

## 1. Scope & Design Goals

* **Strict Pure-Dart Core Boundary**: Everything under `packages/markdown_engine/lib/` depends exclusively on `package:meta` (`^1.16.0`) and never imports `package:flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*`. `MarkdownEngine` executes synchronously on caller-supplied strings with zero filesystem access, zero network calls, and zero global mutable state across parses.
* **Specification-Driven Parity**: Core block and inline parsing targets exact HTML compliance with vendored official CommonMark `0.31.2` (`652` examples) and `github/cmark-gfm 0.29.0.gfm.13` (`672` spec + `30` extension examples) fixtures in `corpus/spec/`, continuously verified by `tool/verify_spec.dart` and summarized in [`doc/COVERAGE.md`](COVERAGE.md).
* **Dart 3 Sealed AST**: All 18 block node types extend `sealed class MarkdownBlockNode` and all 20 inline node types extend `sealed class MarkdownInlineNode`, giving exporters, linters, and Flutter renderers compile-time exhaustive `switch` checks alongside immutable value equality and UTF-16 `SourceSpan` tracking.
* **Incremental & Streaming First**: Dedicated `IncrementalMarkdownParser` and `StreamingMarkdownController` entry points avoid quadratic full-document reparses in live editors and token-by-token streaming feeds while guaranteeing exact parity with full `MarkdownEngine.parse`.
* **Defense in Depth**: Configurable `MarkdownBudgets`, `MarkdownUrlPolicy` URI allowlisting, GFM `tagfilter`, and deep raw HTML sanitization (`sanitizeHtml: true`) bound hostile Markdown payloads deterministically.

---

## 2. Two-Phase CommonMark & GFM Pipeline

`MarkdownEngine.parse()` (`packages/markdown_engine/lib/src/engine.dart`) enforces `maxInputLength` upfront and delegates non-empty input to the two-phase CommonMark parsing algorithm extended with GFM and opt-in document constructs:

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
| **Normalization & Frontmatter** | `block_parser.dart`, `frontmatter.dart` | Normalizes `\r\n` and `\r` line endings to `\n`, replaces NUL (`U+0000`) with `U+FFFD`, and extracts optional leading YAML (`---`) or TOML (`+++`) frontmatter into `FrontmatterNode` / `MarkdownFrontmatter`. |
| **Phase 1 — Block Structure** | `block_parser.dart` | Scans lines via an open-container stack (`_DocOpenBlock`, blockquotes, lists, list items, footnote definitions, code fences, HTML blocks 1–7, display math, GFM pipe tables, ATX/setext headings, thematic breaks, paragraphs), collects first-wins link reference definitions (`[label]: url "title"`), footnote definitions, and abbreviation definitions, and runs post-processing for GitHub alerts, definition lists, `<details>`, `<figure>`, and `<div align="...">`. |
| **Phase 2 — Inline Resolution** | `inline_parser.dart`, `entities.dart`, `unicode.dart`, `emoji.dart`, `slugs.dart` | Resolves inline code spans, backslash escapes, HTML5 named and numeric character references, emphasis and GFM strikethrough delimiter stacks, links, images, CommonMark and GFM extended autolinks, inline math (`$...$`), footnotes (`[^label]`), highlight/subscript/superscript, emoji shortcodes, smart punctuation, `<kbd>`, `<abbr>`, `<picture>`, heading anchor slugs, document outline, and deduplicated remote image URLs. |
| **Exporters & Sanitization** | `document.dart`, `html_renderer.dart`, `security.dart`, `url_utils.dart` | Emits CommonMark/GFM HTML with percent-encoded URLs, URL policy checks, GFM `tagfilter` or deep HTML sanitization, raw HTML byte budgets, normalized plain text, and JSON metadata snapshots. |

### Phase 1: Line-by-Line Container Stack & Post-Processing

Phase 1 maintains a stack of open containers rooted at the document node. For each normalized source line, the block engine first checks continuation markers on open containers (blockquote `>`, list item indentation, footnote indentation), closes unmatched containers, detects new block starters (headings, fenced/indented code, HTML blocks, thematic breaks, blockquotes, lists, display math, tables), and attaches remaining lines to paragraphs or active leaf blocks while recording exact UTF-16 `SourceSpan` offsets and 1-based line numbers.

When paragraphs finalize, leading CommonMark link reference definitions are extracted into a normalized first-wins table (`Unicode` case-folded and whitespace-collapsed labels) before any inline parsing runs. Optional structured extensions (`alerts`, `definitionLists`, `detailsBlocks`, `figureBlocks`, `alignedBlocks`) transform matched raw blocks cleanly during Phase 1 finalization so Phase 2 resolves their inner inline runs uniformly.

### Phase 2: Delimiter Stack & Cross-Reference Resolution

Phase 2 walks every finalized block's raw inline strings with access to the complete Phase 1 link-reference, footnote, and abbreviation tables. Inline emphasis (`*`, `_`), GFM strikethrough (`~`, `~~`), highlight (`==`), subscript (`~`), and superscript (`^`) resolve through the CommonMark flanking-delimiter stack rules backed by Unicode whitespace and punctuation tables (`unicode.dart`). Links and images resolve inline destinations, full/collapsed/shortcut reference labels, and image dimensions while enforcing `MarkdownUrlPolicy` when `sanitizeUrls` is enabled.

Footnote citations (`[^label]`) are queued iteratively in order of first reference so footnotes referencing other footnotes resolve deterministically without cyclic recursion, appending a `FootnoteSectionNode` at the end of the document block list. Heading nodes compute GitHub-style deduplicated slugs via `HeadingSlugGenerator` (or honor `explicitHeadingIds` such as `{#custom-id}`) and populate `MarkdownDocument.outline`.

---

## 3. Immutable Sealed AST Hierarchy

Every AST node in `packages/markdown_engine/lib/src/ast.dart` is `@immutable`, exposes unmodifiable child collections, implements structural `==` and `hashCode`, extracts plain text via `toPlainText()`, and supports constant-structure span relocation via `shiftSpan(offsetDelta, lineDelta)`.

```mermaid
flowchart TD
  Block["sealed class MarkdownBlockNode (blockId, span)"] --> CoreB["Core Blocks: Heading, Paragraph, CodeBlock, BlockQuote, List, ListItem, ThematicBreak, HtmlBlock"]
  Block --> GfmB["GFM & Extended Blocks: Table, Alert, Frontmatter, MathBlock, DefinitionList, DetailsBlock, AlignedBlock, FigureBlock, FootnoteDefinition, FootnoteSection"]
  Inline["sealed class MarkdownInlineNode (span)"] --> CoreI["Core Inlines: Text, SoftBreak, HardBreak, CodeSpan, Emphasis, Strong, Link, Image, RawHtmlInline"]
  Inline --> ExtI["GFM & Extended Inlines: Strikethrough, Highlight, Subscript, Superscript, MathInline, FootnoteRef, KbdInline, AbbrInline, AnchorInline, PictureInline, InlineBreak"]
```

* **18 `MarkdownBlockNode` Subtypes**: `FrontmatterNode`, `HeadingNode`, `ParagraphNode`, `CodeBlockNode`, `BlockQuoteNode`, `AlertNode`, `ListNode`, `ListItemNode`, `TableNode`, `ThematicBreakNode`, `HtmlBlockNode`, `DetailsBlockNode`, `AlignedBlockNode`, `FigureBlockNode`, `MathBlockNode`, `DefinitionListNode`, `FootnoteDefinitionNode`, and `FootnoteSectionNode`.
* **20 `MarkdownInlineNode` Subtypes**: `TextNode`, `SoftBreakNode`, `HardBreakNode`, `CodeSpanNode`, `EmphasisNode`, `StrongNode`, `StrikethroughNode`, `HighlightNode`, `SubscriptNode`, `SuperscriptNode`, `LinkNode`, `ImageNode`, `MathInlineNode`, `FootnoteRefNode`, `KbdInlineNode`, `AbbrInlineNode`, `AnchorInlineNode`, `PictureInlineNode`, `InlineBreakNode`, and `RawHtmlInlineNode`.
* **Stable `blockId` Identity**: Every `MarkdownBlockNode` carries a deterministic `blockId` string preserved across incremental reuse so downstream UI frameworks (such as Flutter slivers) retain widget state, selection anchors, and scroll positions for untouched sections.

---

## 4. HTML Sanitizer, URL Security Gate & Resource Budgets

Untrusted Markdown introduces three distinct threat classes: executable URI schemes, raw HTML/XSS injection, and algorithmic complexity attacks (deep nesting or oversized tables). `markdown_engine` enforces layered controls across `security.dart`, `budgets.dart`, and `html_renderer.dart`:

### URL Security Gate (`MarkdownUrlPolicy`)

When `MarkdownOptions.sanitizeUrls` is enabled (the default across all presets), links, images, `<picture>` sources, and sanitized HTML URI attributes pass through `MarkdownUrlPolicy`:

* Strips ASCII control characters (`<= 0x20`, `0x7F`) before extracting the URI scheme so obfuscated payloads such as `java\tscript:alert(1)` or `&#x6A;avascript:` cannot bypass validation.
* Blocks `javascript`, `vbscript`, and `data` by default (`MarkdownUrlPolicy.defaultBlockedSchemes`).
* Supports strict scheme allowlists (`allowedSchemes`), host allowlists (`allowedHosts` with userinfo/port/IPv6 bracket stripping), toggles for relative (`allowRelative`) and `#fragment` (`allowFragments`) links, and opt-in raster image data URIs (`allowSafeImageDataUrls` permitting base64 `png`/`jpeg`/`gif`/`webp` while keeping `image/svg+xml` blocked).

### GFM Tagfilter & Deep HTML Sanitization

* **GFM `tagfilter` (`gfmTagFilter: true`)**: Escapes the opening `<` of `<title>`, `<textarea>`, `<style>`, `<xmp>`, `<iframe>`, `<noembed>`, `<noframes>`, `<script>`, and `<plaintext>` tags to `&lt;` per the GFM `0.29` specification.
* **Deep Raw HTML Sanitizer (`sanitizeHtml: true`)**: Invokes `sanitizeRawHtml()` to strip dangerous elements (`<script>`, `<style>`, `<iframe>`, `<object>`, `<embed>`, `<applet>`, `<base>`, `<link>`, `<meta>`, `<title>`, `<textarea>`, `<xmp>`, `<noembed>`, `<noframes>`, `<plaintext>`, `<svg>`, `<math>`, `<form>`, `<frame>`, `<frameset>`), remove all `on*` event handler attributes and `srcdoc`, block inline `style` attributes containing `javascript:`, `vbscript:`, `expression(`, or `data:text/html`, and filter `href`, `src`, `action`, `formaction`, `poster`, and `xlink:href` through `urlPolicy`.

### Resource & Complexity Budgets (`MarkdownBudgets`)

| Budget Field | Default Limit | Protected Resource |
| :--- | ---: | :--- |
| `maxInputLength` | `500,000` UTF-16 code units | Maximum document length accepted per parse pass (throws `RangeError` if exceeded). |
| `maxNestingDepth` | `64` levels | Maximum nested container depth for blockquotes, lists, and inline constructs. |
| `maxBlocks` | `50,000` blocks | Upper bound on top-level and nested block AST nodes produced per document. |
| `maxTableColumns` | `128` columns | Maximum column count accepted in a GFM pipe table. |
| `maxTableRows` | `10,000` body rows | Maximum body row count parsed in a single GFM pipe table. |
| `maxHtmlBytes` | `250,000` code units | Cumulative raw HTML emission budget before remaining raw HTML is escaped as text. |
| `maxTokens` | `500,000` tokens | Inline scanner and delimiter-stack work budget per document. |

---

## 5. Incremental & Streaming Architecture

### Incremental Editor Diffing (`IncrementalMarkdownParser`)

`IncrementalMarkdownParser` (`packages/markdown_engine/lib/src/incremental.dart`) minimizes reparsing cost when a user edits a large Markdown document:

```mermaid
flowchart LR
  Diff["Common Prefix & Non-Overlapping Suffix Scan"] --> Prefix["Reuse Blank-Line Isolated Prefix Blocks (Same blockId)"]
  Diff --> Dirty["Phase 1 + Phase 2 Parse Dirty Slice Only"]
  Diff --> Suffix["Reuse Blank-Line Isolated Suffix Blocks + shiftSpan(offsetDelta, lineDelta)"]
  Prefix --> Merge["Merge Blocks + Reconcile Outline & Slugs"]
  Dirty --> Merge
  Suffix --> Merge
```

1. **Exact Prefix & Suffix Diff**: Scans normalized old and new sources to locate the exact changed range, optionally narrowed by `editStartOffset`.
2. **Blank-Line Boundary Isolation**: Reuses leading blocks whose `span.endOffset` ends strictly before a blank line (`\n\n`) inside the unchanged prefix, and trailing blocks preceded strictly by a blank line inside the unchanged suffix. This guarantees the edit cannot retroactively turn an adjacent line into a setext heading, table header, list continuation, or merged paragraph.
3. **Dirty Slice Parsing**: Runs Phase 1 and Phase 2 only on the dirty slice (injecting `previousDocument.linkDefinitions` so reference links inside the edited paragraph resolve immediately) and shifts suffix block spans by `(offsetDelta, lineDelta)` while preserving every reused `blockId`.
4. **Safe Full-Reparse Fallbacks**: Automatically falls back to full `MarkdownEngine.parse` if `options` changed, frontmatter was touched or introduced, footnotes are active, or the dirty slice introduces or modifies link/footnote/abbreviation definitions (`]:`).

### Streaming Token Accumulation (`StreamingMarkdownController`)

`StreamingMarkdownController` (`packages/markdown_engine/lib/src/streaming.dart`) is tailored for chunked network or LLM token feeds:

* **Frozen Settled Prefix**: Maintains `_settledBlocks` (immutable finalized top-level blocks) and `_activeBlocks` (trailing open blocks). Whenever a block inside the active tail is followed by a blank line and a subsequent block (excluding adjacent lists, extended HTML containers, or definition lists that could still merge), it freezes into `_settledBlocks` and advances `_settledOffset` and `_settledLine`.
* **Bounded Tail Work**: Each `append(chunk)` call parses only the unsettled tail substring (`_normalizedBuffer.substring(_settledOffset)`), keeping per-chunk latency bounded as transcripts grow.
* **Prefix-Preserving `replaceText` & Parity `finish()`**: `replaceText(fullText)` retains already-settled blocks whenever the settled prefix matches byte-for-byte, and `finish()` reconciles the completed buffer against `MarkdownEngine.parse(buffer)` so final AST, HTML, and plain text match full parsing identically. If definitions (`]:`) appear mid-stream, the controller safely switches to full-document resolution so forward and backward references stay accurate.

---

## 6. Flutter Rendering Separation (`Parse <-> Theme <-> Sliver`)

`packages/markdown_engine_flutter` cleanly decouples parsing, visual styling, and viewport layout into three independent layers so theme switches never re-parse Markdown and large documents virtualize lazily:

```mermaid
flowchart LR
  Parse["Layer 1: Parse (MarkdownEngine / MarkdownDocumentReader / StreamingMarkdownController)"] --> AST["Immutable MarkdownDocument & Sealed Blocks (blockId)"]
  Theme["Layer 2: Theme (MarkdownTheme / MarkdownThemeData / MarkdownAlertPalette)"] --> Sliver["Layer 3: Slivers (SliverMarkdownDocument & MarkdownView)"]
  AST --> Sliver
  Ctrl["MarkdownController & MarkdownReadingPlace"] <--> Sliver
  Del["MarkdownBuilderDelegates & MarkdownImagePolicy"] --> Sliver
  Sliver --> Select["SelectionArea & Companion Adapters (tex_math_flutter / pele_dart)"]
```

* **Layer 1 — Parse & Isolate Offload (`markdown_engine`, `MarkdownDocumentReader`)**: `MarkdownView` caches the parsed `MarkdownDocument` in widget state and only re-parses when `data`, `options`, or `engine` changes (`MarkdownController.parseCount` stays constant across Light/Dark theme toggles). For pre-parsed ASTs, `MarkdownView.document` skips parsing completely, `MarkdownView.streaming` binds directly to `StreamingMarkdownController`, and `MarkdownDocumentReader` parses short inputs (`< 4096` UTF-16 code units by default) synchronously while offloading larger inputs to a background `Isolate.run` (`isolate_parse_io.dart` / `isolate_parse_stub.dart`) with latest-wins coalescing.
* **Layer 2 — Theme Tokens (`MarkdownTheme`, `MarkdownThemeData`, `MarkdownAlertPalette`, `MarkdownAlertColors`)**: Built `package:flutter/widgets.dart`-first with only three scoped `package:flutter/material.dart` `show` imports (`SelectionArea`, `Tooltip`, and `ColorScheme`/`Theme`/`ThemeData`) guarded with `// ignore: deprecated_member_use` for Flutter `3.32` through `3.50+` compatibility. Supports built-in `.light()`/`.dark()` palettes, `.fromColorScheme`, `.fromTheme`, and smooth `.lerp` transitions without re-parsing source text.
* **Layer 3 — Virtualized Slivers, Navigation & Security Delegates (`SliverMarkdownDocument`, `MarkdownView`, `MarkdownController`, `MarkdownBuilderDelegates`)**: `SliverMarkdownDocument` materializes only visible top-level blocks via `SliverChildBuilderDelegate` keyed by `ValueKey<String>(block.blockId)` with `findChildIndexCallback` (plus `scrollable: false` compact `Column` mode for cards and chat bubbles). `MarkdownController` tracks `outline`, `parseCount`, and `MarkdownReadingPlace`, exposing `scrollToAnchor`, `scrollToLine`, and `jumpToPlace`. `MarkdownBuilderDelegates` enforces `MarkdownUrlPolicy` on interactive links (preventing `javascript:`, `vbscript:`, unsafe `data:`, and control-character obfuscated links from becoming clickable), gates remote images via `MarkdownImagePolicy` (`block`, `ask`, `load`), and exposes `mathInlineBuilder`, `mathBlockBuilder`, `diagramBuilder`, `codeBlockBuilder`, and `imageBuilder` for native `tex_math_flutter` and `pele_dart` integration.

---

## 7. Verification & Monorepo Boundaries

| Workspace Area | Responsibility | Quality Gate |
| :--- | :--- | :--- |
| `packages/markdown_engine/` | Pure-Dart parser, AST, exporters, incremental/streaming (`meta` only, Dart `^3.8.0`). | `dart test`, `dart run example/main.dart`, `dart doc --dry-run`, `dart pub publish --dry-run` |
| `packages/markdown_engine_flutter/` | Flutter widgets, theming, selection, and streaming helpers (`>=3.32.0`, Dart `^3.8.0`). | `flutter test`, `dart doc --dry-run`, `flutter pub publish --dry-run` |
| `packages/markdown_engine_flutter/example/` | Standalone Flutter example app exercising widgets and theming. | `flutter test` |
| `studio/` | macOS inspection workbench (`>=3.47.0`, Dart `^3.13.0`). | `flutter test` |
| `tool/` & `corpus/` | Spec verification (`verify_spec.dart`), SHA-256 reference integrity (`sync_reference.dart`), lockstep versions (`check_versions.dart`), and native AOT benchmarks (`benchmark_suite.dart`). | `dart analyze --fatal-infos`, `dart format --output=none --set-exit-if-changed` |
