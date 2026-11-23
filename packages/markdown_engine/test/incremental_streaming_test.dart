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
        final Set<String> streamIds = stream.currentDocument.blocks
            .map((MarkdownBlockNode b) => b.blockId)
            .toSet();
        expect(streamIds.length, stream.currentDocument.blocks.length);
        expect(stream.finish().toHtml(), parsed.toHtml());
      },
    );
  });
}
