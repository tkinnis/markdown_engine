import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:markdown_engine_flutter/src/isolate_parse_io.dart';

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
}
