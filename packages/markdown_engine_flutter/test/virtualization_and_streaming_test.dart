import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

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
        final bool scrolled = await controller.scrollToAnchor(
          'section-350',
          duration: Duration.zero,
        );
        await tester.pump();
        expect(scrolled, isTrue);
        expect(controller.readingPlace.blockIndex, greaterThanOrEqualTo(300));

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

    test(
      'parses large documents (>= 4096 code units) in a background isolate with latest-wins coalescing',
      () async {
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
      },
    );

    test('captures parse budget errors cleanly in lastError', () async {
      final MarkdownDocumentReader reader = MarkdownDocumentReader();
      addTearDown(reader.dispose);

      await reader.update(
        'Too long input',
        options: const MarkdownOptions(maxInputLength: 4),
      );

      expect(reader.lastError, isA<RangeError>());
      expect(reader.isParsing, isFalse);
    });
  });
}
