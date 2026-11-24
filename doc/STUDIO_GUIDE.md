# Markdown Studio Guide

**`markdown_engine Studio`** (`studio/`) is a macOS Flutter inspection and streaming workbench for **`markdown_engine`** and **`markdown_engine_flutter`**. Test built-in presets, Light/Dark theme switching, live LLM chunk streaming, outline jumps, link auditing, and AST/HTML/plain-text inspection in one desktop app.

---

## 1. Workbench Architecture & Layout

`MarkdownStudioApp` (`studio/lib/main.dart`) coordinates a multi-pane workspace across six modules alongside a macOS `--profile` benchmark entry point:

```mermaid
flowchart LR
  Toolbar["Top Toolbar (Presets / Light-Dark Theme + Parses Counter / Streaming / Outline / Inspector)"] --> App["MarkdownStudioApp (main.dart)"]
  App --> Left["Left Pane: Live Markdown Editor OR StudioStreamingPane (Play / Pause / Step / Finish / Reset)"]
  App --> Outline["StudioOutlinePanel (controller.outline -> scrollToAnchor)"]
  App --> Preview["Center Pane: MarkdownView / MarkdownView.streaming + StudioBuilders + Link Audit"]
  App --> Inspector["Right Pane: StudioInspectorPane (AST & SourceSpans / HTML / Plain Text)"]
```

| Module | Role |
| :--- | :--- |
| `studio/lib/main.dart` | Root `MarkdownStudioApp` coordinating presets, `MarkdownBuiltInRenderers.warmUp()`, Light/Dark themes, `MarkdownController` telemetry, streaming playback, CLI launch flags, and link banners. |
| `studio/lib/studio_presets.dart` | Defines `StudioPresetId` and the six `studioPresets` entries. |
| `studio/lib/studio_streaming_pane.dart` | Implements `StudioStreamingPane` with Play, Pause, Step, Finish, and Reset controls, chunk speed slider (`20..400 ms`), `settledBlockCount`, and parse microsecond telemetry. |
| `studio/lib/studio_outline_panel.dart` | Implements `StudioOutlinePanel`, following `MarkdownController.readingPlaceNotifier` without scroll-frame rebuilds and jumping to headings via `controller.scrollToAnchor`. |
| `studio/lib/studio_builders.dart` | Supplies `buildStudioDelegates` (built-in math and Mermaid rendering plus syntax-highlighted code blocks) and memoized `auditDocumentLinks` metrics. |
| `studio/lib/studio_inspector.dart` | Implements `StudioInspectorPane` with tabs for an expandable AST and `SourceSpan` tree, memoized `toHtml()`, and memoized `toPlainText()` with copy actions. |
| `studio/lib/profile_benchmark_main.dart` | Headless macOS `--profile` `FrameTiming` benchmark measuring 500-section scrolling and 60Hz streaming via `tool/run_macos_profile_benchmark.dart`. |

### CLI Launch Flags

`MarkdownStudioApp.fromArgs` accepts optional command-line launch flags when running `studio`:

* `--preset=<id>`: Select an initial preset (`showcase`, `comprehensiveGuide`, `kitchenSink`, `alertsAndHtml`, `security`, or `stress500`, matched case-insensitively).
* `--dark`: Start the workbench in dark mode.
* `--streaming`: Start in LLM Streaming Simulator mode.
* `--stream-finish`: Apply all streaming chunks immediately on startup.
* `--stream-steps=<n>`: Apply `n` initial streaming chunks on startup.
* `--scroll=<px>`: Set an initial vertical scroll offset in logical pixels.
* `--anchor=<slug>`: Scroll to a matching heading or anchor slug on startup.

---

## 2. Key Interactive Workflows

* **Preset Sample Selector**: Switch between six built-in sample documents targeting parser features, security rules, and sliver virtualization:

| Preset Label | `--preset` ID | Scope |
| :--- | :--- | :--- |
| **CommonMark & GFM Showcase** | `showcase` | Tables, task lists, footnotes, OpenType TeX math, and vector Mermaid diagrams. |
| **Comprehensive Markdown Guide** | `comprehensiveGuide` | Full Markdown syntax guide, all 33 Mermaid diagram families, and LaTeX math gallery. |
| **Kitchen Sink (Visual Parity)** | `kitchenSink` | Every AST block and inline node alongside CJK/RTL text and security checks. |
| **Alerts, Frontmatter & HTML** | `alertsAndHtml` | YAML frontmatter, all five GitHub alerts, `<details>`, `<figure>`, `<kbd>`, and `<abbr>`. |
| **Security & Sanitization** | `security` | `MarkdownUrlPolicy` scheme filtering, HTML sanitization, and remote image gating. |
| **500-Section Virtualization Stress** | `stress500` | 1,500+ top-level blocks rendered lazily via `SliverMarkdownDocument`. |

* **Zero-Reparse Theme Toggle**: Flip Light and Dark modes while watching the `Parses: <controller.parseCount>` chip stay constant to confirm zero redundant AST reparses.
* **LLM Streaming Simulator**: Toggle **Streaming Mode** to step or play chunks (`20..400 ms/chunk`) through `MarkdownView.streaming`, observing `settledBlockCount` grow while per-chunk latency stays low.
* **Math, Mermaid, Images & Link Audit**: Preview native OpenType math and Mermaid diagrams alongside `MarkdownImagePolicy.ask` consent controls, live allowed/blocked link counts, and link-tap snackbars.
* **AST, HTML & Plain-Text Inspector**: Inspect the expandable AST with exact `blockId` and `SourceSpan` line/offset ranges, raw `document.toHtml()` output, and `document.toPlainText()` previews.

---

## 3. Prerequisites, Headless Tests & Launch

`studio/` is an internal `publish_to: none` workspace application targeting Flutter `>=3.47.0` and Dart `^3.13.0`, with workspace `any` constraints verified by `tool/check_versions.dart`.

Resolve workspace dependencies from the repository root, run `studio/test/widget_test.dart`, or launch the macOS desktop workbench:

```bash
flutter pub get
(cd studio && flutter test)
(cd studio && flutter run -d macos)
```

---

## 4. Accompanying CLI Verification Tools

Use the CLI scripts under `tool/` to check CommonMark/GFM parity, `REFERENCE.md` hashes, lockstep versions, and native AOT performance:

```bash
# Verify CommonMark 0.31.2 and GFM 0.29.0.gfm.13 parity (add --verbose to inspect diffs)
dart run tool/verify_spec.dart --strict

# Verify vendored corpus/spec/ SHA-256 hashes against REFERENCE.md
dart run tool/sync_reference.dart --verify

# Verify lockstep package versions across pubspecs and changelogs
dart run tool/check_versions.dart

# Run native AOT benchmarks (add --json for machine-readable output)
dart run tool/benchmark_suite.dart --check-regressions

# Run real macOS --profile Impeller frame-time benchmark (500-section scroll + 60Hz streaming)
dart run tool/run_macos_profile_benchmark.dart
```
