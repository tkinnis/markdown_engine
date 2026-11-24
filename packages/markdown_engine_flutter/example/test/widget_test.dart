import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:markdown_engine_flutter_example/main.dart';

void main() {
  testWidgets(
    'Example app renders built-in math & Mermaid in showcase/streaming, toggles theme with 0 re-parses, and demonstrates optional hooks',
    (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        await tester.pumpWidget(const MarkdownExampleApp());
        await tester.pumpAndSettle();

        expect(find.text('markdown_engine_flutter Example'), findsOneWidget);
        expect(find.byType(MarkdownView), findsWidgets);
        expect(find.text('Native Flutter Markdown Rendering'), findsOneWidget);
        expect(find.text('Parses: 1'), findsOneWidget);

        // Toggle Light -> Dark theme: parse count must remain 1.
        await tester.tap(find.byKey(const Key('theme-toggle-button')));
        await tester.pumpAndSettle();
        expect(find.text('Parses: 1'), findsOneWidget);

        // Showcase renders real out-of-the-box TexMath and VectorGraphic Mermaid widgets.
        final Finder showcaseVerticalScrollable = find.descendant(
          of: find.byType(MarkdownView).first,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        final Finder showcaseTexMath = find.descendant(
          of: find.byType(MarkdownView).first,
          matching: find.byWidgetPredicate(
            (Widget w) => '${w.runtimeType}' == 'TexMath',
          ),
        );
        await tester.scrollUntilVisible(
          find.descendant(
            of: find.byType(MarkdownView).first,
            matching: find.textContaining('Display equations render natively'),
          ),
          200.0,
          scrollable: showcaseVerticalScrollable,
        );
        await tester.pumpAndSettle();
        expect(showcaseTexMath, findsWidgets);

        final Finder showcaseMermaid = find.descendant(
          of: find.byType(MarkdownView).first,
          matching: find.byWidgetPredicate(
            (Widget w) => '${w.runtimeType}' == 'VectorGraphic',
          ),
        );
        await tester.scrollUntilVisible(
          showcaseMermaid,
          200.0,
          scrollable: showcaseVerticalScrollable,
        );
        expect(showcaseMermaid, findsOneWidget);

        // Scroll to Load remote images in Showcase and approve loading.
        await tester.scrollUntilVisible(
          find.text('Load remote images'),
          200.0,
          scrollable: showcaseVerticalScrollable,
        );
        await tester.ensureVisible(find.text('Load remote images'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Load remote images'));
        await tester.pump();
        expect(find.text('Load remote images'), findsNothing);
        expect(
          find.text('Remote image loading approved for showcase view.'),
          findsOneWidget,
        );

        // Switch to LLM Stream tab and step chunks incrementally, reset, and stream again.
        await tester.tap(find.byKey(const Key('tab-streaming')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('step-chunk-button')));
        await tester.pump();
        expect(find.text('Streaming Assistant Response'), findsOneWidget);

        await tester.tap(find.byKey(const Key('step-chunk-button')));
        await tester.pump();
        expect(
          find.bySemanticsLabel(
            RegExp('Incoming chunks freeze completed prefix blocks'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('reset-stream-button')));
        await tester.pump();
        expect(find.text('Streaming Assistant Response'), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp('Streaming Assistant Response')),
          findsNothing,
        );

        for (int i = 0; i < 16; i++) {
          await tester.tap(find.byKey(const Key('step-chunk-button')));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final Finder streamScrollable = find.descendant(
          of: find.byType(MarkdownView),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        final Finder streamTexMath = find.descendant(
          of: find.byType(MarkdownView),
          matching: find.byWidgetPredicate(
            (Widget w) => '${w.runtimeType}' == 'TexMath',
          ),
        );
        expect(streamTexMath, findsWidgets);

        final Finder streamMermaid = find.descendant(
          of: find.byType(MarkdownView),
          matching: find.byWidgetPredicate(
            (Widget w) => '${w.runtimeType}' == 'VectorGraphic',
          ),
        );
        await tester.scrollUntilVisible(
          streamMermaid,
          200.0,
          scrollable: streamScrollable,
        );
        expect(streamMermaid, findsOneWidget);

        // Switch to Custom Hooks tab and verify optional overrides.
        await tester.tap(find.byKey(const Key('tab-hooks')));
        await tester.pumpAndSettle();
        expect(find.text('Optional Custom Renderer Overrides'), findsOneWidget);
        expect(find.text(r'TeX(e^{i\pi} + 1 = 0)'), findsOneWidget);

        final Finder hooksVerticalScrollable = find.descendant(
          of: find.byType(MarkdownView),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await tester.scrollUntilVisible(
          find.text('Custom Display Math Hook'),
          200.0,
          scrollable: hooksVerticalScrollable,
        );
        expect(find.text('Custom Display Math Hook'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Custom Diagram Decorator (mermaid)'),
          200.0,
          scrollable: hooksVerticalScrollable,
        );
        expect(find.text('Custom Diagram Decorator (mermaid)'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Custom Code Hook (dart)'),
          200.0,
          scrollable: hooksVerticalScrollable,
        );
        expect(find.text('Custom Code Hook (dart)'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );
}
