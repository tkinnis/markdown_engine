## 0.2.1

Lockstep patch release aligned with `markdown_engine_flutter` 0.2.1.

- Maintained full CommonMark 0.31.2 and GFM 0.29.0.gfm.13 parser, AST, exporter, incremental editing, streaming, and security parity with `0.2.0`.

## 0.2.0

Lockstep minor release aligned with `markdown_engine_flutter` 0.2.0.

- Maintained full CommonMark 0.31.2 and GFM 0.29.0.gfm.13 parser, AST, exporter, incremental editing, streaming, and security parity with `0.1.0`.

## 0.1.0

Initial public release of `markdown_engine`, a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, immutable AST, exporter, and incremental streaming engine with `package:meta` as its sole runtime dependency.

### Parsing, Specification Parity & AST

- **Two-Phase CommonMark & GFM Parser**: Implemented `MarkdownEngine` and `MarkdownOptions` with full CommonMark 0.31.2 (652/652) and `cmark-gfm` 0.29.0.gfm.13 (670/670 spec + 30/30 extension) HTML parity.
- **Presets & 23 Opt-Out Extensions**: Enabled all 23 extensions by default on `const MarkdownOptions()` (matching `.extended()`), alongside strict `MarkdownOptions.commonMark()` and `MarkdownOptions.gfm()` specification presets.
- **GFM Extensions**: Added pipe tables, strikethrough, task lists, extended autolinks, and HTML `tagfilter`.
- **Extended Markdown Syntax**: Added footnotes, GitHub alert callouts, YAML/TOML frontmatter, definition lists, inline and display LaTeX math, heading slugs, explicit `{#id}` anchors, `==highlight==`, `~subscript~`/`^superscript^`, emoji shortcodes, smart punctuation, disclosure/figure/aligned containers, `<kbd>`, abbreviations, and inline breaks.
- **Immutable Sealed AST**: Introduced 18 `MarkdownBlockNode` and 20 `MarkdownInlineNode` sealed subtypes carrying pooled `blockId` identity, UTF-16 `SourceSpan` ranges, plain-text extraction, and span shifting.
- **Exporters & Slug Utilities**: Added `MarkdownDocument` (HTML, plain-text, and JSON exporters plus lazy metadata getters), `HtmlRenderer`, `HeadingSlugGenerator`, and `slugifyHeadingText`.

### Incremental Editing & Streaming

- **Incremental Editor Diffing**: Added `IncrementalMarkdownParser` and `IncrementalParseResult` to reuse blank-line-isolated prefix and suffix AST blocks with preserved `blockId` values, constant-time edit-offset windowing, and lazy span shifting.
- **Chunked Streaming Controller**: Added `StreamingMarkdownController` with frozen `settledBlocks`, prefix alignment telemetry, pure-Dart push listeners, active-tail fast paths, prefix-preserving `replaceText()`, and full-parity `finish()`.

### Security & Resource Budgets

- **URL Allowlisting & Obfuscation Defense**: Added `MarkdownUrlPolicy` (with `MarkdownUrlPolicy.strict()` default on `MarkdownOptions()`), stripping control, whitespace, and zero-width characters while blocking protocol-relative authority URLs, userinfo, and `javascript:` / `vbscript:` / unsafe `data:` schemes.
- **HTML Filtering & Sanitization**: Added GFM `tagfilter` escaping (`gfmTagFilter`) and a linear-time state-machine HTML5 allowlist sanitizer (`sanitizeHtml`) stripping active elements, `on*` event attributes, `srcdoc`, and unsafe CSS URLs.
- **Complexity Caps (`MarkdownBudgets`)**: Added deterministic limits via `MarkdownBudgets` covering input length (`maxInputLength`), nesting depth (`maxNestingDepth`), block count, table dimensions, raw HTML size, token count, and `maxOutputBytes`.
