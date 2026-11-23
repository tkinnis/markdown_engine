import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

void main() {
  group('MarkdownTheme', () {
    testWidgets('resolves explicit MarkdownTheme and ColorScheme fallback', (
      WidgetTester tester,
    ) async {
      late MarkdownThemeData resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownTheme(
            data: MarkdownThemeData.fallback,
            child: Builder(
              builder: (BuildContext context) {
                resolved = MarkdownTheme.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(resolved, MarkdownThemeData.fallback);

      late MarkdownThemeData materialResolved;
      final ColorScheme darkScheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: darkScheme),
          home: Builder(
            builder: (BuildContext context) {
              materialResolved = MarkdownTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(materialResolved.foreground, darkScheme.onSurface);
      expect(materialResolved.accent, darkScheme.primary);
      expect(materialResolved.brightness, Brightness.dark);
    });

    test('supports light, dark, copyWith, lerp, and alertPalette lookup', () {
      const MarkdownThemeData light = MarkdownThemeData.light();
      const MarkdownThemeData dark = MarkdownThemeData.dark();

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light, MarkdownThemeData.fallback);
      expect(light == dark, isFalse);

      final MarkdownThemeData custom = light.copyWith(
        fontSize: 18.0,
        blockSpacing: 16.0,
        fontFamily: 'Inter',
        codeFontFamily: 'JetBrains Mono',
      );
      expect(custom.fontSize, 18.0);
      expect(custom.blockSpacing, 16.0);
      expect(custom.fontFamily, 'Inter');
      expect(custom.codeFontFamily, 'JetBrains Mono');
      expect(custom.headingFontSize(1), 36.0);

      final MarkdownThemeData mid = MarkdownThemeData.lerp(light, dark, 0.5);
      expect(mid.brightness, Brightness.dark);
      for (final AlertKind kind in AlertKind.values) {
        expect(light.alertPalette.forKind(kind), isNotNull);
        expect(dark.alertPalette.forKind(kind), isNotNull);
      }
    });
  });

  group('MarkdownView', () {
    testWidgets('renders parsed blocks and empty content cleanly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MarkdownView('First block\n\nSecond block')),
        ),
      );

      expect(find.text('First block'), findsOneWidget);
      expect(find.text('Second block'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MarkdownView('   '))),
      );
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
