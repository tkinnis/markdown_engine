# `markdown_engine` Verification Corpus

The `corpus/` directory stores vendored CommonMark and GitHub Flavored Markdown specification fixtures alongside extension, security, and streaming test suites used by `tool/verify_spec.dart` and `tool/sync_reference.dart`.

## Directory Layout

| Directory | Contents | Verification Scope |
| :--- | :--- | :--- |
| `corpus/spec/` | `commonmark_0.31.2.json` (`652` examples), `gfm_0.29.0_spec.txt` (`672` examples), `gfm_0.29.0_extensions.txt` (`30` examples) | Official CommonMark `0.31.2` and `github/cmark-gfm` `0.29.0.gfm.13` parity suites tracked in [`REFERENCE.md`](../REFERENCE.md). |
| `corpus/extensions/` | `alerts.md`, `definition_lists.md`, `footnotes.md`, `formatting.md`, `frontmatter.md`, `heading_slugs.md`, `html_blocks.md`, `math.md` | Extended Markdown block and inline syntax fixtures. |
| `corpus/security/` | `deep_nesting.md`, `large_table.md`, `unsafe_urls.md`, `xss_vectors.md` | HTML/XSS sanitization, URL scheme filtering, nesting depth limits, and table complexity guards. |
| `corpus/streaming/` | `incremental_edits.json`, `llm_response_chunks.json` | Progressive chunked streaming and incremental editor edit sequences. |

See [`REFERENCE.md`](../REFERENCE.md), [`doc/COVERAGE.md`](../doc/COVERAGE.md), and [`doc/REFERENCE_SYNC.md`](../doc/REFERENCE_SYNC.md) for integrity hashes, live parity totals, and fixture synchronization steps.
