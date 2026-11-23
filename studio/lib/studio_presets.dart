import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Built-in sample documents available in the Studio preset selector.
enum StudioPresetId {
  /// Comprehensive CommonMark, GFM, math, diagram, and link showcase.
  showcase,

  /// Full AST block & inline visual parity showcase exercising every node type.
  kitchenSink,

  /// GitHub alerts, YAML frontmatter, disclosure blocks, and HTML extensions.
  alertsAndHtml,

  /// URL scheme sanitization, HTML tag filtering, and remote image gating.
  security,

  /// 500-section synthetic document exercising sliver virtualization.
  stress500,
}

/// Immutable preset document configuration for the Studio workbench.
final class StudioPreset {
  /// Creates a [StudioPreset].
  const StudioPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.options,
    required this.sourceBuilder,
  });

  /// Stable identifier for this preset.
  final StudioPresetId id;

  /// Human-readable label shown in the toolbar preset selector.
  final String label;

  /// Short description summarizing what this preset demonstrates.
  final String description;

  /// Parser options active when this preset is selected.
  final MarkdownOptions options;

  /// Lazy source factory returning the Markdown content for this preset.
  final String Function() sourceBuilder;

  /// Lazily materialized Markdown source text for this preset.
  String get source => sourceBuilder();
}

const MarkdownOptions _showcaseOptions = MarkdownOptions.extended();

const MarkdownOptions _securityOptions = MarkdownOptions.extended(
  sanitizeHtml: true,
  sanitizeUrls: true,
  urlPolicy: MarkdownUrlPolicy(
    blockedSchemes: MarkdownUrlPolicy.defaultBlockedSchemes,
    allowRelative: true,
    allowFragments: true,
  ),
);

/// Ordered list of all built-in Studio presets.
final List<StudioPreset> studioPresets = <StudioPreset>[
  StudioPreset(
    id: StudioPresetId.showcase,
    label: 'CommonMark & GFM Showcase',
    description: 'Tables, task lists, footnotes, OpenType TeX math, and vector Mermaid diagrams.',
    options: _showcaseOptions,
    sourceBuilder: _showcaseSource,
  ),
  StudioPreset(
    id: StudioPresetId.kitchenSink,
    label: 'Kitchen Sink (Visual Parity)',
    description: 'Every AST block and inline node: H1-H6, math, Mermaid, tables, alerts, details, figures, CJK/RTL, and security.',
    options: _showcaseOptions,
    sourceBuilder: _kitchenSinkSource,
  ),
  StudioPreset(
    id: StudioPresetId.alertsAndHtml,
    label: 'Alerts, Frontmatter & HTML',
    description: 'YAML frontmatter, all five GitHub alerts, <details>, <figure>, <kbd>, and <abbr>.',
    options: _showcaseOptions,
    sourceBuilder: _alertsAndHtmlSource,
  ),
  StudioPreset(
    id: StudioPresetId.security,
    label: 'Security & Sanitization',
    description: 'MarkdownUrlPolicy scheme filtering, HTML sanitization, and remote image gating.',
    options: _securityOptions,
    sourceBuilder: _securitySource,
  ),
  StudioPreset(
    id: StudioPresetId.stress500,
    label: '500-Section Virtualization Stress',
    description:
        '1,500+ top-level blocks rendered lazily via SliverMarkdownDocument.',
    options: _showcaseOptions,
    sourceBuilder: _stress500Source,
  ),
];

/// Resolves a [StudioPreset] by its [StudioPresetId].
StudioPreset studioPresetById(StudioPresetId id) {
  for (final StudioPreset preset in studioPresets) {
    if (preset.id == id) {
      return preset;
    }
  }
  return studioPresets.first;
}

String _showcaseSource() => _showcaseMarkdown;

String _kitchenSinkSource() => _kitchenSinkMarkdown;

String _alertsAndHtmlSource() => _alertsAndHtmlMarkdown;

String _securitySource() => _securityMarkdown;

String? _cachedStress500;

String _stress500Source() {
  return _cachedStress500 ??= _buildStress500Document();
}

String _buildStress500Document() {
  final StringBuffer out = StringBuffer()
    ..writeln('# 500-Section Virtualization Stress')
    ..writeln()
    ..writeln(
      'This generated document contains **500 numbered sections** and over '
      '`1,500` top-level AST blocks rendered lazily by `SliverMarkdownDocument`. '
      'Toggle Light and Dark themes to confirm `controller.parseCount` remains '
      'unchanged, or jump directly to any heading from the Outline sidebar.',
    )
    ..writeln();

  for (int i = 1; i <= 500; i++) {
    out
      ..writeln('## Section $i {#section-$i}')
      ..writeln()
      ..writeln(
        'Paragraph $i exercises virtualized sliver layout with **bold**, '
        '_italic_, `block-$i`, and inline math \$x_{$i} = ${i * 2}\$. '
        'Jump back to [Section 1](#section-1) or visit '
        '[Dart Docs](https://dart.dev).',
      )
      ..writeln();
    if (i % 10 == 0) {
      out
        ..writeln('| Metric | Value | Status |')
        ..writeln('| :--- | :---: | ---: |')
        ..writeln('| Checkpoint | #$i | Verified |')
        ..writeln('| Sliver Reuse | Active | OK |')
        ..writeln();
    } else if (i % 5 == 0) {
      out
        ..writeln('> [!NOTE]')
        ..writeln(
          '> Virtualization checkpoint $i: off-screen blocks stay unmounted.',
        )
        ..writeln();
    }
  }
  return out.toString();
}

const String _showcaseMarkdown = r'''
# CommonMark & GFM Showcase

Welcome to **markdown_engine Studio** — a native Flutter macOS workbench powered by pure-Dart parsing, zero WebViews, and zero-reparse theme switching. Try toggling **Light / Dark** in the toolbar while watching the live `Parses` counter stay frozen.

Visit [the project documentation](https://tkinnis.github.io/markdown_engine/) or jump straight to [Built-in OpenType Math & Mermaid](#built-in-opentype-math--mermaid).

## GFM Tables & Task Lists

| Capability | Spec / Engine | Alignment | Status |
| :--- | :--- | :---: | ---: |
| Block & Inline Parser | CommonMark `0.31.2` | Center | 100% |
| GFM Extensions | `cmark-gfm 0.29` | Center | Active |
| OpenType Math | `tex_math_flutter` | Center | Built-in |
| Vector Diagrams | `pele_dart` + `vector_graphics` | Center | Built-in |
| Incremental Streaming | `StreamingMarkdownController` | Center | Frozen Prefix |

- [x] Immutable sealed `MarkdownBlockNode` & `MarkdownInlineNode` AST
- [x] Exact UTF-16 `SourceSpan` offsets and 1-based line ranges
- [x] Extended inline styles: ~~strikethrough~~, ==highlight==, H~2~O, 2^10^, and <kbd>Cmd</kbd>+<kbd>K</kbd>
- [ ] Switch to **Streaming Mode** in the top toolbar to replay token chunks[^stream-note]

## Built-in OpenType Math & Mermaid

Inline formulas align on the alphabetic baseline via `tex_math_flutter`: Euler's identity $e^{i\pi} + 1 = 0$ and the quadratic root \(x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}\) flow naturally inside prose.

Display equations render natively with OpenType `MATH` metrics:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

Fenced `mermaid` blocks render offline via `pele_dart` and `vector_graphics`, while other fences use Studio's syntax-highlighted `codeBlockBuilder`:

```mermaid
flowchart LR
  Source["Markdown Source"] --> Parser["Pure-Dart AST"]
  Parser --> Sliver["SliverMarkdownDocument"]
  Parser --> Inspector["HTML & Span Inspector"]
```

## Code & Definition Lists

```dart
final MarkdownEngine engine = MarkdownEngine(
  defaultOptions: const MarkdownOptions.extended(),
);
final MarkdownDocument doc = engine.parse('# Pure Dart');
```

`MarkdownController`
: Coordinates parsed `MarkdownDocument`, heading `outline`, `parseCount`, and anchor scrolling.

`MarkdownBuilderDelegates`
: Enables built-in math and Mermaid out of the box alongside custom `codeBlockBuilder` and URL/image policies.

[^stream-note]: Streaming mode freezes completed prefix blocks and reports per-chunk parse duration in microseconds.
''';

const String _kitchenSinkMarkdown = r'''
---
title: Kitchen Sink (Visual Parity)
spec: CommonMark 0.31.2 + GFM 0.29 + Extended AST
version: 0.1.0
tags: [parity, math, mermaid, alerts, security, i18n]
---

# Kitchen Sink Visual Parity {#kitchen-sink-top}

This comprehensive preset exercises **every** block and inline node in the `markdown_engine` AST alongside built-in OpenType `tex_math_flutter` math and `pele_dart` Mermaid rendering.

## Headings H2 with Inline Math $E = mc^2$ {#headings-demo}

### Heading Level 3 (`H3`)
#### Heading Level 4 (`H4`)
##### Heading Level 5 (`H5`)
###### Heading Level 6 (`H6` muted)

## Inline Formatting & Extended Spans

Prose mixes *italic emphasis*, **strong bold**, ~~strikethrough~~, ==highlighted spans==, chemical subscript H~2~O, exponent 2^10^, keyboard shortcut <kbd>Cmd</kbd>+<kbd>K</kbd>, inline code `final int count = 42;`, <u>underlined</u>, <small>small caption</small>, <q>quoted phrase</q>, and abbreviations such as AST and GFM.<a id="inline-anchor"></a>

Line continuation with two trailing spaces  
produces a `HardBreakNode`, while an explicit inline break<br>splits via `InlineBreakNode`, and a soft line wrap
folds cleanly into a single space[^ks-1].

## Built-in OpenType Math & Mermaid Diagrams

Both dollar-delimited `$...$` and parenthesis-delimited `\(...\)` inline math align on the alphabetic baseline: Euler's identity $e^{i\pi} + 1 = 0$, the quadratic formula \(x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}\), and linked math [$a^2 + b^2 = c^2$](https://dart.dev) flow seamlessly in prose.

Display equations support `$$...$$` and `\[...\]`:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}, \qquad \sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}
$$

\[
R(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix} \cdot \frac{1}{\sqrt{2}}
\]

```mermaid
flowchart LR
  Source["Markdown Text"] --> Parser["Pure-Dart AST"]
  Parser --> Math["tex_math_flutter"]
  Parser --> Mermaid["pele_dart Vector"]
  Parser --> HTML["Semantic HTML5"]
```

```mermaid
sequenceDiagram
  participant Author
  participant Engine as MarkdownEngine
  participant View as MarkdownView
  Author->>Engine: parse(kitchenSink)
  Engine-->>View: Immutable MarkdownDocument
  View->>Author: Sliver + OpenType + SVG
```

## Wide GFM Table with Aligned Columns

| Feature | Alignment & Inline Math | Source / Link | Verification |
| :--- | :---: | :---: | ---: |
| **OpenType Layout** | $\frac{\Delta y}{\Delta x} = \lim_{h \to 0} \frac{f(x+h)-f(x)}{h}$ | [`TexMath`](https://pub.dev/packages/tex_math_flutter) | `100%` |
| *Vector Mermaid* | $O(\|V\| + \|E\|)$ layout | [`pele_dart`](https://pub.dev/packages/pele_dart) | **Native** |
| ~~Legacy WebView~~ | Removed (`0` JS bridges) | [Top Anchor](#kitchen-sink-top) | Zero |

## Nested Lists Inside Blockquotes

> Quoted architecture checklist with nested ordered, unordered, and task lists:
>
> 1. Core parsing pipeline
>    - Deterministic UTF-16 `SourceSpan` tracking
>    - Zero global mutable state across parses
>      - [x] Sealed AST node classes
>      - [ ] Optional user custom builder overrides
> 2. Incremental tail reparsing for live streams

---

## All Five GitHub Alert Callouts

> [!NOTE]
> Useful context that readers should notice even when skimming a specification.

> [!TIP]
> Press <kbd>Cmd</kbd>+<kbd>C</kbd> after dragging across rendered prose or tables to copy clean text.

> [!IMPORTANT]
> Abbreviations such as AST and GFM expose semantic tooltips via `AbbrInlineNode`.

> [!WARNING]
> Always inspect `SourceSpan` offsets in the right-hand AST inspector when debugging edits.

> [!CAUTION]
> Untrusted links like `javascript:` are blocked cleanly at both HTML export and Flutter tap gates.

## Collapsible Details, Figures & Aligned Containers

<details open>
<summary>Open `<details open>` block with inline math $\alpha + \beta = \gamma$</summary>

Inside an expanded disclosure container, **rich Markdown**, ==highlights==, and [internal jumps](#headings-demo) render identically to top-level blocks.

</details>

<details>
<summary>Closed `<details>` block (click to expand)</summary>

Hidden until expanded by the user via pointer or keyboard <kbd>Enter</kbd> / <kbd>Space</kbd>.

</details>

<div align="center">

### Centered Alignment Container

Aligned `<div align="center">` content centers headings and paragraphs inside `AlignedBlockNode`.

</div>

<figure>

```mermaid
flowchart TD
  A["AST Node"] --> B["Sliver Block"]
```

<figcaption>Figure 1: Structured `<figure>` container with centered diagram and caption.</figcaption>

</figure>

Theme-aware picture: <picture><source media="(prefers-color-scheme: dark)" srcset="https://example.com/theme-dark.png"><img alt="Theme-aware PictureInlineNode preview" src="https://example.com/theme-light.png"></picture>

<div class="raw-html-sample">Raw HTML block container text for HtmlBlockNode parity.</div>

## Non-Mermaid Syntax-Highlighted Code & Definitions

```dart
Future<void> renderMarkdown(String source) async {
  // Pre-warm OpenType math font and Mermaid registry once at startup.
  await MarkdownBuiltInRenderers.warmUp();
  final MarkdownDocument doc = const MarkdownEngine(
    defaultOptions: MarkdownOptions.extended(),
  ).parse(source);
  assert(doc.blocks.isNotEmpty);
}
```

`MarkdownView`
: Virtualized sliver renderer supporting default, `.document`, and `.streaming` modes.

`MarkdownBuiltInRenderers`
: Pre-warms `NewCMMath-Regular.otf` and `pele_dart` caches with LRU reuse across theme switches.

## Internationalization (CJK & RTL)

- **Japanese / Chinese / Korean**: 日本語の数式表示とレイアウト検査 · 中文排版与数学公式渲染 · 한국어 마크다운 렌더링 테스트
- **Arabic / Hebrew (RTL)**: مرحبا بكم في محرك ماركداون مع دعم كامل للغة العربية والنصوص ثنائية الاتجاه — שלום עולם ובדיקת כיווניות מימין לשמאל.

## Security Links & Image Policy

- Allowed HTTPS link: [Dart Documentation](https://dart.dev)
- Allowed fragment anchor: [Jump to Top](#kitchen-sink-top)
- Blocked JS link (non-interactive): [Blocked JavaScript Link](javascript:alert(1))
- Blocked VBScript link (non-interactive): [Blocked VBScript Link](vbscript:msgbox(1))
- Blocked Data link (non-interactive): [Blocked Data Link](data:text/html,<script>alert(1)</script>)

![Remote Consent Image](https://example.com/architecture-preview.png)

![Blocked Scheme Image](javascript:alert(1))

*[AST]: Abstract Syntax Tree
*[GFM]: GitHub Flavored Markdown

[^ks-1]: Footnotes automatically wire jump links (`#fn-ks-1`) and return links (`#fnref-ks-1`) inside `MarkdownController`.
''';

const String _alertsAndHtmlMarkdown = r'''
---
title: Alerts, Frontmatter & HTML Extensions
author: markdown_engine Studio
version: 0.1.0
tags: [frontmatter, alerts, details, figure, kbd, abbr]
---

# Alerts, Frontmatter & HTML {#alerts-overview}

Leading YAML frontmatter above is extracted into `document.frontmatter` and rendered as a structured metadata card when `showFrontmatter` is enabled.

## GitHub Alert Callouts

> [!NOTE]
> Useful context that readers should notice even when skimming a specification.

> [!TIP]
> Press <kbd>Cmd</kbd>+<kbd>C</kbd> after dragging across rendered blocks to copy clean text from `SelectionArea`.

> [!IMPORTANT]
> Abbreviations such as AST and GFM automatically carry semantic tooltips via `AbbrInlineNode`.

> [!WARNING]
> Always inspect `SourceSpan` ranges in the right-hand AST panel to verify incremental line mapping.

> [!CAUTION]
> Untrusted raw HTML should be paired with `sanitizeHtml: true` and a strict `MarkdownUrlPolicy`.

## Interactive HTML Extensions

<details open>
<summary>Inspect collapsible <code>&lt;details&gt;</code> disclosure container</summary>

Inside `<details>`, full Markdown parsing remains active: **nested emphasis**, ==highlighted findings==, inline math $\alpha + \beta = \gamma$, and [internal anchor links](#alerts-overview).

</details>

<div align="center">

### Centered Alignment Block

Aligned containers preserve block-level structure inside `AlignedBlockNode` with exact `TableAlignment.center` metadata.

</div>

<figure>

```mermaid
flowchart LR
  YAML["Frontmatter"] --> Alerts["AlertNode (5 kinds)"]
  Alerts --> HTML["Details & Figure"]
```

<figcaption>Figure 1: Structured extension nodes exposed in the sealed AST.</figcaption>
</figure>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://example.com/diagram-dark.png">
  <img alt="Theme-aware PictureInlineNode preview" src="https://example.com/diagram-light.png">
</picture>

*[AST]: Abstract Syntax Tree
*[GFM]: GitHub Flavored Markdown
''';

const String _securityMarkdown = r'''
# Security & Sanitization {#policy-summary}

This preset runs with `sanitizeHtml: true`, `sanitizeUrls: true`, `MarkdownImagePolicy.ask`, and `MarkdownUrlPolicy` blocking `javascript:`, `vbscript:`, and `data:` URI schemes.

## Allowed vs. Blocked Links

Tap any allowed link below to see the `MarkdownUrlPolicy` status banner and snackbar:

- Allowed HTTPS link: [Dart Documentation](https://dart.dev)
- Allowed repository docs: [markdown_engine Docs](https://tkinnis.github.io/markdown_engine/)
- Allowed fragment anchor: [Jump to Policy Summary](#policy-summary)
- Blocked JavaScript URI (non-interactive): [Blocked JS Payload](javascript:alert(1))
- Blocked VBScript URI (non-interactive): [Blocked VBS Payload](vbscript:msgbox(1))
- Blocked Data HTML URI (non-interactive): [Blocked Data URI](data:text/html,<script>alert(1)</script>)
- Blocked obfuscated scheme (non-interactive): [Blocked Control-Char URI](java&#x09;script:alert(2))

## Raw HTML Sanitization & GFM Tag Filter

Raw HTML blocks below are stripped or escaped before HTML export and never execute in Flutter:

<script>alert('xss')</script>

<iframe src="https://untrusted.example/embed"></iframe>

<a href="javascript:alert(1)" onclick="stealCookies()">Sanitized raw anchor</a>

<div style="background: url(javascript:alert(1))" onmouseover="pwn()">Sanitized container text</div>

## Remote Image Privacy Gating

Remote network images never fire automatic HTTP requests under `MarkdownImagePolicy.ask`:

![Untrusted Remote Telemetry Pixel](https://example.com/telemetry-preview.png)

> [!IMPORTANT]
> Switch to the **HTML** tab in the right inspector to verify that `<script>`, `<iframe>`, `onclick`, and dangerous `href` schemes were neutralized cleanly.
''';

/// Realistic multi-block token chunks used by the LLM Streaming Simulator.
///
/// Intentionally avoids reference/footnote `]:` definitions so
/// [StreamingMarkdownController] progressively freezes settled prefix blocks
/// while only reparsing the trailing active slice.
const List<String> studioStreamingChunks = <String>[
  '# Streaming ',
  'Architecture ',
  'Walkthrough\n\n',
  'Incoming tokens arrive ',
  'incrementally from a simulated ',
  'model response. ',
  'Once a blank-line boundary ',
  'closes a block, ',
  '`StreamingMarkdownController` ',
  'freezes it cleanly.\n\n',
  '> [!TIP]\n',
  '> Watch **Settled Blocks** climb ',
  'while per-chunk parse time ',
  'stays in the microsecond range.\n\n',
  '## Live Metrics Summary\n\n',
  '| Stage | Strategy | Allocation |\n',
  '| :--- | :--- | ---: |\n',
  '| Settled Prefix | Frozen AST nodes | Zero |\n',
  '| Active Tail | Incremental reparse | Minimal |\n\n',
  'Inline math streams smoothly: ',
  r'complexity scales with tail size $O(|T|)$ ',
  'rather than full document length.\n\n',
  '\$\$\n',
  r'\Delta t_{\text{chunk}} \propto |\text{tail}|',
  '\n\$\$\n\n',
  '```mermaid\n',
  'flowchart LR\n',
  '  Token["Token Chunk"] --> Tail["Active Tail Slice"]\n',
  '  Tail --> Freeze["Freeze Settled Prefix"]\n',
  '```\n\n',
  '```dart\n',
  'final StreamingMarkdownController stream = StreamingMarkdownController(\n',
  '  options: const MarkdownOptions.extended(),\n',
  ');\n',
  'stream.append(chunk);\n',
  '```\n\n',
  'Stream complete — all trailing blocks are now finalized and settled.\n',
];
