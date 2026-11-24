import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:markdown_engine_studio/main.dart';
import 'package:markdown_engine_studio/studio_presets.dart';

void _setDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440.0, 900.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
    'Studio app renders custom initialSource and updates live MarkdownView',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MarkdownStudioApp(initialSource: 'Studio preview text'),
      );
      await tester.pump();

      expect(find.text('markdown_engine Studio'), findsOneWidget);
      expect(find.byKey(const Key('studio-source-editor')), findsOneWidget);
      expect(find.byType(MarkdownView), findsOneWidget);
      expect(find.text('Studio preview text'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('studio-source-editor')),
        'Updated studio content',
      );
      await tester.pump();

      expect(find.text('Updated studio content'), findsWidgets);
    },
  );

  testWidgets('Instant Light / Dark theme toggle performs zero reparses', (
    WidgetTester tester,
  ) async {
    _setDesktopViewport(tester);

    await tester.pumpWidget(const MarkdownStudioApp());
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('studio-parse-count')),
        matching: find.text('Parses: 1'),
      ),
      findsOneWidget,
    );

    MarkdownTheme lightTheme = tester.widget<MarkdownTheme>(
      find.byType(MarkdownTheme),
    );
    expect(lightTheme.data.brightness, Brightness.light);

    await tester.tap(find.byKey(const Key('studio-theme-toggle')));
    await tester.pump();

    final MarkdownTheme darkTheme = tester.widget<MarkdownTheme>(
      find.byType(MarkdownTheme),
    );
    expect(darkTheme.data.brightness, Brightness.dark);
    expect(
      find.descendant(
        of: find.byKey(const Key('studio-parse-count')),
        matching: find.text('Parses: 1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('studio-theme-toggle')));
    await tester.pump();

    lightTheme = tester.widget<MarkdownTheme>(find.byType(MarkdownTheme));
    expect(lightTheme.data.brightness, Brightness.light);
    expect(
      find.descendant(
        of: find.byKey(const Key('studio-parse-count')),
        matching: find.text('Parses: 1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Preset switching loads Kitchen Sink, Alerts, Security, and 500-Section Stress with built-in math & Mermaid',
    (WidgetTester tester) async {
      _setDesktopViewport(tester);
      await tester.runAsync(MarkdownBuiltInRenderers.warmUp);

      await tester.pumpWidget(const MarkdownStudioApp());
      await tester.pumpAndSettle();

      // Default showcase renders built-in TexMath and VectorGraphic Mermaid widgets.
      expect(find.text('CommonMark & GFM Showcase'), findsWidgets);

      final Finder previewScrollable = find
          .descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(MarkdownView),
          matching: find.textContaining('Display equations render natively'),
        ),
        300.0,
        scrollable: previewScrollable,
      );
      await tester.pumpAndSettle();
      final Finder texMathFinder = find.descendant(
        of: find.byType(MarkdownView),
        matching: find.byWidgetPredicate(
          (Widget w) => '${w.runtimeType}' == 'TexMath',
        ),
      );
      expect(texMathFinder, findsWidgets);

      final Finder mermaidGraphicFinder = find.descendant(
        of: find.byType(MarkdownView),
        matching: find.byWidgetPredicate(
          (Widget w) => '${w.runtimeType}' == 'VectorGraphic',
        ),
      );
      await tester.scrollUntilVisible(
        mermaidGraphicFinder,
        300.0,
        scrollable: previewScrollable,
      );
      expect(mermaidGraphicFinder, findsOneWidget);

      // Non-mermaid Dart code fence uses Studio's syntax-highlighted codeBlockBuilder.
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(MarkdownView),
          matching: find.text('Code & Definition Lists'),
        ),
        300.0,
        scrollable: previewScrollable,
      );
      await tester.pumpAndSettle();
      final Finder dartBadgeFinder = find.descendant(
        of: find.byType(MarkdownView),
        matching: find.text('dart'),
      );
      expect(dartBadgeFinder, findsOneWidget);
      expect(find.text('Copy'), findsWidgets);

      // Switch to Kitchen Sink (Visual Parity) preset.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen Sink (Visual Parity)').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Kitchen Sink Visual Parity'), findsWidgets);
      expect(texMathFinder, findsWidgets);

      // Switch to Alerts, Frontmatter & HTML preset.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alerts, Frontmatter & HTML').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Alerts, Frontmatter & HTML'), findsWidgets);
      expect(find.byKey(const Key('studio-outline-list')), findsOneWidget);

      // Switch to Security & Sanitization preset.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Security & Sanitization').last);
      await tester.pumpAndSettle();

      final Text policyText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('studio-url-policy-badge')),
          matching: find.byType(Text),
        ),
      );
      expect(policyText.data, contains('allowed'));
      expect(policyText.data, contains('blocked'));
      expect(policyText.data, isNot(contains('0 blocked')));

      // Verify Security preset sanitizes raw <script> and <iframe> in HTML view.
      await tester.tap(find.byKey(const Key('inspector-tab-html')));
      await tester.pump();
      final SelectableText sanitizedHtml = tester.widget<SelectableText>(
        find.byKey(const Key('studio-html-output')),
      );
      expect(sanitizedHtml.data, isNot(contains('<script>')));
      expect(sanitizedHtml.data, isNot(contains('<iframe')));
      await tester.tap(find.byKey(const Key('inspector-tab-ast')));
      await tester.pump();

      // Switch to 500-Section Virtualization Stress preset.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('500-Section Virtualization Stress').last);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('studio-outline-toggle')),
          matching: find.text('Outline (501)'),
        ),
        findsOneWidget,
      );

      // Jump via outline sidebar item.
      await tester.tap(
        find.byKey(const ValueKey<String>('outline-item-section-2-2')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Jumped to outline heading #section-2'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Inspector switches between AST & Spans, HTML Output, and Plain Text',
    (WidgetTester tester) async {
      _setDesktopViewport(tester);

      await tester.pumpWidget(
        const MarkdownStudioApp(
          initialSource: '# Inspector Heading\n\nParagraph with **bold** text.',
        ),
      );
      await tester.pump();

      // Default AST tab shows node runtimeType, blockId, line range, and offset range.
      expect(find.byKey(const Key('studio-ast-tree')), findsOneWidget);
      expect(find.text('HeadingNode'), findsOneWidget);
      expect(find.text('ParagraphNode'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('studio-ast-tree')),
          matching: find.text('b-1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('studio-ast-tree')),
          matching: find.text('b-2'),
        ),
        findsOneWidget,
      );
      expect(find.text('L1..1'), findsOneWidget);
      expect(find.textContaining('off 0..'), findsOneWidget);

      // Expand HeadingNode to inspect inline children.
      await tester.tap(find.text('HeadingNode'));
      await tester.pump();
      expect(find.text('TextNode'), findsOneWidget);

      // Switch to HTML tab.
      await tester.tap(find.byKey(const Key('inspector-tab-html')));
      await tester.pump();

      final SelectableText htmlWidget = tester.widget<SelectableText>(
        find.byKey(const Key('studio-html-output')),
      );
      expect(htmlWidget.data, contains('<h1'));
      expect(htmlWidget.data, contains('Inspector Heading</h1>'));
      expect(htmlWidget.data, contains('<strong>bold</strong>'));

      // Switch to Plain Text tab.
      await tester.tap(find.byKey(const Key('inspector-tab-text')));
      await tester.pump();

      final SelectableText plainWidget = tester.widget<SelectableText>(
        find.byKey(const Key('studio-plaintext-output')),
      );
      expect(plainWidget.data, contains('Inspector Heading'));
      expect(plainWidget.data, contains('Paragraph with bold text.'));
      expect(plainWidget.data, isNot(contains('<strong>')));
    },
  );

  testWidgets(
    'Streaming simulator supports step, timed play/pause, finish, and reset',
    (WidgetTester tester) async {
      _setDesktopViewport(tester);

      await tester.pumpWidget(const MarkdownStudioApp());
      await tester.pump();

      // Enter Streaming Mode.
      await tester.tap(find.byKey(const Key('studio-streaming-toggle')));
      await tester.pump();

      expect(find.text('LLM Streaming Simulator'), findsOneWidget);
      expect(find.byType(MarkdownView), findsOneWidget);
      expect(
        find.text('Chunks: 0 / ${studioStreamingChunks.length}'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-settled')))
            .data,
        '0',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-total-blocks')))
            .data,
        '0',
      );

      // Step through enough chunks to close and settle the first blocks.
      for (int i = 0; i < 12; i++) {
        await tester.tap(find.byKey(const Key('studio-stream-step')));
        await tester.pump();
      }

      expect(
        find.text('Chunks: 12 / ${studioStreamingChunks.length}'),
        findsOneWidget,
      );
      final int settledAfterStep = int.parse(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-settled')))
            .data!,
      );
      final int totalAfterStep = int.parse(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-total-blocks')))
            .data!,
      );
      expect(settledAfterStep, greaterThan(0));
      expect(totalAfterStep, greaterThanOrEqualTo(settledAfterStep));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-parse-us')))
            .data,
        endsWith(' µs'),
      );

      // Start timed playback, allow several chunks to stream, then pause.
      await tester.tap(find.byKey(const Key('studio-stream-play-pause')));
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 350));
      final String progressWhilePlaying = tester
          .widget<Text>(find.byKey(const Key('studio-stream-progress-label')))
          .data!;
      expect(
        progressWhilePlaying,
        isNot('Chunks: 12 / ${studioStreamingChunks.length}'),
      );

      // Pause and ensure chunk count does not advance while paused.
      await tester.tap(find.byKey(const Key('studio-stream-play-pause')));
      await tester.pump();
      expect(find.text('Play'), findsOneWidget);

      final String progressWhenPaused = tester
          .widget<Text>(find.byKey(const Key('studio-stream-progress-label')))
          .data!;
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-progress-label')))
            .data,
        progressWhenPaused,
      );

      // Verify speed slider updates chunk interval label.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-speed-label')))
            .data,
        '100 ms/chunk',
      );
      final Slider speedSlider = tester.widget<Slider>(
        find.byKey(const Key('studio-stream-speed-slider')),
      );
      speedSlider.onChanged?.call(200.0);
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-speed-label')))
            .data,
        '200 ms/chunk',
      );

      // Finish remaining chunks.
      await tester.tap(find.byKey(const Key('studio-stream-finish')));
      await tester.pump();
      expect(
        find.text(
          'Chunks: ${studioStreamingChunks.length} / ${studioStreamingChunks.length}',
        ),
        findsOneWidget,
      );

      // Reset clears chunks and blocks back to zero.
      await tester.tap(find.byKey(const Key('studio-stream-reset')));
      await tester.pump();
      expect(
        find.text('Chunks: 0 / ${studioStreamingChunks.length}'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-settled')))
            .data,
        '0',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('studio-stream-total-blocks')))
            .data,
        '0',
      );
    },
  );

  testWidgets('Link tap reports MarkdownUrlPolicy status banner and snackbar', (
    WidgetTester tester,
  ) async {
    _setDesktopViewport(tester);

    await tester.pumpWidget(
      const MarkdownStudioApp(
        initialSource: '# Policy Test\n\nOpen [Dart Docs](https://dart.dev) or [Bad](javascript:alert(1)).',
      ),
    );
    await tester.pump();

    final Text badgeText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('studio-url-policy-badge')),
        matching: find.byType(Text),
      ),
    );
    expect(badgeText.data, 'MarkdownUrlPolicy: 1 allowed · 1 blocked');

    // Locate the TapGestureRecognizer attached to the safe link span.
    bool tapped = false;
    for (final Element element in find.byType(RichText).evaluate()) {
      final RichText richText = element.widget as RichText;
      richText.text.visitChildren((InlineSpan span) {
        if (span is TextSpan &&
            span.text == 'Dart Docs' &&
            span.recognizer is TapGestureRecognizer) {
          (span.recognizer! as TapGestureRecognizer).onTap?.call();
          tapped = true;
          return false;
        }
        return true;
      });
      if (tapped) {
        break;
      }
    }
    expect(tapped, isTrue);
    await tester.pump();

    expect(find.byKey(const Key('studio-status-banner')), findsOneWidget);
    expect(
      find.text('MarkdownUrlPolicy allowed link: https://dart.dev'),
      findsWidgets,
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
    'Cursor-only editor moves trigger zero reparses, expanded inspector clears across presets, and Load remote images works',
    (WidgetTester tester) async {
      _setDesktopViewport(tester);

      await tester.pumpWidget(const MarkdownStudioApp());
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('studio-parse-count')),
          matching: find.text('Parses: 1'),
        ),
        findsOneWidget,
      );

      // Moving selection/caret without modifying text triggers 0 reparses.
      final TextField editor = tester.widget<TextField>(
        find.byKey(const Key('studio-source-editor')),
      );
      editor.controller!.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      editor.controller!.selection = const TextSelection.collapsed(offset: 12);
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('studio-parse-count')),
          matching: find.text('Parses: 1'),
        ),
        findsOneWidget,
      );

      // Expand an AST card, then switch presets -> expanded IDs clear cleanly.
      await tester.tap(find.text('HeadingNode').first);
      await tester.pump();
      expect(find.text('TextNode'), findsWidgets);

      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Security & Sanitization').last);
      await tester.pumpAndSettle();

      // Switch back to Showcase and verify expanded inline nodes are collapsed.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CommonMark & GFM Showcase').last);
      await tester.pumpAndSettle();
      expect(find.text('TextNode'), findsNothing);

      // Switch to Security preset and approve remote image loading.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Security & Sanitization').last);
      await tester.pumpAndSettle();

      final Finder previewScrollable = find
          .descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Load remote images'),
        250.0,
        scrollable: previewScrollable,
      );
      await tester.ensureVisible(find.text('Load remote images'));
      await tester.pumpAndSettle();
      expect(find.text('Load remote images'), findsOneWidget);

      await tester.tap(find.text('Load remote images'));
      await tester.pump();
      expect(find.text('Load remote images'), findsNothing);
      expect(
        find.text(
          'Remote image loading approved for current view (MarkdownImagePolicy.ask).',
        ),
        findsWidgets,
      );
    },
  );
}
