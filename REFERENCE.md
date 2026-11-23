# Reference Specification & Upstream Pins

This document is the **single source of truth** for the upstream CommonMark and GitHub Flavored Markdown (`cmark-gfm`) specifications, fixture counts, and SHA-256 digests that **`markdown_engine`** targets and verifies via `tool/sync_reference.dart` and `tool/verify_spec.dart`.

---

## Pinned Versions & Integrity

| Component | Version / Value | Notes |
| :--- | :--- | :--- |
| `markdown_engine` | See `packages/markdown_engine/pubspec.yaml` | Authoritative lockstep pure-Dart core package version (synchronized with `packages/markdown_engine/CHANGELOG.md` via `tool/check_versions.dart`). |
| `markdown_engine_flutter` | See `packages/markdown_engine_flutter/pubspec.yaml` | Authoritative lockstep Flutter rendering package version (synchronized with `packages/markdown_engine_flutter/CHANGELOG.md` via `tool/check_versions.dart`). |
| `commonmark` | `0.31.2` | Pinned CommonMark specification (`https://spec.commonmark.org/0.31.2/spec.json`, `652` official examples). |
| `cmark-gfm` | `0.29.0.gfm.13` | Pinned GitHub Flavored Markdown reference (`github/cmark-gfm` tag `0.29.0.gfm.13`, `test/spec.txt` `672` examples + `test/extensions.txt` `30` examples). |

---

## Vendored Spec Fixtures & SHA-256 Digests

`tool/sync_reference.dart --verify` computes the SHA-256 digest of every vendored file under `corpus/spec/` and enforces an exact match against the hashes recorded below:

| File | Upstream Source | Examples | SHA-256 Digest |
| :--- | :--- | ---: | :--- |
| `corpus/spec/commonmark_0.31.2.json` | `https://spec.commonmark.org/0.31.2/spec.json` | 652 | `d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20` |
| `corpus/spec/gfm_0.29.0_spec.txt` | `github/cmark-gfm` (`0.29.0.gfm.13`) `test/spec.txt` | 672 | `7d8e5814befec287ac116786d81ff14e0adc9b13295b4494649e995408fd871c` |
| `corpus/spec/gfm_0.29.0_extensions.txt` | `github/cmark-gfm` (`0.29.0.gfm.13`) `test/extensions.txt` | 30 | `a2a45e98be9fca95f564f927265a0f63beea6cae5369d1cf4bde44caa51b2a3a` |

---

## Specification Breakdown & Extension Scope

### CommonMark `0.31.2` (`652` Examples)

The official CommonMark `0.31.2` JSON test suite covers tabs, thematic breaks, ATX and setext headings, indented and fenced code blocks, HTML blocks, link reference definitions, paragraphs, blank lines, block quotes, list items and lists, backslash escapes, entity and numeric character references, code spans, emphasis and strong emphasis, links, images, autolinks, raw HTML, hard and soft line breaks, and textual content.

### GitHub Flavored Markdown `0.29.0.gfm.13`

* **`test/spec.txt` (`672` examples)**: `648` core CommonMark `0.29` examples, `22` inline GFM extension examples (`8` `table`, `2` `strikethrough`, `11` `autolink`, `1` `tagfilter`), and `2` `disabled` task-list examples.
* **`test/extensions.txt` (`30` examples)**: Dedicated GFM extension and interoperability suite covering tables, strikethrough, autolinks (including `1` `<IGNORE>` crash-regression fixture), HTML `tagfilter`, footnotes, and task lists.

### Additional Corpus & Engine Suites

| Suite | Path | Scope |
| :--- | :--- | :--- |
| **Extensions** | `corpus/extensions/` | GitHub alerts, YAML/TOML frontmatter, footnotes, definition lists, inline/display math, subscript/superscript/highlight/emoji/smartypants formatting, heading slugs, and HTML blocks. |
| **Security** | `corpus/security/` | XSS HTML injection vectors, unsafe URL schemes (`javascript:`, `vbscript:`, `data:`), deep nesting stress tests, and large table bounds. |
| **Streaming** | `corpus/streaming/` | Chunked streaming response sequences and incremental editor diff updates. |
