import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart'
    show TexMath, TexMathErrorWidget;
import 'package:vector_graphics/vector_graphics.dart' show VectorGraphic;

bool _goldenFontsLoaded = false;

Future<void> _ensureGoldenFontsLoaded(WidgetTester tester) async {
  if (_goldenFontsLoaded) {
    return;
  }
  await tester.runAsync(() async {
    final ByteData mathFontBytes = await rootBundle.load(
      'packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf',
    );
    final FontLoader mathFontLoader = FontLoader('NewCMMath')
      ..addFont(Future<ByteData>.value(mathFontBytes));
    await mathFontLoader.load();

    final Directory? materialFontsDir = _locateFlutterMaterialFontsDir();
    if (materialFontsDir != null) {
      Future<ByteData?> readFontBytes(String fileName) async {
        final File file = File('${materialFontsDir.path}/$fileName');
        if (!file.existsSync()) {
          return null;
        }
        final Uint8List bytes = await file.readAsBytes();
        return ByteData.sublistView(bytes);
      }

      final ByteData? regular = await readFontBytes('Roboto-Regular.ttf');
      final ByteData? bold = await readFontBytes('Roboto-Bold.ttf');
      final ByteData? italic = await readFontBytes('Roboto-Italic.ttf');
      final ByteData? boldItalic = await readFontBytes('Roboto-BoldItalic.ttf');

      Future<void> loadFamily(
        String family, {
        bool includeVariants = true,
      }) async {
        final FontLoader loader = FontLoader(family);
        if (regular != null) {
          loader.addFont(Future<ByteData>.value(regular));
        }
        if (includeVariants) {
          if (bold != null) {
            loader.addFont(Future<ByteData>.value(bold));
          }
          if (italic != null) {
            loader.addFont(Future<ByteData>.value(italic));
          }
          if (boldItalic != null) {
            loader.addFont(Future<ByteData>.value(boldItalic));
          }
        }
        await loader.load();
      }

      if (regular != null) {
        await loadFamily('Roboto');
        await loadFamily('Helvetica');
        await loadFamily('Menlo', includeVariants: false);
        await loadFamily('monospace', includeVariants: false);
      }
    }
  });
  _goldenFontsLoaded = true;
}

Directory? _locateFlutterMaterialFontsDir() {
  final String? envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null && envRoot.isNotEmpty) {
    final Directory candidate = Directory(
      '$envRoot/bin/cache/artifacts/material_fonts',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
  }

  Directory current = File(Platform.resolvedExecutable).parent;
  for (int i = 0; i < 10; i++) {
    final Directory candidate = Directory(
      '${current.path}/bin/cache/artifacts/material_fonts',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    final Directory directCandidate = Directory(
      '${current.path}/cache/artifacts/material_fonts',
    );
    if (directCandidate.existsSync()) {
      return directCandidate;
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
  return null;
}

Future<void> _expectGolden(
  Finder finder,
  String goldenPath, {
  double precisionTolerance = 0.02,
}) async {
  final GoldenFileComparator previous = goldenFileComparator;
  if (previous is! LocalFileComparator) {
    await expectLater(finder, matchesGoldenFile(goldenPath));
    return;
  }
  goldenFileComparator = _TolerantGoldenFileComparator(
    previous.basedir.resolve('golden_rendering_test.dart'),
    precisionTolerance: precisionTolerance,
  );
  try {
    await expectLater(finder, matchesGoldenFile(goldenPath));
  } finally {
    goldenFileComparator = previous;
  }
}

Future<void> _pumpGoldenDocument(
  WidgetTester tester, {
  required String markdown,
  required Size viewportSize,
  required bool isDark,
  MarkdownOptions options = const MarkdownOptions.extended(),
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await _ensureGoldenFontsLoaded(tester);
  await tester.runAsync(MarkdownBuiltInRenderers.warmUp);

  final Color canvasColor = isDark
      ? const Color(0xFF0B1120)
      : const Color(0xFFFFFFFF);
  final MarkdownThemeData mdTheme = isDark
      ? const MarkdownThemeData.dark(fontSize: 15.0, blockSpacing: 10.0)
      : const MarkdownThemeData.light(fontSize: 15.0, blockSpacing: 10.0);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        fontFamily: 'Roboto',
        fontFamilyFallback: const <String>['NewCMMath'],
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: canvasColor,
        body: RepaintBoundary(
          key: const Key('golden-root'),
          child: Container(
            width: viewportSize.width,
            height: viewportSize.height,
            color: canvasColor,
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: 'Roboto',
                fontFamilyFallback: const <String>['NewCMMath'],
                fontSize: mdTheme.fontSize,
                color: mdTheme.foreground,
              ),
              child: MarkdownTheme(
                data: mdTheme,
                child: MarkdownView(
                  markdown,
                  options: options,
                  selectable: false,
                  padding: const EdgeInsets.all(20.0),
                  delegates: const MarkdownBuilderDelegates(
                    imagePolicy: MarkdownImagePolicy.ask,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

const String _kitchenSinkGoldenMarkdown = r'''
---
title: Kitchen Sink Parity Suite
version: 0.1.0
tags: [commonmark, gfm, math, mermaid]
---

# Kitchen Sink H1 with Inline Math $E = mc^2$ {#top}

## Heading H2 · ### H3 · Styling

Prose with *emphasis*, **strong**, ~~strike~~, ==highlight==, H~2~O, 2^10^, <kbd>Cmd</kbd>+<kbd>K</kbd>, inline `code`, <u>underline</u>, <small>small</small>, <q>quoted</q>, and AST abbreviation.

Inline math $e^{i\pi}+1=0$ and \(\frac{a+b}{2}\) align cleanly on the baseline[^1].

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

```mermaid
flowchart LR
  Source["Markdown"] --> Parser["Pure-Dart AST"]
  Parser --> Math["TexMath"]
  Parser --> Diagram["VectorGraphic"]
```

| Module | Inline Math | Link | Role |
| :--- | :---: | :---: | ---: |
| `tex_math_flutter` | $\sum_{k=1}^n k$ | [Top](#top) | **OpenType** |
| `pele_dart` | $O(\|V\|+\|E\|)$ | [Docs](https://dart.dev) | *Vector* |

> Quoted checklist with nested lists:
> 1. Ordered parent item
>    - [x] Checked nested task item
>    - [ ] Unchecked nested task item

---

> [!NOTE]
> Informational callout block.

> [!TIP]
> Helpful keyboard hint: <kbd>Cmd</kbd>+<kbd>C</kbd>.

> [!WARNING]
> Check `SourceSpan` ranges before editing.

<details open>
<summary>Open `<details open>` block with math $\alpha + \beta$</summary>

Nested Markdown inside an expanded disclosure block.

</details>

<details>
<summary>Closed `<details>` disclosure block</summary>

Hidden body content.

</details>

<div align="center">

### Centered Alignment Block (`AlignedBlockNode`)

</div>

<figure>

```dart
final doc = const MarkdownEngine().parse(r'Hello $x^2$');
```

<figcaption>Figure 1: Code block inside <code>&lt;figure&gt;</code> container.</figcaption>
</figure>

`Definition Term`
: Structured definition list item rendered via `DefinitionListNode`.

Security links: [Allowed HTTPS](https://dart.dev) · [Blocked JS](javascript:alert(1))

![Remote Diagram Preview](https://example.com/diagram.png)

*[AST]: Abstract Syntax Tree

[^1]: Footnote definition linked from prose.
''';

const String _tablesAlertsDetailsGoldenMarkdown = r'''
# Tables, Alerts & Disclosure Blocks

This view verifies **GFM table column alignments**, **all five GitHub alerts**, nested lists inside blockquotes, and open/closed `<details>` containers.

## Aligned GFM Table

| Component | Alignment & Formula | Link Target | Status |
| :--- | :---: | :---: | ---: |
| **Parser Core** | $O(N)$ linear pass | [Spec](https://commonmark.org) | `100%` |
| **Math Layout** | $x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$ | [Top](#tables-alerts--disclosure-blocks) | **Active** |
| **URL Gate** | ~~`javascript:`~~ blocked | [Blocked](javascript:alert(1)) | Safe |

## All Five GitHub Alert Callouts

> [!NOTE]
> Contextual note callout with inline `code` and subtle accent border.

> [!TIP]
> Press <kbd>Cmd</kbd>+<kbd>K</kbd> to jump quickly between sections.

> [!IMPORTANT]
> Required architectural invariant: keep pure-Dart core free of `dart:ui`.

> [!WARNING]
> Remote images remain gated under `MarkdownImagePolicy.ask` until approved.

> [!CAUTION]
> Untrusted URI schemes like `vbscript:` or `data:` are non-interactive.

## Nested Blockquote Lists & Collapsible Details

> Review checklist inside a blockquote:
> 1. Verify header alignment and zebra striping
>    - [x] Left, center, and right aligned cells
>    - [ ] Optional theme override verification

<details open>
<summary>Expanded `<details open>` container</summary>

Supports **nested formatting**, ==highlighted spans==, and inline math $\alpha^2 + \beta^2 = \gamma^2$ seamlessly.

</details>

<details>
<summary>Collapsed `<details>` container</summary>

Hidden until expanded.

</details>
''';

const String _mathAndMermaidGoldenMarkdown = r'''
# OpenType Math & Mermaid Showcase

## Inline Baseline Alignment with $E = mc^2$ in Heading

Prose with inline dollar math $e^{i\pi} + 1 = 0$, parenthesis math \(x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}\), and summations $\sum_{k=1}^{n} k = \frac{n(n+1)}{2}$ aligned to the alphabetic baseline.

| Expression | Inline Formula | Meaning |
| :--- | :---: | ---: |
| Gaussian | $\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}$ | Normalizing constant |
| Taylor | $e^x = \sum_{n=0}^{\infty} \frac{x^n}{n!}$ | Exponential series |

## Display Equations (Integrals, Fractions & Matrices)

$$
\int_{0}^{\infty} \frac{x^3}{e^x - 1}\,dx = \frac{\pi^4}{15}, \qquad R(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix}
$$

## Vector Mermaid Diagrams (`pele_dart` + `vector_graphics`)

```mermaid
flowchart LR
  Input["TeX & Markdown"] --> AST["Immutable AST"]
  AST --> Math["NewCMMath Paths"]
  AST --> SVG["VectorGraphic"]
```

```mermaid
sequenceDiagram
  participant User
  participant Engine
  participant Canvas
  User->>Engine: Markdown + LaTeX
  Engine-->>Canvas: DisplayList + Vector
```

## Graceful Invalid LaTeX & Mermaid Fallbacks

Broken inline $\frac{1}{$ recovers cleanly alongside prose.

$$
\unknowncommandxyz{1}
$$

```mermaid
invalid_diagram_header
  A --> B
```
''';

void main() {
  setUp(() {
    MarkdownBuiltInRenderers.clearCaches();
    MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = false;
  });

  tearDown(() async {
    MarkdownBuiltInRenderers.clearCaches();
    await MarkdownBuiltInRenderers.dispose();
  });

  group('Golden pixel rendering suite', () {
    testWidgets('kitchen_sink_light', (WidgetTester tester) async {
      addTearDown(MarkdownBuiltInRenderers.clearCaches);
      addTearDown(MarkdownBuiltInRenderers.dispose);

      await _pumpGoldenDocument(
        tester,
        markdown: _kitchenSinkGoldenMarkdown,
        viewportSize: const Size(920.0, 1740.0),
        isDark: false,
      );

      expect(find.byType(TexMath), findsWidgets);
      expect(find.byType(VectorGraphic), findsOneWidget);
      await _expectGolden(
        find.byKey(const Key('golden-root')),
        'goldens/kitchen_sink_light.png',
      );
    });

    testWidgets('kitchen_sink_dark', (WidgetTester tester) async {
      addTearDown(MarkdownBuiltInRenderers.clearCaches);
      addTearDown(MarkdownBuiltInRenderers.dispose);

      await _pumpGoldenDocument(
        tester,
        markdown: _kitchenSinkGoldenMarkdown,
        viewportSize: const Size(920.0, 1740.0),
        isDark: true,
      );

      expect(find.byType(TexMath), findsWidgets);
      expect(find.byType(VectorGraphic), findsOneWidget);
      await _expectGolden(
        find.byKey(const Key('golden-root')),
        'goldens/kitchen_sink_dark.png',
      );
    });

    testWidgets('tables_alerts_details_light', (WidgetTester tester) async {
      addTearDown(MarkdownBuiltInRenderers.clearCaches);
      addTearDown(MarkdownBuiltInRenderers.dispose);

      await _pumpGoldenDocument(
        tester,
        markdown: _tablesAlertsDetailsGoldenMarkdown,
        viewportSize: const Size(860.0, 1180.0),
        isDark: false,
      );

      expect(find.byType(TexMath), findsWidgets);
      await _expectGolden(
        find.byKey(const Key('golden-root')),
        'goldens/tables_alerts_details_light.png',
      );
    });

    testWidgets('tables_alerts_details_dark', (WidgetTester tester) async {
      addTearDown(MarkdownBuiltInRenderers.clearCaches);
      addTearDown(MarkdownBuiltInRenderers.dispose);

      await _pumpGoldenDocument(
        tester,
        markdown: _tablesAlertsDetailsGoldenMarkdown,
        viewportSize: const Size(860.0, 1180.0),
        isDark: true,
      );

      expect(find.byType(TexMath), findsWidgets);
      await _expectGolden(
        find.byKey(const Key('golden-root')),
        'goldens/tables_alerts_details_dark.png',
      );
    });

    testWidgets('math_and_mermaid_showcase_light', (WidgetTester tester) async {
      addTearDown(MarkdownBuiltInRenderers.clearCaches);
      addTearDown(MarkdownBuiltInRenderers.dispose);

      await _pumpGoldenDocument(
        tester,
        markdown: _mathAndMermaidGoldenMarkdown,
        viewportSize: const Size(900.0, 1340.0),
        isDark: false,
      );

      expect(find.byType(TexMath), findsWidgets);
      expect(find.byType(TexMathErrorWidget), findsNWidgets(2));
      expect(find.byType(VectorGraphic), findsNWidgets(2));
      await _expectGolden(
        find.byKey(const Key('golden-root')),
        'goldens/math_and_mermaid_showcase_light.png',
      );
    });

    testWidgets('math_and_mermaid_showcase_dark', (WidgetTester tester) async {
      addTearDown(MarkdownBuiltInRenderers.clearCaches);
      addTearDown(MarkdownBuiltInRenderers.dispose);

      await _pumpGoldenDocument(
        tester,
        markdown: _mathAndMermaidGoldenMarkdown,
        viewportSize: const Size(900.0, 1340.0),
        isDark: true,
      );

      expect(find.byType(TexMath), findsWidgets);
      expect(find.byType(TexMathErrorWidget), findsNWidgets(2));
      expect(find.byType(VectorGraphic), findsNWidgets(2));
      await _expectGolden(
        find.byKey(const Key('golden-root')),
        'goldens/math_and_mermaid_showcase_dark.png',
      );
    });
  });
}

final class _TolerantGoldenFileComparator extends LocalFileComparator {
  _TolerantGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
  }) : assert(
         0 <= precisionTolerance && precisionTolerance <= 1,
         'precisionTolerance must be between 0 and 1',
       ),
       _precisionTolerance = precisionTolerance;

  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final bool passed =
        result.passed || result.diffPercent <= _precisionTolerance;
    if (passed) {
      result.dispose();
      return true;
    }
    final String error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
