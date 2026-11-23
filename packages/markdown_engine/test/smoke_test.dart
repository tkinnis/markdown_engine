import 'package:markdown_engine/markdown_engine.dart';
import 'package:test/test.dart';

void main() {
  group('MarkdownOptions', () {
    test('provides documented defaults and presets', () {
      const MarkdownOptions defaults = MarkdownOptions();
      expect(defaults.gfmTables, isTrue);
      expect(defaults.gfmTagFilter, isTrue);
      expect(defaults.math, isTrue);
      expect(defaults.sanitizeUrls, isTrue);
      expect(defaults.maxInputLength, MarkdownOptions.defaultMaxInputLength);
      expect(defaults.maxNestingDepth, MarkdownOptions.defaultMaxNestingDepth);
      expect(defaults.highlight, isFalse);
      expect(defaults.subscript, isFalse);
      expect(defaults.superscript, isFalse);

      const MarkdownOptions commonMark = MarkdownOptions.commonMark();
      expect(commonMark.gfmTables, isFalse);
      expect(commonMark.gfmStrikethrough, isFalse);
      expect(commonMark.gfmTaskLists, isFalse);
      expect(commonMark.gfmAutolinks, isFalse);
      expect(commonMark.math, isFalse);

      const MarkdownOptions gfm = MarkdownOptions.gfm();
      expect(gfm.gfmTables, isTrue);
      expect(gfm.math, isFalse);

      const MarkdownOptions extended = MarkdownOptions.extended();
      expect(extended.alerts, isTrue);
      expect(extended.frontmatter, isTrue);
      expect(extended.math, isTrue);
      expect(extended.definitionLists, isTrue);
      expect(extended.highlight, isTrue);
      expect(extended.subscript, isTrue);
      expect(extended.superscript, isTrue);
      expect(extended.copyWith(alerts: false).alerts, isFalse);
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
