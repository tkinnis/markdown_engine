# markdown_engine_studio

macOS Flutter inspection and streaming workbench for **`markdown_engine`** and **`markdown_engine_flutter`**.

## Features

* **Preset Sample Selector**: Switch between `CommonMark & GFM Showcase`, `Comprehensive Markdown Guide` (full Markdown syntax guide, all 33 Mermaid diagram families, and comprehensive LaTeX math gallery loaded from `assets/comprehensive_markdown_guide.md`), `Kitchen Sink (Visual Parity)`, `Alerts, Frontmatter & HTML`, `Security & Sanitization`, and `500-Section Virtualization Stress`.
* **Zero-Reparse Light / Dark Theme Switching**: Toggle between Light and Dark `MarkdownThemeData` palettes from the top toolbar while monitoring live `controller.parseCount` telemetry to confirm zero redundant parses on theme changes.
* **Live Editor & LLM Streaming Simulator**: Edit Markdown source live on the left pane or flip into **Streaming Mode** for interactive Play, Pause, Step, Finish, and Reset playback with adjustable chunk intervals, live `settledBlockCount`, total/active block counts, and per-chunk parse duration in microseconds.
* **Virtualized Preview, Outline Jump & Custom Hooks**: Render documents lazily with `MarkdownView` and `MarkdownView.streaming`, jump directly to headings via the live `controller.outline` sidebar (`controller.scrollToAnchor`), inspect custom `mathInlineBuilder`, `mathBlockBuilder`, and `diagramBuilder` demo cards, and verify `MarkdownUrlPolicy` filtering via live link-audit badges, status banners, and snackbars.
* **AST, SourceSpans, HTML & Plain-Text Inspector**: Toggle the right-hand inspector between an expandable AST and `SourceSpan` tree (`blockId`, node type, 1-based line ranges, and UTF-16 offsets), serialized `document.toHtml()` output, and `document.toPlainText()` previews.

## Setup, Tests & Launch

Resolve workspace dependencies at the repository root, then run headless widget tests or launch the macOS desktop workbench:

```bash
flutter pub get
(cd studio && flutter test)
cd studio && flutter run -d macos
```

See the [Comparison Studio Guide](../doc/STUDIO_GUIDE.md) for workspace architecture and accompanying CLI verification tools.
