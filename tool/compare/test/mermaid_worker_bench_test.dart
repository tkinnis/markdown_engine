import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_engine_compare/compare_fixtures.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';
// ignore: implementation_imports
import 'package:markdown_engine_flutter/src/built_in_mermaid.dart';

void main() {
  testWidgets(
    '10-diagram cold Mermaid worker isolate benchmark (persistent + burst pool vs single persistent vs compute)',
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
        MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers =
            MarkdownBuiltInRenderers.defaultMaxMermaidConcurrentWorkers;
        MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
        MarkdownBuiltInRenderers.debugForceAsyncMermaidInTests = false;
        await MarkdownBuiltInRenderers.dispose();
      });

      const int warmupRounds = 2;
      const int timedRounds = 10;

      late ({SampleSummary persistent, SampleSummary oneShot}) unwarmedSeq;
      late ({SampleSummary persistent, SampleSummary oneShot}) warmedSeq;
      late ({
        SampleSummary lazyBurst,
        SampleSummary warmBurst,
        SampleSummary singlePersistent,
        SampleSummary oneShot,
      })
      warmedConcurrent;

      await tester.runAsync(() async {
        unwarmedSeq = await _benchmarkSequentialMode(
          diagrams: diagrams,
          theme: lightTheme,
          warmupRounds: warmupRounds,
          timedRounds: timedRounds,
          warmBeforeBatch: false,
        );

        warmedSeq = await _benchmarkSequentialMode(
          diagrams: diagrams,
          theme: lightTheme,
          warmupRounds: warmupRounds,
          timedRounds: timedRounds,
          warmBeforeBatch: true,
        );

        warmedConcurrent = await _benchmarkConcurrentMode(
          diagrams: diagrams,
          theme: lightTheme,
          warmupRounds: warmupRounds,
          timedRounds: timedRounds,
        );
      });

      stdout.writeln('');
      stdout.writeln(
        '=== Mermaid Worker Isolate Benchmark (10 Distinct Cold Diagrams, '
        '$warmupRounds warmup + $timedRounds interleaved rounds, '
        'defaultMaxMermaidConcurrentWorkers=${MarkdownBuiltInRenderers.defaultMaxMermaidConcurrentWorkers}, '
        'debugForceAsyncMermaidInTests=true) ===',
      );
      _printSequentialComparison('Unwarmed sequential', unwarmedSeq);
      _printSequentialComparison('Post-warmUp() sequential', warmedSeq);
      _printConcurrentComparison(
        'Post-warmUp() concurrent (Future.wait)',
        warmedConcurrent,
      );
    },
  );
}

Future<({SampleSummary persistent, SampleSummary oneShot})>
_benchmarkSequentialMode({
  required List<String> diagrams,
  required DerivedMermaidTheme theme,
  required int warmupRounds,
  required int timedRounds,
  required bool warmBeforeBatch,
}) async {
  final List<double> persistentSamplesMs = <double>[];
  final List<double> oneShotSamplesMs = <double>[];

  for (int round = 0; round < warmupRounds + timedRounds; round++) {
    final bool isTimed = round >= warmupRounds;
    for (final int idx in interleaveRoundIndices(2, round)) {
      final bool usePersistent = idx == 0;
      MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers =
          MarkdownBuiltInRenderers.defaultMaxMermaidConcurrentWorkers;
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

      final List<BuiltInMermaidResult> results = <BuiltInMermaidResult>[];
      final Stopwatch sw = Stopwatch()..start();
      for (final String code in diagrams) {
        results.add(await BuiltInMermaidCache.instance.render(code, theme));
      }
      sw.stop();

      expect(results.length, diagrams.length);
      for (final BuiltInMermaidResult result in results) {
        expect(result, isA<BuiltInMermaidSuccess>());
      }
      expect(MarkdownBuiltInRenderers.mermaidRenderCount, diagrams.length);
      expect(MarkdownBuiltInRenderers.mermaidCacheHitCount, 0);
      expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, usePersistent);
      expect(
        MarkdownBuiltInRenderers.activeMermaidWorkerCount,
        usePersistent ? 1 : 0,
      );

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

Future<
  ({
    SampleSummary lazyBurst,
    SampleSummary warmBurst,
    SampleSummary singlePersistent,
    SampleSummary oneShot,
  })
>
_benchmarkConcurrentMode({
  required List<String> diagrams,
  required DerivedMermaidTheme theme,
  required int warmupRounds,
  required int timedRounds,
}) async {
  final List<double> lazyBurstSamplesMs = <double>[];
  final List<double> warmBurstSamplesMs = <double>[];
  final List<double> singlePersistentSamplesMs = <double>[];
  final List<double> oneShotSamplesMs = <double>[];

  final int defaultCap =
      MarkdownBuiltInRenderers.defaultMaxMermaidConcurrentWorkers;

  for (int round = 0; round < warmupRounds + timedRounds; round++) {
    final bool isTimed = round >= warmupRounds;
    for (final int mode in interleaveRoundIndices(4, round)) {
      await MarkdownBuiltInRenderers.dispose();
      switch (mode) {
        case 0:
          // persistent + lazy burst (only primary warm initially).
          MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = defaultCap;
          MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
        case 1:
          // persistent + warm burst (all burst workers pre-spawned/warmed).
          MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = defaultCap;
          MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
          await MarkdownBuiltInRenderers.warmUp();
          MarkdownBuiltInRenderers.clearCaches();
          final List<BuiltInMermaidResult> preBurst =
              await Future.wait<BuiltInMermaidResult>(
                diagrams.map(
                  (String code) =>
                      BuiltInMermaidCache.instance.render(code, theme),
                ),
              );
          expect(preBurst.length, diagrams.length);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, defaultCap);
        case 2:
          // single persistent (cap=1).
          MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = 1;
          MarkdownBuiltInRenderers.usePersistentMermaidIsolate = true;
          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 1);
        case 3:
          // one-shot compute().
          MarkdownBuiltInRenderers.maxMermaidConcurrentWorkers = defaultCap;
          MarkdownBuiltInRenderers.usePersistentMermaidIsolate = false;
          await MarkdownBuiltInRenderers.warmUp();
          expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
          expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 0);
      }

      MarkdownBuiltInRenderers.clearCaches();
      expect(MarkdownBuiltInRenderers.mermaidCacheLength, 0);

      final Stopwatch sw = Stopwatch()..start();
      final List<BuiltInMermaidResult> results =
          await Future.wait<BuiltInMermaidResult>(
            diagrams.map(
              (String code) => BuiltInMermaidCache.instance.render(code, theme),
            ),
          );
      sw.stop();

      expect(results.length, diagrams.length);
      for (final BuiltInMermaidResult result in results) {
        expect(result, isA<BuiltInMermaidSuccess>());
      }
      expect(MarkdownBuiltInRenderers.mermaidRenderCount, diagrams.length);
      expect(MarkdownBuiltInRenderers.mermaidCacheHitCount, 0);

      if (mode == 3) {
        expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isFalse);
        expect(MarkdownBuiltInRenderers.activeMermaidWorkerCount, 0);
      } else {
        expect(MarkdownBuiltInRenderers.isMermaidWorkerActive, isTrue);
        expect(
          MarkdownBuiltInRenderers.activeMermaidWorkerCount,
          lessThanOrEqualTo(mode == 2 ? 1 : defaultCap),
        );
      }

      if (isTimed) {
        final double elapsedMs = sw.elapsedMicroseconds / 1000.0;
        switch (mode) {
          case 0:
            lazyBurstSamplesMs.add(elapsedMs);
          case 1:
            warmBurstSamplesMs.add(elapsedMs);
          case 2:
            singlePersistentSamplesMs.add(elapsedMs);
          case 3:
            oneShotSamplesMs.add(elapsedMs);
        }
      }
    }
  }

  return (
    lazyBurst: summarizeSamples(lazyBurstSamplesMs),
    warmBurst: summarizeSamples(warmBurstSamplesMs),
    singlePersistent: summarizeSamples(singlePersistentSamplesMs),
    oneShot: summarizeSamples(oneShotSamplesMs),
  );
}

void _printSequentialComparison(
  String label,
  ({SampleSummary persistent, SampleSummary oneShot}) pair,
) {
  final double ratio = pair.persistent.median > 0
      ? pair.oneShot.median / pair.persistent.median
      : 0.0;
  final String speedupNote = ratio >= 1.0
      ? '${ratio.toStringAsFixed(2)}x faster persistent'
      : '${(1.0 / ratio).toStringAsFixed(2)}x faster compute()';
  stdout.writeln(
    '  $label: '
    'usePersistentMermaidIsolate=true -> ${formatMsSummary(pair.persistent)} | '
    'false (compute) -> ${formatMsSummary(pair.oneShot)} '
    '[$speedupNote]',
  );
}

void _printConcurrentComparison(
  String label,
  ({
    SampleSummary lazyBurst,
    SampleSummary warmBurst,
    SampleSummary singlePersistent,
    SampleSummary oneShot,
  })
  results,
) {
  final String warmVsCompute = results.warmBurst.median > 0
      ? '${(results.oneShot.median / results.warmBurst.median).toStringAsFixed(2)}x vs compute()'
      : 'n/a';
  final String lazyVsCompute = results.lazyBurst.median > 0
      ? '${(results.oneShot.median / results.lazyBurst.median).toStringAsFixed(2)}x vs compute()'
      : 'n/a';
  stdout.writeln('  $label:');
  stdout.writeln(
    '    persistent + lazy burst   -> ${formatMsSummary(results.lazyBurst)} [$lazyVsCompute]',
  );
  stdout.writeln(
    '    persistent + warm burst   -> ${formatMsSummary(results.warmBurst)} [$warmVsCompute]',
  );
  stdout.writeln(
    '    single persistent (cap=1) -> ${formatMsSummary(results.singlePersistent)}',
  );
  stdout.writeln(
    '    one-shot compute()        -> ${formatMsSummary(results.oneShot)}',
  );
}
