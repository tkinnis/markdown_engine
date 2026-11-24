# markdown_engine_studio

macOS Flutter inspection and streaming workbench for **`markdown_engine`** and **`markdown_engine_flutter`**.

## Features

* **Preset Sample Selector**: Switch among `CommonMark & GFM Showcase`, `Comprehensive Markdown Guide` (`StudioPresetId.comprehensiveGuide`, loaded from `assets/comprehensive_markdown_guide.md`), `Kitchen Sink`, `Alerts, Frontmatter & HTML`, `Security & Sanitization`, and `500-Section Virtualization Stress`.
* **Zero-Reparse Theme Switching**: Toggle Light and Dark `MarkdownThemeData` palettes from the toolbar while monitoring `controller.parseCount` to confirm zero redundant parses.
* **Live Editor & Streaming Simulator**: Edit Markdown live on the left pane or switch to **Streaming Mode** for Play, Pause, Step, Finish, and Reset controls with chunk timing and `settledBlockCount` telemetry.
* **Virtualized Preview & Outline Jump**: Render documents with `MarkdownView` and `MarkdownView.streaming`, navigate headings via `controller.scrollToAnchor`, test custom builders, and audit `MarkdownUrlPolicy` link filtering.
* **AST, HTML & Plain-Text Inspector**: Inspect the expandable AST with `blockId` and `SourceSpan` ranges alongside `document.toHtml()` and `document.toPlainText()` outputs.

## Setup, Tests & Launch

Resolve workspace dependencies at the repository root, then run headless widget tests or launch the macOS desktop workbench:

```bash
flutter pub get
(cd studio && flutter test)
(cd studio && flutter run -d macos)
```

See the [Comparison Studio Guide](../doc/STUDIO_GUIDE.md) for workbench architecture and accompanying CLI verification tools.
