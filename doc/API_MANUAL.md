# API Manual

This manual documents every public symbol exported by **`package:markdown_engine/markdown_engine.dart`** (pure Dart) and provides an overview of **`package:markdown_engine_flutter/markdown_engine_flutter.dart`** (Flutter widgets and theming).

## Installation

```bash
# Pure Dart (requires Dart ^3.8.0, package:meta only)
dart pub add markdown_engine

# Flutter (requires Dart ^3.13.0 and Flutter >=3.47.0)
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
| `MarkdownDocument` | `source`, `options`, `blocks`, `frontmatter`, `outline`, `footnotes`, `remoteImageAddresses`, `linkDefinitions`, `abbreviations`, `isEmpty`, `toHtml()`, `toPlainText()`, `toJson()` | Immutable parsed document holding frozen AST blocks, lazy `source`/`outline`/`remoteImageAddresses` evaluation on parser-built documents, extracted metadata, and HTML/text/JSON exporters. |
| `HtmlRenderer` | `const HtmlRenderer({MarkdownOptions options = const MarkdownOptions()})`, `String render(List<MarkdownBlockNode> blocks)` | Renders any list of `MarkdownBlockNode`s to CommonMark `0.31.2` / `cmark-gfm` HTML while enforcing `gfmTagFilter`, `sanitizeHtml`, `sanitizeUrls`, and `maxHtmlBytes`. |

```dart
import 'package:markdown_engine/markdown_engine.dart';

void main() {
  const MarkdownEngine engine = MarkdownEngine();

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
| `const MarkdownOptions(...)` | Complete out-of-the-box configuration: all 23 extension flags (`gfmTables`, `gfmStrikethrough`, `gfmTaskLists`, `gfmAutolinks`, `gfmTagFilter`, `footnotes`, `alerts`, `frontmatter`, `definitionLists`, `math`, `headingSlugs`, `highlight`, `subscript`, `superscript`, `emoji`, `smartPunctuation`, `explicitHeadingIds`, `detailsBlocks`, `figureBlocks`, `alignedBlocks`, `kbd`, `abbreviations`, `inlineBreaks`) default to `true` and are individually opt-out; `sanitizeUrls: true`, `sanitizeHtml: false`, `urlPolicy: const MarkdownUrlPolicy.strict()`. |
| `const MarkdownOptions.commonMark(...)` | Strict CommonMark `0.31.2` compliance with all 23 GFM and optional extensions disabled (`false`); `sanitizeUrls: true`, `sanitizeHtml: false`, `urlPolicy: const MarkdownUrlPolicy()`. |
| `const MarkdownOptions.gfm(...)` | Standard GitHub Flavored Markdown (`0.29.0.gfm.13`): enables all five core GFM flags plus `footnotes: true` and `headingSlugs: true` by default while keeping the remaining 16 extensions `false` (`math: false`, etc.); `urlPolicy: const MarkdownUrlPolicy()`; individual extensions remain overridable. |
| `const MarkdownOptions.extended(...)` | Named preset matching `const MarkdownOptions()` with all 23 GFM and optional block/inline extensions enabled and `urlPolicy: const MarkdownUrlPolicy.strict()`. |

### Complete Option Reference

| Field | Type | Default (`MarkdownOptions()`) | Description |
| :--- | :--- | :--- | :--- |
| `gfmTables` | `bool` | `true` | Parses GFM pipe tables (`TableNode`). |
| `gfmStrikethrough` | `bool` | `true` | Parses GFM strikethrough (`~...~` / `~~...~~` -> `StrikethroughNode`). |
| `gfmTaskLists` | `bool` | `true` | Parses GFM task checkboxes (`- [ ]` / `- [x]` -> `ListItemNode.taskState`). |
| `gfmAutolinks` | `bool` | `true` | Parses GFM extended autolinks (`www.`, `http(s)://`, emails). |
| `gfmTagFilter` | `bool` | `true` | Escapes GFM disallowed raw HTML opening tags (`<script`, `<style`, `<iframe`, etc.). |
| `footnotes` | `bool` | `true` (`false` in `.commonMark()`) | Enables footnote definitions (`[^id]: ...`) and inline citations (`[^id]`). |
| `alerts` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Enables GitHub-style blockquote alerts (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`). |
| `frontmatter` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Extracts leading YAML (`---`) or TOML (`+++`) frontmatter into `FrontmatterNode` and `MarkdownDocument.frontmatter`. |
| `definitionLists` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Parses PHP Markdown Extra style definition lists (`DefinitionListNode`). |
| `math` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Parses inline (`$...$`, `\(...\)`) and display (`$$...$$`, `\[...\]`) LaTeX math into `MathInlineNode` and `MathBlockNode`. |
| `headingSlugs` | `bool` | `true` (`false` in `.commonMark()`) | Populates deduplicated GitHub-style anchor slugs on `HeadingNode.slug` and `MarkdownDocument.outline`. |
| `highlight` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Parses `==text==` into `HighlightNode` (`<mark>`). |
| `subscript` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Parses `~text~` into `SubscriptNode` (`<sub>`) without breaking `~~strike~~`. |
| `superscript` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Parses `^text^` into `SuperscriptNode` (`<sup>`). |
| `emoji` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Expands common `:shortcode:` emoji tokens (`:rocket:`, `:tada:`, etc.). |
| `smartPunctuation` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Converts `--`, `---`, `...`, and straight quotes into typographic punctuation. |
| `explicitHeadingIds` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Parses trailing `{#custom-id}` heading attributes into `HeadingNode.explicitId` and emits `id="..."` in HTML. |
| `detailsBlocks` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Extracts `<details>` / `<summary>` blocks into structured `DetailsBlockNode`s. |
| `figureBlocks` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Extracts `<figure>` / `<figcaption>` blocks into structured `FigureBlockNode`s. |
| `alignedBlocks` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Extracts `<div align="...">` containers into structured `AlignedBlockNode`s. |
| `kbd` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Parses inline `<kbd>...</kbd>` tags into `KbdInlineNode`s. |
| `abbreviations` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Extracts `*[ABBR]: Expansion` definitions and wraps matching text in `AbbrInlineNode`. |
| `inlineBreaks` | `bool` | `true` (`false` in `.commonMark()` / `.gfm()`) | Parses inline `<br>` / `<br />` HTML tags into `InlineBreakNode`s. |
| `sanitizeHtml` | `bool` | `false` | Strips dangerous raw HTML elements, `on*` event attributes, `srcdoc`, unsafe CSS styles, and disallowed URI attributes. |
| `sanitizeUrls` | `bool` | `true` | Validates link, image, and `<picture>` destinations against `urlPolicy`. |
| `collapseNestedStrong` | `bool` | `false` | Collapses nested `<strong>` tags during HTML rendering to match `cmark 0.29` output. |
| `maxInputLength` | `int` (getter) | `500000` | Optional override merged into `effectiveBudgets.maxInputLength`. |
| `maxNestingDepth` | `int` (getter) | `64` | Optional override merged into `effectiveBudgets.maxNestingDepth`. |
| `budgets` | `MarkdownBudgets` | `const MarkdownBudgets()` | Full resource and complexity limit bundle (`effectiveBudgets` merges top-level overrides). |
| `urlPolicy` | `MarkdownUrlPolicy` | `const MarkdownUrlPolicy.strict()` | Scheme and host validation policy applied when `sanitizeUrls` is `true` (`.commonMark()` and `.gfm()` default to `const MarkdownUrlPolicy()`). |

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
| `maxOutputBytes` | `defaultMaxOutputBytes` | `4194304` | Maximum cumulative rendered HTML output and reference/abbreviation expansion budget. |

### `MarkdownUrlPolicy`

`MarkdownUrlPolicy` validates URI destinations after stripping control, Unicode whitespace, and zero-width characters to neutralize obfuscated schemes, backslashes (`/\`, `\/`, `\\`), and unexpected authority userinfo:

| Member | Type / Signature | Default & Behavior |
| :--- | :--- | :--- |
| `MarkdownUrlPolicy(...)` | `const MarkdownUrlPolicy({...})` | Blocklist constructor rejecting `blockedSchemes`, protocol-relative `//`, and userinfo `@` by default (`allowProtocolRelative: false`, `allowUserInfo: false`). |
| `MarkdownUrlPolicy.strict(...)` | `const MarkdownUrlPolicy.strict({...})` | Strict allowlist constructor (`allowedSchemes = defaultStrictSchemes` `{'http', 'https', 'mailto'}`, `allowProtocolRelative: false`, `allowUserInfo: false`). |
| `blockedSchemes` | `Set<String>` | `defaultBlockedSchemes` (`{'javascript', 'vbscript', 'data'}`). |
| `allowedSchemes` | `Set<String>?` | `null` (`defaultStrictSchemes` in `.strict()`, overriding `blockedSchemes` as a strict scheme allowlist). |
| `allowedHosts` | `Set<String>?` | `null` (when non-null, restricts authority hosts case-insensitively after stripping ports and IPv6 brackets). |
| `allowRelative` | `bool` | `true` — permits scheme-less relative paths (and empty destinations). |
| `allowFragments` | `bool` | `true` — permits `#section` fragment links. |
| `allowSafeImageDataUrls` | `bool` | `false` — when `true`, allows base64 `data:image/(png|jpeg|jpg|gif|webp)` URIs while keeping SVG and HTML `data:` URIs blocked. |
| `allowProtocolRelative` | `bool` | `false` — controls whether protocol-relative authority URLs (`//host/path`) are accepted. |
| `allowUserInfo` | `bool` | `false` — controls whether authority userinfo (`user:pass@host`) is accepted. |
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
    editOldEndOffset: 25,
    editNewEndOffset: 27,
  );
  assert(v2.reusedBlockCount == 2 && v2.reparsedBlockCount == 1);
}
```

### `StreamingMarkdownController`

Accumulate chunked token streams while freezing settled prefix blocks and re-parsing only the active trailing slice:

| Member | Type / Signature | Behavior |
| :--- | :--- | :--- |
| Constructor | `StreamingMarkdownController({MarkdownEngine engine = const MarkdownEngine(), MarkdownOptions? options})` | Initializes an empty streaming session. |
| `append` | `MarkdownDocument append(String chunk)` | Appends `chunk` (checking `maxInputLength` upfront), fast-paths active-tail appends across mid-paragraph updates, open fenced code blocks, single-line blockquotes (`BlockQuoteNode` with one single-line `ParagraphNode`), trailing single-line list-item paragraphs (`ListNode` final item), and open GFM pipe tables (`TableNode` mid-row updates and new `|`-prefixed rows), settles completed leading blocks, notifies registered push listeners, and returns the updated lazy-metadata `MarkdownDocument` snapshot. |
| `replaceText` | `MarkdownDocument replaceText(String fullText)` | Replaces buffered text while preserving already-settled prefix blocks if the settled prefix is unchanged, and notifies push listeners. |
| `finish` | `MarkdownDocument finish()` | Finalizes the stream, producing the exact same semantic AST and HTML as `MarkdownEngine.parse(buffer)` while preserving safe settled blocks and notifying listeners. |
| `reset` | `void reset()` | Clears buffered text, settled blocks, and active blocks back to an empty state and notifies listeners. |
| `addListener` / `removeListener` / `dispose` | `void addListener(void Function() listener)` | Pure-Dart push listener registration notified synchronously whenever `append`, `replaceText`, `finish`, or `reset` updates state. |
| Read-only getters | `effectiveOptions`, `buffer`, `currentDocument`, `document`, `settledBlocks`, `activeBlocks`, `settledBlockCount`, `settledPrefixBlockCount`, `isFinished`, `html` | Inspect current stream state without triggering extra parses (`settledPrefixBlockCount` gives the exact prefix length of `currentDocument.blocks` whose frozen objects remain `identical` across tail chunks, returning `0` while definitions force full reparsing and equaling `currentDocument.blocks.length` after `finish()`; `html` renders `currentDocument.toHtml()`). |

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
| `MathBlockNode` | `latex` | Display LaTeX math block (`$$...$$` or `\[...\]`). |
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
| `MathInlineNode` | `latex` | Inline LaTeX math (`$...$` or `\(...\)`). |
| `FootnoteRefNode` | `label`, `index`, `occurrenceIndex` | Inline footnote citation (`[^label]`). |
| `KbdInlineNode` | `children` | Keyboard key tag (`<kbd>`). |
| `AbbrInlineNode` | `title`, `children` | Expanded abbreviation (`<abbr title="...">`). |
| `AnchorInlineNode` | `id` | Explicit inline anchor (`<a id="..."></a>` or `<a name="..."></a>`). |
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

`markdown_engine_flutter` wraps the pure-Dart engine in zero-reparse widgets, built-in native OpenType TeX math (`tex_math_flutter`) and Mermaid diagram (`pele_dart` + `vector_graphics`) renderers, lazy virtualized slivers, widgets-first and Material theming, background isolate document loading, `SelectionArea` integration, and security-gated builders (requiring Dart `^3.13.0` and Flutter `>=3.47.0`).

Importing `package:markdown_engine_flutter/markdown_engine_flutter.dart` also re-exports 19 core types from `markdown_engine` (`AlertKind`, `CodeBlockNode`, `ImageNode`, `IncrementalMarkdownParser`, `IncrementalParseResult`, `MarkdownBlockNode`, `MarkdownBudgets`, `MarkdownDocument`, `MarkdownEngine`, `MarkdownFrontmatter`, `MarkdownInlineNode`, `MarkdownOptions`, `MarkdownOutlineItem`, `MarkdownUrlPolicy`, `MathBlockNode`, `MathInlineNode`, `SourceSpan`, `StreamingMarkdownController`, and `TableAlignment`).

### 7.1 Views, Virtualized Slivers & Layout-Safe Text (`MarkdownView`, `SliverMarkdownDocument` & `MarkdownRichText`)

| Symbol | Constructors / Key Members | Behavior |
| :--- | :--- | :--- |
| `MarkdownView` | `const MarkdownView(String data, {options, engine, controller, theme, delegates, selectable = true, focusNode, scrollable = true, showFrontmatter = true, remoteImagesApproved = false, padding = EdgeInsets.zero, scrollController, physics, shrinkWrap = false, cacheExtent})` | Parses `data` once in widget state, applies `IncrementalMarkdownParser` automatically on compatible `data` edits, performs zero AST re-parses across Light/Dark `MarkdownTheme` flips, memoizes top-level block and inline subtrees, accelerates plain/formatted prose via `MarkdownRichText` / `FastMarkdownText` / `MarkdownParagraphLeaf` / `MarkdownHorizontalOverflowBox`, guards `SelectionArea` / `SelectableRegion` for `MaterialApp` and `WidgetsApp`, and exports full `toPlainText()` on Select All (`Cmd+A`) across virtualized slivers. |
| `MarkdownView.document` | `const MarkdownView.document({required MarkdownDocument document, controller, theme, delegates, selectable = true, focusNode, scrollable = true, showFrontmatter = true, remoteImagesApproved = false, padding = EdgeInsets.zero, scrollController, physics, shrinkWrap = false, cacheExtent})` | Renders a pre-parsed `MarkdownDocument` (for example from `MarkdownDocumentReader` or `IncrementalMarkdownParser`) with zero parsing work inside the widget. |
| `MarkdownView.streaming` | `const MarkdownView.streaming({required StreamingMarkdownController controller, MarkdownController? markdownController, Listenable? listenable, Duration? pollInterval, theme, delegates, selectable = true, focusNode, scrollable = true, showFrontmatter = true, remoteImagesApproved = false, padding = EdgeInsets.zero, scrollController, physics, shrinkWrap = false, cacheExtent})` | Binds directly to `StreamingMarkdownController` via push listeners (`addListener`/`removeListener`) with zero polling timers (`pollInterval` is a deprecated compatibility no-op), accelerates fully canvas-eligible streams via tail-isolated `RenderMarkdownStreamingCanvas` (`MarkdownStreamingCanvasLeaf` + `MarkdownStreamingSliverAdapter` with visible-viewport prefix `ui.Picture` caching and native `Selectable` support), and for mixed streams containing settled rich blocks (`TexMath`, Mermaid, alerts, `<details>`, custom code builders) splits `CustomScrollView` into a frozen settled-prefix `SliverMarkdownDocument` (`[0, settledCount)` sliced at `settledPrefixBlockCount` before frontmatter filtering, `trailingBlockSpacing: true`, split top+horizontal padding) plus a dedicated trailing `MarkdownStreamingCanvasLeaf` tail (`startBlockIndex`, `includeTopPadding: false`, bottom+horizontal padding) whenever trailing blocks are canvas-supported and `markdownController == null` (falling back to a slot-isolated trailing `SliverMarkdownDocument` while active trailing blocks invoke rich/custom builders, switching cleanly back to the trailing canvas once they settle, preserving cross-sliver `SelectionArea` / `Cmd+A` selection, and supporting post-`finish()` `reset()` / `append()` reuse). |
| `SliverMarkdownDocument` | `const SliverMarkdownDocument({required MarkdownDocument document, theme, delegates, controller, showFrontmatter = true, padding, addAutomaticKeepAlives = true, addRepaintBoundaries = true, remoteImagesApproved = false, onRequestLoadRemoteImages, startBlockIndex = 0, endBlockIndex, trailingBlockSpacing = false, streamingNormalizedSource})` | Stateful virtualized sliver built on a custom `RenderSliverList` and `SliverChildBuilderDelegate` keyed by `ValueKey<String>(block.blockId)` with `findChildIndexCallback`, cached `idToIndex` lookup, built-sliver memoization, optional `[startBlockIndex, endBlockIndex)` prefix slicing, and `addAutomaticKeepAlives = true` by default so active off-screen drag selections persist across scroll; caches measured block extents in a `Float64List` extent cache for `estimateMaxScrollOffset` and performs single-frame leading-child scroll-offset batching when `scrollOffset < precisionErrorTolerance` (issuing one combined `scrollOffsetCorrection` per layout pass up to the viewport/overscroll/cache target, capped after `3` consecutive correction cycles, so fast upward ballistic flings never exceed `RenderViewport.maxLayoutCycles`); exposes `visibleBlocksFor(document, showFrontmatter: ..., startBlockIndex: ..., endBlockIndex: ...)`. |
| `MarkdownRichText` | `const MarkdownRichText(String data, {Key? key, TextStyle? style, StrutStyle? strutStyle, TextAlign? textAlign, TextDirection? textDirection, Locale? locale, bool? softWrap, TextOverflow? overflow, double? textScaleFactor, TextScaler? textScaler, int? maxLines, String? semanticsLabel, String? semanticsIdentifier, TextWidthBasis? textWidthBasis, TextHeightBehavior? textHeightBehavior, Color? selectionColor})` | Drop-in `Text` subclass (`textScaleFactor` deprecated in favor of `textScaler`) that guards paragraph selection and screen-order layout readiness across debug, profile, and release builds; inside an enclosing `SelectionContainer` (such as `SelectionArea` or `MarkdownView`), wraps a layout-aware `SelectionContainer` backed by `_SafeRenderParagraph` (tracking layout readiness explicitly rather than `RenderObject.debugNeedsLayout`, which is always `false` in profile/release) so screen-order sorting, triple-click paragraph selection, `selectAll`, and drag selection wait until layout is clean across off-screen kept-alive slivers, and outside a selection scope (including `SelectionContainer.disabled`) renders a non-selectable paragraph directly. |
| `MarkdownRichText.rich` | `const MarkdownRichText.rich(InlineSpan textSpan, {Key? key, TextStyle? style, StrutStyle? strutStyle, TextAlign? textAlign, TextDirection? textDirection, Locale? locale, bool? softWrap, TextOverflow? overflow, double? textScaleFactor, TextScaler? textScaler, int? maxLines, String? semanticsLabel, String? semanticsIdentifier, TextWidthBasis? textWidthBasis, TextHeightBehavior? textHeightBehavior, Color? selectionColor})` | `Text.rich`-compatible `MarkdownRichText` constructor accepting an `InlineSpan` tree (`TextSpan` and `WidgetSpan` children, with `textScaleFactor` deprecated in favor of `textScaler`), applying ambient `DefaultTextStyle`, `boldText`, spacing overrides, and `Semantics` while enforcing the same release-safe layout readiness guard inside selection scopes. |

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
| `MarkdownController` | `MarkdownController({MarkdownDocument? initialDocument})`, `document`, `outline`, `parseCount`, `readingPlace`, `readingPlaceNotifier`, `showFrontmatter`, `scrollController`, `attachScrollController(..., {owner, showFrontmatter})`, `detachScrollController(..., {owner})`, `updateDocument(..., {incrementParseCount, showFrontmatter})`, `registerAnchor` / `unregisterAnchor`, `registerBlock` / `unregisterBlock`, `scrollToAnchor(slug, ...)`, `scrollToLine(line, ...)`, `jumpToPlace(place, ...)` | `ChangeNotifier` coordinating parsed document state, heading outline navigation, owner-scoped scroll attachment, viewport-measured `readingPlace` updates (isolated on `ValueListenable<MarkdownReadingPlace> readingPlaceNotifier`), and `parseCount` telemetry. |
| `MarkdownReadingPlace` | `const MarkdownReadingPlace({required int blockIndex, String? blockId, double offsetFraction = 0.0})`, `MarkdownReadingPlace.start`, `copyWith(...)` | Immutable reading position recording active top-level block index, stable `blockId`, and normalized `0.0..1.0` scroll progress within the block. |
| `MarkdownDocumentReader` | `MarkdownDocumentReader({MarkdownEngine engine = const MarkdownEngine(), int syncThreshold = defaultSyncThreshold, MarkdownDocument? initialDocument})`, `defaultSyncThreshold` (`4096`), `document`, `value`, `hasRead`, `isParsing`, `lastError`, `lastStackTrace`, `parseCount`, `backgroundParseCount`, `update(source, {options})`, `clear()` | `ChangeNotifier` implementing `ValueListenable<MarkdownDocument>` that parses sources shorter than `syncThreshold` (`4096` UTF-16 code units by default) synchronously and offloads larger documents to `Isolate.run` (falling back synchronously on `IsolateSpawnException`) with in-flight deduplication and latest-wins coalescing. |

### 7.4 Built-In Renderers, Pluggable Builders & Security Delegates

| Symbol | Values / Signature | Behavior |
| :--- | :--- | :--- |
| `MarkdownImagePolicy` | `block`, `ask`, `load` | Controls whether remote/external images render a non-network placeholder (`block`, default for privacy), prompt for user consent (`ask`), or load automatically (`load`). |
| `MarkdownBuiltInRenderers` | `warmUp()`, `configureCaches({int? mathMaxEntries, int? mathMaxBytes, int? mermaidMaxEntries, int? mermaidMaxBytes})`, `resetCacheDefaults()`, `clearCaches()`, `dispose()`, `usePersistentMermaidIsolate` (`bool`, default `true`), `isMermaidWorkerActive` (`bool`), `mathLayoutCount`, `mathCacheHitCount`, `mathCacheLength`, `mathCacheBytes`, `mathMaxEntries`, `mathMaxBytes`, `mermaidRenderCount`, `mermaidCacheHitCount`, `mermaidCacheLength`, `mermaidCacheBytes`, `mermaidMaxEntries`, `mermaidMaxBytes`, `debugForceAsyncMermaidInTests` (`@visibleForTesting`) | Lifecycle, pre-warming, persistent Mermaid worker control, dual entry+byte LRU cache budget configuration, reset, and byte/hit telemetry API for the built-in `tex_math_flutter` math renderer (default `1,024` entries / `8 MiB`) and `pele_dart` + `vector_graphics` Mermaid renderer (default `128` entries / `16 MiB`). Setting `usePersistentMermaidIsolate = false` immediately shuts down any active background Mermaid worker (`isMermaidWorkerActive`) and routes subsequent cold compiles to one-shot `compute()`. `configureCaches(...)` validates positive limits (throwing `RangeError` if `<= 0`) and immediately evicts LRU entries over budget, `warmUp()` pre-loads `NewCMMath-Regular.otf` and primes `pele_dart` (and the persistent worker when enabled) off the UI thread, and `dispose()` awaits worker shutdown and clears pending compile state without altering `usePersistentMermaidIsolate`. |
| `MarkdownBuilderDelegates` | `const MarkdownBuilderDelegates({imagePolicy = MarkdownImagePolicy.block, remoteImagesApproved = false, onLoadRemoteImages, autoScrollToAnchors = true, enableBuiltInMath = true, enableBuiltInMermaid = true, mathInlineBuilder, mathBlockBuilder, diagramBuilder, codeBlockBuilder, imageBuilder, onTapLink, onOpenWebLink, urlPolicy})`, `copyWith(...)`, `resolveUrlPolicy(fallback)`, `normalizeUrlDestination(destination)`, `isRemoteImageUrl(destination)` | Bundles built-in math/Mermaid opt-outs (`enableBuiltInMath`, `enableBuiltInMermaid`), custom override builders (`mathInlineBuilder`, `mathBlockBuilder`, `diagramBuilder`, `codeBlockBuilder`, `imageBuilder`), and URL/image security policies; interactive links are gated by `MarkdownUrlPolicy` before firing `onTapLink` or `onOpenWebLink`, and `#fragment` links automatically scroll attached controllers when `autoScrollToAnchors` is `true`. |
| `MarkdownMathInlineBuilder` | `InlineSpan Function(BuildContext context, MathInlineNode node, TextStyle style, GestureRecognizer? linkRecognizer)` | Optional custom override for inline `$...$` / `\(...\)` math nodes (takes precedence over built-in `tex_math_flutter` rendering), receiving the enclosing `linkRecognizer` when nested inside a sanitized hyperlink. |
| `MarkdownMathBlockBuilder` | `Widget Function(BuildContext context, MathBlockNode node)` | Optional custom override for display `$$...$$` / `\[...\]` math blocks (takes precedence over built-in `tex_math_flutter` rendering). |
| `MarkdownDiagramBuilder` | `Widget? Function(BuildContext context, CodeBlockNode node)` | Optional custom diagram builder inspected before built-in Mermaid (`enableBuiltInMermaid`) and `codeBlockBuilder`; returning `null` falls back to built-in Mermaid rendering for `mermaid` fences or to code block rendering otherwise. |
| `MarkdownCodeBlockBuilder` | `Widget Function(BuildContext context, CodeBlockNode node)` | Overrides the built-in fenced/indented code block widget (which includes language badges and copy-to-clipboard buttons). |
| `MarkdownImageBuilder` | `Widget Function(BuildContext context, ImageNode node)` | Custom renderer invoked for images allowed by `imagePolicy` and `MarkdownUrlPolicy`. |
| `MarkdownLinkTapCallback` | `void Function(String destination, String? title)` | Callback fired when a user taps any policy-allowed link destination. |
| `MarkdownWebLinkCallback` | `void Function(Uri uri)` | Callback fired when a user taps a policy-allowed `http` or `https` web URI. |

```dart
import 'dart:async' show unawaited;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

Widget buildIntegratedMarkdownView(
  BuildContext context,
  MarkdownController controller,
  String source,
) {
  // Optional warm-up pre-loads NewCMMath-Regular.otf and primes pele_dart.
  unawaited(MarkdownBuiltInRenderers.warmUp());

  return MarkdownTheme(
    data: MarkdownThemeData.fromTheme(context),
    child: MarkdownView(
      source, // Renders all 23 extensions, TeX math & Mermaid out of the box.
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
        // Optional override for custom non-Mermaid fences; returning null preserves
        // built-in pele_dart rendering for `mermaid` blocks.
        diagramBuilder: (BuildContext ctx, CodeBlockNode node) {
          if (node.language == 'graphviz') {
            return Text('Custom diagram (${node.literal.length} chars)');
          }
          return null;
        },
      ),
    ),
  );
}
```

See [`packages/markdown_engine_flutter/README.md`](../packages/markdown_engine_flutter/README.md) and [`packages/markdown_engine_flutter/example/lib/main.dart`](../packages/markdown_engine_flutter/example/lib/main.dart) for complete interactive Flutter examples.
