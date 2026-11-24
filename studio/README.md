# markdown_engine Studio

**Markdown Studio** (`studio/`) is a macOS Flutter inspection and streaming workbench (`markdown_engine Studio`) for **`markdown_engine`** and **`markdown_engine_flutter`**.

## Features

* **Preset Sample Selector**: Switch across six built-in presets covering CommonMark/GFM, math, and virtualization stress tests:
  * **CommonMark & GFM Showcase** (`showcase`)
  * **Comprehensive Markdown Guide** (`comprehensiveGuide`)
  * **Kitchen Sink (Visual Parity)** (`kitchenSink`)
  * **Alerts, Frontmatter & HTML** (`alertsAndHtml`)
  * **Security & Sanitization** (`security`)
  * **500-Section Virtualization Stress** (`stress500`)
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

See the [Markdown Studio Guide](../doc/STUDIO_GUIDE.md) for workbench architecture, CLI launch flags, and accompanying CLI verification tools.
