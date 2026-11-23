# `markdown_engine` Verification Corpus

The `corpus/` directory holds vendored official specification suites alongside extension, security, and streaming fixtures used by `tool/verify_spec.dart` and `tool/sync_reference.dart`.

## Directory Layout

| Directory | Contents | Verification Scope |
| :--- | :--- | :--- |
| `corpus/spec/` | `commonmark_0.31.2.json` (`652` examples), `gfm_0.29.0_spec.txt` (`672` examples), `gfm_0.29.0_extensions.txt` (`30` examples) | Official CommonMark `0.31.2` and `github/cmark-gfm` `0.29.0.gfm.13` parity suites whose SHA-256 hashes are tracked in [`REFERENCE.md`](../REFERENCE.md). |
| `corpus/extensions/` | `alerts.md`, `frontmatter.md`, `footnotes.md`, `definition_lists.md`, `math.md`, `formatting.md`, `heading_slugs.md`, `html_blocks.md` | Non-spec and extended Markdown constructs. |
| `corpus/security/` | `xss_vectors.md`, `unsafe_urls.md`, `deep_nesting.md`, `large_table.md` | HTML/XSS sanitization, dangerous URL scheme filtering, deep nesting bounds, and table complexity guards. |
| `corpus/streaming/` | `llm_response_chunks.json`, `incremental_edits.json` | Progressive chunked streaming and incremental document edit sequences. |
