import 'dart:io';

import 'package:markdown_engine/markdown_engine.dart';

/// Demonstrates parsing, frontmatter/outline extraction, extensions,
/// incremental block reuse, streaming updates, and HTML export using
/// [MarkdownEngine].
void main() {
  const MarkdownEngine engine = MarkdownEngine(
    defaultOptions: MarkdownOptions.extended(),
  );

  const String sample = '''---
title: markdown_engine Walkthrough
tags:
  - commonmark
  - gfm
---

# Overview

Pure-Dart CommonMark 0.31.2 and GFM 0.29.0.gfm.13 engine with H~2~O, x^2^, ==highlight==, and ~~strike~~.

> [!NOTE]
> Supports alerts, footnotes[^1], definition lists, and math \$E = mc^2\$.

[^1]: Verified against all vendored CommonMark and GFM specs.
''';

  final MarkdownDocument document = engine.parse(sample);
  stdout.writeln(
    'Parsed ${document.blocks.length} blocks '
    '(frontmatter title: ${document.frontmatter?['title']}, '
    'outline: ${document.outline.length}, '
    'footnotes: ${document.footnotes.length}).',
  );
  stdout.writeln(document.toHtml());

  // Incremental diff reuse across a multi-paragraph document.
  const IncrementalMarkdownParser incremental = IncrementalMarkdownParser(
    engine: engine,
  );
  const String docV1 = '# Section\n\nFirst paragraph.\n\nSecond paragraph.\n';
  const String docV2 = '# Section\n\nEdited paragraph.\n\nSecond paragraph.\n';
  final IncrementalParseResult first = incremental.parseIncremental(docV1);
  final IncrementalParseResult second = incremental.parseIncremental(
    docV2,
    previousResult: first,
    editStartOffset: 11,
  );
  stdout.writeln(
    'Incremental update: reused=${second.reusedBlockCount}, '
    'reparsed=${second.reparsedBlockCount}.',
  );

  // Streaming chunked accumulation.
  final StreamingMarkdownController stream = StreamingMarkdownController(
    options: const MarkdownOptions.gfm(),
  );
  stream
    ..append('# Streamed ')
    ..append('Heading\n\n')
    ..append('Trailing *inline* chunk.');
  final MarkdownDocument finalStreamDoc = stream.finish();
  stdout.writeln('Streamed HTML:\n${finalStreamDoc.toHtml()}');
}
