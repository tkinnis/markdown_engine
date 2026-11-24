import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine/markdown_engine.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:markdown_engine_studio/main.dart';
import 'package:markdown_engine_studio/studio_presets.dart';

void _setDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440.0, 900.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 100,
}) async {
  for (int i = 0; i < maxAttempts; i++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pumpAndSettle();
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
    for (final Element element in find.bySubtype<RichText>().evaluate()) {
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

  testWidgets(
    '500-Section Stress outline jump, upward ballistic fling/overscroll, active selection across math & code block, theme toggle, and preset switch throw zero exceptions',
    (WidgetTester tester) async {
      _setDesktopViewport(tester);
      await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
      addTearDown(() async {
        MarkdownBuiltInRenderers.clearCaches();
        await MarkdownBuiltInRenderers.dispose();
      });

      await tester.pumpWidget(const MarkdownStudioApp());
      await tester.pumpAndSettle();

      // 1. Scroll to inline math & Dart code block on Showcase, select across
      // them, scroll past into _keepAliveBucket, toggle Light/Dark theme, and
      // switch to 500-Section Virtualization Stress.
      final Finder previewScrollable = find
          .descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Scrollable),
          )
          .first;
      final ScrollableState previewState = tester.state<ScrollableState>(
        previewScrollable,
      );
      final Finder showcaseMath = find.descendant(
        of: find.byType(MarkdownView),
        matching: find.byWidgetPredicate(
          (Widget w) => '${w.runtimeType}' == 'TexMath',
        ),
      );
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(MarkdownView),
          matching: find.textContaining('Display equations render natively'),
        ),
        250.0,
        scrollable: previewScrollable,
      );
      await tester.pumpAndSettle();
      expect(showcaseMath, findsWidgets);

      final Element previewSelectableElement = tester.element(
        find
            .descendant(
              of: find.byType(MarkdownView),
              matching: find.byType(SelectionContainer),
            )
            .first,
      );
      Focus.of(previewSelectableElement).requestFocus();
      await tester.pump();
      Actions.invoke(
        previewSelectableElement,
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Scroll away from inline math into the bottom of Showcase (and
      // toggle Studio Light/Dark theme) with zero exceptions.
      previewState.position.jumpTo(previewState.position.maxScrollExtent);
      await tester.pump();
      await tester.tap(find.byKey(const Key('studio-theme-toggle')));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('studio-theme-toggle')));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 2. Switch to 500-Section Virtualization Stress preset.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('500-Section Virtualization Stress').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Outline jump to a deep section, then upward ballistic fling &
      // negative overscroll (-503.977) back to top.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('outline-item-section-25-25')),
        200.0,
        scrollable: find.descendant(
          of: find.byKey(const Key('studio-outline-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('outline-item-section-25-25')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.fling(previewScrollable, const Offset(0.0, 2600.0), 7500.0);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      previewState.position.jumpTo(1600.0);
      await tester.pump();
      previewState.position.jumpTo(-503.977);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 3. Drag selection over top rich inline-math paragraph, scroll >3000px
      // offscreen, toggle theme, and switch to Kitchen Sink preset.
      final Finder stressMathPara = find.byWidgetPredicate(
        (Widget w) =>
            w is MarkdownRichText &&
            w.textSpan != null &&
            w.textSpan!.toPlainText().contains('Paragraph 1 exercises'),
      );
      expect(stressMathPara, findsOneWidget);
      final Rect paraRect = tester.getRect(stressMathPara);
      final TestGesture drag = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(drag.removePointer);
      await drag.down(paraRect.centerLeft + const Offset(4.0, 0.0));
      await tester.pump();
      await drag.moveTo(paraRect.centerRight - const Offset(4.0, 0.0));
      await tester.pump();
      await drag.up();
      await tester.pump();

      previewState.position.jumpTo(3600.0);
      await tester.pump();
      await tester.tap(find.byKey(const Key('studio-theme-toggle')));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen Sink (Visual Parity)').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'MarkdownStudioApp launches with Comprehensive Markdown Guide preset and CLI arg without exceptions',
    (WidgetTester tester) async {
      _setDesktopViewport(tester);
      await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
      addTearDown(() async {
        rootBundle.evict('assets/comprehensive_markdown_guide.md');
        MarkdownBuiltInRenderers.clearCaches();
        await MarkdownBuiltInRenderers.dispose();
      });

      final MarkdownStudioApp cliApp = MarkdownStudioApp.fromArgs(
        const <String>['--preset=comprehensiveGuide'],
      );
      expect(cliApp.initialPreset, StudioPresetId.comprehensiveGuide);

      await tester.pumpWidget(cliApp);
      await _pumpUntilFound(
        tester,
        find.text('Loaded preset: Comprehensive Markdown Guide'),
      );
      expect(tester.takeException(), isNull);

      expect(
        find.text('Loaded preset: Comprehensive Markdown Guide'),
        findsOneWidget,
      );

      final TextField editor = tester.widget<TextField>(
        find.byKey(const Key('studio-source-editor')),
      );
      final String loadedSource = editor.controller!.text;
      expect(loadedSource, contains('title: Markdown Syntax Guide'));
      expect(loadedSource, contains('# Mermaid Diagram Examples'));
      expect(loadedSource, contains('# LaTeX Math Examples'));

      final MarkdownDocument parsed = const MarkdownEngine(
        defaultOptions: MarkdownOptions.extended(),
      ).parse(loadedSource);
      expect(parsed.blocks.whereType<FrontmatterNode>(), isNotEmpty);
      expect(parsed.blocks.whereType<HeadingNode>(), isNotEmpty);
      expect(parsed.blocks.whereType<MathBlockNode>(), isNotEmpty);
      expect(
        parsed.blocks.whereType<CodeBlockNode>().where(
          (CodeBlockNode b) => b.language == 'mermaid',
        ),
        isNotEmpty,
      );

      // Frontmatter metadata and top heading render cleanly.
      expect(find.text('User Manual'), findsWidgets);
      expect(find.text('Markdown Syntax Guide'), findsWidgets);

      final Finder previewScrollable = find
          .descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Scrollable),
          )
          .first;

      // Scroll to LaTeX math and Mermaid sections inside the guide.
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(MarkdownView),
          matching: find.text('Display / Block Math'),
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
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(MarkdownView),
          matching: find.text('Sequence Diagrams'),
        ),
        300.0,
        scrollable: previewScrollable,
      );
      await tester.pumpAndSettle();
      final Finder mermaidGraphicFinder = find.descendant(
        of: find.byType(MarkdownView),
        matching: find.byWidgetPredicate(
          (Widget w) => '${w.runtimeType}' == 'VectorGraphic',
        ),
      );
      expect(mermaidGraphicFinder, findsWidgets);
      expect(tester.takeException(), isNull);

      // Jump via outline to the LaTeX Math Examples section and verify zero exceptions.
      final Finder outlineLatexItem = find.descendant(
        of: find.byKey(const Key('studio-outline-list')),
        matching: find.text('LaTeX Math Examples'),
      );
      await tester.scrollUntilVisible(
        outlineLatexItem,
        200.0,
        scrollable: find.descendant(
          of: find.byKey(const Key('studio-outline-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(outlineLatexItem);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Scroll to wide overflow & intentional malformed TeX error widgets at the end.
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(MarkdownView),
          matching: find.textContaining('Intentional Malformed TeX'),
        ),
        350.0,
        scrollable: previewScrollable,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Selecting Comprehensive Markdown Guide from dropdown renders and handles async preset switch & edit races cleanly',
    (WidgetTester tester) async {
      _setDesktopViewport(tester);
      await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
      final ByteData? realGuideBytes = await tester.runAsync(
        () => rootBundle.load('assets/comprehensive_markdown_guide.md'),
      );
      expect(realGuideBytes, isNotNull);

      await tester.pumpWidget(const MarkdownStudioApp());
      await tester.pumpAndSettle();

      // 1. Select Comprehensive Markdown Guide via toolbar dropdown (real asset load).
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprehensive Markdown Guide').last);
      await _pumpUntilFound(
        tester,
        find.text('Loaded preset: Comprehensive Markdown Guide'),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Loaded preset: Comprehensive Markdown Guide'),
        findsOneWidget,
      );
      expect(find.text('Markdown Syntax Guide'), findsWidgets);

      // Switch away to Showcase and back to Comprehensive Guide (cached in rootBundle).
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CommonMark & GFM Showcase').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Loaded preset: CommonMark & GFM Showcase'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprehensive Markdown Guide').last);
      await _pumpUntilFound(
        tester,
        find.text('Loaded preset: Comprehensive Markdown Guide'),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Loaded preset: Comprehensive Markdown Guide'),
        findsOneWidget,
      );
      expect(find.text('Markdown Syntax Guide'), findsWidgets);

      // 2. Deterministic race tests with mocked delayed asset loads.
      final List<Completer<ByteData?>> pendingLoads = <Completer<ByteData?>>[];
      bool failNextAssetLoad = false;
      final TestDefaultBinaryMessenger messenger =
          tester.binding.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (
        ByteData? message,
      ) async {
        final String key = message == null
            ? ''
            : utf8.decode(
                message.buffer.asUint8List(
                  message.offsetInBytes,
                  message.lengthInBytes,
                ),
              );
        if (key == 'assets/comprehensive_markdown_guide.md') {
          if (failNextAssetLoad) {
            failNextAssetLoad = false;
            return null;
          }
          final Completer<ByteData?> completer = Completer<ByteData?>();
          pendingLoads.add(completer);
          return completer.future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMessageHandler('flutter/assets', null);
        rootBundle.evict('assets/comprehensive_markdown_guide.md');
        MarkdownBuiltInRenderers.clearCaches();
        return MarkdownBuiltInRenderers.dispose();
      });

      // Switch away to Showcase first.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CommonMark & GFM Showcase').last);
      await tester.pumpAndSettle();

      // Race A: Switch to Comprehensive Guide, then immediately switch away to Kitchen Sink.
      rootBundle.evict('assets/comprehensive_markdown_guide.md');
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprehensive Markdown Guide').last);
      await tester.pump();
      expect(pendingLoads, hasLength(1));

      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen Sink (Visual Parity)').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Kitchen Sink Visual Parity'), findsWidgets);

      // Complete stale Comprehensive Guide load -> must NOT overwrite Kitchen Sink.
      pendingLoads[0].complete(realGuideBytes);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Kitchen Sink Visual Parity'), findsWidgets);
      expect(
        find.text('Loaded preset: Kitchen Sink (Visual Parity)'),
        findsOneWidget,
      );

      // Race B: Switch to Comprehensive Guide -> away -> back again; resolve stale first, then latest.
      rootBundle.evict('assets/comprehensive_markdown_guide.md');
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprehensive Markdown Guide').last);
      await tester.pump();
      expect(pendingLoads, hasLength(2));

      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CommonMark & GFM Showcase').last);
      await tester.pumpAndSettle();

      rootBundle.evict('assets/comprehensive_markdown_guide.md');
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprehensive Markdown Guide').last);
      await tester.pump();
      expect(pendingLoads, hasLength(3));

      // Resolving stale load #2 with distinct content must NOT overwrite current empty loading state.
      pendingLoads[1].complete(
        ByteData.sublistView(utf8.encode('# Stale Guide Content')),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(find.text('Stale Guide Content'), findsNothing);

      // Resolving latest load #3 populates the real guide cleanly.
      pendingLoads[2].complete(realGuideBytes);
      await _pumpUntilFound(
        tester,
        find.text('Loaded preset: Comprehensive Markdown Guide'),
      );
      expect(find.text('Markdown Syntax Guide'), findsWidgets);
      expect(
        find.text('Loaded preset: Comprehensive Markdown Guide'),
        findsOneWidget,
      );

      // Race C: Manual user edit while async asset load is in flight must not be overwritten.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CommonMark & GFM Showcase').last);
      await tester.pumpAndSettle();

      rootBundle.evict('assets/comprehensive_markdown_guide.md');
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprehensive Markdown Guide').last);
      await tester.pump();
      expect(pendingLoads, hasLength(4));

      await tester.enterText(
        find.byKey(const Key('studio-source-editor')),
        '# Manual User Edit\n\nDo not overwrite me.',
      );
      await tester.pump();
      pendingLoads[3].complete(realGuideBytes);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manual User Edit'), findsWidgets);
      expect(find.text('Markdown Syntax Guide'), findsNothing);

      // Error handling: failed asset load surfaces error status cleanly without throwing.
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CommonMark & GFM Showcase').last);
      await tester.pumpAndSettle();

      rootBundle.evict('assets/comprehensive_markdown_guide.md');
      failNextAssetLoad = true;
      await tester.tap(find.byKey(const Key('studio-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprehensive Markdown Guide').last);
      await _pumpUntilFound(
        tester,
        find.textContaining(
          'Failed to load preset "Comprehensive Markdown Guide"',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(
          'Failed to load preset "Comprehensive Markdown Guide"',
        ),
        findsOneWidget,
      );
    },
  );
}
