import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

void main() {
  group('Enclosing link tap targets', () {
    testWidgets(
      'tapping bold, code, highlight, and inline math children inside a link invokes onTapLink',
      (WidgetTester tester) async {
        final List<(String, String?)> tapped = <(String, String?)>[];
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24.0),
                child: MarkdownView(
                  r'[**bold** `code` ==hl== $x$](target.md "Target Title")',
                  options: const MarkdownOptions.extended(),
                  controller: controller,
                  selectable: false,
                  delegates: MarkdownBuilderDelegates(
                    onTapLink: (String dest, String? title) {
                      tapped.add((dest, title));
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        // Locate the outer paragraph RenderParagraph (the one holding the link).
        final Finder richFinder = find.byWidgetPredicate(
          (Widget w) =>
              w is RichText && w.text.toPlainText().contains('bold code hl'),
        );
        expect(richFinder, findsOneWidget);

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          richFinder,
        );
        final String plain = paragraph.text.toPlainText();

        Future<void> tapSubstring(String sub) async {
          final int start = plain.indexOf(sub);
          expect(start, greaterThanOrEqualTo(0), reason: 'Missing "$sub"');
          final List<TextBox> boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + sub.length),
          );
          expect(boxes, isNotEmpty);
          final Offset localCenter = boxes.first.toRect().center;
          final Offset globalCenter = paragraph.localToGlobal(localCenter);
          await tester.tapAt(globalCenter);
          await tester.pump();
        }

        await tapSubstring('bold');
        await tapSubstring('code');
        await tapSubstring('hl');

        // Tap the inline math WidgetSpan child (`x`).
        await tester.tap(find.text('x'));
        await tester.pump();

        expect(tapped, <(String, String?)>[
          ('target.md', 'Target Title'),
          ('target.md', 'Target Title'),
          ('target.md', 'Target Title'),
          ('target.md', 'Target Title'),
        ]);
      },
    );

    testWidgets('invokes onOpenWebLink for safe https links', (
      WidgetTester tester,
    ) async {
      final List<Uri> opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              '[Docs](https://example.com/guide)',
              selectable: false,
              delegates: MarkdownBuilderDelegates(onOpenWebLink: opened.add),
            ),
          ),
        ),
      );

      final Offset linkPos =
          tester.getTopLeft(find.text('Docs')) + const Offset(10.0, 10.0);
      await tester.tapAt(linkPos);
      await tester.pump();
      expect(opened, <Uri>[Uri.parse('https://example.com/guide')]);
    });
  });

  group('Security & image policies', () {
    testWidgets(
      'unsafe schemes (javascript:, vbscript:, data:, control chars) are never interactive',
      (WidgetTester tester) async {
        final List<String> tapped = <String>[];
        final List<Uri> opened = <Uri>[];

        // Even with sanitizeUrls disabled on the AST, Flutter layer still gates
        // every link through MarkdownUrlPolicy.
        const String hostile =
            '[JS Link](javascript:alert(1))\n\n'
            '[VBS Link](vbscript:msgbox(1))\n\n'
            '[Data Link](data:text/html,<script>alert(1)</script>)\n\n'
            '[Obfuscated](java&#x09;script:alert(1))';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                hostile,
                options: const MarkdownOptions.gfm(sanitizeUrls: false),
                selectable: false,
                delegates: MarkdownBuilderDelegates(
                  onTapLink: (String dest, String? _) => tapped.add(dest),
                  onOpenWebLink: opened.add,
                ),
              ),
            ),
          ),
        );

        for (final String label in <String>[
          'JS Link',
          'VBS Link',
          'Data Link',
          'Obfuscated',
        ]) {
          final Finder finder = find.text(label);
          expect(finder, findsOneWidget);
          await tester.tapAt(
            tester.getTopLeft(finder) + const Offset(10.0, 10.0),
          );
          await tester.pump();

          final Text widget = tester.widget<Text>(finder);
          bool foundRecognizer = false;
          widget.textSpan?.visitChildren((InlineSpan span) {
            if (span is TextSpan && span.recognizer != null) {
              foundRecognizer = true;
            }
            return true;
          });
          expect(
            foundRecognizer,
            isFalse,
            reason: '$label must not attach any GestureRecognizer',
          );
        }

        expect(tapped, isEmpty);
        expect(opened, isEmpty);
      },
    );

    testWidgets(
      'MarkdownImagePolicy.block renders placeholder without Image widgets; ask prompts load',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '![Architecture Diagram](https://example.com/diagram.png)',
                delegates: MarkdownBuilderDelegates(
                  imagePolicy: MarkdownImagePolicy.block,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(Image), findsNothing);
        expect(find.text('Architecture Diagram'), findsOneWidget);
        expect(find.text('example.com'), findsOneWidget);

        int loadRequests = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '![Remote Photo](https://cdn.example.org/photo.png)',
                delegates: MarkdownBuilderDelegates(
                  imagePolicy: MarkdownImagePolicy.ask,
                  onLoadRemoteImages: () => loadRequests++,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(Image), findsNothing);
        expect(find.text('Load remote images'), findsOneWidget);
        await tester.tap(find.text('Load remote images'));
        await tester.pump();
        expect(loadRequests, 1);

        // When imagePolicy is load, custom imageBuilder renders allowed URLs,
        // while javascript: URLs remain blocked.
        final List<String> builtImages = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '![Safe](https://cdn.example.org/ok.png)\n\n'
                '![Bad](javascript:alert(1))',
                options: const MarkdownOptions.gfm(sanitizeUrls: false),
                delegates: MarkdownBuilderDelegates(
                  imagePolicy: MarkdownImagePolicy.load,
                  imageBuilder: (BuildContext context, ImageNode node) {
                    builtImages.add(node.destination);
                    return Text('CUSTOM-IMG:${node.alt}');
                  },
                ),
              ),
            ),
          ),
        );

        expect(builtImages, <String>['https://cdn.example.org/ok.png']);
        expect(find.text('CUSTOM-IMG:Safe'), findsOneWidget);
        expect(find.text('Disallowed URL scheme'), findsOneWidget);
      },
    );
  });

  group('Rich blocks, inline extensions, and custom builders', () {
    testWidgets('renders all 5 GitHub Alerts with distinct titles and bodies', (
      WidgetTester tester,
    ) async {
      const String alertsDoc = '''
> [!NOTE]
> Informational note body.

> [!TIP]
> Helpful tip body.

> [!IMPORTANT]
> Important notice body.

> [!WARNING]
> Warning details body.

> [!CAUTION]
> Caution danger body.
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              alertsDoc,
              options: MarkdownOptions.extended(),
              scrollable: false,
            ),
          ),
        ),
      );

      for (final String title in <String>[
        'Note',
        'Tip',
        'Important',
        'Warning',
        'Caution',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Informational note body.'), findsOneWidget);
      expect(find.text('Caution danger body.'), findsOneWidget);
    });

    testWidgets('renders frontmatter card and respects showFrontmatter flag', (
      WidgetTester tester,
    ) async {
      const String doc = '''
---
title: Release Notes
tags: [flutter, markdown]
---

# Body Heading
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              doc,
              options: MarkdownOptions.extended(),
              showFrontmatter: true,
            ),
          ),
        ),
      );

      expect(find.text('YAML'), findsOneWidget);
      expect(find.text('Frontmatter'), findsOneWidget);
      expect(find.text('Release Notes'), findsOneWidget);
      expect(find.text('flutter'), findsOneWidget);
      expect(find.text('Body Heading'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              doc,
              options: MarkdownOptions.extended(),
              showFrontmatter: false,
            ),
          ),
        ),
      );

      expect(find.text('Frontmatter'), findsNothing);
      expect(find.text('Body Heading'), findsOneWidget);
    });

    testWidgets(
      'toggles collapsible <details>/<summary> blocks interactively',
      (WidgetTester tester) async {
        const String doc = '''
<details>
<summary>Show advanced settings</summary>

Hidden secret panel content.

</details>
''';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                doc,
                options: MarkdownOptions.extended(),
                selectable: false,
              ),
            ),
          ),
        );

        expect(find.text('Show advanced settings'), findsOneWidget);
        expect(find.text('Hidden secret panel content.'), findsNothing);

        await tester.tap(find.text('Show advanced settings'));
        await tester.pump();
        expect(find.text('Hidden secret panel content.'), findsOneWidget);

        await tester.tap(find.text('Show advanced settings'));
        await tester.pump();
        expect(find.text('Hidden secret panel content.'), findsNothing);
      },
    );

    testWidgets(
      'renders GFM aligned table, task list checkboxes, footnotes, definition lists, kbd, and abbr',
      (WidgetTester tester) async {
        const String doc = '''
| Feature | Align | Score |
| :--- | :---: | ---: |
| Tables | Center | 100 |
| Tasks | Mid | 99 |

- [x] Completed item
- [ ] Pending item

Press <kbd>Cmd</kbd>+<kbd>K</kbd> to inspect AST[^1].

*[AST]: Abstract Syntax Tree

Term Alpha
: Definition for alpha term.

[^1]: Footnote explanation body.
''';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MarkdownView(
                  doc,
                  options: MarkdownOptions.extended(),
                  scrollable: false,
                ),
              ),
            ),
          ),
        );

        // Table
        expect(find.byType(Table), findsOneWidget);
        expect(find.text('Feature'), findsOneWidget);
        expect(find.text('100'), findsOneWidget);

        // Task list semantics
        expect(find.text('Completed item'), findsOneWidget);
        expect(find.text('Pending item'), findsOneWidget);
        expect(find.text('✓'), findsOneWidget);

        // <kbd> and <abbr>
        expect(find.text('Cmd'), findsOneWidget);
        expect(find.text('K'), findsOneWidget);
        expect(find.byType(Tooltip), findsOneWidget);
        final Tooltip abbrTooltip = tester.widget<Tooltip>(
          find.byType(Tooltip),
        );
        expect(abbrTooltip.message, 'Abstract Syntax Tree');

        // Definition list
        expect(find.text('Term Alpha'), findsOneWidget);
        expect(find.text('Definition for alpha term.'), findsOneWidget);

        // Footnotes
        expect(find.text('[1]'), findsOneWidget);
        expect(find.text('Footnote explanation body.'), findsOneWidget);
        expect(find.text('↩'), findsOneWidget);
      },
    );

    testWidgets(
      'invokes custom mathInlineBuilder, mathBlockBuilder, diagramBuilder, and codeBlockBuilder',
      (WidgetTester tester) async {
        const String doc = r'''
Inline formula $a^2 + b^2 = c^2$ inside text.

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```mermaid
graph LR
  A --> B
```

```dart
void main() {}
```
''';

        GestureRecognizer? seenRecognizer;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                doc,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                delegates: MarkdownBuilderDelegates(
                  mathInlineBuilder:
                      (
                        BuildContext context,
                        MathInlineNode node,
                        TextStyle style,
                        GestureRecognizer? linkRecognizer,
                      ) {
                        seenRecognizer = linkRecognizer;
                        return WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: Text('INLINE-MATH:${node.latex}'),
                        );
                      },
                  mathBlockBuilder: (BuildContext context, MathBlockNode node) {
                    return Text('BLOCK-MATH:${node.latex.trim()}');
                  },
                  diagramBuilder: (BuildContext context, CodeBlockNode node) {
                    if (node.language == 'mermaid') {
                      return Text('MERMAID:${node.literal.trim()}');
                    }
                    return null;
                  },
                  codeBlockBuilder: (BuildContext context, CodeBlockNode node) {
                    return Text(
                      'CODE(${node.language}):${node.literal.trim()}',
                    );
                  },
                ),
              ),
            ),
          ),
        );

        expect(seenRecognizer, isNull);
        expect(find.text('INLINE-MATH:a^2 + b^2 = c^2'), findsOneWidget);
        expect(
          find.text(r'BLOCK-MATH:\int_0^1 x^2\,dx = \frac{1}{3}'),
          findsOneWidget,
        );
        expect(find.text('MERMAID:graph LR\n  A --> B'), findsOneWidget);
        expect(find.text('CODE(dart):void main() {}'), findsOneWidget);
      },
    );

    testWidgets(
      'default code block displays language badge and copies literal to clipboard',
      (WidgetTester tester) async {
        String? copiedClipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                copiedClipboardText = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '```dart\nfinal int answer = 42;\n```',
                selectable: false,
              ),
            ),
          ),
        );

        expect(find.text('dart'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
        expect(find.text('final int answer = 42;'), findsOneWidget);

        await tester.tap(find.text('Copy'));
        await tester.pump();

        expect(copiedClipboardText, 'final int answer = 42;\n');
        expect(find.text('Copied'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 1600));
        expect(find.text('Copy'), findsOneWidget);
      },
    );

    testWidgets('SelectionArea auto-wraps once and respects selectable: false', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MarkdownView('Selectable content')),
        ),
      );
      expect(find.byType(SelectionArea), findsOneWidget);

      // When already wrapped in an ancestor SelectionArea, do not nest another.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SelectionArea(child: MarkdownView('Nested selection')),
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsOneWidget);

      // When selectable: false, no SelectionArea is created.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownView('Non-selectable', selectable: false),
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsNothing);
    });

    testWidgets('renders aligned blocks, figures, and theme-aware <picture>', (
      WidgetTester tester,
    ) async {
      const String doc = '''
<div align="center">

Centered paragraph.

</div>

<figure>

![Fig Image](https://example.com/fig.png)

<figcaption>Figure 1 caption</figcaption>

</figure>

Logo: <picture><source media="(prefers-color-scheme: dark)" srcset="https://example.com/dark.png"><img alt="Theme Logo" src="https://example.com/light.png"></picture>
''';

      final List<String> seenSources = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownTheme(
              data: const MarkdownThemeData.dark(),
              child: MarkdownView(
                doc,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                delegates: MarkdownBuilderDelegates(
                  imagePolicy: MarkdownImagePolicy.load,
                  imageBuilder: (BuildContext context, ImageNode node) {
                    seenSources.add(node.destination);
                    return Text('IMG:${node.destination}');
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Centered paragraph.'), findsOneWidget);
      expect(find.text('Figure 1 caption'), findsOneWidget);
      expect(seenSources, contains('https://example.com/fig.png'));
      expect(seenSources, contains('https://example.com/dark.png'));
    });

    testWidgets(
      'renders default inline math with baseline alignment and works inside pure WidgetsApp',
      (WidgetTester tester) async {
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MarkdownTheme(
              data: const MarkdownThemeData.light(),
              child: MarkdownView(
                'Formula \$E = mc^2\$ with H~2~O, x^2^, ~~strike~~, and ==mark==.\n\n'
                '> Quoted paragraph\n\n'
                '1. Ordered one\n'
                '2. Ordered two\n\n'
                '---\n\n'
                '<a id="jump-spot"></a>Target anchor paragraph.',
                options: const MarkdownOptions.extended(),
                controller: controller,
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );

        expect(find.text('E = mc^2'), findsOneWidget);
        expect(find.text('Quoted paragraph'), findsOneWidget);
        expect(find.text('Ordered one'), findsOneWidget);
        expect(find.text('1.'), findsOneWidget);

        // Verify MathInlineNode default WidgetSpan uses alphabetic baseline.
        final Finder formulaRich = find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              w.textSpan != null &&
              w.textSpan!.toPlainText().contains('Formula'),
        );
        expect(formulaRich, findsOneWidget);
        final Text formulaText = tester.widget<Text>(formulaRich);
        bool sawBaselineMath = false;
        formulaText.textSpan?.visitChildren((InlineSpan span) {
          if (span is WidgetSpan &&
              span.alignment == PlaceholderAlignment.baseline &&
              span.baseline == TextBaseline.alphabetic) {
            sawBaselineMath = true;
          }
          return true;
        });
        expect(sawBaselineMath, isTrue);

        // Inline <a id="jump-spot"></a> registered with controller.
        final bool foundAnchor = await controller.scrollToAnchor(
          'jump-spot',
          duration: Duration.zero,
        );
        expect(foundAnchor, isTrue);
      },
    );
  });
}
