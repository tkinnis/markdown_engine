import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_compare/compare_fixtures.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
// ignore: implementation_imports
import 'package:markdown_engine_flutter/src/built_in_mermaid.dart';

void main() {
  testWidgets(
    '10-diagram cold Mermaid worker isolate benchmark (persistent vs one-shot compute)',
    (WidgetTester tester) async {
      final List<String> diagrams = buildMermaid10DiagramCorpus();
      expect(diagrams.length, 10);

      final DerivedMermaidTheme lightTheme = deriveMermaidTheme(
        const MarkdownThemeData.light(),
      );

      MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = true;
      addTearDown(() async {
        MarkdownBuiltInRenderers.resetCacheDefaults();
        MarkdownBuiltInRenderers.clearCaches();
        MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
        MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = false;
        await MarkdownBuiltInRenderers.dispose();
      });

      const int warmupRounds = 2;
      const int timedRounds = 10;

      late ({SampleSummary persistent, SampleSummary oneShot}) unwarmedSeq;
      late ({SampleSummary persistent, SampleSummary oneShot}) warmedSeq;
      late ({SampleSummary persistent, SampleSummary oneShot}) warmedConcurrent;

      await tester.runAsync(() async {
        unwarmedSeq = await _benchmarkDispatchMode(
          diagrams: diagrams,
          theme: lightTheme,
          warmupRounds: warmupRounds,
          timedRounds: timedRounds,
          warmBeforeBatch: false,
          concurrent: false,
        );

        warmedSeq = await _benchmarkDispatchMode(
          diagrams: diagrams,
          theme: lightTheme,
          warmupRounds: warmupRounds,
          timedRounds: timedRounds,
          warmBeforeBatch: true,
          concurrent: false,
        );

        warmedConcurrent = await _benchmarkDispatchMode(
          diagrams: diagrams,
          theme: lightTheme,
          warmupRounds: warmupRounds,
          timedRounds: timedRounds,
          warmBeforeBatch: true,
          concurrent: true,
        );
      });

      stdout.writeln('');
      stdout.writeln(
        '=== Mermaid Worker Isolate Benchmark (10 Distinct Cold Diagrams, '
        '$warmupRounds warmup + $timedRounds interleaved rounds, '
        'debugForceAsyncMermaidInTests=true) ===',
      );
      _printWorkerComparison('Unwarmed sequential', unwarmedSeq);
      _printWorkerComparison('Post-warmUp() sequential', warmedSeq);
      _printWorkerComparison(
        'Post-warmUp() concurrent (Future.wait)',
        warmedConcurrent,
      );
    },
  );
}

Future<({SampleSummary persistent, SampleSummary oneShot})>
_benchmarkDispatchMode({
  required List<String> diagrams,
  required DerivedMermaidTheme theme,
  required int warmupRounds,
  required int timedRounds,
  required bool warmBeforeBatch,
  required bool concurrent,
}) async {
  final List<double> persistentSamplesMs = <double>[];
  final List<double> oneShotSamplesMs = <double>[];

  for (int round = 0; round < warmupRounds + timedRounds; round++) {
    final bool isTimed = round >= warmupRounds;
    for (final int idx in interleaveRoundIndices(2, round)) {
      final bool usePersistent = idx == 0;
      if (warmBeforeBatch) {
        MarkdownBuiltInRenderers.usePersistentMermaidIsolate = usePersistent;
        await MarkdownBuiltInRenderers.warmUp();
        expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, usePersistent);
      } else {
        await MarkdownBuiltInRenderers.dispose();
        MarkdownBuiltInRenderers.usePersistentMermaidIsolate = usePersistent;
        expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
      }

      MarkdownBuiltInRenderers.clearCaches();
      expect(MarkdownBuiltInRenderers.mermaidCacheLength, 0);

      final List<BuiltInMermaidResult> results;
      final Stopwatch sw = Stopwatch()..start();
      if (concurrent) {
        results = await Future.wait<BuiltInMermaidResult>(
          diagrams.map(
            (String code) => BuiltInMermaidCache.instance.render(code, theme),
          ),
        );
      } else {
        results = <BuiltInMermaidResult>[];
        for (final String code in diagrams) {
          results.add(await BuiltInMermaidCache.instance.render(code, theme));
        }
      }
      sw.stop();

      expect(results.length, diagrams.length);
      for (final BuiltInMermaidResult result in results) {
        expect(result, isA<BuiltInMermaidSuccess>());
      }
      expect(MarkdownBuiltInRenderers.mermaidRenderCount, diagrams.length);
      expect(MarkdownBuiltInRenderers.mermaidCacheHitCount, 0);
      expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, usePersistent);

      if (isTimed) {
        final double elapsedMs = sw.elapsedMicroseconds / 1000.0;
        if (usePersistent) {
          persistentSamplesMs.add(elapsedMs);
        } else {
          oneShotSamplesMs.add(elapsedMs);
        }
      }
    }
  }

  return (
    persistent: summarizeSamples(persistentSamplesMs),
    oneShot: summarizeSamples(oneShotSamplesMs),
  );
}

void _printWorkerComparison(
  String label,
  ({SampleSummary persistent, SampleSummary oneShot}) pair,
) {
  final double ratio = pair.persistent.median > 0
      ? pair.oneShot.median / pair.persistent.median
      : 0.0;
  final String speedupNote = ratio >= 1.0
      ? '${ratio.toStringAsFixed(2)}x faster persistent'
      : '${(1.0 / ratio).toStringAsFixed(2)}x faster parallel compute()';
  stdout.writeln(
    '  $label: '
    'usePersistentMermaidIsolate=true -> ${formatMsSummary(pair.persistent)} | '
    'false (compute) -> ${formatMsSummary(pair.oneShot)} '
    '[$speedupNote]',
  );
}
