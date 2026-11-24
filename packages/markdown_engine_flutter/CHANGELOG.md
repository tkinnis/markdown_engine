## 0.1.0

Initial public release of `markdown_engine_flutter`, delivering virtualized Flutter Markdown widgets, built-in OpenType TeX math and vector Mermaid rendering, native HTML block and inline conversion, theming, and selection support built atop `markdown_engine`.

### Views, Virtualization & Streaming

- **Core View Constructors (`MarkdownView`)**: Added default `MarkdownView(data)` (with automatic `IncrementalMarkdownParser` reuse on edits), `MarkdownView.document` for pre-parsed ASTs, and `MarkdownView.streaming` for push-driven token feeds.
- **Virtualized Sliver Layout (`SliverMarkdownDocument`)**: Implemented lazy block materialization keyed by `blockId`, `addAutomaticKeepAlives` selection preservation, `Float64List` extent estimation, and single-frame batched scroll-offset corrections.
- **Hybrid Streaming Pipeline**: Combined frozen settled-prefix slivers (`settledPrefixBlockCount`) with an isolated trailing streaming canvas and widget tail fallback for rich blocks, zero polling timers, and seamless post-`finish()` reuse.
- **Background Document Reader (`MarkdownDocumentReader`)**: Added a `ValueListenable<MarkdownDocument>` loader that parses short strings synchronously and offloads larger documents (`>= 4096` UTF-16 code units) to `Isolate.run` with latest-wins coalescing.

### Built-In Math, Mermaid & Native HTML Rendering

- **OpenType TeX Math (`tex_math_flutter`)**: Enabled native inline (`$...$`, `\(...\)`) and display (`$$...$$`, `\[...\]`) LaTeX math out of the box with `NewCMMath-Regular.otf`, alphabetic baseline alignment, spoken accessibility labels, and dual entry+byte LRU caching (`1,024` entries / `8 MiB`).
- **Vector Mermaid Diagrams (`pele_dart` + `vector_graphics`)**: Enabled offline Mermaid diagram compilation with theme-reactive `PelePalette` colors, calm unclosed streaming preview cards, error fallback cards, and dual entry+byte LRU caching (`128` entries / `16 MiB`).
- **Bounded Lazy Burst Mermaid Worker Pool**: Added `MarkdownBuiltInRenderers` lifecycle and cache controls (`warmUp()`, `configureCaches()`, `resetCacheDefaults()`, `clearCaches()`, `dispose()`), persistent primary isolate reuse (`usePersistentMermaidIsolate`), bounded auxiliary burst workers (`maxMermaidConcurrentWorkers`, `15`s idle teardown), and web `compute()` fallback.
- **Native HTML Block & Table Rendering**: Converted raw HTML fragments into native Flutter widgets for `<table>` (with `<caption>`, `<thead>`, `<tbody>`, `<tfoot>`, `colspan`, and cell alignment), `<dl>` (`<dt>`/`<dd>`), `<details>`/`<summary>`, `<figure>`/`<figcaption>`, centered hero/alignment containers (`<center>`, `<div align="center">`), headings, lists, blockquotes, `<pre>`, `<hr>`, semantic section containers, and block-wrapping `<a id>`/`<a name>` anchors.
- **Inline HTML Formatting**: Added native rendering across Markdown paragraphs and HTML blocks for `<mark>`, `<sub>`, `<sup>`, `<kbd>`, `<abbr title="...">` tooltips, `<u>`/`<ins>`, `<small>`, `<q>`, `<code>`/`<samp>`/`<var>`, `<br>`, sized `<img>`, and theme-aware `<picture>` elements.

### Theming, Selection, Navigation & Security

- **Theming (`MarkdownTheme` & `MarkdownThemeData`)**: Added Material `ColorScheme` / `ThemeData` derivation (`.fromColorScheme()`, `.fromTheme()`), `.light()` and `.dark()` presets, `MarkdownAlertPalette` / `MarkdownAlertColors`, `.lerp()` transitions, and zero-reparse Light/Dark switching.
- **Release-Safe Selection (`SelectionArea` & `MarkdownRichText`)**: Integrated `SelectionArea` (`MaterialApp`) and `SelectableRegion` (`WidgetsApp`), `MarkdownRichText` / `MarkdownRichText.rich` layout readiness guards across debug/profile/release builds, excluded UI chrome, and full-document `Cmd+A` / Copy across off-screen slivers.
- **Outline Navigation & Reading Tracking (`MarkdownController`)**: Added owner-scoped `ScrollController` attachment, `readingPlaceNotifier`, `scrollToAnchor()`, `scrollToLine()`, `jumpToPlace()`, and `parseCount` telemetry.
- **Delegates, Policies & Accessibility (`MarkdownBuilderDelegates`)**: Added `MarkdownImagePolicy` (`block`, `ask`, `load`), `MarkdownUrlPolicy` link/image gating, custom override hooks (`mathInlineBuilder`, `mathBlockBuilder`, `diagramBuilder`, `codeBlockBuilder`, `imageBuilder`), screen-reader `Semantics`, and keyboard `FocusableActionDetector` controls.
