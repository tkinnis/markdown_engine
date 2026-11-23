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
  const MarkdownEngine engine = MarkdownEngine();
  final String root = _corpusRoot();

  group('Security & Sanitization', () {
    test('sanitizes XSS vectors when sanitizeHtml is enabled', () {
      final String source = File(
        '$root/security/xss_vectors.md',
      ).readAsStringSync();
      final MarkdownDocument doc = engine.parse(
        source,
        options: const MarkdownOptions.gfm(sanitizeHtml: true),
      );
      final String html = doc.toHtml();
      final String lower = html.toLowerCase();

      expect(lower, isNot(contains('<script')));
      expect(lower, isNot(contains('<svg')));
      expect(lower, isNot(contains('<iframe')));
      expect(lower, isNot(contains('<style')));
      expect(lower, isNot(contains('onerror=')));
      expect(lower, isNot(contains('onload=')));
      expect(lower, isNot(contains('onclick=')));
      expect(lower, isNot(contains('javascript:')));
      expect(html, contains('<div>Click</div>'));
      expect(html, contains('id="fn-%22%3E%3Cscript%3Ealert(3)%3C/script%3E"'));
    });

    test(
      'blocks dangerous URL schemes including control-character obfuscation',
      () {
        final String source = File(
          '$root/security/unsafe_urls.md',
        ).readAsStringSync();
        final MarkdownDocument doc = engine.parse(
          source,
          options: const MarkdownOptions.gfm(sanitizeUrls: true),
        );
        final String html = doc.toHtml();
        final String lower = html.toLowerCase();

        expect(lower, isNot(contains('javascript:')));
        expect(lower, isNot(contains('vbscript:')));
        expect(lower, isNot(contains('data:text/html')));

        // Safe schemes remain intact.
        expect(html, contains('href="https://example.com/docs"'));
        expect(html, contains('href="http://example.com"'));
        expect(html, contains('href="mailto:security@example.com"'));
        expect(html, contains('href="#section-1"'));
        expect(html, contains('href="/docs/reference"'));
      },
    );

    test('MarkdownUrlPolicy enforces allowlists and safe data images', () {
      const MarkdownUrlPolicy strict = MarkdownUrlPolicy(
        allowedSchemes: <String>{'https'},
        allowedHosts: <String>{'docs.example.com'},
        allowRelative: false,
        allowFragments: false,
        allowSafeImageDataUrls: true,
      );

      expect(strict.isAllowed('https://docs.example.com/guide'), isTrue);
      expect(strict.isAllowed('https://evil.example.com/guide'), isFalse);
      expect(strict.isAllowed('http://docs.example.com/guide'), isFalse);
      expect(strict.isAllowed('/relative/path'), isFalse);
      expect(strict.isAllowed('#frag'), isFalse);
      expect(strict.isAllowed('data:image/png;base64,iVBORw0KGgo='), isTrue);
      expect(strict.isAllowed('data:image/svg+xml;base64,PHN2Zz4='), isFalse);
      expect(strict.isAllowed('java\x09script:alert(1)'), isFalse);
    });

    test('handles deep nesting without stack overflow or quadratic hang', () {
      final String source = File(
        '$root/security/deep_nesting.md',
      ).readAsStringSync();
      final MarkdownDocument doc = engine.parse(
        source,
        options: const MarkdownOptions.gfm(maxNestingDepth: 64),
      );
      expect(doc.blocks, isNotEmpty);
      expect(doc.toHtml(), isNotEmpty);

      // Verify block nesting never exceeds maxNestingDepth.
      int measureQuoteDepth(MarkdownBlockNode node) {
        if (node is BlockQuoteNode) {
          int maxChild = 0;
          for (final MarkdownBlockNode c in node.children) {
            final int d = measureQuoteDepth(c);
            if (d > maxChild) {
              maxChild = d;
            }
          }
          return 1 + maxChild;
        }
        return 0;
      }

      expect(measureQuoteDepth(doc.blocks.first), lessThanOrEqualTo(64));
    });

    test(
      'parses large table and enforces table row/column/block/html budgets',
      () {
        final String source = File(
          '$root/security/large_table.md',
        ).readAsStringSync();
        final MarkdownDocument full = engine.parse(source);
        final TableNode table = full.blocks.single as TableNode;
        expect(table.headers.length, 6);
        expect(table.rows.length, 120);

        final MarkdownDocument rowBounded = engine.parse(
          source,
          options: const MarkdownOptions.gfm(
            budgets: MarkdownBudgets(maxTableRows: 10),
          ),
        );
        final TableNode cappedTable = rowBounded.blocks.first as TableNode;
        expect(cappedTable.rows.length, 10);

        final MarkdownDocument colBounded = engine.parse(
          source,
          options: const MarkdownOptions.gfm(
            budgets: MarkdownBudgets(maxTableColumns: 3),
          ),
        );
        expect(colBounded.blocks.whereType<TableNode>(), isEmpty);

        final MarkdownDocument blockBounded = engine.parse(
          'P1\n\nP2\n\nP3\n\nP4\n\nP5\n',
          options: const MarkdownOptions.gfm(
            budgets: MarkdownBudgets(maxBlocks: 2),
          ),
        );
        expect(blockBounded.blocks.length, lessThanOrEqualTo(2));

        final MarkdownDocument htmlBounded = engine.parse(
          '<div class="a">one</div>\n\n<div class="b">two</div>\n',
          options: const MarkdownOptions.gfm(
            budgets: MarkdownBudgets(maxHtmlBytes: 20),
          ),
        );
        expect(
          htmlBounded.toHtml(),
          contains('&lt;div class=&quot;b&quot;&gt;'),
        );
      },
    );
  });
}
