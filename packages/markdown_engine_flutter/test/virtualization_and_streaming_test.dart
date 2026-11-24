import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:markdown_engine_flutter/src/fast_text.dart';
import 'package:markdown_engine_flutter/src/isolate_parse_io.dart';
import 'package:markdown_engine_flutter/src/streaming_canvas.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart' show TexMath;
import 'package:vector_graphics/vector_graphics.dart' show VectorGraphic;

void main() {
  group('Zero-reparse theme toggle', () {
    testWidgets(
      'toggling Light and Dark theme performs 0 re-parses and updates styling',
      (WidgetTester tester) async {
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        bool isDark = false;
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuildHost = setState;
              final MarkdownThemeData mdTheme = isDark
                  ? const MarkdownThemeData.dark()
                  : const MarkdownThemeData.light();
              return MaterialApp(
                theme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: isDark ? Brightness.dark : Brightness.light,
                  ),
                ),
                home: Scaffold(
                  body: MarkdownTheme(
                    data: mdTheme,
                    child: MarkdownView(
                      '# Theme Invariance\n\nParagraph text stays parsed once.',
                      options: const MarkdownOptions.extended(),
                      controller: controller,
                    ),
                  ),
                ),
              );
            },
          ),
        );

        expect(controller.parseCount, 1);
        expect(controller.outline.length, 1);
        expect(find.text('Theme Invariance'), findsOneWidget);

        // Toggle to dark theme.
        rebuildHost(() => isDark = true);
        await tester.pumpAndSettle();
        expect(controller.parseCount, 1);

        // Toggle back to light theme.
        rebuildHost(() => isDark = false);
        await tester.pumpAndSettle();
        expect(controller.parseCount, 1);

        // Verify dark text color actually resolved during dark mode.
        rebuildHost(() => isDark = true);
        await tester.pumpAndSettle();
        final Text paragraphText = tester.widget<Text>(
          find.text('Paragraph text stays parsed once.'),
        );
        expect(
          paragraphText.textSpan?.style?.color,
          const MarkdownThemeData.dark().foreground,
        );
        expect(controller.parseCount, 1);
      },
    );

    testWidgets(
      're-parses only when data or options change, and never in MarkdownView.document',
      (WidgetTester tester) async {
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        String source = 'Initial paragraph';
        MarkdownOptions options = const MarkdownOptions.gfm();
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: MarkdownView(
                    source,
                    options: options,
                    controller: controller,
                  ),
                ),
              );
            },
          ),
        );

        expect(controller.parseCount, 1);

        // Rebuild with identical data & options: still 1 parse.
        rebuildHost(() {});
        await tester.pump();
        expect(controller.parseCount, 1);

        // Change data -> 2 parses.
        rebuildHost(() => source = 'Updated paragraph');
        await tester.pump();
        expect(controller.parseCount, 2);
        expect(find.text('Updated paragraph'), findsOneWidget);

        // Change options -> 3 parses.
        rebuildHost(() => options = const MarkdownOptions.extended());
        await tester.pump();
        expect(controller.parseCount, 3);

        // MarkdownView.document performs zero parsing.
        final MarkdownController docController = MarkdownController();
        addTearDown(docController.dispose);
        final MarkdownDocument preParsed = const MarkdownEngine().parse(
          '# Preparsed\n\nZero parse widget.',
          options: const MarkdownOptions.gfm(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView.document(
                document: preParsed,
                controller: docController,
              ),
            ),
          ),
        );
        expect(docController.parseCount, 0);
        expect(docController.document, same(preParsed));
        expect(find.text('Preparsed'), findsOneWidget);
      },
    );
  });

  group('Sliver virtualization and navigation', () {
    testWidgets(
      '400-block document materializes far fewer than 400 block widgets on screen',
      (WidgetTester tester) async {
        final StringBuffer buffer = StringBuffer();
        for (int i = 0; i < 400; i++) {
          if (i % 50 == 0) {
            buffer.writeln('## Section $i\n');
          } else {
            buffer.writeln('Block paragraph number $i with content.\n');
          }
        }
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 500.0,
                child: MarkdownView(
                  buffer.toString(),
                  options: const MarkdownOptions.gfm(),
                  controller: controller,
                ),
              ),
            ),
          ),
        );

        expect(controller.document.blocks.length, 400);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);

        // First block is visible; last block is virtualized off-screen.
        expect(find.text('Section 0'), findsOneWidget);
        expect(
          find.text('Block paragraph number 399 with content.'),
          findsNothing,
        );

        // Count actual materialized top-level block elements by ValueKey<String>.
        final Set<String> allBlockIds = controller.document.blocks
            .map((MarkdownBlockNode b) => b.blockId)
            .toSet();
        final Finder materializedBlocks = find.byWidgetPredicate(
          (Widget w) =>
              w.key is ValueKey<String> &&
              allBlockIds.contains((w.key! as ValueKey<String>).value),
        );
        final int builtCount = materializedBlocks.evaluate().length;
        expect(builtCount, greaterThan(0));
        expect(builtCount, lessThan(80));

        // Programmatic navigation to a distant anchor and line works cleanly.
        final Future<bool> scrolledFuture = controller.scrollToAnchor(
          'section-350',
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        expect(await scrolledFuture, isTrue);
        expect(find.text('Section 350'), findsOneWidget);
        expect(controller.readingPlace.blockIndex, greaterThanOrEqualTo(340));

        final bool jumpedLine = await controller.scrollToLine(
          1,
          duration: Duration.zero,
        );
        await tester.pump();
        expect(jumpedLine, isTrue);
        expect(controller.readingPlace.blockIndex, 0);
      },
    );

    testWidgets(
      'SliverMarkdownDocument composes cleanly inside a CustomScrollView',
      (WidgetTester tester) async {
        final MarkdownDocument doc = const MarkdownEngine().parse(
          '# Header\n\nBody paragraph inside sliver.',
          options: const MarkdownOptions.gfm(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: <Widget>[
                  const SliverToBoxAdapter(child: Text('Top Banner')),
                  SliverMarkdownDocument(
                    document: doc,
                    padding: const EdgeInsets.all(16.0),
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('Top Banner'), findsOneWidget);
        expect(find.text('Header'), findsOneWidget);
        expect(find.text('Body paragraph inside sliver.'), findsOneWidget);
      },
    );
  });

  group('MarkdownView.streaming', () {
    testWidgets(
      'updates incrementally across chunked StreamingMarkdownController.append calls',
      (WidgetTester tester) async {
        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.gfm(),
        );
        final MarkdownController viewController = MarkdownController();
        addTearDown(viewController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView.streaming(
                controller: stream,
                markdownController: viewController,
              ),
            ),
          ),
        );

        expect(find.byType(SizedBox), findsOneWidget);

        stream.append('# Streaming Title\n\nFirst settled ');
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Streaming Title'), findsOneWidget);
        expect(find.text('First settled'), findsOneWidget);

        stream.append('paragraph.\n\nSecond ');
        await tester.pump(const Duration(milliseconds: 50));
        expect(stream.settledBlockCount, greaterThanOrEqualTo(2));
        expect(find.text('First settled paragraph.'), findsOneWidget);
        expect(find.text('Second'), findsOneWidget);

        stream.append('tail paragraph.');
        stream.finish();
        await tester.pumpAndSettle();

        expect(find.text('Second tail paragraph.'), findsOneWidget);
        expect(viewController.document.blocks.length, 3);
      },
    );

    testWidgets('supports external Listenable without polling', (
      WidgetTester tester,
    ) async {
      final StreamingMarkdownController stream = StreamingMarkdownController(
        options: const MarkdownOptions.gfm(),
      );
      final ValueNotifier<int> tick = ValueNotifier<int>(0);
      addTearDown(tick.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownView.streaming(
              controller: stream,
              listenable: tick,
              pollInterval: null,
            ),
          ),
        ),
      );

      stream.append('Chunk driven by listenable.');
      tick.value++;
      await tester.pump();

      expect(find.text('Chunk driven by listenable.'), findsOneWidget);
    });
  });

  group('MarkdownDocumentReader', () {
    test('parses short documents synchronously (< 4096 code units)', () async {
      final MarkdownDocumentReader reader = MarkdownDocumentReader();
      addTearDown(reader.dispose);

      final MarkdownDocument doc = await reader.update(
        '# Short\n\nFast synchronous path.',
      );

      expect(reader.isParsing, isFalse);
      expect(reader.lastError, isNull);
      expect(reader.parseCount, 1);
      expect(reader.backgroundParseCount, 0);
      expect(doc.blocks.length, 2);
      expect(reader.document, same(doc));
    });

    test('parses large documents (>= 4096 code units) in a background isolate with latest-wins coalescing', () async {
      final MarkdownDocumentReader reader = MarkdownDocumentReader(
        engine: const MarkdownEngine(defaultOptions: MarkdownOptions.gfm()),
      );
      addTearDown(reader.dispose);

      String makeLargeDoc(String tag) {
        final StringBuffer sb = StringBuffer('# Document $tag\n\n');
        for (int i = 0; i < 140; i++) {
          sb.writeln(
            'Paragraph $i in $tag with **bold** and `code` text to exceed threshold.\n',
          );
        }
        return sb.toString();
      }

      final String docA = makeLargeDoc('Alpha');
      final String docB = makeLargeDoc('Beta');
      final String docC = makeLargeDoc('Gamma');
      expect(docA.length, greaterThanOrEqualTo(4096));
      expect(docC.length, greaterThanOrEqualTo(4096));

      final List<bool> parsingStates = <bool>[];
      reader.addListener(() => parsingStates.add(reader.isParsing));

      final Future<MarkdownDocument> fA = reader.update(docA);
      final Future<MarkdownDocument> fB = reader.update(docB);
      final Future<MarkdownDocument> fC = reader.update(docC);

      expect(reader.isParsing, isTrue);

      final List<MarkdownDocument> results = await Future.wait(
        <Future<MarkdownDocument>>[fA, fB, fC],
      );

      expect(reader.isParsing, isFalse);
      expect(reader.lastError, isNull);
      expect(reader.backgroundParseCount, greaterThanOrEqualTo(1));
      expect(reader.document.source, docC);
      expect(results.last.source, docC);
      expect(reader.document.outline.first.text, 'Document Gamma');
      expect(parsingStates, contains(true));
      expect(parsingStates.last, isFalse);
    });

    test('captures parse budget errors cleanly in lastError', () async {
      final MarkdownDocumentReader reader = MarkdownDocumentReader();
      addTearDown(reader.dispose);

      await reader.update(
        'Too long input',
        options: const MarkdownOptions(maxInputLength: 4),
      );

      expect(reader.lastError, isA<RangeError>());
      expect(reader.isParsing, isFalse);
      expect(reader.hasRead, isFalse);
    });
  });

  group('Wave 3 streaming, incremental, controller & selection regressions', () {
    testWidgets(
      'MarkdownView.streaming pushes chunks with zero timers and supports reset() + append() after finish()',
      (WidgetTester tester) async {
        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        addTearDown(stream.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MarkdownView.streaming(controller: stream)),
          ),
        );

        stream.append('First push chunk.');
        await tester.pump();
        expect(find.text('First push chunk.'), findsOneWidget);

        stream.finish();
        await tester.pump();
        expect(stream.isFinished, isTrue);

        // Reset and stream new chunks without recreating MarkdownView.
        stream.reset();
        await tester.pump();
        expect(find.text('First push chunk.'), findsNothing);

        stream.append('Second stream after reset.');
        await tester.pump();
        expect(find.text('Second stream after reset.'), findsOneWidget);
      },
    );

    testWidgets(
      'MarkdownView.didUpdateWidget uses IncrementalMarkdownParser and preserves <details> state',
      (WidgetTester tester) async {
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        String trailing = 'Trailing v1';
        late StateSetter rebuild;

        String makeSource(String tail) =>
            '''
<details>
<summary>Persistent Disclosure</summary>

Disclosure inner body.

</details>

$tail
''';

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return MaterialApp(
                home: Scaffold(
                  body: MarkdownView(
                    makeSource(trailing),
                    options: const MarkdownOptions.extended(),
                    controller: controller,
                    selectable: false,
                  ),
                ),
              );
            },
          ),
        );

        final String initialDetailsId =
            controller.document.blocks.first.blockId;
        await tester.tap(find.text('Persistent Disclosure'));
        await tester.pump();
        expect(find.text('Disclosure inner body.'), findsOneWidget);

        rebuild(() => trailing = 'Trailing v2');
        await tester.pump();

        expect(find.text('Trailing v2'), findsOneWidget);
        expect(controller.document.blocks.first.blockId, initialDetailsId);
        expect(find.text('Disclosure inner body.'), findsOneWidget);
      },
    );

    testWidgets(
      'swapping MarkdownView instances preserves shared ScrollController ownership and RenderBox readingPlace',
      (WidgetTester tester) async {
        final MarkdownController controller = MarkdownController();
        final ScrollController scrollController = ScrollController();
        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        addTearDown(controller.dispose);
        addTearDown(scrollController.dispose);
        addTearDown(stream.dispose);

        final StringBuffer doc = StringBuffer();
        for (int i = 0; i < 60; i++) {
          doc.writeln('## Heading $i\n\nParagraph content $i.\n');
        }
        stream.append(doc.toString());
        stream.finish();

        bool useStreaming = false;
        late StateSetter rebuild;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 600.0,
                    height: 300.0,
                    child: useStreaming
                        ? MarkdownView.streaming(
                            controller: stream,
                            markdownController: controller,
                            scrollController: scrollController,
                          )
                        : MarkdownView(
                            doc.toString(),
                            options: const MarkdownOptions.extended(),
                            controller: controller,
                            scrollController: scrollController,
                          ),
                  ),
                ),
              );
            },
          ),
        );

        // Swap to streaming view sharing both controller and scrollController.
        rebuild(() => useStreaming = true);
        await tester.pump();

        // ScrollController must still be attached to controller after oldState.dispose().
        expect(controller.scrollController, same(scrollController));

        int docNotifyCount = 0;
        int placeNotifyCount = 0;
        controller.addListener(() => docNotifyCount++);
        controller.readingPlaceNotifier.addListener(() => placeNotifyCount++);

        scrollController.jumpTo(900.0);
        await tester.pump();

        expect(placeNotifyCount, greaterThan(0));
        expect(docNotifyCount, 0);
        expect(controller.readingPlace.blockIndex, greaterThan(0));
      },
    );

    testWidgets(
      'scrollToAnchor handles showFrontmatter: false, variable-height docs, duplicate anchors, and unreachable targets',
      (WidgetTester tester) async {
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        final StringBuffer doc = StringBuffer(
          '---\ntitle: Hidden Frontmatter\n---\n\n'
          '# Intro {#intro}\n\n',
        );
        // Variable heights: tall code blocks early, short paragraphs later.
        for (int i = 1; i <= 150; i++) {
          if (i <= 20) {
            doc.writeln(
              '```dart\n// Block $i\n' + ('int x$i = $i;\n' * 12) + '```\n',
            );
          } else if (i == 120) {
            doc.writeln(
              '## Variable Target {#var-target}\n\nReached paragraph.\n',
            );
          } else {
            doc.writeln('Short line $i.\n');
          }
        }
        doc.writeln(
          '<details>\n<summary>Closed Target</summary>\n\n<a id="inside-closed"></a>\n\n</details>\n',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 350.0,
                child: MarkdownView(
                  doc.toString(),
                  options: const MarkdownOptions.extended(),
                  controller: controller,
                  showFrontmatter: false,
                ),
              ),
            ),
          ),
        );

        // First visible block is # Intro even though FrontmatterNode is block 0.
        final Future<bool> introFuture = controller.scrollToAnchor(
          'intro',
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        expect(await introFuture, isTrue);
        expect(controller.scrollController!.offset, 0.0);

        // Variable-height offscreen convergence reaches block 120 cleanly.
        final Future<bool> targetFuture = controller.scrollToAnchor(
          'var-target',
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        expect(await targetFuture, isTrue);
        expect(find.text('Variable Target'), findsOneWidget);

        // Capture mounted context before probing down to collapsed <details>.
        final BuildContext firstCtx = tester.element(
          find.text('Variable Target'),
        );
        controller.registerAnchor('dup-slug', firstCtx);

        // Unreachable anchor inside collapsed <details> returns false cleanly.
        final Future<bool> hiddenFuture = controller.scrollToAnchor(
          'inside-closed',
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        expect(await hiddenFuture, isFalse);

        // Missing anchor returns false.
        expect(
          await controller.scrollToAnchor(
            'does-not-exist',
            duration: Duration.zero,
          ),
          isFalse,
        );

        // Duplicate anchors/blocks do not erase remaining mounted context.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (BuildContext ctx) {
                  controller.registerAnchor('dup-slug', ctx);
                  return const Text('Second mount');
                },
              ),
            ),
          ),
        );
        // Unmounting firstCtx happens after registering ctx; dup-slug stays reachable.
        expect(
          await controller.scrollToAnchor('dup-slug', duration: Duration.zero),
          isTrue,
        );
      },
    );

    testWidgets(
      'SliverMarkdownDocument defaults addAutomaticKeepAlives to true and offscreen Cmd+A exports full plainText',
      (WidgetTester tester) async {
        String? copiedClipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                copiedClipboard = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final FocusNode focusNode = FocusNode();
        final MarkdownController controller = MarkdownController();
        addTearDown(focusNode.dispose);
        addTearDown(controller.dispose);

        final StringBuffer bigDoc = StringBuffer();
        for (int i = 0; i < 200; i++) {
          bigDoc.writeln('Virtualized paragraph #$i for full Cmd+A.\n');
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 300.0,
                child: MarkdownView(
                  bigDoc.toString(),
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        );

        final SliverMarkdownDocument sliver = tester
            .widget<SliverMarkdownDocument>(
              find.byType(SliverMarkdownDocument),
            );
        expect(sliver.addAutomaticKeepAlives, isTrue);
        expect(
          find.text('Virtualized paragraph #199 for full Cmd+A.'),
          findsNothing,
        );

        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();

        expect(copiedClipboard, controller.document.toPlainText());
        expect(
          copiedClipboard,
          contains('Virtualized paragraph #199 for full Cmd+A.'),
        );
      },
    );

    test('MarkdownDocumentReader implements ValueListenable, dedups active in-flight work, avoids spurious finally notify, and falls back on IsolateSpawnException', () async {
      final MarkdownDocumentReader reader = MarkdownDocumentReader(
        syncThreshold: 128,
      );
      addTearDown(reader.dispose);

      expect(reader, isA<ValueListenable<MarkdownDocument>>());
      expect(reader.hasRead, isFalse);
      expect(reader.value, same(reader.document));

      final String largeA = 'Paragraph A ' * 20;
      expect(largeA.length, greaterThanOrEqualTo(128));

      // Duplicate concurrent update on the exact same in-flight source reuses active parse.
      final Future<MarkdownDocument> f1 = reader.update(largeA);
      final Future<MarkdownDocument> f2 = reader.update(largeA);
      final List<MarkdownDocument> sameResults = await Future.wait(
        <Future<MarkdownDocument>>[f1, f2],
      );
      expect(sameResults[0], same(sameResults[1]));
      expect(reader.backgroundParseCount, 1);
      expect(reader.hasRead, isTrue);
      expect(reader.value, same(reader.document));

      // Sync update superseding active background parse must not fire spurious finally notify.
      int notifications = 0;
      reader.addListener(() => notifications++);
      final String largeB = 'Paragraph B ' * 20;
      final Future<MarkdownDocument> bg = reader.update(largeB);
      await reader.update('Short override');
      final int countAfterSync = notifications;
      await bg;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifications, countAfterSync);
      expect(reader.document.source, 'Short override');

      reader.clear();
      expect(reader.hasRead, isFalse);

      // IsolateSpawnException fallback executes synchronous parse cleanly.
      final MarkdownDocument fallbackDoc = await parseMarkdownWithIsolateRunner(
        const MarkdownEngine(),
        '# Fallback Heading',
        const MarkdownOptions(),
        runIsolate: (MarkdownDocument Function() _) async {
          throw IsolateSpawnException('Simulated spawn block');
        },
      );
      expect(fallbackDoc.blocks.length, 1);
      expect(fallbackDoc.outline.first.text, 'Fallback Heading');
    });

    testWidgets(
      'MarkdownDocumentReader defers notifyListeners safely during widget build phase',
      (WidgetTester tester) async {
        final MarkdownDocumentReader reader = MarkdownDocumentReader();
        addTearDown(reader.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<MarkdownDocument>(
              valueListenable: reader,
              builder: (BuildContext context, MarkdownDocument doc, Widget? _) {
                if (!reader.hasRead) {
                  reader.update('# Deferred Build Read');
                }
                return Text(doc.toPlainText());
              },
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Deferred Build Read'), findsOneWidget);
      },
    );
  });

  group('Hybrid two-sliver streaming tail canvas', () {
    testWidgets(
      'mixed settled MathBlockNode, CodeBlockNode(mermaid), and AlertNode freeze in settled SliverMarkdownDocument while trailing prose streams on MarkdownStreamingCanvasLeaf',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        addTearDown(stream.dispose);

        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 600.0,
                  height: 700.0,
                  child: MarkdownView.streaming(
                    controller: stream,
                    padding: const EdgeInsets.all(16.0),
                  ),
                ),
              ),
            ),
          );

          stream.append(
            r'$$\int_0^1 x^2\,dx = \frac{1}{3}$$'
            '\n\n'
            '```mermaid\n'
            'flowchart LR\n'
            '  A[Alpha] --> B[Beta]\n'
            '```\n\n'
            '> [!NOTE]\n'
            '> Settled alert body.\n\n'
            'Trailing canvas prose ',
          );
          await tester.pumpAndSettle();

          expect(stream.settledPrefixBlockCount, 3);
          expect(find.byType(SliverMarkdownDocument), findsOneWidget);
          expect(find.byType(MarkdownStreamingSliverAdapter), findsOneWidget);
          expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
          expect(find.byType(TexMath), findsOneWidget);
          expect(find.byType(VectorGraphic), findsOneWidget);
          expect(find.text('Note'), findsOneWidget);
          expect(find.text('Settled alert body.'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp('Trailing canvas prose')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          // Capture settled widget and RenderObject instances across rich blocks.
          final Widget settledMathWidget = tester.widget(find.byType(TexMath));
          final RenderObject settledMathRender = tester.renderObject(
            find.byType(TexMath),
          );
          final Widget settledMermaidWidget = tester.widget(
            find.byType(VectorGraphic),
          );
          final RenderObject settledMermaidRender = tester.renderObject(
            find.byType(VectorGraphic),
          );
          final Widget settledAlertWidget = tester.widget(
            find.text('Settled alert body.'),
          );
          final RenderObject settledAlertRender = tester.renderObject(
            find.text('Settled alert body.'),
          );

          // Append tail prose tokens; settled rich prefix must remain untouched.
          for (final String token in <String>[
            'with ',
            'multiple ',
            'incremental ',
            'tokens.',
          ]) {
            stream.append(token);
            await tester.pump();

            expect(find.byType(SliverMarkdownDocument), findsOneWidget);
            expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
            expect(
              identical(tester.widget(find.byType(TexMath)), settledMathWidget),
              isTrue,
            );
            expect(
              identical(
                tester.renderObject(find.byType(TexMath)),
                settledMathRender,
              ),
              isTrue,
            );
            expect(
              identical(
                tester.widget(find.byType(VectorGraphic)),
                settledMermaidWidget,
              ),
              isTrue,
            );
            expect(
              identical(
                tester.renderObject(find.byType(VectorGraphic)),
                settledMermaidRender,
              ),
              isTrue,
            );
            expect(
              identical(
                tester.widget(find.text('Settled alert body.')),
                settledAlertWidget,
              ),
              isTrue,
            );
            expect(
              identical(
                tester.renderObject(find.text('Settled alert body.')),
                settledAlertRender,
              ),
              isTrue,
            );
          }

          expect(
            find.bySemanticsLabel(
              RegExp('Trailing canvas prose with multiple incremental tokens.'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'per-block delegate compatibility keeps prose tail on MarkdownStreamingCanvasLeaf even when custom math/diagram/code delegates exist, falling back only when trailing block invokes them',
      (WidgetTester tester) async {
        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        addTearDown(stream.dispose);

        int mathBuilds = 0;
        int diagramBuilds = 0;
        int codeBuilds = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 600.0,
                child: MarkdownView.streaming(
                  controller: stream,
                  delegates: MarkdownBuilderDelegates(
                    mathBlockBuilder: (BuildContext _, MathBlockNode node) {
                      mathBuilds++;
                      return Text('CUSTOM_MATH:${node.latex.trim()}');
                    },
                    diagramBuilder: (BuildContext _, CodeBlockNode node) {
                      if (node.language != 'mermaid') {
                        return null;
                      }
                      diagramBuilds++;
                      return Text('CUSTOM_DIAGRAM:${node.literal.trim()}');
                    },
                    codeBlockBuilder: (BuildContext _, CodeBlockNode node) {
                      codeBuilds++;
                      return Text('CUSTOM_CODE:${node.literal.trim()}');
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        stream.append(
          r'$$\alpha + \beta$$'
          '\n\n'
          '```mermaid\nflowchart TD\n  X --> Y\n```\n\n'
          'Trailing plain ',
        );
        await tester.pump();

        expect(stream.settledPrefixBlockCount, 2);
        expect(mathBuilds, 1);
        expect(diagramBuilds, 1);
        expect(codeBuilds, 0);
        expect(find.text(r'CUSTOM_MATH:\alpha + \beta'), findsOneWidget);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);

        // Appending more plain prose keeps tail on canvas without rebuilding custom delegates.
        stream.append('prose words.');
        await tester.pump();
        expect(mathBuilds, 1);
        expect(diagramBuilds, 1);
        expect(codeBuilds, 0);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);

        // Trailing code block invokes codeBlockBuilder -> tail switches to widget tail.
        stream.append('\n\n```dart\nfinal int v = 42;');
        await tester.pump();
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsNothing);
        expect(find.byType(SliverMarkdownDocument), findsNWidgets(2));
        expect(find.text('CUSTOM_CODE:final int v = 42;'), findsOneWidget);
        expect(mathBuilds, 1);
        expect(diagramBuilds, 1);

        // Once the code block settles behind subsequent prose, tail returns to canvas.
        stream.append('\n```\n\nBack to prose ');
        await tester.pump();
        expect(stream.settledPrefixBlockCount, 4);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
        expect(mathBuilds, 1);
        expect(diagramBuilds, 1);
        expect(codeBuilds, 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'full multi-phase transition (full canvas -> widget tail -> hybrid settled widgets + canvas tail -> finish -> reset) maintains split padding and zero assertions',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        addTearDown(stream.dispose);

        const EdgeInsets outerPadding = EdgeInsets.fromLTRB(
          12.0,
          16.0,
          14.0,
          20.0,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 600.0,
                child: MarkdownView.streaming(
                  controller: stream,
                  padding: outerPadding,
                ),
              ),
            ),
          ),
        );

        // Phase 1: Pure prose (>= 2 blocks) -> full-document streaming canvas.
        stream.append('Introductory paragraph.\n\nActive prose ');
        await tester.pump();
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
        expect(find.byType(SliverMarkdownDocument), findsNothing);
        expect(tester.takeException(), isNull);

        // Phase 2: Trailing block becomes live display math -> hybrid widget tail.
        stream.append('\n\n\$\$\n\\sum_{i=1}^n i');
        await tester.pump();
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsNothing);
        expect(find.byType(SliverMarkdownDocument), findsNWidgets(2));
        expect(tester.takeException(), isNull);

        // Phase 3: Close display math and stream subsequent prose -> hybrid canvas tail.
        stream.append('\n\$\$\n\nResumed prose ');
        await tester.pump();
        expect(stream.settledPrefixBlockCount, 3);
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);

        // Check split outer padding & trailingBlockSpacing between the two slivers.
        final SliverMarkdownDocument settledSliver = tester
            .widget<SliverMarkdownDocument>(
              find.byType(SliverMarkdownDocument),
            );
        expect(
          settledSliver.padding,
          const EdgeInsets.fromLTRB(12.0, 16.0, 14.0, 0.0),
        );
        expect(settledSliver.trailingBlockSpacing, isTrue);

        final Rect settledMathRect = tester.getRect(find.byType(TexMath));
        final Rect tailCanvasRect = tester.getRect(
          find.byType(MarkdownStreamingCanvasLeaf),
        );
        expect(
          tailCanvasRect.top,
          greaterThanOrEqualTo(settledMathRect.bottom),
        );
        expect(tester.takeException(), isNull);

        // Phase 4: Finish stream -> switches cleanly to unified SliverMarkdownDocument.
        stream.finish();
        await tester.pump();
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsNothing);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.text('Resumed prose'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Phase 5: Reset stream cleanly -> empty without errors, then restart pure prose.
        stream.reset();
        await tester.pump();
        expect(find.byType(TexMath), findsNothing);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsNothing);
        expect(tester.takeException(), isNull);

        stream.append('Restarted first.\n\nRestarted second ');
        await tester.pump();
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
        expect(find.byType(SliverMarkdownDocument), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cross-sliver SelectionArea drag selection and SelectAll copy work across settled rich blocks and hybrid canvas tail',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        String? copiedClipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                copiedClipboard = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        final FocusNode focusNode = FocusNode();
        addTearDown(stream.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 600.0,
                child: MarkdownView.streaming(
                  controller: stream,
                  focusNode: focusNode,
                  padding: const EdgeInsets.all(16.0),
                ),
              ),
            ),
          ),
        );

        stream.append(
          '> [!NOTE]\n'
          '> Alert settled text.\n\n'
          r'$$E = mc^2$$'
          '\n\n'
          'Tail canvas sentence alpha beta ',
        );
        await tester.pump();

        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
        expect(find.byType(TexMath), findsOneWidget);

        // Drag mouse selection from settled alert text down across trailing canvas leaf.
        final Offset alertLeft =
            tester.getRect(find.text('Alert settled text.')).centerLeft +
            const Offset(2.0, 0.0);
        final Rect tailRect = tester.getRect(
          find.byType(MarkdownStreamingCanvasLeaf),
        );
        final Offset tailEnd = Offset(tailRect.right - 8.0, tailRect.center.dy);

        final TestGesture drag = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(drag.removePointer);
        await drag.down(alertLeft);
        await tester.pump();
        await drag.moveTo(tailEnd);
        await tester.pump();
        await drag.up();
        await tester.pump();

        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();

        expect(copiedClipboard, isNotNull);
        expect(copiedClipboard, contains('Alert settled text.'));
        expect(copiedClipboard, contains('Tail canvas sentence alpha beta'));

        // Now invoke SelectAll, stream another token while SelectAll is active, and copy.
        copiedClipboard = null;
        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();

        stream.append('gamma.');
        await tester.pump();

        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();

        expect(copiedClipboard, stream.document.toPlainText());
        expect(copiedClipboard, contains('Alert settled text.'));
        expect(
          copiedClipboard,
          contains('Tail canvas sentence alpha beta gamma.'),
        );
      },
    );

    testWidgets(
      'showFrontmatter: false handles leading FrontmatterNode cleanly without off-by-1 split or empty settled sliver',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        addTearDown(stream.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 600.0,
                child: MarkdownView.streaming(
                  controller: stream,
                  showFrontmatter: false,
                  padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
                ),
              ),
            ),
          ),
        );

        // Case A1: Frontmatter is the only settled block and trailing block is canvas-eligible.
        stream.append(
          '---\n'
          'title: Secret Frontmatter\n'
          '---\n\n'
          'First visible paragraph ',
        );
        await tester.pump();

        expect(stream.settledPrefixBlockCount, 1);
        expect(find.textContaining('Secret Frontmatter'), findsNothing);
        // Must NOT mount an empty SliverMarkdownDocument stealing top padding.
        expect(find.byType(SliverMarkdownDocument), findsNothing);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
        final double heightWithTopPadding = tester
            .getRect(find.byType(MarkdownStreamingCanvasLeaf))
            .height;
        expect(tester.takeException(), isNull);

        // Case B: Leading frontmatter + settled paragraph + settled MathBlockNode + streaming prose tail.
        stream.append('\n\n\$\$x^2 + y^2 = z^2\$\$\n\nTrailing hybrid prose ');
        await tester.pump();

        expect(stream.settledPrefixBlockCount, 3);
        expect(find.textContaining('Secret Frontmatter'), findsNothing);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.text('First visible paragraph'), findsOneWidget);
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
        expect(find.text('Trailing hybrid prose '), findsNothing);
        expect(tester.takeException(), isNull);

        // Case B2: Leading frontmatter (filtered) + single settled MathBlockNode + prose tail (settledCount == 2).
        final StreamingMarkdownController frontmatterPlusMathStream =
            StreamingMarkdownController(
              options: const MarkdownOptions.extended(),
            );
        addTearDown(frontmatterPlusMathStream.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 600.0,
                child: MarkdownView.streaming(
                  controller: frontmatterPlusMathStream,
                  showFrontmatter: false,
                  padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
                ),
              ),
            ),
          ),
        );
        frontmatterPlusMathStream.append(
          '---\n'
          'title: Also Hidden\n'
          '---\n\n'
          '\$\$a^2 + b^2 = c^2\$\$\n\n'
          'Only trailing prose ',
        );
        await tester.pump();

        expect(frontmatterPlusMathStream.settledPrefixBlockCount, 2);
        expect(find.textContaining('Also Hidden'), findsNothing);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
        expect(find.text('Only trailing prose '), findsNothing);
        expect(tester.takeException(), isNull);

        // Also verify frontmatter-only settled + rich unsupported tail avoids empty top sliver.
        final StreamingMarkdownController richTailStream =
            StreamingMarkdownController(
              options: const MarkdownOptions.extended(),
            );
        addTearDown(richTailStream.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 600.0,
                child: MarkdownView.streaming(
                  controller: richTailStream,
                  showFrontmatter: false,
                  padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
                ),
              ),
            ),
          ),
        );

        richTailStream.append(
          '---\n'
          'title: Hidden Only\n'
          '---\n\n'
          '> [!NOTE]\n'
          '> Trailing alert body.',
        );
        await tester.pump();

        expect(richTailStream.settledPrefixBlockCount, 1);
        expect(find.textContaining('Hidden Only'), findsNothing);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.text('Trailing alert body.'), findsOneWidget);
        expect(
          tester
              .widget<SliverMarkdownDocument>(
                find.byType(SliverMarkdownDocument),
              )
              .padding,
          const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
        );
        expect(tester.takeException(), isNull);

        // Compare top-24 vs top-0 padding on the same hidden-frontmatter stream.
        final StreamingMarkdownController zeroTopStream =
            StreamingMarkdownController(
              options: const MarkdownOptions.extended(),
            );
        addTearDown(zeroTopStream.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 600.0,
                child: MarkdownView.streaming(
                  controller: zeroTopStream,
                  showFrontmatter: false,
                  padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
                ),
              ),
            ),
          ),
        );
        zeroTopStream.append(
          '---\n'
          'title: Secret Frontmatter\n'
          '---\n\n'
          'First visible paragraph ',
        );
        await tester.pump();
        final double heightWithoutTopPadding = tester
            .getRect(find.byType(MarkdownStreamingCanvasLeaf))
            .height;
        expect(heightWithTopPadding - heightWithoutTopPadding, 24.0);
      },
    );

    testWidgets(
      'MarkdownController preserves prefix memoization and block/anchor registrations across hybrid widget-tail transitions',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        final MarkdownController viewController = MarkdownController();
        addTearDown(stream.dispose);
        addTearDown(viewController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 320.0,
                child: MarkdownView.streaming(
                  controller: stream,
                  markdownController: viewController,
                ),
              ),
            ),
          ),
        );

        stream.append(
          '# Intro {#intro}\n\n'
          '```mermaid\n'
          'flowchart LR\n'
          '  A[One] --> B[Two]\n'
          '```\n\n'
          'Active tail ',
        );
        await tester.pump();

        expect(stream.settledPrefixBlockCount, 2);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsNothing);
        expect(find.byType(SliverMarkdownDocument), findsNWidgets(2));
        expect(find.byType(VectorGraphic), findsOneWidget);

        final Widget settledHeadingWidget = tester.widget(find.text('Intro'));
        final RenderObject settledMermaidRender = tester.renderObject(
          find.byType(VectorGraphic),
        );

        // Append tail content including multiple filler paragraphs and a tail heading anchor.
        final StringBuffer tailAppend = StringBuffer('more tokens.\n\n');
        for (int i = 0; i < 12; i++) {
          tailAppend.writeln('Filler tail paragraph $i for scrollability.\n');
        }
        tailAppend.writeln('## Tail Section {#tail-sec}\n\nTail bottom line.');
        stream.append(tailAppend.toString());
        await tester.pump();

        expect(
          identical(tester.widget(find.text('Intro')), settledHeadingWidget),
          isTrue,
        );
        expect(
          identical(
            tester.renderObject(find.byType(VectorGraphic)),
            settledMermaidRender,
          ),
          isTrue,
        );

        stream.finish();
        await tester.pump();

        final Future<bool> tailAnchorFuture = viewController.scrollToAnchor(
          'tail-sec',
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        expect(await tailAnchorFuture, isTrue);
        expect(find.text('Tail Section'), findsOneWidget);

        final Future<bool> introAnchorFuture = viewController.scrollToAnchor(
          'intro',
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        expect(await introAnchorFuture, isTrue);
        expect(find.text('Intro'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'mid-stream reference/footnote definitions shrinking settledPrefixBlockCount and replaceText() on settled blocks refresh _StreamingBlockSlot without stale text',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.extended(),
        );
        addTearDown(stream.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 600.0,
                child: MarkdownView.streaming(
                  controller: stream,
                  delegates: MarkdownBuilderDelegates(
                    onTapLink: (String _, String? _) {},
                  ),
                ),
              ),
            ),
          ),
        );

        // Phase 1: settled paragraph with unresolved [docs] & [^1] + settled math + canvas tail.
        stream.append(
          'See [docs] and note[^1].\n\n'
          r'$$\alpha = 1$$'
          '\n\n'
          'Active tail ',
        );
        await tester.pump();

        expect(stream.settledPrefixBlockCount, 2);
        expect(find.byType(SliverMarkdownDocument), findsOneWidget);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsOneWidget);
        expect(find.text('See [docs] and note[^1].'), findsOneWidget);
        final TexMath mathBefore = tester.widget<TexMath>(find.byType(TexMath));

        // replaceText() keeping settledPrefixBlockCount == 2 (hybridCanvasTail) must refresh both slots.
        stream.replaceText(
          'See [docs] and updated note[^1].\n\n'
          r'$$\beta = 2$$'
          '\n\n'
          'Active tail ',
        );
        await tester.pump();

        expect(stream.settledPrefixBlockCount, 2);
        expect(find.text('See [docs] and updated note[^1].'), findsOneWidget);
        expect(find.text('See [docs] and note[^1].'), findsNothing);
        final TexMath mathAfterCanvasReplace = tester.widget<TexMath>(
          find.byType(TexMath),
        );
        expect(
          identical(mathAfterCanvasReplace.displayList, mathBefore.displayList),
          isFalse,
        );

        // Transition to hybridWidgetTail via inline math in active tail, then replaceText() settled blocks again.
        stream.append(r'with $z$.');
        await tester.pump();
        expect(stream.settledPrefixBlockCount, 2);
        expect(find.byType(MarkdownStreamingCanvasLeaf), findsNothing);
        expect(find.byType(SliverMarkdownDocument), findsNWidgets(2));

        stream.replaceText(
          'See [docs] now[^1].\n\n'
          r'$$\gamma = 3$$'
          '\n\n'
          r'Active tail with $z$.',
        );
        await tester.pump();

        expect(stream.settledPrefixBlockCount, 2);
        expect(find.text('See [docs] now[^1].'), findsOneWidget);
        final TexMath mathAfterWidgetReplace = tester
            .widgetList<TexMath>(find.byType(TexMath))
            .first;
        expect(
          identical(
            mathAfterWidgetReplace.displayList,
            mathAfterCanvasReplace.displayList,
          ),
          isFalse,
        );

        // Mid-stream reference + footnote definitions arrive -> settledPrefixBlockCount drops to 0!
        // Stream stays active and block-0 must immediately resolve its link & footnote marker.
        stream.append(
          '\n\n[docs]: https://example.com/docs\n[^1]: Resolved footnote body.',
        );
        await tester.pump();

        expect(stream.isFinished, isFalse);
        expect(stream.settledPrefixBlockCount, 0);
        expect(find.text('See [docs] now[^1].'), findsNothing);
        expect(find.textContaining('See docs now'), findsOneWidget);
        expect(find.textContaining('Resolved footnote body.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'swapping StreamingMarkdownController or toggling showFrontmatter clears stale SelectAll state cleanly',
      (WidgetTester tester) async {
        String? copiedClipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                copiedClipboard = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final StreamingMarkdownController firstStream =
            StreamingMarkdownController(
              options: const MarkdownOptions.extended(),
            );
        final StreamingMarkdownController secondStream =
            StreamingMarkdownController(
              options: const MarkdownOptions.extended(),
            );
        final FocusNode focusNode = FocusNode();
        addTearDown(firstStream.dispose);
        addTearDown(secondStream.dispose);
        addTearDown(focusNode.dispose);

        firstStream.append(
          '---\ntitle: Front\n---\n\nFirst stream body.\n\nSecond paragraph.',
        );
        secondStream.append('Second stream replacement.');

        StreamingMarkdownController activeStream = firstStream;
        bool showFrontmatter = true;
        late StateSetter rebuild;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuild = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 600.0,
                    height: 400.0,
                    child: MarkdownView.streaming(
                      controller: activeStream,
                      focusNode: focusNode,
                      showFrontmatter: showFrontmatter,
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        // Trigger SelectAll on firstStream with showFrontmatter: true.
        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(copiedClipboard, contains('First stream body.'));

        // Toggle showFrontmatter -> stale SelectAll state must clear cleanly without crash.
        rebuild(() => showFrontmatter = false);
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Re-select all, then swap to secondStream -> stale SelectAll cleared cleanly.
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        rebuild(() => activeStream = secondStream);
        await tester.pump();

        copiedClipboard = null;
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(
          copiedClipboard == null ||
              !copiedClipboard!.contains('First stream body.'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'document switching with nested SingleChildScrollView and Text.rich WidgetSpan avoids ConcurrentModificationError with and without active selection',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        String? copiedClipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                copiedClipboard = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        const String docA =
            '# Preset A\n\n'
            'Inline math \$x^2 + y^2\$ in rich text.\n\n'
            '```mermaid\n'
            'flowchart LR\n'
            '  A[Alpha] --> B[Bravo] --> C[Charlie] --> D[Delta] --> E[Echo]\n'
            '```\n\n'
            '| Col 1 | Col 2 | Col 3 |\n'
            '| :--- | :--- | :--- |\n'
            '| Wide cell \$a^2\$ | Second cell alpha | Third cell beta |\n\n'
            '> [!NOTE]\n'
            '> Alert inside Preset A.';

        const String docB =
            '# Preset B\n\n'
            'Switched paragraph \$z^3\$ without crash.\n\n'
            '```dart\nfinal int cleanSwitch = 1;\n```';

        final FocusNode focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        String currentDoc = docA;
        late StateSetter rebuild;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuild = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 280.0,
                    height: 500.0,
                    child: MarkdownView(
                      currentDoc,
                      options: const MarkdownOptions.extended(),
                      focusNode: focusNode,
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        expect(find.byType(SingleChildScrollView), findsWidgets);
        expect(find.text('Preset A'), findsOneWidget);

        // 1. Switch without any active selection.
        rebuild(() => currentDoc = docB);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Preset B'), findsOneWidget);

        // Switch back to docA with nested table WidgetSpans.
        rebuild(() => currentDoc = docA);
        await tester.pump();
        expect(tester.takeException(), isNull);

        // 2. Activate SelectAll across nested SingleChildScrollView + Text.rich, then switch.
        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        rebuild(() => currentDoc = docB);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Preset B'), findsOneWidget);

        copiedClipboard = null;
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(
          copiedClipboard == null || !copiedClipboard!.contains('Preset A'),
          isTrue,
        );

        // 3. Mouse drag selection over docA paragraph with WidgetSpan, then switch to docB.
        rebuild(() => currentDoc = docA);
        await tester.pump();
        final Offset start =
            tester.getRect(find.text('Preset A')).centerLeft +
            const Offset(2.0, 0.0);
        final Offset end =
            tester.getRect(find.text('Preset A')).centerRight -
            const Offset(2.0, 0.0);
        final TestGesture drag = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(drag.removePointer);
        await drag.down(start);
        await tester.pump();
        await drag.moveTo(end);
        await tester.pump();
        await drag.up();
        await tester.pump();

        rebuild(() => currentDoc = docB);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Sliver leading scroll-offset batching and extent caching', () {
    RenderSliverMultiBoxAdaptor findMarkdownSliver(WidgetTester tester) {
      return tester.allRenderObjects
          .whereType<RenderSliverMultiBoxAdaptor>()
          .first;
    }

    void expectMonotonicChildLayoutOffsets(
      RenderSliverMultiBoxAdaptor sliver, {
      bool requireFirstIndexZero = false,
    }) {
      RenderBox? child = sliver.firstChild;
      expect(child, isNotNull);
      final SliverMultiBoxAdaptorParentData firstPd =
          child!.parentData! as SliverMultiBoxAdaptorParentData;
      if (requireFirstIndexZero) {
        expect(firstPd.index, 0);
        expect(firstPd.layoutOffset, 0.0);
      }
      double prevOffset = -1.0;
      int? prevIndex;
      while (child != null) {
        final SliverMultiBoxAdaptorParentData pd =
            child.parentData! as SliverMultiBoxAdaptorParentData;
        expect(pd.layoutOffset, isNotNull);
        expect(pd.layoutOffset!.isNaN, isFalse);
        expect(pd.layoutOffset!.isFinite, isTrue);
        expect(pd.layoutOffset!, greaterThanOrEqualTo(prevOffset));
        if (prevIndex != null) {
          expect(pd.index, prevIndex + 1);
        }
        prevIndex = pd.index;
        prevOffset = pd.layoutOffset!;
        child = sliver.childAfter(child);
      }
    }

    testWidgets(
      '500-section document survives deep scroll, width narrowing, and negative overscroll (-503.977, -2500, -5000) without exceeding RenderViewport cycles',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final StringBuffer buf = StringBuffer('# 500-Section Stress\n\n');
        for (int i = 1; i <= 500; i++) {
          buf
            ..writeln('## Section $i {#section-$i}')
            ..writeln()
            ..writeln(
              'Paragraph $i exercises virtualized sliver layout with **bold**, '
              '_italic_, `block-$i`, inline math \$x_{$i} = ${i * 2}\$, and '
              'additional prose tokens that wrap onto many tall lines when the '
              'viewport narrows sharply.',
            )
            ..writeln();
        }
        final String stressDoc = buf.toString();
        final ScrollController scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        double viewportWidth = 1100.0;
        double viewportHeight = 700.0;
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: viewportWidth,
                    height: viewportHeight,
                    child: MarkdownView(
                      stressDoc,
                      options: const MarkdownOptions.extended(),
                      padding: const EdgeInsets.all(20.0),
                      physics: const BouncingScrollPhysics(),
                      cacheExtent: 2000.0,
                      scrollController: scrollController,
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        // Jump deep so blocks 0..15 are collected from the leading edge.
        scrollController.jumpTo(8500.0);
        await tester.pump();
        expect(find.text('500-Section Stress'), findsNothing);

        // Narrow width & shrink viewport height to 300px so blocks 0..15 grow
        // much taller than dead-reckoned layoutOffsets while cacheExtent stays 2000.
        rebuildHost(() {
          viewportWidth = 260.0;
          viewportHeight = 300.0;
        });
        await tester.pump();

        // Drive extreme negative overscroll directly from deep offset so
        // RenderSliverList batches leading children in bounded cycles without
        // exceeding RenderViewport.maxLayoutCycles.
        for (final double overscroll in <double>[-503.977, -2500.0, -5000.0]) {
          scrollController.jumpTo(9500.0);
          await tester.pump();
          scrollController.jumpTo(overscroll);
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectMonotonicChildLayoutOffsets(findMarkdownSliver(tester));
        }

        // Now position near the top cache zone (blocks 0..15 taller than
        // dead-reckoned offsets) and drive negative overscroll + settle back
        // to index 0 with monotonic layoutOffsets.
        for (final double overscroll in <double>[-503.977, -2500.0, -5000.0]) {
          scrollController.jumpTo(9500.0);
          await tester.pump();
          scrollController.jumpTo(1200.0);
          await tester.pump();
          scrollController.jumpTo(overscroll);
          await tester.pump();
          expect(tester.takeException(), isNull);
          // Finish settling any residual positive correction back to block 0.
          while (scrollController.position.pixels > 0.0) {
            scrollController.jumpTo(0.0);
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final RenderSliverMultiBoxAdaptor sliver = findMarkdownSliver(tester);
          expectMonotonicChildLayoutOffsets(
            sliver,
            requireFirstIndexZero: true,
          );
          expect(find.text('500-Section Stress'), findsOneWidget);
        }

        // Real upward ballistic fling from near the top cache zone past 0.
        scrollController.jumpTo(1400.0);
        await tester.pump();
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0.0, 2600.0),
          7500.0,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectMonotonicChildLayoutOffsets(
          findMarkdownSliver(tester),
          requireFirstIndexZero: true,
        );
      },
    );

    testWidgets(
      'short blocks (<20px tall) in top cache zone converge without RenderViewport cycle errors when scrolling back without negative overscroll',
      (WidgetTester tester) async {
        final StringBuffer buf = StringBuffer();
        for (int i = 0; i < 120; i++) {
          buf.writeln('Row $i\n');
        }
        final ScrollController scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 300.0,
                child: MarkdownTheme(
                  data: const MarkdownThemeData.light(blockSpacing: 2.0),
                  child: MarkdownView(
                    buf.toString(),
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    cacheExtent: 250.0,
                    scrollController: scrollController,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Scroll deep so >25 short (<20px) blocks above the cache zone are collected.
        scrollController.jumpTo(1400.0);
        await tester.pump();
        final RenderSliverMultiBoxAdaptor sliverDeep = findMarkdownSliver(
          tester,
        );
        final SliverMultiBoxAdaptorParentData deepFirst =
            sliverDeep.firstChild!.parentData!
                as SliverMultiBoxAdaptorParentData;
        expect(deepFirst.index, greaterThan(15));

        // Scroll back near top and directly to 0.0 without negative overscroll.
        scrollController.jumpTo(5.0);
        await tester.pump();
        expect(tester.takeException(), isNull);
        scrollController.jumpTo(0.0);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectMonotonicChildLayoutOffsets(
          findMarkdownSliver(tester),
          requireFirstIndexZero: true,
        );
        expect(find.text('Row 0'), findsOneWidget);
      },
    );

    testWidgets(
      'zero-height leading blocks (HTML comments + blockSpacing: 0.0) prepend at scrollOffset == 0.0 without scrollOffsetCorrection == 0.0 failure',
      (WidgetTester tester) async {
        // Case A: all leading zero-height blocks plus positive body blocks.
        final StringBuffer buf = StringBuffer();
        for (int i = 0; i < 20; i++) {
          buf.writeln('<!-- leading zero block $i -->\n');
        }
        for (int i = 0; i < 60; i++) {
          buf.writeln('Visible paragraph #$i after zero-height comments.\n');
        }

        final ScrollController scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 300.0,
                child: MarkdownTheme(
                  data: const MarkdownThemeData.light(blockSpacing: 0.0),
                  child: MarkdownView(
                    buf.toString(),
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    cacheExtent: 0.0,
                    scrollController: scrollController,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        scrollController.jumpTo(1200.0);
        await tester.pump();
        final RenderSliverMultiBoxAdaptor deepSliver = findMarkdownSliver(
          tester,
        );
        expect(
          (deepSliver.firstChild!.parentData!
                  as SliverMultiBoxAdaptorParentData)
              .index,
          greaterThan(20),
        );

        scrollController.jumpTo(0.0);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectMonotonicChildLayoutOffsets(
          findMarkdownSliver(tester),
          requireFirstIndexZero: true,
        );
        expect(
          find.text('Visible paragraph #0 after zero-height comments.'),
          findsOneWidget,
        );

        // Case B: prepending strictly 0-height leading blocks when firstChild is already at layoutOffset 0.0.
        String toggledSource =
            'First block\n\nSecond block\n\nThird block\n\nTail block';
        late StateSetter rebuild;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuild = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 600.0,
                    height: 300.0,
                    child: MarkdownTheme(
                      data: const MarkdownThemeData.light(blockSpacing: 0.0),
                      child: MarkdownView(
                        toggledSource,
                        padding: EdgeInsets.zero,
                        physics: const ClampingScrollPhysics(),
                        cacheExtent: 0.0,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        rebuild(() {
          toggledSource =
              '<!-- z0 -->\n\n<!-- z1 -->\n\n<!-- z2 -->\n\n'
              'First block\n\nSecond block\n\nThird block\n\nTail block';
        });
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectMonotonicChildLayoutOffsets(
          findMarkdownSliver(tester),
          requireFirstIndexZero: true,
        );
      },
    );

    testWidgets(
      'non-first SliverMarkdownDocument after 5000px leading sliver and shrinkWrap: true MarkdownView produce zero exceptions or NaN metrics',
      (WidgetTester tester) async {
        final StringBuffer buf = StringBuffer();
        for (int i = 0; i < 80; i++) {
          buf.writeln('Sliver body block #$i with **rich** content.\n');
        }
        final MarkdownDocument doc = const MarkdownEngine(
          defaultOptions: MarkdownOptions.gfm(),
        ).parse(buf.toString());
        final ScrollController scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 400.0,
                child: CustomScrollView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  slivers: <Widget>[
                    const SliverToBoxAdapter(child: SizedBox(height: 5000.0)),
                    SliverMarkdownDocument(document: doc),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Scroll deep into the second sliver so its leading blocks collect.
        scrollController.jumpTo(7600.0);
        await tester.pump();
        expect(find.textContaining('Sliver body block #0'), findsNothing);

        // Cross back above the leading 5000px boundary and into negative overscroll.
        scrollController.jumpTo(4900.0);
        await tester.pump();
        expect(tester.takeException(), isNull);
        scrollController.jumpTo(-500.0);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Verify shrinkWrap: true + BouncingScrollPhysics produces zero NaN geometry.
        final ScrollController shrinkController = ScrollController();
        addTearDown(shrinkController.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500.0,
                height: 350.0,
                child: MarkdownView(
                  buf.toString(),
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  scrollController: shrinkController,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        shrinkController.jumpTo(600.0);
        await tester.pump();
        shrinkController.jumpTo(-300.0);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(shrinkController.position.maxScrollExtent.isNaN, isFalse);
      },
    );

    testWidgets(
      'visual continuity: visible block screen-Y stays within 0.5px of scroll delta across batched leading correction',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200.0, 900.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final StringBuffer buf = StringBuffer();
        for (int i = 0; i < 120; i++) {
          buf.writeln(
            'Paragraph $i carries multiple descriptive words so narrowing '
            'from desktop width to mobile width increases line wrapping height '
            'substantially.',
          );
          buf.writeln();
        }
        final ScrollController scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        double width = 1000.0;
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: width,
                    height: 800.0,
                    child: MarkdownView(
                      buf.toString(),
                      padding: const EdgeInsets.all(20.0),
                      physics: const BouncingScrollPhysics(),
                      cacheExtent: 0.0,
                      scrollController: scrollController,
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        // Scroll past top blocks so blocks 0..k are unmounted at wide width.
        scrollController.jumpTo(320.0);
        await tester.pump();

        // Narrow viewport while staying scrolled at 320.0 (unmounted leading
        // blocks now have much larger wrapped height than dead-reckoned offset).
        rebuildHost(() => width = 280.0);
        await tester.pump();

        // Pick a visible paragraph near the top of the 800px viewport so after
        // a 360px upward scroll step it remains visible inside the viewport.
        String? anchorPrefix;
        double? topBefore;
        for (int i = 0; i < 120; i++) {
          final String needle = 'Paragraph $i carries';
          final Finder f = find.textContaining(needle);
          if (f.evaluate().isNotEmpty) {
            final double dy = tester.getTopLeft(f.first).dy;
            if (dy >= 0.0 && dy <= 300.0) {
              anchorPrefix = needle;
              topBefore = dy;
              break;
            }
          }
        }
        expect(anchorPrefix, isNotNull);
        expect(topBefore, isNotNull);

        // Scroll upward into negative overscroll/leading correction region so
        // RenderSliverList batches all taller leading blocks in one pass while
        // the anchor paragraph remains inside the 800px viewport.
        const double targetPixels = -40.0;
        final double expectedScreenDelta =
            scrollController.position.pixels - targetPixels;
        scrollController.jumpTo(targetPixels);
        await tester.pump();
        expect(tester.takeException(), isNull);

        final Finder anchorFinder = find.textContaining(anchorPrefix!);
        expect(anchorFinder, findsOneWidget);
        final double topAfter = tester.getTopLeft(anchorFinder).dy;
        expect(
          (topAfter - topBefore! - expectedScreenDelta).abs(),
          lessThan(0.5),
        );
      },
    );
  });

  group('Keep-alive selection safety across offscreen mutations', () {
    testWidgets(
      'Studio repro: inline math, links, kbd, sub/sup, footnotes, and WidgetSpans survive SelectAll + drag, offscreen _keepAliveBucket scroll (>3000px), Light/Dark toggle, and source updates',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final StringBuffer docBuf = StringBuffer(
          '# Studio Selection Repro\n\n'
          'Top rich line with \$x_i = 2i\$, [Dart](https://dart.dev), '
          '<kbd>Cmd</kbd>, H~2~O, 2^3^, and note[^n1].\n\n'
          '```dart\nfinal int code = 42;\n```\n\n',
        );
        for (int i = 1; i <= 120; i++) {
          docBuf
            ..writeln('## Section $i')
            ..writeln()
            ..writeln(
              'Scrollable body $i with inline math \$y_$i = $i\$ and '
              '<kbd>K$i</kbd> plus [Link $i](https://example.com/$i).',
            )
            ..writeln();
        }
        docBuf.writeln('[^n1]: Footnote detail text.');

        String currentSource = docBuf.toString();
        bool isDark = false;
        final ScrollController scrollController = ScrollController();
        final FocusNode focusNode = FocusNode();
        addTearDown(scrollController.dispose);
        addTearDown(focusNode.dispose);
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 800.0,
                    height: 500.0,
                    child: MarkdownTheme(
                      data: isDark
                          ? const MarkdownThemeData.dark()
                          : const MarkdownThemeData.light(),
                      child: MarkdownView(
                        currentSource,
                        options: const MarkdownOptions.extended(),
                        scrollController: scrollController,
                        focusNode: focusNode,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        // 1. Pointer drag selection on top rich line -> scroll >3000px into
        // _keepAliveBucket -> toggle theme & update source -> scroll back.
        final Finder topPara = find.textContaining('Top rich line');
        expect(topPara, findsOneWidget);
        final Rect topRect = tester.getRect(topPara);
        final TestGesture drag = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(drag.removePointer);
        await drag.down(topRect.centerLeft + const Offset(4.0, 0.0));
        await tester.pump();
        await drag.moveTo(topRect.centerRight - const Offset(4.0, 0.0));
        await tester.pump();
        await drag.up();
        await tester.pump();
        expect(tester.takeException(), isNull);

        scrollController.jumpTo(3600.0);
        await tester.pump();
        rebuildHost(() => isDark = true);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);

        rebuildHost(() => isDark = false);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);

        scrollController.jumpTo(0.0);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);

        // 2. SelectAll -> scroll >3000px into _keepAliveBucket -> toggle theme
        // Light<->Dark and update source across multiple frames.
        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        scrollController.jumpTo(3800.0);
        await tester.pump();
        rebuildHost(() => isDark = true);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);

        rebuildHost(() {
          isDark = false;
          currentSource = currentSource.replaceFirst(
            'Top rich line with',
            'Updated rich line with',
          );
        });
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);

        scrollController.jumpTo(0.0);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Updated rich line'), findsOneWidget);
      },
    );

    testWidgets(
      'copy order after deferred reorder preserves exact reading order for kept-alive WidgetSpan paragraphs',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        String? copiedClipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                copiedClipboard = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final StringBuffer docBuf = StringBuffer(
          'before \$x^2\$ after\n\n'
          'before <kbd>K</kbd> after\n\n',
        );
        for (int i = 0; i < 120; i++) {
          docBuf.writeln(
            'Spacer paragraph #$i pushing kept-alive blocks offscreen.\n',
          );
        }

        double viewportWidth = 600.0;
        final ScrollController scrollController = ScrollController();
        final FocusNode focusNode = FocusNode();
        addTearDown(scrollController.dispose);
        addTearDown(focusNode.dispose);
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: viewportWidth,
                    height: 360.0,
                    child: MarkdownView(
                      docBuf.toString(),
                      options: const MarkdownOptions.extended(),
                      scrollController: scrollController,
                      focusNode: focusNode,
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        // Select across both "before $x^2$ after" and "before <kbd>K</kbd> after".
        final Finder firstRich = find.byWidgetPredicate(
          (Widget w) =>
              w is MarkdownRichText &&
              w.textSpan != null &&
              w.textSpan!.toPlainText().contains('before') &&
              w.textSpan!.toPlainText().contains('after'),
        );
        expect(firstRich, findsNWidgets(2));
        final Rect firstRect = tester.getRect(firstRich.first);
        final Rect secondRect = tester.getRect(firstRich.at(1));
        final TestGesture drag = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(drag.removePointer);
        await drag.down(firstRect.centerLeft + const Offset(2.0, 0.0));
        await tester.pump();
        await drag.moveTo(secondRect.centerRight - const Offset(2.0, 0.0));
        await tester.pump();
        await drag.up();
        await tester.pump();

        // Capture kept-alive RenderParagraph objects for the selected WidgetSpan
        // paragraphs while still mounted.
        final List<RenderParagraph> keptParagraphs = tester
            .renderObjectList<RenderParagraph>(
              find.byWidgetPredicate(
                (Widget w) =>
                    w is RichText && w.text.toPlainText().contains('before'),
              ),
            )
            .toList(growable: false);
        expect(keptParagraphs, isNotEmpty);

        // Scroll offscreen (>3000px into _keepAliveBucket), dirty the kept-alive
        // paragraphs via width change + explicit markNeedsLayout while offscreen.
        scrollController.jumpTo(3600.0);
        await tester.pump();
        for (final RenderParagraph ro in keptParagraphs) {
          ro.markNeedsLayout();
        }
        rebuildHost(() => viewportWidth = 420.0);
        await tester.pump();
        await tester.pump();

        // Scroll back on-screen and copy WITHOUT another pointer drag.
        scrollController.jumpTo(0.0);
        await tester.pump();
        await tester.pump();

        focusNode.requestFocus();
        await tester.pump();
        copiedClipboard = null;
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(copiedClipboard, isNotNull);

        final int firstBefore = copiedClipboard!.indexOf('before');
        final int firstAfter = copiedClipboard!.indexOf('after');
        expect(firstBefore, greaterThanOrEqualTo(0));
        expect(firstAfter, greaterThan(firstBefore));

        final int secondBefore = copiedClipboard!.indexOf('before', firstAfter);
        final int kIdx = copiedClipboard!.indexOf('K', secondBefore);
        final int secondAfter = copiedClipboard!.indexOf('after', secondBefore);
        expect(secondBefore, greaterThan(firstAfter));
        expect(kIdx, greaterThan(secondBefore));
        expect(secondAfter, greaterThan(kIdx));
      },
    );

    testWidgets(
      'FastMarkdownText (useLeafRenderBox: true and false) kept-alive mutation, SelectAll, and SelectionContainer.disabled badges stay non-selectable',
      (WidgetTester tester) async {
        String? copiedClipboard;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                copiedClipboard = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final ScrollController scrollController = ScrollController();
        final FocusNode focusNode = FocusNode();
        addTearDown(scrollController.dispose);
        addTearDown(focusNode.dispose);

        bool mutated = false;
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 600.0,
                    height: 360.0,
                    child: SelectionArea(
                      focusNode: focusNode,
                      child: CustomScrollView(
                        controller: scrollController,
                        slivers: <Widget>[
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (BuildContext context, int index) {
                                final SelectionRegistrar? registrar =
                                    SelectionContainer.maybeOf(context);
                                if (index == 0) {
                                  return Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: FastMarkdownText(
                                          span: TextSpan(
                                            text: mutated
                                                ? 'Leaf mutated paragraph'
                                                : 'Leaf initial paragraph',
                                          ),
                                          plainText: mutated
                                              ? 'Leaf mutated paragraph'
                                              : 'Leaf initial paragraph',
                                          effectiveStyle: const TextStyle(
                                            fontSize: 16.0,
                                          ),
                                          resolvedTextAlign: TextAlign.start,
                                          resolvedTextDirection:
                                              TextDirection.ltr,
                                          resolvedTextScaler:
                                              TextScaler.noScaling,
                                          selectionRegistrar: registrar,
                                          selectionColor: Colors.blue,
                                          useLeafRenderBox: true,
                                        ),
                                      ),
                                      const SelectionContainer.disabled(
                                        child: Text('CHROME-BADGE'),
                                      ),
                                    ],
                                  );
                                }
                                if (index == 1) {
                                  return FastMarkdownText(
                                    span: TextSpan(
                                      text: mutated
                                          ? 'Rich mutated link paragraph'
                                          : 'Rich initial link paragraph',
                                    ),
                                    plainText: mutated
                                        ? 'Rich mutated link paragraph'
                                        : 'Rich initial link paragraph',
                                    effectiveStyle: const TextStyle(
                                      fontSize: 16.0,
                                    ),
                                    resolvedTextAlign: TextAlign.start,
                                    resolvedTextDirection: TextDirection.ltr,
                                    resolvedTextScaler: TextScaler.noScaling,
                                    selectionRegistrar: registrar,
                                    selectionColor: Colors.blue,
                                    useLeafRenderBox: false,
                                  );
                                }
                                return SizedBox(
                                  height: 60.0,
                                  child: Text('Filler item $index'),
                                );
                              },
                              childCount: 80,
                              addAutomaticKeepAlives: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        // SelectAll, scroll top FastMarkdownText items offscreen (>3000px),
        // mutate them while kept-alive, scroll back, and re-copy.
        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(copiedClipboard, contains('Leaf initial paragraph'));
        expect(copiedClipboard, contains('Rich initial link paragraph'));
        expect(copiedClipboard, isNot(contains('CHROME-BADGE')));

        scrollController.jumpTo(3500.0);
        await tester.pump();
        rebuildHost(() => mutated = true);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);

        scrollController.jumpTo(0.0);
        await tester.pump();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        copiedClipboard = null;
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(copiedClipboard, contains('Leaf mutated paragraph'));
        expect(copiedClipboard, contains('Rich mutated link paragraph'));
        expect(copiedClipboard, isNot(contains('CHROME-BADGE')));
      },
    );

    testWidgets(
      'streaming canvas preserves drag selection on macOS right-click inside selection and selects word outside',
      (WidgetTester tester) async {
        SelectedContent? currentSelection;
        final StreamingMarkdownController stream =
            StreamingMarkdownController();
        final FocusNode focusNode = FocusNode();
        addTearDown(stream.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800.0,
                height: 300.0,
                child: SelectionArea(
                  focusNode: focusNode,
                  onSelectionChanged: (SelectedContent? content) {
                    currentSelection = content;
                  },
                  child: MarkdownView.streaming(
                    controller: stream,
                    selectable: true,
                  ),
                ),
              ),
            ),
          ),
        );

        stream.append(
          'prefix alpha beta gamma suffix\n\nSecond streaming block.',
        );
        await tester.pump();

        final Finder canvasFinder = find.byType(MarkdownStreamingCanvasLeaf);
        expect(canvasFinder, findsOneWidget);
        final Rect canvasRect = tester.getRect(canvasFinder);
        final double lineCenterY = canvasRect.top + 12.0;
        final Offset alphaStart = Offset(
          canvasRect.left + 7 * 16.0 + 4.0,
          lineCenterY,
        );
        final Offset betaCenter = Offset(
          canvasRect.left + 15 * 16.0,
          lineCenterY,
        );
        final Offset gammaEnd = Offset(
          canvasRect.left + 23 * 16.0 - 2.0,
          lineCenterY,
        );
        final Offset suffixCenter = Offset(
          canvasRect.left + 27 * 16.0,
          lineCenterY,
        );

        final TestGesture drag = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(drag.removePointer);
        await drag.down(alphaStart);
        await tester.pump();
        await drag.moveTo(gammaEnd);
        await tester.pump();
        await drag.up();
        await tester.pump();

        expect(currentSelection?.plainText, 'alpha beta gamma');

        // Right-click inside selection preserves full drag selection and shows toolbar.
        final TestGesture rightClickInside = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        addTearDown(rightClickInside.removePointer);
        await rightClickInside.down(betaCenter);
        await tester.pump();
        await rightClickInside.up();
        await tester.pump();

        expect(currentSelection?.plainText, 'alpha beta gamma');
        expect(find.text('Copy'), findsOneWidget);

        // Right-click outside selection selects clicked word 'suffix'.
        final TestGesture rightClickOutside = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        addTearDown(rightClickOutside.removePointer);
        await rightClickOutside.down(suffixCenter);
        await tester.pump();
        await rightClickOutside.up();
        await tester.pump();

        expect(currentSelection?.plainText, 'suffix');
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.macOS,
      }),
    );
  });
}
