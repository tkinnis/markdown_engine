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

      // Switch to LLM Stream tab and step chunks incrementally.
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

      // Switch to Custom Hooks tab and verify math, diagram, and code hooks.
      await tester.tap(find.byKey(const Key('tab-hooks')));
      await tester.pumpAndSettle();
      expect(find.text(r'TeX(e^{i\pi} + 1 = 0)'), findsOneWidget);
      expect(find.text('Custom Display Math Hook'), findsOneWidget);
      expect(find.text('Diagram Hook (mermaid)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Custom Code Hook (dart)'),
        200.0,
        scrollable: find.descendant(
          of: find.byType(MarkdownView).last,
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Custom Code Hook (dart)'), findsOneWidget);
    },
  );
}
