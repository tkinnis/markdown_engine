import 'dart:convert';
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
    defaultOptions: MarkdownOptions.gfm(),
  );
  const IncrementalMarkdownParser incremental = IncrementalMarkdownParser(
    engine: engine,
  );
  final String root = _corpusRoot();

  group('IncrementalMarkdownParser', () {
    test(
      'reuses unchanged blocks and preserves blockIds on single-paragraph edit',
      () {
        final List<String> paragraphs = List<String>.generate(
          12,
          (int i) => 'Paragraph $i with *markdown* content.',
        );
        final String v1 = paragraphs.join('\n\n');
        final IncrementalParseResult res1 = incremental.parseIncremental(v1);
        expect(res1.document.blocks.length, 12);
        expect(res1.reusedBlockCount, 0);
        expect(res1.reparsedBlockCount, 12);

        paragraphs[5] = 'Paragraph 5 EDITED with **bold** text.';
        final String v2 = paragraphs.join('\n\n');
        final IncrementalParseResult res2 = incremental.parseIncremental(
          v2,
          previousResult: res1,
        );

        expect(res2.document.blocks.length, 12);
        expect(res2.reusedBlockCount, 11);
        expect(res2.reparsedBlockCount, 1);
        expect(
          res2.document.blocks[0].blockId,
          res1.document.blocks[0].blockId,
        );
        expect(
          res2.document.blocks[11].blockId,
          res1.document.blocks[11].blockId,
        );
        expect(res2.document.toHtml(), engine.renderToHtml(v2));
      },
    );

    test('executes incremental_edits.json corpus sequences accurately', () {
      final Map<String, Object?> payload =
          jsonDecode(
                File(
                  '$root/streaming/incremental_edits.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final List<Object?> sequences = payload['sequences'] as List<Object?>;

      for (final Object? rawSeq in sequences) {
        final Map<String, Object?> seq = rawSeq as Map<String, Object?>;
        String text = seq['initialSource'] as String;
        IncrementalParseResult result = incremental.parseIncremental(text);

        final List<Object?> edits = seq['edits'] as List<Object?>;
        for (final Object? rawEdit in edits) {
          final Map<String, Object?> edit = rawEdit as Map<String, Object?>;
          final int start = edit['startOffset'] as int;
          final int del = edit['deleteLength'] as int;
          final String ins = edit['insertText'] as String;
          text =
              '${text.substring(0, start)}$ins${text.substring(start + del)}';
          result = incremental.parseIncremental(
            text,
            previousResult: result,
            editStartOffset: start,
            editOldEndOffset: start + del,
            editNewEndOffset: start + ins.length,
          );
          expect(
            result.document.toHtml(),
            engine.renderToHtml(text),
            reason: 'Incremental mismatch during ${seq['id']}',
          );
        }
        expect(result.document.blocks.length, seq['expectedFinalBlocks']);
      }
    });

    test(
      'falls back safely when link reference definitions or frontmatter change',
      () {
        const String v1 =
            '# Title\n\nSee [home].\n\n[home]: https://old.example\n';
        const String v2 =
            '# Title\n\nSee [home].\n\n[home]: https://new.example\n';
        final IncrementalParseResult r1 = incremental.parseIncremental(v1);
        final IncrementalParseResult r2 = incremental.parseIncremental(
          v2,
          previousResult: r1,
        );
        expect(r2.document.toHtml(), engine.renderToHtml(v2));
        expect(r2.document.toHtml(), contains('https://new.example'));

        const IncrementalMarkdownParser extInc = IncrementalMarkdownParser(
          engine: MarkdownEngine(defaultOptions: MarkdownOptions.extended()),
        );
        const String fm1 = '---\ntitle: One\n---\n\nBody\n';
        const String fm2 = '---\ntitle: Two\n---\n\nBody\n';
        final IncrementalParseResult f1 = extInc.parseIncremental(fm1);
        final IncrementalParseResult f2 = extInc.parseIncremental(
          fm2,
          previousResult: f1,
        );
        expect(f2.document.frontmatter?['title'], 'Two');
      },
    );
  });

  group('StreamingMarkdownController', () {
    test(
      'processes llm_response_chunks.json with monotonic settled blocks and exact finish parity',
      () {
        final Map<String, Object?> payload =
            jsonDecode(
                  File(
                    '$root/streaming/llm_response_chunks.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        final List<Object?> scenarios = payload['scenarios'] as List<Object?>;

        for (final Object? rawScenario in scenarios) {
          final Map<String, Object?> scenario =
              rawScenario as Map<String, Object?>;
          final StreamingMarkdownController controller =
              StreamingMarkdownController(options: const MarkdownOptions.gfm());

          int prevSettled = 0;
          final List<String> chunks = (scenario['chunks'] as List<Object?>)
              .cast<String>();
          for (final String chunk in chunks) {
            controller.append(chunk);
            expect(
              controller.settledBlockCount,
              greaterThanOrEqualTo(prevSettled),
            );
            prevSettled = controller.settledBlockCount;
          }

          if (scenario['id'] == 'markdown_guide_stream') {
            expect(controller.settledBlockCount, greaterThanOrEqualTo(3));
          }

          final MarkdownDocument streamedFinal = controller.finish();
          final MarkdownDocument fullFinal = engine.parse(controller.buffer);
          expect(controller.isFinished, isTrue);
          expect(streamedFinal.toHtml(), fullFinal.toHtml());
          expect(streamedFinal.blocks.length, fullFinal.blocks.length);
          expect(streamedFinal.toPlainText(), fullFinal.toPlainText());

          for (final String expectedSub
              in (scenario['expectedFinalContains'] as List<Object?>)
                  .cast<String>()) {
            expect(streamedFinal.toHtml(), contains(expectedSub));
          }
        }
      },
    );

    test('supports replaceText and reset cleanly', () {
      final StreamingMarkdownController controller =
          StreamingMarkdownController(options: const MarkdownOptions.gfm());
      controller
        ..append('# Head\n\nPara 1\n\n')
        ..append('Para 2');
      expect(controller.settledBlockCount, 2);

      final String prefixPreserved = '# Head\n\nPara 1\n\nPara 2 edited';
      controller.replaceText(prefixPreserved);
      expect(controller.settledBlockCount, 2);
      expect(controller.html, contains('Para 2 edited'));

      controller.reset();
      expect(controller.buffer, isEmpty);
      expect(controller.settledBlockCount, 0);
      expect(controller.currentDocument.isEmpty, isTrue);
      expect(controller.isFinished, isFalse);
    });

    test(
      'propagates multi-item list and lazy blockquote spans for reuse and settling',
      () {
        const String multiListDoc = '''# Intro

- First item
- Second item
- Third item

> Quote line 1
lazy continuation line

Middle paragraph.

- Fourth item
- Fifth item

Tail paragraph.
''';
        final MarkdownDocument parsed = engine.parse(multiListDoc);
        final ListNode firstList = parsed.blocks[1] as ListNode;
        expect(firstList.span.startLine, 3);
        expect(firstList.span.endLine, 5);
        expect(
          multiListDoc.substring(
            firstList.span.startOffset,
            firstList.span.endOffset,
          ),
          '- First item\n- Second item\n- Third item\n',
        );

        final BlockQuoteNode quote = parsed.blocks[2] as BlockQuoteNode;
        expect(quote.span.startLine, 7);
        expect(quote.span.endLine, 8);
        expect(
          multiListDoc.substring(quote.span.startOffset, quote.span.endOffset),
          '> Quote line 1\nlazy continuation line\n',
        );

        // Incremental mid-edit past multi-item list and lazy blockquote reuses 5 of 6 blocks.
        final String editedDoc = multiListDoc.replaceFirst(
          'Middle paragraph.',
          'Middle paragraph EDITED.',
        );
        final IncrementalParseResult incRes = incremental.parseIncremental(
          editedDoc,
          previousDocument: parsed,
        );
        expect(incRes.document.blocks.length, 6);
        expect(incRes.reusedBlockCount, 5);
        expect(incRes.reparsedBlockCount, 1);
        expect(incRes.document.toHtml(), engine.renderToHtml(editedDoc));
        final Set<String> incIds = incRes.document.blocks
            .map((MarkdownBlockNode b) => b.blockId)
            .toSet();
        expect(incIds.length, incRes.document.blocks.length);

        // Streaming settles past multi-item lists and lazy blockquotes without stalling.
        final StreamingMarkdownController stream = StreamingMarkdownController(
          options: const MarkdownOptions.gfm(),
        );
        final List<String> lines = multiListDoc.split('\n');
        for (int i = 0; i < lines.length; i++) {
          final String chunk = i == lines.length - 1
              ? lines[i]
              : '${lines[i]}\n';
          stream.append(chunk);
        }
        expect(stream.settledBlockCount, 5);
        expect(stream.settledPrefixBlockCount, 5);
        final Set<String> streamIds = stream.currentDocument.blocks
            .map((MarkdownBlockNode b) => b.blockId)
            .toSet();
        expect(streamIds.length, stream.currentDocument.blocks.length);
        expect(stream.finish().toHtml(), parsed.toHtml());
      },
    );

    test(
      'settledPrefixBlockCount aligns with currentDocument.blocks across frontmatter, definitions, and finish',
      () {
        // 1. Leading frontmatter + normal blocks preserve exact identical() prefix.
        final StreamingMarkdownController fmStream =
            StreamingMarkdownController(
              options: const MarkdownOptions(frontmatter: true),
            );
        fmStream.append('---\ntitle: Stream\n---\n\n');
        expect(fmStream.settledPrefixBlockCount, 0);
        expect(fmStream.currentDocument.blocks.single, isA<FrontmatterNode>());

        fmStream.append('First paragraph\n\nSecond paragraph');
        expect(fmStream.settledPrefixBlockCount, 2);
        expect(fmStream.settledBlockCount, 2);
        final List<MarkdownBlockNode> settledSnap = fmStream.settledBlocks;
        final List<MarkdownBlockNode> docSnap1 =
            fmStream.currentDocument.blocks;
        for (int i = 0; i < fmStream.settledPrefixBlockCount; i++) {
          expect(identical(docSnap1[i], settledSnap[i]), isTrue);
        }
        expect(
          docSnap1.sublist(fmStream.settledPrefixBlockCount),
          fmStream.activeBlocks,
        );

        fmStream.append(' updated');
        final List<MarkdownBlockNode> docSnap2 =
            fmStream.currentDocument.blocks;
        for (int i = 0; i < fmStream.settledPrefixBlockCount; i++) {
          expect(identical(docSnap2[i], settledSnap[i]), isTrue);
        }

        // 2. Definitions / footnotes drop settledPrefixBlockCount to 0 during active streaming.
        final StreamingMarkdownController fnStream =
            StreamingMarkdownController(options: const MarkdownOptions.gfm());
        fnStream.append('Intro paragraph[^1]\n\nMiddle paragraph\n\nTail');
        expect(fnStream.settledPrefixBlockCount, 2);

        fnStream.append('\n\n[^1]: Footnote text');
        expect(fnStream.settledPrefixBlockCount, 0);
        expect(fnStream.settledBlockCount, 0);
        expect(
          fnStream.activeBlocks.length,
          fnStream.currentDocument.blocks.length,
        );
        expect(
          fnStream.currentDocument.blocks.last,
          isA<FootnoteSectionNode>(),
        );

        final MarkdownDocument finishedFn = fnStream.finish();
        expect(fnStream.isFinished, isTrue);
        expect(fnStream.settledPrefixBlockCount, finishedFn.blocks.length);
        expect(fnStream.activeBlocks, isEmpty);

        // Resuming append after finish resets prefix count cleanly when definitions exist.
        fnStream.append(' continued');
        expect(fnStream.isFinished, isFalse);
        expect(fnStream.settledPrefixBlockCount, 0);
        expect(
          fnStream.finish().toHtml(),
          engine.renderToHtml(fnStream.buffer),
        );
      },
    );

    test(
      'incremental parser maintains parity without editStartOffset, on CRLF edits, and across consecutive edits',
      () {
        final List<String> sections = List<String>.generate(
          30,
          (int i) =>
              '## Heading $i\n\nParagraph $i with *alpha* text.\n\n- Item ${i}a\n- Item ${i}b',
        );
        final String docText = '${sections.join('\n\n')}\n';
        IncrementalParseResult res = incremental.parseIncremental(docText);

        // Edit without editStartOffset.
        final String v2 = docText.replaceFirst(
          'Paragraph 15 with *alpha* text.',
          'Paragraph 15 EDITED with **beta** text.',
        );
        res = incremental.parseIncremental(v2, previousResult: res);
        expect(res.reusedBlockCount, greaterThan(80));
        expect(res.document.toHtml(), engine.renderToHtml(v2));

        // Edit with only editStartOffset (and CRLF inside edited slice).
        final int offset = v2.indexOf('Paragraph 15 EDITED');
        final String v3 = v2.replaceFirst(
          'Paragraph 15 EDITED with **beta** text.',
          'Paragraph 15 CRLF\r\nsecond line.',
        );
        res = incremental.parseIncremental(
          v3,
          previousResult: res,
          editStartOffset: offset,
        );
        expect(res.document.toHtml(), engine.renderToHtml(v3));

        // Consecutive edit with full coordinates preserves unique blockIds.
        final int off3 = v3.indexOf('Paragraph 20 with');
        const String oldSeg = 'Paragraph 20 with *alpha* text.';
        const String newSeg = 'Paragraph 20 THIRD EDIT.';
        final String v4 = v3.replaceFirst(oldSeg, newSeg);
        res = incremental.parseIncremental(
          v4,
          previousResult: res,
          editStartOffset: off3,
          editOldEndOffset: off3 + oldSeg.length,
          editNewEndOffset: off3 + newSeg.length,
        );
        expect(res.document.toHtml(), engine.renderToHtml(v4));
        final Set<String> ids = res.document.blocks
            .map((MarkdownBlockNode b) => b.blockId)
            .toSet();
        expect(ids.length, res.document.blocks.length);
      },
    );

    test(
      'streaming preserves lazy snapshots and parity across mid-paragraph fast-path edge cases',
      () {
        const MarkdownEngine defaultEngine = MarkdownEngine();
        final StreamingMarkdownController ctrl = StreamingMarkdownController(
          engine: defaultEngine,
        );

        final MarkdownDocument snap1 = ctrl.append('# Title\n\nFirst ');
        final MarkdownDocument snap2 = ctrl.append(
          'paragraph with a = b and Note: 12:30 and ![img](https://example.com/a.png)',
        );
        final MarkdownDocument snap3 = ctrl.append('   ');
        final MarkdownDocument snap4 = ctrl.append(
          'continued **bold** text.\n\nIntro line\nNext line ',
        );
        final MarkdownDocument snap5 = ctrl.append('with more words');
        ctrl.append('\n\nCol1 | Col2\n| --- | --- |\n| a | b |\n\n[ref]: /x');

        // Verify historical snapshots remain completely immutable after later appends & reset.
        expect(snap1.source, '# Title\n\nFirst ');
        expect(
          snap1.outline.map((MarkdownOutlineItem o) => o.slug).toList(),
          <String>['title'],
        );
        expect((snap1.blocks.first as HeadingNode).slug, 'title');
        expect(snap2.remoteImageAddresses, <String>[
          'https://example.com/a.png',
        ]);
        expect(snap3.toHtml(), defaultEngine.renderToHtml(snap3.source));
        expect(snap4.toHtml(), defaultEngine.renderToHtml(snap4.source));
        expect(snap5.toHtml(), defaultEngine.renderToHtml(snap5.source));

        final MarkdownDocument beforeReset = ctrl.finish();
        final String beforeResetSource = beforeReset.source;
        expect(
          beforeReset.toHtml(),
          defaultEngine.renderToHtml(beforeResetSource),
        );

        ctrl.reset();
        expect(snap2.source, isNotEmpty);
        expect(snap2.blocks.length, 2);

        // Edge-case transitions from mid-paragraph fast path into blocks/defs.
        final List<List<String>> cases = <List<String>>[
          <String>['Title ', 'here', '\n===', ''],
          <String>['Header ', 'A | B', '\n| ---', ' | --- |\n| 1 | 2 |'],
          <String>['[lbl', ']', ': https://example.com', '\n\nUse [lbl].'],
          <String>['*[abbr', ']: Long Form', '\n\nUse abbr here.'],
          <String>['Paragraph ', 'with *em* and `code`', ' tail   ', 'end'],
        ];
        for (final List<String> chunks in cases) {
          final StreamingMarkdownController c = StreamingMarkdownController(
            engine: defaultEngine,
          );
          for (final String chunk in chunks) {
            final MarkdownDocument d = c.append(chunk);
            expect(d.toHtml(), defaultEngine.renderToHtml(c.buffer));
          }
          expect(c.finish().toHtml(), defaultEngine.renderToHtml(c.buffer));
        }
      },
    );

    test(
      'open fenced code streaming fast-path matches full parse across fence edge cases',
      () {
        const MarkdownEngine defaultEngine = MarkdownEngine();
        final List<List<String>> fenceCases = <List<String>>[
          <String>['  ```da', 'rt\n', '  print(1);\n', '  print(2);\n  ```'],
          <String>['```py', 'thon\n', 'x = 1', '\ny = 2\n', '```'],
          <String>['```dart\nline1\n', '\nline3', '\n```\n\nAfter'],
          <String>['```dart\na = 1;\n', 'b = 2;\n```\n\nNext'],
          <String>['~~~txt\nhello', ' world\nline2', '\n~~~'],
          <String>['```sh\r\necho hi\r', '\necho bye\r\n```'],
        ];
        for (final List<String> chunks in fenceCases) {
          final StreamingMarkdownController ctrl = StreamingMarkdownController(
            engine: defaultEngine,
          );
          for (final String chunk in chunks) {
            final MarkdownDocument snap = ctrl.append(chunk);
            final MarkdownDocument ref = defaultEngine.parse(ctrl.buffer);
            expect(snap.toHtml(), ref.toHtml());
            expect(snap.blocks.length, ref.blocks.length);
            for (int i = 0; i < ref.blocks.length; i++) {
              expect(snap.blocks[i].span, ref.blocks[i].span);
              if (snap.blocks[i] is CodeBlockNode &&
                  ref.blocks[i] is CodeBlockNode) {
                final CodeBlockNode sCode = snap.blocks[i] as CodeBlockNode;
                final CodeBlockNode rCode = ref.blocks[i] as CodeBlockNode;
                expect(sCode.literal, rCode.literal);
                expect(sCode.info, rCode.info);
                expect(sCode.language, rCode.language);
                expect(sCode.isFenced, rCode.isFenced);
                expect(sCode.codeUnitOffset, rCode.codeUnitOffset);
              }
            }
          }
          final MarkdownDocument done = ctrl.finish();
          final MarkdownDocument ref = defaultEngine.parse(ctrl.buffer);
          expect(done.toHtml(), ref.toHtml());
          expect(done.blocks.length, ref.blocks.length);
          for (int i = 0; i < ref.blocks.length; i++) {
            expect(done.blocks[i].span, ref.blocks[i].span);
          }
        }
      },
    );

    test(
      'single-backtick inline fast-path matches general inline scanner on edge cases',
      () {
        const MarkdownEngine defaultEngine = MarkdownEngine();
        final Map<String, String> gfmCases = <String, String>{
          'Before `a\nb` after': '<p>Before <code>a b</code> after</p>\n',
          'Keep spaces `   ` intact':
              '<p>Keep spaces <code>   </code> intact</p>\n',
          'Strip outer spaces ` foo ` cleanly':
              '<p>Strip outer spaces <code>foo</code> cleanly</p>\n',
          'Keep one space ` a  ` trimmed symmetrically':
              '<p>Keep one space <code>a </code> trimmed symmetrically</p>\n',
          'Multiple `a` and `b` spans':
              '<p>Multiple <code>a</code> and <code>b</code> spans</p>\n',
          "It's `a` quoted": "<p>It's <code>a</code> quoted</p>\n",
          'Unclosed `code span': '<p>Unclosed `code span</p>\n',
          'Mismatched `code`` span': '<p>Mismatched `code`` span</p>\n',
          'Plain `only`': '<p>Plain <code>only</code></p>\n',
          '`only`': '<p><code>only</code></p>\n',
        };
        for (final MapEntry<String, String> entry in gfmCases.entries) {
          final String md = entry.key;
          final String expectedGfm = entry.value;
          final MarkdownDocument doc = defaultEngine.parse(md);
          final MarkdownDocument gfmDoc = engine.parse(md);
          final MarkdownDocument cmDoc = engine.parse(
            md,
            options: const MarkdownOptions.commonMark(),
          );
          expect(gfmDoc.toHtml(), expectedGfm);
          expect(cmDoc.toHtml(), expectedGfm);
          if (md == "It's `a` quoted") {
            expect(doc.toHtml(), '<p>It\u2019s <code>a</code> quoted</p>\n');
          } else {
            expect(doc.toHtml(), expectedGfm);
          }
        }
        // Verify exact budget truncation parity on single-backtick fast path.
        const MarkdownOptions tightBudgetOpts = MarkdownOptions(
          budgets: MarkdownBudgets(maxTokens: 1),
        );
        final MarkdownDocument limited = defaultEngine.parse(
          'prefix `code` suffix',
          options: tightBudgetOpts,
        );
        expect(limited.toHtml(), '<p>prefix `code` suffix</p>\n');
      },
    );

    test(
      'streaming fast paths (table, list/task-list, blockquote/alert, trailing single newline) match full parse across chunk sizes',
      () {
        const MarkdownEngine extEngine = MarkdownEngine(
          defaultOptions: MarkdownOptions.extended(),
        );

        void verifyChunks({
          required List<String> chunks,
          required MarkdownOptions options,
          required String label,
          bool checkEveryChunk = true,
        }) {
          final MarkdownEngine refEngine = MarkdownEngine(
            defaultOptions: options,
          );
          final StreamingMarkdownController ctrl = StreamingMarkdownController(
            engine: refEngine,
          );
          final StringBuffer acc = StringBuffer();
          int prevSettledPrefix = 0;

          for (int i = 0; i < chunks.length; i++) {
            final String chunk = chunks[i];
            acc.write(chunk);
            final MarkdownDocument snap = ctrl.append(chunk);
            expect(
              ctrl.settledPrefixBlockCount,
              greaterThanOrEqualTo(prevSettledPrefix),
              reason: '$label chunk $i settledPrefixBlockCount regressed',
            );
            prevSettledPrefix = ctrl.settledPrefixBlockCount;
            final List<MarkdownBlockNode> settledSnap = ctrl.settledBlocks;
            for (int b = 0; b < ctrl.settledPrefixBlockCount; b++) {
              expect(
                identical(snap.blocks[b], settledSnap[b]),
                isTrue,
                reason: '$label chunk $i settled prefix block $b not identical',
              );
            }
            final bool isSafeBoundary =
                chunk.endsWith('\n') || i == chunks.length - 1;
            if (checkEveryChunk || isSafeBoundary) {
              final MarkdownDocument refDoc = refEngine.parse(acc.toString());
              expect(
                snap.toHtml(),
                refDoc.toHtml(),
                reason:
                    '$label HTML mismatch at chunk $i (${jsonEncode(chunk)})',
              );
            }
          }

          final MarkdownDocument finished = ctrl.finish();
          final MarkdownDocument fullRef = refEngine.parse(acc.toString());
          expect(
            finished.toHtml(),
            fullRef.toHtml(),
            reason: '$label finish()',
          );
          expect(
            finished.blocks.length,
            fullRef.blocks.length,
            reason: '$label finish() block count',
          );
          expect(
            finished.toPlainText(),
            fullRef.toPlainText(),
            reason: '$label finish() plainText',
          );
        }

        List<String> sliceChunks(String source, int size) {
          final List<String> out = <String>[];
          for (int i = 0; i < source.length; i += size) {
            final int end = i + size > source.length ? source.length : i + size;
            out.add(source.substring(i, end));
          }
          return out;
        }

        // 1. TableNode mid-row, escaped pipes \|, inline code with |, leading spaces,
        // \n| row append, trailing row finalization, and trailing paragraph transition.
        const String tableDoc = '''# Table Stream

| Feature | Syntax | Notes |
| :--- | :---: | ---: |
| Escaped | a \\| b | ok |
   | Code | `x | y` | indented |
| Final | `pipe | inside` and \\| tail | done |

After table paragraph.
''';
        verifyChunks(
          chunks: sliceChunks(tableDoc, 1),
          options: const MarkdownOptions.gfm(),
          label: 'table-1char',
        );
        verifyChunks(
          chunks: <String>[
            '# Table Stream\n\n',
            '| Feature | Syntax | Notes |\n| :--- | :---: | ---: |\n| Esc',
            'aped | a \\| b | ok',
            ' |\n',
            '   | Code | `x | y`',
            ' | indented |\n| Final | `pipe | inside`',
            ' and \\| tail | done |',
            '\n',
            '\nAfter table paragraph.\n',
          ],
          options: const MarkdownOptions.gfm(),
          label: 'table-row-boundaries',
        );
        verifyChunks(
          chunks: <String>[
            '| A | B |\n| --- | --- |\n| r1',
            '\n| r2 | v2 |\n    | not-table-4-spaces',
            '\n| r3 | v3 |',
          ],
          options: const MarkdownOptions.gfm(),
          label: 'table-newline-pipe-and-4space-fallback',
        );

        // Enforce maxTableRows budget on fast table append path.
        const MarkdownOptions tableBudgetOpts = MarkdownOptions.gfm(
          budgets: MarkdownBudgets(maxTableRows: 2),
        );
        final StreamingMarkdownController budgetCtrl =
            StreamingMarkdownController(options: tableBudgetOpts);
        budgetCtrl.append('| H1 | H2 |\n| --- | --- |\n| 1 | 2 |\n');
        budgetCtrl.append('| 3 | 4 |\n');
        budgetCtrl.append('| 5 | 6 |\n');
        final MarkdownDocument budgetDoc = budgetCtrl.finish();
        expect(
          budgetDoc.toHtml(),
          const MarkdownEngine(
            defaultOptions: tableBudgetOpts,
          ).renderToHtml(budgetCtrl.buffer),
        );
        final TableNode cappedTable = budgetDoc.blocks.first as TableNode;
        expect(cappedTable.rows.length, lessThanOrEqualTo(2));

        // Verify table/list fast paths reuse invariant prefix rows/items and
        // handle reference definitions + entities mid-stream.
        final StreamingMarkdownController reuseCtrl =
            StreamingMarkdownController(options: const MarkdownOptions.gfm());
        final TableNode t1 =
            reuseCtrl
                    .append('| H1 | H2 |\n| --- | --- |\n| r1 | v1 |\n| r2 ')
                    .blocks
                    .single
                as TableNode;
        final TableNode t2 =
            reuseCtrl.append('| v2 &amp; more').blocks.single as TableNode;
        expect(identical(t2.headers, t1.headers), isTrue);
        expect(identical(t2.rows.first, t1.rows.first), isTrue);
        reuseCtrl.append('\n\nSee [r1]\n\n[r1]: https://example.com');
        expect(
          reuseCtrl.finish().toHtml(),
          const MarkdownEngine(
            defaultOptions: MarkdownOptions.gfm(),
          ).renderToHtml(reuseCtrl.buffer),
        );

        final StreamingMarkdownController listReuseCtrl =
            StreamingMarkdownController(options: const MarkdownOptions.gfm());
        final ListNode l1 =
            listReuseCtrl.append('- First\n- Second ').blocks.single
                as ListNode;
        final ListNode l2 =
            listReuseCtrl.append('item tail').blocks.single as ListNode;
        expect(identical(l2.items.first, l1.items.first), isTrue);
        expect(
          listReuseCtrl.finish().toHtml(),
          const MarkdownEngine(
            defaultOptions: MarkdownOptions.gfm(),
          ).renderToHtml(listReuseCtrl.buffer),
        );

        // 2. ListNode last-item single-line paragraph fast path + GFM task lists.
        const String listDoc = '''- First item
- Second item streaming mid-line words
- [ ] Unchecked task item
- [x] Checked task item with `code` and **bold**

1. Ordered first
2. Ordered second

  Continued paragraph inside ordered item
''';
        verifyChunks(
          chunks: sliceChunks(listDoc, 1),
          options: const MarkdownOptions.gfm(),
          label: 'list-1char',
        );
        verifyChunks(
          chunks: <String>[
            '- First item\n- Second ',
            'item streaming ',
            'mid-line words\n',
            '- [',
            ' ',
            '] Unchecked ',
            'task item\n',
            '- [x',
            '] Checked ',
            'task item\n',
            '- Plain\n---',
          ],
          options: const MarkdownOptions.gfm(),
          label: 'list-task-transitions',
        );

        // 3. BlockQuoteNode single-line mid-paragraph fast path + [!NOTE] alert transition.
        const String quoteAndAlertDoc =
            '''> Single line quote streaming words slowly

> [!NOTE]
> Alert body after bracket starter transition

> [!WARNING]
> Warning alert body
''';
        verifyChunks(
          chunks: sliceChunks(quoteAndAlertDoc, 1),
          options: extEngine.defaultOptions,
          label: 'quote-alert-1char',
        );
        verifyChunks(
          chunks: <String>[
            '> Single line ',
            'quote ',
            'streaming words',
            '\nlazy continuation line\n\n',
            '> ',
            '[',
            '!NOTE]',
            '\n> Alert ',
            'body',
          ],
          options: extEngine.defaultOptions,
          label: 'quote-alert-slices',
        );

        // 4. Trailing single \n on ParagraphNode fast path + setext/table/continuation transitions.
        verifyChunks(
          chunks: <String>[
            'First line of paragraph',
            '\n',
            'second line continues',
            '\n',
            '\nSettled next paragraph',
            '\n',
            '===',
            '\n\nHeader A | Header B',
            '\n',
            '| --- | --- |',
          ],
          options: const MarkdownOptions.gfm(),
          label: 'paragraph-trailing-single-nl',
        );
        final StreamingMarkdownController nlCtrl = StreamingMarkdownController(
          options: const MarkdownOptions.gfm(),
        );
        nlCtrl.append('Line one');
        final MarkdownDocument afterNl = nlCtrl.append('\n');
        final MarkdownDocument refAfterNl = const MarkdownEngine(
          defaultOptions: MarkdownOptions.gfm(),
        ).parse('Line one\n');
        expect(afterNl.blocks.single.span, refAfterNl.blocks.single.span);
        expect(afterNl.toHtml(), refAfterNl.toHtml());

        // 5. Full 50-chunk LLM response fixture across 50 slices, 3-char slices, and 1-char slices.
        const String llm50Full = '''# Streaming Response Walkthrough

When rendering token-by-token responses from an **HTTP SSE stream**, re-parsing the entire transcript from scratch on every token scales quadratically as the answer grows.

## 1. Settled Prefix Freezing

`StreamingMarkdownController` keeps a frozen list of completed top-level blocks (`settledBlocks`) separated by blank-line boundaries. Only the active trailing block slice is re-parsed on each incoming chunk.

- Completed headings and paragraphs never re-run inline resolution.
- Stable `blockId` values let Flutter `CustomScrollView` slivers preserve selection and scroll offsets.
- Calling `finish()` reconciles the buffer for exact parity with `MarkdownEngine.parse`.

## 2. Example Streaming Loop

```dart
final StreamingMarkdownController controller = StreamingMarkdownController(
  options: const MarkdownOptions.gfm(),
);

for (final String chunk in tokenStream) {
  final MarkdownDocument snapshot = controller.append(chunk);
  renderBlocks(snapshot.blocks);
}

final MarkdownDocument finalDoc = controller.finish();
```

## 3. Observed Properties

| Phase | Scope | Allocation Profile |
| :--- | :--- | :--- |
| Settled prefix | Frozen `MarkdownBlockNode` list | Zero re-parse per chunk |
| Active tail | Unsettled trailing blocks only | Bounded by tail block size |
| Finalization | Full parity reconciliation | Single pass at stream end |

> Because settled prefix blocks stay immutable across `append()` calls, tail latency remains bounded even as long technical explanations accumulate multiple code blocks, lists, and GFM tables.

## 4. Security During Streaming

Even partial chunks enforce `MarkdownUrlPolicy`, GFM `tagfilter`, and `MarkdownBudgets` so untrusted model outputs cannot inject `javascript:` links or exceed nesting caps mid-stream.

- [x] Reject unsafe URL schemes incrementally
- [x] Escape disallowed raw HTML tags (`<script>`, `<iframe>`, `<style>`)
- [x] Bound input length and container nesting depth

## 5. Summary

Pairing `StreamingMarkdownController` with sliver-based widgets yields smooth 60/120 fps scrolling across long streaming replies without embedding a browser engine.
''';
        final List<String> fiftyChunks = <String>[];
        for (int i = 0; i < 50; i++) {
          final int start = (i * llm50Full.length) ~/ 50;
          final int end = ((i + 1) * llm50Full.length) ~/ 50;
          if (end > start) {
            fiftyChunks.add(llm50Full.substring(start, end));
          }
        }
        verifyChunks(
          chunks: fiftyChunks,
          options: const MarkdownOptions.gfm(),
          label: 'llm-50-chunks',
        );
        verifyChunks(
          chunks: sliceChunks(llm50Full, 3),
          options: const MarkdownOptions.gfm(),
          label: 'llm-3char',
        );
        verifyChunks(
          chunks: sliceChunks(llm50Full, 1),
          options: const MarkdownOptions.gfm(),
          label: 'llm-1char',
          checkEveryChunk: false,
        );
      },
    );

    test(
      'fast paths engage on trailing table, list, and blockquote opened in the same chunk that settles preceding blocks',
      () {
        const MarkdownEngine gfmEngine = MarkdownEngine(
          defaultOptions: MarkdownOptions.gfm(),
        );
        const MarkdownEngine extEngine = MarkdownEngine(
          defaultOptions: MarkdownOptions.extended(),
        );

        void expectSnapshotParity(
          StreamingMarkdownController ctrl,
          MarkdownEngine refEngine,
          String label,
        ) {
          final MarkdownDocument snap = ctrl.currentDocument;
          final MarkdownDocument ref = refEngine.parse(ctrl.buffer);
          expect(snap.toHtml(), ref.toHtml(), reason: '$label HTML parity');
          expect(
            snap.toPlainText(),
            ref.toPlainText(),
            reason: '$label plainText parity',
          );
          expect(
            snap.blocks.length,
            ref.blocks.length,
            reason: '$label block count',
          );
          for (int i = 0; i < ref.blocks.length; i++) {
            expect(
              snap.blocks[i].span,
              ref.blocks[i].span,
              reason: '$label block[$i] span',
            );
          }
        }

        // 1. Heading + paragraph settle while opening a trailing TableNode in one chunk.
        final StreamingMarkdownController tableCtrl =
            StreamingMarkdownController(engine: gfmEngine);
        tableCtrl.append('# Title\n\nIntro');
        final MarkdownDocument dTableOpen = tableCtrl.append(
          ' text.\n\n| Key | Value |\n| :--- | ---: |\n| alpha | 1 |\n| beta ',
        );
        expect(tableCtrl.settledPrefixBlockCount, 2);
        expect(dTableOpen.blocks.length, 3);
        expect(dTableOpen.blocks.last, isA<TableNode>());
        final TableNode tableAfterOpen = dTableOpen.blocks.last as TableNode;
        expectSnapshotParity(tableCtrl, gfmEngine, 'table-open');

        // Next mid-row append must hit _tryFastTableAppend (reusing headers & prefix row).
        final MarkdownDocument dTableFast1 = tableCtrl.append('| 2');
        final TableNode tableFast1 = dTableFast1.blocks.last as TableNode;
        expect(identical(tableFast1.headers, tableAfterOpen.headers), isTrue);
        expect(
          identical(tableFast1.rows.first, tableAfterOpen.rows.first),
          isTrue,
        );
        expect(identical(dTableFast1.blocks[0], dTableOpen.blocks[0]), isTrue);
        expect(identical(dTableFast1.blocks[1], dTableOpen.blocks[1]), isTrue);
        expectSnapshotParity(tableCtrl, gfmEngine, 'table-fast-mid-row');

        final MarkdownDocument dTableFast2 = tableCtrl.append(' |\n| gamma');
        final TableNode tableFast2 = dTableFast2.blocks.last as TableNode;
        expect(identical(tableFast2.headers, tableFast1.headers), isTrue);
        expect(identical(tableFast2.rows.first, tableFast1.rows.first), isTrue);
        expectSnapshotParity(tableCtrl, gfmEngine, 'table-fast-next-row');

        // Also verify table opened right at delimiter newline (`| --- |\n`) engages fast path.
        final StreamingMarkdownController tableNlCtrl =
            StreamingMarkdownController(engine: gfmEngine);
        final MarkdownDocument dTableNlOpen = tableNlCtrl.append(
          '## Section\n\n| Col1 | Col2 |\n| --- | --- |\n',
        );
        expect(tableNlCtrl.settledPrefixBlockCount, 1);
        final TableNode tNlOpen = dTableNlOpen.blocks.last as TableNode;
        final MarkdownDocument dTableNlNext = tableNlCtrl.append('| x | y');
        final TableNode tNlNext = dTableNlNext.blocks.last as TableNode;
        expect(identical(tNlNext.headers, tNlOpen.headers), isTrue);
        expectSnapshotParity(tableNlCtrl, gfmEngine, 'table-nl-fast-row');
        tableNlCtrl.append(' |\n\nDone.');
        expectSnapshotParity(tableNlCtrl, gfmEngine, 'table-nl-done');
        expect(
          tableNlCtrl.finish().toHtml(),
          gfmEngine.renderToHtml(tableNlCtrl.buffer),
        );

        // 2. Settling preceding paragraph while opening a trailing ListNode (plain + task).
        final StreamingMarkdownController listCtrl =
            StreamingMarkdownController(engine: gfmEngine);
        listCtrl.append('Lead');
        final MarkdownDocument dListOpen = listCtrl.append(
          ' paragraph.\n\n- First item\n- [x] Second ',
        );
        expect(listCtrl.settledPrefixBlockCount, 1);
        expect(dListOpen.blocks.length, 2);
        expect(dListOpen.blocks.last, isA<ListNode>());
        final ListNode listAfterOpen = dListOpen.blocks.last as ListNode;
        expectSnapshotParity(listCtrl, gfmEngine, 'list-open');

        // Next mid-item append must hit _tryFastListAppend (reusing first item).
        final MarkdownDocument dListFast = listCtrl.append('task item');
        final ListNode listFast = dListFast.blocks.last as ListNode;
        expect(
          identical(listFast.items.first, listAfterOpen.items.first),
          isTrue,
        );
        expect(identical(dListFast.blocks[0], dListOpen.blocks[0]), isTrue);
        expectSnapshotParity(listCtrl, gfmEngine, 'list-fast-append');

        listCtrl.append(' with *inline*!\n\nClosing.');
        expectSnapshotParity(listCtrl, gfmEngine, 'list-after-close');
        expect(
          listCtrl.finish().toHtml(),
          gfmEngine.renderToHtml(listCtrl.buffer),
        );

        // 3. Settling preceding table/heading while opening a trailing BlockQuoteNode.
        final StreamingMarkdownController quoteCtrl =
            StreamingMarkdownController(engine: extEngine);
        quoteCtrl.append('# Quotes\n\n| A | B |\n| --- | --- |\n| 1 | 2');
        final MarkdownDocument dQuoteOpen = quoteCtrl.append(
          ' |\n\n> Quoted line',
        );
        expect(quoteCtrl.settledPrefixBlockCount, 2);
        expect(dQuoteOpen.blocks.length, 3);
        expect(dQuoteOpen.blocks.last, isA<BlockQuoteNode>());
        final BlockQuoteNode quoteAfterOpen =
            dQuoteOpen.blocks.last as BlockQuoteNode;
        expectSnapshotParity(quoteCtrl, extEngine, 'quote-open');

        final MarkdownDocument dQuoteFast1 = quoteCtrl.append(
          ' continues with ',
        );
        final BlockQuoteNode quoteFast1 =
            dQuoteFast1.blocks.last as BlockQuoteNode;
        expect(quoteFast1.blockId, quoteAfterOpen.blockId);
        expect(identical(dQuoteFast1.blocks[0], dQuoteOpen.blocks[0]), isTrue);
        expect(identical(dQuoteFast1.blocks[1], dQuoteOpen.blocks[1]), isTrue);
        expectSnapshotParity(quoteCtrl, extEngine, 'quote-fast-append-1');

        final MarkdownDocument dQuoteFast2 = quoteCtrl.append('`code`');
        expectSnapshotParity(quoteCtrl, extEngine, 'quote-fast-append-2');
        expect(
          (dQuoteFast2.blocks.last as BlockQuoteNode).blockId,
          quoteAfterOpen.blockId,
        );

        quoteCtrl.append('\nlazy line\n\n> [!NOTE]\n> Alert text');
        expectSnapshotParity(quoteCtrl, extEngine, 'quote-alert-transition');
        expect(
          quoteCtrl.finish().toHtml(),
          extEngine.renderToHtml(quoteCtrl.buffer),
        );

        // 4. Edge cases: whitespace-only blank line before list/quote & single-nl table interruption.
        final StreamingMarkdownController edgeCtrl =
            StreamingMarkdownController(engine: gfmEngine);
        edgeCtrl.append('# Heading\n\n   \n- Item ');
        expectSnapshotParity(edgeCtrl, gfmEngine, 'ws-blank-line-list');
        edgeCtrl.append('tail\n\nPara line\n| H1 | H2 |\n| --- | --- |\n| r1');
        expectSnapshotParity(edgeCtrl, gfmEngine, 'single-nl-table-interrupt');
        edgeCtrl.append(' | v1 |\n');
        expectSnapshotParity(edgeCtrl, gfmEngine, 'single-nl-table-row-end');
        expect(
          edgeCtrl.finish().toHtml(),
          gfmEngine.renderToHtml(edgeCtrl.buffer),
        );
      },
    );
  });
}
