import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine/markdown_engine.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
import 'package:markdown_engine_flutter/src/fast_text.dart'
    show
        MarkdownParagraphLeaf,
        RenderMarkdownParagraph,
        compareScreenOrderRects;
import 'package:markdown_engine_flutter/src/html_block_renderer.dart'
    show
        HtmlBlockEntry,
        decodeHtmlEntities,
        maxHtmlColspan,
        maxHtmlTableRows,
        parseHtmlBlockFragment;
import 'package:markdown_engine_flutter/src/inline_renderer.dart'
    show MarkdownAnchorTarget, MarkdownInlineText;
import 'package:tex_math_flutter/tex_math_flutter.dart' show TexMath;

void main() {
  group('Enclosing link tap targets', () {
    testWidgets(
      'tapping bold, code, highlight, and inline math children inside a link invokes onTapLink',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
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

        // Tap the inline math WidgetSpan child (`TexMath`).
        expect(find.byType(TexMath), findsOneWidget);
        await tester.tapAt(tester.getCenter(find.byType(TexMath)));
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
        expect(
          find.textContaining('Footnote explanation body.'),
          findsOneWidget,
        );
        expect(find.text('↩\uFE0E'), findsOneWidget);
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
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
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

        expect(find.byType(TexMath), findsOneWidget);
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
                      pageBuilder: (
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
          '↩\uFE0E',
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
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
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
              of: find.byType(TexMath),
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

  group('Layout-guarded rich text selection invariants', () {
    testWidgets(
      'post-frame dirty layout race while selectables flush avoids assertions and sorts cleanly on next frame',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

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
        addTearDown(focusNode.dispose);
        String source = 'Alpha \$x^2\$ <kbd>K</kbd> omega';
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: MarkdownView(
                    source,
                    options: const MarkdownOptions.extended(),
                    focusNode: focusNode,
                    scrollable: false,
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        // Schedule a post-frame callback that dirties the MarkdownRichText's
        // RenderParagraph on the exact frame selectables flush during SelectAll
        // + sibling block insertion.
        final RenderParagraph richPara = tester
            .renderObjectList<RenderParagraph>(
              find.byWidgetPredicate(
                (Widget w) =>
                    w is RichText && w.text.toPlainText().contains('Alpha'),
              ),
            )
            .first;

        SchedulerBinding.instance.addPostFrameCallback((Duration _) {
          richPara.markNeedsLayout();
        });
        rebuildHost(() {
          source = 'Alpha \$x^2\$ <kbd>K</kbd> omega\n\nSibling \$y^2\$ line';
        });
        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);

        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(copiedClipboard, isNotNull);
        final int alphaIdx = copiedClipboard!.indexOf('Alpha');
        final int kIdx = copiedClipboard!.indexOf('K', alphaIdx);
        final int omegaIdx = copiedClipboard!.indexOf('omega', kIdx);
        final int siblingIdx = copiedClipboard!.indexOf('Sibling', omegaIdx);
        expect(alphaIdx, greaterThanOrEqualTo(0));
        expect(kIdx, greaterThan(alphaIdx));
        expect(omegaIdx, greaterThan(kIdx));
        expect(siblingIdx, greaterThan(omegaIdx));
      },
    );

    testWidgets(
      'triple-click, SelectParagraphSelectionEvent, paragraph-granularity edge updates, backward drag across WidgetSpans, and wrapped multi-line WidgetSpan layout preserve reading order',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

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
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600.0,
                height: 400.0,
                child: MarkdownView(
                  'Start \$x^2\$ <kbd>Cmd</kbd> H~2~O end.\n\nSecond paragraph.',
                  options: const MarkdownOptions.extended(),
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final Finder firstParaFinder = find.byWidgetPredicate(
          (Widget w) =>
              w is MarkdownRichText &&
              w.textSpan != null &&
              w.textSpan!.toPlainText().contains('Start'),
        );
        expect(firstParaFinder, findsOneWidget);
        final Rect firstParaRect = tester.getRect(firstParaFinder);

        // 1. Triple-click across WidgetSpans selects the full paragraph.
        final Offset tapPos =
            firstParaRect.centerLeft + const Offset(10.0, 0.0);
        await tester.tapAt(tapPos, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(tapPos, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(tapPos, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);

        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(copiedClipboard, isNotNull);
        expect(copiedClipboard, contains('Start'));
        expect(copiedClipboard, contains('Cmd'));
        expect(copiedClipboard, contains('end.'));

        // 2. Direct SelectParagraphSelectionEvent & SelectionEdgeUpdateEvent
        // with TextGranularity.paragraph on MarkdownRichText's delegate.
        final SelectionContainer richContainer = tester
            .widget<SelectionContainer>(
              find
                  .descendant(
                    of: firstParaFinder,
                    matching: find.byType(SelectionContainer),
                  )
                  .first,
            );
        final SelectionContainerDelegate richDelegate = richContainer.delegate!;
        expect(
          richDelegate.dispatchSelectionEvent(
            SelectParagraphSelectionEvent(globalPosition: tapPos),
          ),
          isNotNull,
        );
        richDelegate.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forStart(
            globalPosition: firstParaRect.centerLeft + const Offset(2.0, 0.0),
            granularity: TextGranularity.paragraph,
          ),
        );
        richDelegate.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forEnd(
            globalPosition: firstParaRect.centerRight - const Offset(2.0, 0.0),
            granularity: TextGranularity.paragraph,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final SelectedContent? paraContent = richDelegate.getSelectedContent();
        expect(paraContent, isNotNull);
        expect(paraContent!.plainText, contains('Start'));
        expect(paraContent.plainText, contains('Cmd'));
        expect(paraContent.plainText, contains('end.'));

        // 3. Backward drag across TexMath, <kbd>, and ~sub~ selects cleanly in
        // forward reading order.
        richDelegate.dispatchSelectionEvent(const ClearSelectionEvent());
        await tester.pump();
        final TestGesture backDrag = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(backDrag.removePointer);
        await backDrag.down(firstParaRect.centerRight - const Offset(4.0, 0.0));
        await tester.pump();
        await backDrag.moveTo(
          firstParaRect.centerLeft + const Offset(4.0, 0.0),
        );
        await tester.pump();
        await backDrag.up();
        await tester.pump();
        copiedClipboard = null;
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(copiedClipboard, isNotNull);
        final int startIdx = copiedClipboard!.indexOf('Start');
        final int cmdIdx = copiedClipboard!.indexOf('Cmd', startIdx);
        final int endIdx = copiedClipboard!.indexOf('end.', cmdIdx);
        expect(startIdx, greaterThanOrEqualTo(0));
        expect(cmdIdx, greaterThan(startIdx));
        expect(endIdx, greaterThan(cmdIdx));

        // 4. Wrapped multi-line paragraph around a WidgetSpan maintains
        // left-to-right screen order on copy.
        final FocusNode wrapFocus = FocusNode();
        addTearDown(wrapFocus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 170.0,
                height: 400.0,
                child: MarkdownView(
                  'Left prefix words <kbd>MID</kbd> right suffix words wrap cleanly',
                  options: const MarkdownOptions.extended(),
                  focusNode: wrapFocus,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        wrapFocus.requestFocus();
        await tester.pump();
        Actions.invoke(
          wrapFocus.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        copiedClipboard = null;
        Actions.invoke(wrapFocus.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(copiedClipboard, isNotNull);
        final int lIdx = copiedClipboard!.indexOf('Left prefix words');
        final int mIdx = copiedClipboard!.indexOf('MID', lIdx);
        final int rIdx = copiedClipboard!.indexOf('right suffix words', mIdx);
        expect(lIdx, greaterThanOrEqualTo(0));
        expect(mIdx, greaterThan(lIdx));
        expect(rIdx, greaterThan(mIdx));
      },
    );

    testWidgets(
      'DirectionallyExtendSelectionEvent (all 4 directions) and GranularlyExtendSelectionEvent (forward/backward) while dirty throw zero assertion errors',
      (WidgetTester tester) async {
        final FocusNode focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500.0,
                height: 300.0,
                child: MarkdownView(
                  'First <kbd>K</kbd> line.\n\nPlain middle line.\n\nSecond <kbd>Alt</kbd> line.',
                  options: const MarkdownOptions.extended(),
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();

        final Finder firstRichFinder = find.byWidgetPredicate(
          (Widget w) =>
              w is MarkdownRichText &&
              w.textSpan != null &&
              w.textSpan!.toPlainText().contains('First'),
        );
        expect(firstRichFinder, findsOneWidget);
        final SelectionContainerDelegate outerDelegate = tester
            .widget<SelectionContainer>(find.byType(SelectionContainer).first)
            .delegate!;
        final SelectionContainerDelegate richDelegate = tester
            .widget<SelectionContainer>(
              find
                  .descendant(
                    of: firstRichFinder,
                    matching: find.byType(SelectionContainer),
                  )
                  .first,
            )
            .delegate!;

        // Dirty all RenderParagraph / RenderMarkdownParagraph objects right
        // before dispatching directional & granular selection extension events.
        for (final RenderObject ro in tester.allRenderObjects) {
          if (ro is RenderParagraph || ro is RenderBox) {
            if (ro is RenderParagraph) {
              ro.markNeedsLayout();
            } else if ('${ro.runtimeType}' == 'RenderMarkdownParagraph') {
              ro.markNeedsLayout();
            }
          }
        }

        for (final SelectionExtendDirection dir
            in SelectionExtendDirection.values) {
          richDelegate.dispatchSelectionEvent(
            DirectionallyExtendSelectionEvent(
              dx: 40.0,
              isEnd: true,
              direction: dir,
            ),
          );
          outerDelegate.dispatchSelectionEvent(
            DirectionallyExtendSelectionEvent(
              dx: 40.0,
              isEnd: true,
              direction: dir,
            ),
          );
        }
        for (final bool forward in <bool>[true, false]) {
          richDelegate.dispatchSelectionEvent(
            GranularlyExtendSelectionEvent(
              forward: forward,
              isEnd: true,
              granularity: TextGranularity.character,
            ),
          );
          outerDelegate.dispatchSelectionEvent(
            GranularlyExtendSelectionEvent(
              forward: forward,
              isEnd: true,
              granularity: TextGranularity.word,
            ),
          );
        }

        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'MarkdownView(scrollable: true) SelectAll and Copy survive dirty MarkdownRichText and empty heading FastMarkdownText',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

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
        addTearDown(focusNode.dispose);
        String source =
            'Alpha \$x^2\$ <kbd>K</kbd> omega\n\n# \n\nInitial middle\n\nOmega \$y^2\$ <kbd>M</kbd> tail';
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 560.0,
                    height: 360.0,
                    child: MarkdownView(
                      source,
                      options: const MarkdownOptions.extended(),
                      focusNode: focusNode,
                      scrollable: true,
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        final List<RenderParagraph> richParas = tester
            .renderObjectList<RenderParagraph>(
              find.byWidgetPredicate(
                (Widget w) =>
                    w is RichText &&
                    (w.text.toPlainText().contains('Alpha') ||
                        w.text.toPlainText().contains('Omega')),
              ),
            )
            .toList(growable: false);
        final List<RenderMarkdownParagraph> leafParas = tester
            .renderObjectList<RenderMarkdownParagraph>(
              find.byType(MarkdownParagraphLeaf),
            )
            .toList(growable: false);
        expect(richParas.length, greaterThanOrEqualTo(2));
        expect(leafParas, isNotEmpty);

        // Dirty first and last MarkdownRichText plus empty heading leaf right
        // before SelectAll fires under Scrollable.
        SchedulerBinding.instance.addPostFrameCallback((Duration _) {
          for (final RenderParagraph p in richParas) {
            if (p.attached) {
              p.markNeedsLayout();
            }
          }
          for (final RenderMarkdownParagraph p in leafParas) {
            if (p.attached) {
              p.markNeedsLayout();
            }
          }
        });
        rebuildHost(() {
          source = 'Alpha \$x^2\$ <kbd>K</kbd> omega\n\n# \n\nMiddle line\n\nOmega \$y^2\$ <kbd>M</kbd> tail';
        });
        focusNode.requestFocus();
        await tester.pump();

        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        expect(tester.takeException(), isNull);

        // Copy immediately while pending and again after deferred layout flush.
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(copiedClipboard, isNotNull);
        expect(copiedClipboard, contains('Alpha'));
        expect(copiedClipboard, contains('K'));
        expect(copiedClipboard, contains('omega'));
        expect(copiedClipboard, contains('Omega'));
        expect(copiedClipboard, contains('M'));
        expect(copiedClipboard, contains('tail'));

        await tester.pump();
        copiedClipboard = null;
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(copiedClipboard, contains('Middle line'));
      },
    );

    testWidgets(
      'Direct MarkdownRichText under SingleChildScrollView handles pending SelectAll, immediate Copy, and clear',
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
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400.0,
                height: 240.0,
                child: SelectionArea(
                  focusNode: focusNode,
                  child: const SingleChildScrollView(
                    child: MarkdownRichText('Dirty rich text under scrollable'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final RenderParagraph richPara = tester.renderObject<RenderParagraph>(
          find
              .byWidgetPredicate(
                (Widget w) =>
                    w is RichText &&
                    w.text.toPlainText().contains('Dirty rich text'),
              )
              .first,
        );
        final SelectionContainer richContainer = tester
            .widget<SelectionContainer>(
              find
                  .descendant(
                    of: find.byType(MarkdownRichText),
                    matching: find.byType(SelectionContainer),
                  )
                  .first,
            );
        final SelectionContainerDelegate richDelegate = richContainer.delegate!;

        richPara.markNeedsLayout();
        focusNode.requestFocus();
        await tester.pump();
        richPara.markNeedsLayout();

        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        expect(tester.takeException(), isNull);
        expect(richDelegate.value.hasSelection, isTrue);
        expect(richDelegate.value.startSelectionPoint, isNotNull);
        expect(richDelegate.value.endSelectionPoint, isNotNull);
        expect(
          richDelegate.getSelectedContent()?.plainText,
          'Dirty rich text under scrollable',
        );

        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(copiedClipboard, 'Dirty rich text under scrollable');

        richDelegate.dispatchSelectionEvent(const ClearSelectionEvent());
        expect(richDelegate.value.status, SelectionStatus.none);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Empty heading # handles DirectionallyExtendSelectionEvent backward/forward, document granularity, and padded FastMarkdownText vertical extend under Scrollable',
      (WidgetTester tester) async {
        final FocusNode focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420.0,
                height: 300.0,
                child: MarkdownView(
                  '# \n\n> Quoted line one\n> Quoted line two\n\n# ',
                  options: const MarkdownOptions.extended(),
                  focusNode: focusNode,
                  scrollable: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        focusNode.requestFocus();
        await tester.pump();

        final SelectionContainerDelegate outerDelegate = tester
            .widget<SelectionContainer>(find.byType(SelectionContainer).first)
            .delegate!;

        // Empty heading # at start and end: backward/forward must satisfy
        // MultiSelectableSelectionContainerDelegate's assert(result == end).
        for (final SelectionExtendDirection dir
            in SelectionExtendDirection.values) {
          outerDelegate.dispatchSelectionEvent(
            DirectionallyExtendSelectionEvent(
              dx: 24.0,
              isEnd: true,
              direction: dir,
            ),
          );
        }
        expect(tester.takeException(), isNull);

        // Also test direct dispatch on RenderMarkdownParagraph's empty #
        // selectable and padded blockquote selectable.
        final List<RenderMarkdownParagraph> paragraphs = tester
            .renderObjectList<RenderMarkdownParagraph>(
              find.byType(MarkdownParagraphLeaf),
            )
            .toList(growable: false);
        expect(paragraphs.length, greaterThanOrEqualTo(3));

        // SelectAll then extend across empty headings, padded blockquote lines,
        // and document bounds.
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        for (final SelectionExtendDirection dir
            in SelectionExtendDirection.values) {
          outerDelegate.dispatchSelectionEvent(
            DirectionallyExtendSelectionEvent(
              dx: 48.0,
              isEnd: true,
              direction: dir,
            ),
          );
        }
        for (final bool forward in <bool>[true, false]) {
          outerDelegate.dispatchSelectionEvent(
            GranularlyExtendSelectionEvent(
              forward: forward,
              isEnd: true,
              granularity: TextGranularity.document,
            ),
          );
        }
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Verify empty heading # child selectable directly under a
        // MultiSelectableSelectionContainerDelegate returns SelectionResult.end
        // for backward/forward and previous/next for previousLine/nextLine.
        final FocusNode emptyFocus = FocusNode();
        addTearDown(emptyFocus.dispose);
        String emptyText = 'A';
        late StateSetter rebuildEmptyHost;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildEmptyHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 300.0,
                    height: 120.0,
                    child: SelectionArea(
                      focusNode: emptyFocus,
                      child: Builder(
                        builder: (BuildContext ctx) {
                          return MarkdownParagraphLeaf(
                            text: TextSpan(text: emptyText),
                            plainText: emptyText,
                            textAlign: TextAlign.start,
                            textDirection: TextDirection.ltr,
                            textScaler: TextScaler.noScaling,
                            registrar: SelectionContainer.maybeOf(ctx),
                            selectionColor: Colors.blue,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();
        await tester.pump();
        final MultiSelectableSelectionContainerDelegate nonScrollDelegate =
            tester
                    .widget<SelectionContainer>(
                      find.byType(SelectionContainer).last,
                    )
                    .delegate!
                as MultiSelectableSelectionContainerDelegate;
        expect(nonScrollDelegate.selectables, hasLength(1));
        final Selectable emptySelectable = nonScrollDelegate.selectables.single;
        emptyFocus.requestFocus();
        await tester.pump();
        Actions.invoke(
          emptyFocus.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();

        // Transition leaf from 'A' to empty '' and dispatch directional extend
        // inside a pre-scheduled post-frame callback (after full layout/paint,
        // before post-frame unregistration completes) so Flutter's
        // assert(result == SelectionResult.end) is exercised directly.
        bool ranEmptyExtend = false;
        SchedulerBinding.instance.addPostFrameCallback((Duration _) {
          ranEmptyExtend = true;
          for (final SelectionExtendDirection dir
              in SelectionExtendDirection.values) {
            nonScrollDelegate.dispatchSelectionEvent(
              DirectionallyExtendSelectionEvent(
                dx: 0.0,
                isEnd: true,
                direction: dir,
              ),
            );
          }
        });
        rebuildEmptyHost(() {
          emptyText = '';
        });
        await tester.pump();
        expect(ranEmptyExtend, isTrue);
        expect(
          emptySelectable.dispatchSelectionEvent(
            const DirectionallyExtendSelectionEvent(
              dx: 0.0,
              isEnd: true,
              direction: SelectionExtendDirection.backward,
            ),
          ),
          SelectionResult.end,
        );
        expect(
          emptySelectable.dispatchSelectionEvent(
            const DirectionallyExtendSelectionEvent(
              dx: 0.0,
              isEnd: true,
              direction: SelectionExtendDirection.forward,
            ),
          ),
          SelectionResult.end,
        );
        expect(
          emptySelectable.dispatchSelectionEvent(
            const DirectionallyExtendSelectionEvent(
              dx: 0.0,
              isEnd: true,
              direction: SelectionExtendDirection.previousLine,
            ),
          ),
          SelectionResult.previous,
        );
        expect(
          emptySelectable.dispatchSelectionEvent(
            const DirectionallyExtendSelectionEvent(
              dx: 0.0,
              isEnd: true,
              direction: SelectionExtendDirection.nextLine,
            ),
          ),
          SelectionResult.next,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'FastMarkdownText unsized SelectAll, didUpdateContent while selected, and padded DirectionallyExtendSelectionEvent update geometry cleanly',
      (WidgetTester tester) async {
        final FocusNode focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        String text = 'AB';
        bool skipChildLayout = true;
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 400.0,
                    height: 200.0,
                    child: SelectionArea(
                      focusNode: focusNode,
                      child: SingleChildScrollView(
                        child: _UnsizedChildHost(
                          skipLayout: skipChildLayout,
                          child: Builder(
                            builder: (BuildContext ctx) {
                              return MarkdownParagraphLeaf(
                                text: TextSpan(text: text),
                                plainText: text,
                                textAlign: TextAlign.start,
                                textDirection: TextDirection.ltr,
                                textScaler: TextScaler.noScaling,
                                registrar: SelectionContainer.maybeOf(ctx),
                                selectionColor: Colors.blue,
                                contentPadding: const EdgeInsets.only(
                                  left: 40.0,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        final RenderMarkdownParagraph leaf = tester
            .renderObject<RenderMarkdownParagraph>(
              find.byType(MarkdownParagraphLeaf, skipOffstage: false),
            );
        expect(leaf.attached, isTrue);
        expect(leaf.hasSize, isFalse);

        // SelectAll while RenderMarkdownParagraph is unsized (!hasSize).
        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        final MultiSelectableSelectionContainerDelegate scrollDelegate =
            tester
                    .widget<SelectionContainer>(
                      find.byType(SelectionContainer).last,
                    )
                    .delegate!
                as MultiSelectableSelectionContainerDelegate;
        final Selectable leafSelectable = scrollDelegate.selectables.single;
        expect(leafSelectable.value.status, SelectionStatus.uncollapsed);
        expect(leafSelectable.value.startSelectionPoint, isNotNull);
        expect(leafSelectable.value.endSelectionPoint, isNotNull);

        // Reveal (performLayout runs -> didChangeLayout updates real geometry).
        rebuildHost(() {
          skipChildLayout = false;
        });
        await tester.pump();
        await tester.pump();
        expect(leaf.hasSize, isTrue);
        expect(
          leafSelectable.value.endSelectionPoint!.localPosition.dx,
          greaterThan(40.0),
        );

        // Mutate text to a different string while selected (didUpdateContent).
        rebuildHost(() {
          text = 'CD';
        });
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(leafSelectable.getSelectedContent()?.plainText, 'CD');

        // Document granularity bounds return next/previous cleanly.
        expect(
          leafSelectable.dispatchSelectionEvent(
            const GranularlyExtendSelectionEvent(
              forward: true,
              isEnd: true,
              granularity: TextGranularity.document,
            ),
          ),
          SelectionResult.next,
        );
        expect(
          leafSelectable.dispatchSelectionEvent(
            const GranularlyExtendSelectionEvent(
              forward: false,
              isEnd: true,
              granularity: TextGranularity.document,
            ),
          ),
          SelectionResult.previous,
        );
        expect(leafSelectable.getSelection()?.endOffset, 0);

        // Padded vertical directional extend subtracts _padLeft (40.0).
        rebuildHost(() {
          text = 'First line words\nSecond line words';
        });
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        final double leafLeft = leaf.localToGlobal(Offset.zero).dx;
        expect(
          leafSelectable.dispatchSelectionEvent(
            DirectionallyExtendSelectionEvent(
              dx: leafLeft + 40.0,
              isEnd: true,
              direction: SelectionExtendDirection.previousLine,
            ),
          ),
          SelectionResult.end,
        );
        expect(leafSelectable.getSelection()?.endOffset, 0);
        expect(
          leafSelectable.dispatchSelectionEvent(
            DirectionallyExtendSelectionEvent(
              dx: leafLeft + 40.0,
              isEnd: true,
              direction: SelectionExtendDirection.nextLine,
            ),
          ),
          SelectionResult.end,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Non-scrollable MarkdownView inside SelectionArea + SingleChildScrollView survives dirty SelectAll, spacing overrides, and sub-0.005px extent changes',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final FocusNode focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        double width = 400.0;
        late StateSetter rebuildHost;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (BuildContext _, StateSetter setState) {
              rebuildHost = setState;
              return MaterialApp(
                home: Scaffold(
                  body: MediaQuery(
                    data: const MediaQueryData(
                      lineHeightScaleFactorOverride: 1.3,
                      letterSpacingOverride: 1.2,
                      wordSpacingOverride: 1.5,
                    ),
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          width: width,
                          height: 150.0,
                          child: SelectionArea(
                            focusNode: focusNode,
                            child: const SingleChildScrollView(
                              child: MarkdownView(
                                'Inline \$x^2\$ <kbd>Space</kbd> text',
                                options: MarkdownOptions.extended(),
                                scrollable: false,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          height: 150.0,
                          child: const MarkdownView(
                            'Scrollable paragraph wrapping check at fractional width',
                            scrollable: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pump();

        final RenderParagraph richPara = tester.renderObject<RenderParagraph>(
          find
              .byWidgetPredicate(
                (Widget w) =>
                    w is RichText && w.text.toPlainText().contains('Inline'),
              )
              .first,
        );
        richPara.markNeedsLayout();
        focusNode.requestFocus();
        await tester.pump();
        richPara.markNeedsLayout();

        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        expect(tester.takeException(), isNull);

        // Sub-0.005px width delta must sync extent cache cleanly.
        rebuildHost(() {
          width = 400.004;
        });
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    test('compareScreenOrderRects maintains strict weak ordering with NaN/infinite rects', () {
      const Rect r1 = Rect.fromLTRB(0.0, 0.0, 20.0, 10.0);
      const Rect r2 = Rect.fromLTRB(25.0, 3.0, 45.0, 10.0);
      const Rect r3 = Rect.fromLTRB(0.0, 20.0, 20.0, 30.0);
      const Rect nanRect = Rect.fromLTWH(double.nan, 0.0, 10.0, 10.0);
      const Rect infRect = Rect.fromLTRB(
        double.negativeInfinity,
        0.0,
        10.0,
        10.0,
      );

      expect(compareScreenOrderRects(r1, r1), 0);
      expect(compareScreenOrderRects(nanRect, nanRect), 0);
      expect(compareScreenOrderRects(nanRect, infRect), 0);
      expect(compareScreenOrderRects(nanRect, r1), -1);
      expect(compareScreenOrderRects(r1, nanRect), 1);
      expect(compareScreenOrderRects(infRect, r1), -1);
      expect(compareScreenOrderRects(r1, infRect), 1);
      expect(compareScreenOrderRects(r1, r2), -compareScreenOrderRects(r2, r1));
      expect(compareScreenOrderRects(r1, r3), -1);
      expect(compareScreenOrderRects(r3, r1), 1);

      final List<Rect> rects = <Rect>[r3, infRect, r2, nanRect, r1];
      rects.sort(compareScreenOrderRects);
      expect(rects.last, r3);
    });
  });

  group('HTML block parsing, rendering, and security', () {
    test('parseHtmlBlockFragment enforces post-tokenization entity decoding, deterministic blockIds, and budgets', () {
      expect(
        decodeHtmlEntities('A &amp; B &lt;tag&gt; &#x27;ok&#x27;'),
        "A & B <tag> 'ok'",
      );

      const String raw =
          '<table><tr><td><code>&lt;kbd&gt;</code></td></tr></table>'
          '<dl><dt>Term</dt><dd>Def</dd></dl>';
      final List<HtmlBlockEntry> entries = parseHtmlBlockFragment(
        raw,
        parentBlockId: 'b-7',
      );
      expect(entries, hasLength(2));
      expect(entries[0].block, isA<TableNode>());
      expect(entries[0].block.blockId, 'b-7-h0');
      expect(entries[1].block, isA<DefinitionListNode>());
      expect(entries[1].block.blockId, 'b-7-h1');

      final TableNode table = entries[0].block as TableNode;
      expect(table.rows.single.single.children.single, isA<CodeSpanNode>());
      expect(
        (table.rows.single.single.children.single as CodeSpanNode).literal,
        '<kbd>',
      );

      // Colspan is bounded to maxHtmlColspan (16) and row count to maxHtmlTableRows (500).
      final StringBuffer hugeTable = StringBuffer('<table>');
      for (int i = 0; i < maxHtmlTableRows + 25; i++) {
        hugeTable.write('<tr><td colspan="999">R$i</td></tr>');
      }
      hugeTable.write('</table>');
      final List<HtmlBlockEntry> boundedEntries = parseHtmlBlockFragment(
        hugeTable.toString(),
        parentBlockId: 'b-99',
      );
      expect(boundedEntries, hasLength(1));
      final TableNode boundedTable = boundedEntries.single.block as TableNode;
      expect(boundedTable.rows.length, maxHtmlTableRows);
      expect(boundedTable.rows.first.length, maxHtmlColspan);
    });

    testWidgets(
      'renders HTML <table> with alignment, literal <code>&lt;kbd&gt;</code>, <kbd> badges, thead/tbody/tfoot, caption, headerless tables, and ragged colspan',
      (WidgetTester tester) async {
        const String doc = '''
<table>
  <caption>Widget <strong>Summary</strong></caption>
  <thead>
    <tr>
      <th>Element</th>
      <th align="center">Category</th>
      <th style="text-align: right;">Example</th>
    </tr>
    <tr>
      <th>Extra</th>
      <th>Header</th>
      <th>Row</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>&lt;kbd&gt;</code></td>
      <td align="center">Inline</td>
      <td><kbd>Cmd</kbd> + <kbd>P</kbd></td>
    </tr>
    <tr>
      <td colspan="2">Spanning two</td>
      <td style="text-align: right">Right cell</td>
    </tr>
    <tr>
      <td>Ragged single cell</td>
    </tr>
  </tbody>
  <tfoot>
    <tr>
      <th>Total</th>
      <td colspan="2">3 entries</td>
    </tr>
  </tfoot>
</table>

<table>
  <tbody>
    <tr>
      <td>Headerless Alpha</td>
      <td>Headerless Beta</td>
    </tr>
  </tbody>
</table>
''';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MarkdownView(
                  doc,
                  options: MarkdownOptions.extended(),
                  scrollable: false,
                  selectable: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final Finder tables = find.byType(Table);
        expect(tables, findsNWidgets(2));

        // First table has 1 promoted header row + 1 extra thead row + 3 tbody rows + 1 tfoot row = 6 TableRows.
        final Table firstTable = tester.widget<Table>(tables.at(0));
        expect(firstTable.children, hasLength(6));
        for (final TableRow row in firstTable.children) {
          expect(row.children, hasLength(3));
        }

        // Second table is headerless -> NO phantom empty header row (1 TableRow total).
        final Table secondTable = tester.widget<Table>(tables.at(1));
        expect(secondTable.children, hasLength(1));
        expect(secondTable.children.single.children, hasLength(2));
        expect(find.text('Headerless Alpha'), findsOneWidget);
        expect(find.text('Headerless Beta'), findsOneWidget);

        // Caption sits centered and above the first Table widget.
        final Finder captionFinder = find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              w.textSpan != null &&
              w.textSpan!.toPlainText() == 'Widget Summary',
        );
        expect(captionFinder, findsOneWidget);
        final Text captionWidget = tester.widget<Text>(captionFinder);
        expect(captionWidget.textAlign, TextAlign.center);
        expect(
          tester.getBottomLeft(captionFinder).dy,
          lessThanOrEqualTo(tester.getTopLeft(tables.at(0)).dy),
        );

        // Alignment check on <th align="center"> and <td align="center">.
        final Text categoryText = tester.widget<Text>(find.text('Category'));
        expect(categoryText.textAlign, TextAlign.center);
        final Text inlineText = tester.widget<Text>(find.text('Inline'));
        expect(inlineText.textAlign, TextAlign.center);
        final Text rightCellText = tester.widget<Text>(find.text('Right cell'));
        expect(rightCellText.textAlign, TextAlign.right);

        // Literal <code>&lt;kbd&gt;</code> renders as `<kbd>` text (not a keycap).
        expect(find.text('<kbd>'), findsOneWidget);

        // <kbd>Cmd</kbd> + <kbd>P</kbd> preserves spaces and renders keycap badges.
        final Finder cmdPlusPFinder = find.byWidgetPredicate(
          (Widget w) => w is RichText && w.text.toPlainText().contains(' + '),
        );
        expect(cmdPlusPFinder, findsOneWidget);
        expect(find.text('Cmd'), findsOneWidget);
        expect(find.text('P'), findsOneWidget);

        // Body <th> in extra thead / tfoot renders bolded via StrongNode.
        final Text totalText = tester.widget<Text>(find.text('Total'));
        FontWeight? totalWeight;
        totalText.textSpan?.visitChildren((InlineSpan span) {
          if (span is TextSpan && span.text == 'Total') {
            totalWeight = span.style?.fontWeight;
            return false;
          }
          return true;
        });
        expect(totalWeight, FontWeight.w700);
      },
    );

    testWidgets(
      'renders HTML <dl>, <ul>, <ol start="3"> with nested lists and implicit closes',
      (WidgetTester tester) async {
        const String doc = '''
<dl>
  <dt>Single-Tab Invariant</dt>
  <dd>Focuses existing tab without duplication.
  <dt>Offscreen Engine</dt>
  <dd><p>Compiles diagrams cleanly.</p></dd>
</dl>

<ul>
  <li>Bullet A
    <ul>
      <li>Nested bullet B</li>
    </ul>
  <li>Bullet C</li>
</ul>

<ol start="3">
  <li>Third item</li>
  <li>Fourth item</li>
</ol>
''';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MarkdownView(
                  doc,
                  options: MarkdownOptions.extended(),
                  scrollable: false,
                  selectable: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('Single-Tab Invariant'), findsOneWidget);
        expect(
          find.text('Focuses existing tab without duplication.'),
          findsOneWidget,
        );
        expect(find.text('Offscreen Engine'), findsOneWidget);
        expect(find.text('Compiles diagrams cleanly.'), findsOneWidget);

        expect(find.text('Bullet A'), findsOneWidget);
        expect(find.text('Nested bullet B'), findsOneWidget);
        expect(find.text('Bullet C'), findsOneWidget);
        expect(find.text('•'), findsNWidgets(2));
        expect(find.text('◦'), findsOneWidget);

        expect(find.text('3.'), findsOneWidget);
        expect(find.text('4.'), findsOneWidget);
        expect(find.text('Third item'), findsOneWidget);
        expect(find.text('Fourth item'), findsOneWidget);
      },
    );

    testWidgets(
      'renders aligned blocks, sized <img>, linked <picture> hero with MarkdownUrlPolicy and MarkdownImagePolicy',
      (WidgetTester tester) async {
        const String oneByOnePngDataUri =
            'data:image/png;base64,'
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

        const String doc =
            '''
<a href="https://flutter.dev/">
  <h1 align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://docs.flutter.dev/logo_dark.png">
      <img alt="Flutter Hero" src="https://docs.flutter.dev/logo.png">
    </picture>
  </h1>
</a>

<p align="center">
  <img src="$oneByOnePngDataUri" alt="Centered Data Logo" width="72" height="48" />
</p>

<p align="center">
  <strong>Centered HTML bold text</strong>
</p>

<table>
  <tr>
    <td><a href="https://dart.dev">Allowed Table Link</a></td>
    <td><a href="javascript:alert(1)">Blocked Table Link</a></td>
  </tr>
</table>
''';

        final List<String> tappedLinks = <String>[];
        final List<String> builtImages = <String>[];

        // 1. MarkdownImagePolicy.block renders placeholder without Image widgets.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MarkdownView(
                  doc,
                  options: const MarkdownOptions.extended(
                    urlPolicy: MarkdownUrlPolicy.strict(
                      allowSafeImageDataUrls: true,
                    ),
                  ),
                  scrollable: false,
                  selectable: false,
                  delegates: MarkdownBuilderDelegates(
                    imagePolicy: MarkdownImagePolicy.block,
                    urlPolicy: const MarkdownUrlPolicy.strict(
                      allowSafeImageDataUrls: true,
                    ),
                    onTapLink: (String dest, String? _) =>
                        tappedLinks.add(dest),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Flutter Hero'), findsOneWidget);
        expect(find.text('docs.flutter.dev'), findsOneWidget);
        // Only the safe data:image renders as an Image; remote <picture> is blocked.
        expect(find.byType(Image), findsOneWidget);
        final Image sizedDataImg = tester.widget<Image>(find.byType(Image));
        expect(sizedDataImg.width, 72.0);
        expect(sizedDataImg.height, 48.0);

        // Centered bold text has TextAlign.center and FontWeight.w700.
        final Text centeredBold = tester.widget<Text>(
          find.text('Centered HTML bold text'),
        );
        expect(centeredBold.textAlign, TextAlign.center);

        // Allowed table link fires onTapLink; javascript: table link does NOT.
        await tester.tap(find.text('Allowed Table Link'));
        await tester.pump();
        expect(tappedLinks, <String>['https://dart.dev']);

        await tester.tap(find.text('Blocked Table Link'));
        await tester.pump();
        expect(tappedLinks, <String>['https://dart.dev']);

        final Text blockedText = tester.widget<Text>(
          find.text('Blocked Table Link'),
        );
        bool hasBlockedRecognizer = false;
        blockedText.textSpan?.visitChildren((InlineSpan span) {
          if (span is TextSpan && span.recognizer != null) {
            hasBlockedRecognizer = true;
          }
          return true;
        });
        expect(hasBlockedRecognizer, isFalse);

        // Tapping linked <picture> hero placeholder triggers https://flutter.dev/.
        await tester.tap(find.text('Flutter Hero'));
        await tester.pump();
        expect(tappedLinks, <String>[
          'https://dart.dev',
          'https://flutter.dev/',
        ]);

        // 2. MarkdownImagePolicy.load in dark theme selects dark <source> and stays clickable.
        tappedLinks.clear();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownTheme(
                data: const MarkdownThemeData.dark(),
                child: SingleChildScrollView(
                  child: MarkdownView(
                    doc,
                    options: const MarkdownOptions.extended(
                      urlPolicy: MarkdownUrlPolicy.strict(
                        allowSafeImageDataUrls: true,
                      ),
                    ),
                    scrollable: false,
                    selectable: false,
                    delegates: MarkdownBuilderDelegates(
                      imagePolicy: MarkdownImagePolicy.load,
                      urlPolicy: const MarkdownUrlPolicy.strict(
                        allowSafeImageDataUrls: true,
                      ),
                      onTapLink: (String dest, String? _) =>
                          tappedLinks.add(dest),
                      imageBuilder: (BuildContext context, ImageNode node) {
                        builtImages.add(node.destination);
                        return Text('IMG:${node.destination}');
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(builtImages, contains('https://docs.flutter.dev/logo_dark.png'));
        await tester.tap(
          find.text('IMG:https://docs.flutter.dev/logo_dark.png'),
        );
        await tester.pump();
        expect(tappedLinks, <String>['https://flutter.dev/']);
      },
    );

    testWidgets(
      'strips dangerous elements, preserves entity-escaped <script>, and survives 200x nested unclosed <table><tr><td> without overflow or assertions',
      (WidgetTester tester) async {
        final String deepUnclosedTable =
            '${'<table><tr><td>' * 200}Deep surviving cell';
        final String doc =
            '''
<table>
  <tr>
    <td>Safe cell<script>alert("xss")</script><style>.x{color:red}</style><iframe src="https://evil.example">evil</iframe></td>
    <td><code>&lt;script&gt;alert(1)&lt;/script&gt;</code></td>
  </tr>
</table>

<p>Literal escaped &lt;script&gt; text<!-- hidden comment --></p>

$deepUnclosedTable
''';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MarkdownView(
                  doc,
                  options: const MarkdownOptions.extended(sanitizeHtml: false),
                  scrollable: false,
                  selectable: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('Safe cell'), findsOneWidget);
        expect(find.textContaining('alert("xss")'), findsNothing);
        expect(find.textContaining('color:red'), findsNothing);
        expect(find.text('evil'), findsNothing);
        expect(find.text('hidden comment'), findsNothing);

        expect(find.text('<script>alert(1)</script>'), findsOneWidget);
        expect(find.text('Literal escaped <script> text'), findsOneWidget);
        expect(find.text('Deep surviving cell'), findsOneWidget);
        expect(find.byType(Table), findsNWidgets(2));
      },
    );

    testWidgets(
      'renders inline <samp>, <var>, <strong>, <b>, <em>, <i>, <del>, <s>, <strike>, and <ins> inside Markdown paragraphs',
      (WidgetTester tester) async {
        const String doc =
            'Inline <samp>stdout</samp>, <var>x</var>, <b>bold-b</b>, <i>italic-i</i>, <del>deleted</del>, <s>struck</s>, and <ins>inserted</ins>.';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                doc,
                options: MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final Text para = tester.widget<Text>(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Text &&
                w.textSpan != null &&
                w.textSpan!.toPlainText().contains('stdout'),
          ),
        );
        final MarkdownThemeData resolvedTheme = MarkdownTheme.of(
          tester.element(find.bySubtype<Text>().first),
        );

        TextStyle? sampStyle;
        TextStyle? varStyle;
        TextStyle? boldStyle;
        TextStyle? italicStyle;
        TextStyle? delStyle;
        TextStyle? sStyle;
        TextStyle? insStyle;

        para.textSpan!.visitChildren((InlineSpan span) {
          if (span is TextSpan) {
            switch (span.text) {
              case 'stdout':
                sampStyle = span.style;
              case 'x':
                varStyle = span.style;
              case 'bold-b':
                boldStyle = span.style;
              case 'italic-i':
                italicStyle = span.style;
              case 'deleted':
                delStyle = span.style;
              case 'struck':
                sStyle = span.style;
              case 'inserted':
                insStyle = span.style;
            }
          }
          return true;
        });

        expect(sampStyle?.fontFamily, resolvedTheme.effectiveCodeFontFamily);
        expect(sampStyle?.backgroundColor, resolvedTheme.codeBackground);
        expect(varStyle?.fontStyle, FontStyle.italic);
        expect(boldStyle?.fontWeight, FontWeight.w700);
        expect(italicStyle?.fontStyle, FontStyle.italic);
        expect(
          delStyle?.decoration?.contains(TextDecoration.lineThrough),
          isTrue,
        );
        expect(
          sStyle?.decoration?.contains(TextDecoration.lineThrough),
          isTrue,
        );
        expect(
          insStyle?.decoration?.contains(TextDecoration.underline),
          isTrue,
        );
      },
    );

    testWidgets(
      'renders HTML <pre><code>, <blockquote>, <hr>, <details>, <figure>, <abbr>, <mark>, <q>, <sub>, <sup>, and <small> inside HTML blocks',
      (WidgetTester tester) async {
        const String doc = '''
<div>
  <pre><code class="language-dart">  void main() {
    print('&lt;ok&gt;');
  }</code></pre>
  <blockquote><p>Quoted <mark>highlight</mark>, <q>inner</q>, H<sub>2</sub>O, 2<sup>10</sup>, <small>tiny</small>, and <abbr title="HyperText Markup Language">HTML</abbr>.</p></blockquote>
  <hr />
  <details open>
    <summary>HTML Disclosure</summary>
    <p>Inside HTML details.</p>
  </details>
  <figure>
    <p>Figure body</p>
    <figcaption>HTML Fig Caption</figcaption>
  </figure>
</div>
''';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MarkdownView(
                  doc,
                  options: MarkdownOptions.extended(),
                  scrollable: false,
                  selectable: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('dart'), findsOneWidget);
        expect(
          find.text("  void main() {\n    print('<ok>');\n  }"),
          findsOneWidget,
        );
        expect(find.textContaining('Quoted highlight'), findsOneWidget);
        expect(find.textContaining('\u201Cinner\u201D'), findsOneWidget);
        expect(find.byType(Tooltip), findsOneWidget);
        expect(find.text('HTML Disclosure'), findsOneWidget);
        expect(find.text('Inside HTML details.'), findsOneWidget);
        expect(find.text('Figure body'), findsOneWidget);
        expect(find.text('HTML Fig Caption'), findsOneWidget);
      },
    );

    testWidgets(
      'renders inline <sub>, <sup>, <mark>, and <abbr title> inside regular Markdown paragraphs with nesting, links, and unclosed fallbacks',
      (WidgetTester tester) async {
        const String doc =
            'Water is H<sub>2</sub>O, 2<sup>10</sup> = 1024, '
            '<mark>highlighted terms</mark>, '
            '<abbr title="GitHub Flavored Markdown">GFM</abbr>, '
            '<abbr title="A &amp; B">AB</abbr>, '
            'nested x<sub>i<sub>j</sub></sub>, '
            '[Link H<sub>2</sub>O <abbr title="HyperText">HT</abbr>](https://example.com/chem), '
            'and unclosed H<sub>2 2<sup>10 <abbr title="Open">Unclosed.';

        final List<String> tappedLinks = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: MarkdownView(
                  doc,
                  options: const MarkdownOptions.extended(),
                  scrollable: false,
                  selectable: false,
                  delegates: MarkdownBuilderDelegates(
                    onTapLink: (String dest, String? _) =>
                        tappedLinks.add(dest),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final MarkdownThemeData resolvedTheme = MarkdownTheme.of(
          tester.element(find.byType(MarkdownView)),
        );

        // Verify <sub> and <sup> use Transform.translate with downward/upward offsets.
        final List<Transform> transforms = tester
            .widgetList<Transform>(find.byType(Transform))
            .toList();
        expect(
          transforms.any((Transform t) => t.transform.getTranslation().y > 0),
          isTrue,
        );
        expect(
          transforms.any((Transform t) => t.transform.getTranslation().y < 0),
          isTrue,
        );
        expect(find.text('2'), findsWidgets);
        expect(find.text('10'), findsOneWidget);
        expect(find.text('j'), findsOneWidget);

        // Verify <mark>highlighted terms</mark> receives theme.highlightFill.
        final RichText para = tester.widget<RichText>(
          find.byWidgetPredicate(
            (Widget w) =>
                w is RichText &&
                w.text.toPlainText().contains('highlighted terms'),
          ),
        );
        Color? markBackground;
        para.text.visitChildren((InlineSpan span) {
          if (span is TextSpan && span.text == 'highlighted terms') {
            markBackground = span.style?.backgroundColor;
            return false;
          }
          return true;
        });
        expect(markBackground, resolvedTheme.highlightFill);

        // Verify <abbr title="..."> renders Tooltip with decoded title and dotted underline.
        final List<Tooltip> tooltips = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .toList();
        expect(
          tooltips.any((Tooltip t) => t.message == 'GitHub Flavored Markdown'),
          isTrue,
        );
        expect(tooltips.any((Tooltip t) => t.message == 'A & B'), isTrue);
        expect(tooltips.any((Tooltip t) => t.message == 'HyperText'), isTrue);
        // Unclosed <abbr title="Open"> must not create a Tooltip.
        expect(tooltips.any((Tooltip t) => t.message == 'Open'), isFalse);

        final RichText gfmText = tester.widget<RichText>(
          find.descendant(
            of: find.byWidgetPredicate(
              (Widget w) =>
                  w is Tooltip && w.message == 'GitHub Flavored Markdown',
            ),
            matching: find.bySubtype<RichText>(),
          ),
        );
        TextStyle? gfmStyle;
        gfmText.text.visitChildren((InlineSpan span) {
          if (span is TextSpan && span.text == 'GFM') {
            gfmStyle = span.style;
            return false;
          }
          return true;
        });
        expect(
          gfmStyle?.decoration?.contains(TextDecoration.underline),
          isTrue,
        );
        expect(gfmStyle?.decorationStyle, TextDecorationStyle.dotted);

        // Verify link inheritance for <sub> and <abbr> inside a Markdown link.
        await tester.tap(find.text('HT'));
        await tester.pump();
        expect(tappedLinks, <String>['https://example.com/chem']);

        // Unclosed tags still preserve visible text cleanly.
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is RichText && w.text.toPlainText().contains('Unclosed.'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'preserves full data:image URI in <picture><source srcset> in dark mode while enforcing URL and image policies',
      (WidgetTester tester) async {
        const String oneByOnePngDataUri =
            'data:image/png;base64,'
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

        const String doc =
            '''
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="$oneByOnePngDataUri 2x, https://example.com/dark-fallback.png 1x">
  <img src="https://example.com/light.png" alt="Logo">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="data:text/html,<script>alert(1)</script>">
  <img src="https://example.com/light2.png" alt="Unsafe Data">
</picture>
''';

        final List<String> builtImages = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownTheme(
                data: const MarkdownThemeData.dark(),
                child: SingleChildScrollView(
                  child: MarkdownView(
                    doc,
                    options: const MarkdownOptions.extended(
                      urlPolicy: MarkdownUrlPolicy.strict(
                        allowSafeImageDataUrls: true,
                      ),
                    ),
                    scrollable: false,
                    selectable: false,
                    delegates: MarkdownBuilderDelegates(
                      imagePolicy: MarkdownImagePolicy.block,
                      urlPolicy: const MarkdownUrlPolicy.strict(
                        allowSafeImageDataUrls: true,
                      ),
                      imageBuilder: (BuildContext context, ImageNode node) {
                        builtImages.add(node.destination);
                        return Text('DATA-IMG:${node.alt}');
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Full base64 data URI past `,` is preserved and descriptor `2x` stripped.
        expect(builtImages, <String>[oneByOnePngDataUri]);
        expect(find.text('DATA-IMG:Logo'), findsOneWidget);
        // Non-image data:text/html URI remains blocked by URL policy.
        expect(find.text('Unsafe Data'), findsOneWidget);
        expect(find.text('Disallowed URL scheme'), findsOneWidget);

        // Default strict URL policy (allowSafeImageDataUrls: false) blocks data:image too.
        builtImages.clear();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownTheme(
                data: const MarkdownThemeData.dark(),
                child: SingleChildScrollView(
                  child: MarkdownView(
                    doc,
                    options: const MarkdownOptions.extended(),
                    scrollable: false,
                    selectable: false,
                    delegates: MarkdownBuilderDelegates(
                      imagePolicy: MarkdownImagePolicy.load,
                      imageBuilder: (BuildContext context, ImageNode node) {
                        builtImages.add(node.destination);
                        return Text('DATA-IMG:${node.alt}');
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(builtImages, isEmpty);
        expect(find.text('Disallowed URL scheme'), findsNWidgets(2));
      },
    );

    testWidgets(
      'registers anchors for block-wrapping <a id> and <a name> at top level and inside nested containers',
      (WidgetTester tester) async {
        const String htmlFragment = '''
<a id="hero">
  <h1>Hero Title</h1>
</a>

<a name="sub-anchor">
  <h2 align="center">Sub Section</h2>
</a>

<div><a id="div-hero"><h1>Div Section</h1></a></div>

<details open>
  <summary>Section</summary>
  <a id="nested-hero"><h3>Nested Title</h3></a>
</details>

<a id="pre-hero">
  <pre><code>pre ok</code></pre>
</a>
''';

        // 1. AST-level check: AnchorInlineNode is emitted alongside wrapped headings without phantom paragraphs before headings.
        final List<HtmlBlockEntry> entries = parseHtmlBlockFragment(
          htmlFragment,
          parentBlockId: 'b0',
        );
        expect(entries, hasLength(6));
        expect(entries[0].block, isA<HeadingNode>());
        final HeadingNode heroHeading = entries[0].block as HeadingNode;
        expect(heroHeading.children.first, const AnchorInlineNode('hero'));
        expect(heroHeading.text, 'Hero Title');

        expect(entries[1].block, isA<AlignedBlockNode>());
        final AlignedBlockNode subAligned =
            entries[1].block as AlignedBlockNode;
        final HeadingNode subHeading =
            subAligned.children.single as HeadingNode;
        expect(subHeading.children.first, const AnchorInlineNode('sub-anchor'));

        expect(entries[2].block, isA<HeadingNode>());
        final HeadingNode divHeading = entries[2].block as HeadingNode;
        expect(divHeading.children.first, const AnchorInlineNode('div-hero'));

        expect(entries[3].block, isA<DetailsBlockNode>());
        final DetailsBlockNode details = entries[3].block as DetailsBlockNode;
        expect(details.children.single, isA<HeadingNode>());
        final HeadingNode nestedHeading =
            details.children.single as HeadingNode;
        expect(
          nestedHeading.children.first,
          const AnchorInlineNode('nested-hero'),
        );

        expect(entries[4].block, isA<ParagraphNode>());
        expect(
          (entries[4].block as ParagraphNode).children,
          const <MarkdownInlineNode>[AnchorInlineNode('pre-hero')],
        );
        expect(entries[5].block, isA<CodeBlockNode>());

        // 2. Widget + MarkdownController check: targets register and headings still render with semantics.
        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);
        final SemanticsHandle semanticsHandle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: MarkdownView(
                    htmlFragment,
                    options: const MarkdownOptions.extended(),
                    controller: controller,
                    scrollable: false,
                    selectable: false,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          for (final String slug in <String>[
            'hero',
            'sub-anchor',
            'div-hero',
            'nested-hero',
            'pre-hero',
          ]) {
            expect(
              find.byWidgetPredicate(
                (Widget w) =>
                    w is MarkdownAnchorTarget && w.slugs.contains(slug),
              ),
              findsOneWidget,
              reason: 'Expected MarkdownAnchorTarget for #$slug',
            );
            expect(await controller.scrollToAnchor(slug), isTrue);
          }

          expect(find.textContaining('Hero Title'), findsOneWidget);
          expect(find.textContaining('Sub Section'), findsOneWidget);
          expect(find.textContaining('Div Section'), findsOneWidget);
          expect(find.textContaining('Nested Title'), findsOneWidget);
          expect(find.text('pre ok'), findsOneWidget);

          final Semantics heroSem = tester.widget<Semantics>(
            find
                .ancestor(
                  of: find.textContaining('Hero Title'),
                  matching: find.byWidgetPredicate(
                    (Widget w) => w is Semantics && w.properties.header == true,
                  ),
                )
                .first,
          );
          expect(heroSem.properties.headingLevel, 1);

          final Semantics nestedSem = tester.widget<Semantics>(
            find
                .ancestor(
                  of: find.textContaining('Nested Title'),
                  matching: find.byWidgetPredicate(
                    (Widget w) => w is Semantics && w.properties.header == true,
                  ),
                )
                .first,
          );
          expect(nestedSem.properties.headingLevel, 3);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'handles unclosed <sub>, <sup>, and <abbr> bursts in linear time without throwing or stalling',
      (WidgetTester tester) async {
        final String unclosedSubDoc = '${'<sub>' * 5000}tail';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                unclosedSubDoc,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('tail'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                '<sub>' * 5000,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownInlineText(
                nodes: <MarkdownInlineNode>[
                  ...List<MarkdownInlineNode>.filled(
                    5000,
                    const RawHtmlInlineNode('<sup>'),
                  ),
                  ...List<MarkdownInlineNode>.filled(
                    5000,
                    const RawHtmlInlineNode('<abbr title="t">'),
                  ),
                  const TextNode('after-burst'),
                ],
                baseStyle: const TextStyle(fontSize: 16.0),
                theme: const MarkdownThemeData.light(),
                delegates: const MarkdownBuilderDelegates(),
                urlPolicy: const MarkdownUrlPolicy.strict(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('after-burst'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MarkdownInlineText),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(MarkdownInlineText),
            matching: find.byType(Tooltip),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'caps deeply nested <sub>, <sup>, <abbr>, and AST script/abbr nodes at 32 wrappers',
      (WidgetTester tester) async {
        final String nestedSubDoc = '${'<sub>' * 5000}core${'</sub>' * 5000}';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                nestedSubDoc,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('core'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Transform),
          ),
          findsNWidgets(32),
        );

        final String nestedSupDoc = '${'<sup>' * 500}core${'</sup>' * 500}';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                nestedSupDoc,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('core'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Transform),
          ),
          findsNWidgets(32),
        );

        final String nestedAbbrDoc =
            '${'<abbr title="t">' * 500}core${'</abbr>' * 500}';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                nestedAbbrDoc,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('core'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Tooltip),
          ),
          findsNWidgets(32),
        );

        final String nestedTitlelessAbbrDoc =
            '${'<abbr>' * 500}no-title${'</abbr>' * 500}';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                nestedTitlelessAbbrDoc,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('no-title'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MarkdownView),
            matching: find.byType(Tooltip),
          ),
          findsNothing,
        );

        // AST SubscriptNode, SuperscriptNode, and AbbrInlineNode nesting also caps at 32.
        MarkdownInlineNode astSub = const TextNode('ast-sub');
        MarkdownInlineNode astSup = const TextNode('ast-sup');
        MarkdownInlineNode astAbbr = const TextNode('ast-abbr');
        for (int depth = 0; depth < 40; depth++) {
          astSub = SubscriptNode(children: <MarkdownInlineNode>[astSub]);
          astSup = SuperscriptNode(children: <MarkdownInlineNode>[astSup]);
          astAbbr = AbbrInlineNode(
            title: 't',
            children: <MarkdownInlineNode>[astAbbr],
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  MarkdownInlineText(
                    nodes: <MarkdownInlineNode>[astSub],
                    baseStyle: const TextStyle(fontSize: 16.0),
                    theme: const MarkdownThemeData.light(),
                    delegates: const MarkdownBuilderDelegates(),
                    urlPolicy: const MarkdownUrlPolicy.strict(),
                  ),
                  MarkdownInlineText(
                    nodes: <MarkdownInlineNode>[astSup],
                    baseStyle: const TextStyle(fontSize: 16.0),
                    theme: const MarkdownThemeData.light(),
                    delegates: const MarkdownBuilderDelegates(),
                    urlPolicy: const MarkdownUrlPolicy.strict(),
                  ),
                  MarkdownInlineText(
                    nodes: <MarkdownInlineNode>[astAbbr],
                    baseStyle: const TextStyle(fontSize: 16.0),
                    theme: const MarkdownThemeData.light(),
                    delegates: const MarkdownBuilderDelegates(),
                    urlPolicy: const MarkdownUrlPolicy.strict(),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('ast-sub'), findsOneWidget);
        expect(find.text('ast-sup'), findsOneWidget);
        expect(find.text('ast-abbr'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MarkdownInlineText).at(0),
            matching: find.byType(Transform),
          ),
          findsNWidgets(32),
        );
        expect(
          find.descendant(
            of: find.byType(MarkdownInlineText).at(1),
            matching: find.byType(Transform),
          ),
          findsNWidgets(32),
        );
        expect(
          find.descendant(
            of: find.byType(MarkdownInlineText).at(2),
            matching: find.byType(Tooltip),
          ),
          findsNWidgets(32),
        );
      },
    );

    testWidgets(
      'renders crossing malformed <sub> and <abbr> tags safely without range or assertion errors',
      (WidgetTester tester) async {
        const String doc =
            '<sub><abbr title="t">a</sub>b</abbr> <abbr title="u">c</abbr>';
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                doc,
                options: MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('a'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is RichText && w.text.toPlainText().contains('b'),
          ),
          findsOneWidget,
        );
        expect(find.text('c'), findsOneWidget);

        final List<Tooltip> tooltips = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .toList();
        expect(tooltips.any((Tooltip t) => t.message == 't'), isFalse);
        expect(tooltips.any((Tooltip t) => t.message == 'u'), isTrue);
      },
    );

    testWidgets(
      'renders consecutive numeric and named footnotes without blank lines and scrolls to fn-note',
      (WidgetTester tester) async {
        const String doc = '''
markdown_engine compiles Mermaid diagrams into native vector bytecode[^1] and supports named references[^note].

First spacer paragraph so the footnotes section renders below the fold.

Second spacer paragraph to ensure the viewport must scroll to reach footnotes.

Third spacer paragraph confirming controller anchor navigation works cleanly.

[^1]: Powered by `pele_dart` and `vector_graphics_compiler`.
[^note]: Footnote definitions are collected and numbered at the bottom of the rendered document.
''';
        final List<(String, String?)> tappedLinks = <(String, String?)>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                doc,
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: false,
                delegates: MarkdownBuilderDelegates(
                  onTapLink: (String destination, String? title) {
                    tappedLinks.add((destination, title));
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.bySemanticsLabel('Footnote 1'), findsOneWidget);
        expect(find.bySemanticsLabel('Footnote 2'), findsOneWidget);
        expect(find.text('[1]'), findsOneWidget);
        expect(find.text('[2]'), findsOneWidget);
        expect(find.textContaining('[^note]'), findsNothing);
        expect(
          find.textContaining(
            'Footnote definitions are collected and numbered',
          ),
          findsOneWidget,
        );
        expect(find.text('↩\uFE0E'), findsNWidgets(2));

        await tester.tap(find.bySemanticsLabel('Footnote 2'));
        await tester.pump();
        expect(tappedLinks, <(String, String?)>[('#fn-note', null)]);

        final MarkdownController controller = MarkdownController();
        final ScrollController scrollController = ScrollController();
        addTearDown(() {
          controller.dispose();
          scrollController.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 120.0,
                child: MarkdownView(
                  doc,
                  options: const MarkdownOptions.extended(),
                  controller: controller,
                  scrollController: scrollController,
                  selectable: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(scrollController.offset, 0.0);

        await tester.tap(find.bySemanticsLabel('Footnote 2'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(scrollController.offset, greaterThan(0.0));
      },
    );
  });

  group('Mouse hover cursor', () {
    testWidgets(
      'shows click cursor over links, footnotes, linked inline widgets, and details summary under selectable: true',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final MarkdownController controller = MarkdownController();
        addTearDown(controller.dispose);

        const String doc = '''
Plain [Click docs](https://example.com) and [**Bold link**](https://example.com) and [`codeLink`](https://example.com) and [Jump section](#target) plus[^1]

Linked widgets: [<kbd>Cmd</kbd>](https://example.com) [x<sup>2</sup>](https://example.com) [H<sub>2</sub>O](https://example.com) [<abbr title="HyperText">HTML</abbr>](https://example.com) [Unsafe](javascript:alert(1))

<details>
<summary>Toggle summary</summary>

Hidden body

</details>

## Target {#target}

[^1]: Footnote detail body.
''';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900.0,
                height: 900.0,
                child: MarkdownView(
                  doc,
                  options: const MarkdownOptions.extended(),
                  controller: controller,
                  scrollable: false,
                  selectable: true,
                  delegates: MarkdownBuilderDelegates(
                    onTapLink: (String _, String? _) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final TestGesture mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 1,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        Future<MouseCursor?> cursorAt(Offset globalOffset) async {
          await mouse.moveTo(globalOffset);
          await tester.pump();
          return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
            1,
          );
        }

        Offset centerOfSubstring(String paragraphContains, String target) {
          final Finder richFinder = find.byWidgetPredicate(
            (Widget w) =>
                w is RichText &&
                w.text.toPlainText().contains(paragraphContains),
          );
          final RenderParagraph paragraph = tester
              .renderObject<RenderParagraph>(richFinder.first);
          final String plain = paragraph.text.toPlainText();
          final int start = plain.indexOf(target);
          expect(start, greaterThanOrEqualTo(0), reason: 'Missing "$target"');
          final List<TextBox> boxes = paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: start,
              extentOffset: start + target.length,
            ),
          );
          expect(boxes, isNotEmpty, reason: 'No boxes for "$target"');
          return paragraph.localToGlobal(boxes.first.toRect().center);
        }

        // Plain prose next to links uses text cursor.
        expect(
          await cursorAt(centerOfSubstring('Click docs', 'Plain')),
          SystemMouseCursors.text,
        );
        // Plain, bold, inline code, and anchor links use click cursor.
        expect(
          await cursorAt(centerOfSubstring('Click docs', 'Click docs')),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(centerOfSubstring('Bold link', 'Bold link')),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(centerOfSubstring('codeLink', 'codeLink')),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(centerOfSubstring('Jump section', 'Jump section')),
          SystemMouseCursors.click,
        );

        // Footnote inline badge and back-link use click cursor.
        expect(
          await cursorAt(tester.getCenter(find.bySemanticsLabel('Footnote 1'))),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(
            tester.getCenter(
              find.bySemanticsLabel('Back to footnote reference 1'),
            ),
          ),
          SystemMouseCursors.click,
        );

        // Linked WidgetSpan elements (<kbd>, <sup>, <sub>, <abbr>) use click cursor.
        expect(
          await cursorAt(tester.getCenter(find.text('Cmd'))),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(tester.getCenter(find.text('2').first)),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(tester.getCenter(find.text('2').last)),
          SystemMouseCursors.click,
        );
        expect(
          await cursorAt(tester.getCenter(find.text('HTML'))),
          SystemMouseCursors.click,
        );

        // Blocked javascript: link must NOT use click cursor.
        expect(
          await cursorAt(centerOfSubstring('Unsafe', 'Unsafe')),
          SystemMouseCursors.text,
        );

        // <details><summary> uses click cursor over the summary text itself.
        expect(
          await cursorAt(tester.getCenter(find.text('Toggle summary'))),
          SystemMouseCursors.click,
        );
      },
    );

    testWidgets(
      'shows click cursor over linked inline math chip (built-in math off) and TexMath (built-in math on)',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          await MarkdownBuiltInRenderers.dispose();
        });

        final TestGesture mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 1,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        Future<MouseCursor?> cursorAt(Offset globalOffset) async {
          await mouse.moveTo(globalOffset);
          await tester.pump();
          return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
            1,
          );
        }

        // 1. Built-in math disabled -> fallback math chip link.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                r'Linked math [$x+1$](https://example.com)',
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: true,
                delegates: MarkdownBuilderDelegates(
                  enableBuiltInMath: false,
                  onTapLink: (String _, String? _) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          await cursorAt(tester.getCenter(find.text('x+1'))),
          SystemMouseCursors.click,
        );

        // 2. Built-in math enabled -> native TexMath widget inside link.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownView(
                r'Linked math [$x+1$](https://example.com)',
                options: const MarkdownOptions.extended(),
                scrollable: false,
                selectable: true,
                delegates: MarkdownBuilderDelegates(
                  enableBuiltInMath: true,
                  onTapLink: (String _, String? _) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TexMath), findsOneWidget);
        expect(
          await cursorAt(tester.getCenter(find.byType(TexMath))),
          SystemMouseCursors.click,
        );
      },
    );
  });

  group('macOS right-click selection preservation', () {
    testWidgets(
      'preserves single-paragraph drag selection on right-click inside selection, updates on right-click outside, and still allows double-click word selection',
      (WidgetTester tester) async {
        SelectedContent? currentSelection;
        final FocusNode focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800.0,
                height: 400.0,
                child: SelectionArea(
                  focusNode: focusNode,
                  onSelectionChanged: (SelectedContent? content) {
                    currentSelection = content;
                  },
                  child: const MarkdownView(
                    'prefix alpha beta gamma suffix',
                    scrollable: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Finder paraFinder = find.text('prefix alpha beta gamma suffix');
        expect(paraFinder, findsOneWidget);
        final Rect paraRect = tester.getRect(paraFinder);
        // Flutter test's default Ahem font advances 16px per character at fontSize 16.
        // 'prefix alpha beta gamma suffix' -> indices:
        // alpha: 7..12, beta: 13..17, gamma: 18..23, suffix: 24..30.
        final Offset alphaStart = Offset(
          paraRect.left + 7 * 16.0 + 4.0,
          paraRect.center.dy,
        );
        final Offset betaCenter = Offset(
          paraRect.left + 15 * 16.0,
          paraRect.center.dy,
        );
        final Offset gammaEnd = Offset(
          paraRect.left + 23 * 16.0 - 2.0,
          paraRect.center.dy,
        );
        final Offset suffixCenter = Offset(
          paraRect.left + 27 * 16.0,
          paraRect.center.dy,
        );

        final TestGesture drag = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(drag.removePointer);
        await drag.down(alphaStart);
        await tester.pump();
        await drag.moveTo(gammaEnd);
        await tester.pump();
        await drag.up();
        await tester.pump();

        expect(currentSelection?.plainText, 'alpha beta gamma');

        // Right-click inside the active selection on 'beta': must preserve selection
        // and show context menu.
        final TestGesture rightClickInside = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        addTearDown(rightClickInside.removePointer);
        await rightClickInside.down(betaCenter);
        await tester.pump();
        await rightClickInside.up();
        await tester.pump();

        expect(currentSelection?.plainText, 'alpha beta gamma');
        expect(find.text('Copy'), findsOneWidget);

        // Double-click inside the active selection on 'beta': must still shrink
        // selection to 'beta'.
        final TestGesture doubleClick = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(doubleClick.removePointer);
        await doubleClick.down(betaCenter);
        await tester.pump();
        await doubleClick.up();
        await tester.pump(const Duration(milliseconds: 50));
        await doubleClick.down(betaCenter);
        await tester.pump();
        await doubleClick.up();
        await tester.pump();

        expect(currentSelection?.plainText, 'beta');

        // Drag 'alpha beta gamma' again, then right-click OUTSIDE on 'suffix':
        // native macOS behavior selects the clicked word 'suffix'.
        await drag.down(alphaStart);
        await tester.pump();
        await drag.moveTo(gammaEnd);
        await tester.pump();
        await drag.up();
        await tester.pump();
        expect(currentSelection?.plainText, 'alpha beta gamma');

        final TestGesture rightClickOutside = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        addTearDown(rightClickOutside.removePointer);
        await rightClickOutside.down(suffixCenter);
        await tester.pump();
        await rightClickOutside.up();
        await tester.pump();

        expect(currentSelection?.plainText, 'suffix');
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'preserves multi-paragraph drag selection on right-click inside first paragraph',
      (WidgetTester tester) async {
        SelectedContent? currentSelection;
        final FocusNode focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800.0,
                height: 400.0,
                child: SelectionArea(
                  focusNode: focusNode,
                  onSelectionChanged: (SelectedContent? content) {
                    currentSelection = content;
                  },
                  child: const MarkdownView(
                    'First paragraph words\n\nSecond paragraph words',
                    scrollable: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Rect firstRect = tester.getRect(
          find.text('First paragraph words'),
        );
        final Rect secondRect = tester.getRect(
          find.text('Second paragraph words'),
        );

        final TestGesture drag = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(drag.removePointer);
        await drag.down(firstRect.centerLeft + const Offset(4.0, 0.0));
        await tester.pump();
        await drag.moveTo(secondRect.centerRight - const Offset(4.0, 0.0));
        await tester.pump();
        await drag.up();
        await tester.pump();

        expect(currentSelection?.plainText, contains('First paragraph words'));
        expect(currentSelection?.plainText, contains('Second paragraph words'));
        final String beforeRightClick = currentSelection!.plainText;

        final TestGesture rightClick = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        addTearDown(rightClick.removePointer);
        await rightClick.down(firstRect.center);
        await tester.pump();
        await rightClick.up();
        await tester.pump();

        expect(currentSelection?.plainText, beforeRightClick);
        expect(find.text('Copy'), findsOneWidget);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'preserves Select All document selection on right-click inside a paragraph',
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
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800.0,
                height: 400.0,
                child: MarkdownView(
                  'Alpha select all\n\nBeta select all',
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        focusNode.requestFocus();
        await tester.pump();
        Actions.invoke(
          focusNode.context!,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();

        final TestGesture rightClick = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        addTearDown(rightClick.removePointer);
        await rightClick.down(tester.getCenter(find.text('Alpha select all')));
        await tester.pump();
        await rightClick.up();
        await tester.pump();

        expect(find.text('Copy'), findsOneWidget);
        Actions.invoke(focusNode.context!, CopySelectionTextIntent.copy);
        await tester.pump();

        expect(copiedClipboard, contains('Alpha select all'));
        expect(copiedClipboard, contains('Beta select all'));
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.macOS,
      }),
    );
  });

  group('Inline footnote back-links and linked image underline exclusion', () {
    testWidgets(
      'renders footnote back-link inline on the same row as paragraph text and falls back below trailing code blocks',
      (WidgetTester tester) async {
        const String doc = '''
Paragraph note[^1] and multi-block note[^2].

[^1]: Footnote explanation ends inline.
[^2]: Leading summary paragraph.

    ```dart
    final int answer = 42;
    ```
''';
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 720.0,
                child: MarkdownView(
                  doc,
                  options: MarkdownOptions.extended(),
                  scrollable: false,
                  selectable: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final Finder inlineNoteFinder = find.byWidgetPredicate(
          (Widget w) =>
              w is RichText &&
              w.text.toPlainText().contains(
                'Footnote explanation ends inline.',
              ),
        );
        expect(inlineNoteFinder, findsOneWidget);
        final Rect inlineNoteRect = tester.getRect(inlineNoteFinder);
        final Finder backLinks = find.text('↩\uFE0E');
        expect(backLinks, findsNWidgets(2));

        // First back-link sits horizontally inline inside the trailing paragraph row.
        final Rect firstBackRect = tester.getRect(backLinks.first);
        expect(
          firstBackRect.top,
          greaterThanOrEqualTo(inlineNoteRect.top - 2.0),
        );
        expect(
          firstBackRect.bottom,
          lessThanOrEqualTo(inlineNoteRect.bottom + 2.0),
        );

        // Second footnote ends with a fenced code block so its back-link sits below it.
        final Rect codeRect = tester.getRect(
          find.textContaining('final int answer = 42;'),
        );
        final Rect secondBackRect = tester.getRect(backLinks.last);
        expect(secondBackRect.top, greaterThan(codeRect.bottom));
      },
    );

    testWidgets(
      'omits link underline across linked images and <picture> elements while keeping text link underlines and tap handling',
      (WidgetTester tester) async {
        final List<String> tapped = <String>[];
        const String doc = '''
[![Flutter badge](https://example.com/badge.png)](https://flutter.dev/badge)

<a href="https://flutter.dev/hero">
  <h1 align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://example.com/dark.png">
      <img alt="Flutter" src="https://example.com/light.png">
    </picture>
  </h1>
</a>

[Visit ![icon](https://example.com/icon.png) **Flutter** docs](https://flutter.dev/docs)
''';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 760.0,
                child: MarkdownView(
                  doc,
                  options: const MarkdownOptions.extended(),
                  scrollable: false,
                  selectable: false,
                  delegates: MarkdownBuilderDelegates(
                    imagePolicy: MarkdownImagePolicy.load,
                    onTapLink: (String destination, String? _) {
                      tapped.add(destination);
                    },
                    imageBuilder: (BuildContext _, ImageNode node) => SizedBox(
                      key: ValueKey<String>('custom-img-${node.alt}'),
                      width: 64.0,
                      height: 28.0,
                      child: Center(child: Text('IMG:${node.alt}')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        void expectNoUnderlineOnWidgetSpan(String expectedKeyValue) {
          final Finder imgFinder = find.byKey(
            ValueKey<String>(expectedKeyValue),
          );
          expect(imgFinder, findsOneWidget);
          final Finder richAncestor = find
              .ancestor(
                of: imgFinder,
                matching: find.byWidgetPredicate((Widget w) => w is RichText),
              )
              .first;
          final RichText richText = tester.widget<RichText>(richAncestor);

          bool checkSpanTree(InlineSpan span) {
            if (span is TextSpan) {
              for (final InlineSpan child
                  in span.children ?? const <InlineSpan>[]) {
                if (child is WidgetSpan) {
                  final bool containsUnderline =
                      span.style?.decoration?.contains(
                        TextDecoration.underline,
                      ) ??
                      false;
                  expect(
                    containsUnderline,
                    isFalse,
                    reason: 'Ancestor TextSpan around WidgetSpan must not underline',
                  );
                  expect(
                    child.style?.decoration == TextDecoration.underline,
                    isFalse,
                  );
                } else {
                  checkSpanTree(child);
                }
              }
            }
            return true;
          }

          checkSpanTree(richText.text);
        }

        expectNoUnderlineOnWidgetSpan('custom-img-Flutter badge');
        expectNoUnderlineOnWidgetSpan('custom-img-Flutter');
        expectNoUnderlineOnWidgetSpan('custom-img-icon');

        // Verify mixed link text spans still carry link underlines.
        final RichText mixedRich = tester.widget<RichText>(
          find
              .ancestor(
                of: find.byKey(const ValueKey<String>('custom-img-icon')),
                matching: find.byWidgetPredicate((Widget w) => w is RichText),
              )
              .first,
        );
        final List<TextSpan> underlinedTextSpans = <TextSpan>[];
        void collectUnderlined(InlineSpan span) {
          if (span is TextSpan) {
            final bool hasText = (span.text ?? '').trim().isNotEmpty;
            final bool underlined =
                span.style?.decoration?.contains(TextDecoration.underline) ??
                false;
            if (hasText && underlined) {
              underlinedTextSpans.add(span);
            }
            for (final InlineSpan child
                in span.children ?? const <InlineSpan>[]) {
              collectUnderlined(child);
            }
          }
        }

        collectUnderlined(mixedRich.text);
        final String combinedUnderlined = underlinedTextSpans
            .map((TextSpan s) => s.text ?? '')
            .join();
        expect(combinedUnderlined, contains('Visit'));
        expect(combinedUnderlined, contains('Flutter'));
        expect(combinedUnderlined, contains('docs'));

        // Tapping linked images and linked <picture> still triggers onTapLink.
        await tester.tap(
          find.byKey(const ValueKey<String>('custom-img-Flutter badge')),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('custom-img-Flutter')),
        );
        await tester.pump();
        expect(tapped, <String>[
          'https://flutter.dev/badge',
          'https://flutter.dev/hero',
        ]);
      },
    );
  });
}

final class _UnsizedChildHost extends SingleChildRenderObjectWidget {
  const _UnsizedChildHost({required this.skipLayout, required super.child});

  final bool skipLayout;

  @override
  _RenderUnsizedChildHost createRenderObject(BuildContext context) {
    return _RenderUnsizedChildHost(skipLayout: skipLayout);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderUnsizedChildHost renderObject,
  ) {
    renderObject.skipLayout = skipLayout;
  }
}

final class _RenderUnsizedChildHost extends RenderProxyBox {
  _RenderUnsizedChildHost({required this._skipLayout});

  bool _skipLayout;
  set skipLayout(bool value) {
    if (_skipLayout == value) {
      return;
    }
    _skipLayout = value;
    markNeedsLayout();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void performLayout() {
    if (_skipLayout || child == null) {
      size = constraints.constrain(Size.zero);
      return;
    }
    child!.layout(constraints, parentUsesSize: true);
    size = child!.size;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_skipLayout) {
      return;
    }
    super.visitChildrenForSemantics(visitor);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_skipLayout) {
      return;
    }
    super.paint(context, offset);
  }
}
