# API Manual

This manual documents every public symbol exported by **`package:markdown_engine/markdown_engine.dart`** (pure Dart) and provides an overview of **`package:markdown_engine_flutter/markdown_engine_flutter.dart`** (Flutter widgets and theming).

## Installation

```bash
# Pure Dart (requires Dart ^3.8.0, package:meta only)
dart pub add markdown_engine

# Flutter (requires Dart ^3.8.0 and Flutter >=3.32.0)
flutter pub add markdown_engine_flutter
```

---

## 1. Core Engine, Document & HTML Renderer

`MarkdownEngine` is a stateless, immutable entry point with zero global mutable state across parses. Parse Markdown strings synchronously into a `MarkdownDocument`, or invoke `renderToHtml` / `toPlainText` directly.

| Symbol | Signature / Key Members | Behavior |
| :--- | :--- | :--- |
| `MarkdownEngine` | `const MarkdownEngine({MarkdownOptions defaultOptions = const MarkdownOptions()})` | Configures default `MarkdownOptions` applied when per-call options are omitted. |
| `MarkdownEngine.parse` | `MarkdownDocument parse(String source, {MarkdownOptions? options})` | Enforces `maxInputLength` (throws `RangeError` if exceeded), runs Phase 1 and Phase 2 parsing, and returns an immutable `MarkdownDocument`. |
| `MarkdownEngine.renderToHtml` | `String renderToHtml(String source, {MarkdownOptions? options})` | Parses `source` and serializes directly to CommonMark/GFM HTML. |
| `MarkdownEngine.toPlainText` | `String toPlainText(String source, {MarkdownOptions? options})` | Parses `source` and extracts normalized plain text joined across blocks by `\n\n`. |
| `MarkdownDocument` | `source`, `options`, `blocks`, `frontmatter`, `outline`, `footnotes`, `remoteImageAddresses`, `linkDefinitions`, `isEmpty`, `toHtml()`, `toPlainText()`, `toJson()` | Immutable parsed document holding unmodifiable AST blocks, extracted metadata, and HTML/text/JSON exporters. |
| `HtmlRenderer` | `const HtmlRenderer({MarkdownOptions options = const MarkdownOptions()})`, `String render(List<MarkdownBlockNode> blocks)` | Renders any list of `MarkdownBlockNode`s to CommonMark `0.31.2` / `cmark-gfm` HTML while enforcing `gfmTagFilter`, `sanitizeHtml`, `sanitizeUrls`, and `maxHtmlBytes`. |

```dart
import 'package:markdown_engine/markdown_engine.dart';

void main() {
  const MarkdownEngine engine = MarkdownEngine(
    defaultOptions: MarkdownOptions.extended(),
  );

  final MarkdownDocument doc = engine.parse('''---
title: Release Notes
---

# Overview

Pure-Dart **CommonMark** and *GFM* with `code`, ~~old~~, and ==highlight==.
''');

  final String html = doc.toHtml();
  final String text = doc.toPlainText();
  final Map<String, Object?> summary = doc.toJson();
  assert(doc.frontmatter?['title'] == 'Release Notes');
  assert(doc.outline.first.slug == 'overview');
  assert(html.isNotEmpty && text.isNotEmpty && summary['blockCount'] == doc.blocks.length);
}
```

---

## 2. Configuration (`MarkdownOptions`)

`MarkdownOptions` provides four constructors for common presets plus `copyWith(...)` for fine-grained overrides:

| Preset Constructor | Enabled Feature Set |
| :--- | :--- |
| `const MarkdownOptions(...)` | Default GFM core flags (`gfmTables`, `gfmStrikethrough`, `gfmTaskLists`, `gfmAutolinks`, `gfmTagFilter`) enabled; optional extensions off; `sanitizeUrls: true`, `sanitizeHtml: false`. |
| `const MarkdownOptions.commonMark(...)` | Strict CommonMark `0.31.2` compliance with all GFM and optional extensions disabled; `sanitizeUrls: true`, `sanitizeHtml: false`. |
| `const MarkdownOptions.gfm(...)` | Standard GitHub Flavored Markdown (`0.29.0.gfm.13`): enables all five core GFM flags plus `footnotes: true` and `headingSlugs: true` by default; individual extensions remain overridable. |
| `const MarkdownOptions.extended(...)` | Enables GFM plus every optional block and inline extension (`footnotes`, `alerts`, `frontmatter`, `definitionLists`, `math`, `headingSlugs`, `highlight`, `subscript`, `superscript`, `emoji`, `smartPunctuation`, `explicitHeadingIds`, `detailsBlocks`, `figureBlocks`, `alignedBlocks`, `kbd`, `abbreviations`, `inlineBreaks`). |

### Complete Option Reference

| Field | Type | Default (`MarkdownOptions()`) | Description |
| :--- | :--- | :--- | :--- |
| `gfmTables` | `bool` | `true` | Parses GFM pipe tables (`TableNode`). |
| `gfmStrikethrough` | `bool` | `true` | Parses GFM strikethrough (`~...~` / `~~...~~` -> `StrikethroughNode`). |
| `gfmTaskLists` | `bool` | `true` | Parses GFM task checkboxes (`- [ ]` / `- [x]` -> `ListItemNode.taskState`). |
| `gfmAutolinks` | `bool` | `true` | Parses GFM extended autolinks (`www.`, `http(s)://`, emails). |
| `gfmTagFilter` | `bool` | `true` | Escapes GFM disallowed raw HTML opening tags (`<script`, `<style`, `<iframe`, etc.). |
| `footnotes` | `bool` | `false` (`true` in `.gfm()`) | Enables footnote definitions (`[^id]: ...`) and inline citations (`[^id]`). |
| `alerts` | `bool` | `false` | Enables GitHub-style blockquote alerts (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`). |
| `frontmatter` | `bool` | `false` | Extracts leading YAML (`---`) or TOML (`+++`) frontmatter into `FrontmatterNode` and `MarkdownDocument.frontmatter`. |
| `definitionLists` | `bool` | `false` | Parses PHP Markdown Extra style definition lists (`DefinitionListNode`). |
| `math` | `bool` | `false` | Parses inline (`$...$`) and display (`$$...$$`) LaTeX math into `MathInlineNode` and `MathBlockNode`. |
| `headingSlugs` | `bool` | `false` (`true` in `.gfm()`) | Populates deduplicated GitHub-style anchor slugs on `HeadingNode.slug` and `MarkdownDocument.outline`. |
| `highlight` | `bool` | `false` | Parses `==text==` into `HighlightNode` (`<mark>`). |
| `subscript` | `bool` | `false` | Parses `~text~` into `SubscriptNode` (`<sub>`) without breaking `~~strike~~`. |
| `superscript` | `bool` | `false` | Parses `^text^` into `SuperscriptNode` (`<sup>`). |
| `emoji` | `bool` | `false` | Expands common `:shortcode:` emoji tokens (`:rocket:`, `:tada:`, etc.). |
| `smartPunctuation` | `bool` | `false` | Converts `--`, `---`, `...`, and straight quotes into typographic punctuation. |
| `explicitHeadingIds` | `bool` | `false` | Parses trailing `{#custom-id}` heading attributes into `HeadingNode.explicitId` and emits `id="..."` in HTML. |
| `detailsBlocks` | `bool` | `false` | Extracts `<details>` / `<summary>` blocks into structured `DetailsBlockNode`s. |
| `figureBlocks` | `bool` | `false` | Extracts `<figure>` / `<figcaption>` blocks into structured `FigureBlockNode`s. |
| `alignedBlocks` | `bool` | `false` | Extracts `<div align="...">` containers into structured `AlignedBlockNode`s. |
| `kbd` | `bool` | `false` | Parses inline `<kbd>...</kbd>` tags into `KbdInlineNode`s. |
| `abbreviations` | `bool` | `false` | Extracts `*[ABBR]: Expansion` definitions and wraps matching text in `AbbrInlineNode`. |
| `inlineBreaks` | `bool` | `false` | Parses inline `<br>` / `<br />` HTML tags into `InlineBreakNode`s. |
| `sanitizeHtml` | `bool` | `false` | Strips dangerous raw HTML elements, `on*` event attributes, `srcdoc`, unsafe CSS styles, and disallowed URI attributes. |
| `sanitizeUrls` | `bool` | `true` | Validates link, image, and `<picture>` destinations against `urlPolicy`. |
| `collapseNestedStrong` | `bool` | `false` | Collapses nested `<strong>` tags during HTML rendering to match `cmark 0.29` output. |
| `maxInputLength` | `int` (getter) | `500000` | Optional override merged into `effectiveBudgets.maxInputLength`. |
| `maxNestingDepth` | `int` (getter) | `64` | Optional override merged into `effectiveBudgets.maxNestingDepth`. |
| `budgets` | `MarkdownBudgets` | `const MarkdownBudgets()` | Full resource and complexity limit bundle (`effectiveBudgets` merges top-level overrides). |
| `urlPolicy` | `MarkdownUrlPolicy` | `const MarkdownUrlPolicy()` | Scheme and host validation policy applied when `sanitizeUrls` is `true`. |

---

## 3. Security & Resource Budgets (`MarkdownBudgets` & `MarkdownUrlPolicy`)

### `MarkdownBudgets`

Configure deterministic limits on untrusted Markdown inputs via `MarkdownBudgets` (exposes `copyWith(...)`):

| Field | Default Constant | Default Value | Protected Resource |
| :--- | :--- | ---: | :--- |
| `maxInputLength` | `defaultMaxInputLength` | `500000` | Maximum input UTF-16 code units accepted per parse call. |
| `maxNestingDepth` | `defaultMaxNestingDepth` | `64` | Maximum nested container and inline depth. |
| `maxBlocks` | `defaultMaxBlocks` | `50000` | Maximum AST block nodes emitted per document. |
| `maxTableColumns` | `defaultMaxTableColumns` | `128` | Maximum columns per GFM pipe table. |
| `maxTableRows` | `defaultMaxTableRows` | `10000` | Maximum body rows per GFM pipe table. |
| `maxHtmlBytes` | `defaultMaxHtmlBytes` | `250000` | Cumulative raw HTML emission budget before escaping remaining HTML. |
| `maxTokens` | `defaultMaxTokens` | `500000` | Maximum inline scanner and delimiter-stack work units per document. |

### `MarkdownUrlPolicy`

`MarkdownUrlPolicy` validates URI destinations after stripping control characters (`<= 0x20`, `0x7F`) to neutralize obfuscated schemes:

| Member | Type / Signature | Default & Behavior |
| :--- | :--- | :--- |
| `blockedSchemes` | `Set<String>` | `defaultBlockedSchemes` (`{'javascript', 'vbscript', 'data'}`). |
| `allowedSchemes` | `Set<String>?` | `null` (when non-null, overrides `blockedSchemes` as a strict scheme allowlist). |
| `allowedHosts` | `Set<String>?` | `null` (when non-null, restricts authority hosts case-insensitively after stripping userinfo and ports). |
| `allowRelative` | `bool` | `true` — permits scheme-less relative paths (and empty destinations). |
| `allowFragments` | `bool` | `true` — permits `#section` fragment links. |
| `allowSafeImageDataUrls` | `bool` | `false` — when `true`, allows base64 `data:image/(png|jpeg|jpg|gif|webp)` URIs while keeping SVG and HTML `data:` URIs blocked. |
| `isAllowed` | `bool isAllowed(String url)` | Returns `true` if `url` satisfies the policy. |
| `sanitize` | `String sanitize(String url, {String fallback = ''})` | Returns `url` if allowed, otherwise returns `fallback`. |

```dart
import 'package:markdown_engine/markdown_engine.dart';

const MarkdownOptions strictUserContent = MarkdownOptions.gfm(
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
  ),
);
```

---

## 4. Incremental Editing & Streaming APIs

### `IncrementalMarkdownParser` & `IncrementalParseResult`

Reuse unchanged top-level AST blocks (preserving stable `blockId` values) across live editor mutations while shifting suffix `SourceSpan`s cleanly:

| Symbol | Signature / Members | Behavior |
| :--- | :--- | :--- |
| `IncrementalMarkdownParser` | `const IncrementalMarkdownParser({MarkdownEngine engine = const MarkdownEngine()})` | Stateful-free incremental parser wrapping a `MarkdownEngine`. |
| `parseIncremental` | `IncrementalParseResult parseIncremental(String newSource, {MarkdownDocument? previousDocument, IncrementalParseResult? previousResult, int? editStartOffset, int? editOldEndOffset, int? editNewEndOffset, MarkdownOptions? options})` | Diffs `newSource` against the previous document, reuses blank-line-isolated prefix and suffix blocks, parses only the dirty slice, and falls back safely when frontmatter, footnotes, or definitions change. |
| `IncrementalParseResult` | `document`, `reusedBlockCount`, `reparsedBlockCount` | Immutable result pairing the updated `MarkdownDocument` with block reuse counts. |

```dart
import 'package:markdown_engine/markdown_engine.dart';

void editDocument() {
  const IncrementalMarkdownParser parser = IncrementalMarkdownParser(
    engine: MarkdownEngine(defaultOptions: MarkdownOptions.gfm()),
  );

  final IncrementalParseResult v1 = parser.parseIncremental(
    '# Guide\n\nFirst paragraph.\n\nSecond paragraph.\n',
  );
  final IncrementalParseResult v2 = parser.parseIncremental(
    '# Guide\n\nUpdated paragraph.\n\nSecond paragraph.\n',
    previousResult: v1,
    editStartOffset: 9,
  );
  assert(v2.reusedBlockCount == 2 && v2.reparsedBlockCount == 1);
}
```

### `StreamingMarkdownController`

Accumulate chunked token streams while freezing settled prefix blocks and re-parsing only the active trailing slice:

| Member | Type / Signature | Behavior |
| :--- | :--- | :--- |
| Constructor | `StreamingMarkdownController({MarkdownEngine engine = const MarkdownEngine(), MarkdownOptions? options})` | Initializes an empty streaming session. |
| `append` | `MarkdownDocument append(String chunk)` | Appends `chunk`, settles completed leading blocks, and returns the updated `MarkdownDocument` snapshot. |
| `replaceText` | `MarkdownDocument replaceText(String fullText)` | Replaces buffered text while preserving already-settled prefix blocks if the settled prefix is unchanged. |
| `finish` | `MarkdownDocument finish()` | Finalizes the stream, producing the exact same semantic AST and HTML as `MarkdownEngine.parse(buffer)`. |
| `reset` | `void reset()` | Clears buffered text, settled blocks, and active blocks back to an empty state. |
| Read-only getters | `effectiveOptions`, `buffer`, `currentDocument`, `document`, `settledBlocks`, `activeBlocks`, `settledBlockCount`, `isFinished`, `html` | Inspect current stream state without triggering extra parses (`html` renders `currentDocument.toHtml()`). |

```dart
import 'package:markdown_engine/markdown_engine.dart';

MarkdownDocument consumeStream(Iterable<String> chunks) {
  final StreamingMarkdownController controller = StreamingMarkdownController(
    options: const MarkdownOptions.gfm(),
  );
  for (final String chunk in chunks) {
    final MarkdownDocument partial = controller.append(chunk);
    assert(partial.blocks.length >= controller.settledBlockCount);
  }
  return controller.finish();
}
```

---

## 5. Sealed AST Reference & Supporting Types

### Supporting Metadata & Value Types

| Type | Key Members | Role |
| :--- | :--- | :--- |
| `SourceSpan` | `startOffset`, `endOffset`, `startLine`, `endLine`, `length`, `shift(offsetDelta, lineDelta)`, `SourceSpan.zero` | UTF-16 offset range and 1-based line numbers attached to every block and inline node. |
| `AlertKind` | `note`, `tip`, `important`, `warning`, `caution` | Severity category for GitHub-style `AlertNode` blocks. |
| `TableAlignment` | `none`, `left`, `center`, `right` | Column and container horizontal alignment for `TableNode`, `TableCellNode`, and `AlignedBlockNode`. |
| `TableCellNode` | `children`, `alignment`, `span`, `toPlainText()`, `shiftSpan(...)` | Single header or body cell inside a `TableNode`. |
| `DefinitionGroup` | `term`, `definitions`, `span`, `toPlainText()`, `shiftSpan(...)` | Term (`<dt>`) and block definition list (`<dd>`) entry inside a `DefinitionListNode`. |
| `MarkdownFrontmatter` | `format` (`'yaml'` / `'toml'`), `raw`, `entries`, `operator [](String key)` | Parsed structured document frontmatter exposed on `MarkdownDocument.frontmatter` and `FrontmatterNode`. |
| `MarkdownOutlineItem` | `text`, `level`, `line`, `slug`, `span` | Source-order heading entry exposed via `MarkdownDocument.outline`. |
| `MarkdownLinkDefinition` | `label`, `normalizedLabel`, `destination`, `title`, `span` | Resolved CommonMark link reference definition exposed via `MarkdownDocument.linkDefinitions`. |

### Block AST Nodes (`sealed class MarkdownBlockNode`)

Every `MarkdownBlockNode` exposes `blockId`, `span`, `toPlainText()`, and `shiftSpan(offsetDelta, lineDelta)`:

| Subtype | Specific Members | Markdown Construct |
| :--- | :--- | :--- |
| `FrontmatterNode` | `frontmatter`, `format`, `raw`, `entries` | Leading YAML (`---`) or TOML (`+++`) metadata block. |
| `HeadingNode` | `level` (`1..6`), `text`, `slug`, `explicitId`, `children`, `isSetext` | ATX (`#`) or setext (`===` / `---`) heading. |
| `ParagraphNode` | `children` | Paragraph (`<p>`). |
| `CodeBlockNode` | `literal`, `info`, `language`, `isFenced`, `codeUnitOffset` | Fenced (```` ``` ```` / `~~~`) or 4-space indented code block. |
| `BlockQuoteNode` | `children` | Blockquote container (`>`). |
| `AlertNode` | `kind` (`AlertKind`), `title`, `children` | GitHub callout (`> [!NOTE]`, `> [!WARNING]`, etc.). |
| `ListNode` | `ordered`, `start`, `tight`, `delimiter`, `items` | Bullet (`<ul>`) or ordered (`<ol>`) list. |
| `ListItemNode` | `taskState`, `isChecked`, `isTaskItem`, `children` | List item (`<li>`), optionally carrying a GFM task checkbox state. |
| `TableNode` | `alignments`, `headers`, `rows` | GFM pipe table (`<table>`). |
| `ThematicBreakNode` | *(inherits `blockId`, `span`)* | Horizontal rule (`---`, `***`, `___`). |
| `HtmlBlockNode` | `literal`, `html`, `blockType` (`1..7`) | CommonMark raw HTML block (types 1–7). |
| `DetailsBlockNode` | `summary`, `summaryInlines`, `initiallyOpen`, `children` | Collapsible `<details>` / `<summary>` disclosure block. |
| `AlignedBlockNode` | `alignment` (`TableAlignment`), `children` | Explicitly aligned container (`<div align="...">`). |
| `FigureBlockNode` | `children`, `caption`, `captionInlines` | `<figure>` container with optional `<figcaption>`. |
| `MathBlockNode` | `latex` | Display LaTeX math block (`$$...$$`). |
| `DefinitionListNode` | `groups` (`List<DefinitionGroup>`) | PHP Markdown Extra definition list (`<dl>`). |
| `FootnoteDefinitionNode` | `label`, `index`, `referenceCount`, `children` | Individual footnote definition (`[^label]: ...`). |
| `FootnoteSectionNode` | `definitions` (`List<FootnoteDefinitionNode>`) | Appended footnotes footer (`<section class="footnotes">`). |

### Inline AST Nodes (`sealed class MarkdownInlineNode`)

Every `MarkdownInlineNode` exposes `span`, `toPlainText()`, and `shiftSpan(offsetDelta, lineDelta)`:

| Subtype | Specific Members | Markdown Construct |
| :--- | :--- | :--- |
| `TextNode` | `text` | Decoded literal text run. |
| `SoftBreakNode` | *(inherits `span`)* | Soft line break (`\n` inside a paragraph). |
| `HardBreakNode` | *(inherits `span`)* | Hard line break (`  \n` or `\\\n`). |
| `CodeSpanNode` | `literal`, `code` | Backtick-delimited inline code span (`<code>`). |
| `EmphasisNode` | `children`, `delimiter` (`'*'` / `'_'`) | Italic emphasis (`<em>`). |
| `StrongNode` | `children`, `delimiter` (`'**'` / `'__'`) | Bold strong emphasis (`<strong>`). |
| `StrikethroughNode` | `children` | GFM strikethrough (`<del>`). |
| `HighlightNode` | `children` | Highlighted text (`==text==` -> `<mark>`). |
| `SubscriptNode` | `children` | Subscript span (`~text~` -> `<sub>`). |
| `SuperscriptNode` | `children` | Superscript span (`^text^` -> `<sup>`). |
| `LinkNode` | `destination`, `title`, `children`, `isAutolink` | Inline, reference, or autolink hyperlink (`<a>`). |
| `ImageNode` | `destination`, `alt`, `title`, `width`, `height`, `children` | Markdown or sized image (`<img>`). |
| `MathInlineNode` | `latex` | Inline LaTeX math (`$...$`). |
| `FootnoteRefNode` | `label`, `index`, `occurrenceIndex` | Inline footnote citation (`[^label]`). |
| `KbdInlineNode` | `children` | Keyboard key tag (`<kbd>`). |
| `AbbrInlineNode` | `title`, `children` | Expanded abbreviation (`<abbr title="...">`). |
| `AnchorInlineNode` | `id` | Explicit inline anchor (`<a id="..."></a>`). |
| `PictureInlineNode` | `lightSource`, `darkSource`, `alt` | Light/dark theme-aware `<picture>` element. |
| `InlineBreakNode` | *(inherits `span`)* | Parsed inline `<br>` / `<br />` element. |
| `RawHtmlInlineNode` | `html`, `literal` | Raw inline HTML tag, comment, or declaration. |

### Exhaustive Pattern Matching Example

```dart
import 'package:markdown_engine/markdown_engine.dart';

String describeBlock(MarkdownBlockNode block) {
  return switch (block) {
    FrontmatterNode(:final String format) => 'frontmatter ($format)',
    HeadingNode(:final int level, :final String text) => 'H$level: $text',
    ParagraphNode() => 'paragraph',
    CodeBlockNode(:final String? language) => 'code (${language ?? 'plain'})',
    BlockQuoteNode() => 'blockquote',
    AlertNode(:final AlertKind kind) => 'alert (${kind.name})',
    ListNode(:final bool ordered, :final List<ListItemNode> items) =>
      '${ordered ? 'ordered' : 'bullet'} list (${items.length} items)',
    ListItemNode() => 'list item',
    TableNode(:final List<List<TableCellNode>> rows) =>
      'table (${rows.length} rows)',
    ThematicBreakNode() => 'hr',
    HtmlBlockNode(:final int blockType) => 'html block (type $blockType)',
    DetailsBlockNode(:final String summary) => 'details ($summary)',
    AlignedBlockNode(:final TableAlignment alignment) =>
      'aligned (${alignment.name})',
    FigureBlockNode() => 'figure',
    MathBlockNode() => 'math block',
    DefinitionListNode() => 'definition list',
    FootnoteDefinitionNode(:final String label) => 'footnote ($label)',
    FootnoteSectionNode() => 'footnotes section',
  };
}
```

---

## 6. Heading Anchor Slugs (`HeadingSlugGenerator` & `slugifyHeadingText`)

Generate deterministic GitHub-style heading anchor slugs directly outside a full parse:

| Symbol | Signature | Behavior |
| :--- | :--- | :--- |
| `slugifyHeadingText` | `String slugifyHeadingText(String text)` | Case-folds text, converts spaces/tabs to `-`, preserves ASCII alphanumerics, `-`, `_`, and non-ASCII letters/digits, strips punctuation, and returns `'section'` when empty. |
| `HeadingSlugGenerator` | `HeadingSlugGenerator()`, `String generate(String text)` | Tracks previously emitted slugs and appends `-1`, `-2`, ... on collisions (`overview`, `overview-1`, `overview-2`). |

---

## 7. Flutter Package (`package:markdown_engine_flutter/markdown_engine_flutter.dart`)

`markdown_engine_flutter` wraps the pure-Dart engine in zero-reparse widgets, lazy virtualized slivers, widgets-first and Material theming, background isolate document loading, `SelectionArea` integration, and security-gated builders (requiring Dart `^3.8.0` and Flutter `>=3.32.0`).

Importing `package:markdown_engine_flutter/markdown_engine_flutter.dart` also re-exports 19 core types from `markdown_engine` (`AlertKind`, `CodeBlockNode`, `ImageNode`, `IncrementalMarkdownParser`, `IncrementalParseResult`, `MarkdownBlockNode`, `MarkdownBudgets`, `MarkdownDocument`, `MarkdownEngine`, `MarkdownFrontmatter`, `MarkdownInlineNode`, `MarkdownOptions`, `MarkdownOutlineItem`, `MarkdownUrlPolicy`, `MathBlockNode`, `MathInlineNode`, `SourceSpan`, `StreamingMarkdownController`, and `TableAlignment`).

### 7.1 Views & Virtualized Slivers (`MarkdownView` & `SliverMarkdownDocument`)

| Symbol | Constructors / Key Members | Behavior |
| :--- | :--- | :--- |
| `MarkdownView` | `const MarkdownView(String data, {options, engine, controller, theme, delegates, selectable = true, scrollable = true, showFrontmatter = true, padding = EdgeInsets.zero, scrollController, physics, shrinkWrap = false, cacheExtent})` | Parses `data` once in widget state and only re-parses when `data`, `options`, or `engine` changes, ensuring Light/Dark theme toggles perform zero AST re-parses. Uses a virtualized `CustomScrollView` when `scrollable: true` or a compact `Column` when `scrollable: false`. |
| `MarkdownView.document` | `const MarkdownView.document({required MarkdownDocument document, controller, theme, delegates, selectable = true, scrollable = true, showFrontmatter = true, padding = EdgeInsets.zero, scrollController, physics, shrinkWrap = false, cacheExtent})` | Renders a pre-parsed `MarkdownDocument` (for example from `MarkdownDocumentReader` or `IncrementalMarkdownParser`) with zero parsing work inside the widget. |
| `MarkdownView.streaming` | `const MarkdownView.streaming({required StreamingMarkdownController controller, MarkdownController? markdownController, Listenable? listenable, Duration? pollInterval = const Duration(milliseconds: 32), theme, delegates, selectable = true, scrollable = true, showFrontmatter = true, padding = EdgeInsets.zero, scrollController, physics, shrinkWrap = false, cacheExtent})` | Binds directly to a `StreamingMarkdownController`, rendering frozen `settledBlocks` alongside updating `activeBlocks` via an optional external `listenable` or bounded `pollInterval`. |
| `SliverMarkdownDocument` | `const SliverMarkdownDocument({required MarkdownDocument document, theme, delegates, controller, showFrontmatter = true, padding, addAutomaticKeepAlives = false, addRepaintBoundaries = true, remoteImagesApproved = false, onRequestLoadRemoteImages})` | Standalone virtualized sliver built on `SliverChildBuilderDelegate` keyed by `ValueKey<String>(block.blockId)` with `findChildIndexCallback` for state preservation inside caller-owned `CustomScrollView`s; exposes static helper `visibleBlocksFor(document, showFrontmatter: ...)`. |

### 7.2 Theming (`MarkdownTheme`, `MarkdownThemeData`, `MarkdownAlertPalette`, `MarkdownAlertColors`)

| Symbol | Constructors / Key Members | Behavior |
| :--- | :--- | :--- |
| `MarkdownTheme` | `const MarkdownTheme({required MarkdownThemeData data, required Widget child})`, `MarkdownTheme.of(context)`, `MarkdownTheme.maybeOf(context)` | `InheritedTheme` propagating `MarkdownThemeData` down the widget tree; `of(context)` falls back to `MarkdownThemeData.fromTheme(context)` when no explicit `MarkdownTheme` ancestor is present. |
| `MarkdownThemeData` | `const MarkdownThemeData(...)`, `.light(...)`, `.dark(...)`, `.fallback`, `.fromColorScheme(ColorScheme, ...)`, `.fromTheme(BuildContext, ...)`, `.copyWith(...)`, `.lerp(a, b, t)`, `defaultCodeFontFallback` | Immutable token bundle covering `brightness`, `foreground`, `muted`, `accent`, `linkColor`, `codeBackground`, `codeForeground`, `border`, `blockquoteBorder`, `blockquoteBackground`, `tableBorder`, `tableHeaderBackground`, `tableStripeBackground`, `highlightFill`, `alertPalette`, typography (`fontSize`, `lineHeight`, `codeFontSize`, `codeLineHeight`, `blockSpacing`, `h1Scale`–`h6Scale`, `headingLineHeight`, `fontFamily`, `codeFontFamily`), and `effective*` color getters. |
| `MarkdownAlertPalette` | `const MarkdownAlertPalette({note, tip, important, warning, caution})`, `.light()`, `.dark()`, `forKind(AlertKind)`, `copyWith(...)`, `lerp(a, b, t)` | Complete color palette mapping all five GitHub `AlertKind` severities (`note`, `tip`, `important`, `warning`, `caution`). |
| `MarkdownAlertColors` | `const MarkdownAlertColors({required border, required background, required foreground})`, `copyWith(...)`, `lerp(a, b, t)` | Border, background tint, and icon/title foreground triple for a single GitHub alert level. |

### 7.3 Navigation, Reading Position & Background Isolate Reader

| Symbol | Constructors / Key Members | Behavior |
| :--- | :--- | :--- |
| `MarkdownController` | `MarkdownController({MarkdownDocument? initialDocument})`, `document`, `outline`, `parseCount`, `readingPlace`, `scrollController`, `attachScrollController`, `detachScrollController`, `updateDocument`, `registerAnchor` / `unregisterAnchor`, `registerBlock` / `unregisterBlock`, `scrollToAnchor(slug, ...)`, `scrollToLine(line, ...)`, `jumpToPlace(place, ...)` | `ChangeNotifier` coordinating parsed document state, heading outline navigation, footnote/anchor jumps, live reading position synchronization, and `parseCount` telemetry. |
| `MarkdownReadingPlace` | `const MarkdownReadingPlace({required int blockIndex, String? blockId, double offsetFraction = 0.0})`, `MarkdownReadingPlace.start`, `copyWith(...)` | Immutable reading position recording active top-level block index, stable `blockId`, and normalized `0.0..1.0` scroll progress within the block. |
| `MarkdownDocumentReader` | `MarkdownDocumentReader({MarkdownEngine engine = const MarkdownEngine(), int syncThreshold = defaultSyncThreshold, MarkdownDocument? initialDocument})`, `defaultSyncThreshold` (`4096`), `document`, `isParsing`, `lastError`, `lastStackTrace`, `parseCount`, `backgroundParseCount`, `update(source, {options})`, `clear()` | `ChangeNotifier` that parses sources shorter than `syncThreshold` (`4096` UTF-16 code units by default) synchronously and offloads larger documents to a background `Isolate.run` (with web fallback) using latest-wins coalescing. |

### 7.4 Pluggable Builders, Security Delegates & Companion Adapters

| Symbol | Values / Signature | Behavior |
| :--- | :--- | :--- |
| `MarkdownImagePolicy` | `block`, `ask`, `load` | Controls whether remote (`http://`, `https://`, `//`) images render a non-network placeholder (`block`, default for privacy), prompt for user consent (`ask`), or load automatically (`load`). |
| `MarkdownBuilderDelegates` | `const MarkdownBuilderDelegates({imagePolicy = MarkdownImagePolicy.block, onLoadRemoteImages, mathInlineBuilder, mathBlockBuilder, diagramBuilder, codeBlockBuilder, imageBuilder, onTapLink, onOpenWebLink, urlPolicy})`, `copyWith(...)`, `resolveUrlPolicy(fallback)`, `isRemoteImageUrl(destination)` | Bundles pluggable custom widget/span renderers with URL and remote image security policies; interactive links are gated by `MarkdownUrlPolicy` before firing `onTapLink` or `onOpenWebLink`. |
| `MarkdownMathInlineBuilder` | `InlineSpan Function(BuildContext context, MathInlineNode node, TextStyle style, GestureRecognizer? linkRecognizer)` | Renders inline `$...$` math nodes (for example via `tex_math_flutter`'s `TexMathSpan`), receiving the enclosing `linkRecognizer` when nested inside a sanitized hyperlink. |
| `MarkdownMathBlockBuilder` | `Widget Function(BuildContext context, MathBlockNode node)` | Renders display `$$...$$` math blocks (for example via `tex_math_flutter`'s `TexMath`). |
| `MarkdownDiagramBuilder` | `Widget? Function(BuildContext context, CodeBlockNode node)` | Inspected before `codeBlockBuilder` for fenced code blocks (such as `language == 'mermaid'` via `pele_dart`); returning `null` falls back to code block rendering. |
| `MarkdownCodeBlockBuilder` | `Widget Function(BuildContext context, CodeBlockNode node)` | Overrides the built-in fenced/indented code block widget (which includes language badges and copy-to-clipboard buttons). |
| `MarkdownImageBuilder` | `Widget Function(BuildContext context, ImageNode node)` | Custom renderer invoked for images allowed by `imagePolicy` and `MarkdownUrlPolicy`. |
| `MarkdownLinkTapCallback` | `void Function(String destination, String? title)` | Callback fired when a user taps any policy-allowed link destination. |
| `MarkdownWebLinkCallback` | `void Function(Uri uri)` | Callback fired when a user taps a policy-allowed `http` or `https` web URI. |

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

Widget buildIntegratedMarkdownView(
  BuildContext context,
  MarkdownController controller,
  String source,
) {
  return MarkdownTheme(
    data: MarkdownThemeData.fromTheme(context),
    child: MarkdownView(
      source,
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
          // Open validated http/https links externally.
        },
        mathInlineBuilder: (
          BuildContext ctx,
          MathInlineNode node,
          TextStyle style,
          GestureRecognizer? linkRecognizer,
        ) {
          // Delegate to tex_math_flutter's TexMathSpan when installed.
          return TextSpan(text: node.latex, style: style, recognizer: linkRecognizer);
        },
        mathBlockBuilder: (BuildContext ctx, MathBlockNode node) {
          // Delegate to tex_math_flutter's TexMath when installed.
          return Text(node.latex);
        },
        diagramBuilder: (BuildContext ctx, CodeBlockNode node) {
          if (node.language == 'mermaid') {
            // Delegate to pele_dart SVG rendering when installed.
            return Text('Mermaid diagram (${node.literal.length} chars)');
          }
          return null;
        },
      ),
    ),
  );
}
```

See [`packages/markdown_engine_flutter/README.md`](../packages/markdown_engine_flutter/README.md) and [`packages/markdown_engine_flutter/example/lib/main.dart`](../packages/markdown_engine_flutter/example/lib/main.dart) for complete interactive Flutter examples.
