import 'dart:io';

import 'package:markdown_engine/markdown_engine.dart';
import 'package:test/test.dart';

String _corpusRoot() {
  if (Directory('corpus').existsSync()) {
    return 'corpus';
  }
  return '../../corpus';
}

void main() {
  const MarkdownEngine engine = MarkdownEngine(
    defaultOptions: MarkdownOptions.extended(),
  );
  final String root = _corpusRoot();

  group('Corpus extensions', () {
    test(
      'parses GitHub blockquote alerts and preserves regular blockquotes',
      () {
        final String source = File(
          '$root/extensions/alerts.md',
        ).readAsStringSync();
        final MarkdownDocument doc = engine.parse(source);

        final List<AlertNode> alerts = doc.blocks
            .whereType<AlertNode>()
            .toList();
        expect(alerts.length, 5);
        expect(alerts.map((AlertNode a) => a.kind).toList(), <AlertKind>[
          AlertKind.note,
          AlertKind.tip,
          AlertKind.important,
          AlertKind.warning,
          AlertKind.caution,
        ]);
        expect(alerts[1].children.whereType<ListNode>().length, 1);

        final List<BlockQuoteNode> quotes = doc.blocks
            .whereType<BlockQuoteNode>()
            .toList();
        expect(quotes.length, 1);
        expect(doc.toHtml(), contains('markdown-alert-warning'));
      },
    );

    test(
      'extracts leading YAML and TOML frontmatter without hijacking body HR',
      () {
        final String yamlSrc = File(
          '$root/extensions/frontmatter.md',
        ).readAsStringSync();
        final MarkdownDocument yamlDoc = engine.parse(yamlSrc);

        expect(yamlDoc.frontmatter, isNotNull);
        expect(yamlDoc.frontmatter!.format, 'yaml');
        expect(
          yamlDoc.frontmatter!['title'],
          'Specification Compliance Report',
        );
        expect(yamlDoc.frontmatter!['tags'], <Object?>['commonmark', 'gfm']);
        expect(yamlDoc.frontmatter!['draft'], isFalse);
        expect(yamlDoc.blocks.whereType<FrontmatterNode>().length, 1);
        expect(yamlDoc.blocks.whereType<ThematicBreakNode>().length, 1);
        expect(yamlDoc.toHtml(), contains('<hr />'));
        expect(
          yamlDoc.toHtml(),
          isNot(contains('Specification Compliance Report')),
        );

        const String tomlSrc = '+++\ntitle = "TOML"\ncount = 3\n+++\n\nBody\n';
        final MarkdownDocument tomlDoc = engine.parse(tomlSrc);
        expect(tomlDoc.frontmatter?.format, 'toml');
        expect(tomlDoc.frontmatter?['title'], 'TOML');
        expect(tomlDoc.frontmatter?['count'], 3);
      },
    );

    test('parses footnotes, repeated refs, and skips unused definitions', () {
      final String source = File(
        '$root/extensions/footnotes.md',
      ).readAsStringSync();
      final MarkdownDocument doc = engine.parse(source);

      final FootnoteSectionNode? section = doc.blocks
          .whereType<FootnoteSectionNode>()
          .firstOrNull;
      expect(section, isNotNull);
      expect(section!.definitions.length, 3);
      expect(
        section.definitions.map((FootnoteDefinitionNode d) => d.label),
        <String>['1', 'details', 'shared'],
      );
      expect(section.definitions[2].referenceCount, 2);
      expect(doc.footnotes.length, 4);
      expect(doc.footnotes.last.label, 'unused');
      expect(doc.footnotes.last.index, 0);
      expect(doc.toHtml(), isNot(contains('Unused footnote definition')));
      expect(doc.toHtml(), contains('Unmatched reference[^missing]'));
    });

    test('parses PHP Extra definition lists with multi-paragraph bodies', () {
      final String source = File(
        '$root/extensions/definition_lists.md',
      ).readAsStringSync();
      final MarkdownDocument doc = engine.parse(source);

      final List<DefinitionListNode> lists = doc.blocks
          .whereType<DefinitionListNode>()
          .toList();
      expect(lists.length, 1);
      expect(lists.first.groups.length, 3);
      expect(lists.first.groups[0].definitions.length, 2);
      expect(lists.first.groups[1].definitions.first.length, 2);
      expect(doc.toHtml(), contains('<dl>'));
      expect(doc.toHtml(), contains('<dt><code>MarkdownOptions</code></dt>'));
    });

    test(
      'parses inline and display math while leaving currency amounts literal',
      () {
        final String source = File(
          '$root/extensions/math.md',
        ).readAsStringSync();
        final MarkdownDocument doc = engine.parse(source);

        final ParagraphNode firstPara = doc.blocks[0] as ParagraphNode;
        final List<MathInlineNode> inlineMaths = firstPara.children
            .whereType<MathInlineNode>()
            .toList();
        expect(inlineMaths.length, 2);
        expect(inlineMaths[0].latex, 'E = mc^2');

        final ParagraphNode currencyPara = doc.blocks[1] as ParagraphNode;
        expect(currencyPara.children.whereType<MathInlineNode>(), isEmpty);
        expect(currencyPara.toPlainText(), contains(r'$5 and $10 or $4.99'));
        expect(currencyPara.toPlainText(), contains(r'escaped $x$'));

        final List<MathBlockNode> blockMaths = doc.blocks
            .whereType<MathBlockNode>()
            .toList();
        expect(blockMaths.length, 1);
        expect(
          blockMaths.first.latex,
          r'\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}',
        );

        final BlockQuoteNode quote = doc.blocks
            .whereType<BlockQuoteNode>()
            .single;
        expect(
          quote.children.whereType<MathBlockNode>().single.latex,
          r'a^2 + b^2 = c^2',
        );
      },
    );

    test(
      'parses sub, sup, highlight, strike without interference, smart punctuation, and emoji',
      () {
        final String source = File(
          '$root/extensions/formatting.md',
        ).readAsStringSync();
        final MarkdownDocument doc = engine.parse(source);

        final ParagraphNode p1 = doc.blocks[0] as ParagraphNode;
        expect(p1.children.whereType<SubscriptNode>().length, 1);
        expect(p1.children.whereType<SuperscriptNode>().length, 1);
        expect(p1.children.whereType<HighlightNode>().length, 1);
        expect(p1.children.whereType<StrikethroughNode>().length, 1);

        final String html = doc.toHtml();
        expect(html, contains('H<sub>2</sub>O'));
        expect(html, contains('x<sup>2</sup>'));
        expect(html, contains('<mark>highlighted text</mark>'));
        expect(html, contains('<del>struck text</del>'));
        expect(html, contains('\u2013'));
        expect(html, contains('\u2014'));
        expect(html, contains('\u2026'));
        expect(html, contains('\u201Csmart quotes\u201D'));
        expect(html, contains('\u{1F680}'));
        expect(html, contains('href="https://example.com/docs"'));
        expect(html, contains('href="http://www.example.org"'));
      },
    );

    test('generates deduplicated UTF-8 heading slugs and document outline', () {
      final String source = File(
        '$root/extensions/heading_slugs.md',
      ).readAsStringSync();
      final MarkdownDocument doc = engine.parse(
        source,
        options: const MarkdownOptions.gfm(),
      );

      expect(doc.outline.length, 7);
      expect(
        doc.outline.map((MarkdownOutlineItem o) => o.slug).toList(),
        <String>[
          'overview',
          'overview-1',
          'overview-2',
          'api-reference-markdownengineparse',
          'getting-started--step-1',
          'café--résumé-utf-8-headings',
          '---leading-and-trailing---',
        ],
      );
      expect(doc.outline.first.line, 1);
    });

    test('parses all 7 HTML block conditions cleanly', () {
      final String source = File(
        '$root/extensions/html_blocks.md',
      ).readAsStringSync();
      final MarkdownDocument doc = engine.parse(
        source,
        options: const MarkdownOptions.commonMark(),
      );
      expect(doc.blocks.whereType<HtmlBlockNode>().length, 8);
      expect(doc.blocks.whereType<ParagraphNode>().length, 1);
    });

    test('parses extended block and inline AST containers', () {
      const String richSource = '''
# Custom Heading {#custom-id}

<details open>
<summary>Toggle **details**</summary>

Hidden paragraph.

</details>

<figure>

![Light](https://example.com/light.png)

<figcaption>Diagram caption</figcaption>

</figure>

<div align="center">

Centered block text.

</div>

Press <kbd>Cmd+K</kbd> for HTML and <a id="jump"></a><br />
<picture><source media="(prefers-color-scheme: dark)" srcset="https://example.com/dark.png"><img src="https://example.com/light2.png" alt="Theme logo"></picture>

*[HTML]: HyperText Markup Language
''';
      final MarkdownDocument doc = engine.parse(richSource);
      final HeadingNode heading = doc.blocks.whereType<HeadingNode>().single;
      expect(heading.explicitId, 'custom-id');
      expect(heading.slug, 'custom-id');

      final DetailsBlockNode details = doc.blocks
          .whereType<DetailsBlockNode>()
          .single;
      expect(details.initiallyOpen, isTrue);
      expect(details.summary, 'Toggle details');
      expect(details.children.length, 1);

      final FigureBlockNode figure = doc.blocks
          .whereType<FigureBlockNode>()
          .single;
      expect(figure.caption, 'Diagram caption');
      expect(figure.children.length, 1);

      final AlignedBlockNode aligned = doc.blocks
          .whereType<AlignedBlockNode>()
          .single;
      expect(aligned.alignment, TableAlignment.center);

      final ParagraphNode inlinePara = doc.blocks
          .whereType<ParagraphNode>()
          .single;
      expect(inlinePara.children.whereType<KbdInlineNode>().length, 1);
      expect(
        inlinePara.children.whereType<AbbrInlineNode>().single.title,
        'HyperText Markup Language',
      );
      expect(
        inlinePara.children.whereType<AnchorInlineNode>().single.id,
        'jump',
      );
      expect(inlinePara.children.whereType<InlineBreakNode>().length, 1);
      final PictureInlineNode pic = inlinePara.children
          .whereType<PictureInlineNode>()
          .single;
      expect(pic.lightSource, 'https://example.com/light2.png');
      expect(pic.darkSource, 'https://example.com/dark.png');
      expect(
        doc.remoteImageAddresses,
        containsAll(<String>[
          'https://example.com/light.png',
          'https://example.com/light2.png',
          'https://example.com/dark.png',
        ]),
      );
    });
  });

  group('Default math & LaTeX delimiters', () {
    const MarkdownEngine defaultEngine = MarkdownEngine();

    test(
      'parses inline \$...\$ and \\(...\\) out of the box with exact UTF-16 spans',
      () {
        const String src =
            r'Rocket 🚀 $E = mc^2$ and \( a^2 + b^2 = c^2 \) and *\(x_i\)*';
        final MarkdownDocument doc = defaultEngine.parse(src);
        final ParagraphNode para = doc.blocks.single as ParagraphNode;

        final List<MathInlineNode> inlineMaths = <MathInlineNode>[];
        for (final MarkdownInlineNode node in para.children) {
          if (node is MathInlineNode) {
            inlineMaths.add(node);
          } else if (node is EmphasisNode) {
            inlineMaths.addAll(node.children.whereType<MathInlineNode>());
          }
        }
        expect(inlineMaths.length, 3);
        expect(inlineMaths[0].latex, 'E = mc^2');
        expect(
          src.substring(
            inlineMaths[0].span.startOffset,
            inlineMaths[0].span.endOffset,
          ),
          r'$E = mc^2$',
        );
        expect(inlineMaths[1].latex, 'a^2 + b^2 = c^2');
        expect(
          src.substring(
            inlineMaths[1].span.startOffset,
            inlineMaths[1].span.endOffset,
          ),
          r'\( a^2 + b^2 = c^2 \)',
        );
        expect(inlineMaths[2].latex, 'x_i');
        expect(
          src.substring(
            inlineMaths[2].span.startOffset,
            inlineMaths[2].span.endOffset,
          ),
          r'\(x_i\)',
        );

        // Also works inside GFM pipe tables and links.
        final MarkdownDocument tableDoc = defaultEngine.parse(
          '| Expr | Link |\n| :--- | :--- |\n| \\(x^2\\) | [ref \\(y\\)](https://example.com) |\n',
        );
        final TableNode table = tableDoc.blocks.single as TableNode;
        expect(
          table.rows.single[0].children
              .whereType<MathInlineNode>()
              .single
              .latex,
          'x^2',
        );
        final LinkNode link = table.rows.single[1].children
            .whereType<LinkNode>()
            .single;
        expect(link.children.whereType<MathInlineNode>().single.latex, 'y');
      },
    );

    test(
      'keeps currency, escaped delimiters, and unbalanced \\( safe without eating text',
      () {
        const String src =
            r'Price $5 and $10, escaped \$x\$, escaped \\(y\), triple \\\(z\), empty \(\) \( \), unbalanced \(foo and *bold* and \*esc\*!';
        final MarkdownDocument doc = defaultEngine.parse(src);
        final ParagraphNode para = doc.blocks.single as ParagraphNode;
        final List<MathInlineNode> maths = para.children
            .whereType<MathInlineNode>()
            .toList();
        expect(maths.length, 1);
        expect(maths.single.latex, 'z');

        expect(
          para.children.whereType<EmphasisNode>().single.toPlainText(),
          'bold',
        );
        final String plain = para.toPlainText();
        expect(plain, contains(r'$5 and $10'));
        expect(plain, contains(r'$x$'));
        expect(plain, contains(r'\(y)'));
        expect(plain, contains('() ( )'));
        expect(plain, contains('(foo and bold and *esc*!'));

        // Unbalanced `\\(` before valid `\\(valid\\)` does not swallow valid math.
        final MarkdownDocument twoOpenDoc = defaultEngine.parse(
          r'First \( literal, then \(x^2\) done.',
        );
        final ParagraphNode twoOpenPara =
            twoOpenDoc.blocks.single as ParagraphNode;
        expect(
          twoOpenPara.children.whereType<MathInlineNode>().single.latex,
          'x^2',
        );
        expect(twoOpenPara.toPlainText(), contains('First ( literal'));
      },
    );

    test(
      'parses single-line, multi-line, and flexible \$\$...\$\$ and \\[...\\] display math',
      () {
        const String src = '''
\$\$ a^2 + b^2 = c^2 \$\$

\$\$
\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}
\$\$

\$\$ \\int_0^1 x\\,dx
= \\frac{1}{2}
\$\$

\$\$ \\sum_{i=1}^n i
= \\frac{n(n+1)}{2} \$\$

\\[ a^2 + b^2 = c^2 \\]

\\[
\\begin{aligned}
x &= 1 \\\\
y &= 2
\\end{aligned}
\\]

\\[ \\alpha +
\\beta = \\gamma \\]

> \\[
> e^{i\\pi} + 1 = 0
> \\]
''';
        final MarkdownDocument doc = defaultEngine.parse(src);
        final List<MathBlockNode> blocks = doc.blocks
            .whereType<MathBlockNode>()
            .toList();
        expect(blocks.length, 7);
        expect(blocks[0].latex, 'a^2 + b^2 = c^2');
        expect(
          blocks[1].latex,
          r'\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}',
        );
        expect(blocks[2].latex, '\\int_0^1 x\\,dx\n= \\frac{1}{2}');
        expect(blocks[3].latex, '\\sum_{i=1}^n i\n= \\frac{n(n+1)}{2}');
        expect(blocks[4].latex, 'a^2 + b^2 = c^2');
        expect(
          blocks[5].latex,
          '\\begin{aligned}\nx &= 1 \\\\\ny &= 2\n\\end{aligned}',
        );
        expect(blocks[6].latex, '\\alpha +\n\\beta = \\gamma');

        final BlockQuoteNode quote = doc.blocks
            .whereType<BlockQuoteNode>()
            .single;
        expect(
          quote.children.whereType<MathBlockNode>().single.latex,
          r'e^{i\pi} + 1 = 0',
        );
      },
    );

    test(
      'handles escaped \\\\[ / \\\\] and unbalanced \\[ / \$\$ without swallowing following blocks',
      () {
        const String src = '''
\\[unbalanced display opener

\\[not a link](https://example.com)

\\\\[not math\\]

\\[\ninside fenced check\n\n```
\\]
```

\$\$5 and \$10

Second paragraph intact.
''';
        final MarkdownDocument doc = defaultEngine.parse(src);
        expect(doc.blocks.whereType<MathBlockNode>(), isEmpty);
        expect(doc.blocks.whereType<ParagraphNode>().length, 6);
        expect(doc.blocks.whereType<CodeBlockNode>().length, 1);

        final String html = doc.toHtml();
        expect(html, contains('<p>[unbalanced display opener</p>'));
        expect(
          html,
          contains(
            '<p>[not a link](<a href="https://example.com">https://example.com</a>)</p>',
          ),
        );
        expect(html, contains('<p>\\[not math]</p>'));
        expect(html, contains('<p>Second paragraph intact.</p>'));

        // Escaped `\\]` (2 backslashes + `]`) must not close early; `\\\\\\]` (3 backslashes + `]`) does close.
        final MarkdownDocument escDoc = defaultEngine.parse(
          '\\[\nx \\\\]\n\\]\n\n\\[ y \\\\\\]',
        );
        final List<MathBlockNode> escBlocks = escDoc.blocks
            .whereType<MathBlockNode>()
            .toList();
        expect(escBlocks.length, 2);
        expect(escBlocks[0].latex, 'x \\\\]');
        expect(escBlocks[1].latex, 'y \\\\');
      },
    );

    test(
      'preserves strict CommonMark and GFM compliance when math is disabled',
      () {
        const String src = r'''Inline $E = mc^2$ and \(x^2\)

$$
a^2 + b^2 = c^2
$$

\[
c^2 = a^2 + b^2
\]
''';
        for (final MarkdownOptions opts in const <MarkdownOptions>[
          MarkdownOptions.commonMark(),
          MarkdownOptions.gfm(),
        ]) {
          final MarkdownDocument doc = defaultEngine.parse(src, options: opts);
          expect(doc.blocks.whereType<MathBlockNode>(), isEmpty);
          for (final ParagraphNode p in doc.blocks.whereType<ParagraphNode>()) {
            expect(p.children.whereType<MathInlineNode>(), isEmpty);
          }
          final String html = doc.toHtml();
          expect(html, contains(r'<p>Inline $E = mc^2$ and (x^2)</p>'));
          expect(html, contains('<p>[\nc^2 = a^2 + b^2\n]</p>'));
        }
      },
    );
  });

  group('Figure container parsing', () {
    const MarkdownEngine extEngine = MarkdownEngine(
      defaultOptions: MarkdownOptions.extended(),
    );

    test(
      'parses <figure> when <figcaption> and </figure> lack a blank line',
      () {
        const String src = '''
<figure>

```mermaid
flowchart LR
  YAML["Frontmatter"] --> Alerts["AlertNode"]
```

<figcaption>Figure 1: Structured extension nodes exposed in the **AST**.</figcaption>
</figure>
''';
        final MarkdownDocument doc = extEngine.parse(src);
        expect(doc.blocks.whereType<HtmlBlockNode>(), isEmpty);
        final FigureBlockNode figure = doc.blocks
            .whereType<FigureBlockNode>()
            .single;
        expect(figure.children.single, isA<CodeBlockNode>());
        expect(
          figure.caption,
          'Figure 1: Structured extension nodes exposed in the AST.',
        );
        expect(figure.captionInlines.whereType<StrongNode>().length, 1);
      },
    );

    test(
      'handles compact <figure>, multi-line <figcaption>, trailing HTML, and unclosed fallback',
      () {
        const String src = '''
<figure>
<figcaption>Line 1
Line 2</figcaption>
</figure>
<div class="after">Sibling HTML</div>

<figure>

![Photo](https://example.com/photo.png)

<figcaption>Caption mentioning `</figure>` literally</figcaption></figure>

<figure>

![Unclosed](https://example.com/unclosed.png)

<figcaption>Never closed
''';
        final MarkdownDocument doc = extEngine.parse(src);
        final List<FigureBlockNode> figures = doc.blocks
            .whereType<FigureBlockNode>()
            .toList();
        expect(figures.length, 2);

        expect(figures[0].children, isEmpty);
        expect(figures[0].caption, 'Line 1\nLine 2');

        expect(figures[1].children.single, isA<ParagraphNode>());
        expect(figures[1].caption, 'Caption mentioning </figure> literally');
        expect(figures[1].captionInlines.whereType<CodeSpanNode>().length, 1);

        final List<HtmlBlockNode> htmlBlocks = doc.blocks
            .whereType<HtmlBlockNode>()
            .toList();
        expect(
          htmlBlocks.any((HtmlBlockNode h) => h.html.contains('Sibling HTML')),
          isTrue,
        );
        expect(
          htmlBlocks.any((HtmlBlockNode h) => h.html.startsWith('<figure>')),
          isTrue,
        );
      },
    );
  });
}
