## 0.1.0

Initial public release of `markdown_engine`, a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, immutable AST, exporter, and incremental streaming engine with `package:meta` as its sole runtime dependency.

### Parsing, Specification Parity & AST

- **Two-Phase CommonMark & GFM Parser**: Implemented `MarkdownEngine` and `MarkdownOptions` with full CommonMark `0.31.2` (`652/652`) and `cmark-gfm 0.29.0.gfm.13` (`670/670` spec + `30/30` extension) HTML parity.
- **Presets & 23 Opt-Out Extensions**: Enabled all 23 extensions by default on `const MarkdownOptions()` (matching `.extended()`), alongside strict `MarkdownOptions.commonMark()` and `MarkdownOptions.gfm()` specification presets.
- **Extended Syntax Support**: Added GFM pipe tables, strikethrough, task lists, extended autolinks, `tagfilter`, footnotes, GitHub alert callouts, YAML/TOML frontmatter, definition lists, inline/display LaTeX math, GitHub heading slugs, explicit `{#id}` heading anchors, `==highlight==`, `~subscript~`, `^superscript^`, emoji shortcodes, smart punctuation, `<details>`, `<figure>`, `<div align>`, `<kbd>`, abbreviations, and inline `<br>` breaks.
- **Immutable Sealed AST**: Introduced 18 `MarkdownBlockNode` and 20 `MarkdownInlineNode` sealed subtypes carrying pooled `blockId` identity, UTF-16 `SourceSpan` ranges, `toPlainText()`, and `shiftSpan()` relocation.
- **Exporters & Slug Utilities**: Added `MarkdownDocument` (`toHtml()`, `toPlainText()`, `toJson()`, lazy `source`, `outline`, and `remoteImageAddresses`), `HtmlRenderer`, `HeadingSlugGenerator`, and `slugifyHeadingText`.

### Incremental Editing & Streaming

- **Incremental Editor Diffing**: Added `IncrementalMarkdownParser` and `IncrementalParseResult` to reuse blank-line-isolated prefix and suffix AST blocks with preserved `blockId` values, constant-time edit-offset windowing, and lazy span shifting.
- **Chunked Streaming Controller**: Added `StreamingMarkdownController` with frozen `settledBlocks`, `settledPrefixBlockCount` alignment, pure-Dart push listeners (`addListener`, `removeListener`, `dispose`), active-tail fast paths, prefix-preserving `replaceText()`, and full-parity `finish()`.

### Security & Resource Budgets

- **URL Allowlisting & Obfuscation Defense**: Added `MarkdownUrlPolicy` (with `MarkdownUrlPolicy.strict()` default on `MarkdownOptions()`), stripping control, whitespace, and zero-width characters while blocking protocol-relative `//`, userinfo `@`, `javascript:`, `vbscript:`, and unsafe `data:` URIs.
- **HTML Filtering & Sanitization**: Added GFM `tagfilter` escaping (`gfmTagFilter`) and a linear-time state-machine HTML5 allowlist sanitizer (`sanitizeHtml`) stripping active elements, `on*` event attributes, `srcdoc`, and unsafe CSS URLs.
- **Complexity Caps (`MarkdownBudgets`)**: Added deterministic limits for `maxInputLength`, `maxNestingDepth`, `maxBlocks`, `maxTableColumns`, `maxTableRows`, `maxHtmlBytes`, `maxTokens`, and `maxOutputBytes`.
