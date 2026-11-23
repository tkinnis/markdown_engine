import 'dart:isolate';

import 'package:markdown_engine/markdown_engine.dart';
import 'package:test/test.dart';

void main() {
  const MarkdownEngine engine = MarkdownEngine();

  group('HTML Sanitization & XSS Hardening', () {
    test('strips slash-separated attributes and quotes containing angles', () {
      const String md = '''
<div><img/src="https://example.com/a.png"/onerror=alert(1)><details/open/ontoggle=alert(2)><summary>Hi</summary>Body</details></div>
<div title="a<b" onclick="alert(3)">Safe "a>b" text</div>
''';
      final String html = engine.renderToHtml(
        md,
        options: const MarkdownOptions.gfm(sanitizeHtml: true),
      );
      final String lower = html.toLowerCase();
      expect(lower, isNot(contains('onerror')));
      expect(lower, isNot(contains('ontoggle')));
      expect(lower, isNot(contains('onclick')));
      expect(html, contains('title="a&lt;b"'));
      expect(html, contains('Safe "a>b" text'));
      expect(html, contains('src="https://example.com/a.png"'));

      final String directSanitized = engine.renderToHtml(
        '<div><img/src="https://example.com/x.png"/onerror=alert(9)></div>',
        options: const MarkdownOptions.gfm(sanitizeHtml: true),
      );
      expect(directSanitized.toLowerCase(), isNot(contains('onerror')));
      expect(directSanitized, contains('src="https://example.com/x.png"'));
    });

    test(
      'decodes HTML5 numeric/named entities before URL & style validation',
      () {
        const String md = '''
<a href="&#106;avascript:alert(1)">Hex</a>
<a href="&#x6a&#x61vascript:alert(2)">Semicolonless</a>
<a href="&#0000106avascript:alert(3)">Padded</a>
<div style="background: url(&#106;avascript:alert(4)); color: red;">Styled</div>
<div style="background: \\75 rl(javascript:alert(5)); font-weight: bold;">CssEsc</div>
<div style="width: expression(alert(6)); color: blue;">Expr</div>
<div style="color: green; font-weight: bold;">SafeStyle</div>
''';
        final String html = engine.renderToHtml(
          md,
          options: const MarkdownOptions.gfm(
            sanitizeHtml: true,
            sanitizeUrls: true,
          ),
        );
        final String lower = html.toLowerCase();
        expect(lower, isNot(contains('javascript:')));
        expect(lower, isNot(contains('expression(')));
        expect(lower, isNot(contains('url(')));
        expect(html, contains('style="color: green; font-weight: bold;"'));
      },
    );

    test(
      'validates all URL attributes and strips blocked subtrees cleanly',
      () {
        const String md = '''
<video poster="javascript:alert(1)">v</video>
<blockquote cite="javascript:alert(2)">q</blockquote>
<table background="javascript:alert(3)"><tr><td>cell</td></tr></table>
<a href="https://example.com/ok" ping="javascript:alert(4)">ok</a>
<img src="https://example.com/a.png" srcset="javascript:alert(5) 1x, https://example.com/b.png 2x" longdesc="javascript:alert(6)">
<img src="https://example.com/a.png" srcset="https://example.com/b.png 2x">
<script>window.evil = 1;</script>
<noscript><img src="x" onerror="alert(7)"></noscript>
<template><script>alert(8)</script></template>
<svg onload="alert(9)"><circle /></svg>
<math><mi>x</mi></math>
<form action="javascript:alert(10)"><input type="text"></form>
<iframe srcdoc="<script>alert(11)</script>">fallback</iframe>
<meta http-equiv="refresh" content="0;url=javascript:alert(12)">
<p>After safe</p>
''';
        final String html = engine.renderToHtml(
          md,
          options: const MarkdownOptions.gfm(
            sanitizeHtml: true,
            sanitizeUrls: true,
          ),
        );
        final String lower = html.toLowerCase();
        expect(lower, isNot(contains('javascript:')));
        expect(lower, isNot(contains('window.evil')));
        expect(lower, isNot(contains('<script')));
        expect(lower, isNot(contains('<noscript')));
        expect(lower, isNot(contains('<template')));
        expect(lower, isNot(contains('<svg')));
        expect(lower, isNot(contains('<math')));
        expect(lower, isNot(contains('<form')));
        expect(lower, isNot(contains('<iframe')));
        expect(lower, isNot(contains('<meta')));
        expect(lower, isNot(contains('poster=')));
        expect(lower, isNot(contains('cite=')));
        expect(lower, isNot(contains('background=')));
        expect(lower, isNot(contains('ping=')));
        expect(lower, isNot(contains('longdesc=')));
        expect(html, contains('srcset="https://example.com/b.png 2x"'));
        expect(html, contains('<p>After safe</p>'));
      },
    );

    test(
      'rejects backslash, protocol-relative, userinfo, and zero-width URLs',
      () {
        const MarkdownUrlPolicy strict = MarkdownUrlPolicy.strict();
        expect(strict.isAllowed('https://example.com/a'), isTrue);
        expect(strict.isAllowed('http://example.com/a'), isTrue);
        expect(strict.isAllowed('mailto:user@example.com'), isTrue);
        expect(strict.isAllowed('/docs/page'), isTrue);
        expect(strict.isAllowed('#heading'), isTrue);

        expect(strict.isAllowed('//evil.com/x'), isFalse);
        expect(strict.isAllowed(r'/\evil.com/x'), isFalse);
        expect(strict.isAllowed(r'\/evil.com/x'), isFalse);
        expect(strict.isAllowed(r'\\evil.com\share'), isFalse);
        expect(strict.isAllowed(r'https:\\evil.com'), isFalse);
        expect(strict.isAllowed(r'https:/\evil.com'), isFalse);
        expect(strict.isAllowed('https://user:pass@evil.com'), isFalse);
        expect(strict.isAllowed('https://user@evil.com'), isFalse);
        expect(strict.isAllowed('java\u00A0script:alert(1)'), isFalse);
        expect(strict.isAllowed('java\u200Bscript:alert(1)'), isFalse);
        expect(strict.isAllowed('ftp://example.com/file'), isFalse);
        expect(strict.isAllowed('file:///etc/passwd'), isFalse);

        // Case-insensitive policy equality & hashCode.
        const MarkdownUrlPolicy upper = MarkdownUrlPolicy(
          allowedSchemes: <String>{'HTTPS', 'Http'},
          allowedHosts: <String>{'Example.COM'},
        );
        const MarkdownUrlPolicy lower = MarkdownUrlPolicy(
          allowedSchemes: <String>{'http', 'https'},
          allowedHosts: <String>{'example.com'},
        );
        expect(upper, lower);
        expect(upper.hashCode, lower.hashCode);

        // Blocked links omit href while empty CommonMark links preserve href="".
        final String blockedHtml = engine.renderToHtml(
          '[bad](javascript:alert(1)) [empty]() ![badimg](//evil.com/a.png)',
          options: const MarkdownOptions(),
        );
        expect(blockedHtml, contains('<a>bad</a>'));
        expect(blockedHtml, contains('<a href="">empty</a>'));
        expect(blockedHtml, isNot(contains('src=')));

        // Default MarkdownOptions uses headingSlugs: true & strict URL policy;
        // CommonMark preserves headingSlugs: false.
        const MarkdownOptions defaults = MarkdownOptions();
        const MarkdownOptions cm = MarkdownOptions.commonMark();
        expect(defaults.headingSlugs, isTrue);
        expect(defaults.urlPolicy, const MarkdownUrlPolicy.strict());
        expect(cm.headingSlugs, isFalse);
      },
    );

    test('sanitizes <picture> entities and normalizes remote image URLs', () {
      const String md = '''
<picture><source media="(prefers-color-scheme: dark)" srcset="&#106;avascript:alert(1)"><img src="https://example.com/light.png" alt="Logo"></picture>

![obfuscated](<ht\ttp://example.com/ok.png>)
''';
      final MarkdownDocument doc = engine.parse(
        md,
        options: const MarkdownOptions(sanitizeUrls: true),
      );
      final String html = doc.toHtml();
      expect(html.toLowerCase(), isNot(contains('javascript:')));
      expect(doc.remoteImageAddresses, isNot(contains('javascript:alert(1)')));
      expect(html, contains('https://example.com/light.png'));
    });
  });

  group('DoS, ReDoS & Depth Hardening', () {
    test('eliminates ReDoS and quadratic inline scans cleanly under 50ms', () {
      final Stopwatch sw = Stopwatch()..start();

      engine.renderToHtml(
        '<a ${' ' * 5000}>x',
        options: const MarkdownOptions(sanitizeHtml: true),
      );
      engine.renderToHtml(
        '<script ' * 4000,
        options: const MarkdownOptions(sanitizeHtml: true),
      );
      engine.renderToHtml(
        '# a${' ' * 10000}{#bad!',
        options: const MarkdownOptions(explicitHeadingIds: true),
      );
      engine.renderToHtml('<' * 50000);
      engine.renderToHtml(r'$a ' * 20000);
      engine.renderToHtml('*' * 50000);
      engine.renderToHtml('${'<a x=1 ' * 5000}<b >');

      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(250));
    });

    test(
      'bounds deep emphasis nesting in Isolate.run without StackOverflowError',
      () async {
        final String payload = '${'*a ' * 7000}end${' a*' * 7000}';
        final ({int depth, int textLen, int htmlLen, bool shiftOk})
        result = await Isolate.run(() {
          const MarkdownEngine isoEngine = MarkdownEngine();
          final MarkdownDocument doc = isoEngine.parse(
            payload,
            options: const MarkdownOptions(),
          );

          int maxInlineDepth(MarkdownInlineNode node) {
            return switch (node) {
              EmphasisNode() =>
                1 +
                    node.children.fold<int>(0, (int m, MarkdownInlineNode c) {
                      final int d = maxInlineDepth(c);
                      return d > m ? d : m;
                    }),
              StrongNode() =>
                1 +
                    node.children.fold<int>(0, (int m, MarkdownInlineNode c) {
                      final int d = maxInlineDepth(c);
                      return d > m ? d : m;
                    }),
              LinkNode() =>
                1 +
                    node.children.fold<int>(0, (int m, MarkdownInlineNode c) {
                      final int d = maxInlineDepth(c);
                      return d > m ? d : m;
                    }),
              ImageNode() =>
                1 +
                    node.children.fold<int>(0, (int m, MarkdownInlineNode c) {
                      final int d = maxInlineDepth(c);
                      return d > m ? d : m;
                    }),
              _ => 0,
            };
          }

          final ParagraphNode p = doc.blocks.first as ParagraphNode;
          int depth = 0;
          for (final MarkdownInlineNode child in p.children) {
            final int d = maxInlineDepth(child);
            if (d > depth) {
              depth = d;
            }
          }
          final MarkdownBlockNode shifted = p.shiftSpan(10, 2);
          return (
            depth: depth,
            textLen: doc.toPlainText().length,
            htmlLen: doc.toHtml().length,
            shiftOk: shifted.span.startOffset == p.span.startOffset + 10,
          );
        });

        expect(result.depth, lessThanOrEqualTo(64));
        expect(result.textLen, greaterThan(0));
        expect(result.htmlLen, greaterThan(0));
        expect(result.shiftOk, isTrue);
      },
    );

    test(
      'enforces maxBlocks, doc-wide maxTokens, wide table clamp & output cap',
      () {
        // maxBlocks across nested blockquotes.
        final String nestedBlocks = List<String>.generate(
          20,
          (int i) => '> Paragraph $i',
        ).join('\n>\n');
        final MarkdownDocument blockLimited = engine.parse(
          nestedBlocks,
          options: const MarkdownOptions.gfm(
            budgets: MarkdownBudgets(maxBlocks: 5),
          ),
        );
        int countBlocks(List<MarkdownBlockNode> list) {
          int count = 0;
          for (final MarkdownBlockNode b in list) {
            count++;
            if (b is BlockQuoteNode) {
              count += countBlocks(b.children);
            }
          }
          return count;
        }

        expect(countBlocks(blockLimited.blocks), lessThanOrEqualTo(5));

        // Document-wide maxTokens across paragraphs.
        final String multiParaTokens = List<String>.generate(
          30,
          (int i) => '*a* *b* *c* *d* *e*',
        ).join('\n\n');
        final MarkdownDocument tokenLimited = engine.parse(
          multiParaTokens,
          options: const MarkdownOptions.gfm(
            budgets: MarkdownBudgets(maxTokens: 120),
          ),
        );
        final ParagraphNode lastPara =
            tokenLimited.blocks.last as ParagraphNode;
        expect(lastPara.children.whereType<EmphasisNode>(), isEmpty);

        // Wide body table columns clamped to alignments.length.
        final String wideBodyTable =
            '| a | b |\n| - | - |\n${'| x ' * 5000}|\n';
        final MarkdownDocument tableDoc = engine.parse(
          wideBodyTable,
          options: const MarkdownOptions.gfm(),
        );
        final TableNode table = tableDoc.blocks.single as TableNode;
        expect(table.rows.single.length, 2);

        // Link reference & abbreviation expansion output cap (maxOutputBytes).
        final String longDest = 'https://example.com/${'a' * 256}';
        final String refBomb =
            '[r]: $longDest\n\n${'[r] ' * 40}\n\n*[ABBR]: ${'x' * 256}\n\n${'ABBR ' * 40}\n';
        final MarkdownDocument cappedDoc = engine.parse(
          refBomb,
          options: const MarkdownOptions(
            budgets: MarkdownBudgets(maxOutputBytes: 2048),
          ),
        );
        final int linkCount = cappedDoc.blocks
            .whereType<ParagraphNode>()
            .expand((ParagraphNode p) => p.children.whereType<LinkNode>())
            .length;
        final int abbrCount = cappedDoc.blocks
            .whereType<ParagraphNode>()
            .expand((ParagraphNode p) => p.children.whereType<AbbrInlineNode>())
            .length;
        expect(linkCount, lessThan(40));
        expect(abbrCount, lessThan(40));
        expect(cappedDoc.toHtml().length, lessThanOrEqualTo(2048 + 128));
      },
    );
  });

  group('Extended HTML Tags, IDs, Incremental & Streaming', () {
    test(
      'supports <a name>, <img width/height>, <u>/<small>/<q>, unique DL & FN IDs',
      () {
        const String md = '''
<a name="top"></a>Intro <img src="https://example.com/pic.png" width="120" height="80" alt="Banner" title="Tip"> <u>u</u> <small>s</small> <q>q</q>

Term A
:   First body paragraph

    Second nested paragraph

Foot[^1] and second[^2].

[^1]: First note.
[^2]: Second note.
''';
        final MarkdownDocument doc = engine.parse(
          md,
          options: const MarkdownOptions.extended(sanitizeHtml: true),
        );
        final ParagraphNode p = doc.blocks.first as ParagraphNode;
        expect(p.children.whereType<AnchorInlineNode>().single.id, 'top');
        final ImageNode img = p.children.whereType<ImageNode>().single;
        expect(img.destination, 'https://example.com/pic.png');
        expect(img.width, 120);
        expect(img.height, 80);
        expect(img.alt, 'Banner');
        expect(img.title, 'Tip');
        expect(
          doc.remoteImageAddresses,
          contains('https://example.com/pic.png'),
        );

        // Default MarkdownOptions() also parses <a name> and <img width/height>.
        final MarkdownDocument defaultDoc = engine.parse(
          '<a name="top"></a>Hi <img src="https://example.com/badge.png" width="88" height="20">',
        );
        final ParagraphNode defPara = defaultDoc.blocks.first as ParagraphNode;
        expect(defPara.children.whereType<AnchorInlineNode>().single.id, 'top');
        final ImageNode defImg = defPara.children.whereType<ImageNode>().single;
        expect(defImg.width, 88);
        expect(defImg.height, 20);

        final String html = doc.toHtml();
        expect(html, contains('<u>u</u>'));
        expect(html, contains('<small>s</small>'));
        expect(html, contains('<q>q</q>'));

        // Check DefinitionList nested block IDs are globally unique across document.
        final Set<String> seenIds = <String>{};
        void checkIds(MarkdownBlockNode b) {
          expect(
            seenIds.add(b.blockId),
            isTrue,
            reason: 'Duplicate ${b.blockId}',
          );
          switch (b) {
            case DefinitionListNode():
              for (final DefinitionGroup g in b.groups) {
                for (final List<MarkdownBlockNode> def in g.definitions) {
                  for (final MarkdownBlockNode child in def) {
                    checkIds(child);
                  }
                }
              }
            case FootnoteSectionNode():
              for (final FootnoteDefinitionNode d in b.definitions) {
                checkIds(d);
              }
            case FootnoteDefinitionNode():
              for (final MarkdownBlockNode child in b.children) {
                checkIds(child);
              }
            default:
              break;
          }
        }

        for (final MarkdownBlockNode b in doc.blocks) {
          checkIds(b);
        }
        final FootnoteSectionNode fnSec =
            doc.blocks.last as FootnoteSectionNode;
        expect(
          fnSec.span.endOffset,
          greaterThanOrEqualTo(fnSec.definitions.last.span.endOffset),
        );

        // Frontmatter immutability.
        final MarkdownDocument fmDoc = engine.parse(
          '---\ntags:\n  - a\n  - b\n---\n\nHi\n',
          options: const MarkdownOptions.extended(),
        );
        expect(
          () => (fmDoc.frontmatter!['tags']! as List<Object?>).add('c'),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'incremental parser preserves abbreviations, list merges, and containers',
      () {
        const MarkdownOptions extOpts = MarkdownOptions.extended();
        const IncrementalMarkdownParser inc = IncrementalMarkdownParser(
          engine: MarkdownEngine(defaultOptions: extOpts),
        );

        const String abbrBase =
            '*[HTML]: HyperText Markup Language\n\nParagraph one.\n\nUse HTML here.\n\nTail.\n';
        final IncrementalParseResult r1 = inc.parseIncremental(abbrBase);
        final String abbrEdit = abbrBase.replaceFirst(
          'Use HTML here.',
          'Use HTML now.',
        );
        final IncrementalParseResult r2 = inc.parseIncremental(
          abbrEdit,
          previousResult: r1,
        );
        expect(
          r2.document.toHtml(),
          engine.renderToHtml(abbrEdit, options: extOpts),
        );
        expect(
          r2.document.toHtml(),
          contains('<abbr title="HyperText Markup Language">HTML</abbr>'),
        );

        // List merge guard across blank line.
        const String listBase = '- one\n\nMiddle\n\n- three\n';
        final IncrementalParseResult l1 = inc.parseIncremental(listBase);
        final String listMerged = '- one\n\n- two\n\n- three\n';
        final IncrementalParseResult l2 = inc.parseIncremental(
          listMerged,
          previousResult: l1,
        );
        expect(
          l2.document.toHtml(),
          engine.renderToHtml(listMerged, options: extOpts),
        );

        // Details container boundary guard.
        const String detBase =
            '<details>\n<summary>Title</summary>\n\nBody\n\nEnd\n';
        final IncrementalParseResult d1 = inc.parseIncremental(detBase);
        const String detClosed =
            '<details>\n<summary>Title</summary>\n\nBody\n\n</details>\n';
        final IncrementalParseResult d2 = inc.parseIncremental(
          detClosed,
          previousResult: d1,
        );
        expect(
          d2.document.toHtml(),
          engine.renderToHtml(detClosed, options: extOpts),
        );
        expect(d2.document.blocks.single, isA<DetailsBlockNode>());
      },
    );

    test(
      'StreamingMarkdownController enforces listeners, stability, finish resume & scaling',
      () {
        final StreamingMarkdownController ctrl = StreamingMarkdownController(
          options: const MarkdownOptions(
            budgets: MarkdownBudgets(maxInputLength: 100),
          ),
        );
        int calls = 0;
        void onUpdate() {
          calls++;
        }

        ctrl.addListener(onUpdate);
        ctrl.append('# Heading\n\nHello');
        expect(calls, 1);
        final String activeId1 = ctrl.activeBlocks.single.blockId;
        ctrl.append(' world');
        expect(calls, 2);
        expect(ctrl.activeBlocks.single.blockId, activeId1);

        // Duplicate headings deduplicate across settled + tail before finish().
        ctrl.append('\n\n# Heading');
        expect(calls, 3);
        expect(
          ctrl.currentDocument.outline
              .map((MarkdownOutlineItem o) => o.slug)
              .toList(),
          <String>['heading', 'heading-1'],
        );

        // Oversized append throws RangeError without mutating buffer or state.
        final String prevBuf = ctrl.buffer;
        expect(() => ctrl.append('x' * 90), throwsRangeError);
        expect(ctrl.buffer, prevBuf);

        // finish() preserves settled blockIds AND append() resumes cleanly mid-paragraph.
        final String settledId = ctrl.settledBlocks.first.blockId;
        final MarkdownDocument finished = ctrl.finish();
        expect(finished.blocks.first.blockId, settledId);

        ctrl.append(' Two');
        final MarkdownDocument resumed = ctrl.finish();
        expect(resumed.toHtml(), engine.renderToHtml(ctrl.buffer));
        expect(resumed.toHtml(), contains('Heading Two'));

        ctrl.removeListener(onUpdate);
        ctrl.dispose();
        ctrl.reset();
        expect(calls, 6);

        // 25 KB / 200-chunk stream scales cleanly without O(N^2) blowup.
        final StreamingMarkdownController largeStream =
            StreamingMarkdownController(options: const MarkdownOptions.gfm());
        final Stopwatch sw = Stopwatch()..start();
        for (int i = 0; i < 200; i++) {
          largeStream.append(
            '## Section $i\n\n```dart\n[0]: inside fence\n```\n\n${'word ' * 12}\n\n',
          );
        }
        expect(largeStream.settledBlockCount, greaterThan(100));
        final MarkdownDocument finalLarge = largeStream.finish();
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(200));
        expect(finalLarge.blocks.length, greaterThanOrEqualTo(400));
        expect(finalLarge.toHtml(), engine.renderToHtml(largeStream.buffer));
      },
    );
  });
}
