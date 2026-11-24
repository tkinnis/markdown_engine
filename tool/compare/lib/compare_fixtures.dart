import 'dart:convert';
import 'dart:io';

/// Parsed CommonMark or GFM specification fixture case.
final class SpecFixtureCase {
  /// Creates a specification fixture case.
  const SpecFixtureCase({
    required this.suite,
    required this.exampleNumber,
    required this.section,
    required this.markdown,
    required this.expectedHtml,
    this.tag = '',
    this.ignored = false,
    this.disabled = false,
  });

  /// Suite identifier (`commonmark`, `gfm_spec`, or `gfm_extensions`).
  final String suite;

  /// 1-based example number within the suite.
  final int exampleNumber;

  /// Specification section title.
  final String section;

  /// Raw Markdown input fixture.
  final String markdown;

  /// Expected HTML output from the specification.
  final String expectedHtml;

  /// Optional cmark-gfm extension tag (`table`, `autolink`, etc.).
  final String tag;

  /// Whether expected output is `<IGNORE>` (crash-regression fixture).
  final bool ignored;

  /// Whether the upstream example is marked `disabled`.
  final bool disabled;
}

/// Large 5,000-line fixture paired with a single mid-document paragraph edit.
final class LargeEditFixture {
  /// Creates a [LargeEditFixture].
  const LargeEditFixture({
    required this.baseSource,
    required this.editedSource,
    required this.editStartOffset,
    required this.editOldEndOffset,
    required this.editNewEndOffset,
    required this.editedLineNumber,
    required this.lineCount,
  });

  /// Original ~5,000-line document text.
  final String baseSource;

  /// Modified document text with a single mid-document paragraph updated.
  final String editedSource;

  /// UTF-16 start offset of the edited paragraph.
  final int editStartOffset;

  /// UTF-16 end offset of the edited paragraph in [baseSource].
  final int editOldEndOffset;

  /// UTF-16 end offset of the edited paragraph in [editedSource].
  final int editNewEndOffset;

  /// 1-based line number where the edit starts.
  final int editedLineNumber;

  /// Total line count of [baseSource].
  final int lineCount;
}

/// Chunked streaming Markdown fixture.
final class StreamingPayloadFixture {
  /// Creates a [StreamingPayloadFixture].
  const StreamingPayloadFixture({
    required this.fullSource,
    required this.chunks,
  });

  /// Complete concatenated Markdown source.
  final String fullSource;

  /// Ordered token/chunk slices summing to [fullSource].
  final List<String> chunks;
}

/// Statistical summary of repeated latency measurements.
final class LatencyStats {
  /// Creates a [LatencyStats] measurement summary.
  const LatencyStats({
    required this.label,
    required this.payloadBytes,
    required this.samples,
    required this.batchIterations,
    required this.unitDivisor,
    required this.meanUs,
    required this.medianUs,
    required this.p95Us,
    required this.minUs,
    required this.maxUs,
    required this.throughputMbPerSec,
  });

  /// Descriptive label for the measured operation.
  final String label;

  /// UTF-8 byte size of the primary payload.
  final int payloadBytes;

  /// Number of timed sample windows.
  final int samples;

  /// Iterations executed per timed sample window.
  final int batchIterations;

  /// Sub-units per iteration (e.g. chunk count for streaming averages).
  final int unitDivisor;

  /// Arithmetic mean latency in microseconds.
  final double meanUs;

  /// Median (p50) latency in microseconds.
  final double medianUs;

  /// 95th percentile latency in microseconds.
  final double p95Us;

  /// Minimum observed latency in microseconds.
  final double minUs;

  /// Maximum observed latency in microseconds.
  final double maxUs;

  /// Throughput in MiB/s computed from median latency.
  final double throughputMbPerSec;

  /// Serializes this measurement summary to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'payloadBytes': payloadBytes,
    'samples': samples,
    'batchIterations': batchIterations,
    'unitDivisor': unitDivisor,
    'meanUs': meanUs,
    'medianUs': medianUs,
    'p95Us': p95Us,
    'minUs': minUs,
    'maxUs': maxUs,
    'throughputMbPerSec': throughputMbPerSec,
  };
}

/// Summary statistics for repeated millisecond measurements.
final class SampleSummary {
  /// Creates a [SampleSummary].
  const SampleSummary({
    required this.count,
    required this.median,
    required this.p95,
    required this.iqr,
    required this.mean,
    required this.min,
    required this.max,
  });

  /// Number of timed samples.
  final int count;

  /// Median (p50) value.
  final double median;

  /// 95th percentile value.
  final double p95;

  /// Interquartile range (`p75 - p25`).
  final double iqr;

  /// Arithmetic mean value.
  final double mean;

  /// Minimum observed value.
  final double min;

  /// Maximum observed value.
  final double max;
}

/// Specification for one participant in an interleaved latency benchmark.
final class InterleavedBenchmarkSpec {
  /// Creates an [InterleavedBenchmarkSpec].
  const InterleavedBenchmarkSpec({
    required this.label,
    required this.payloadBytes,
    required this.batchIterations,
    required this.operation,
    this.unitDivisor = 1,
    this.throughputBytesPerUnit,
  });

  /// Descriptive label for the measured operation.
  final String label;

  /// UTF-8 byte size of the primary payload.
  final int payloadBytes;

  /// Iterations executed per timed sample window.
  final int batchIterations;

  /// Sub-units per iteration (e.g. chunk count for streaming averages).
  final int unitDivisor;

  /// Optional payload bytes per sub-unit for throughput computation.
  final double? throughputBytesPerUnit;

  /// Synchronous benchmark operation under test.
  final void Function() operation;
}

/// Host hardware and Dart runtime metadata.
final class HostEnvironmentInfo {
  /// Creates a [HostEnvironmentInfo].
  const HostEnvironmentInfo({
    required this.cpuBrand,
    required this.arch,
    required this.os,
    required this.osVersion,
    required this.cores,
    required this.memory,
    required this.dartVersion,
  });

  /// CPU brand string.
  final String cpuBrand;

  /// CPU architecture (e.g. `arm64`, `x86_64`).
  final String arch;

  /// Operating system identifier.
  final String os;

  /// Operating system version string.
  final String osVersion;

  /// Logical processor count.
  final int cores;

  /// Physical memory summary.
  final String memory;

  /// Dart SDK version string.
  final String dartVersion;

  /// Serializes host info to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'cpuBrand': cpuBrand,
    'arch': arch,
    'os': os,
    'osVersion': osVersion,
    'cores': cores,
    'memory': memory,
    'dartVersion': dartVersion,
  };
}

/// Builds the ~1 KB technical Markdown snippet used across parser benchmarks.
String buildSmallDocument() {
  return '''# Cache Eviction Policy

The **bounded LRU cache** stores parsed `MarkdownDocument` instances keyed by source text and `MarkdownOptions`. Entries with ~~expired TTL~~ stale signatures are evicted in *O(1)* time via a linked hash map; see the [architecture overview](https://example.com/docs/cache) for details.

```dart
final MarkdownEngine engine = const MarkdownEngine(
  defaultOptions: MarkdownOptions.gfm(),
);
final MarkdownDocument doc = engine.parse(source);
final String html = doc.toHtml();
```

- [x] Deterministic UTF-16 `SourceSpan` tracking across all AST nodes
- [x] URL allowlist filtering for `javascript:` and `vbscript:` links
- [x] Bounded table column, row, and container nesting budgets
- [ ] Optional telemetry hook for custom slab allocators

> Keeping parsing and rendering strictly pure-Dart avoids WebView cold-start latency and guarantees identical HTML output across CLI, server, mobile, and desktop builds.
''';
}

/// Builds the ~25 KB multi-section README document used across parser benchmarks.
String buildMediumDocument() {
  final StringBuffer out = StringBuffer()
    ..writeln('# Platform SDK Reference Manual')
    ..writeln()
    ..writeln(
      'A deterministic, pure-Dart **CommonMark 0.31.2** and **GitHub Flavored Markdown** '
      'pipeline designed for *high-throughput* document rendering, live editors, and '
      'streaming feeds without WebView overhead. Explore the '
      '[API docs](https://example.com/api), inspect https://example.com/status, '
      'or review ~~legacy DOM hooks~~ modern sliver rendering.',
    )
    ..writeln();

  for (int section = 1; section <= 19; section++) {
    out
      ..writeln('## $section. Subsystem Module $section')
      ..writeln()
      ..writeln(
        'Module **$section** validates incoming payloads against `MarkdownBudgets` '
        'and produces immutable `MarkdownBlockNode` trees. Every heading, list item, '
        'and table cell preserves its *1-based line span* and sanitizes unsafe URIs '
        'such as [safe docs](https://example.com/modules/$section "Module $section Docs") '
        'while keeping `inline_code_$section()` crisp.',
      )
      ..writeln()
      ..writeln('| Option | Default | Type | Behavior |')
      ..writeln('| :--- | :---: | :--- | ---: |')
      ..writeln(
        '| `gfmTables` | `true` | `bool` | Parses aligned pipe tables in section $section |',
      )
      ..writeln(
        '| `gfmStrikethrough` | `true` | `bool` | Resolves ~~deleted spans~~ into `<del>` |',
      )
      ..writeln(
        '| `sanitizeUrls` | `true` | `bool` | Enforces `MarkdownUrlPolicy` on links & images |',
      )
      ..writeln(
        '| `maxNestingDepth` | `64` | `int` | Caps nested blockquotes and emphasis runs |',
      )
      ..writeln()
      ..writeln('```dart')
      ..writeln('void runModule$section(MarkdownEngine engine, String input) {')
      ..writeln(
        '  final MarkdownDocument doc = engine.parse(input, options: const MarkdownOptions.gfm());',
      )
      ..writeln('  final String html = doc.toHtml();')
      ..writeln('  assert(html.isNotEmpty);')
      ..writeln('}')
      ..writeln('```')
      ..writeln()
      ..writeln(
        '- [x] Verified CommonMark phase-1 container closure ($section)',
      )
      ..writeln(
        '- [x] Verified phase-2 delimiter stack resolution with **nested *emphasis***',
      )
      ..writeln(
        '- [ ] Benchmark custom theme tokens for dark/light contrast ($section)',
      )
      ..writeln()
      ..writeln(
        '> Subsystem $section runs synchronously in memory with zero filesystem I/O and '
        'deterministic output across Dart VM and native AOT binaries.',
      )
      ..writeln();
  }

  return out.toString();
}

/// Builds the ~5,000-line (~173 KB) document fixture with a 1-paragraph edit.
LargeEditFixture buildLargeDocumentFixture() {
  const int totalSections = 208;
  const int targetSection = 104;

  final StringBuffer base = StringBuffer()
    ..writeln('# Enterprise Architecture & Specification Corpus')
    ..writeln()
    ..writeln(
      'This synthetic **5,000-line** technical manual exercises full-document parsing '
      'and mid-document incremental edits with isolated blank-line block boundaries.',
    )
    ..writeln();

  final StringBuffer edited = StringBuffer()..write(base.toString());
  int editStartOffset = 0;
  int editOldEndOffset = 0;
  int editNewEndOffset = 0;
  int editedLineNumber = 0;

  for (int i = 1; i <= totalSections; i++) {
    final String heading = '## Section $i: Pipeline Stage & Storage\n\n';
    final String introParagraph =
        'Section **$i** explains how containers close across blank lines so '
        '`IncrementalMarkdownParser` reuses untouched prefix and suffix blocks. '
        'See [stage $i](https://example.com/s/$i) for span offsets.\n\n';

    final String editableOriginal =
        'Invariant $i states every `ParagraphNode` keeps a stable `blockId` '
        'and *monotonic* UTF-16 `SourceSpan` offsets across edits.\n\n';
    final String editableModified =
        'Invariant $i confirms every `ParagraphNode` keeps a stable `blockId`, '
        '*monotonic* UTF-16 `SourceSpan` offsets, and exact HTML parity across edits.\n\n';

    final String table =
        '| Metric | Stage $i | Budget |\n'
        '| :--- | :---: | ---: |\n'
        '| `tokens` | `${i * 12}` | `500000` |\n'
        '| `blocks` | `${i * 5}` | `50000` |\n'
        '| `depth` | `${(i % 6) + 1}` | `64` |\n\n';

    final String list =
        '- Normalize line endings for stage $i\n'
        '- Apply `MarkdownUrlPolicy` on external links\n'
        '- Escape entities inside `<pre><code>` blocks\n'
        '- Preserve ~~legacy~~ compatibility options\n\n';

    final String code =
        '```dart\n'
        'final int sum$i = ${i * 31} ^ 0x5A5A;\n'
        'final String id$i = \'stage-$i\';\n'
        '```\n\n';

    final String quote =
        '> Note $i: Pure-Dart execution keeps frame times predictable.\n\n';

    base.write(heading);
    edited.write(heading);

    base.write(introParagraph);
    edited.write(introParagraph);

    if (i == targetSection) {
      editStartOffset = base.length;
      editedLineNumber = countLines(base.toString());
      base.write(editableOriginal);
      edited.write(editableModified);
      // Exclude the trailing `\n\n` separator so the dirty range stays within
      // the edited paragraph and preserves all suffix blocks.
      editOldEndOffset = base.length - 2;
      editNewEndOffset = edited.length - 2;
    } else {
      base.write(editableOriginal);
      edited.write(editableOriginal);
    }

    base
      ..write(table)
      ..write(list)
      ..write(code)
      ..write(quote);
    edited
      ..write(table)
      ..write(list)
      ..write(code)
      ..write(quote);
  }

  final String baseSource = base.toString();
  final String editedSource = edited.toString();
  return LargeEditFixture(
    baseSource: baseSource,
    editedSource: editedSource,
    editStartOffset: editStartOffset,
    editOldEndOffset: editOldEndOffset,
    editNewEndOffset: editNewEndOffset,
    editedLineNumber: editedLineNumber,
    lineCount: countLines(baseSource),
  );
}

/// Builds a streaming Markdown payload split into [chunkCount] UTF-16 slices.
StreamingPayloadFixture buildStreamingFixture({int chunkCount = 50}) {
  const String full = '''# Streaming Response Walkthrough

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

  return StreamingPayloadFixture(
    fullSource: full,
    chunks: splitIntoChunks(full, chunkCount),
  );
}

/// Builds a 30-chunk mixed-content streaming fixture with a settled rich prefix
/// (heading, display TeX math, Mermaid diagram, and GitHub alert) followed by
/// streaming trailing prose, list, and summary chunks.
StreamingPayloadFixture buildMixedStreamingFixture() {
  const List<String> chunks = <String>[
    '# Hybrid Mixed-Content ',
    'Stream\n\n\$\$\n\\int_{0}^{\\infty} e^{-x^2}\\,dx = ',
    '\\frac{\\sqrt{\\pi}}{2}\n\$\$\n\n',
    '```mermaid\nflowchart LR\n  S["Settled Sliver"] --> ',
    'T["Tail Canvas"]\n```\n\n',
    '> [!TIP]\n> Settled math, Mermaid, and alert blocks remain frozen ',
    'while trailing prose streams incrementally.\n\n',
    'Trailing ',
    'prose ',
    'tokens ',
    'stream ',
    'into ',
    'the ',
    'dedicated ',
    'tail ',
    'canvas ',
    'without ',
    'rebuilding ',
    'settled ',
    'widgets.\n\n',
    '- Preserves ',
    'frozen **TexMath** ',
    'and *VectorGraphic* ',
    'slots\n',
    '- Keeps `blockId` ',
    'anchors ',
    'and selection ',
    'stable\n\n',
    'Final summary ',
    'line.\n',
  ];
  return StreamingPayloadFixture(fullSource: chunks.join(), chunks: chunks);
}

/// Builds 10 distinct Mermaid diagrams spanning multiple diagram families for
/// cold worker isolate and `compute()` benchmarks.
List<String> buildMermaid10DiagramCorpus() {
  return const <String>[
    '''flowchart LR
  Input["Markdown"] --> Parser["AST"]
  Parser --> Math["TexMath"]
  Parser --> Vector["VectorGraphic"]''',
    '''flowchart TD
  Start([Request]) --> Auth{Authenticated?}
  Auth -->|Yes| Render[Render Sliver]
  Auth -->|No| Reject[403 Error]''',
    '''sequenceDiagram
  participant Client
  participant Worker
  participant Cache
  Client->>Worker: compile(diagram)
  Worker-->>Cache: TransferableTypedData
  Cache-->>Client: CompiledBytes''',
    '''stateDiagram-v2
  [*] --> Idle
  Idle --> Compiling: append(mermaid)
  Compiling --> Cached: success
  Compiling --> Fallback: error
  Cached --> [*]''',
    '''classDiagram
  class MarkdownView {
    +String data
    +MarkdownThemeData theme
  }
  class MarkdownController {
    +int parseCount
  }
  MarkdownView --> MarkdownController''',
    '''erDiagram
  DOCUMENT ||--o{ BLOCK : contains
  BLOCK ||--o{ INLINE : contains
  DOCUMENT {
    string id
    int lineCount
  }''',
    '''pie title Render Pipeline Stages
  "Tokenize & Block" : 30
  "Inline Resolve" : 25
  "Text Layout" : 30
  "Vector Paint" : 15''',
    '''gantt
  title Streaming Frame Budget
  dateFormat X
  axisFormat %Lms
  section Main
  Append & Diff : 0, 2
  Canvas Paint : 2, 4
  section Isolate
  Mermaid Compile : 1, 5''',
    '''mindmap
  root((markdown_engine))
    Parser
      CommonMark 0.31.2
      GFM 0.29
    Renderers
      OpenType Math
      Vector Mermaid''',
    '''xychart-beta
  title "Chunk Throughput"
  x-axis [10, 20, 30, 40, 50]
  y-axis "Microseconds" 0 --> 20
  bar [4, 5, 4, 6, 5]''',
  ];
}

/// Builds a ~400-block rich Markdown document for headless widget benchmarks.
String buildWidget400BlockDocument() {
  const int sections = 67;
  final StringBuffer out = StringBuffer()
    ..writeln('# Widget Rendering Benchmark (400+ Blocks)')
    ..writeln();

  for (int i = 1; i <= sections; i++) {
    out
      ..writeln('## Section $i: Layout & Virtualization')
      ..writeln()
      ..writeln(
        'Section **$i** mixes *inline formatting*, `codeSpan($i)`, and '
        '[reference link $i](https://example.com/item/$i) across bounded slabs.',
      )
      ..writeln()
      ..writeln('- Bullet A for section $i')
      ..writeln('- Bullet B with **emphasis** for section $i')
      ..writeln()
      ..writeln('| Key | Value | Status |')
      ..writeln('| :--- | :---: | ---: |')
      ..writeln('| `id` | `$i` | `ok` |')
      ..writeln()
      ..writeln('```dart')
      ..writeln('final int section$i = $i * 2;')
      ..writeln('```')
      ..writeln()
      ..writeln('> Callout $i: Slivers paint only viewport-visible blocks.')
      ..writeln();
  }

  return out.toString();
}

/// Splits [source] deterministically into [chunkCount] non-empty substrings.
List<String> splitIntoChunks(String source, int chunkCount) {
  final int totalLen = source.length;
  final List<String> chunks = <String>[];
  for (int i = 0; i < chunkCount; i++) {
    final int start = (i * totalLen) ~/ chunkCount;
    final int end = ((i + 1) * totalLen) ~/ chunkCount;
    if (end > start) {
      chunks.add(source.substring(start, end));
    }
  }
  return chunks;
}

/// Builds an adversarial string with [count] unmatched `<` tag prefixes.
String buildAdversarialUnmatchedLt(int count) => '<a ' * count;

/// Builds an adversarial string with [count] unmatched `*` emphasis delimiters.
String buildAdversarialUnmatchedStar(int count) => '*a ' * count;

/// Builds an adversarial string with [count] unmatched `$` math delimiters.
String buildAdversarialUnmatchedDollar(int count) => r'$a ' * count;

/// Builds a ~10 KB deeply nested emphasis string (`*a *a ... core a* a*`).
String buildAdversarialNestedEmphasis10Kb() {
  const int pairs = 1706; // 1706 * 6 + 4 = 10,240 UTF-16 code units (10 KiB).
  return '${'*a ' * pairs}core${' a*' * pairs}';
}

/// Locates the `corpus/spec/` directory relative to the current working
/// directory or an explicit override path.
String resolveCorpusSpecDir({String? overrideDir}) {
  final List<String> candidates = <String>[
    if (overrideDir != null && overrideDir.isNotEmpty) overrideDir,
    'corpus/spec',
    '../corpus/spec',
    '../../corpus/spec',
    '../../../corpus/spec',
  ];
  for (final String candidate in candidates) {
    final File marker = File('$candidate/commonmark_0.31.2.json');
    if (marker.existsSync()) {
      return candidate;
    }
  }
  throw StateError(
    'Unable to locate corpus/spec/commonmark_0.31.2.json from '
    '${Directory.current.path}. Pass --corpus-dir=<path> if running elsewhere.',
  );
}

/// Loads all CommonMark `0.31.2` JSON examples from [specDir].
List<SpecFixtureCase> loadCommonMarkSpecCases(String specDir) {
  final File file = File('$specDir/commonmark_0.31.2.json');
  final List<Object?> rawList =
      jsonDecode(file.readAsStringSync()) as List<Object?>;
  final List<SpecFixtureCase> cases = <SpecFixtureCase>[];
  for (final Object? item in rawList) {
    final Map<String, Object?> map = item as Map<String, Object?>;
    cases.add(
      SpecFixtureCase(
        suite: 'commonmark',
        exampleNumber: map['example'] as int,
        section: map['section'] as String,
        markdown: map['markdown'] as String,
        expectedHtml: map['html'] as String,
      ),
    );
  }
  return cases;
}

/// Loads cmark-gfm `.txt` examples (`gfm_0.29.0_spec.txt` or
/// `gfm_0.29.0_extensions.txt`) from [filePath].
List<SpecFixtureCase> loadCmarkTxtSpecCases(
  String filePath, {
  required String suite,
}) {
  final List<String> lines = File(filePath).readAsLinesSync();
  final List<SpecFixtureCase> cases = <SpecFixtureCase>[];
  final RegExp fenceOpen = RegExp(r'^`{32} example(?:\s+(.*))?$');
  final RegExp fenceClose = RegExp(r'^`{32}$');
  final RegExp headingPattern = RegExp(r'^#{1,6}\s+(.+)$');

  String currentSection = 'General';
  int exampleNumber = 0;

  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final RegExpMatch? fenceMatch = fenceOpen.firstMatch(line);
    if (fenceMatch != null) {
      exampleNumber++;
      final String tag = (fenceMatch.group(1) ?? '').trim();
      final List<String> mdLines = <String>[];
      final List<String> htmlLines = <String>[];

      i++;
      while (i < lines.length && lines[i] != '.') {
        mdLines.add(lines[i].replaceAll('\u2192', '\t'));
        i++;
      }
      if (i >= lines.length || lines[i] != '.') {
        throw FormatException(
          'Missing "." separator in $filePath at line ${i + 1}',
        );
      }

      i++;
      while (i < lines.length && !fenceClose.hasMatch(lines[i])) {
        htmlLines.add(lines[i].replaceAll('\u2192', '\t'));
        i++;
      }
      if (i >= lines.length) {
        throw FormatException('Unclosed example block in $filePath at line $i');
      }

      final String markdown = '${mdLines.join('\n')}\n';
      final String rawHtml = htmlLines.join('\n');
      final bool isIgnored = rawHtml.trim() == '<IGNORE>';
      final String expectedHtml = htmlLines.isEmpty ? '' : '$rawHtml\n';

      cases.add(
        SpecFixtureCase(
          suite: suite,
          exampleNumber: exampleNumber,
          section: currentSection,
          markdown: markdown,
          expectedHtml: expectedHtml,
          tag: tag,
          ignored: isIgnored,
          disabled: tag == 'disabled',
        ),
      );
      continue;
    }

    final RegExpMatch? headingMatch = headingPattern.firstMatch(line);
    if (headingMatch != null) {
      currentSection = headingMatch.group(1)!.trim();
    }
  }

  return cases;
}

/// Benchmarks [operation] with warmup and repeated multi-iteration samples.
LatencyStats measureLatency({
  required String label,
  required int payloadBytes,
  required int warmupSamples,
  required int samples,
  required int batchIterations,
  required void Function() operation,
  int unitDivisor = 1,
  double? throughputBytesPerUnit,
}) {
  for (int w = 0; w < warmupSamples; w++) {
    for (int i = 0; i < batchIterations; i++) {
      operation();
    }
  }

  final Stopwatch sw = Stopwatch();
  final List<double> perUnitUs = <double>[];

  for (int s = 0; s < samples; s++) {
    sw
      ..reset()
      ..start();
    for (int i = 0; i < batchIterations; i++) {
      operation();
    }
    sw.stop();
    perUnitUs.add(sw.elapsedMicroseconds / (batchIterations * unitDivisor));
  }

  return _computeLatencyStats(
    label: label,
    payloadBytes: payloadBytes,
    samples: samples,
    batchIterations: batchIterations,
    unitDivisor: unitDivisor,
    throughputBytesPerUnit: throughputBytesPerUnit,
    perUnitUs: perUnitUs,
  );
}

/// Returns round-robin indices `0 .. count - 1` rotated by [round].
List<int> interleaveRoundIndices(int count, int round) {
  if (count <= 0) {
    return const <int>[];
  }
  final int start = round % count;
  return List<int>.generate(count, (int k) => (start + k) % count);
}

/// Benchmarks [specs] using round-robin interleaved rotation across
/// [warmupRounds] and [timedRounds] so scheduling jitter and thermal drift
/// affect every participant uniformly.
List<LatencyStats> measureInterleavedLatencies({
  required List<InterleavedBenchmarkSpec> specs,
  required int warmupRounds,
  required int timedRounds,
}) {
  for (int round = 0; round < warmupRounds; round++) {
    for (final int idx in interleaveRoundIndices(specs.length, round)) {
      final InterleavedBenchmarkSpec spec = specs[idx];
      for (int i = 0; i < spec.batchIterations; i++) {
        spec.operation();
      }
    }
  }

  final Stopwatch sw = Stopwatch();
  final List<List<double>> perUnitSamples = List<List<double>>.generate(
    specs.length,
    (_) => <double>[],
  );

  for (int round = 0; round < timedRounds; round++) {
    for (final int idx in interleaveRoundIndices(
      specs.length,
      warmupRounds + round,
    )) {
      final InterleavedBenchmarkSpec spec = specs[idx];
      sw
        ..reset()
        ..start();
      for (int i = 0; i < spec.batchIterations; i++) {
        spec.operation();
      }
      sw.stop();
      perUnitSamples[idx].add(
        sw.elapsedMicroseconds / (spec.batchIterations * spec.unitDivisor),
      );
    }
  }

  return List<LatencyStats>.generate(specs.length, (int idx) {
    final InterleavedBenchmarkSpec spec = specs[idx];
    return _computeLatencyStats(
      label: spec.label,
      payloadBytes: spec.payloadBytes,
      samples: timedRounds,
      batchIterations: spec.batchIterations,
      unitDivisor: spec.unitDivisor,
      throughputBytesPerUnit: spec.throughputBytesPerUnit,
      perUnitUs: perUnitSamples[idx],
    );
  });
}

LatencyStats _computeLatencyStats({
  required String label,
  required int payloadBytes,
  required int samples,
  required int batchIterations,
  required int unitDivisor,
  required double? throughputBytesPerUnit,
  required List<double> perUnitUs,
}) {
  final SampleSummary summary = summarizeSamples(perUnitUs);
  final double effectiveBytes =
      throughputBytesPerUnit ?? payloadBytes.toDouble();
  final double throughputMbPerSec = summary.median > 0
      ? (effectiveBytes / (1024.0 * 1024.0)) / (summary.median / 1000000.0)
      : 0.0;

  return LatencyStats(
    label: label,
    payloadBytes: payloadBytes,
    samples: samples,
    batchIterations: batchIterations,
    unitDivisor: unitDivisor,
    meanUs: _round2(summary.mean),
    medianUs: _round2(summary.median),
    p95Us: _round2(summary.p95),
    minUs: _round2(summary.min),
    maxUs: _round2(summary.max),
    throughputMbPerSec: _round2(throughputMbPerSec),
  );
}

/// Computes `median` (`p50`), `p95`, `iqr`, `mean`, `min`, and `max` across
/// [rawSamples].
SampleSummary summarizeSamples(List<double> rawSamples) {
  if (rawSamples.isEmpty) {
    return const SampleSummary(
      count: 0,
      median: 0.0,
      p95: 0.0,
      iqr: 0.0,
      mean: 0.0,
      min: 0.0,
      max: 0.0,
    );
  }
  final List<double> sorted = List<double>.of(rawSamples)..sort();
  final double mean =
      sorted.reduce((double a, double b) => a + b) / sorted.length;
  final double median = _percentile(sorted, 0.50);
  final double p95 = _percentile(sorted, 0.95);
  final double p25 = _percentile(sorted, 0.25);
  final double p75 = _percentile(sorted, 0.75);
  return SampleSummary(
    count: sorted.length,
    median: median,
    p95: p95,
    iqr: p75 - p25,
    mean: mean,
    min: sorted.first,
    max: sorted.last,
  );
}

/// Formats a millisecond [SampleSummary] with both `p50` and `p95`.
String formatMsSummary(SampleSummary summary) =>
    '${summary.median.toStringAsFixed(2)} ms '
    '(p95=${summary.p95.toStringAsFixed(2)} ms)';

/// Collects host hardware and Dart version details for benchmark reports.
HostEnvironmentInfo collectHostEnvironmentInfo() {
  String cpuBrand = '${Platform.operatingSystem} CPU';
  String arch = 'unknown';
  String memorySummary = 'unknown';

  try {
    final ProcessResult unameResult = Process.runSync('uname', <String>['-m']);
    if (unameResult.exitCode == 0) {
      arch = (unameResult.stdout as String).trim();
    }
  } on ProcessException {
    arch = 'unknown';
  }

  if (Platform.isMacOS) {
    try {
      final ProcessResult cpuRes = Process.runSync('sysctl', <String>[
        '-n',
        'machdep.cpu.brand_string',
      ]);
      if (cpuRes.exitCode == 0 && (cpuRes.stdout as String).trim().isNotEmpty) {
        cpuBrand = (cpuRes.stdout as String).trim();
      }
      final ProcessResult memRes = Process.runSync('sysctl', <String>[
        '-n',
        'hw.memsize',
      ]);
      if (memRes.exitCode == 0) {
        final int? bytes = int.tryParse((memRes.stdout as String).trim());
        if (bytes != null && bytes > 0) {
          final double gib = bytes / (1024 * 1024 * 1024);
          memorySummary = '${gib.toStringAsFixed(0)} GiB';
        }
      }
    } on ProcessException {
      // Retain default metadata when sysctl is unavailable.
    }
  } else if (Platform.isLinux) {
    final File cpuInfo = File('/proc/cpuinfo');
    if (cpuInfo.existsSync()) {
      for (final String line in cpuInfo.readAsLinesSync()) {
        if (line.startsWith('model name')) {
          final int colon = line.indexOf(':');
          if (colon != -1) {
            cpuBrand = line.substring(colon + 1).trim();
            break;
          }
        }
      }
    }
    final File memInfo = File('/proc/meminfo');
    if (memInfo.existsSync()) {
      for (final String line in memInfo.readAsLinesSync()) {
        if (line.startsWith('MemTotal:')) {
          final RegExpMatch? m = RegExp(r'(\d+)').firstMatch(line);
          if (m != null) {
            final int kib = int.parse(m.group(1)!);
            final double gib = kib / (1024 * 1024);
            memorySummary = '${gib.toStringAsFixed(0)} GiB';
            break;
          }
        }
      }
    }
  }

  final String dartVersion = Platform.version.split(' ').first;
  return HostEnvironmentInfo(
    cpuBrand: cpuBrand,
    arch: arch,
    os: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion.trim(),
    cores: Platform.numberOfProcessors,
    memory: memorySummary,
    dartVersion: dartVersion,
  );
}

/// Counts lines in [text].
int countLines(String text) {
  if (text.isEmpty) {
    return 0;
  }
  int count = 0;
  for (int i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      count++;
    }
  }
  return text.endsWith('\n') ? count : count + 1;
}

/// Formats microseconds into readable `us` or `ms` units.
String formatMicroseconds(double us) {
  if (us >= 1000.0) {
    return '${(us / 1000.0).toStringAsFixed(3)} ms';
  }
  return '${us.toStringAsFixed(2)} us';
}

/// Formats byte counts as `B` or `KB`.
String formatBytes(int bytes) {
  if (bytes >= 1024) {
    return '${(bytes / 1024.0).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) {
    return 0.0;
  }
  if (sorted.length == 1) {
    return sorted.first;
  }
  final double index = p * (sorted.length - 1);
  final int lower = index.floor();
  final int upper = index.ceil();
  if (lower == upper) {
    return sorted[lower];
  }
  final double fraction = index - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

double _round2(double value) => (value * 100.0).roundToDouble() / 100.0;
