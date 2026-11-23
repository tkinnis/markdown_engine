import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:markdown_engine_flutter_example/main.dart';

void main() {
  testWidgets(
    'Example app renders showcase, toggles theme with 0 re-parses, streams chunks, and runs custom hooks',
    (WidgetTester tester) async {
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

      // Scroll to Load remote images in Showcase and approve loading.
      final Finder showcaseVerticalScrollable = find.descendant(
        of: find.byType(MarkdownView).first,
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
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
        find.text('Incoming chunks freeze completed prefix blocks'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('reset-stream-button')));
      await tester.pump();
      expect(find.text('Streaming Assistant Response'), findsNothing);

      await tester.tap(find.byKey(const Key('step-chunk-button')));
      await tester.pump();
      expect(find.text('Streaming Assistant Response'), findsOneWidget);

      // Switch to Custom Hooks tab and verify math, diagram, and code hooks.
      await tester.tap(find.byKey(const Key('tab-hooks')));
      await tester.pumpAndSettle();
      expect(find.text(r'TeX(e^{i\pi} + 1 = 0)'), findsOneWidget);
      expect(find.text('Custom Display Math Hook'), findsOneWidget);

      final Finder hooksVerticalScrollable = find.descendant(
        of: find.byType(MarkdownView).last,
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Diagram Hook (mermaid)'),
        200.0,
        scrollable: hooksVerticalScrollable,
      );
      expect(find.text('Diagram Hook (mermaid)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Custom Code Hook (dart)'),
        200.0,
        scrollable: hooksVerticalScrollable,
      );
      expect(find.text('Custom Code Hook (dart)'), findsOneWidget);
    },
  );
}
