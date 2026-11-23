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

      // Small (~1 KB)
      final LatencyStats smallEngineAst = measureLatency(
        label: 'markdown_engine AST',
        payloadBytes: smallBytes,
        warmupSamples: 8,
        samples: 15,
        batchIterations: 150,
        operation: () {
          sink ^= engine.parse(smallDoc).blocks.length;
        },
      );
      final LatencyStats smallEngineHtml = measureLatency(
        label: 'markdown_engine AST+HTML',
        payloadBytes: smallBytes,
        warmupSamples: 4,
        samples: 15,
        batchIterations: 150,
        operation: () {
          sink ^= engine.parse(smallDoc).toHtml().length;
        },
      );
      final LatencyStats smallFlutterMd = measureLatency(
        label: 'flutter_md AST',
        payloadBytes: smallBytes,
        warmupSamples: 4,
        samples: 15,
        batchIterations: 150,
        operation: () {
          sink ^= fmd.Markdown.fromString(smallDoc).blocks.length;
        },
      );
      final LatencyStats smallPkgMarkdownAst = measureLatency(
        label: 'package:markdown AST',
        payloadBytes: smallBytes,
        warmupSamples: 4,
        samples: 15,
        batchIterations: 150,
        operation: () {
          final md.Document doc = md.Document(
            extensionSet: md.ExtensionSet.gitHubFlavored,
            encodeHtml: false,
          );
          sink ^= doc.parseLines(lineSplitter.convert(smallDoc)).length;
        },
      );

      // Medium (~25 KB)
      final LatencyStats mediumEngineAst = measureLatency(
        label: 'markdown_engine AST',
        payloadBytes: mediumBytes,
        warmupSamples: 3,
        samples: 15,
        batchIterations: 10,
        operation: () {
          sink ^= engine.parse(mediumDoc).blocks.length;
        },
      );
      final LatencyStats mediumEngineHtml = measureLatency(
        label: 'markdown_engine AST+HTML',
        payloadBytes: mediumBytes,
        warmupSamples: 3,
        samples: 15,
        batchIterations: 10,
        operation: () {
          sink ^= engine.parse(mediumDoc).toHtml().length;
        },
      );
      final LatencyStats mediumFlutterMd = measureLatency(
        label: 'flutter_md AST',
        payloadBytes: mediumBytes,
        warmupSamples: 3,
        samples: 15,
        batchIterations: 10,
        operation: () {
          sink ^= fmd.Markdown.fromString(mediumDoc).blocks.length;
        },
      );
      final LatencyStats mediumPkgMarkdownAst = measureLatency(
        label: 'package:markdown AST',
        payloadBytes: mediumBytes,
        warmupSamples: 3,
        samples: 15,
        batchIterations: 10,
        operation: () {
          final md.Document doc = md.Document(
            extensionSet: md.ExtensionSet.gitHubFlavored,
            encodeHtml: false,
          );
          sink ^= doc.parseLines(lineSplitter.convert(mediumDoc)).length;
        },
      );

      // Large (5,000 lines ~173 KB)
      final LatencyStats largeEngineAst = measureLatency(
        label: 'markdown_engine AST',
        payloadBytes: largeBytes,
        warmupSamples: 2,
        samples: 11,
        batchIterations: 2,
        operation: () {
          sink ^= engine.parse(largeFixture.baseSource).blocks.length;
        },
      );
      final LatencyStats largeEngineHtml = measureLatency(
        label: 'markdown_engine AST+HTML',
        payloadBytes: largeBytes,
        warmupSamples: 2,
        samples: 11,
        batchIterations: 2,
        operation: () {
          sink ^= engine.parse(largeFixture.baseSource).toHtml().length;
        },
      );
      final LatencyStats largeFlutterMd = measureLatency(
        label: 'flutter_md AST',
        payloadBytes: largeBytes,
        warmupSamples: 2,
        samples: 11,
        batchIterations: 2,
        operation: () {
          sink ^= fmd.Markdown.fromString(
            largeFixture.baseSource,
          ).blocks.length;
        },
      );
      final LatencyStats largePkgMarkdownAst = measureLatency(
        label: 'package:markdown AST',
        payloadBytes: largeBytes,
        warmupSamples: 2,
        samples: 11,
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
      );

      // 50-chunk Streaming
      final StreamingMarkdownController engineStream =
          StreamingMarkdownController(engine: engine, options: gfmOptions);
      final int chunkCount = stream50Fixture.chunks.length;
      final LatencyStats streamEngine = measureLatency(
        label: 'markdown_engine stream (per chunk)',
        payloadBytes: streamBytes,
        warmupSamples: 3,
        samples: 15,
        batchIterations: 8,
        unitDivisor: chunkCount,
        throughputBytesPerUnit: streamBytes / chunkCount,
        operation: () {
          engineStream.reset();
          for (final String chunk in stream50Fixture.chunks) {
            sink ^= engineStream.append(chunk).blocks.length;
          }
        },
      );

      final fmd.StreamingMarkdownParser fmdStream =
          fmd.StreamingMarkdownParser();
      final LatencyStats streamFlutterMd = measureLatency(
        label: 'flutter_md stream (per chunk)',
        payloadBytes: streamBytes,
        warmupSamples: 3,
        samples: 15,
        batchIterations: 8,
        unitDivisor: chunkCount,
        throughputBytesPerUnit: streamBytes / chunkCount,
        operation: () {
          fmdStream.reset();
          for (final String chunk in stream50Fixture.chunks) {
            sink ^= fmdStream.add(chunk).blocks.length;
          }
        },
      );

      final LatencyStats streamPkgMarkdown = measureLatency(
        label: 'package:markdown full-reparse stream (per chunk)',
        payloadBytes: streamBytes,
        warmupSamples: 2,
        samples: 11,
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
            sink ^= doc.parseLines(lineSplitter.convert(buf.toString())).length;
          }
        },
      );

      expect(sink, isNot(-1));
      engineStream.dispose();

      stdout.writeln('');
      stdout.writeln(
        '=== Flutter Test JIT Parser Throughput (markdown_engine vs flutter_md 0.3.1 vs package:markdown 7.3.1) ===',
      );
      _printThreeWay(
        'Small (~1 KB, ${formatBytes(smallBytes)})',
        smallEngineAst,
        smallEngineHtml,
        smallFlutterMd,
        smallPkgMarkdownAst,
      );
      _printThreeWay(
        'Medium (~25 KB, ${formatBytes(mediumBytes)})',
        mediumEngineAst,
        mediumEngineHtml,
        mediumFlutterMd,
        mediumPkgMarkdownAst,
      );
      _printThreeWay(
        'Large (${largeFixture.lineCount} lines, ${formatBytes(largeBytes)})',
        largeEngineAst,
        largeEngineHtml,
        largeFlutterMd,
        largePkgMarkdownAst,
      );
      stdout.writeln(
        '  50-chunk Streaming (${formatBytes(streamBytes)}): '
        'markdown_engine=${formatMicroseconds(streamEngine.medianUs)}/chunk '
        '(${formatMicroseconds(streamEngine.medianUs * chunkCount)} total) | '
        'flutter_md=${formatMicroseconds(streamFlutterMd.medianUs)}/chunk '
        '(${formatMicroseconds(streamFlutterMd.medianUs * chunkCount)} total) | '
        'package:markdown=${formatMicroseconds(streamPkgMarkdown.medianUs)}/chunk '
        '(${formatMicroseconds(streamPkgMarkdown.medianUs * chunkCount)} total)',
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

      // 1a. MarkdownView(data) — includes parse + lazy sliver build/layout.
      final double engineColdMs = await _measureWidgetMounts(
        tester: tester,
        warmupCount: 1,
        sampleCount: 5,
        builder: (int iteration) => MarkdownView(
          doc400,
          key: ValueKey<String>('me_cold_$iteration'),
          engine: engine,
          theme: engineLight,
        ),
      );

      // 1b. MarkdownView.document — pre-parsed lazy sliver build/layout.
      final double enginePreParsedMs = await _measureWidgetMounts(
        tester: tester,
        warmupCount: 1,
        sampleCount: 5,
        builder: (int iteration) => MarkdownView.document(
          key: ValueKey<String>('me_doc_$iteration'),
          document: preParsedEngineDoc,
          theme: engineLight,
        ),
      );

      // 1c. flutter_md MarkdownWidget (parse + full RenderBox layout) &
      // pre-parsed MarkdownWidget.
      final double fmdColdMs = await _measureWidgetMounts(
        tester: tester,
        warmupCount: 1,
        sampleCount: 5,
        builder: (int iteration) => SingleChildScrollView(
          key: ValueKey<String>('fmd_cold_$iteration'),
          child: fmd.MarkdownWidget(
            markdown: fmd.Markdown.fromString(doc400),
            theme: fmdLight,
          ),
        ),
      );
      final double fmdPreParsedMs = await _measureWidgetMounts(
        tester: tester,
        warmupCount: 1,
        sampleCount: 5,
        builder: (int iteration) => SingleChildScrollView(
          key: ValueKey<String>('fmd_doc_$iteration'),
          child: fmd.MarkdownWidget(markdown: preParsedFmdDoc, theme: fmdLight),
        ),
      );

      // 1d. flutter_markdown_plus Markdown (parse + eager ListView build).
      final double fmpColdMs = await _measureWidgetMounts(
        tester: tester,
        warmupCount: 1,
        sampleCount: 5,
        builder: (int iteration) => fmp.Markdown(
          key: ValueKey<String>('fmp_cold_$iteration'),
          data: doc400,
          styleSheet: fmpLight,
        ),
      );

      stdout.writeln('');
      stdout.writeln(
        '=== Widget Benchmark 1: 400+ Block Initial Build & Pump '
        '(${preParsedEngineDoc.blocks.length} blocks, 800x600 viewport) ===',
      );
      stdout.writeln(
        '  MarkdownView(data) (parse + lazy sliver): ${engineColdMs.toStringAsFixed(2)} ms',
      );
      stdout.writeln(
        '  MarkdownView.document (pre-parsed lazy sliver): ${enginePreParsedMs.toStringAsFixed(2)} ms',
      );
      stdout.writeln(
        '  flutter_md (Markdown.fromString + MarkdownWidget): ${fmdColdMs.toStringAsFixed(2)} ms '
        '(pre-parsed widget only: ${fmdPreParsedMs.toStringAsFixed(2)} ms)',
      );
      stdout.writeln(
        '  flutter_markdown_plus Markdown (parse + eager ListView): ${fmpColdMs.toStringAsFixed(2)} ms',
      );
    });

    testWidgets('2. Light <-> Dark theme toggle time + re-parse count', (
      WidgetTester tester,
    ) async {
      const int warmupToggles = 2;
      const int timedToggles = 10;

      // 2a. markdown_engine MarkdownView
      final MarkdownController engineController = MarkdownController();
      const MarkdownThemeData engineLight = MarkdownThemeData.light();
      const MarkdownThemeData engineDark = MarkdownThemeData.dark();
      final ValueNotifier<bool> engineDarkMode = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        _benchShell(
          child: ValueListenableBuilder<bool>(
            valueListenable: engineDarkMode,
            builder: (BuildContext context, bool isDark, _) => MarkdownView(
              doc400,
              controller: engineController,
              theme: isDark ? engineDark : engineLight,
            ),
          ),
        ),
      );
      expect(engineController.parseCount, 1);

      final double engineToggleMs = await _measureThemeToggles(
        tester: tester,
        notifier: engineDarkMode,
        warmupToggles: warmupToggles,
        timedToggles: timedToggles,
      );
      final int engineReparses = engineController.parseCount - 1;
      expect(engineReparses, 0);

      engineController.dispose();
      engineDarkMode.dispose();

      // 2b. flutter_markdown_plus Markdown
      final _CountingH1Builder fmpParseCounter = _CountingH1Builder();
      final fmp.MarkdownStyleSheet fmpLight = _buildFmpStyleSheet(
        Brightness.light,
      );
      final fmp.MarkdownStyleSheet fmpDark = _buildFmpStyleSheet(
        Brightness.dark,
      );
      final ValueNotifier<bool> fmpDarkMode = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        _benchShell(
          child: ValueListenableBuilder<bool>(
            valueListenable: fmpDarkMode,
            builder: (BuildContext context, bool isDark, _) => fmp.Markdown(
              data: doc400,
              styleSheet: isDark ? fmpDark : fmpLight,
              builders: <String, fmp.MarkdownElementBuilder>{
                'h1': fmpParseCounter,
              },
            ),
          ),
        ),
      );
      expect(fmpParseCounter.count, 1);

      final double fmpToggleMs = await _measureThemeToggles(
        tester: tester,
        notifier: fmpDarkMode,
        warmupToggles: warmupToggles,
        timedToggles: timedToggles,
      );
      final int fmpReparses = fmpParseCounter.count - 1;
      expect(fmpReparses, warmupToggles + timedToggles);

      fmpDarkMode.dispose();

      // 2c. flutter_md MarkdownWidget (caller caches pre-parsed Markdown).
      final fmd.Markdown cachedFmd = fmd.Markdown.fromString(doc400);
      final fmd.MarkdownThemeData fmdLight = fmd.MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 16.0, color: Color(0xFF0F172A)),
        surfaceColor: const Color(0xFFF1F5F9),
      );
      final fmd.MarkdownThemeData fmdDark = fmd.MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 16.0, color: Color(0xFFE2E8F0)),
        surfaceColor: const Color(0xFF1E293B),
      );
      final ValueNotifier<bool> fmdDarkMode = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        _benchShell(
          child: ValueListenableBuilder<bool>(
            valueListenable: fmdDarkMode,
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

      final double fmdToggleMs = await _measureThemeToggles(
        tester: tester,
        notifier: fmdDarkMode,
        warmupToggles: warmupToggles,
        timedToggles: timedToggles,
      );
      fmdDarkMode.dispose();

      stdout.writeln('');
      stdout.writeln(
        '=== Widget Benchmark 2: Light <-> Dark Theme Toggle '
        '(${warmupToggles + timedToggles} toggles on 400+ block doc) ===',
      );
      stdout.writeln(
        '  MarkdownView: ${engineToggleMs.toStringAsFixed(2)} ms/toggle | '
        're-parses=$engineReparses',
      );
      stdout.writeln(
        '  flutter_md (cached Markdown): ${fmdToggleMs.toStringAsFixed(2)} ms/toggle | '
        're-parses=0 (caller-cached AST)',
      );
      stdout.writeln(
        '  flutter_markdown_plus Markdown: ${fmpToggleMs.toStringAsFixed(2)} ms/toggle | '
        're-parses=$fmpReparses (full re-parse on every theme flip)',
      );
    });

    testWidgets('3. Live 30-chunk LLM streaming rebuild cost', (
      WidgetTester tester,
    ) async {
      const MarkdownEngine engine = MarkdownEngine(
        defaultOptions: MarkdownOptions.gfm(),
      );
      final List<String> chunks = stream30Fixture.chunks;
      expect(chunks.length, 30);

      const MarkdownThemeData engineLight = MarkdownThemeData.light();
      final fmd.MarkdownThemeData fmdLight = fmd.MarkdownThemeData(
        textStyle: const TextStyle(fontSize: 16.0, color: Color(0xFF0F172A)),
        surfaceColor: const Color(0xFFF1F5F9),
      );
      final fmp.MarkdownStyleSheet fmpLight = _buildFmpStyleSheet(
        Brightness.light,
      );

      // 3a. MarkdownView.streaming (push-based StreamingMarkdownController)
      final StreamingMarkdownController engineStream =
          StreamingMarkdownController(
            engine: engine,
            options: const MarkdownOptions.gfm(),
          );
      await tester.pumpWidget(
        _benchShell(
          child: MarkdownView.streaming(
            controller: engineStream,
            theme: engineLight,
          ),
        ),
      );

      Future<void> runEngineStreamSession() async {
        engineStream.reset();
        await tester.pump();
        for (final String chunk in chunks) {
          engineStream.append(chunk);
          await tester.pump();
        }
        engineStream.finish();
        await tester.pump();
      }

      // Warmup 1 session, then measure 3 sessions.
      await runEngineStreamSession();
      final List<double> engineSessionMs = <double>[];
      for (int i = 0; i < 3; i++) {
        final Stopwatch sw = Stopwatch()..start();
        await runEngineStreamSession();
        sw.stop();
        engineSessionMs.add(sw.elapsedMicroseconds / 1000.0);
      }
      engineSessionMs.sort();
      final double engineMedianSessionMs = engineSessionMs[1];
      await tester.pumpWidget(const SizedBox.shrink());
      engineStream.dispose();

      // 3b. flutter_md StreamingMarkdownParser + MarkdownWidget
      final fmd.StreamingMarkdownParser fmdParser =
          fmd.StreamingMarkdownParser();
      final ValueNotifier<fmd.Markdown> fmdDocNotifier =
          ValueNotifier<fmd.Markdown>(const fmd.Markdown.empty());
      await tester.pumpWidget(
        _benchShell(
          child: ValueListenableBuilder<fmd.Markdown>(
            valueListenable: fmdDocNotifier,
            builder: (BuildContext context, fmd.Markdown doc, _) =>
                SingleChildScrollView(
                  child: fmd.MarkdownWidget(markdown: doc, theme: fmdLight),
                ),
          ),
        ),
      );

      Future<void> runFmdStreamSession() async {
        fmdParser.reset();
        fmdDocNotifier.value = const fmd.Markdown.empty();
        await tester.pump();
        for (final String chunk in chunks) {
          fmdDocNotifier.value = fmdParser.add(chunk);
          await tester.pump();
        }
      }

      await runFmdStreamSession();
      final List<double> fmdSessionMs = <double>[];
      for (int i = 0; i < 3; i++) {
        final Stopwatch sw = Stopwatch()..start();
        await runFmdStreamSession();
        sw.stop();
        fmdSessionMs.add(sw.elapsedMicroseconds / 1000.0);
      }
      fmdSessionMs.sort();
      final double fmdMedianSessionMs = fmdSessionMs[1];
      await tester.pumpWidget(const SizedBox.shrink());
      fmdDocNotifier.dispose();

      // 3c. flutter_markdown_plus full re-parse + full rebuild per chunk
      final ValueNotifier<String> fmpSourceNotifier = ValueNotifier<String>('');
      await tester.pumpWidget(
        _benchShell(
          child: ValueListenableBuilder<String>(
            valueListenable: fmpSourceNotifier,
            builder: (BuildContext context, String data, _) =>
                fmp.Markdown(data: data, styleSheet: fmpLight),
          ),
        ),
      );

      Future<void> runFmpStreamSession() async {
        final StringBuffer acc = StringBuffer();
        fmpSourceNotifier.value = '';
        await tester.pump();
        for (final String chunk in chunks) {
          acc.write(chunk);
          fmpSourceNotifier.value = acc.toString();
          await tester.pump();
        }
      }

      await runFmpStreamSession();
      final List<double> fmpSessionMs = <double>[];
      for (int i = 0; i < 3; i++) {
        final Stopwatch sw = Stopwatch()..start();
        await runFmpStreamSession();
        sw.stop();
        fmpSessionMs.add(sw.elapsedMicroseconds / 1000.0);
      }
      fmpSessionMs.sort();
      final double fmpMedianSessionMs = fmpSessionMs[1];
      await tester.pumpWidget(const SizedBox.shrink());
      fmpSourceNotifier.dispose();

      stdout.writeln('');
      stdout.writeln(
        '=== Widget Benchmark 3: Live 30-Chunk LLM Streaming Session ===',
      );
      stdout.writeln(
        '  MarkdownView.streaming: ${engineMedianSessionMs.toStringAsFixed(2)} ms total '
        '(${(engineMedianSessionMs / chunks.length).toStringAsFixed(2)} ms/chunk)',
      );
      stdout.writeln(
        '  flutter_md StreamingMarkdownParser + MarkdownWidget: '
        '${fmdMedianSessionMs.toStringAsFixed(2)} ms total '
        '(${(fmdMedianSessionMs / chunks.length).toStringAsFixed(2)} ms/chunk)',
      );
      stdout.writeln(
        '  flutter_markdown_plus Markdown (full re-parse/rebuild): '
        '${fmpMedianSessionMs.toStringAsFixed(2)} ms total '
        '(${(fmpMedianSessionMs / chunks.length).toStringAsFixed(2)} ms/chunk)',
      );
    });
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

Future<double> _measureWidgetMounts({
  required WidgetTester tester,
  required int warmupCount,
  required int sampleCount,
  required Widget Function(int iteration) builder,
}) async {
  for (int w = 0; w < warmupCount; w++) {
    await tester.pumpWidget(_benchShell(child: builder(-1 - w)));
    await tester.pumpWidget(const SizedBox.shrink());
  }

  final List<double> samplesMs = <double>[];
  for (int i = 0; i < sampleCount; i++) {
    final Stopwatch sw = Stopwatch()..start();
    await tester.pumpWidget(_benchShell(child: builder(i)));
    sw.stop();
    samplesMs.add(sw.elapsedMicroseconds / 1000.0);
    await tester.pumpWidget(const SizedBox.shrink());
  }
  samplesMs.sort();
  return samplesMs[samplesMs.length ~/ 2];
}

Future<double> _measureThemeToggles({
  required WidgetTester tester,
  required ValueNotifier<bool> notifier,
  required int warmupToggles,
  required int timedToggles,
}) async {
  for (int w = 0; w < warmupToggles; w++) {
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
  samplesMs.sort();
  return samplesMs[samplesMs.length ~/ 2];
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
    '(${engineAst.throughputMbPerSec.toStringAsFixed(2)} MB/s), '
    'AST+HTML=${formatMicroseconds(engineHtml.medianUs)} | '
    'flutter_md AST=${formatMicroseconds(fmdAst.medianUs)} '
    '(${fmdAst.throughputMbPerSec.toStringAsFixed(2)} MB/s) | '
    'package:markdown AST=${formatMicroseconds(pkgMarkdownAst.medianUs)} '
    '(${pkgMarkdownAst.throughputMbPerSec.toStringAsFixed(2)} MB/s)',
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
