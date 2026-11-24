import 'package:markdown_engine/markdown_engine.dart';
import 'package:test/test.dart';

void main() {
  group('MarkdownOptions', () {
    test('provides documented defaults and presets', () {
      const MarkdownOptions defaults = MarkdownOptions();
      expect(defaults.gfmTables, isTrue);
      expect(defaults.gfmStrikethrough, isTrue);
      expect(defaults.gfmTaskLists, isTrue);
      expect(defaults.gfmAutolinks, isTrue);
      expect(defaults.gfmTagFilter, isTrue);
      expect(defaults.footnotes, isTrue);
      expect(defaults.alerts, isTrue);
      expect(defaults.frontmatter, isTrue);
      expect(defaults.definitionLists, isTrue);
      expect(defaults.math, isTrue);
      expect(defaults.headingSlugs, isTrue);
      expect(defaults.highlight, isTrue);
      expect(defaults.subscript, isTrue);
      expect(defaults.superscript, isTrue);
      expect(defaults.emoji, isTrue);
      expect(defaults.smartPunctuation, isTrue);
      expect(defaults.explicitHeadingIds, isTrue);
      expect(defaults.detailsBlocks, isTrue);
      expect(defaults.figureBlocks, isTrue);
      expect(defaults.alignedBlocks, isTrue);
      expect(defaults.kbd, isTrue);
      expect(defaults.abbreviations, isTrue);
      expect(defaults.inlineBreaks, isTrue);
      expect(defaults.sanitizeHtml, isFalse);
      expect(defaults.sanitizeUrls, isTrue);
      expect(defaults.collapseNestedStrong, isFalse);
      expect(defaults.maxInputLength, MarkdownOptions.defaultMaxInputLength);
      expect(defaults.maxNestingDepth, MarkdownOptions.defaultMaxNestingDepth);

      const MarkdownOptions optOut = MarkdownOptions(
        gfmTables: false,
        gfmStrikethrough: false,
        gfmTaskLists: false,
        gfmAutolinks: false,
        gfmTagFilter: false,
        footnotes: false,
        alerts: false,
        frontmatter: false,
        definitionLists: false,
        math: false,
        headingSlugs: false,
        highlight: false,
        subscript: false,
        superscript: false,
        emoji: false,
        smartPunctuation: false,
        explicitHeadingIds: false,
        detailsBlocks: false,
        figureBlocks: false,
        alignedBlocks: false,
        kbd: false,
        abbreviations: false,
        inlineBreaks: false,
      );
      expect(optOut.gfmTables, isFalse);
      expect(optOut.gfmStrikethrough, isFalse);
      expect(optOut.gfmTaskLists, isFalse);
      expect(optOut.gfmAutolinks, isFalse);
      expect(optOut.gfmTagFilter, isFalse);
      expect(optOut.footnotes, isFalse);
      expect(optOut.alerts, isFalse);
      expect(optOut.frontmatter, isFalse);
      expect(optOut.definitionLists, isFalse);
      expect(optOut.math, isFalse);
      expect(optOut.headingSlugs, isFalse);
      expect(optOut.highlight, isFalse);
      expect(optOut.subscript, isFalse);
      expect(optOut.superscript, isFalse);
      expect(optOut.emoji, isFalse);
      expect(optOut.smartPunctuation, isFalse);
      expect(optOut.explicitHeadingIds, isFalse);
      expect(optOut.detailsBlocks, isFalse);
      expect(optOut.figureBlocks, isFalse);
      expect(optOut.alignedBlocks, isFalse);
      expect(optOut.kbd, isFalse);
      expect(optOut.abbreviations, isFalse);
      expect(optOut.inlineBreaks, isFalse);

      const MarkdownOptions commonMark = MarkdownOptions.commonMark();
      expect(commonMark.gfmTables, isFalse);
      expect(commonMark.gfmStrikethrough, isFalse);
      expect(commonMark.gfmTaskLists, isFalse);
      expect(commonMark.gfmAutolinks, isFalse);
      expect(commonMark.gfmTagFilter, isFalse);
      expect(commonMark.footnotes, isFalse);
      expect(commonMark.alerts, isFalse);
      expect(commonMark.frontmatter, isFalse);
      expect(commonMark.definitionLists, isFalse);
      expect(commonMark.math, isFalse);
      expect(commonMark.headingSlugs, isFalse);
      expect(commonMark.highlight, isFalse);
      expect(commonMark.subscript, isFalse);
      expect(commonMark.superscript, isFalse);
      expect(commonMark.emoji, isFalse);
      expect(commonMark.smartPunctuation, isFalse);
      expect(commonMark.explicitHeadingIds, isFalse);
      expect(commonMark.detailsBlocks, isFalse);
      expect(commonMark.figureBlocks, isFalse);
      expect(commonMark.alignedBlocks, isFalse);
      expect(commonMark.kbd, isFalse);
      expect(commonMark.abbreviations, isFalse);
      expect(commonMark.inlineBreaks, isFalse);

      const MarkdownOptions gfm = MarkdownOptions.gfm();
      expect(gfm.gfmTables, isTrue);
      expect(gfm.gfmStrikethrough, isTrue);
      expect(gfm.gfmTaskLists, isTrue);
      expect(gfm.gfmAutolinks, isTrue);
      expect(gfm.gfmTagFilter, isTrue);
      expect(gfm.footnotes, isTrue);
      expect(gfm.headingSlugs, isTrue);
      expect(gfm.alerts, isFalse);
      expect(gfm.frontmatter, isFalse);
      expect(gfm.definitionLists, isFalse);
      expect(gfm.math, isFalse);
      expect(gfm.highlight, isFalse);
      expect(gfm.subscript, isFalse);
      expect(gfm.superscript, isFalse);
      expect(gfm.emoji, isFalse);
      expect(gfm.smartPunctuation, isFalse);
      expect(gfm.explicitHeadingIds, isFalse);
      expect(gfm.detailsBlocks, isFalse);
      expect(gfm.figureBlocks, isFalse);
      expect(gfm.alignedBlocks, isFalse);
      expect(gfm.kbd, isFalse);
      expect(gfm.abbreviations, isFalse);
      expect(gfm.inlineBreaks, isFalse);

      const MarkdownOptions extended = MarkdownOptions.extended();
      expect(extended.alerts, isTrue);
      expect(extended.frontmatter, isTrue);
      expect(extended.math, isTrue);
      expect(extended.definitionLists, isTrue);
      expect(extended.highlight, isTrue);
      expect(extended.subscript, isTrue);
      expect(extended.superscript, isTrue);
      expect(extended.copyWith(alerts: false).alerts, isFalse);
      expect(
        defaults.copyWith(smartPunctuation: false).smartPunctuation,
        isFalse,
      );
    });

    test('renders all extended syntax out of the box with default options', () {
      const MarkdownEngine engine = MarkdownEngine();
      final MarkdownDocument doc = engine.parse('''
---
title: Default Suite
---

# Custom Heading {#my-id}

> [!NOTE]
> Alert body with ==mark==, H~2~O, 2^10^, :rocket:, "smart" -- text...

Term
: Definition

<details>
<summary>Details</summary>

Press <kbd>Cmd</kbd> for HTML<br />

</details>

*[HTML]: HyperText Markup Language

Footnote[^1].

[^1]: Footnote body.
''');
      expect(doc.frontmatter?['title'], 'Default Suite');
      expect(doc.blocks.whereType<AlertNode>(), isNotEmpty);
      expect(doc.blocks.whereType<DefinitionListNode>(), isNotEmpty);
      expect(doc.blocks.whereType<DetailsBlockNode>(), isNotEmpty);
      expect(doc.blocks.whereType<FootnoteSectionNode>(), isNotEmpty);
      final String html = doc.toHtml();
      expect(html, contains('id="my-id"'));
      expect(html, contains('<mark>mark</mark>'));
      expect(html, contains('H<sub>2</sub>O'));
      expect(html, contains('2<sup>10</sup>'));
      expect(html, contains('\u{1F680}'));
      expect(html, contains('\u201Csmart\u201D \u2013 text\u2026'));
      expect(html, contains('<kbd>Cmd</kbd>'));
      expect(
        html,
        contains('<abbr title="HyperText Markup Language">HTML</abbr>'),
      );
      expect(html, contains('<br />'));
    });
  });

  group('MarkdownEngine & MarkdownDocument', () {
    test(
      'parses empty and multi-block Markdown documents deterministically',
      () {
        const MarkdownEngine engine = MarkdownEngine();

        final MarkdownDocument empty = engine.parse('   \n\n  ');
        expect(empty.isEmpty, isTrue);
        expect(empty.toHtml(), '');
        expect(empty.toPlainText(), '');

        final MarkdownDocument doc = engine.parse(
          'Hello <world>\n\nSecond line',
        );
        expect(doc.blocks.length, 2);
        expect(doc.blocks.first, isA<ParagraphNode>());
        expect(
          doc.blocks.map((MarkdownBlockNode b) => b.toPlainText()).toList(),
          <String>['Hello ', 'Second line'],
        );
        expect(doc.toHtml(), '<p>Hello <world></p>\n<p>Second line</p>\n');
        expect(doc.toPlainText(), 'Hello \n\nSecond line');
        expect(engine.renderToHtml('Single'), '<p>Single</p>\n');
      },
    );

    test('enforces maxInputLength guard', () {
      const MarkdownEngine bounded = MarkdownEngine(
        defaultOptions: MarkdownOptions(maxInputLength: 8),
      );
      expect(() => bounded.parse('123456789'), throwsA(isA<RangeError>()));
    });
  });
}
