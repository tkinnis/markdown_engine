import 'dart:async';
import 'dart:isolate' show IsolateSpawnException;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:markdown_engine_flutter/src/built_in_mermaid.dart';
import 'package:markdown_engine_flutter/src/built_in_mermaid_worker.dart';
import 'package:pele_dart/pele_dart.dart' show PelePalette;
import 'package:tex_math_flutter/tex_math_flutter.dart'
    show
        TexMath,
        TexMathErrorWidget,
        TexMathFontBundle,
        TexMathOverflow,
        TexMathTheme,
        TexMathThemeData;
import 'package:vector_graphics/vector_graphics.dart' show VectorGraphic;

void main() {
  setUp(() {
    MarkdownBuiltInRenderers.resetCacheDefaults();
    MarkdownBuiltInRenderers.clearCaches();
    MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = false;
  });

  tearDownAll(() async {
    await MarkdownBuiltInRenderers.dispose();
  });

  group('Cold Frame-1 Table dry baseline & scrollToAnchor (#307)', () {
    testWidgets(
      'table cells with cold inline math and all inline WidgetSpan variants compute dry baseline without throwing',
      (WidgetTester tester) async {
        // Keep this before warmUp() runs so cachedMathFont starts cold.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 640.0,
                height: 600.0,
                child: MarkdownView('''
| Feature | Inline Spans | Notes |
| :--- | :--- | :--- |
| ColdMath | Formula \$\\frac{\\Delta y}{\\Delta x} + x_i\$ tail | Text |
| LinkedMath | Link [\$a^2 + b^2 = c^2\$](https://dart.dev) | Link |
| Anchor | Before <a id="cell-anchor"></a> after | [ref](#cell-anchor) |
| Key | Press [<kbd>Cmd</kbd>](https://dart.dev)+<kbd>K</kbd> | Shortcut |
| Abbr | Using AST in prose | Tooltip |
| SubSup | H~2~O and 2^10^ | Script |
| Footnote | Claim[^t1] here | Ref |
| InvalidMath | \$\\unknowncmd{1}\$ text | Error |

*[AST]: Abstract Syntax Tree

[^t1]: Note body.
'''),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Table), findsOneWidget);
        expect(find.byType(TexMath), findsNWidgets(3));
        expect(find.byType(TexMathErrorWidget), findsOneWidget);
      },
    );

    testWidgets(
      'frame-1 scrollToAnchor converges without SelectionContainer hasSize errors across cold math tables and async Mermaid blocks',
      (WidgetTester tester) async {
        MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = true;
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);
        final ScrollController scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        final StringBuffer doc = StringBuffer('# Top {#top}\n\n');
        for (int i = 0; i < 6; i++) {
          doc.writeln('Paragraph $i with inline math \$x_$i + y_$i\$.\n');
        }
        doc.writeln(r'''
```mermaid
flowchart LR
  A["Start"] --> B["Middle"]
  B --> C["End"]
```

```mermaid
sequenceDiagram
  Author->>Engine: parse
  Engine-->>View: render
```

| Feature | Inline Math | Status |
| :--- | :---: | ---: |
| OpenType | $\frac{\Delta y}{\Delta x} = \lim_{h \to 0} \frac{f(x+h)-f(x)}{h}$ and $O(\|V\|)$ | Ready |
| Native | [$\sqrt{a^2+b^2}$](https://dart.dev) | Verified |

''');
        for (int i = 6; i < 24; i++) {
          doc.writeln(
            'Section block $i filler prose for virtualized scrolling.\n',
          );
        }
        doc.writeln('''
## Internationalization (CJK & RTL)

- Japanese / Chinese / Korean: 日本語 · 中文 · 한국어
- Arabic / Hebrew: مرحبا بالعالم — שלום עולם

## Trailing Section

End of document.
''');

        bool? scrollSucceeded;
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 800.0,
                  height: 600.0,
                  child: _FrameOneAnchorHost(
                    source: doc.toString(),
                    anchor: 'internationalization-cjk--rtl',
                    controller: controller,
                    scrollController: scrollController,
                    onResult: (bool ok) => scrollSucceeded = ok,
                  ),
                ),
              ),
            ),
          );
          for (int i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });

        expect(tester.takeException(), isNull);
        expect(scrollSucceeded, isTrue);
        expect(scrollController.offset, greaterThan(0.0));
        expect(find.text('Internationalization (CJK & RTL)'), findsOneWidget);
      },
    );
  });

  group('Built-in tex_math_flutter rendering', () {
    testWidgets(
      'renders inline and display math out of the box with default options and zero custom builders',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                r'Inline $x^2$ and \(a + b\) formula.'
                '\n\n'
                r'$$\frac{1}{2}$$'
                '\n\n'
                r'\[\sum_{i=1}^n i\]',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TexMath), findsNWidgets(4));
        expect(find.byType(TexMathErrorWidget), findsNothing);

        // Inline spans use alphabetic baseline alignment.
        final Finder richFinder = find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              w.textSpan != null &&
              w.textSpan!.toPlainText().contains('Inline'),
        );
        expect(richFinder, findsOneWidget);
        final Text inlineParagraph = tester.widget<Text>(richFinder);
        int baselineMathSpans = 0;
        inlineParagraph.textSpan?.visitChildren((InlineSpan span) {
          if (span is WidgetSpan &&
              span.alignment == PlaceholderAlignment.baseline &&
              span.baseline == TextBaseline.alphabetic) {
            baselineMathSpans++;
          }
          return true;
        });
        expect(baselineMathSpans, 2);

        // Display math configures horizontal scroll overflow.
        final List<TexMath> mathWidgets = tester
            .widgetList<TexMath>(find.byType(TexMath))
            .toList(growable: false);
        expect(
          mathWidgets.where(
            (TexMath w) => w.effectiveOverflow == TexMathOverflow.scroll,
          ),
          hasLength(2),
        );
      },
    );

    testWidgets(
      'renders cold math asynchronously before font warm-up without crashing',
      (WidgetTester tester) async {
        TexMathFontBundle.clearCache();
        expect(TexMathFontBundle.cachedMathFont, isNull);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                r'Cold $x^2$'
                '\n\n'
                r'$$y = mx + b$$',
                options: MarkdownOptions(math: true),
              ),
            ),
          ),
        );

        expect(find.byType(TexMath), findsNWidgets(2));
        expect(find.byType(TexMathErrorWidget), findsNothing);

        await tester.runAsync(() async {
          await TexMathFontBundle.loadMathFont();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();

        expect(find.byType(TexMath), findsNWidgets(2));
      },
    );

    testWidgets(
      'tapping inline TexMath inside a Markdown link invokes onTapLink even with selectable: true',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        final List<String> tapped = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                r'Click [$x^2$](https://example.com/formula) here.',
                options: const MarkdownOptions(math: true),
                selectable: true,
                delegates: MarkdownBuilderDelegates(
                  onTapLink: (String dest, String? _) => tapped.add(dest),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TexMath), findsOneWidget);
        await tester.tap(find.byType(TexMath));
        await tester.pump();

        expect(tapped, <String>['https://example.com/formula']);
      },
    );

    testWidgets(
      'renders TexMathErrorWidget safely for invalid inline and display LaTeX',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                r'Broken $\frac{1}{$'
                '\n\n'
                r'$$\unknowncommandxyz{1}$$',
                options: MarkdownOptions(math: true),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TexMathErrorWidget), findsNWidgets(2));
      },
    );
  });

  group('Built-in pele_dart Mermaid rendering', () {
    testWidgets(
      'renders Mermaid diagram out of the box with VectorGraphic, RepaintBoundary, and Semantics',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: MarkdownView(
                  '```mermaid\nflowchart LR\n  A[Start] --> B[End]\n```',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final Finder vgFinder = find.byType(VectorGraphic);
          expect(vgFinder, findsOneWidget);
          expect(
            find.ancestor(of: vgFinder, matching: find.byType(RepaintBoundary)),
            findsWidgets,
          );
          expect(
            find.bySemanticsLabel(RegExp('flowchart', caseSensitive: false)),
            findsOneWidget,
          );
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'constrains ultra-wide Mermaid diagrams cleanly with horizontal scroll',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 240.0,
                height: 400.0,
                child: MarkdownView(
                  '```mermaid\nflowchart LR\n'
                  '  A[Alpha] --> B[Bravo] --> C[Charlie] --> D[Delta] --> E[Echo] --> F[Foxtrot]\n```',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(VectorGraphic), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          find.ancestor(
            of: find.byType(VectorGraphic),
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'renders background compute isolate Mermaid path cleanly under runAsync and disposes without leaks',
      (WidgetTester tester) async {
        MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = true;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '```mermaid\nflowchart LR\n  AsyncA --> AsyncB\n```',
              ),
            ),
          ),
        );
        expect(find.text('Mermaid diagram preview'), findsOneWidget);
        expect(find.byType(VectorGraphic), findsNothing);

        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        await tester.pumpAndSettle();

        expect(find.byType(VectorGraphic), findsOneWidget);
        await MarkdownBuiltInRenderers.dispose();
      },
    );

    testWidgets(
      'renders clean styled fallback card for complete invalid Mermaid without throwing',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '```mermaid\nnot_a_valid_diagram_header\n  A --> B\n```',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(VectorGraphic), findsNothing);
        expect(find.text('mermaid'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'shows calm neutral preview card while streaming an incomplete Mermaid fence, then upgrades to VectorGraphic when closed',
      (WidgetTester tester) async {
        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions(),
        );
        addTearDown(stream.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MarkdownView.streaming(controller: stream)),
          ),
        );

        stream.append('Intro paragraph.\n\n```mermaid\nflowchart LR\n  A --> ');
        await tester.pump();

        expect(find.text('Mermaid diagram preview'), findsOneWidget);
        expect(find.byType(VectorGraphic), findsNothing);
        expect(find.textContaining('Parse error'), findsNothing);

        stream.append('B\n```\n');
        await tester.pumpAndSettle();

        expect(find.byType(VectorGraphic), findsOneWidget);
        expect(find.text('Mermaid diagram preview'), findsNothing);

        stream.finish();
        await tester.pumpAndSettle();
        expect(find.byType(VectorGraphic), findsOneWidget);

        // Truncated invalid unclosed fence stays calm while streaming, then
        // falls back cleanly on finish().
        stream.reset();
        await tester.pump();
        stream.append('```mermaid\ninvalid_diagram_type\n  X --> ');
        await tester.pump();
        expect(find.text('Mermaid diagram preview'), findsOneWidget);
        expect(find.text('Copy'), findsNothing);

        stream.finish();
        await tester.pumpAndSettle();
        expect(find.byType(VectorGraphic), findsNothing);
        expect(find.text('mermaid'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
      },
    );

    testWidgets(
      'onTapMermaid fires with populated MarkdownMermaidDiagram across light/dark themes and delegates equality',
      (WidgetTester tester) async {
        final List<MarkdownMermaidDiagram> tapped = <MarkdownMermaidDiagram>[];
        void handleTap(BuildContext context, MarkdownMermaidDiagram diagram) {
          tapped.add(diagram);
        }

        final MarkdownBuilderDelegates baseDelegates =
            const MarkdownBuilderDelegates();
        final MarkdownBuilderDelegates withTap = baseDelegates.copyWith(
          onTapMermaid: handleTap,
        );
        expect(withTap.onTapMermaid, same(handleTap));
        expect(withTap, isNot(equals(baseDelegates)));
        expect(
          withTap,
          equals(MarkdownBuilderDelegates(onTapMermaid: handleTap)),
        );
        expect(
          withTap.hashCode,
          equals(MarkdownBuilderDelegates(onTapMermaid: handleTap).hashCode),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownTheme(
                data: const MarkdownThemeData.light(),
                child: MarkdownView(
                  '```mermaid\nflowchart LR\n  A[Start] --> B[End]\n\n```\n',
                  selectable: true,
                  delegates: withTap,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(VectorGraphic), findsOneWidget);
        await tester.tap(find.byType(VectorGraphic));
        await tester.pump();

        expect(tapped, hasLength(1));
        final MarkdownMermaidDiagram lightDiagram = tapped.single;
        expect(lightDiagram.code, 'flowchart LR\n  A[Start] --> B[End]');
        expect(lightDiagram.compiledBytes, isNotEmpty);
        expect(lightDiagram.svg, contains('<svg'));
        expect(lightDiagram.logicalSize.width, greaterThan(0.0));
        expect(lightDiagram.logicalSize.height, greaterThan(0.0));
        expect(lightDiagram.semanticsLabel, isNotEmpty);
        expect(lightDiagram.brightness, Brightness.light);

        final MarkdownMermaidDiagram identicalCopy = MarkdownMermaidDiagram(
          code: lightDiagram.code,
          compiledBytes: Uint8List.fromList(lightDiagram.compiledBytes),
          svg: lightDiagram.svg,
          logicalSize: lightDiagram.logicalSize,
          semanticsLabel: lightDiagram.semanticsLabel,
          brightness: lightDiagram.brightness,
        );
        expect(lightDiagram, equals(identicalCopy));
        expect(lightDiagram.hashCode, equals(identicalCopy.hashCode));

        // Dark theme propagates Brightness.dark cleanly.
        tapped.clear();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownTheme(
                data: const MarkdownThemeData.dark(),
                child: MarkdownView(
                  '```mermaid\nflowchart LR\n  A[Start] --> B[End]\n```',
                  selectable: false,
                  delegates: withTap,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(VectorGraphic));
        await tester.pump();
        expect(tapped, hasLength(1));
        expect(tapped.single.brightness, Brightness.dark);
        expect(tapped.single.svg, contains('<svg'));
      },
    );

    testWidgets(
      'hovering interactive Mermaid diagram reveals Zoom and Copy pill controls without double-firing outer onTapMermaid',
      (WidgetTester tester) async {
        String? copiedClipboardText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'Clipboard.setData') {
              final Map<Object?, Object?>? args =
                  call.arguments as Map<Object?, Object?>?;
              copiedClipboardText = args?['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });

        final List<MarkdownMermaidDiagram> tapped = <MarkdownMermaidDiagram>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 400.0,
                child: MarkdownView(
                  '```mermaid\nflowchart LR\n  HoverA --> HoverB\n```',
                  selectable: true,
                  delegates: MarkdownBuilderDelegates(
                    onTapMermaid: (
                      BuildContext ctx,
                      MarkdownMermaidDiagram d,
                    ) => tapped.add(d),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Zoom'), findsNothing);
        expect(find.text('Copy'), findsNothing);
        expect(find.text('Copied'), findsNothing);

        final TestGesture mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 1,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        final Offset diagramCenter = tester.getCenter(
          find.byType(BuiltInMermaidDiagram),
        );
        await mouse.moveTo(diagramCenter);
        await tester.pump();

        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.zoomIn,
        );
        expect(find.text('Zoom'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
        expect(find.bySemanticsLabel('Zoom Mermaid diagram'), findsOneWidget);
        expect(find.bySemanticsLabel('Copy Mermaid source'), findsOneWidget);

        // Hovering and tapping Copy copies raw Mermaid source, toggles Copied,
        // and MUST NOT invoke onTapMermaid.
        final Offset copyCenter = tester.getCenter(find.text('Copy'));
        await mouse.moveTo(copyCenter);
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(tapped, isEmpty);
        expect(copiedClipboardText, 'flowchart LR\n  HoverA --> HoverB\n');
        expect(find.text('Copied'), findsOneWidget);
        expect(find.bySemanticsLabel('Copied'), findsOneWidget);

        // Hovering and tapping Zoom invokes onTapMermaid exactly once.
        final Offset zoomCenter = tester.getCenter(find.text('Zoom'));
        await mouse.moveTo(zoomCenter);
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        await tester.tap(find.text('Zoom'));
        await tester.pump();
        expect(tapped, hasLength(1));
        expect(tapped.single.code, 'flowchart LR\n  HoverA --> HoverB');

        // Copied label resets back to Copy after 1.5s, and leaving hides overlay.
        await tester.pump(const Duration(milliseconds: 1500));
        expect(find.text('Copy'), findsOneWidget);

        await mouse.moveTo(const Offset(599.0, 399.0));
        await tester.pump();
        expect(find.text('Zoom'), findsNothing);
        expect(find.text('Copy'), findsNothing);
      },
    );

    testWidgets(
      'onTapMermaid == null shows no hover toolbar, keeps non-zoom cursor, and tapping does nothing',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 400.0,
                child: MarkdownView(
                  '```mermaid\nflowchart LR\n  StaticA --> StaticB\n```',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final TestGesture mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 1,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        await mouse.moveTo(
          tester.getCenter(find.byType(BuiltInMermaidDiagram)),
        );
        await tester.pump();

        expect(find.text('Zoom'), findsNothing);
        expect(find.text('Copy'), findsNothing);
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          isNot(SystemMouseCursors.zoomIn),
        );

        await tester.tap(find.byType(VectorGraphic));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Delegates, overrides, and Light/Dark theme caching', () {
    testWidgets(
      'enableBuiltInMath: false and enableBuiltInMermaid: false restore raw fallbacks',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                r'Inline $x^2$'
                '\n\n'
                r'$$y = z$$'
                '\n\n'
                '```mermaid\nflowchart LR\n  A --> B\n```',
                options: MarkdownOptions(math: true),
                delegates: MarkdownBuilderDelegates(
                  enableBuiltInMath: false,
                  enableBuiltInMermaid: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TexMath), findsNothing);
        expect(find.byType(VectorGraphic), findsNothing);
        expect(find.text('x^2'), findsOneWidget);
        expect(find.text('y = z'), findsOneWidget);
        expect(find.text('mermaid'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
      },
    );

    testWidgets(
      'custom mathInlineBuilder, mathBlockBuilder, and diagramBuilder override built-in renderers',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                r'Inline $a$'
                '\n\n'
                r'$$b$$'
                '\n\n'
                '```mermaid\nflowchart LR\n  A --> B\n```',
                options: const MarkdownOptions(math: true),
                delegates: MarkdownBuilderDelegates(
                  mathInlineBuilder: (
                    BuildContext context,
                    MathInlineNode node,
                    TextStyle style,
                    GestureRecognizer? linkRecognizer,
                  ) => TextSpan(text: '[CUSTOM-IN:${node.latex}]'),
                  mathBlockBuilder: (
                    BuildContext context,
                    MathBlockNode node,
                  ) => Text('[CUSTOM-BLK:${node.latex.trim()}]'),
                  diagramBuilder: (BuildContext context, CodeBlockNode node) =>
                      Text('[CUSTOM-DIAG:${node.language}]'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TexMath), findsNothing);
        expect(find.byType(VectorGraphic), findsNothing);
        expect(find.textContaining('[CUSTOM-IN:a]'), findsOneWidget);
        expect(find.text('[CUSTOM-BLK:b]'), findsOneWidget);
        expect(find.text('[CUSTOM-DIAG:mermaid]'), findsOneWidget);
      },
    );

    testWidgets(
      'Light/Dark theme toggle keeps parseCount == 1 and reuses cached math DisplayLists and Mermaid renders',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        bool isDark = false;
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: MarkdownTheme(
                    data: isDark
                        ? const MarkdownThemeData.dark()
                        : const MarkdownThemeData.light(),
                    child: MarkdownView(
                      r'Inline $x^2 + y^2$'
                      '\n\n'
                      r'$$\int_0^1 x\,dx$$'
                      '\n\n'
                      '```mermaid\nflowchart LR\n  L --> R\n```',
                      options: const MarkdownOptions(math: true),
                      controller: controller,
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(controller.parseCount, 1);
        expect(MarkdownBuiltInRenderers.mathLayoutCount, 2);
        expect(MarkdownBuiltInRenderers.mermaidRenderCount, 1);

        final TexMathThemeData lightMathTheme = TexMathTheme.of(
          tester.element(find.byType(TexMath).first),
        );
        expect(
          lightMathTheme.foreground,
          const MarkdownThemeData.light().foreground,
        );

        // Toggle to dark: zero re-parses, zero math relayouts, dark Mermaid rendered once.
        rebuildHost(() => isDark = true);
        await tester.pumpAndSettle();

        expect(controller.parseCount, 1);
        expect(MarkdownBuiltInRenderers.mathLayoutCount, 2);
        expect(MarkdownBuiltInRenderers.mathCacheHitCount, 2);
        expect(MarkdownBuiltInRenderers.mermaidRenderCount, 2);

        final TexMathThemeData darkMathTheme = TexMathTheme.of(
          tester.element(find.byType(TexMath).first),
        );
        expect(
          darkMathTheme.foreground,
          const MarkdownThemeData.dark().foreground,
        );

        // Toggle back to light: zero re-parses, zero math relayouts, AND Mermaid cache hit!
        rebuildHost(() => isDark = false);
        await tester.pumpAndSettle();

        expect(controller.parseCount, 1);
        expect(MarkdownBuiltInRenderers.mathLayoutCount, 2);
        expect(MarkdownBuiltInRenderers.mathCacheHitCount, 4);
        expect(MarkdownBuiltInRenderers.mermaidRenderCount, 2);
        expect(MarkdownBuiltInRenderers.mermaidCacheHitCount, 1);
      },
    );
  });

  group('Streaming settled-prefix & memoization optimization', () {
    testWidgets(
      'settled prefix blocks do not rebuild across active tail token appends',
      (WidgetTester tester) async {
        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions(),
        );
        final MarkdownController viewController = MarkdownController();
        addTearDown(stream.dispose);
        addTearDown(viewController.dispose);

        int settledCodeBlockBuilds = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 500.0,
                child: MarkdownView.streaming(
                  controller: stream,
                  markdownController: viewController,
                  padding: const EdgeInsets.all(16.0),
                  delegates: MarkdownBuilderDelegates(
                    codeBlockBuilder:
                        (BuildContext context, CodeBlockNode node) {
                          if (node.language == 'dart') {
                            settledCodeBlockBuilds++;
                          }
                          return Text('CODE:${node.literal.trim()}');
                        },
                  ),
                ),
              ),
            ),
          ),
        );

        stream.append(
          '# Settled Heading\n\n'
          'Settled paragraph body.\n\n'
          '```dart\nfinal int v = 1;\n```\n\n'
          'Tail ',
        );
        await tester.pump();

        expect(stream.settledPrefixBlockCount, greaterThanOrEqualTo(3));
        expect(settledCodeBlockBuilds, 1);
        expect(find.text('Settled paragraph body.'), findsOneWidget);
        expect(find.text('Tail'), findsOneWidget);

        // Capture exact widget and render object instances of the settled paragraph.
        final Widget settledParagraphBefore = tester.widget(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Text &&
                w.textSpan?.toPlainText() == 'Settled paragraph body.',
          ),
        );
        final RenderObject settledRenderBefore = tester.renderObject(
          find.text('Settled paragraph body.'),
        );

        // Append multiple token chunks to the active tail paragraph.
        for (final String token in <String>[
          'token1 ',
          'token2 ',
          'token3 ',
          'token4 ',
          'token5.',
        ]) {
          stream.append(token);
          await tester.pump();
        }

        // Settled blocks MUST NOT have rebuilt across any of the 5 tail updates!
        expect(settledCodeBlockBuilds, 1);
        final Widget settledParagraphAfter = tester.widget(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Text &&
                w.textSpan?.toPlainText() == 'Settled paragraph body.',
          ),
        );
        final RenderObject settledRenderAfter = tester.renderObject(
          find.text('Settled paragraph body.'),
        );
        expect(
          identical(settledParagraphBefore, settledParagraphAfter),
          isTrue,
        );
        expect(identical(settledRenderBefore, settledRenderAfter), isTrue);
        expect(
          find.text('Tail token1 token2 token3 token4 token5.'),
          findsOneWidget,
        );

        // Anchor navigation still works across settled and tail slivers.
        expect(
          await viewController.scrollToAnchor(
            'settled-heading',
            duration: Duration.zero,
          ),
          isTrue,
        );

        stream.finish();
        await tester.pumpAndSettle();
        expect(settledCodeBlockBuilds, 1);
      },
    );
  });

  group('Visual parity regressions (#301)', () {
    testWidgets(
      'inline TexMath inside GFM table cells reports true intrinsic width and does not overflow column borders',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900.0,
                height: 600.0,
                child: MarkdownView('''
| Col | Formula | Next |
| :--- | :--- | :--- |
| Short | \$\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}\$ | Value |
| Wide | \$a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 + a_9 + a_{10} + a_{11} + a_{12} + a_{13} + a_{14} + a_{15} + a_{16} + a_{17} + a_{18}\$ | End |
'''),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Finder mathFinder = find.byType(TexMath);
        expect(mathFinder, findsNWidgets(2));

        final Rect firstMathRect = tester.getRect(mathFinder.at(0));
        final Rect secondMathRect = tester.getRect(mathFinder.at(1));
        final Rect nextHeaderRect = tester.getRect(find.text('Next'));
        final Rect valueCellRect = tester.getRect(find.text('Value'));

        // Intrinsic width ensures the column expands beyond the narrow "Formula"
        // header (~60px) and stays completely left of the "Next" column.
        expect(firstMathRect.width, greaterThan(80.0));
        expect(firstMathRect.right, lessThanOrEqualTo(nextHeaderRect.left));
        expect(firstMathRect.right, lessThanOrEqualTo(valueCellRect.left));

        // Ultra-wide inline math scales down within the 420px cell maxWidth and
        // stays cleanly inside its column boundary.
        expect(secondMathRect.width, lessThanOrEqualTo(420.0));
        expect(secondMathRect.right, lessThanOrEqualTo(nextHeaderRect.left));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'HTML block fallback decodes entities and inline <code> tags render with monospace code styling',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '<div>Tom &amp; Jerry &lt;tag&gt; &mdash; &#39;ok&#39;</div>\n\n'
                'Inline <code>myWidget()</code> tag.',
                scrollable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text("Tom & Jerry <tag> \u2014 'ok'"), findsOneWidget);

        final Text inlinePara = tester.widget<Text>(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Text &&
                w.textSpan != null &&
                w.textSpan!.toPlainText().contains('myWidget()'),
          ),
        );
        TextStyle? codeStyle;
        inlinePara.textSpan!.visitChildren((InlineSpan span) {
          if (span is TextSpan && span.text == 'myWidget()') {
            codeStyle = span.style;
            return false;
          }
          return true;
        });
        final MarkdownThemeData resolvedTheme = MarkdownTheme.of(
          tester.element(find.bySubtype<Text>().first),
        );
        expect(codeStyle, isNotNull);
        expect(codeStyle!.fontFamily, resolvedTheme.effectiveCodeFontFamily);
        expect(codeStyle!.backgroundColor, resolvedTheme.codeBackground);
      },
    );
  });

  group('Dual entry+byte LRU cache budgets', () {
    test('exposes default capacities, validation, and resetCacheDefaults', () {
      addTearDown(MarkdownBuiltInRenderers.resetCacheDefaults);

      expect(MarkdownBuiltInRenderers.mathMaxEntries, 1024);
      expect(MarkdownBuiltInRenderers.mathMaxBytes, 8 * 1024 * 1024);
      expect(MarkdownBuiltInRenderers.mermaidMaxEntries, 128);
      expect(MarkdownBuiltInRenderers.mermaidMaxBytes, 16 * 1024 * 1024);
      expect(MarkdownBuiltInRenderers.mathCacheBytes, 0);
      expect(MarkdownBuiltInRenderers.mermaidCacheBytes, 0);

      MarkdownBuiltInRenderers.configureCaches(
        mathMaxEntries: 42,
        mathMaxBytes: 16384,
        mermaidMaxEntries: 12,
        mermaidMaxBytes: 65536,
      );
      expect(MarkdownBuiltInRenderers.mathMaxEntries, 42);
      expect(MarkdownBuiltInRenderers.mathMaxBytes, 16384);
      expect(MarkdownBuiltInRenderers.mermaidMaxEntries, 12);
      expect(MarkdownBuiltInRenderers.mermaidMaxBytes, 65536);

      // Zero / negative values throw RangeError without mutating existing bounds.
      expect(
        () => MarkdownBuiltInRenderers.configureCaches(mathMaxEntries: 0),
        throwsRangeError,
      );
      expect(
        () => MarkdownBuiltInRenderers.configureCaches(mathMaxBytes: -1),
        throwsRangeError,
      );
      expect(
        () => MarkdownBuiltInRenderers.configureCaches(mermaidMaxEntries: 0),
        throwsRangeError,
      );
      expect(
        () => MarkdownBuiltInRenderers.configureCaches(mermaidMaxBytes: -128),
        throwsRangeError,
      );
      expect(MarkdownBuiltInRenderers.mathMaxEntries, 42);
      expect(MarkdownBuiltInRenderers.mathMaxBytes, 16384);
      expect(MarkdownBuiltInRenderers.mermaidMaxEntries, 12);
      expect(MarkdownBuiltInRenderers.mermaidMaxBytes, 65536);

      MarkdownBuiltInRenderers.resetCacheDefaults();
      expect(MarkdownBuiltInRenderers.mathMaxEntries, 1024);
      expect(MarkdownBuiltInRenderers.mathMaxBytes, 8 * 1024 * 1024);
      expect(MarkdownBuiltInRenderers.mermaidMaxEntries, 128);
      expect(MarkdownBuiltInRenderers.mermaidMaxBytes, 16 * 1024 * 1024);
    });

    testWidgets(
      'math cache enforces entry cap, LRU hit promotion, byte cap, and clean byte accounting',
      (WidgetTester tester) async {
        addTearDown(MarkdownBuiltInRenderers.resetCacheDefaults);
        await MarkdownBuiltInRenderers.warmUp();

        Future<void> renderMarkdown(String source) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: MarkdownView(source, scrollable: false)),
            ),
          );
          await tester.pump();
        }

        // Entry-count LRU eviction & hit promotion.
        MarkdownBuiltInRenderers.configureCaches(
          mathMaxEntries: 2,
          mathMaxBytes: 4 * 1024 * 1024,
        );
        await renderMarkdown(r'$a$ and $b$');
        expect(MarkdownBuiltInRenderers.mathCacheLength, 2);
        expect(MarkdownBuiltInRenderers.mathLayoutCount, 2);
        final int twoEntryBytes = MarkdownBuiltInRenderers.mathCacheBytes;
        expect(twoEntryBytes, greaterThan(0));

        // Promote $a$ by accessing it again (hit).
        await renderMarkdown(r'$a$');
        expect(MarkdownBuiltInRenderers.mathCacheHitCount, 1);
        expect(MarkdownBuiltInRenderers.mathCacheBytes, twoEntryBytes);

        // Insert $c$ -> $b$ (oldest unused) must be evicted while $a$ stays hot.
        await renderMarkdown(r'$c$');
        expect(MarkdownBuiltInRenderers.mathCacheLength, 2);
        expect(MarkdownBuiltInRenderers.mathLayoutCount, 3);
        expect(MarkdownBuiltInRenderers.mathCacheBytes, greaterThan(0));
        expect(
          MarkdownBuiltInRenderers.mathCacheBytes,
          lessThanOrEqualTo(MarkdownBuiltInRenderers.mathMaxBytes),
        );

        await renderMarkdown(r'$a$');
        expect(MarkdownBuiltInRenderers.mathCacheHitCount, 2);
        expect(MarkdownBuiltInRenderers.mathLayoutCount, 3);

        // Inserting $b$ again is a miss because it was evicted.
        await renderMarkdown(r'$b$');
        expect(MarkdownBuiltInRenderers.mathLayoutCount, 4);

        // Runtime shrink by entry count evicts LRU entries immediately.
        MarkdownBuiltInRenderers.configureCaches(mathMaxEntries: 1);
        expect(MarkdownBuiltInRenderers.mathCacheLength, 1);
        final int oneEntryBytes = MarkdownBuiltInRenderers.mathCacheBytes;
        expect(oneEntryBytes, greaterThan(0));

        // Byte-budget eviction under generous entry limit (100 entries).
        MarkdownBuiltInRenderers.clearCaches();
        MarkdownBuiltInRenderers.configureCaches(
          mathMaxEntries: 100,
          mathMaxBytes: 4 * 1024 * 1024,
        );
        await renderMarkdown(r'$$\frac{x_1 + x_2}{y_1 + y_2}$$');
        final int bytesExpr1 = MarkdownBuiltInRenderers.mathCacheBytes;
        await renderMarkdown(r'$$\sqrt{a^2 + b^2 + c^2}$$');
        final int bytesBoth = MarkdownBuiltInRenderers.mathCacheBytes;
        final int bytesExpr2 = bytesBoth - bytesExpr1;
        expect(bytesExpr1, greaterThan(0));
        expect(bytesExpr2, greaterThan(0));

        // Re-render expr 1 so expr 1 becomes most recently used and expr 2 oldest.
        await renderMarkdown(r'$$\frac{x_1 + x_2}{y_1 + y_2}$$');
        expect(MarkdownBuiltInRenderers.mathCacheHitCount, 1);

        // Shrink byte budget below two entries -> evicts expr 2, retains expr 1.
        final int tightMathBudget = bytesExpr1 + bytesExpr2 - 1;
        MarkdownBuiltInRenderers.configureCaches(mathMaxBytes: tightMathBudget);
        expect(MarkdownBuiltInRenderers.mathCacheLength, 1);
        expect(MarkdownBuiltInRenderers.mathCacheBytes, bytesExpr1);

        // Error entry byte accounting & eviction on tight byte cap.
        await renderMarkdown(r'$\invalidunknowncommand$');
        expect(
          MarkdownBuiltInRenderers.mathCacheBytes,
          lessThanOrEqualTo(tightMathBudget),
        );

        // Oversized entry exceeding maxBytes must not be inserted or breach budget.
        MarkdownBuiltInRenderers.configureCaches(mathMaxBytes: 1);
        expect(MarkdownBuiltInRenderers.mathCacheLength, 0);
        expect(MarkdownBuiltInRenderers.mathCacheBytes, 0);
        await renderMarkdown(r'$$a + b + c$$');
        expect(MarkdownBuiltInRenderers.mathCacheLength, 0);
        expect(MarkdownBuiltInRenderers.mathCacheBytes, 0);

        MarkdownBuiltInRenderers.clearCaches();
        expect(MarkdownBuiltInRenderers.mathCacheBytes, 0);
        expect(MarkdownBuiltInRenderers.mathCacheLength, 0);
      },
    );

    testWidgets(
      'mermaid cache enforces entry cap, LRU hit promotion, byte cap, and clean byte accounting',
      (WidgetTester tester) async {
        addTearDown(MarkdownBuiltInRenderers.resetCacheDefaults);
        await MarkdownBuiltInRenderers.warmUp();

        Future<void> renderDiagram(String source) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: MarkdownView(source, scrollable: false)),
            ),
          );
          await tester.pumpAndSettle();
        }

        // Entry-count LRU eviction & hit promotion.
        MarkdownBuiltInRenderers.configureCaches(
          mermaidMaxEntries: 2,
          mermaidMaxBytes: 16 * 1024 * 1024,
        );
        await renderDiagram('```mermaid\nflowchart LR\n  A --> B\n```');
        final int diagram1Bytes = MarkdownBuiltInRenderers.mermaidCacheBytes;
        expect(MarkdownBuiltInRenderers.mermaidCacheLength, 1);
        expect(MarkdownBuiltInRenderers.mermaidRenderCount, 1);
        expect(diagram1Bytes, greaterThan(128));

        await renderDiagram('```mermaid\nflowchart LR\n  C --> D\n```');
        final int twoDiagramBytes = MarkdownBuiltInRenderers.mermaidCacheBytes;
        final int diagram2Bytes = twoDiagramBytes - diagram1Bytes;
        expect(MarkdownBuiltInRenderers.mermaidCacheLength, 2);
        expect(MarkdownBuiltInRenderers.mermaidRenderCount, 2);
        expect(diagram2Bytes, greaterThan(128));

        // Promote diagram 1 via cache hit.
        await renderDiagram('```mermaid\nflowchart LR\n  A --> B\n```');
        expect(MarkdownBuiltInRenderers.mermaidCacheHitCount, greaterThan(0));
        expect(MarkdownBuiltInRenderers.mermaidCacheBytes, twoDiagramBytes);

        // Insert diagram 3 -> evicts diagram 2 (LRU), keeps diagram 1.
        await renderDiagram('```mermaid\nflowchart LR\n  E --> F\n```');
        expect(MarkdownBuiltInRenderers.mermaidCacheLength, 2);
        expect(MarkdownBuiltInRenderers.mermaidRenderCount, 3);
        final int bytesWith1And3 = MarkdownBuiltInRenderers.mermaidCacheBytes;
        final int diagram3Bytes = bytesWith1And3 - diagram1Bytes;
        expect(diagram3Bytes, greaterThan(128));

        final int rendersBeforeHit =
            MarkdownBuiltInRenderers.mermaidRenderCount;
        await renderDiagram('```mermaid\nflowchart LR\n  A --> B\n```');
        expect(MarkdownBuiltInRenderers.mermaidRenderCount, rendersBeforeHit);

        // Shrink byte budget below sum of retained entries -> evicts diagram 3 (LRU).
        MarkdownBuiltInRenderers.configureCaches(
          mermaidMaxEntries: 64,
          mermaidMaxBytes: diagram1Bytes + diagram3Bytes - 1,
        );
        expect(MarkdownBuiltInRenderers.mermaidCacheLength, 1);
        expect(MarkdownBuiltInRenderers.mermaidCacheBytes, diagram1Bytes);

        // Oversized entry exceeding maxBytes must not be inserted or breach budget.
        MarkdownBuiltInRenderers.configureCaches(mermaidMaxBytes: 32);
        expect(MarkdownBuiltInRenderers.mermaidCacheLength, 0);
        expect(MarkdownBuiltInRenderers.mermaidCacheBytes, 0);
        await renderDiagram('```mermaid\nflowchart LR\n  G --> H\n```');
        expect(MarkdownBuiltInRenderers.mermaidCacheLength, 0);
        expect(MarkdownBuiltInRenderers.mermaidCacheBytes, 0);

        // Invalid Mermaid diagram failure entry accounts non-zero bytes and clears cleanly.
        MarkdownBuiltInRenderers.resetCacheDefaults();
        await renderDiagram('```mermaid\ninvalid syntax @@@\n```');
        expect(MarkdownBuiltInRenderers.mermaidCacheLength, 1);
        expect(MarkdownBuiltInRenderers.mermaidCacheBytes, greaterThan(128));

        MarkdownBuiltInRenderers.clearCaches();
        expect(MarkdownBuiltInRenderers.mermaidCacheLength, 0);
        expect(MarkdownBuiltInRenderers.mermaidCacheBytes, 0);
      },
    );

    testWidgets(
      'BuiltInMermaidCache.currentBytes accounts for propagated svg bytes across sync and persistent worker paths',
      (WidgetTester tester) async {
        addTearDown(() async {
          MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = false;
          MarkdownBuiltInRenderers.resetCacheDefaults();
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        const String source = 'flowchart LR\n  SvgByteA --> SvgByteB';
        final DerivedMermaidTheme theme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );

        final BuiltInMermaidResult syncResult = BuiltInMermaidCache.instance
            .renderSync(source, theme);
        expect(syncResult, isA<BuiltInMermaidSuccess>());
        final BuiltInMermaidSuccess syncOk =
            syncResult as BuiltInMermaidSuccess;
        expect(syncOk.svg, contains('<svg'));

        final int expectedBytes =
            syncOk.compiledBytes.lengthInBytes +
            syncOk.svg.length * 2 +
            syncOk.semanticsLabel.length * 2 +
            source.trim().length * 2 +
            128;
        expect(BuiltInMermaidCache.instance.currentBytes, expectedBytes);
        expect(
          BuiltInMermaidCache.instance.currentBytes,
          greaterThan(syncOk.compiledBytes.lengthInBytes + syncOk.svg.length),
        );

        // Verify persistent isolate path produces the same SVG & byte accounting.
        MarkdownBuiltInRenderers.clearCaches();
        MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = true;
        await tester.runAsync(() async {
          final BuiltInMermaidResult asyncResult = await BuiltInMermaidCache
              .instance
              .render(source, theme);
          expect(asyncResult, isA<BuiltInMermaidSuccess>());
          final BuiltInMermaidSuccess asyncOk =
              asyncResult as BuiltInMermaidSuccess;
          expect(asyncOk.svg, equals(syncOk.svg));
          expect(BuiltInMermaidCache.instance.currentBytes, expectedBytes);
        });
      },
    );
  });

  group('Persistent Mermaid worker isolate', () {
    void enableAsyncWorkerWithCleanup() {
      MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
      MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers =
          MarkdownBuiltInRenderers.defaultMaxMermaidConcurrentWorkers;
      BuiltInMermaidCache.instance.debugWorker.debugBurstWorkerIdleTimeout =
          const Duration(seconds: 15);
      BuiltInMermaidCache.instance.debugWorker.debugSpawnErrorInjector = null;
      MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = true;
      addTearDown(() async {
        BuiltInMermaidCache.instance.debugWorker.debugSpawnErrorInjector = null;
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers =
            MarkdownBuiltInRenderers.defaultMaxMermaidConcurrentWorkers;
        BuiltInMermaidCache.instance.debugWorker.debugBurstWorkerIdleTimeout =
            const Duration(seconds: 15);
        MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
        MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = false;
        await MarkdownBuiltInRenderers.dispose();
      });
    }

    List<String> buildBurstDiagrams(int count, {String prefix = 'Burst'}) {
      return List<String>.generate(
        count,
        (int i) =>
            'flowchart LR\n  ${prefix}A$i["Step $i"] --> ${prefix}B$i["Out $i"]',
      );
    }

    testWidgets(
      'defaults to persistent worker, reuses single active isolate for concurrent distinct + duplicate-key diagrams, and dispose() shuts down cleanly',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();

        expect(MarkdownBuiltInRenderers.usePersistentMermaidIsolate, isTrue);
        expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );
        final DerivedMermaidTheme darkTheme = deriveMermaidTheme(
          const MarkdownThemeData.dark(),
        );

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          final int? initialIsolateId =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(initialIsolateId, isNotNull);

          // Repeat warmUp reuses the exact same isolate.
          await MarkdownBuiltInRenderers.warmUp();
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            initialIsolateId,
          );

          final Future<BuiltInMermaidResult> f1 = BuiltInMermaidCache.instance
              .render('flowchart LR\n  A1 --> B1', lightTheme);
          final Future<BuiltInMermaidResult> f1Dup = BuiltInMermaidCache
              .instance
              .render('  flowchart LR\n  A1 --> B1  ', lightTheme);
          final Future<BuiltInMermaidResult> f2 = BuiltInMermaidCache.instance
              .render('sequenceDiagram\n  Alice->>Bob: Ping', darkTheme);
          final Future<BuiltInMermaidResult> f3 = BuiltInMermaidCache.instance
              .render('flowchart TD\n  Start --> Finish', lightTheme);
          final Future<BuiltInMermaidResult> fBad = BuiltInMermaidCache.instance
              .render('not_a_diagram_type\n  X --> Y', lightTheme);

          // Identical key must deduplicate in-flight futures.
          expect(identical(f1, f1Dup), isTrue);
          expect(MarkdownBuiltInRenderers.mermaidRenderCount, 4);

          final List<BuiltInMermaidResult> results =
              await Future.wait<BuiltInMermaidResult>(
                <Future<BuiltInMermaidResult>>[f1, f1Dup, f2, f3, fBad],
              );

          expect(results[0], isA<BuiltInMermaidSuccess>());
          expect(results[1], same(results[0]));
          expect(results[2], isA<BuiltInMermaidSuccess>());
          expect(results[3], isA<BuiltInMermaidSuccess>());
          expect(results[4], isA<BuiltInMermaidFailure>());

          final BuiltInMermaidSuccess ok0 = results[0] as BuiltInMermaidSuccess;
          expect(ok0.compiledBytes, isNotEmpty);
          expect(ok0.logicalSize.width, greaterThan(0.0));
          expect(ok0.logicalSize.height, greaterThan(0.0));

          expect(MarkdownBuiltInRenderers.mermaidCacheLength, 4);
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            initialIsolateId,
          );
        });

        // resetCacheDefaults() must not alter usePersistentMermaidIsolate, and
        // dispose() must shut down the worker without mutating the setting.
        MarkdownBuiltInRenderers.resetCacheDefaults();
        expect(MarkdownBuiltInRenderers.usePersistentMermaidIsolate, isTrue);

        await MarkdownBuiltInRenderers.dispose();
        expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
        expect(MarkdownBuiltInRenderers.usePersistentMermaidIsolate, isTrue);
      },
    );

    testWidgets(
      'setting usePersistentMermaidIsolate = false immediately shuts down active worker and uses one-shot compute()',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);

          MarkdownBuiltInRenderers.usePersistentMermaidIsolate = false;
          expect(MarkdownBuiltInRenderers.usePersistentMermaidIsolate, isFalse);
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);

          // warmUp() and subsequent cold renders stay off persistent worker.
          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);

          final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
            const MarkdownThemeData.light(),
          );
          final BuiltInMermaidResult r1 = await BuiltInMermaidCache.instance
              .render('flowchart LR\n  OneShotA --> OneShotB', lightTheme);
          expect(r1, isA<BuiltInMermaidSuccess>());
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
        });

        // Widget path also renders via one-shot compute() with worker inactive.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '```mermaid\nflowchart LR\n  WidgetCompute1 --> WidgetCompute2\n```',
              ),
            ),
          ),
        );
        expect(find.text('Mermaid diagram preview'), findsOneWidget);

        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 160));
        });
        await tester.pumpAndSettle();

        expect(find.byType(VectorGraphic), findsOneWidget);
        expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);

        // Re-enabling persistent isolate spawns a fresh worker on next render.
        await tester.runAsync(() async {
          MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
          final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
            const MarkdownThemeData.light(),
          );
          final BuiltInMermaidResult r2 = await BuiltInMermaidCache.instance
              .render('flowchart LR\n  ReenabledA --> ReenabledB', lightTheme);
          expect(r2, isA<BuiltInMermaidSuccess>());
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
        });
      },
    );

    testWidgets(
      'rapid render() -> dispose() -> render() epoch transitions complete without hangs or leaked ports',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );

        await tester.runAsync(() async {
          const String code = 'flowchart LR\n  EpochA --> EpochB';
          final Future<BuiltInMermaidResult> staleFirst = BuiltInMermaidCache
              .instance
              .render(code, lightTheme);
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);

          await MarkdownBuiltInRenderers.dispose();
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);

          final Future<BuiltInMermaidResult> freshSecond = BuiltInMermaidCache
              .instance
              .render(code, lightTheme);
          final List<BuiltInMermaidResult> pair =
              await Future.wait<BuiltInMermaidResult>(
                <Future<BuiltInMermaidResult>>[staleFirst, freshSecond],
              );

          expect(pair[0], isA<BuiltInMermaidFailure>());
          expect(pair[1], isA<BuiltInMermaidSuccess>());
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);

          // Second rapid epoch transition with distinct diagrams.
          final Future<BuiltInMermaidResult> staleThird = BuiltInMermaidCache
              .instance
              .render('flowchart LR\n  EpochC --> EpochD', lightTheme);
          await MarkdownBuiltInRenderers.dispose();
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);

          final Future<BuiltInMermaidResult> freshFourth = BuiltInMermaidCache
              .instance
              .render('flowchart LR\n  EpochE --> EpochF', lightTheme);
          final List<BuiltInMermaidResult> pair2 =
              await Future.wait<BuiltInMermaidResult>(
                <Future<BuiltInMermaidResult>>[staleThird, freshFourth],
              );
          expect(pair2[0], isA<BuiltInMermaidFailure>());
          expect(pair2[1], isA<BuiltInMermaidSuccess>());
        });

        await MarkdownBuiltInRenderers.dispose();
        expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
      },
    );

    testWidgets(
      'unexpected worker exit (onExit) and uncaught error (onError) complete pending requests cleanly and recover on next render',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          final int? id1 =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(id1, isNotNull);

          // Kill the isolate directly while a compile is pending to exercise onExit.
          final Future<BuiltInMermaidResult> killedRender = BuiltInMermaidCache
              .instance
              .render('flowchart LR\n  RecoverA --> RecoverB', lightTheme);
          BuiltInMermaidCache.instance.debugWorker
              .debugKillIsolateWithoutReset();

          final BuiltInMermaidResult killedResult = await killedRender;
          expect(killedResult, isA<BuiltInMermaidFailure>());
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);

          // Next render (for the exact same diagram!) must not hit a cached
          // failure and must recover on a newly spawned worker isolate.
          final BuiltInMermaidResult recovered = await BuiltInMermaidCache
              .instance
              .render('flowchart LR\n  RecoverA --> RecoverB', lightTheme);
          expect(recovered, isA<BuiltInMermaidSuccess>());
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          final int? id2 =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(id2, isNotNull);
          expect(id2, isNot(equals(id1)));

          // Inject an uncaught worker error to exercise onError recovery.
          BuiltInMermaidCache.instance.debugWorker.debugTriggerUncaughtError();
          for (
            int i = 0;
            i < 40 && MarkdownBuiltInRenderers.isMermaidWorkerActive;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);

          final BuiltInMermaidResult afterError = await BuiltInMermaidCache
              .instance
              .render('flowchart LR\n  RecoverC --> RecoverD', lightTheme);
          expect(afterError, isA<BuiltInMermaidSuccess>());
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          final int? id3 =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(id3, isNotNull);
          expect(id3, isNot(equals(id2)));
        });
      },
    );

    test('encodePelePalette and decodePelePalette round-trip theme tokens', () {
      for (final MarkdownThemeData theme in <MarkdownThemeData>[
        const MarkdownThemeData.light(),
        const MarkdownThemeData.dark(),
      ]) {
        final PelePalette original = deriveMermaidTheme(theme).palette;
        final PelePalette restored = decodePelePalette(
          encodePelePalette(original),
        );
        expect(restored.bg, original.bg);
        expect(restored.fg, original.fg);
        expect(restored.fgOnLight, original.fgOnLight);
        expect(restored.fgOnDark, original.fgOnDark);
        expect(restored.muted, original.muted);
        expect(restored.line, original.line);
        expect(restored.surface, original.surface);
        expect(restored.surfaceAlt, original.surfaceAlt);
        expect(restored.border, original.border);
        expect(restored.accent, original.accent);
        expect(restored.code, original.code);
        expect(restored.critical, original.critical);
        expect(restored.radius, original.radius);
        expect(restored.strokeWidth, original.strokeWidth);
        expect(restored.thickStrokeWidth, original.thickStrokeWidth);
        expect(restored.hairlineStrokeWidth, original.hairlineStrokeWidth);
        expect(restored.fontFamily, original.fontFamily);
        expect(restored.monoFontFamily, original.monoFontFamily);
        expect(restored.colors, orderedEquals(original.colors));
      }
    });

    test('exposes defaultMaxMermaidConcurrentWorkers bounds and validates maxMermaidConcurrentWorkers', () {
      addTearDown(() {
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers =
            MarkdownBuiltInRenderers.defaultMaxMermaidConcurrentWorkers;
      });

      final int defaultCap =
          MarkdownBuiltInRenderers.defaultMaxMermaidConcurrentWorkers;
      expect(defaultCap, inInclusiveRange(1, 4));
      expect(MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers, defaultCap);
      expect(
        BuiltInMermaidCache.defaultMaxMermaidConcurrentWorkers,
        defaultCap,
      );

      expect(
        () => MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 0,
        throwsRangeError,
      );
      expect(
        () => MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = -2,
        throwsRangeError,
      );
      expect(
        () => BuiltInMermaidCache.maxMermaidConcurrentWorkers = 0,
        throwsRangeError,
      );
      expect(MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers, defaultCap);

      MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 3;
      expect(MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers, 3);
      expect(BuiltInMermaidCache.maxMermaidConcurrentWorkers, 3);
    });

    testWidgets(
      'sequential renders stay at activeMermaidWorkerCount == 1 and reuse primary isolate',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          final int? primaryId =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(primaryId, isNotNull);

          for (final String diagram in buildBurstDiagrams(
            6,
            prefix: 'SeqOnly',
          )) {
            final BuiltInMermaidResult result = await BuiltInMermaidCache
                .instance
                .render(diagram, lightTheme);
            expect(result, isA<BuiltInMermaidSuccess>());
            expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
            expect(
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
              primaryId,
            );
            expect(
              BuiltInMermaidCache
                  .instance
                  .debugWorker
                  .debugWorkerIsolateIdentities,
              <int>[primaryId!],
            );
          }
        });
      },
    );

    testWidgets(
      'concurrent Future.wait burst of 12 diagrams scales <= maxMermaidConcurrentWorkers and returns 12 valid renders',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );
        final List<String> diagrams = buildBurstDiagrams(12, prefix: 'Pool12');

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          final int? primaryId =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(primaryId, isNotNull);

          final List<Future<BuiltInMermaidResult>> futures = diagrams
              .map(
                (String code) =>
                    BuiltInMermaidCache.instance.render(code, lightTheme),
              )
              .toList(growable: false);

          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 4);

          final List<BuiltInMermaidResult> results =
              await Future.wait<BuiltInMermaidResult>(futures);
          expect(results, hasLength(12));
          for (final BuiltInMermaidResult result in results) {
            expect(result, isA<BuiltInMermaidSuccess>());
            final BuiltInMermaidSuccess ok = result as BuiltInMermaidSuccess;
            expect(ok.compiledBytes, isNotEmpty);
            expect(ok.logicalSize.width, greaterThan(0.0));
            expect(ok.logicalSize.height, greaterThan(0.0));
          }

          expect(
            MarkdownBuiltInRenderers.activeMermaidWorkerCount,
            inInclusiveRange(2, 4),
          );
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            primaryId,
          );
          final List<int> identities = BuiltInMermaidCache
              .instance
              .debugWorker
              .debugWorkerIsolateIdentities;
          expect(identities, contains(primaryId));
          expect(identities.toSet().length, identities.length);

          // Cap=1 disables burst workers while keeping primary persistent.
          await MarkdownBuiltInRenderers.dispose();
          MarkdownBuiltInRenderers.clearCaches();
          MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 1;
          await MarkdownBuiltInRenderers.warmUp();
          final int? cap1PrimaryId =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(cap1PrimaryId, isNotNull);

          final List<Future<BuiltInMermaidResult>> cap1Futures = diagrams
              .map(
                (String code) =>
                    BuiltInMermaidCache.instance.render(code, lightTheme),
              )
              .toList(growable: false);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);

          final List<BuiltInMermaidResult> cap1Results =
              await Future.wait<BuiltInMermaidResult>(cap1Futures);
          for (final BuiltInMermaidResult result in cap1Results) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            cap1PrimaryId,
          );
        });
      },
    );

    testWidgets(
      'burst workers tear down automatically after debugBurstWorkerIdleTimeout while primary keeps exact identity',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;
        BuiltInMermaidCache.instance.debugWorker.debugBurstWorkerIdleTimeout =
            const Duration(milliseconds: 50);

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );
        final List<String> diagrams = buildBurstDiagrams(12, prefix: 'Idle');

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          final int? primaryId =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(primaryId, isNotNull);

          final List<Future<BuiltInMermaidResult>> futures = diagrams
              .map(
                (String code) =>
                    BuiltInMermaidCache.instance.render(code, lightTheme),
              )
              .toList(growable: false);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 4);

          final List<BuiltInMermaidResult> results =
              await Future.wait<BuiltInMermaidResult>(futures);
          for (final BuiltInMermaidResult result in results) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }

          for (
            int i = 0;
            i < 60 && MarkdownBuiltInRenderers.activeMermaidWorkerCount > 1;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 15));
          }

          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            primaryId,
          );
          expect(
            BuiltInMermaidCache
                .instance
                .debugWorker
                .debugWorkerIsolateIdentities,
            <int>[primaryId!],
          );

          final BuiltInMermaidResult afterIdle = await BuiltInMermaidCache
              .instance
              .render('flowchart LR\n  AfterIdleA --> AfterIdleB', lightTheme);
          expect(afterIdle, isA<BuiltInMermaidSuccess>());
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            primaryId,
          );
        });
      },
    );

    testWidgets(
      'dynamically shrinking maxMermaidConcurrentWorkers = 1 mid-flight completes in-flight jobs and tears down excess workers',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );
        final List<String> diagrams = buildBurstDiagrams(12, prefix: 'Shrink');

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          final int? primaryId =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(primaryId, isNotNull);

          final List<Future<BuiltInMermaidResult>> futures = diagrams
              .map(
                (String code) =>
                    BuiltInMermaidCache.instance.render(code, lightTheme),
              )
              .toList(growable: false);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 4);

          // Shrink mid-flight while burst workers are starting/busy.
          MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 1;

          final List<BuiltInMermaidResult> results =
              await Future.wait<BuiltInMermaidResult>(futures);
          for (final BuiltInMermaidResult result in results) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            primaryId,
          );

          // Also verify immediate teardown of idle excess burst workers.
          MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;
          MarkdownBuiltInRenderers.clearCaches();
          final List<BuiltInMermaidResult> warmBurstResults =
              await Future.wait<BuiltInMermaidResult>(
                buildBurstDiagrams(12, prefix: 'IdleShrink').map(
                  (String code) =>
                      BuiltInMermaidCache.instance.render(code, lightTheme),
                ),
              );
          for (final BuiltInMermaidResult result in warmBurstResults) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }
          expect(
            MarkdownBuiltInRenderers.activeMermaidWorkerCount,
            greaterThan(1),
          );

          MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 1;
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            primaryId,
          );
        });
      },
    );

    testWidgets(
      'usePersistentMermaidIsolate = false and dispose() tear down primary plus all burst workers',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          final List<BuiltInMermaidResult> burst1 =
              await Future.wait<BuiltInMermaidResult>(
                buildBurstDiagrams(12, prefix: 'ShutdownOptOut').map(
                  (String code) =>
                      BuiltInMermaidCache.instance.render(code, lightTheme),
                ),
              );
          for (final BuiltInMermaidResult result in burst1) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }
          expect(
            MarkdownBuiltInRenderers.activeMermaidWorkerCount,
            greaterThan(1),
          );

          MarkdownBuiltInRenderers.usePersistentMermaidIsolate = false;
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 0);
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
          expect(
            BuiltInMermaidCache
                .instance
                .debugWorker
                .debugWorkerIsolateIdentities,
            isEmpty,
          );

          MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.warmUp();
          final List<BuiltInMermaidResult> burst2 =
              await Future.wait<BuiltInMermaidResult>(
                buildBurstDiagrams(12, prefix: 'ShutdownDispose').map(
                  (String code) =>
                      BuiltInMermaidCache.instance.render(code, lightTheme),
                ),
              );
          for (final BuiltInMermaidResult result in burst2) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }
          expect(
            MarkdownBuiltInRenderers.activeMermaidWorkerCount,
            greaterThan(1),
          );

          await MarkdownBuiltInRenderers.dispose();
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 0);
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
          expect(
            BuiltInMermaidCache
                .instance
                .debugWorker
                .debugWorkerIsolateIdentities,
            isEmpty,
          );
        });
      },
    );

    testWidgets(
      'killing or throwing on primary worker during concurrent burst fails only dead worker active job and recovers remaining work',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );
        final List<String> killDiagrams = buildBurstDiagrams(
          12,
          prefix: 'KillBurst',
        );

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          final int? id1 =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(id1, isNotNull);

          final List<Future<BuiltInMermaidResult>> futures = killDiagrams
              .map(
                (String code) =>
                    BuiltInMermaidCache.instance.render(code, lightTheme),
              )
              .toList(growable: false);
          BuiltInMermaidCache.instance.debugWorker
              .debugKillIsolateWithoutReset();

          final List<BuiltInMermaidResult> results =
              await Future.wait<BuiltInMermaidResult>(futures);
          expect(results[0], isA<BuiltInMermaidFailure>());
          for (int i = 1; i < results.length; i++) {
            expect(results[i], isA<BuiltInMermaidSuccess>());
          }

          // Dead primary active failure must not be cached; retry succeeds on
          // recovered pool with a new primary isolate identity.
          final BuiltInMermaidResult retried = await BuiltInMermaidCache
              .instance
              .render(killDiagrams[0], lightTheme);
          expect(retried, isA<BuiltInMermaidSuccess>());
          final int? id2 =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(id2, isNotNull);
          expect(id2, isNot(equals(id1)));

          // Uncaught error injected into primary during a concurrent burst.
          MarkdownBuiltInRenderers.clearCaches();
          final List<String> errDiagrams = buildBurstDiagrams(
            10,
            prefix: 'ErrBurst',
          );
          final List<Future<BuiltInMermaidResult>> errFutures = errDiagrams
              .map(
                (String code) =>
                    BuiltInMermaidCache.instance.render(code, lightTheme),
              )
              .toList(growable: false);
          BuiltInMermaidCache.instance.debugWorker.debugTriggerUncaughtError();

          final List<BuiltInMermaidResult> errResults =
              await Future.wait<BuiltInMermaidResult>(errFutures);
          for (int i = 0; i < errResults.length; i++) {
            if (errResults[i] is BuiltInMermaidFailure) {
              final BuiltInMermaidResult retryOk = await BuiltInMermaidCache
                  .instance
                  .render(errDiagrams[i], lightTheme);
              expect(retryOk, isA<BuiltInMermaidSuccess>());
            }
          }

          // Wait briefly if the fatal uncaught error exit arrives right after
          // the batch completed, then confirm primary recovers with a fresh id.
          await Future<void>.delayed(const Duration(milliseconds: 25));
          final BuiltInMermaidResult afterErr = await BuiltInMermaidCache
              .instance
              .render('flowchart LR\n  PostErrA --> PostErrB', lightTheme);
          expect(afterErr, isA<BuiltInMermaidSuccess>());
          final int? id3 =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(id3, isNotNull);
          expect(id3, isNot(equals(id2)));
        });
      },
    );

    testWidgets(
      'auxiliary burst IsolateSpawnException preserves surviving primary worker and drains burst without sync fallback',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          final int? primaryId =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(primaryId, isNotNull);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);

          int auxiliaryAttempts = 0;
          BuiltInMermaidCache
              .instance
              .debugWorker
              .debugSpawnErrorInjector = ({required bool isPrimary}) {
            if (!isPrimary) {
              auxiliaryAttempts++;
              return IsolateSpawnException('Simulated auxiliary isolate limit');
            }
            return null;
          };

          final List<BuiltInMermaidResult> warmBurst =
              await Future.wait<BuiltInMermaidResult>(
                buildBurstDiagrams(8, prefix: 'AuxSpawnFail').map(
                  (String code) =>
                      BuiltInMermaidCache.instance.render(code, lightTheme),
                ),
              );
          expect(auxiliaryAttempts, greaterThan(0));
          for (final BuiltInMermaidResult result in warmBurst) {
            expect(result, isA<BuiltInMermaidSuccess>());
            final BuiltInMermaidSuccess ok = result as BuiltInMermaidSuccess;
            expect(ok.compiledBytes, isNotEmpty);
            expect(ok.logicalSize.width, greaterThan(0.0));
            expect(ok.logicalSize.height, greaterThan(0.0));
          }
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            primaryId,
          );
          expect(
            BuiltInMermaidCache
                .instance
                .debugWorker
                .debugWorkerIsolateIdentities,
            <int>[primaryId!],
          );

          // Follow-up warmUp and render continue using the exact same primary
          // isolate (proving _spawnUnsupported was not set).
          await MarkdownBuiltInRenderers.warmUp();
          final BuiltInMermaidResult followUp = await BuiltInMermaidCache
              .instance
              .render(
                'flowchart LR\n  AfterAuxFailA --> AfterAuxFailB',
                lightTheme,
              );
          expect(followUp, isA<BuiltInMermaidSuccess>());
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            primaryId,
          );
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);

          // Cold start (no prior warmUp) with auxiliary IsolateSpawnException
          // while primary is still starting also drains cleanly on primary.
          await MarkdownBuiltInRenderers.dispose();
          MarkdownBuiltInRenderers.clearCaches();
          auxiliaryAttempts = 0;
          final List<BuiltInMermaidResult> coldBurst =
              await Future.wait<BuiltInMermaidResult>(
                buildBurstDiagrams(4, prefix: 'ColdAuxFail').map(
                  (String code) =>
                      BuiltInMermaidCache.instance.render(code, lightTheme),
                ),
              );
          expect(auxiliaryAttempts, greaterThan(0));
          for (final BuiltInMermaidResult result in coldBurst) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);

          // Lifting the fault restores auxiliary burst scaling immediately.
          BuiltInMermaidCache.instance.debugWorker.debugSpawnErrorInjector =
              null;
          MarkdownBuiltInRenderers.clearCaches();
          final List<BuiltInMermaidResult> recoveredBurst =
              await Future.wait<BuiltInMermaidResult>(
                buildBurstDiagrams(8, prefix: 'RecoveredBurst').map(
                  (String code) =>
                      BuiltInMermaidCache.instance.render(code, lightTheme),
                ),
              );
          for (final BuiltInMermaidResult result in recoveredBurst) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }
          expect(
            MarkdownBuiltInRenderers.activeMermaidWorkerCount,
            greaterThan(1),
          );
        });
      },
    );

    testWidgets(
      'auxiliary non-IsolateSpawnException keeps surviving worker while 0-worker IsolateSpawnException falls back to sync',
      (WidgetTester tester) async {
        enableAsyncWorkerWithCleanup();
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 4;

        final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
          const MarkdownThemeData.light(),
        );

        await tester.runAsync(() async {
          await MarkdownBuiltInRenderers.warmUp();
          final int? primaryId =
              BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity;
          expect(primaryId, isNotNull);

          int stateErrorAttempts = 0;
          BuiltInMermaidCache.instance.debugWorker.debugSpawnErrorInjector =
              ({required bool isPrimary}) {
                if (!isPrimary) {
                  stateErrorAttempts++;
                  return StateError('Simulated auxiliary spawn failure');
                }
                return null;
              };

          final List<BuiltInMermaidResult> nonSpawnExcBurst =
              await Future.wait<BuiltInMermaidResult>(
                buildBurstDiagrams(6, prefix: 'AuxStateErr').map(
                  (String code) =>
                      BuiltInMermaidCache.instance.render(code, lightTheme),
                ),
              );
          expect(stateErrorAttempts, greaterThan(0));
          for (final BuiltInMermaidResult result in nonSpawnExcBurst) {
            expect(result, isA<BuiltInMermaidSuccess>());
          }
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
          expect(
            BuiltInMermaidCache.instance.debugWorker.debugIsolateIdentity,
            primaryId,
          );

          // Primary IsolateSpawnException with 0 active workers falls back to
          // synchronous compilation without leaving orphaned worker slots.
          await MarkdownBuiltInRenderers.dispose();
          MarkdownBuiltInRenderers.clearCaches();
          BuiltInMermaidCache.instance.debugWorker.debugSpawnErrorInjector = ({
            required bool isPrimary,
          }) => IsolateSpawnException('Simulated isolates unsupported');

          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 0);

          final BuiltInMermaidResult syncFallbackResult =
              await BuiltInMermaidCache.instance.render(
                'flowchart LR\n  SyncFallbackA --> SyncFallbackB',
                lightTheme,
              );
          expect(syncFallbackResult, isA<BuiltInMermaidSuccess>());
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 0);

          // After dispose() resets _spawnUnsupported and fault clears, the
          // persistent worker spawns cleanly again.
          BuiltInMermaidCache.instance.debugWorker.debugSpawnErrorInjector =
              null;
          await MarkdownBuiltInRenderers.dispose();
          final BuiltInMermaidResult recovered = await BuiltInMermaidCache
              .instance
              .render(
                'flowchart LR\n  RecoverSyncA --> RecoverSyncB',
                lightTheme,
              );
          expect(recovered, isA<BuiltInMermaidSuccess>());
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
        });
      },
    );
  });
}

final class _FrameOneAnchorHost extends StatefulWidget {
  const _FrameOneAnchorHost({
    required this.source,
    required this.anchor,
    required this.controller,
    required this.scrollController,
    required this.onResult,
  });

  final String source;
  final String anchor;
  final MarkdownController controller;
  final ScrollController scrollController;
  final ValueChanged<bool> onResult;

  @override
  State<_FrameOneAnchorHost> createState() => _FrameOneAnchorHostState();
}

final class _FrameOneAnchorHostState extends State<_FrameOneAnchorHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        unawaited(
          widget.controller
              .scrollToAnchor(widget.anchor, duration: Duration.zero)
              .then(widget.onResult),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownView(
      widget.source,
      controller: widget.controller,
      scrollController: widget.scrollController,
      padding: const EdgeInsets.all(20.0),
    );
  }
}
