import 'dart:convert';
import 'dart:io';

import 'package:markdown_engine/markdown_engine.dart';

import 'src/cli_args.dart';

const String _baselinePath = 'tool/benchmark_baseline.json';
const String _docsPath = 'doc/BENCHMARKS.md';

/// Generous per-workload median (p50) latency ceilings in microseconds designed
/// to catch catastrophic O(N^2) regressions without flaking on shared CI VMs.
const Map<String, double> _sanityCeilingsUs = <String, double>{
  'small_doc_parse_and_html': 2000.0, // 2.0 ms for ~1 KB parse + HTML
  'medium_doc_parse_and_html': 30000.0, // 30.0 ms for ~25 KB parse + HTML
  'large_doc_5000_lines_parse': 200000.0, // 200.0 ms for ~5,000-line parse
  'incremental_single_paragraph_edit': 25000.0, // 25.0 ms incremental edit
  'streaming_llm_50_chunks_per_chunk': 5000.0, // 5.0 ms average per chunk
};

const double _minIncrementalReusedRatio = 0.90;
const double _minIncrementalSpeedup = 2.0;

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/benchmark_suite.dart '
      '[--update-docs] [--update-baseline] [--check-regressions] '
      '[--no-aot] [--json]',
    );
    return;
  }

  if (args.contains('--aot-worker') || args.contains('--no-aot')) {
    exitCode = _runBenchmarksEntry(args);
    return;
  }

  exitCode = _compileAndRunAot(args);
}

int _compileAndRunAot(List<String> args) {
  final Directory tempDir = Directory.systemTemp.createTempSync(
    'markdown_engine_bench_',
  );
  final String exePath = '${tempDir.path}/benchmark_suite.exe';
  try {
    final ProcessResult compileResult = Process.runSync('dart', <String>[
      'compile',
      'exe',
      'tool/benchmark_suite.dart',
      '-o',
      exePath,
    ]);
    if (compileResult.exitCode != 0) {
      stderr.writeln('ERROR: Failed to AOT-compile tool/benchmark_suite.dart.');
      if ((compileResult.stdout as String).isNotEmpty) {
        stderr.writeln(compileResult.stdout);
      }
      if ((compileResult.stderr as String).isNotEmpty) {
        stderr.writeln(compileResult.stderr);
      }
      return compileResult.exitCode == 0 ? 1 : compileResult.exitCode;
    }

    final ProcessResult runResult = Process.runSync(exePath, <String>[
      '--aot-worker',
      ...args,
    ]);
    if ((runResult.stdout as String).isNotEmpty) {
      stdout.write(runResult.stdout);
    }
    if ((runResult.stderr as String).isNotEmpty) {
      stderr.write(runResult.stderr);
    }
    return runResult.exitCode;
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

int _runBenchmarksEntry(List<String> args) {
  final bool updateDocs = args.contains('--update-docs');
  final bool updateBaseline = args.contains('--update-baseline');
  final bool checkRegressions = args.contains('--check-regressions');
  final bool jsonOutput = args.contains('--json');
  final bool isAot = args.contains('--aot-worker');
  final double? toleranceOverride = parseDoubleFlag(args, 'tolerance');

  final _HardwareInfo hardware = _collectHardwareInfo(isAot: isAot);
  final _SuiteRun suite = _executeSuite();

  if (updateBaseline) {
    final Map<String, Object?> payload = _buildJsonPayload(
      hardware: hardware,
      suite: suite,
      checks: null,
      passed: null,
    );
    File(_baselinePath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
    if (!jsonOutput) {
      stdout.writeln('Updated $_baselinePath.');
    }
  }

  if (updateDocs) {
    final String markdown = _renderBenchmarksMarkdown(
      hardware: hardware,
      suite: suite,
    );
    File(_docsPath).writeAsStringSync(markdown);
    if (!jsonOutput) {
      stdout.writeln('Updated $_docsPath.');
    }
  }

  bool passed = true;
  final List<_RegressionCheck> checks = <_RegressionCheck>[];
  if (checkRegressions) {
    final double multiplier = toleranceOverride ?? 1.0;
    for (final _BenchmarkResult result in suite.results) {
      final double ceilingUs =
          (_sanityCeilingsUs[result.id] ?? result.medianUs * 5.0) * multiplier;
      final bool ok = result.medianUs <= ceilingUs;
      if (!ok) {
        passed = false;
      }
      checks.add(
        _RegressionCheck(
          id: result.id,
          metric: 'medianUs',
          measured: result.medianUs,
          threshold: ceilingUs,
          comparator: '<=',
          unit: 'us',
          passed: ok,
        ),
      );
    }

    final bool reuseOk =
        suite.incremental.reusedRatio >= _minIncrementalReusedRatio;
    if (!reuseOk) {
      passed = false;
    }
    checks.add(
      _RegressionCheck(
        id: 'incremental_reused_block_ratio',
        metric: 'reusedRatio',
        measured: _round4(suite.incremental.reusedRatio),
        threshold: _minIncrementalReusedRatio,
        comparator: '>=',
        unit: 'ratio',
        passed: reuseOk,
      ),
    );

    final bool speedupOk =
        suite.incremental.speedupFactor >= _minIncrementalSpeedup;
    if (!speedupOk) {
      passed = false;
    }
    checks.add(
      _RegressionCheck(
        id: 'incremental_vs_full_speedup',
        metric: 'speedupFactor',
        measured: _round2(suite.incremental.speedupFactor),
        threshold: _minIncrementalSpeedup,
        comparator: '>=',
        unit: 'x',
        passed: speedupOk,
      ),
    );

    final bool settledOk = suite.streaming.settledBlocksBeforeFinish > 0;
    if (!settledOk) {
      passed = false;
    }
    checks.add(
      _RegressionCheck(
        id: 'streaming_settled_blocks',
        metric: 'settledBlocksBeforeFinish',
        measured: suite.streaming.settledBlocksBeforeFinish.toDouble(),
        threshold: 1.0,
        comparator: '>=',
        unit: 'blocks',
        passed: settledOk,
      ),
    );
  }

  if (jsonOutput) {
    final Map<String, Object?> payload = _buildJsonPayload(
      hardware: hardware,
      suite: suite,
      checks: checkRegressions ? checks : null,
      passed: checkRegressions ? passed : null,
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
  } else {
    stdout.writeln(
      'markdown_engine benchmarks (${hardware.executionMode}, '
      '${hardware.cpuBrand}, ${hardware.os} ${hardware.arch}, '
      'Dart ${hardware.dartVersion}):',
    );
    for (final _BenchmarkResult r in suite.results) {
      stdout.writeln(
        '  ${r.id}: median=${_fmtUs(r.medianUs)}, mean=${_fmtUs(r.meanUs)}, '
        'p95=${_fmtUs(r.p95Us)}, throughput=${r.throughputMbPerSec.toStringAsFixed(2)} MB/s '
        '(${_fmtBytes(r.payloadBytes)}, ${r.samples}x${r.batchIterations})',
      );
    }
    stdout.writeln(
      '  incremental telemetry: '
      'speedup=${suite.incremental.speedupFactor.toStringAsFixed(2)}x vs full parse, '
      'reused=${suite.incremental.reusedBlocks}/${suite.incremental.totalBlocks} '
      '(${(suite.incremental.reusedRatio * 100.0).toStringAsFixed(1)}%), '
      'reparsed=${suite.incremental.reparsedBlocks}',
    );
    stdout.writeln(
      '  streaming telemetry: ${suite.streaming.chunkCount} chunks, '
      'total=${_fmtUs(suite.streaming.totalSessionMedianUs)}, '
      'per-chunk median=${_fmtUs(suite.streaming.perChunkMedianUs)}, '
      'settled before finish=${suite.streaming.settledBlocksBeforeFinish}/${suite.streaming.finalBlockCount} blocks',
    );
    if (checkRegressions) {
      for (final _RegressionCheck c in checks) {
        final String status = c.passed ? 'PASS' : 'FAIL';
        final String measuredStr = c.unit == 'us'
            ? _fmtUs(c.measured)
            : '${c.measured} ${c.unit}';
        final String thresholdStr = c.unit == 'us'
            ? _fmtUs(c.threshold)
            : '${c.threshold} ${c.unit}';
        stdout.writeln(
          '  [$status] ${c.id}: $measuredStr ${c.comparator} $thresholdStr',
        );
      }
    }
  }

  return passed ? 0 : 1;
}

Map<String, Object?> _buildJsonPayload({
  required _HardwareInfo hardware,
  required _SuiteRun suite,
  required List<_RegressionCheck>? checks,
  required bool? passed,
}) {
  return <String, Object?>{
    'schemaVersion': 2,
    'processMaxRssMb': _round2(ProcessInfo.maxRss / (1024.0 * 1024.0)),
    'hardware': hardware.toJson(),
    'benchmarks': suite.results
        .map((_BenchmarkResult r) => r.toJson())
        .toList(),
    'incremental': suite.incremental.toJson(),
    'streaming': suite.streaming.toJson(),
    if (checks != null)
      'regressionChecks': checks
          .map((_RegressionCheck c) => c.toJson())
          .toList(),
    'passed': ?passed,
  };
}

_SuiteRun _executeSuite() {
  const MarkdownOptions gfmOptions = MarkdownOptions.gfm();
  const MarkdownEngine engine = MarkdownEngine(defaultOptions: gfmOptions);
  const IncrementalMarkdownParser incrementalParser = IncrementalMarkdownParser(
    engine: engine,
  );

  final String smallDoc = _buildSmallDocument();
  final String mediumDoc = _buildMediumDocument();
  final _LargeFixture largeFixture = _buildLargeDocumentFixture();
  final _StreamingFixture streamingFixture = _buildStreamingFixture();

  final int smallBytes = utf8.encode(smallDoc).length;
  final int mediumBytes = utf8.encode(mediumDoc).length;
  final int largeBytes = utf8.encode(largeFixture.baseSource).length;
  final int streamBytes = utf8.encode(streamingFixture.fullSource).length;

  // Validate correctness of incremental and streaming fixtures outside timed
  // loops so benchmark timings reflect verified semantics.
  final MarkdownDocument baseLargeDoc = engine.parse(largeFixture.baseSource);
  final MarkdownDocument expectedEditedDoc = engine.parse(
    largeFixture.editedSource,
  );
  final IncrementalParseResult verifiedInc = incrementalParser.parseIncremental(
    largeFixture.editedSource,
    previousDocument: baseLargeDoc,
    editStartOffset: largeFixture.editStartOffset,
    editOldEndOffset: largeFixture.editOldEndOffset,
    editNewEndOffset: largeFixture.editNewEndOffset,
  );
  if (verifiedInc.document.toHtml() != expectedEditedDoc.toHtml()) {
    throw StateError(
      'Incremental parse HTML diverged from full parse HTML on large fixture.',
    );
  }
  if (verifiedInc.reusedBlockCount <= 0) {
    throw StateError('Incremental parse reused zero blocks on large fixture.');
  }

  final StreamingMarkdownController verifyStream = StreamingMarkdownController(
    engine: engine,
    options: gfmOptions,
  );
  for (final String chunk in streamingFixture.chunks) {
    verifyStream.append(chunk);
  }
  final int settledBeforeFinish = verifyStream.settledBlockCount;
  final MarkdownDocument finalStreamDoc = verifyStream.finish();
  final MarkdownDocument expectedStreamDoc = engine.parse(
    streamingFixture.fullSource,
  );
  if (finalStreamDoc.toHtml() != expectedStreamDoc.toHtml()) {
    throw StateError(
      'Streaming finish() HTML diverged from full parse HTML on 50-chunk fixture.',
    );
  }

  int sink = 0;

  // 1. Small document (~1 KB) full parse + toHtml().
  final _BenchmarkResult smallResult = _measure(
    id: 'small_doc_parse_and_html',
    label: 'Small doc (~1 KB) parse + toHtml',
    description:
        'Full GFM parse and HTML serialization of a ${_fmtBytes(smallBytes)} '
        '(${_countLines(smallDoc)} lines) technical Markdown snippet',
    payloadBytes: smallBytes,
    lineCount: _countLines(smallDoc),
    warmupSamples: 5,
    samples: 25,
    batchIterations: 400,
    operation: () {
      final String html = engine.parse(smallDoc).toHtml();
      sink ^= html.length;
    },
  );

  // 2. Medium document (~25 KB README) full parse + toHtml().
  final _BenchmarkResult mediumResult = _measure(
    id: 'medium_doc_parse_and_html',
    label: 'Medium README (~25 KB) parse + toHtml',
    description:
        'Full GFM parse and HTML serialization of a ${_fmtBytes(mediumBytes)} '
        '(${_countLines(mediumDoc)} lines) README with tables, code, lists, and links',
    payloadBytes: mediumBytes,
    lineCount: _countLines(mediumDoc),
    warmupSamples: 4,
    samples: 25,
    batchIterations: 25,
    operation: () {
      final String html = engine.parse(mediumDoc).toHtml();
      sink ^= html.length;
    },
  );

  // 3. Large document (~5,000 lines / ~200 KB) full parse.
  final _BenchmarkResult largeResult = _measure(
    id: 'large_doc_5000_lines_parse',
    label: 'Large doc (5k lines) full parse',
    description:
        'Full GFM AST parse of a ${_fmtBytes(largeBytes)} '
        '(${largeFixture.lineCount} lines, ${baseLargeDoc.blocks.length} blocks) document',
    payloadBytes: largeBytes,
    lineCount: largeFixture.lineCount,
    warmupSamples: 3,
    samples: 21,
    batchIterations: 4,
    operation: () {
      final MarkdownDocument doc = engine.parse(largeFixture.baseSource);
      sink ^= doc.blocks.length;
    },
  );

  // 4. Incremental single-paragraph edit in the 5,000-line document.
  final _BenchmarkResult incrementalResult = _measure(
    id: 'incremental_single_paragraph_edit',
    label: 'Incremental 1-paragraph edit',
    description:
        'Single-paragraph mid-document edit in the ${largeFixture.lineCount}-line '
        'document via IncrementalMarkdownParser '
        '(${verifiedInc.reusedBlockCount}/${verifiedInc.document.blocks.length} blocks reused)',
    payloadBytes: largeBytes,
    lineCount: largeFixture.lineCount,
    warmupSamples: 4,
    samples: 25,
    batchIterations: 25,
    operation: () {
      final IncrementalParseResult res = incrementalParser.parseIncremental(
        largeFixture.editedSource,
        previousDocument: baseLargeDoc,
        editStartOffset: largeFixture.editStartOffset,
        editOldEndOffset: largeFixture.editOldEndOffset,
        editNewEndOffset: largeFixture.editNewEndOffset,
      );
      sink ^= res.reusedBlockCount;
    },
  );

  // 5. Streaming LLM chunked append over 50 chunks (per-chunk tail latency).
  final StreamingMarkdownController benchStream = StreamingMarkdownController(
    engine: engine,
    options: gfmOptions,
  );
  final int chunkCount = streamingFixture.chunks.length;
  final _BenchmarkResult streamingResult = _measure(
    id: 'streaming_llm_50_chunks_per_chunk',
    label: 'Streaming LLM (avg / 50 chunks)',
    description:
        'Average per-chunk tail latency across $chunkCount streamed chunks '
        '(${_fmtBytes(streamBytes)} total, $settledBeforeFinish settled blocks before finish)',
    payloadBytes: streamBytes,
    lineCount: _countLines(streamingFixture.fullSource),
    warmupSamples: 4,
    samples: 25,
    batchIterations: 15,
    unitDivisor: chunkCount,
    throughputBytesPerUnit: streamBytes / chunkCount,
    operation: () {
      benchStream.reset();
      for (final String chunk in streamingFixture.chunks) {
        final MarkdownDocument doc = benchStream.append(chunk);
        sink ^= doc.blocks.length;
      }
    },
  );

  // Prevent compiler dead-code elimination of the sink accumulator.
  if (sink == -1) {
    stderr.writeln('unreachable sink guard: $sink');
  }

  final double speedupFactor = incrementalResult.medianUs > 0
      ? largeResult.medianUs / incrementalResult.medianUs
      : 0.0;
  final int totalBlocks = verifiedInc.document.blocks.length;
  final double reusedRatio = totalBlocks > 0
      ? verifiedInc.reusedBlockCount / totalBlocks
      : 0.0;

  final _IncrementalTelemetry incrementalTelemetry = _IncrementalTelemetry(
    fullParseMedianUs: largeResult.medianUs,
    incrementalMedianUs: incrementalResult.medianUs,
    speedupFactor: _round2(speedupFactor),
    totalBlocks: totalBlocks,
    reusedBlocks: verifiedInc.reusedBlockCount,
    reparsedBlocks: verifiedInc.reparsedBlockCount,
    reusedRatio: reusedRatio,
    editedLineNumber: largeFixture.editedLineNumber,
  );

  final _StreamingTelemetry streamingTelemetry = _StreamingTelemetry(
    chunkCount: chunkCount,
    totalPayloadBytes: streamBytes,
    perChunkMedianUs: streamingResult.medianUs,
    perChunkMeanUs: streamingResult.meanUs,
    totalSessionMedianUs: _round2(streamingResult.medianUs * chunkCount),
    totalSessionMeanUs: _round2(streamingResult.meanUs * chunkCount),
    settledBlocksBeforeFinish: settledBeforeFinish,
    finalBlockCount: finalStreamDoc.blocks.length,
  );

  return _SuiteRun(
    results: <_BenchmarkResult>[
      smallResult,
      mediumResult,
      largeResult,
      incrementalResult,
      streamingResult,
    ],
    incremental: incrementalTelemetry,
    streaming: streamingTelemetry,
  );
}

_BenchmarkResult _measure({
  required String id,
  required String label,
  required String description,
  required int payloadBytes,
  required int lineCount,
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

  final int rssBefore = ProcessInfo.currentRss;
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

  final int rssAfter = ProcessInfo.currentRss;
  final int maxRss = ProcessInfo.maxRss;

  perUnitUs.sort();
  final double meanUs =
      perUnitUs.reduce((double a, double b) => a + b) / perUnitUs.length;
  final double medianUs = _percentile(perUnitUs, 0.50);
  final double p95Us = _percentile(perUnitUs, 0.95);
  final double minUs = perUnitUs.first;
  final double maxUs = perUnitUs.last;

  final double effectiveBytes =
      throughputBytesPerUnit ?? payloadBytes.toDouble();
  final double throughputMbPerSec = medianUs > 0
      ? (effectiveBytes / (1024.0 * 1024.0)) / (medianUs / 1000000.0)
      : 0.0;

  return _BenchmarkResult(
    id: id,
    label: label,
    description: description,
    payloadBytes: payloadBytes,
    lineCount: lineCount,
    warmupSamples: warmupSamples,
    samples: samples,
    batchIterations: batchIterations,
    unitDivisor: unitDivisor,
    meanUs: _round2(meanUs),
    medianUs: _round2(medianUs),
    p95Us: _round2(p95Us),
    minUs: _round2(minUs),
    maxUs: _round2(maxUs),
    throughputMbPerSec: _round2(throughputMbPerSec),
    rssMb: _round2(rssAfter / (1024.0 * 1024.0)),
    rssDeltaKb: _round2((rssAfter - rssBefore) / 1024.0),
    maxRssMb: _round2(maxRss / (1024.0 * 1024.0)),
  );
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

String _buildSmallDocument() {
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

String _buildMediumDocument() {
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

_LargeFixture _buildLargeDocumentFixture() {
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
      editedLineNumber = _countLines(base.toString());
      base.write(editableOriginal);
      edited.write(editableModified);
      // Exclude trailing `\n\n` so the edit window stays inside the paragraph.
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
  return _LargeFixture(
    baseSource: baseSource,
    editedSource: editedSource,
    editStartOffset: editStartOffset,
    editOldEndOffset: editOldEndOffset,
    editNewEndOffset: editNewEndOffset,
    editedLineNumber: editedLineNumber,
    lineCount: _countLines(baseSource),
  );
}

_StreamingFixture _buildStreamingFixture() {
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

  const int chunkCount = 50;
  final List<String> chunks = <String>[];
  final int totalLen = full.length;
  for (int i = 0; i < chunkCount; i++) {
    final int start = (i * totalLen) ~/ chunkCount;
    final int end = ((i + 1) * totalLen) ~/ chunkCount;
    chunks.add(full.substring(start, end));
  }

  return _StreamingFixture(fullSource: full, chunks: chunks);
}

String _renderBenchmarksMarkdown({
  required _HardwareInfo hardware,
  required _SuiteRun suite,
}) {
  final _BenchmarkResult small = suite.byId('small_doc_parse_and_html');
  final _BenchmarkResult medium = suite.byId('medium_doc_parse_and_html');
  final _BenchmarkResult large = suite.byId('large_doc_5000_lines_parse');
  final _BenchmarkResult inc = suite.byId('incremental_single_paragraph_edit');
  final _BenchmarkResult stream = suite.byId(
    'streaming_llm_50_chunks_per_chunk',
  );

  final StringBuffer out = StringBuffer()
    ..writeln('# Benchmarks (Native AOT)')
    ..writeln()
    ..writeln(
      'These timings are measured from a self-compiled native AOT binary built with `dart compile exe tool/benchmark_suite.dart` and executed directly against the pure-Dart `markdown_engine` package (`MarkdownOptions.gfm()`).',
    )
    ..writeln()
    ..writeln(
      'Every workload runs warmup batches before recording repeated multi-iteration samples to report median (`p50`), mean, `p95`, min/max latencies, and UTF-8 throughput (`MB/s`), alongside incremental block-reuse and streaming tail-latency telemetry.',
    )
    ..writeln()
    ..writeln('## Host Environment')
    ..writeln()
    ..writeln('| Property | Value |')
    ..writeln('| :--- | :--- |')
    ..writeln('| CPU | `${hardware.cpuBrand}` |')
    ..writeln('| Architecture | `${hardware.arch}` |')
    ..writeln('| OS | `${hardware.os}` (`${hardware.osVersion}`) |')
    ..writeln('| Logical Cores | `${hardware.cores}` |')
    ..writeln('| Memory | `${hardware.memory}` |')
    ..writeln('| Dart SDK | `${hardware.dartVersion}` |')
    ..writeln('| Execution Mode | `${hardware.executionMode}` |')
    ..writeln(
      '| Peak Process RSS | `${(ProcessInfo.maxRss / (1024.0 * 1024.0)).toStringAsFixed(2)} MiB` |',
    )
    ..writeln()
    ..writeln('## Measured Native AOT Timings')
    ..writeln()
    ..writeln(
      '| Benchmark | Payload | Samples x Batch | Mean | Median (p50) | p95 | Throughput (p50) | CI Ceiling (p50) |',
    )
    ..writeln('| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final _BenchmarkResult r in suite.results) {
    final double ceilingUs = _sanityCeilingsUs[r.id] ?? 0.0;
    final String payloadSummary = r.unitDivisor > 1
        ? '${_fmtBytes(r.payloadBytes)} / ${r.unitDivisor} chunks'
        : '${_fmtBytes(r.payloadBytes)} (${r.lineCount} lines)';
    out.writeln(
      '| `${r.id}` | $payloadSummary | `${r.samples} x ${r.batchIterations}` | '
      '${_fmtUs(r.meanUs)} | **${_fmtUs(r.medianUs)}** | ${_fmtUs(r.p95Us)} | '
      '${r.throughputMbPerSec.toStringAsFixed(2)} MB/s | <= ${_fmtUs(ceilingUs)} |',
    );
  }

  _writeHorizontalMedianChart(
    out,
    <_BenchmarkResult>[small, medium, inc, stream],
    title:
        'Native AOT Median Latency (Sub-Millisecond & Interactive Workloads)',
    stepUs: 100.0,
  );

  _writeHorizontalMedianChart(
    out,
    <_BenchmarkResult>[large, inc],
    title:
        '5,000-Line Document: Full Parse vs Incremental Single-Paragraph Edit',
    stepUs: 500.0,
  );

  out
    ..writeln()
    ..writeln('## Incremental Editing & Streaming Telemetry')
    ..writeln()
    ..writeln(
      'Both `IncrementalMarkdownParser` and `StreamingMarkdownController` verify exact HTML equivalence against `MarkdownEngine.parse` before timed sampling begins.',
    )
    ..writeln()
    ..writeln('### Incremental Single-Paragraph Edit (5,000-Line Document)')
    ..writeln()
    ..writeln('| Metric | Measured Value |')
    ..writeln('| :--- | ---: |')
    ..writeln(
      '| Full 5,000-line parse (`large_doc_5000_lines_parse` p50) | `${_fmtUs(suite.incremental.fullParseMedianUs)}` |',
    )
    ..writeln(
      '| Incremental single-paragraph edit (`incremental_single_paragraph_edit` p50) | `${_fmtUs(suite.incremental.incrementalMedianUs)}` |',
    )
    ..writeln(
      '| **Speedup Factor vs Full Parse** | **`${suite.incremental.speedupFactor.toStringAsFixed(2)}x`** |',
    )
    ..writeln(
      '| Edited Location | Line `${suite.incremental.editedLineNumber}` of `${large.lineCount}` |',
    )
    ..writeln(
      '| Reused Top-Level Blocks | `${suite.incremental.reusedBlocks} / ${suite.incremental.totalBlocks}` (**${(suite.incremental.reusedRatio * 100.0).toStringAsFixed(2)}%**) |',
    )
    ..writeln(
      '| Reparsed Top-Level Blocks | `${suite.incremental.reparsedBlocks}` |',
    )
    ..writeln()
    ..writeln('### Streaming LLM Chunked Append (50 Chunks)')
    ..writeln()
    ..writeln('| Metric | Measured Value |')
    ..writeln('| :--- | ---: |')
    ..writeln('| Total Chunks Appended | `${suite.streaming.chunkCount}` |')
    ..writeln(
      '| Total Streamed Payload | `${_fmtBytes(suite.streaming.totalPayloadBytes)}` |',
    )
    ..writeln(
      '| **Average Per-Chunk Tail Latency (p50 / Mean)** | **`${_fmtUs(suite.streaming.perChunkMedianUs)}`** / `${_fmtUs(suite.streaming.perChunkMeanUs)}` |',
    )
    ..writeln(
      '| Full 50-Chunk Session Time (p50 / Mean) | `${_fmtUs(suite.streaming.totalSessionMedianUs)}` / `${_fmtUs(suite.streaming.totalSessionMeanUs)}` |',
    )
    ..writeln(
      '| Settled Prefix Blocks Frozen Before `finish()` | `${suite.streaming.settledBlocksBeforeFinish} / ${suite.streaming.finalBlockCount}` |',
    )
    ..writeln()
    ..writeln('## Methodology & Regression Ceilings')
    ..writeln()
    ..writeln(
      'Each benchmark executes deterministic in-memory fixtures under `MarkdownOptions.gfm()` with zero filesystem or network I/O during timed loops. Each timed sample wraps `batchIterations` consecutive calls in a single `Stopwatch` window and divides elapsed microseconds by `batchIterations` (and by `50` chunks for `streaming_llm_50_chunks_per_chunk`) to eliminate clock-quantization jitter. Throughput (`MB/s`) divides the UTF-8 payload byte count (in MiB, `1024 * 1024` bytes) by median latency in seconds.',
    )
    ..writeln()
    ..writeln(
      '`dart run tool/benchmark_suite.dart --check-regressions` enforces generous latency ceilings (plus minimum `>= 90%` block reuse, `>= 2.0x` incremental speedup, and `>= 1` settled streaming block) so CI catches catastrophic `O(N^2)` algorithmic regressions without flaking across heterogeneous shared runner hardware.',
    )
    ..writeln()
    ..writeln('## Running Locally')
    ..writeln()
    ..writeln('```bash')
    ..writeln('# Run native AOT benchmarks and enforce CI regression ceilings')
    ..writeln('dart run tool/benchmark_suite.dart --check-regressions')
    ..writeln()
    ..writeln('# Regenerate doc/BENCHMARKS.md with fresh local measurements')
    ..writeln('dart run tool/benchmark_suite.dart --update-docs')
    ..writeln()
    ..writeln('# Emit structured JSON telemetry')
    ..writeln('dart run tool/benchmark_suite.dart --json')
    ..writeln('```');

  return out.toString();
}

void _writeHorizontalMedianChart(
  StringBuffer out,
  List<_BenchmarkResult> subset, {
  required String title,
  required double stepUs,
}) {
  double maxUs = stepUs;
  for (final _BenchmarkResult r in subset) {
    if (r.medianUs > maxUs) {
      maxUs = r.medianUs;
    }
  }
  final int yAxisMax = (((maxUs * 1.2) / stepUs).ceil() * stepUs).toInt();
  final String xLabels = subset
      .map((_BenchmarkResult r) => '"${r.label}"')
      .join(', ');
  final String values = subset
      .map((_BenchmarkResult r) => r.medianUs.toStringAsFixed(2))
      .join(', ');

  out
    ..writeln()
    ..writeln('```mermaid')
    ..writeln('xychart-beta horizontal')
    ..writeln('    title "$title"')
    ..writeln('    x-axis [$xLabels]')
    ..writeln('    y-axis "Median Microseconds (p50)" 0 --> $yAxisMax')
    ..writeln('    bar [$values]')
    ..writeln('```');
}

_HardwareInfo _collectHardwareInfo({required bool isAot}) {
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
      // Retain default fallback metadata.
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
  return _HardwareInfo(
    cpuBrand: cpuBrand,
    arch: arch,
    os: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion.trim(),
    cores: Platform.numberOfProcessors,
    memory: memorySummary,
    dartVersion: dartVersion,
    executionMode: isAot ? 'Native AOT' : 'Dart JIT VM',
  );
}

int _countLines(String text) {
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

double _round2(double value) => (value * 100.0).roundToDouble() / 100.0;

double _round4(double value) => (value * 10000.0).roundToDouble() / 10000.0;

String _fmtUs(double us) {
  if (us >= 1000.0) {
    return '${(us / 1000.0).toStringAsFixed(3)} ms';
  }
  return '${us.toStringAsFixed(2)} us';
}

String _fmtBytes(int bytes) {
  if (bytes >= 1024) {
    return '${(bytes / 1024.0).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

final class _LargeFixture {
  const _LargeFixture({
    required this.baseSource,
    required this.editedSource,
    required this.editStartOffset,
    required this.editOldEndOffset,
    required this.editNewEndOffset,
    required this.editedLineNumber,
    required this.lineCount,
  });

  final String baseSource;
  final String editedSource;
  final int editStartOffset;
  final int editOldEndOffset;
  final int editNewEndOffset;
  final int editedLineNumber;
  final int lineCount;
}

final class _StreamingFixture {
  const _StreamingFixture({required this.fullSource, required this.chunks});

  final String fullSource;
  final List<String> chunks;
}

final class _SuiteRun {
  const _SuiteRun({
    required this.results,
    required this.incremental,
    required this.streaming,
  });

  final List<_BenchmarkResult> results;
  final _IncrementalTelemetry incremental;
  final _StreamingTelemetry streaming;

  _BenchmarkResult byId(String id) {
    return results.firstWhere((_BenchmarkResult r) => r.id == id);
  }
}

final class _HardwareInfo {
  const _HardwareInfo({
    required this.cpuBrand,
    required this.arch,
    required this.os,
    required this.osVersion,
    required this.cores,
    required this.memory,
    required this.dartVersion,
    required this.executionMode,
  });

  final String cpuBrand;
  final String arch;
  final String os;
  final String osVersion;
  final int cores;
  final String memory;
  final String dartVersion;
  final String executionMode;

  Map<String, Object?> toJson() => <String, Object?>{
    'cpuBrand': cpuBrand,
    'arch': arch,
    'os': os,
    'osVersion': osVersion,
    'cores': cores,
    'memory': memory,
    'dartVersion': dartVersion,
    'executionMode': executionMode,
  };
}

final class _BenchmarkResult {
  const _BenchmarkResult({
    required this.id,
    required this.label,
    required this.description,
    required this.payloadBytes,
    required this.lineCount,
    required this.warmupSamples,
    required this.samples,
    required this.batchIterations,
    required this.unitDivisor,
    required this.meanUs,
    required this.medianUs,
    required this.p95Us,
    required this.minUs,
    required this.maxUs,
    required this.throughputMbPerSec,
    required this.rssMb,
    required this.rssDeltaKb,
    required this.maxRssMb,
  });

  final String id;
  final String label;
  final String description;
  final int payloadBytes;
  final int lineCount;
  final int warmupSamples;
  final int samples;
  final int batchIterations;
  final int unitDivisor;
  final double meanUs;
  final double medianUs;
  final double p95Us;
  final double minUs;
  final double maxUs;
  final double throughputMbPerSec;
  final double rssMb;
  final double rssDeltaKb;
  final double maxRssMb;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'description': description,
    'unit': 'us',
    'payloadBytes': payloadBytes,
    'lineCount': lineCount,
    'warmupSamples': warmupSamples,
    'samples': samples,
    'batchIterations': batchIterations,
    'unitDivisor': unitDivisor,
    'meanUs': meanUs,
    'medianUs': medianUs,
    'p95Us': p95Us,
    'minUs': minUs,
    'maxUs': maxUs,
    'throughputMbPerSec': throughputMbPerSec,
    'rssMb': rssMb,
    'rssDeltaKb': rssDeltaKb,
    'maxRssMb': maxRssMb,
  };
}

final class _IncrementalTelemetry {
  const _IncrementalTelemetry({
    required this.fullParseMedianUs,
    required this.incrementalMedianUs,
    required this.speedupFactor,
    required this.totalBlocks,
    required this.reusedBlocks,
    required this.reparsedBlocks,
    required this.reusedRatio,
    required this.editedLineNumber,
  });

  final double fullParseMedianUs;
  final double incrementalMedianUs;
  final double speedupFactor;
  final int totalBlocks;
  final int reusedBlocks;
  final int reparsedBlocks;
  final double reusedRatio;
  final int editedLineNumber;

  Map<String, Object?> toJson() => <String, Object?>{
    'fullParseMedianUs': fullParseMedianUs,
    'incrementalMedianUs': incrementalMedianUs,
    'speedupFactor': speedupFactor,
    'totalBlocks': totalBlocks,
    'reusedBlocks': reusedBlocks,
    'reparsedBlocks': reparsedBlocks,
    'reusedRatio': _round4(reusedRatio),
    'editedLineNumber': editedLineNumber,
  };
}

final class _StreamingTelemetry {
  const _StreamingTelemetry({
    required this.chunkCount,
    required this.totalPayloadBytes,
    required this.perChunkMedianUs,
    required this.perChunkMeanUs,
    required this.totalSessionMedianUs,
    required this.totalSessionMeanUs,
    required this.settledBlocksBeforeFinish,
    required this.finalBlockCount,
  });

  final int chunkCount;
  final int totalPayloadBytes;
  final double perChunkMedianUs;
  final double perChunkMeanUs;
  final double totalSessionMedianUs;
  final double totalSessionMeanUs;
  final int settledBlocksBeforeFinish;
  final int finalBlockCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'chunkCount': chunkCount,
    'totalPayloadBytes': totalPayloadBytes,
    'perChunkMedianUs': perChunkMedianUs,
    'perChunkMeanUs': perChunkMeanUs,
    'totalSessionMedianUs': totalSessionMedianUs,
    'totalSessionMeanUs': totalSessionMeanUs,
    'settledBlocksBeforeFinish': settledBlocksBeforeFinish,
    'finalBlockCount': finalBlockCount,
  };
}

final class _RegressionCheck {
  const _RegressionCheck({
    required this.id,
    required this.metric,
    required this.measured,
    required this.threshold,
    required this.comparator,
    required this.unit,
    required this.passed,
  });

  final String id;
  final String metric;
  final double measured;
  final double threshold;
  final String comparator;
  final String unit;
  final bool passed;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'metric': metric,
    'measured': measured,
    'threshold': threshold,
    'comparator': comparator,
    'unit': unit,
    'passed': passed,
  };
}
