import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as fmp;
import 'package:flutter_md/flutter_md.dart' as fmd;
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_engine_compare/compare_fixtures.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

void main() {
  final String smallDoc = buildSmallDocument();
  final String mediumDoc = buildMediumDocument();
  final LargeEditFixture largeFixture = buildLargeDocumentFixture();
  final StreamingPayloadFixture stream50Fixture = buildStreamingFixture(
    chunkCount: 50,
  );
  final StreamingPayloadFixture stream30Fixture = buildStreamingFixture(
    chunkCount: 30,
  );
  final StreamingPayloadFixture mixedStream30Fixture =
      buildMixedStreamingFixture();
  final String doc400 = buildWidget400BlockDocument();

  group('Parser Throughput (JIT VM)', () {
    test('compares markdown_engine vs flutter_md vs package:markdown', () {
      const MarkdownOptions gfmOptions = MarkdownOptions.gfm();
      const MarkdownEngine engine = MarkdownEngine(defaultOptions: gfmOptions);
      const LineSplitter lineSplitter = LineSplitter();

      final int smallBytes = utf8.encode(smallDoc).length;
      final int mediumBytes = utf8.encode(mediumDoc).length;
      final int largeBytes = utf8.encode(largeFixture.baseSource).length;
      final int streamBytes = utf8.encode(stream50Fixture.fullSource).length;

      int sink = 0;

      // Small (~1 KB) — interleaved round-robin across all 4 measurements.
      final List<LatencyStats> smallStats = measureInterleavedLatencies(
        warmupRounds: 8,
        timedRounds: 15,
        specs: <InterleavedBenchmarkSpec>[
          InterleavedBenchmarkSpec(
            label: 'markdown_engine AST',
            payloadBytes: smallBytes,
            batchIterations: 150,
            operation: () {
              sink ^= engine.parse(smallDoc).blocks.length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'markdown_engine AST+HTML',
            payloadBytes: smallBytes,
            batchIterations: 150,
            operation: () {
              sink ^= engine.parse(smallDoc).toHtml().length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'flutter_md AST',
            payloadBytes: smallBytes,
            batchIterations: 150,
            operation: () {
              sink ^= fmd.Markdown.fromString(smallDoc).blocks.length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'package:markdown AST',
            payloadBytes: smallBytes,
            batchIterations: 150,
            operation: () {
              final md.Document doc = md.Document(
                extensionSet: md.ExtensionSet.gitHubFlavored,
                encodeHtml: false,
              );
              sink ^= doc.parseLines(lineSplitter.convert(smallDoc)).length;
            },
          ),
        ],
      );

      // Medium (~25 KB) — interleaved round-robin.
      final List<LatencyStats> mediumStats = measureInterleavedLatencies(
        warmupRounds: 6,
        timedRounds: 15,
        specs: <InterleavedBenchmarkSpec>[
          InterleavedBenchmarkSpec(
            label: 'markdown_engine AST',
            payloadBytes: mediumBytes,
            batchIterations: 10,
            operation: () {
              sink ^= engine.parse(mediumDoc).blocks.length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'markdown_engine AST+HTML',
            payloadBytes: mediumBytes,
            batchIterations: 10,
            operation: () {
              sink ^= engine.parse(mediumDoc).toHtml().length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'flutter_md AST',
            payloadBytes: mediumBytes,
            batchIterations: 10,
            operation: () {
              sink ^= fmd.Markdown.fromString(mediumDoc).blocks.length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'package:markdown AST',
            payloadBytes: mediumBytes,
            batchIterations: 10,
            operation: () {
              final md.Document doc = md.Document(
                extensionSet: md.ExtensionSet.gitHubFlavored,
                encodeHtml: false,
              );
              sink ^= doc.parseLines(lineSplitter.convert(mediumDoc)).length;
            },
          ),
        ],
      );

      // Large (5,000 lines ~173 KB) — interleaved round-robin.
      final List<LatencyStats> largeStats = measureInterleavedLatencies(
        warmupRounds: 5,
        timedRounds: 13,
        specs: <InterleavedBenchmarkSpec>[
          InterleavedBenchmarkSpec(
            label: 'markdown_engine AST',
            payloadBytes: largeBytes,
            batchIterations: 2,
            operation: () {
              sink ^= engine.parse(largeFixture.baseSource).blocks.length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'markdown_engine AST+HTML',
            payloadBytes: largeBytes,
            batchIterations: 2,
            operation: () {
              sink ^= engine.parse(largeFixture.baseSource).toHtml().length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'flutter_md AST',
            payloadBytes: largeBytes,
            batchIterations: 2,
            operation: () {
              sink ^= fmd.Markdown.fromString(largeFixture.baseSource)
                  .blocks
                  .length;
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'package:markdown AST',
            payloadBytes: largeBytes,
            batchIterations: 2,
            operation: () {
              final md.Document doc = md.Document(
                extensionSet: md.ExtensionSet.gitHubFlavored,
                encodeHtml: false,
              );
              sink ^= doc
                  .parseLines(lineSplitter.convert(largeFixture.baseSource))
                  .length;
            },
          ),
        ],
      );

      // 50-chunk Streaming — interleaved round-robin.
      final StreamingMarkdownController engineStream =
          StreamingMarkdownController(engine: engine, options: gfmOptions);
      final fmd.StreamingMarkdownParser fmdStream =
          fmd.StreamingMarkdownParser();
      final int chunkCount = stream50Fixture.chunks.length;
      final List<LatencyStats> streamStats = measureInterleavedLatencies(
        warmupRounds: 6,
        timedRounds: 15,
        specs: <InterleavedBenchmarkSpec>[
          InterleavedBenchmarkSpec(
            label: 'markdown_engine stream (per chunk)',
            payloadBytes: streamBytes,
            batchIterations: 8,
            unitDivisor: chunkCount,
            throughputBytesPerUnit: streamBytes / chunkCount,
            operation: () {
              engineStream.reset();
              for (final String chunk in stream50Fixture.chunks) {
                sink ^= engineStream.append(chunk).blocks.length;
              }
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'flutter_md stream (per chunk)',
            payloadBytes: streamBytes,
            batchIterations: 8,
            unitDivisor: chunkCount,
            throughputBytesPerUnit: streamBytes / chunkCount,
            operation: () {
              fmdStream.reset();
              for (final String chunk in stream50Fixture.chunks) {
                sink ^= fmdStream.add(chunk).blocks.length;
              }
            },
          ),
          InterleavedBenchmarkSpec(
            label: 'package:markdown full-reparse stream (per chunk)',
            payloadBytes: streamBytes,
            batchIterations: 3,
            unitDivisor: chunkCount,
            throughputBytesPerUnit: streamBytes / chunkCount,
            operation: () {
              final StringBuffer buf = StringBuffer();
              for (final String chunk in stream50Fixture.chunks) {
                buf.write(chunk);
                final md.Document doc = md.Document(
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  encodeHtml: false,
                );
                sink ^= doc
                    .parseLines(lineSplitter.convert(buf.toString()))
                    .length;
              }
            },
          ),
        ],
      );

      expect(sink, isNot(-1));
      engineStream.dispose();

      final LatencyStats streamEngine = streamStats[0];
      final LatencyStats streamFlutterMd = streamStats[1];
      final LatencyStats streamPkgMarkdown = streamStats[2];

      stdout.writeln('');
      stdout.writeln(
        '=== Flutter Test JIT Parser Throughput (interleaved p50 / p95: markdown_engine vs flutter_md 0.3.1 vs package:markdown 7.3.1) ===',
      );
      _printThreeWay(
        'Small (~1 KB, ${formatBytes(smallBytes)})',
        smallStats[0],
        smallStats[1],
        smallStats[2],
        smallStats[3],
      );
      _printThreeWay(
        'Medium (~25 KB, ${formatBytes(mediumBytes)})',
        mediumStats[0],
        mediumStats[1],
        mediumStats[2],
        mediumStats[3],
      );
      _printThreeWay(
        'Large (${largeFixture.lineCount} lines, ${formatBytes(largeBytes)})',
        largeStats[0],
        largeStats[1],
        largeStats[2],
        largeStats[3],
      );
      stdout.writeln(
        '  50-chunk Streaming (${formatBytes(streamBytes)}): '
        'markdown_engine=${formatMicroseconds(streamEngine.medianUs)}/chunk '
        '(p95 ${formatMicroseconds(streamEngine.p95Us)}, '
        '${formatMicroseconds(streamEngine.medianUs * chunkCount)} total) | '
        'flutter_md=${formatMicroseconds(streamFlutterMd.medianUs)}/chunk '
        '(p95 ${formatMicroseconds(streamFlutterMd.p95Us)}, '
        '${formatMicroseconds(streamFlutterMd.medianUs * chunkCount)} total) | '
        'package:markdown=${formatMicroseconds(streamPkgMarkdown.medianUs)}/chunk '
        '(p95 ${formatMicroseconds(streamPkgMarkdown.p95Us)}, '
        '${formatMicroseconds(streamPkgMarkdown.medianUs * chunkCount)} total)',
      );
    });
  });

  group('CommonMark 0.31.2 Parity & Feature Spot Checks', () {
    test('highlights CommonMark differences across engines', () {
      const MarkdownEngine engine = MarkdownEngine(
        defaultOptions: MarkdownOptions.commonMark(),
      );
      final String specDir = resolveCorpusSpecDir();
      final List<SpecFixtureCase> cmCases = loadCommonMarkSpecCases(specDir);

      // Full 652-example check: markdown_engine vs package:markdown 7.3.1.
      int enginePassed = 0;
      int pkgPassed = 0;
      final List<int> pkgFailingExamples = <int>[];
      for (final SpecFixtureCase testCase in cmCases) {
        final String engineHtml = engine.renderToHtml(
          testCase.markdown,
          options: const MarkdownOptions.commonMark(),
        );
        if (engineHtml == testCase.expectedHtml) {
          enginePassed++;
        }
        final String pkgHtml = md.markdownToHtml(
          testCase.markdown,
          extensionSet: md.ExtensionSet.commonMark,
        );
        if (pkgHtml == testCase.expectedHtml) {
          pkgPassed++;
        } else {
          pkgFailingExamples.add(testCase.exampleNumber);
        }
      }
      expect(enginePassed, cmCases.length);
      expect(pkgPassed, lessThan(cmCases.length));

      // Spot check 1: __bold__ in CommonMark is <strong>, whereas flutter_md
      // maps double underscore to MD$Style.underline.
      const String doubleUnderscoreInput = '__bold text__\n';
      expect(
        engine.renderToHtml(doubleUnderscoreInput),
        '<p><strong>bold text</strong></p>\n',
      );
      expect(
        md.markdownToHtml(
          doubleUnderscoreInput,
          extensionSet: md.ExtensionSet.commonMark,
        ),
        '<p><strong>bold text</strong></p>\n',
      );
      final fmd.Markdown fmdUnderscore = fmd.Markdown.fromString(
        doubleUnderscoreInput,
      );
      final fmd.MD$Paragraph fmdUnderscorePara =
          fmdUnderscore.blocks.first as fmd.MD$Paragraph;
      expect(
        fmdUnderscorePara.spans.first.style.contains(fmd.MD$Style.underline),
        isTrue,
      );
      expect(
        fmdUnderscorePara.spans.first.style.contains(fmd.MD$Style.bold),
        isFalse,
      );

      // Spot check 2: Setext headings (Heading\n=======).
      const String setextInput = 'Heading One\n===========\n';
      expect(engine.renderToHtml(setextInput), '<h1>Heading One</h1>\n');
      expect(
        md.markdownToHtml(
          setextInput,
          extensionSet: md.ExtensionSet.commonMark,
        ),
        '<h1>Heading One</h1>\n',
      );
      final fmd.Markdown fmdSetext = fmd.Markdown.fromString(setextInput);
      expect(fmdSetext.blocks.first, isA<fmd.MD$Paragraph>());

      // Spot check 3: Reference-style links ([label][ref]).
      const String refLinkInput =
          '[docs][ref]\n\n[ref]: https://example.com "Title"\n';
      expect(
        engine.renderToHtml(refLinkInput),
        '<p><a href="https://example.com" title="Title">docs</a></p>\n',
      );
      expect(
        md.markdownToHtml(
          refLinkInput,
          extensionSet: md.ExtensionSet.commonMark,
        ),
        '<p><a href="https://example.com" title="Title">docs</a></p>\n',
      );
      final fmd.Markdown fmdRefLink = fmd.Markdown.fromString(refLinkInput);
      final bool fmdHasLink = fmdRefLink.blocks
          .whereType<fmd.MD$Paragraph>()
          .expand((fmd.MD$Paragraph p) => p.spans)
          .any((fmd.MD$Span s) => s.style.contains(fmd.MD$Style.link));
      expect(fmdHasLink, isFalse);

      // Spot check 4: Angle-bracket autolinks (<https://example.com>).
      const String angleAutolinkInput = '<https://example.com>\n';
      expect(
        engine.renderToHtml(angleAutolinkInput),
        '<p><a href="https://example.com">https://example.com</a></p>\n',
      );
      expect(
        md.markdownToHtml(
          angleAutolinkInput,
          extensionSet: md.ExtensionSet.commonMark,
        ),
        '<p><a href="https://example.com">https://example.com</a></p>\n',
      );
      final fmd.Markdown fmdAutolink = fmd.Markdown.fromString(
        angleAutolinkInput,
      );
      final fmd.MD$Paragraph fmdAutolinkPara =
          fmdAutolink.blocks.first as fmd.MD$Paragraph;
      expect(
        fmdAutolinkPara.spans.any(
          (fmd.MD$Span s) => s.style.contains(fmd.MD$Style.link),
        ),
        isFalse,
      );

      // Spot check 5: HTML entities & numeric character references.
      const String entitiesInput = '&copy; &#35; &#x26;\n';
      expect(engine.renderToHtml(entitiesInput), '<p>© # &amp;</p>\n');
      expect(
        md.markdownToHtml(
          entitiesInput,
          extensionSet: md.ExtensionSet.commonMark,
        ),
        '<p>© # &amp;</p>\n',
      );
      final fmd.Markdown fmdEntities = fmd.Markdown.fromString(entitiesInput);
      expect(fmdEntities.text, contains('&copy;'));

      // Spot check 6: 4-space indented code blocks & raw HTML parity.
      const String indentedCodeInput = '    final x = 1;\n';
      expect(
        engine.renderToHtml(indentedCodeInput),
        '<pre><code>final x = 1;\n</code></pre>\n',
      );
      expect(
        md.markdownToHtml(
          indentedCodeInput,
          extensionSet: md.ExtensionSet.commonMark,
        ),
        '<pre><code>final x = 1;\n</code></pre>\n',
      );
      final fmd.Markdown fmdIndented = fmd.Markdown.fromString(
        indentedCodeInput,
      );
      expect(fmdIndented.blocks.first, isA<fmd.MD$Paragraph>());

      const String rawHtmlInput = '<div>hi</div>\n';
      expect(engine.renderToHtml(rawHtmlInput), '<div>hi</div>\n');
      expect(
        md.markdownToHtml(
          rawHtmlInput,
          extensionSet: md.ExtensionSet.commonMark,
        ),
        '<div>hi</div>\n',
      );
      final fmd.Markdown fmdRawHtml = fmd.Markdown.fromString(rawHtmlInput);
      expect(fmdRawHtml.blocks.first, isA<fmd.MD$Paragraph>());
      expect(fmdRawHtml.text, contains('<div>hi</div>'));

      stdout.writeln('');
      stdout.writeln('=== CommonMark 0.31.2 Parity & Feature Spot Checks ===');
      stdout.writeln(
        '  Full CommonMark 0.31.2 suite: '
        'markdown_engine=$enginePassed/${cmCases.length} (100.0%) | '
        'package:markdown=$pkgPassed/${cmCases.length} '
        '(${(pkgPassed * 100.0 / cmCases.length).toStringAsFixed(1)}%, '
        'sample divergences: ${pkgFailingExamples.take(6).join(', ')}) | '
        'flutter_md=N/A (no HTML serializer)',
      );
      stdout.writeln(
        '  flutter_md 0.3.1 CommonMark divergences observed: '
        '`__text__` -> underline (not strong), Setext headings -> paragraph, '
        'reference links -> literal, `<url>` autolinks -> literal, '
        'HTML entities (`&copy;`, `&#35;`) -> un-decoded, '
        '4-space indented code -> paragraph, raw HTML -> literal text.',
      );
    });
  });

  group('Headless Flutter Widget Benchmarks', () {
    const int widgetWarmupRounds = 2;
    const int widgetTimedRounds = 7;

    testWidgets('1. Large 400-block document initial build & pump time', (
      WidgetTester tester,
    ) async {
      const MarkdownEngine engine = MarkdownEngine(
        defaultOptions: MarkdownOptions.gfm(),
      );
      final MarkdownDocument preParsedEngineDoc = engine.parse(doc400);
      expect(preParsedEngineDoc.blocks.length, greaterThanOrEqualTo(400));

      final fmd.Markdown preParsedFmdDoc = fmd.Markdown.fromString(doc400);
      const MarkdownThemeData engineLight = MarkdownThemeData.light();
      final fmd.MarkdownThemeData fmdLight = fmd.MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 16.0, color: Color(0xFF0F172A)),
        surfaceColor: const Color(0xFFF1F5F9),
      );
      final fmp.MarkdownStyleSheet fmpLight = _buildFmpStyleSheet(
        Brightness.light,
      );

      final List<Widget Function(int round)> builders =
          <Widget Function(int round)>[
            (int round) => MarkdownView(
              doc400,
              key: ValueKey<String>('me_cold_$round'),
              engine: engine,
              theme: engineLight,
              selectable: false,
            ),
            (int round) => MarkdownView.document(
              key: ValueKey<String>('me_doc_$round'),
              document: preParsedEngineDoc,
              theme: engineLight,
              selectable: false,
            ),
            (int round) => MarkdownView(
              doc400,
              key: ValueKey<String>('me_cold_sel_$round'),
              engine: engine,
              theme: engineLight,
              selectable: true,
            ),
            (int round) => MarkdownView.document(
              key: ValueKey<String>('me_doc_sel_$round'),
              document: preParsedEngineDoc,
              theme: engineLight,
              selectable: true,
            ),
            (int round) => SingleChildScrollView(
              key: ValueKey<String>('fmd_cold_$round'),
              child: fmd.MarkdownWidget(
                markdown: fmd.Markdown.fromString(doc400),
                theme: fmdLight,
              ),
            ),
            (int round) => SingleChildScrollView(
              key: ValueKey<String>('fmd_doc_$round'),
              child: fmd.MarkdownWidget(
                markdown: preParsedFmdDoc,
                theme: fmdLight,
              ),
            ),
            (int round) => fmp.Markdown(
              key: ValueKey<String>('fmp_cold_$round'),
              data: doc400,
              styleSheet: fmpLight,
            ),
          ];

      final List<List<double>> samplesByEngine = List<List<double>>.generate(
        builders.length,
        (_) => <double>[],
      );

      await _runInterleavedRounds(
        warmupRounds: widgetWarmupRounds,
        timedRounds: widgetTimedRounds,
        participantCount: builders.length,
        runParticipant: (int idx, int round, bool isTimed) async {
          final int keySeed = isTimed ? round : -1 - round;
          final Stopwatch sw = Stopwatch()..start();
          await tester.pumpWidget(_benchShell(child: builders[idx](keySeed)));
          sw.stop();
          if (isTimed) {
            samplesByEngine[idx].add(sw.elapsedMicroseconds / 1000.0);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );

      final SampleSummary engineCold = summarizeSamples(samplesByEngine[0]);
      final SampleSummary enginePreParsed = summarizeSamples(
        samplesByEngine[1],
      );
      final SampleSummary engineColdSel = summarizeSamples(samplesByEngine[2]);
      final SampleSummary enginePreParsedSel = summarizeSamples(
        samplesByEngine[3],
      );
      final SampleSummary fmdCold = summarizeSamples(samplesByEngine[4]);
      final SampleSummary fmdPreParsed = summarizeSamples(samplesByEngine[5]);
      final SampleSummary fmpCold = summarizeSamples(samplesByEngine[6]);

      stdout.writeln('');
      stdout.writeln(
        '=== Widget Benchmark 1: 400+ Block Initial Build & Pump '
        '(${preParsedEngineDoc.blocks.length} blocks, 800x600 viewport, '
        '$widgetWarmupRounds warmup + $widgetTimedRounds interleaved rounds) ===',
      );
      stdout.writeln(
        '  B1 MarkdownView(data) (parse + lazy sliver, selectable: false, apples-to-apples): '
        '${formatMsSummary(engineCold)} (iqr=${engineCold.iqr.toStringAsFixed(2)} ms)',
      );
      stdout.writeln(
        '  B1 MarkdownView.document (pre-parsed lazy sliver, selectable: false, apples-to-apples): '
        '${formatMsSummary(enginePreParsed)} '
        '(iqr=${enginePreParsed.iqr.toStringAsFixed(2)} ms)',
      );
      stdout.writeln(
        '  B1-Selectable MarkdownView(data) (production default, selectable: true): '
        '${formatMsSummary(engineColdSel)} (iqr=${engineColdSel.iqr.toStringAsFixed(2)} ms)',
      );
      stdout.writeln(
        '  B1-Selectable MarkdownView.document (production default, selectable: true): '
        '${formatMsSummary(enginePreParsedSel)} '
        '(iqr=${enginePreParsedSel.iqr.toStringAsFixed(2)} ms)',
      );
      stdout.writeln(
        '  flutter_md (Markdown.fromString + MarkdownWidget, selectable: false): '
        '${formatMsSummary(fmdCold)} '
        '(pre-parsed widget only: ${formatMsSummary(fmdPreParsed)})',
      );
      stdout.writeln(
        '  flutter_markdown_plus Markdown (parse + eager ListView, selectable: false): '
        '${formatMsSummary(fmpCold)} (iqr=${fmpCold.iqr.toStringAsFixed(2)} ms)',
      );
    });

    testWidgets('2. Light <-> Dark theme toggle time + re-parse count', (
      WidgetTester tester,
    ) async {
      const int settleTogglesPerMount = 2;
      const int timedTogglesPerRound = 4;

      const MarkdownThemeData engineLight = MarkdownThemeData.light();
      const MarkdownThemeData engineDark = MarkdownThemeData.dark();
      final fmd.Markdown cachedFmd = fmd.Markdown.fromString(doc400);
      final fmd.MarkdownThemeData fmdLight = fmd.MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 16.0, color: Color(0xFF0F172A)),
        surfaceColor: const Color(0xFFF1F5F9),
      );
      final fmd.MarkdownThemeData fmdDark = fmd.MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 16.0, color: Color(0xFFE2E8F0)),
        surfaceColor: const Color(0xFF1E293B),
      );
      final fmp.MarkdownStyleSheet fmpLight = _buildFmpStyleSheet(
        Brightness.light,
      );
      final fmp.MarkdownStyleSheet fmpDark = _buildFmpStyleSheet(
        Brightness.dark,
      );

      final List<double> engineNonSelSamplesMs = <double>[];
      final List<double> engineSelSamplesMs = <double>[];
      final List<double> fmdSamplesMs = <double>[];
      final List<double> fmpSamplesMs = <double>[];
      int engineNonSelReparsesTotal = 0;
      int engineSelReparsesTotal = 0;
      int fmpReparsesTotal = 0;

      await _runInterleavedRounds(
        warmupRounds: widgetWarmupRounds,
        timedRounds: widgetTimedRounds,
        participantCount: 4,
        runParticipant: (int idx, int round, bool isTimed) async {
          if (idx == 0 || idx == 1) {
            final bool selectable = idx == 1;
            final MarkdownController engineController = MarkdownController();
            final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);
            await tester.pumpWidget(
              _benchShell(
                child: ValueListenableBuilder<bool>(
                  valueListenable: darkMode,
                  builder: (BuildContext context, bool isDark, _) =>
                      MarkdownView(
                        doc400,
                        controller: engineController,
                        theme: isDark ? engineDark : engineLight,
                        selectable: selectable,
                      ),
                ),
              ),
            );
            try {
              expect(engineController.parseCount, 1);
              final List<double> roundSamples = await _measureTogglesInPlace(
                tester: tester,
                notifier: darkMode,
                settleToggles: settleTogglesPerMount,
                timedToggles: timedTogglesPerRound,
              );
              final int reparses = engineController.parseCount - 1;
              expect(reparses, 0);
              if (isTimed) {
                if (selectable) {
                  engineSelSamplesMs.addAll(roundSamples);
                  engineSelReparsesTotal += reparses;
                } else {
                  engineNonSelSamplesMs.addAll(roundSamples);
                  engineNonSelReparsesTotal += reparses;
                }
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              engineController.dispose();
              darkMode.dispose();
            }
          } else if (idx == 2) {
            final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);
            await tester.pumpWidget(
              _benchShell(
                child: ValueListenableBuilder<bool>(
                  valueListenable: darkMode,
                  builder: (BuildContext context, bool isDark, _) =>
                      SingleChildScrollView(
                        child: fmd.MarkdownWidget(
                          markdown: cachedFmd,
                          theme: isDark ? fmdDark : fmdLight,
                        ),
                      ),
                ),
              ),
            );
            try {
              final List<double> roundSamples = await _measureTogglesInPlace(
                tester: tester,
                notifier: darkMode,
                settleToggles: settleTogglesPerMount,
                timedToggles: timedTogglesPerRound,
              );
              if (isTimed) {
                fmdSamplesMs.addAll(roundSamples);
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              darkMode.dispose();
            }
          } else {
            final _CountingH1Builder fmpParseCounter = _CountingH1Builder();
            final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);
            await tester.pumpWidget(
              _benchShell(
                child: ValueListenableBuilder<bool>(
                  valueListenable: darkMode,
                  builder: (BuildContext context, bool isDark, _) =>
                      fmp.Markdown(
                        data: doc400,
                        styleSheet: isDark ? fmpDark : fmpLight,
                        builders: <String, fmp.MarkdownElementBuilder>{
                          'h1': fmpParseCounter,
                        },
                      ),
                ),
              ),
            );
            try {
              expect(fmpParseCounter.count, 1);
              final List<double> roundSamples = await _measureTogglesInPlace(
                tester: tester,
                notifier: darkMode,
                settleToggles: settleTogglesPerMount,
                timedToggles: timedTogglesPerRound,
              );
              final int reparses = fmpParseCounter.count - 1;
              expect(reparses, settleTogglesPerMount + timedTogglesPerRound);
              if (isTimed) {
                fmpSamplesMs.addAll(roundSamples);
                fmpReparsesTotal += reparses;
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              darkMode.dispose();
            }
          }
        },
      );

      final SampleSummary engineNonSelSummary = summarizeSamples(
        engineNonSelSamplesMs,
      );
      final SampleSummary engineSelSummary = summarizeSamples(
        engineSelSamplesMs,
      );
      final SampleSummary fmdSummary = summarizeSamples(fmdSamplesMs);
      final SampleSummary fmpSummary = summarizeSamples(fmpSamplesMs);

      stdout.writeln('');
      stdout.writeln(
        '=== Widget Benchmark 2: Light <-> Dark Theme Toggle '
        '($widgetWarmupRounds warmup + $widgetTimedRounds interleaved rounds x '
        '$timedTogglesPerRound timed toggles on 403-block doc) ===',
      );
      stdout.writeln(
        '  B2 MarkdownView (selectable: false, apples-to-apples): '
        '${engineNonSelSummary.median.toStringAsFixed(2)} ms/toggle '
        '(p95=${engineNonSelSummary.p95.toStringAsFixed(2)} ms, '
        'iqr=${engineNonSelSummary.iqr.toStringAsFixed(2)} ms) | '
        're-parses=$engineNonSelReparsesTotal',
      );
      stdout.writeln(
        '  B2-Selectable MarkdownView (production default, selectable: true): '
        '${engineSelSummary.median.toStringAsFixed(2)} ms/toggle '
        '(p95=${engineSelSummary.p95.toStringAsFixed(2)} ms, '
        'iqr=${engineSelSummary.iqr.toStringAsFixed(2)} ms) | '
        're-parses=$engineSelReparsesTotal',
      );
      stdout.writeln(
        '  flutter_md (cached Markdown, selectable: false): '
        '${fmdSummary.median.toStringAsFixed(2)} ms/toggle '
        '(p95=${fmdSummary.p95.toStringAsFixed(2)} ms, '
        'iqr=${fmdSummary.iqr.toStringAsFixed(2)} ms) | '
        're-parses=0 (caller-cached AST)',
      );
      stdout.writeln(
        '  flutter_markdown_plus Markdown (selectable: false): '
        '${fmpSummary.median.toStringAsFixed(2)} ms/toggle '
        '(p95=${fmpSummary.p95.toStringAsFixed(2)} ms, '
        'iqr=${fmpSummary.iqr.toStringAsFixed(2)} ms) | '
        're-parses=$fmpReparsesTotal (full re-parse on every toggle)',
      );
    });

    testWidgets('3. Live 30-chunk LLM streaming rebuild cost', (
      WidgetTester tester,
    ) async {
      final List<String> chunks = stream30Fixture.chunks;
      expect(chunks.length, 30);

      const MarkdownOptions gfmOptions = MarkdownOptions.gfm();
      const MarkdownThemeData engineLight = MarkdownThemeData.light();
      final fmd.MarkdownThemeData fmdLight = fmd.MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 16.0, color: Color(0xFF0F172A)),
        surfaceColor: const Color(0xFFF1F5F9),
      );
      final fmp.MarkdownStyleSheet fmpLight = _buildFmpStyleSheet(
        Brightness.light,
      );

      final List<double> engineNonSelMs = <double>[];
      final List<double> engineNonSelFinishMs = <double>[];
      final List<double> engineSelMs = <double>[];
      final List<double> engineSelFinishMs = <double>[];
      final List<double> fmdMs = <double>[];
      final List<double> fmpMs = <double>[];

      await _runInterleavedRounds(
        warmupRounds: widgetWarmupRounds,
        timedRounds: widgetTimedRounds,
        participantCount: 4,
        runParticipant: (int idx, int round, bool isTimed) async {
          if (idx == 0 || idx == 1) {
            final bool selectable = idx == 1;
            final ({double activeMs, double finishMs}) res =
                await _runMarkdownViewStreamSession(
                  tester: tester,
                  chunks: chunks,
                  options: gfmOptions,
                  theme: engineLight,
                  delegates: const MarkdownBuilderDelegates(),
                  selectable: selectable,
                );
            if (isTimed) {
              if (selectable) {
                engineSelMs.add(res.activeMs);
                engineSelFinishMs.add(res.finishMs);
              } else {
                engineNonSelMs.add(res.activeMs);
                engineNonSelFinishMs.add(res.finishMs);
              }
            }
          } else if (idx == 2) {
            final double activeMs = await _runFmdStreamSession(
              tester: tester,
              chunks: chunks,
              theme: fmdLight,
            );
            if (isTimed) {
              fmdMs.add(activeMs);
            }
          } else {
            final double activeMs = await _runFmpStreamSession(
              tester: tester,
              chunks: chunks,
              styleSheet: fmpLight,
            );
            if (isTimed) {
              fmpMs.add(activeMs);
            }
          }
        },
      );

      final SampleSummary engineNonSel = summarizeSamples(engineNonSelMs);
      final SampleSummary engineNonSelFinish = summarizeSamples(
        engineNonSelFinishMs,
      );
      final SampleSummary engineSel = summarizeSamples(engineSelMs);
      final SampleSummary engineSelFinish = summarizeSamples(engineSelFinishMs);
      final SampleSummary fmdSummary = summarizeSamples(fmdMs);
      final SampleSummary fmpSummary = summarizeSamples(fmpMs);

      stdout.writeln('');
      stdout.writeln(
        '=== Widget Benchmark 3: Live 30-Chunk Prose LLM Streaming '
        '(31 matched pumps, $widgetWarmupRounds warmup + $widgetTimedRounds interleaved rounds) ===',
      );
      stdout.writeln(
        '  B3 MarkdownView.streaming (selectable: false, apples-to-apples): '
        '${formatMsSummary(engineNonSel)} total '
        '(${(engineNonSel.median / chunks.length).toStringAsFixed(2)} ms/chunk) | '
        '+ finish() delta: ${formatMsSummary(engineNonSelFinish)}',
      );
      stdout.writeln(
        '  B3-Selectable (production default, selectable: true): '
        '${formatMsSummary(engineSel)} total '
        '(${(engineSel.median / chunks.length).toStringAsFixed(2)} ms/chunk) | '
        '+ finish() delta: ${formatMsSummary(engineSelFinish)}',
      );
      stdout.writeln(
        '  flutter_md StreamingMarkdownParser + MarkdownWidget (selectable: false): '
        '${formatMsSummary(fmdSummary)} total '
        '(${(fmdSummary.median / chunks.length).toStringAsFixed(2)} ms/chunk)',
      );
      stdout.writeln(
        '  flutter_markdown_plus Markdown (selectable: false, full re-parse/rebuild): '
        '${formatMsSummary(fmpSummary)} total '
        '(${(fmpSummary.median / chunks.length).toStringAsFixed(2)} ms/chunk)',
      );
    });

    testWidgets(
      '4a. Live mixed-content 30-chunk streaming — Apples-to-Apples Core/Text Mode',
      (WidgetTester tester) async {
        MarkdownBuiltInRenderers.clearCaches();
        addTearDown(MarkdownBuiltInRenderers.clearCaches);

        final List<String> chunks = mixedStream30Fixture.chunks;
        expect(chunks.length, 30);

        const MarkdownOptions gfmOptions = MarkdownOptions.gfm();
        const MarkdownOptions extendedOptions = MarkdownOptions.extended();
        const MarkdownBuilderDelegates disabledBuiltIns =
            MarkdownBuilderDelegates(
              enableBuiltInMath: false,
              enableBuiltInMermaid: false,
            );
        const MarkdownThemeData engineLight = MarkdownThemeData.light();
        final fmd.MarkdownThemeData fmdLight = fmd.MarkdownThemeData(
          textStyle: const TextStyle(fontSize: 16.0, color: Color(0xFF0F172A)),
          surfaceColor: const Color(0xFFF1F5F9),
        );
        final fmp.MarkdownStyleSheet fmpLight = _buildFmpStyleSheet(
          Brightness.light,
        );

        final List<double> engineGfmMs = <double>[];
        final List<double> engineGfmFinishMs = <double>[];
        final List<double> engineHybridMs = <double>[];
        final List<double> engineHybridFinishMs = <double>[];
        final List<double> fmdMs = <double>[];
        final List<double> fmpMs = <double>[];

        await _runInterleavedRounds(
          warmupRounds: widgetWarmupRounds,
          timedRounds: widgetTimedRounds,
          participantCount: 4,
          runParticipant: (int idx, int round, bool isTimed) async {
            if (idx == 0 || idx == 1) {
              final bool isHybrid = idx == 1;
              final ({double activeMs, double finishMs}) res =
                  await _runMarkdownViewStreamSession(
                    tester: tester,
                    chunks: chunks,
                    options: isHybrid ? extendedOptions : gfmOptions,
                    theme: engineLight,
                    delegates: disabledBuiltIns,
                    selectable: false,
                  );
              if (isTimed) {
                if (isHybrid) {
                  engineHybridMs.add(res.activeMs);
                  engineHybridFinishMs.add(res.finishMs);
                } else {
                  engineGfmMs.add(res.activeMs);
                  engineGfmFinishMs.add(res.finishMs);
                }
              }
            } else if (idx == 2) {
              final double activeMs = await _runFmdStreamSession(
                tester: tester,
                chunks: chunks,
                theme: fmdLight,
              );
              if (isTimed) {
                fmdMs.add(activeMs);
              }
            } else {
              final double activeMs = await _runFmpStreamSession(
                tester: tester,
                chunks: chunks,
                styleSheet: fmpLight,
              );
              if (isTimed) {
                fmpMs.add(activeMs);
              }
            }
          },
        );

        expect(MarkdownBuiltInRenderers.mathLayoutCount, 0);
        expect(MarkdownBuiltInRenderers.mermaidRenderCount, 0);

        final SampleSummary gfmSummary = summarizeSamples(engineGfmMs);
        final SampleSummary gfmFinish = summarizeSamples(engineGfmFinishMs);
        final SampleSummary hybridSummary = summarizeSamples(engineHybridMs);
        final SampleSummary hybridFinish = summarizeSamples(
          engineHybridFinishMs,
        );
        final SampleSummary fmdSummary = summarizeSamples(fmdMs);
        final SampleSummary fmpSummary = summarizeSamples(fmpMs);

        stdout.writeln('');
        stdout.writeln(
          '=== Widget Benchmark 4a: Live Mixed-Content 30-Chunk Streaming '
          '(Apples-to-Apples Core/Text Mode, 31 matched pumps, '
          '$widgetWarmupRounds warmup + $widgetTimedRounds interleaved rounds) ===',
        );
        stdout.writeln(
          '  B4a MarkdownView.streaming (GFM, built-in math/Mermaid off, selectable: false): '
          '${formatMsSummary(gfmSummary)} total '
          '(${(gfmSummary.median / chunks.length).toStringAsFixed(2)} ms/chunk) | '
          '+ finish() delta: ${formatMsSummary(gfmFinish)}',
        );
        stdout.writeln(
          '  B4a-Hybrid MarkdownView.streaming (extended alerts + raw math fallback, '
          'built-in math/Mermaid off, selectable: false): '
          '${formatMsSummary(hybridSummary)} total '
          '(${(hybridSummary.median / chunks.length).toStringAsFixed(2)} ms/chunk) | '
          '+ finish() delta: ${formatMsSummary(hybridFinish)}',
        );
        stdout.writeln(
          '  flutter_md StreamingMarkdownParser + MarkdownWidget (raw blocks, selectable: false): '
          '${formatMsSummary(fmdSummary)} total '
          '(${(fmdSummary.median / chunks.length).toStringAsFixed(2)} ms/chunk)',
        );
        stdout.writeln(
          '  flutter_markdown_plus Markdown (raw blocks, selectable: false, full re-parse/rebuild): '
          '${formatMsSummary(fmpSummary)} total '
          '(${(fmpSummary.median / chunks.length).toStringAsFixed(2)} ms/chunk)',
        );
      },
    );

    testWidgets(
      '4b. Live mixed-content 30-chunk streaming — Rich Out-of-the-Box Mode (TexMath + Mermaid + Alerts)',
      (WidgetTester tester) async {
        await tester.runAsync(MarkdownBuiltInRenderers.warmUp);
        addTearDown(() async {
          MarkdownBuiltInRenderers.clearCaches();
          MarkdownBuiltInRenderers.resetCacheDefaults();
          await MarkdownBuiltInRenderers.dispose();
        });

        final List<String> chunks = mixedStream30Fixture.chunks;
        expect(chunks.length, 30);

        const MarkdownOptions extendedOptions = MarkdownOptions.extended();
        const MarkdownEngine engine = MarkdownEngine(
          defaultOptions: extendedOptions,
        );
        const MarkdownThemeData engineLight = MarkdownThemeData.light();

        // Verified warmup session: prove settled TexMath & VectorGraphic Mermaid
        // render objects stay identical across trailing prose chunks.
        final StreamingMarkdownController verifyStream =
            StreamingMarkdownController(
              engine: engine,
              options: extendedOptions,
            );
        await tester.pumpWidget(
          _benchShell(
            child: MarkdownView.streaming(
              controller: verifyStream,
              theme: engineLight,
            ),
          ),
        );
        MarkdownBuiltInRenderers.clearCaches();
        verifyStream.reset();
        await tester.pump();

        final Finder mathFinder = find.byWidgetPredicate(
          (Widget w) => w.runtimeType.toString() == 'TexMath',
        );
        final Finder mermaidFinder = find.byWidgetPredicate(
          (Widget w) => w.runtimeType.toString() == 'VectorGraphic',
        );
        final Finder canvasFinder = find.byWidgetPredicate(
          (Widget w) =>
              w.runtimeType.toString() == 'MarkdownStreamingCanvasLeaf',
        );
        RenderObject? settledMathRender;
        RenderObject? settledMermaidRender;
        for (int i = 0; i < chunks.length; i++) {
          verifyStream.append(chunks[i]);
          await tester.pump();
          if (i == 7) {
            expect(verifyStream.settledPrefixBlockCount, 4);
            expect(find.byType(SliverMarkdownDocument), findsOneWidget);
            expect(canvasFinder, findsOneWidget);
            expect(mathFinder, findsOneWidget);
            expect(mermaidFinder, findsOneWidget);
            settledMathRender = tester.renderObject(mathFinder);
            settledMermaidRender = tester.renderObject(mermaidFinder);
          } else if (i == chunks.length - 1) {
            expect(find.byType(SliverMarkdownDocument), findsOneWidget);
            expect(canvasFinder, findsOneWidget);
            expect(
              identical(tester.renderObject(mathFinder), settledMathRender),
              isTrue,
            );
            expect(
              identical(
                tester.renderObject(mermaidFinder),
                settledMermaidRender,
              ),
              isTrue,
            );
          }
        }
        verifyStream.finish();
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        verifyStream.dispose();

        // Second warmup round covering both Cold and Warm paths, leaving caches
        // populated before timed rounds start.
        await _runMarkdownViewStreamSession(
          tester: tester,
          chunks: chunks,
          options: extendedOptions,
          theme: engineLight,
          delegates: const MarkdownBuilderDelegates(),
          selectable: true,
          beforeSession: MarkdownBuiltInRenderers.clearCaches,
        );
        await _runMarkdownViewStreamSession(
          tester: tester,
          chunks: chunks,
          options: extendedOptions,
          theme: engineLight,
          delegates: const MarkdownBuilderDelegates(),
          selectable: true,
        );

        final List<double> coldActiveMs = <double>[];
        final List<double> coldFinishMs = <double>[];
        final List<double> warmActiveMs = <double>[];
        final List<double> warmFinishMs = <double>[];

        int coldMathLayouts = 0;
        int coldMermaidRenders = 0;
        int warmMathHits = 0;
        int warmMermaidHits = 0;

        await _runInterleavedRounds(
          warmupRounds: 0,
          timedRounds: widgetTimedRounds,
          participantCount: 2,
          runParticipant: (int idx, int round, bool isTimed) async {
            if (idx == 0) {
              final ({double activeMs, double finishMs}) res =
                  await _runMarkdownViewStreamSession(
                    tester: tester,
                    chunks: chunks,
                    options: extendedOptions,
                    theme: engineLight,
                    delegates: const MarkdownBuilderDelegates(),
                    selectable: true,
                    beforeSession: MarkdownBuiltInRenderers.clearCaches,
                  );
              coldMathLayouts = MarkdownBuiltInRenderers.mathLayoutCount;
              coldMermaidRenders = MarkdownBuiltInRenderers.mermaidRenderCount;
              expect(coldMathLayouts, greaterThanOrEqualTo(1));
              expect(coldMermaidRenders, greaterThanOrEqualTo(1));
              coldActiveMs.add(res.activeMs);
              coldFinishMs.add(res.finishMs);
            } else {
              late int layoutsBefore;
              late int rendersBefore;
              late int mathHitsBefore;
              late int mermaidHitsBefore;
              final ({double activeMs, double finishMs})
              res = await _runMarkdownViewStreamSession(
                tester: tester,
                chunks: chunks,
                options: extendedOptions,
                theme: engineLight,
                delegates: const MarkdownBuilderDelegates(),
                selectable: true,
                beforeSession: () {
                  layoutsBefore = MarkdownBuiltInRenderers.mathLayoutCount;
                  rendersBefore = MarkdownBuiltInRenderers.mermaidRenderCount;
                  mathHitsBefore = MarkdownBuiltInRenderers.mathCacheHitCount;
                  mermaidHitsBefore =
                      MarkdownBuiltInRenderers.mermaidCacheHitCount;
                },
              );
              final int newLayouts =
                  MarkdownBuiltInRenderers.mathLayoutCount - layoutsBefore;
              final int newRenders =
                  MarkdownBuiltInRenderers.mermaidRenderCount - rendersBefore;
              warmMathHits =
                  MarkdownBuiltInRenderers.mathCacheHitCount - mathHitsBefore;
              warmMermaidHits =
                  MarkdownBuiltInRenderers.mermaidCacheHitCount -
                  mermaidHitsBefore;
              expect(newLayouts, 0);
              expect(newRenders, 0);
              expect(warmMathHits, greaterThanOrEqualTo(1));
              expect(warmMermaidHits, greaterThanOrEqualTo(1));
              warmActiveMs.add(res.activeMs);
              warmFinishMs.add(res.finishMs);
            }
          },
        );

        final SampleSummary coldActive = summarizeSamples(coldActiveMs);
        final SampleSummary coldFinish = summarizeSamples(coldFinishMs);
        final SampleSummary warmActive = summarizeSamples(warmActiveMs);
        final SampleSummary warmFinish = summarizeSamples(warmFinishMs);

        stdout.writeln('');
        stdout.writeln(
          '=== Widget Benchmark 4b: Live Mixed-Content 30-Chunk Streaming '
          '(Rich Out-of-the-Box: Native TexMath + VectorGraphic Mermaid + Alerts, '
          'selectable: true, 31 matched active pumps, '
          '$widgetWarmupRounds warmup + $widgetTimedRounds interleaved rounds) ===',
        );
        stdout.writeln(
          '  Note: flutter_md and flutter_markdown_plus lack native TeX math/Mermaid '
          'rendering (competitor raw-text baseline is Widget Benchmark 4a).',
        );
        stdout.writeln(
          '  B4b-Cold (Cold LRU Cache): ${formatMsSummary(coldActive)} total '
          '(${(coldActive.median / chunks.length).toStringAsFixed(2)} ms/chunk) | '
          '+ finish() delta: ${formatMsSummary(coldFinish)} | '
          'mathLayouts=$coldMathLayouts, mermaidRenders=$coldMermaidRenders',
        );
        stdout.writeln(
          '  B4b-Warm (Warm LRU Cache): ${formatMsSummary(warmActive)} total '
          '(${(warmActive.median / chunks.length).toStringAsFixed(2)} ms/chunk) | '
          '+ finish() delta: ${formatMsSummary(warmFinish)} | '
          'mathHits=$warmMathHits, mermaidHits=$warmMermaidHits, '
          'newLayouts=0, newRenders=0',
        );
      },
    );
  });
}

Widget _benchShell({required Widget child}) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 800, height: 600, child: child)),
  );
}

fmp.MarkdownStyleSheet _buildFmpStyleSheet(Brightness brightness) {
  final ThemeData baseTheme = brightness == Brightness.dark
      ? ThemeData.dark()
      : ThemeData.light();
  final Color fg = brightness == Brightness.dark
      ? const Color(0xFFE2E8F0)
      : const Color(0xFF0F172A);
  final ThemeData sizedTheme = baseTheme.copyWith(
    textTheme: baseTheme.textTheme.copyWith(
      bodyMedium: TextStyle(fontSize: 16.0, color: fg),
      bodyLarge: TextStyle(fontSize: 18.0, color: fg),
      headlineSmall: TextStyle(fontSize: 24.0, color: fg),
      titleLarge: TextStyle(fontSize: 20.0, color: fg),
      titleMedium: TextStyle(fontSize: 18.0, color: fg),
    ),
  );
  return fmp.MarkdownStyleSheet.fromTheme(sizedTheme);
}

Future<void> _runInterleavedRounds({
  required int warmupRounds,
  required int timedRounds,
  required int participantCount,
  required Future<void> Function(int participantIndex, int round, bool isTimed)
  runParticipant,
}) async {
  for (int w = 0; w < warmupRounds; w++) {
    for (final int idx in interleaveRoundIndices(participantCount, w)) {
      await runParticipant(idx, w, false);
    }
  }
  for (int r = 0; r < timedRounds; r++) {
    for (final int idx in interleaveRoundIndices(
      participantCount,
      warmupRounds + r,
    )) {
      await runParticipant(idx, r, true);
    }
  }
}

Future<List<double>> _measureTogglesInPlace({
  required WidgetTester tester,
  required ValueNotifier<bool> notifier,
  required int settleToggles,
  required int timedToggles,
}) async {
  for (int w = 0; w < settleToggles; w++) {
    notifier.value = !notifier.value;
    await tester.pump();
  }

  final List<double> samplesMs = <double>[];
  for (int i = 0; i < timedToggles; i++) {
    final Stopwatch sw = Stopwatch()..start();
    notifier.value = !notifier.value;
    await tester.pump();
    sw.stop();
    samplesMs.add(sw.elapsedMicroseconds / 1000.0);
  }
  return samplesMs;
}

Future<({double activeMs, double finishMs})> _runMarkdownViewStreamSession({
  required WidgetTester tester,
  required List<String> chunks,
  required MarkdownOptions options,
  required MarkdownThemeData theme,
  required MarkdownBuilderDelegates delegates,
  required bool selectable,
  void Function()? beforeSession,
}) async {
  final MarkdownEngine engine = MarkdownEngine(defaultOptions: options);
  final StreamingMarkdownController controller = StreamingMarkdownController(
    engine: engine,
    options: options,
  );
  await tester.pumpWidget(
    _benchShell(
      child: MarkdownView.streaming(
        controller: controller,
        theme: theme,
        delegates: delegates,
        selectable: selectable,
      ),
    ),
  );
  try {
    beforeSession?.call();
    final Stopwatch activeSw = Stopwatch()..start();
    controller.reset();
    await tester.pump();
    for (final String chunk in chunks) {
      controller.append(chunk);
      await tester.pump();
    }
    activeSw.stop();

    final Stopwatch finishSw = Stopwatch()..start();
    controller.finish();
    await tester.pump();
    finishSw.stop();

    return (
      activeMs: activeSw.elapsedMicroseconds / 1000.0,
      finishMs: finishSw.elapsedMicroseconds / 1000.0,
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }
}

Future<double> _runFmdStreamSession({
  required WidgetTester tester,
  required List<String> chunks,
  required fmd.MarkdownThemeData theme,
}) async {
  final fmd.StreamingMarkdownParser parser = fmd.StreamingMarkdownParser();
  final ValueNotifier<fmd.Markdown> docNotifier = ValueNotifier<fmd.Markdown>(
    const fmd.Markdown.empty(),
  );
  await tester.pumpWidget(
    _benchShell(
      child: ValueListenableBuilder<fmd.Markdown>(
        valueListenable: docNotifier,
        builder: (BuildContext context, fmd.Markdown doc, _) =>
            SingleChildScrollView(
              child: fmd.MarkdownWidget(markdown: doc, theme: theme),
            ),
      ),
    ),
  );
  try {
    final Stopwatch sw = Stopwatch()..start();
    parser.reset();
    docNotifier.value = const fmd.Markdown.empty();
    await tester.pump();
    for (final String chunk in chunks) {
      docNotifier.value = parser.add(chunk);
      await tester.pump();
    }
    sw.stop();
    return sw.elapsedMicroseconds / 1000.0;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    docNotifier.dispose();
  }
}

Future<double> _runFmpStreamSession({
  required WidgetTester tester,
  required List<String> chunks,
  required fmp.MarkdownStyleSheet styleSheet,
}) async {
  final ValueNotifier<String> sourceNotifier = ValueNotifier<String>('');
  await tester.pumpWidget(
    _benchShell(
      child: ValueListenableBuilder<String>(
        valueListenable: sourceNotifier,
        builder: (BuildContext context, String data, _) =>
            fmp.Markdown(data: data, styleSheet: styleSheet),
      ),
    ),
  );
  try {
    final Stopwatch sw = Stopwatch()..start();
    final StringBuffer acc = StringBuffer();
    sourceNotifier.value = '';
    await tester.pump();
    for (final String chunk in chunks) {
      acc.write(chunk);
      sourceNotifier.value = acc.toString();
      await tester.pump();
    }
    sw.stop();
    return sw.elapsedMicroseconds / 1000.0;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    sourceNotifier.dispose();
  }
}

void _printThreeWay(
  String title,
  LatencyStats engineAst,
  LatencyStats engineHtml,
  LatencyStats fmdAst,
  LatencyStats pkgMarkdownAst,
) {
  stdout.writeln(
    '  $title: '
    'markdown_engine AST=${formatMicroseconds(engineAst.medianUs)} '
    '(p95 ${formatMicroseconds(engineAst.p95Us)}, '
    '${engineAst.throughputMbPerSec.toStringAsFixed(2)} MB/s), '
    'AST+HTML=${formatMicroseconds(engineHtml.medianUs)} '
    '(p95 ${formatMicroseconds(engineHtml.p95Us)}) | '
    'flutter_md AST=${formatMicroseconds(fmdAst.medianUs)} '
    '(p95 ${formatMicroseconds(fmdAst.p95Us)}, '
    '${fmdAst.throughputMbPerSec.toStringAsFixed(2)} MB/s) | '
    'package:markdown AST=${formatMicroseconds(pkgMarkdownAst.medianUs)} '
    '(p95 ${formatMicroseconds(pkgMarkdownAst.p95Us)}, '
    '${pkgMarkdownAst.throughputMbPerSec.toStringAsFixed(2)} MB/s)',
  );
}

final class _CountingH1Builder extends fmp.MarkdownElementBuilder {
  int count = 0;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    count++;
    return null;
  }
}
