## 0.2.0

Added interactive Mermaid diagram tap hooks, flattened SVG payload propagation, and hover overlay controls.

### Interactive Mermaid Diagrams

- **Tap-to-Zoom Hook (`onTapMermaid`)**: Added `MarkdownMermaidTapCallback` and `MarkdownMermaidDiagram` (`code`, `compiledBytes`, `svg`, `logicalSize`, `semanticsLabel`, `brightness`) to `MarkdownBuilderDelegates` and `BuiltInMermaidDiagram`.
- **Hover Overlay Controls**: Added a widgets-only top-right floating pill toolbar (`Zoom` and `Copy` / `Copied`) and `zoomIn` cursor on interactive Mermaid diagram cards while keeping non-interactive diagrams identical.
- **Worker & Cache SVG Propagation**: Propagated flattened SVG 1.1 markup across Mermaid worker isolates into `BuiltInMermaidSuccess` and `BuiltInMermaidCache` byte-budget accounting.

## 0.1.0

Initial public release of `markdown_engine_flutter`, delivering virtualized Flutter Markdown widgets, built-in OpenType TeX math and vector Mermaid rendering, native HTML block and inline conversion, theming, and selection support built atop `markdown_engine`.

### Views, Virtualization & Streaming

- **Core View Constructors (`MarkdownView`)**: Added default `MarkdownView(data)` (with automatic `IncrementalMarkdownParser` reuse on edits), `MarkdownView.document` for pre-parsed ASTs, and `MarkdownView.streaming` for push-driven token feeds.
- **Virtualized Sliver Layout (`SliverMarkdownDocument`)**: Implemented lazy block materialization keyed by `blockId`, `addAutomaticKeepAlives` selection preservation, `Float64List` extent estimation, and single-frame batched scroll-offset corrections.
- **Hybrid Streaming Pipeline**: Combined frozen settled-prefix slivers (`settledPrefixBlockCount`) with an isolated trailing streaming canvas and widget tail fallback for rich blocks, zero polling timers, and seamless post-`finish()` reuse.
- **Background Document Reader (`MarkdownDocumentReader`)**: Added a `ValueListenable<MarkdownDocument>` loader that parses short strings synchronously and offloads larger documents (4096 or more UTF-16 code units) to `Isolate.run` with latest-wins coalescing.

### Built-In Math, Mermaid & Native HTML Rendering

- **OpenType TeX Math (`tex_math_flutter`)**: Enabled native inline and display LaTeX math out of the box with `NewCMMath-Regular.otf`, alphabetic baseline alignment, spoken accessibility labels, and dual entry+byte LRU caching (1,024 entries / 8 MiB).
- **Vector Mermaid Diagrams (`pele_dart` + `vector_graphics`)**: Enabled offline Mermaid diagram compilation with theme-reactive `PelePalette` colors, calm unclosed streaming preview cards, error fallback cards, and dual entry+byte LRU caching (128 entries / 16 MiB).
- **Bounded Lazy Burst Mermaid Worker Pool**: Added `MarkdownBuiltInRenderers` lifecycle and cache controls (`warmUp()`, `configureCaches()`), persistent primary isolate reuse (`usePersistentMermaidIsolate`), bounded auxiliary burst workers (`maxMermaidConcurrentWorkers` with 15s idle teardown), and web `compute()` fallback.
- **Native HTML Block & Table Rendering**: Converted raw HTML fragments into native Flutter widgets for tables (`<table>` with captions, headers, footers, `colspan`, and alignment), description lists (`<dl>`), collapsible disclosures (`<details>`), figures (`<figure>`), aligned containers, headings, lists, blockquotes, and anchor targets.
- **Inline HTML Formatting**: Added native rendering across Markdown paragraphs and HTML blocks for highlights (`<mark>`), keycaps (`<kbd>`), abbreviation tooltips (`<abbr>`), theme-aware `<picture>` elements, subscripts/superscripts, underlines, quotes, inline code, breaks, and sized images.

### Theming, Selection, Navigation & Security

- **Theming (`MarkdownTheme` & `MarkdownThemeData`)**: Added `MarkdownTheme` and `MarkdownThemeData` with Material `ColorScheme` derivation, light/dark presets, `MarkdownAlertPalette` alert colors, smooth interpolation, and zero-reparse Light/Dark switching.
- **Release-Safe Selection (`SelectionArea` & `MarkdownRichText`)**: Integrated `SelectionArea` and `SelectableRegion` with `MarkdownRichText` layout readiness guards across debug, profile, and release builds, excluded UI chrome, and full-document Cmd+A / Copy across off-screen slivers.
- **Outline Navigation & Reading Tracking (`MarkdownController`)**: Added owner-scoped scroll controller attachment, `readingPlaceNotifier`, `scrollToAnchor()`, `scrollToLine()`, and `parseCount` telemetry.
- **Delegates, Policies & Accessibility (`MarkdownBuilderDelegates`)**: Added `MarkdownImagePolicy` remote image consent gating, `MarkdownUrlPolicy` link validation, custom builder overrides (`diagramBuilder`, math, code, and image builders), screen-reader `Semantics`, and keyboard focus controls.
