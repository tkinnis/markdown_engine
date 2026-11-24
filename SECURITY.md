# Security Policy

## Security Model of `markdown_engine`

`markdown_engine` parses and renders untrusted Markdown inputs into immutable syntax trees, sanitized HTML, plain text, JSON exports, and Flutter widget/sliver trees deterministically without executing arbitrary scripts, spawning subprocesses, or performing filesystem or network I/O.

### Pure-Dart Execution & Budget Guards

* **Zero DOM, WebView, or Script Execution**: Core parser and exporter code under `packages/markdown_engine/lib/` depends strictly on `package:meta` with no Flutter, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*` imports.
* **Input & Structural Resource Budgets (`MarkdownOptions`)**: Configurable limits bound maximum input UTF-16 length (`maxInputLength`) and maximum block/inline nesting depth (`maxNestingDepth`) alongside table dimension, link-reference, and output caps so pathological inputs cannot trigger stack overflows or quadratic parser blowups.
* **URL Sanitization**: Link and image destinations reject dangerous schemes (`javascript:`, `vbscript:`, `data:text/html`) and control-character obfuscation when URL sanitization is enabled.
* **HTML Filtering & Sanitization**: GFM `tagfilter` and the linear-time HTML sanitizer (`sanitizeHtml: true`) neutralize unsafe raw HTML elements (`<script>`, `<style>`, `<iframe>`) and inline event attributes.

| Guard / Subsystem | Default Target | Protected Resource |
| :--- | :--- | :--- |
| `maxInputLength` | `500000` UTF-16 code units | Raw Markdown document length accepted per parse pass. |
| `maxNestingDepth` | `64` levels | Nested blockquotes, lists, emphasis delimiters, and link brackets. |
| URL scheme allowlist | `http`, `https`, `mailto`, relative, fragment | Blocks `javascript:`, `vbscript:`, and HTML `data:` payloads in links and images. |
| HTML filtering & escaping | GFM `tagfilter` + attribute sanitization | Prevents script injection via raw HTML blocks, inline tags, and footnote anchors. |

---

## Markdown Studio & CLI Tooling Security

`studio/` (`markdown_engine Studio`) and `tool/` are local developer tools outside the publishable `markdown_engine` and `markdown_engine_flutter` packages:

* **Markdown Studio (`studio/`)**: Runs locally as a macOS Flutter desktop workbench (`markdown_engine Studio`) inspecting `markdown_engine` and `markdown_engine_flutter` outputs against vendored corpus fixtures.
* **Spec & Benchmark Tooling (`tool/`)**: Executes offline against vendored spec files in `corpus/spec/` whose SHA-256 digests are verified against [`REFERENCE.md`](REFERENCE.md).

---

## Supported Versions

Security fixes apply to the current lockstep release line across `packages/markdown_engine` and `packages/markdown_engine_flutter` (see [`REFERENCE.md`](REFERENCE.md)):

| Version | Supported |
| :--- | :---: |
| Latest release | Yes |
| Older releases | No |

---

## Reporting a Vulnerability

If you discover a security vulnerability in `markdown_engine` or `markdown_engine_flutter` (such as an XSS vector, unsafe URL scheme bypass, GFM `tagfilter` bypass, or quadratic/stack-overflow DoS input):

1. **Do not open a public GitHub issue.**
2. Report the vulnerability privately through [**GitHub Private Vulnerability Reporting**](https://github.com/tkinnis/markdown_engine/security/advisories/new) on this repository.
3. Include a minimal Markdown snippet or `MarkdownOptions` configuration that reproduces the issue alongside expected and actual behavior.

We will acknowledge receipt within 48 hours and coordinate validation, patching, and responsible disclosure.
