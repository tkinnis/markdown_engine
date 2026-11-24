import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:markdown_engine/markdown_engine.dart';
import 'package:markdown_engine_compare/compare_fixtures.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run bin/compare_parsers_aot.dart '
      '[--corpus-dir=<path>] [--json]',
    );
    return;
  }

  final bool jsonOutput = args.contains('--json');
  final String? corpusOverride = _parseStringFlag(args, 'corpus-dir');
  final String specDir = resolveCorpusSpecDir(overrideDir: corpusOverride);
  final HostEnvironmentInfo host = collectHostEnvironmentInfo();

  const MarkdownOptions gfmOptions = MarkdownOptions.gfm();
  const MarkdownEngine engine = MarkdownEngine(defaultOptions: gfmOptions);
  const IncrementalMarkdownParser incrementalParser = IncrementalMarkdownParser(
    engine: engine,
  );

  final String smallDoc = buildSmallDocument();
  final String mediumDoc = buildMediumDocument();
  final LargeEditFixture largeFixture = buildLargeDocumentFixture();
  final StreamingPayloadFixture streamingFixture = buildStreamingFixture();

  final int smallBytes = utf8.encode(smallDoc).length;
  final int mediumBytes = utf8.encode(mediumDoc).length;
  final int largeBytes = utf8.encode(largeFixture.baseSource).length;
  final int streamBytes = utf8.encode(streamingFixture.fullSource).length;

  final MarkdownDocument baseLargeDoc = engine.parse(largeFixture.baseSource);
  final IncrementalParseResult verifiedInc = incrementalParser.parseIncremental(
    largeFixture.editedSource,
    previousDocument: baseLargeDoc,
    editStartOffset: largeFixture.editStartOffset,
    editOldEndOffset: largeFixture.editOldEndOffset,
    editNewEndOffset: largeFixture.editNewEndOffset,
  );

  int sink = 0;

  // 1. Small doc (~1 KB) parse + HTML (interleaved).
  final List<LatencyStats> smallStats = measureInterleavedLatencies(
    warmupRounds: 6,
    timedRounds: 25,
    specs: <InterleavedBenchmarkSpec>[
      InterleavedBenchmarkSpec(
        label: 'markdown_engine small parse+HTML',
        payloadBytes: smallBytes,
        batchIterations: 400,
        operation: () {
          sink ^= engine.parse(smallDoc).toHtml().length;
        },
      ),
      InterleavedBenchmarkSpec(
        label: 'package:markdown small parse+HTML',
        payloadBytes: smallBytes,
        batchIterations: 400,
        operation: () {
          sink ^= md
              .markdownToHtml(
                smallDoc,
                extensionSet: md.ExtensionSet.gitHubFlavored,
                enableTagfilter: true,
              )
              .length;
        },
      ),
    ],
  );
  final LatencyStats smallEngine = smallStats[0];
  final LatencyStats smallPkgMarkdown = smallStats[1];

  // 2. Medium doc (~25 KB) parse + HTML (interleaved).
  final List<LatencyStats> mediumStats = measureInterleavedLatencies(
    warmupRounds: 6,
    timedRounds: 25,
    specs: <InterleavedBenchmarkSpec>[
      InterleavedBenchmarkSpec(
        label: 'markdown_engine medium parse+HTML',
        payloadBytes: mediumBytes,
        batchIterations: 25,
        operation: () {
          sink ^= engine.parse(mediumDoc).toHtml().length;
        },
      ),
      InterleavedBenchmarkSpec(
        label: 'package:markdown medium parse+HTML',
        payloadBytes: mediumBytes,
        batchIterations: 25,
        operation: () {
          sink ^= md
              .markdownToHtml(
                mediumDoc,
                extensionSet: md.ExtensionSet.gitHubFlavored,
                enableTagfilter: true,
              )
              .length;
        },
      ),
    ],
  );
  final LatencyStats mediumEngine = mediumStats[0];
  final LatencyStats mediumPkgMarkdown = mediumStats[1];

  // 3. Large doc (5,000 lines, ~173 KB) AST parse and parse+HTML (interleaved).
  final List<LatencyStats> largeAstStats = measureInterleavedLatencies(
    warmupRounds: 5,
    timedRounds: 21,
    specs: <InterleavedBenchmarkSpec>[
      InterleavedBenchmarkSpec(
        label: 'markdown_engine large AST parse',
        payloadBytes: largeBytes,
        batchIterations: 4,
        operation: () {
          sink ^= engine.parse(largeFixture.baseSource).blocks.length;
        },
      ),
      InterleavedBenchmarkSpec(
        label: 'package:markdown large AST parse',
        payloadBytes: largeBytes,
        batchIterations: 4,
        operation: () {
          final md.Document doc = md.Document(
            extensionSet: md.ExtensionSet.gitHubFlavored,
          );
          sink ^= doc.parse(largeFixture.baseSource).length;
        },
      ),
    ],
  );
  final LatencyStats largeEngineAst = largeAstStats[0];
  final LatencyStats largePkgMarkdownAst = largeAstStats[1];

  final List<LatencyStats> largeHtmlStats = measureInterleavedLatencies(
    warmupRounds: 5,
    timedRounds: 21,
    specs: <InterleavedBenchmarkSpec>[
      InterleavedBenchmarkSpec(
        label: 'markdown_engine large parse+HTML',
        payloadBytes: largeBytes,
        batchIterations: 4,
        operation: () {
          sink ^= engine.parse(largeFixture.baseSource).toHtml().length;
        },
      ),
      InterleavedBenchmarkSpec(
        label: 'package:markdown large parse+HTML',
        payloadBytes: largeBytes,
        batchIterations: 4,
        operation: () {
          sink ^= md
              .markdownToHtml(
                largeFixture.baseSource,
                extensionSet: md.ExtensionSet.gitHubFlavored,
                enableTagfilter: true,
              )
              .length;
        },
      ),
    ],
  );
  final LatencyStats largeEngineHtml = largeHtmlStats[0];
  final LatencyStats largePkgMarkdownHtml = largeHtmlStats[1];

  // 4. Incremental 1-paragraph edit on 5,000 lines vs full re-parse.
  final LatencyStats incrementalEngine = measureLatency(
    label: 'markdown_engine incremental edit',
    payloadBytes: largeBytes,
    warmupSamples: 6,
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

  // 5. 50-chunk LLM stream (incremental tail vs full re-parse, interleaved).
  final StreamingMarkdownController streamController =
      StreamingMarkdownController(engine: engine, options: gfmOptions);
  final int chunkCount = streamingFixture.chunks.length;
  final List<LatencyStats> streamStats = measureInterleavedLatencies(
    warmupRounds: 6,
    timedRounds: 25,
    specs: <InterleavedBenchmarkSpec>[
      InterleavedBenchmarkSpec(
        label: 'markdown_engine 50-chunk stream (per-chunk)',
        payloadBytes: streamBytes,
        batchIterations: 15,
        unitDivisor: chunkCount,
        throughputBytesPerUnit: streamBytes / chunkCount,
        operation: () {
          streamController.reset();
          for (final String chunk in streamingFixture.chunks) {
            sink ^= streamController.append(chunk).blocks.length;
          }
        },
      ),
      InterleavedBenchmarkSpec(
        label: 'package:markdown 50-chunk full-reparse (per-chunk)',
        payloadBytes: streamBytes,
        batchIterations: 5,
        unitDivisor: chunkCount,
        throughputBytesPerUnit: streamBytes / chunkCount,
        operation: () {
          final StringBuffer accumulated = StringBuffer();
          for (final String chunk in streamingFixture.chunks) {
            accumulated.write(chunk);
            final md.Document doc = md.Document(
              extensionSet: md.ExtensionSet.gitHubFlavored,
            );
            sink ^= doc.parse(accumulated.toString()).length;
          }
        },
      ),
    ],
  );
  final LatencyStats streamEngine = streamStats[0];
  final LatencyStats streamPkgMarkdown = streamStats[1];
  streamController.dispose();

  // 6. Adversarial inputs (safe try/catch for StackOverflowError or Errors).
  final List<_AdversarialComparison> adversarialResults =
      <_AdversarialComparison>[
        _runAdversarialCase(
          id: 'unmatched_lt_5000',
          label: '5,000 unmatched `<` (`<a ` * 5000)',
          input: buildAdversarialUnmatchedLt(5000),
          engine: engine,
          engineOptions: gfmOptions,
        ),
        _runAdversarialCase(
          id: 'unmatched_star_5000',
          label: '5,000 unmatched `*` (`*a ` * 5000)',
          input: buildAdversarialUnmatchedStar(5000),
          engine: engine,
          engineOptions: gfmOptions,
        ),
        _runAdversarialCase(
          id: 'unmatched_dollar_5000',
          label: r'5,000 unmatched `$` (`$a ` * 5000, math enabled)',
          input: buildAdversarialUnmatchedDollar(5000),
          engine: engine,
          engineOptions: const MarkdownOptions.gfm(math: true),
        ),
        _runAdversarialCase(
          id: 'nested_emphasis_10kb',
          label: '10 KB nested emphasis (`*a ` * 1706 + core + ` a*` * 1706)',
          input: buildAdversarialNestedEmphasis10Kb(),
          engine: engine,
          engineOptions: gfmOptions,
        ),
      ];

  // 7. CommonMark 0.31.2 + GFM 0.29.0 specification parity comparison.
  final _SpecComparisonResult specComparison = _runSpecComparison(
    specDir: specDir,
    engine: engine,
  );

  if (sink == -1) {
    stderr.writeln('unreachable sink guard: $sink');
  }

  final Map<String, Object?> report = <String, Object?>{
    'sampling': 'interleaved',
    'host': host.toJson(),
    'payloads': <String, Object?>{
      'smallBytes': smallBytes,
      'smallLines': countLines(smallDoc),
      'mediumBytes': mediumBytes,
      'mediumLines': countLines(mediumDoc),
      'largeBytes': largeBytes,
      'largeLines': largeFixture.lineCount,
      'largeBlocks': baseLargeDoc.blocks.length,
      'streamBytes': streamBytes,
      'streamChunks': chunkCount,
    },
    'benchmarks': <String, Object?>{
      'small_markdown_engine': smallEngine.toJson(),
      'small_package_markdown': smallPkgMarkdown.toJson(),
      'medium_markdown_engine': mediumEngine.toJson(),
      'medium_package_markdown': mediumPkgMarkdown.toJson(),
      'large_ast_markdown_engine': largeEngineAst.toJson(),
      'large_ast_package_markdown': largePkgMarkdownAst.toJson(),
      'large_html_markdown_engine': largeEngineHtml.toJson(),
      'large_html_package_markdown': largePkgMarkdownHtml.toJson(),
      'incremental_edit_markdown_engine': incrementalEngine.toJson(),
      'incremental_reused_blocks': verifiedInc.reusedBlockCount,
      'incremental_total_blocks': verifiedInc.document.blocks.length,
      'stream_per_chunk_markdown_engine': streamEngine.toJson(),
      'stream_per_chunk_package_markdown': streamPkgMarkdown.toJson(),
    },
    'adversarial': adversarialResults
        .map((_AdversarialComparison c) => c.toJson())
        .toList(),
    'specParity': specComparison.toJson(),
  };

  if (jsonOutput) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    return;
  }

  _printReport(
    host: host,
    smallBytes: smallBytes,
    mediumBytes: mediumBytes,
    largeBytes: largeBytes,
    largeLines: largeFixture.lineCount,
    streamBytes: streamBytes,
    chunkCount: chunkCount,
    smallEngine: smallEngine,
    smallPkgMarkdown: smallPkgMarkdown,
    mediumEngine: mediumEngine,
    mediumPkgMarkdown: mediumPkgMarkdown,
    largeEngineAst: largeEngineAst,
    largePkgMarkdownAst: largePkgMarkdownAst,
    largeEngineHtml: largeEngineHtml,
    largePkgMarkdownHtml: largePkgMarkdownHtml,
    incrementalEngine: incrementalEngine,
    verifiedInc: verifiedInc,
    streamEngine: streamEngine,
    streamPkgMarkdown: streamPkgMarkdown,
    adversarialResults: adversarialResults,
    specComparison: specComparison,
  );
}

_AdversarialComparison _runAdversarialCase({
  required String id,
  required String label,
  required String input,
  required MarkdownEngine engine,
  required MarkdownOptions engineOptions,
}) {
  final int inputBytes = utf8.encode(input).length;
  int engineOp() => engine.parse(input, options: engineOptions).toHtml().length;
  int pkgOp() => md
      .markdownToHtml(
        input,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        enableTagfilter: true,
      )
      .length;

  final List<({String status, double elapsedUs, int outputLength})> firstRound =
      <({String status, double elapsedUs, int outputLength})>[
        _runSingleProtected(engineOp),
        _runSingleProtected(pkgOp),
      ];

  final List<List<double>> samplesUs = <List<double>>[
    <double>[firstRound[0].elapsedUs],
    <double>[firstRound[1].elapsedUs],
  ];
  final bool engineFast =
      firstRound[0].status == 'ok' && firstRound[0].elapsedUs < 25000.0;
  final bool pkgFast =
      firstRound[1].status == 'ok' && firstRound[1].elapsedUs < 25000.0;

  if (engineFast || pkgFast) {
    for (int round = 1; round <= 4; round++) {
      for (final int idx in interleaveRoundIndices(2, round)) {
        if (idx == 0 && engineFast) {
          final ({String status, double elapsedUs, int outputLength}) res =
              _runSingleProtected(engineOp);
          if (res.status == 'ok') {
            samplesUs[0].add(res.elapsedUs);
          }
        } else if (idx == 1 && pkgFast) {
          final ({String status, double elapsedUs, int outputLength}) res =
              _runSingleProtected(pkgOp);
          if (res.status == 'ok') {
            samplesUs[1].add(res.elapsedUs);
          }
        }
      }
    }
  }

  _AdversarialOutcome toOutcome(int idx) {
    final ({String status, double elapsedUs, int outputLength}) initial =
        firstRound[idx];
    if (initial.status != 'ok') {
      return _AdversarialOutcome(
        status: initial.status,
        elapsedUs: initial.elapsedUs,
        outputLength: 0,
      );
    }
    final SampleSummary summary = summarizeSamples(samplesUs[idx]);
    return _AdversarialOutcome(
      status: 'ok',
      elapsedUs: summary.median,
      outputLength: initial.outputLength,
    );
  }

  return _AdversarialComparison(
    id: id,
    label: label,
    inputBytes: inputBytes,
    markdownEngine: toOutcome(0),
    packageMarkdown: toOutcome(1),
  );
}

({String status, double elapsedUs, int outputLength}) _runSingleProtected(
  int Function() operation,
) {
  final Stopwatch sw = Stopwatch()..start();
  try {
    final int outputLen = operation();
    sw.stop();
    return (
      status: 'ok',
      elapsedUs: sw.elapsedMicroseconds.toDouble(),
      outputLength: outputLen,
    );
  } on StackOverflowError {
    sw.stop();
    return (
      status: 'StackOverflowError',
      elapsedUs: sw.elapsedMicroseconds.toDouble(),
      outputLength: 0,
    );
  } on Object catch (error) {
    sw.stop();
    return (
      status: 'Error(${error.runtimeType})',
      elapsedUs: sw.elapsedMicroseconds.toDouble(),
      outputLength: 0,
    );
  }
}

_SpecComparisonResult _runSpecComparison({
  required String specDir,
  required MarkdownEngine engine,
}) {
  final List<SpecFixtureCase> commonMarkCases = loadCommonMarkSpecCases(
    specDir,
  );
  final List<SpecFixtureCase> gfmSpecCases = loadCmarkTxtSpecCases(
    '$specDir/gfm_0.29.0_spec.txt',
    suite: 'gfm_spec',
  );
  final List<SpecFixtureCase> gfmExtCases = loadCmarkTxtSpecCases(
    '$specDir/gfm_0.29.0_extensions.txt',
    suite: 'gfm_extensions',
  );

  final _SuiteParity cmStats = _evaluateSuite(
    name: 'CommonMark 0.31.2',
    cases: commonMarkCases,
    engine: engine,
    engineOptionsForCase: (_) => const MarkdownOptions.commonMark(),
    pkgExtensionSet: md.ExtensionSet.commonMark,
    pkgTagfilter: false,
  );

  final _SuiteParity gfmSpecStats = _evaluateSuite(
    name: 'GFM 0.29.0 Spec',
    cases: gfmSpecCases,
    engine: engine,
    engineOptionsForCase: (SpecFixtureCase testCase) =>
        MarkdownOptions.commonMark(collapseNestedStrong: true).copyWith(
          gfmTables: testCase.tag == 'table',
          gfmStrikethrough: testCase.tag == 'strikethrough',
          gfmAutolinks: testCase.tag == 'autolink',
          gfmTagFilter: testCase.tag == 'tagfilter',
        ),
    pkgExtensionSet: md.ExtensionSet.gitHubFlavored,
    pkgTagfilter: true,
  );

  final _SuiteParity gfmExtStats = _evaluateSuite(
    name: 'GFM 0.29.0 Extensions',
    cases: gfmExtCases,
    engine: engine,
    engineOptionsForCase: (_) => const MarkdownOptions.gfm(headingSlugs: false),
    pkgExtensionSet: md.ExtensionSet.gitHubFlavored,
    pkgTagfilter: true,
  );

  return _SpecComparisonResult(
    commonMark: cmStats,
    gfmSpec: gfmSpecStats,
    gfmExtensions: gfmExtStats,
  );
}

_SuiteParity _evaluateSuite({
  required String name,
  required List<SpecFixtureCase> cases,
  required MarkdownEngine engine,
  required MarkdownOptions Function(SpecFixtureCase) engineOptionsForCase,
  required md.ExtensionSet pkgExtensionSet,
  required bool pkgTagfilter,
}) {
  int total = 0;
  int disabled = 0;
  int active = 0;
  int ignored = 0;
  int enginePassed = 0;
  int pkgPassed = 0;
  int pkgErrors = 0;

  for (final SpecFixtureCase testCase in cases) {
    total++;
    if (testCase.disabled) {
      disabled++;
      continue;
    }

    final MarkdownOptions options = engineOptionsForCase(testCase);
    final String engineHtml = engine.renderToHtml(
      testCase.markdown,
      options: options,
    );

    String? pkgHtml;
    bool pkgCrashed = false;
    try {
      pkgHtml = md.markdownToHtml(
        testCase.markdown,
        extensionSet: pkgExtensionSet,
        enableTagfilter: pkgTagfilter,
      );
    } on Object {
      pkgCrashed = true;
      pkgErrors++;
    }

    if (testCase.ignored) {
      ignored++;
      active++;
      enginePassed++;
      if (!pkgCrashed) {
        pkgPassed++;
      }
      continue;
    }

    active++;
    if (engineHtml == testCase.expectedHtml) {
      enginePassed++;
    }
    if (!pkgCrashed && pkgHtml == testCase.expectedHtml) {
      pkgPassed++;
    }
  }

  return _SuiteParity(
    name: name,
    total: total,
    active: active,
    disabled: disabled,
    ignored: ignored,
    markdownEnginePassed: enginePassed,
    packageMarkdownPassed: pkgPassed,
    packageMarkdownErrors: pkgErrors,
  );
}

void _printReport({
  required HostEnvironmentInfo host,
  required int smallBytes,
  required int mediumBytes,
  required int largeBytes,
  required int largeLines,
  required int streamBytes,
  required int chunkCount,
  required LatencyStats smallEngine,
  required LatencyStats smallPkgMarkdown,
  required LatencyStats mediumEngine,
  required LatencyStats mediumPkgMarkdown,
  required LatencyStats largeEngineAst,
  required LatencyStats largePkgMarkdownAst,
  required LatencyStats largeEngineHtml,
  required LatencyStats largePkgMarkdownHtml,
  required LatencyStats incrementalEngine,
  required IncrementalParseResult verifiedInc,
  required LatencyStats streamEngine,
  required LatencyStats streamPkgMarkdown,
  required List<_AdversarialComparison> adversarialResults,
  required _SpecComparisonResult specComparison,
}) {
  stdout.writeln(
    '=== Pure-Dart Parser Comparison: markdown_engine vs package:markdown 7.3.1 ===',
  );
  stdout.writeln(
    'Host: ${host.cpuBrand} (${host.arch}), ${host.os} ${host.osVersion}, '
    '${host.cores} cores, ${host.memory}, Dart ${host.dartVersion}',
  );
  stdout.writeln();

  stdout.writeln('--- Throughput & Latency (interleaved p50 median / p95) ---');
  _printPair(
    'Small (~1 KB, ${formatBytes(smallBytes)}) parse+HTML',
    smallEngine,
    smallPkgMarkdown,
  );
  _printPair(
    'Medium (~25 KB, ${formatBytes(mediumBytes)}) parse+HTML',
    mediumEngine,
    mediumPkgMarkdown,
  );
  _printPair(
    'Large ($largeLines lines, ${formatBytes(largeBytes)}) AST parse',
    largeEngineAst,
    largePkgMarkdownAst,
  );
  _printPair(
    'Large ($largeLines lines, ${formatBytes(largeBytes)}) parse+HTML',
    largeEngineHtml,
    largePkgMarkdownHtml,
  );

  final double incVsEngineFull = largeEngineAst.medianUs > 0
      ? largeEngineAst.medianUs / incrementalEngine.medianUs
      : 0.0;
  final double incVsPkgFull = largePkgMarkdownAst.medianUs > 0
      ? largePkgMarkdownAst.medianUs / incrementalEngine.medianUs
      : 0.0;
  stdout.writeln(
    'Incremental 1-paragraph edit ($largeLines lines): '
    'markdown_engine=${formatMicroseconds(incrementalEngine.medianUs)} '
    '(p95 ${formatMicroseconds(incrementalEngine.p95Us)}, '
    'reused ${verifiedInc.reusedBlockCount}/${verifiedInc.document.blocks.length} blocks, '
    '${incVsEngineFull.toStringAsFixed(2)}x vs markdown_engine full parse, '
    '${incVsPkgFull.toStringAsFixed(2)}x vs package:markdown full parse '
    '${formatMicroseconds(largePkgMarkdownAst.medianUs)})',
  );

  final double streamSpeedup = streamEngine.medianUs > 0
      ? streamPkgMarkdown.medianUs / streamEngine.medianUs
      : 0.0;
  stdout.writeln(
    'Streaming $chunkCount chunks (${formatBytes(streamBytes)}): '
    'markdown_engine=${formatMicroseconds(streamEngine.medianUs)}/chunk '
    '(p95 ${formatMicroseconds(streamEngine.p95Us)}, '
    '${formatMicroseconds(streamEngine.medianUs * chunkCount)} total) vs '
    'package:markdown full re-parse=${formatMicroseconds(streamPkgMarkdown.medianUs)}/chunk '
    '(p95 ${formatMicroseconds(streamPkgMarkdown.p95Us)}, '
    '${formatMicroseconds(streamPkgMarkdown.medianUs * chunkCount)} total) '
    '[${streamSpeedup.toStringAsFixed(2)}x faster]',
  );
  stdout.writeln();

  stdout.writeln('--- Adversarial Inputs ---');
  for (final _AdversarialComparison item in adversarialResults) {
    stdout.writeln(
      '  ${item.label} (${formatBytes(item.inputBytes)}): '
      'markdown_engine=${item.markdownEngine.status} '
      '(${formatMicroseconds(item.markdownEngine.elapsedUs)}) | '
      'package:markdown=${item.packageMarkdown.status} '
      '(${formatMicroseconds(item.packageMarkdown.elapsedUs)})',
    );
  }
  stdout.writeln();

  stdout.writeln('--- Specification Parity ---');
  for (final _SuiteParity s in <_SuiteParity>[
    specComparison.commonMark,
    specComparison.gfmSpec,
    specComparison.gfmExtensions,
  ]) {
    final double engPct = s.active > 0
        ? (s.markdownEnginePassed * 100.0 / s.active)
        : 0.0;
    final double pkgPct = s.active > 0
        ? (s.packageMarkdownPassed * 100.0 / s.active)
        : 0.0;
    stdout.writeln(
      '  ${s.name}: '
      'markdown_engine=${s.markdownEnginePassed}/${s.active} (${engPct.toStringAsFixed(1)}%) | '
      'package:markdown=${s.packageMarkdownPassed}/${s.active} (${pkgPct.toStringAsFixed(1)}%, '
      'errors=${s.packageMarkdownErrors})',
    );
  }
}

void _printPair(String title, LatencyStats engineStats, LatencyStats pkgStats) {
  final double ratio = engineStats.medianUs > 0
      ? pkgStats.medianUs / engineStats.medianUs
      : 0.0;
  final String comparisonLabel = ratio >= 1.0
      ? '${ratio.toStringAsFixed(2)}x faster'
      : '${(1.0 / ratio).toStringAsFixed(2)}x slower';
  stdout.writeln(
    '  $title: '
    'markdown_engine=${formatMicroseconds(engineStats.medianUs)} '
    '(p95 ${formatMicroseconds(engineStats.p95Us)}, '
    '${engineStats.throughputMbPerSec.toStringAsFixed(2)} MB/s) | '
    'package:markdown=${formatMicroseconds(pkgStats.medianUs)} '
    '(p95 ${formatMicroseconds(pkgStats.p95Us)}, '
    '${pkgStats.throughputMbPerSec.toStringAsFixed(2)} MB/s) '
    '[$comparisonLabel]',
  );
}

String? _parseStringFlag(List<String> args, String name) {
  final String prefix = '--$name=';
  for (final String arg in args) {
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
}

final class _AdversarialOutcome {
  const _AdversarialOutcome({
    required this.status,
    required this.elapsedUs,
    required this.outputLength,
  });

  final String status;
  final double elapsedUs;
  final int outputLength;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'elapsedUs': elapsedUs,
    'outputLength': outputLength,
  };
}

final class _AdversarialComparison {
  const _AdversarialComparison({
    required this.id,
    required this.label,
    required this.inputBytes,
    required this.markdownEngine,
    required this.packageMarkdown,
  });

  final String id;
  final String label;
  final int inputBytes;
  final _AdversarialOutcome markdownEngine;
  final _AdversarialOutcome packageMarkdown;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'inputBytes': inputBytes,
    'markdownEngine': markdownEngine.toJson(),
    'packageMarkdown': packageMarkdown.toJson(),
  };
}

final class _SuiteParity {
  const _SuiteParity({
    required this.name,
    required this.total,
    required this.active,
    required this.disabled,
    required this.ignored,
    required this.markdownEnginePassed,
    required this.packageMarkdownPassed,
    required this.packageMarkdownErrors,
  });

  final String name;
  final int total;
  final int active;
  final int disabled;
  final int ignored;
  final int markdownEnginePassed;
  final int packageMarkdownPassed;
  final int packageMarkdownErrors;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'total': total,
    'active': active,
    'disabled': disabled,
    'ignored': ignored,
    'markdownEnginePassed': markdownEnginePassed,
    'packageMarkdownPassed': packageMarkdownPassed,
    'packageMarkdownErrors': packageMarkdownErrors,
  };
}

final class _SpecComparisonResult {
  const _SpecComparisonResult({
    required this.commonMark,
    required this.gfmSpec,
    required this.gfmExtensions,
  });

  final _SuiteParity commonMark;
  final _SuiteParity gfmSpec;
  final _SuiteParity gfmExtensions;

  Map<String, Object?> toJson() => <String, Object?>{
    'commonmark': commonMark.toJson(),
    'gfmSpec': gfmSpec.toJson(),
    'gfmExtensions': gfmExtensions.toJson(),
  };
}
