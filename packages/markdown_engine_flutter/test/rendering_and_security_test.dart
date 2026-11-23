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

  group('Wave 3 security, WidgetsApp, semantics & inline polish', () {
    testWidgets(
      'MarkdownImagePolicy.ask resets approval across document/data changes and honors remoteImagesApproved',
      (WidgetTester tester) async {
        String source = '![Doc A Img](https://a.example/one.png)';
        late StateSetter rebuild;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return MaterialApp(
                home: Scaffold(
                  body: MarkdownView(
                    source,
                    delegates: MarkdownBuilderDelegates(
                      imagePolicy: MarkdownImagePolicy.ask,
                      imageBuilder: (BuildContext context, ImageNode node) =>
                          Text('LOADED:${node.destination}'),
                    ),
                  ),
                ),
              );
            },
          ),
        );

        expect(find.text('Load remote images'), findsOneWidget);
        expect(find.text('LOADED:https://a.example/one.png'), findsNothing);

        await tester.tap(find.text('Load remote images'));
        await tester.pump();
        expect(find.text('LOADED:https://a.example/one.png'), findsOneWidget);

        // Switching to Document B must reset local remote-image approval.
        rebuild(() => source = '![Doc B Img](https://b.example/two.png)');
        await tester.pump();
        expect(find.text('LOADED:https://b.example/two.png'), findsNothing);
        expect(find.text('Load remote images'), findsOneWidget);

        // Explicit remoteImagesApproved + onLoadRemoteImages wiring on MarkdownView.
        bool approvedByHost = false;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return MaterialApp(
                home: Scaffold(
                  body: MarkdownView(
                    '![Controlled Img](https://c.example/three.png)',
                    remoteImagesApproved: approvedByHost,
                    delegates: MarkdownBuilderDelegates(
                      imagePolicy: MarkdownImagePolicy.ask,
                      onLoadRemoteImages: () =>
                          setState(() => approvedByHost = true),
                      imageBuilder: (BuildContext context, ImageNode node) =>
                          Text('HOST-LOADED:${node.destination}'),
                    ),
                  ),
                ),
              );
            },
          ),
        );

        expect(find.text('Load remote images'), findsOneWidget);
        await tester.tap(find.text('Load remote images'));
        await tester.pump();
        expect(
          find.text('HOST-LOADED:https://c.example/three.png'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'normalizes obfuscated, bracketed, protocol-relative, ftp, smb, and file image URLs before imageBuilder',
      (WidgetTester tester) async {
        expect(
          MarkdownBuilderDelegates.isRemoteImageUrl(
            'ht\ttp://evil.example/a.png',
          ),
          isTrue,
        );
        expect(
          MarkdownBuilderDelegates.isRemoteImageUrl(
            '< https://evil.example/b.png >',
          ),
          isTrue,
        );
        expect(
          MarkdownBuilderDelegates.isRemoteImageUrl('//evil.example/c.png'),
          isTrue,
        );
        expect(
          MarkdownBuilderDelegates.isRemoteImageUrl(r'/\evil.example/d.png'),
          isTrue,
        );
        expect(
          MarkdownBuilderDelegates.isRemoteImageUrl(
            'ftp://files.example/e.png',
          ),
          isTrue,
        );
        expect(
          MarkdownBuilderDelegates.isRemoteImageUrl('smb://nas/share/f.png'),
          isTrue,
        );
        expect(
          MarkdownBuilderDelegates.isRemoteImageUrl('file:///etc/passwd'),
          isTrue,
        );
        expect(
          MarkdownBuilderDelegates.isRemoteImageUrl('assets/local_logo.png'),
          isFalse,
        );

        final List<String> builtUrls = <String>[];
        const MarkdownUrlPolicy permissiveNonScript = MarkdownUrlPolicy(
          blockedSchemes: <String>{'javascript', 'vbscript'},
          allowProtocolRelative: true,
        );
        const String md =
            '![Obf](<ht\ttp://evil.example/obf.png>)\n\n'
            '![Ftp](ftp://evil.example/a.png)\n\n'
            '![Smb](smb://evil.example/b.png)\n\n'
            '![File](file:///etc/passwd)\n\n'
            '![Local](assets/local.png)';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                md,
                options: const MarkdownOptions.gfm(
                  sanitizeUrls: false,
                  urlPolicy: permissiveNonScript,
                ),
                scrollable: false,
                delegates: MarkdownBuilderDelegates(
                  imagePolicy: MarkdownImagePolicy.block,
                  urlPolicy: permissiveNonScript,
                  imageBuilder: (BuildContext context, ImageNode node) {
                    builtUrls.add(node.destination);
                    return Text('LOCAL:${node.destination}');
                  },
                ),
              ),
            ),
          ),
        );

        expect(builtUrls, <String>['assets/local.png']);
        expect(find.text('LOCAL:assets/local.png'), findsOneWidget);
        expect(find.text('Load remote images'), findsNothing);
      },
    );

    testWidgets(
      'renders safely with selectable: true inside pure WidgetsApp without MaterialLocalizations',
      (WidgetTester tester) async {
        // Without Navigator/Overlay, MarkdownView degrades safely to non-crash content.
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFFFFFFFF),
            builder: (BuildContext context, Widget? child) {
              return const MarkdownTheme(
                data: MarkdownThemeData.light(),
                child: MarkdownView(
                  '# Bare WidgetsApp\n\nRenders without MaterialLocalizations or Overlay.',
                  selectable: true,
                  scrollable: false,
                ),
              );
            },
          ),
        );

        expect(find.byType(SelectionArea), findsNothing);
        expect(find.text('Bare WidgetsApp'), findsOneWidget);

        // With routed WidgetsApp (Navigator provides Overlay, still zero MaterialLocalizations),
        // MarkdownView uses SelectableRegion directly without crashing.
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFFFFFFFF),
            pageRouteBuilder:
                <T>(RouteSettings settings, WidgetBuilder builder) =>
                    PageRouteBuilder<T>(
                      settings: settings,
                      pageBuilder:
                          (
                            BuildContext ctx,
                            Animation<double> a,
                            Animation<double> b,
                          ) => builder(ctx),
                    ),
            home: const MarkdownTheme(
              data: MarkdownThemeData.light(),
              child: MarkdownView(
                '# Pure WidgetsApp\n\nSelectable prose without Material.',
                selectable: true,
                scrollable: false,
              ),
            ),
          ),
        );

        expect(find.byType(SelectionArea), findsNothing);
        expect(find.byType(SelectableRegion), findsOneWidget);
        expect(find.text('Pure WidgetsApp'), findsOneWidget);
        expect(find.text('Selectable prose without Material.'), findsOneWidget);
      },
    );

    testWidgets(
      'excludes non-prose UI chrome from selection and exports clean plain text on Cmd+A / Copy',
      (WidgetTester tester) async {
        String? clipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                clipboardText = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final FocusNode focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        const String docSource = '''
# Chrome Exclusion

- Bullet item
- [x] Checked task

> [!NOTE]
> Alert body text.

```dart
final int x = 1;
```

<details open>
<summary>Toggle details</summary>

Inside details body[^1].

</details>

![Remote](https://example.com/pixel.png)

[^1]: Footnote body text.
''';

        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                docSource,
                options: const MarkdownOptions.extended(),
                controller: controller,
                focusNode: focusNode,
                delegates: const MarkdownBuilderDelegates(
                  imagePolicy: MarkdownImagePolicy.ask,
                ),
              ),
            ),
          ),
        );

        // Chrome widgets sit inside SelectionContainer.disabled.
        for (final String chrome in <String>[
          'Copy',
          'dart',
          '•',
          '✓',
          'Note',
          '▾',
          '↩',
          'Load remote images',
        ]) {
          final Finder chromeFinder = find.text(chrome);
          expect(chromeFinder, findsOneWidget, reason: 'Missing "$chrome"');
          expect(
            find.ancestor(
              of: chromeFinder,
              matching: find.byWidgetPredicate(
                (Widget w) => w is SelectionContainer && w.delegate == null,
              ),
            ),
            findsWidgets,
            reason:
                'Chrome "$chrome" must be inside SelectionContainer.disabled',
          );
        }

        // Select All + Copy via focusNode Actions exports exact document plain text.
        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();

        expect(clipboardText, controller.document.toPlainText());
        expect(clipboardText, isNot(contains('Load remote images')));
        expect(clipboardText, isNot(contains('↩')));
      },
    );

    testWidgets(
      'verifies headingLevel, table headers, single-speak abbr, linked WidgetSpan semantics, and FocusableActionDetector keyboard activation',
      (WidgetTester tester) async {
        final SemanticsHandle semanticsHandle = tester.ensureSemantics();
        try {
          String? copiedCode;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (
                MethodCall call,
              ) async {
                if (call.method == 'Clipboard.setData') {
                  final Map<Object?, Object?> args =
                      call.arguments as Map<Object?, Object?>;
                  copiedCode = args['text'] as String?;
                }
                return null;
              });
          addTearDown(() {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null);
          });

          int loadRemoteCalls = 0;
          final List<String> tappedLinks = <String>[];
          const String doc = r'''
### Level Three Heading

| Name | Role |
| :--- | :--- |
| Alice | Maintainer |

- [x] Done task

Inspect AST inside [$x$](https://example.com/math) link.

*[AST]: Abstract Syntax Tree

```python
print("ok")
```

<details>
<summary>Expand section</summary>

Hidden keyboard body[^k1].

</details>

![Img](https://example.com/pic.png)

[^k1]: Footnote target.
''';

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: MarkdownView(
                    doc,
                    options: const MarkdownOptions.extended(),
                    scrollable: false,
                    selectable: false,
                    delegates: MarkdownBuilderDelegates(
                      imagePolicy: MarkdownImagePolicy.ask,
                      onLoadRemoteImages: () => loadRemoteCalls++,
                      onTapLink: (String dest, String? _) =>
                          tappedLinks.add(dest),
                    ),
                  ),
                ),
              ),
            ),
          );

          // Heading exposes header + headingLevel: 3.
          final Semantics headingSem = tester.widget<Semantics>(
            find
                .ancestor(
                  of: find.text('Level Three Heading'),
                  matching: find.byWidgetPredicate(
                    (Widget w) => w is Semantics && w.properties.header == true,
                  ),
                )
                .first,
          );
          expect(headingSem.properties.headingLevel, 3);

          // Table header cell exposes Semantics(header: true, container: true).
          final Semantics tableHeaderSem = tester.widget<Semantics>(
            find
                .ancestor(
                  of: find.text('Name'),
                  matching: find.byWidgetPredicate(
                    (Widget w) =>
                        w is Semantics &&
                        w.properties.header == true &&
                        w.container == true,
                  ),
                )
                .first,
          );
          expect(tableHeaderSem.properties.header, isTrue);

          // Task checkbox exposes checked + readOnly.
          final Semantics taskSem = tester.widget<Semantics>(
            find
                .ancestor(
                  of: find.text('✓'),
                  matching: find.byWidgetPredicate(
                    (Widget w) =>
                        w is Semantics && w.properties.checked == true,
                  ),
                )
                .first,
          );
          expect(taskSem.properties.readOnly, isTrue);

          // <abbr> Tooltip has excludeFromSemantics: true and outer Semantics has excludeSemantics: true.
          final Tooltip abbrTooltip = tester.widget<Tooltip>(
            find.byType(Tooltip),
          );
          expect(abbrTooltip.excludeFromSemantics, isTrue);
          final Semantics abbrSem = tester.widget<Semantics>(
            find
                .ancestor(
                  of: find.byType(Tooltip),
                  matching: find.byWidgetPredicate(
                    (Widget w) =>
                        w is Semantics && w.properties.tooltip != null,
                  ),
                )
                .first,
          );
          expect(abbrSem.excludeSemantics, isTrue);
          expect(abbrSem.properties.hint, isNull);

          // Linked WidgetSpan exposes Semantics(link: true).
          expect(
            find.ancestor(
              of: find.text('x'),
              matching: find.byWidgetPredicate(
                (Widget w) => w is Semantics && w.properties.link == true,
              ),
            ),
            findsOneWidget,
          );

          // Interactive Copy, <details>, Load remote images use FocusableActionDetector & Enter/ActivateIntent activates.
          final Finder copyDetectorFinder = find.ancestor(
            of: find.text('Copy'),
            matching: find.byType(FocusableActionDetector),
          );
          expect(copyDetectorFinder, findsOneWidget);
          Focus.of(tester.element(find.text('Copy'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(copiedCode, 'print("ok")\n');

          final Finder detailsDetectorFinder = find.ancestor(
            of: find.text('Expand section'),
            matching: find.byType(FocusableActionDetector),
          );
          expect(detailsDetectorFinder, findsOneWidget);
          Actions.invoke(
            tester.element(find.text('Expand section')),
            const ActivateIntent(),
          );
          await tester.pump();
          expect(find.textContaining('Hidden keyboard body'), findsOneWidget);

          final Finder loadDetectorFinder = find.ancestor(
            of: find.text('Load remote images'),
            matching: find.byType(FocusableActionDetector),
          );
          expect(loadDetectorFinder, findsOneWidget);
          Actions.invoke(
            tester.element(find.text('Load remote images')),
            const ActivateIntent(),
          );
          await tester.pump();
          expect(loadRemoteCalls, 1);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'renders <a name>, <img width/height>, <u>, <small>, <q>, reuses recognizers, caches data:image bytes, and preserves #fragment scroll',
      (WidgetTester tester) async {
        // Minimal 1x1 transparent PNG data URI.
        const String oneByOnePngDataUri =
            'data:image/png;base64,'
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        final List<String> linkEvents = <String>[];
        bool isDark = false;
        String source =
            'Before <u>under</u> <small>tiny</small> <q>quote</q> '
            '[Link A](https://example.com/a) '
            '[Jump](#named-anchor)\n\n'
            '<img src="$oneByOnePngDataUri" width="72" height="48" alt="Inline Pic">\n\n'
            '<a name="named-anchor"></a>Anchored paragraph.';

        late StateSetter rebuild;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return MaterialApp(
                home: Scaffold(
                  body: MarkdownTheme(
                    data: isDark
                        ? const MarkdownThemeData.dark()
                        : const MarkdownThemeData.light(),
                    child: MarkdownView(
                      source,
                      options: const MarkdownOptions.extended(
                        urlPolicy: MarkdownUrlPolicy.strict(
                          allowSafeImageDataUrls: true,
                        ),
                      ),
                      controller: controller,
                      scrollable: false,
                      selectable: false,
                      delegates: MarkdownBuilderDelegates(
                        urlPolicy: const MarkdownUrlPolicy.strict(
                          allowSafeImageDataUrls: true,
                        ),
                        onTapLink: (String dest, String? _) =>
                            linkEvents.add(dest),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );

        // Verify <u>, <small>, <q> styling and text.
        final RichText proseRich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (Widget w) =>
                w is RichText && w.text.toPlainText().contains('under'),
          ),
        );
        final String prosePlain = proseRich.text.toPlainText();
        expect(prosePlain, contains('\u201Cquote\u201D'));
        bool sawUnderline = false;
        bool sawSmall = false;
        GestureRecognizer? firstLinkRecognizer;
        proseRich.text.visitChildren((InlineSpan span) {
          if (span is TextSpan) {
            if (span.text == 'under' &&
                span.style?.decoration != null &&
                span.style!.decoration!.contains(TextDecoration.underline)) {
              sawUnderline = true;
            }
            if (span.text == 'tiny' &&
                span.style?.fontSize != null &&
                span.style!.fontSize! < 15.0) {
              sawSmall = true;
            }
            if (span.text == 'Link A') {
              firstLinkRecognizer = span.recognizer;
            }
          }
          return true;
        });
        expect(sawUnderline, isTrue);
        expect(sawSmall, isTrue);
        expect(firstLinkRecognizer, isA<TapGestureRecognizer>());

        // Verify <img width="72" height="48"> dimensions and decoded bytes.
        final Image imgWidget = tester.widget<Image>(find.byType(Image));
        expect(imgWidget.width, 72.0);
        expect(imgWidget.height, 48.0);
        final Uint8List firstBytes = (imgWidget.image as MemoryImage).bytes;

        // Verify #fragment link triggers BOTH automatic controller scroll AND onTapLink.
        final Finder jumpFinder = find.byWidgetPredicate(
          (Widget w) => w is RichText && w.text.toPlainText().contains('Jump'),
        );
        final RenderParagraph jumpPara = tester.renderObject<RenderParagraph>(
          jumpFinder,
        );
        final int jumpIdx = jumpPara.text.toPlainText().indexOf('Jump');
        final List<TextBox> jumpBoxes = jumpPara.getBoxesForSelection(
          TextSelection(baseOffset: jumpIdx, extentOffset: jumpIdx + 4),
        );
        await tester.tapAt(
          jumpPara.localToGlobal(jumpBoxes.first.toRect().center),
        );
        await tester.pumpAndSettle();
        expect(linkEvents, <String>['#named-anchor']);

        // Toggle theme -> recognizer AND cached data:image Uint8List are reused identically.
        rebuild(() => isDark = true);
        await tester.pump();

        final RichText darkProseRich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (Widget w) =>
                w is RichText && w.text.toPlainText().contains('Link A'),
          ),
        );
        GestureRecognizer? secondLinkRecognizer;
        darkProseRich.text.visitChildren((InlineSpan span) {
          if (span is TextSpan && span.text == 'Link A') {
            secondLinkRecognizer = span.recognizer;
          }
          return true;
        });
        expect(identical(firstLinkRecognizer, secondLinkRecognizer), isTrue);

        final Image darkImgWidget = tester.widget<Image>(find.byType(Image));
        final Uint8List secondBytes =
            (darkImgWidget.image as MemoryImage).bytes;
        expect(identical(firstBytes, secondBytes), isTrue);

        // Remove Link A and pump post-frame cleanup cleanly without error.
        rebuild(() => source = '<a name="named-anchor"></a>No links left.');
        await tester.pumpAndSettle();
        expect(find.textContaining('No links left.'), findsOneWidget);
      },
    );
  });
}
