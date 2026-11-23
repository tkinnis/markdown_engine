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
}
