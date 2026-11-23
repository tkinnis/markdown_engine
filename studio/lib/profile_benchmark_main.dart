import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Profile-mode macOS frame-time benchmark entrypoint for `markdown_engine_flutter`.
///
/// Run in real `--profile` mode via:
/// `flutter run -d macos --profile -t lib/profile_benchmark_main.dart`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MarkdownBuiltInRenderers.warmUp();
  runApp(const _ProfileBenchmarkApp());
}

final class _ProfileBenchmarkApp extends StatefulWidget {
  const _ProfileBenchmarkApp();

  @override
  State<_ProfileBenchmarkApp> createState() => _ProfileBenchmarkAppState();
}

enum _BenchPhase { idle, scrolling, streaming, done }

final class _ProfileBenchmarkAppState extends State<_ProfileBenchmarkApp> {
  static const double _jankThresholdMs = 1000.0 / 60.0; // 16.6667 ms

  late final String _doc500;
  late final ScrollController _scrollController;
  late final MarkdownController _markdownController;
  late final StreamingMarkdownController _streamController;

  final List<FrameTiming> _scrollTimings = <FrameTiming>[];
  final List<FrameTiming> _streamTimings = <FrameTiming>[];

  _BenchPhase _phase = _BenchPhase.idle;
  bool _recordingActive = false;

  @override
  void initState() {
    super.initState();
    _doc500 = _build500SectionBenchmarkDocument();
    _scrollController = ScrollController();
    _markdownController = MarkdownController();
    _streamController = StreamingMarkdownController(
      options: const MarkdownOptions.extended(),
    );
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      unawaited(_runBenchmarks());
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _scrollController.dispose();
    _markdownController.dispose();
    _streamController.dispose();
    super.dispose();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_recordingActive) {
      return;
    }
    if (_phase == _BenchPhase.scrolling) {
      _scrollTimings.addAll(timings);
    } else if (_phase == _BenchPhase.streaming) {
      _streamTimings.addAll(timings);
    }
  }

  Future<void> _waitNextFrame() {
    final Completer<void> completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    SchedulerBinding.instance.scheduleFrame();
    return completer.future;
  }

  Future<void> _runBenchmarks() async {
    // Allow initial window presentation + shader warm-up to settle before timing.
    for (int i = 0; i < 8; i++) {
      await _waitNextFrame();
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Phase A: Smooth 500-section scroll exercising TexMath + Mermaid + tables/alerts.
    _scrollTimings.clear();
    setState(() {
      _phase = _BenchPhase.scrolling;
    });
    await _waitNextFrame();
    _recordingActive = true;

    const int scrollFrames = 150;
    const double stepPx = 220.0;
    for (int frame = 1; frame <= scrollFrames; frame++) {
      if (_scrollController.hasClients) {
        final double maxExtent = _scrollController.position.maxScrollExtent;
        final double target = (frame * stepPx).clamp(0.0, maxExtent);
        _scrollController.jumpTo(target);
      }
      await _waitNextFrame();
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
    _recordingActive = false;

    // Phase B: 60Hz realistic streaming (48 chunks including math & Mermaid).
    _streamTimings.clear();
    _streamController.reset();
    setState(() {
      _phase = _BenchPhase.streaming;
    });
    await _waitNextFrame();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    _recordingActive = true;
    final List<String> chunks = _build48StreamingChunks();
    final Completer<void> streamDone = Completer<void>();
    int chunkIndex = 0;
    final Timer streamTimer = Timer.periodic(const Duration(milliseconds: 16), (
      Timer timer,
    ) {
      if (!mounted) {
        timer.cancel();
        if (!streamDone.isCompleted) {
          streamDone.complete();
        }
        return;
      }
      if (chunkIndex < chunks.length) {
        _streamController.append(chunks[chunkIndex]);
        chunkIndex++;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
      if (chunkIndex >= chunks.length) {
        _streamController.finish();
        timer.cancel();
        if (!streamDone.isCompleted) {
          streamDone.complete();
        }
      }
    });
    await streamDone.future;
    streamTimer.cancel();

    for (int i = 0; i < 6; i++) {
      await _waitNextFrame();
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _recordingActive = false;

    if (mounted) {
      setState(() {
        _phase = _BenchPhase.done;
      });
    }

    _printReport(chunks.length);
    await MarkdownBuiltInRenderers.dispose();
    await stdout.flush();
    exit(0);
  }

  void _printReport(int chunkCount) {
    final _FrameStats scrollStats = _computeStats(_scrollTimings);
    final _FrameStats streamStats = _computeStats(_streamTimings);

    stdout.writeln('=== macOS --profile FrameTiming Benchmark ===');
    stdout.writeln(
      'Scroll (500 sections, math + Mermaid + tables/alerts): '
      'frames=${scrollStats.frameCount} | '
      'build p50=${scrollStats.buildP50Ms.toStringAsFixed(2)}ms '
      'p95=${scrollStats.buildP95Ms.toStringAsFixed(2)}ms '
      'p99=${scrollStats.buildP99Ms.toStringAsFixed(2)}ms '
      'max=${scrollStats.buildMaxMs.toStringAsFixed(2)}ms | '
      'raster p50=${scrollStats.rasterP50Ms.toStringAsFixed(2)}ms '
      'p95=${scrollStats.rasterP95Ms.toStringAsFixed(2)}ms '
      'p99=${scrollStats.rasterP99Ms.toStringAsFixed(2)}ms '
      'max=${scrollStats.rasterMaxMs.toStringAsFixed(2)}ms | '
      'jank(>16.67ms): build=${scrollStats.buildJankCount} '
      'raster=${scrollStats.rasterJankCount} '
      'total=${scrollStats.totalJankCount}',
    );
    stdout.writeln(
      'Streaming ($chunkCount chunks @ 60Hz, math + Mermaid): '
      'frames=${streamStats.frameCount} | '
      'build p50=${streamStats.buildP50Ms.toStringAsFixed(2)}ms '
      'p95=${streamStats.buildP95Ms.toStringAsFixed(2)}ms '
      'p99=${streamStats.buildP99Ms.toStringAsFixed(2)}ms '
      'max=${streamStats.buildMaxMs.toStringAsFixed(2)}ms | '
      'raster p50=${streamStats.rasterP50Ms.toStringAsFixed(2)}ms '
      'p95=${streamStats.rasterP95Ms.toStringAsFixed(2)}ms '
      'p99=${streamStats.rasterP99Ms.toStringAsFixed(2)}ms '
      'max=${streamStats.rasterMaxMs.toStringAsFixed(2)}ms | '
      'jank(>16.67ms): build=${streamStats.buildJankCount} '
      'raster=${streamStats.rasterJankCount} '
      'total=${streamStats.totalJankCount}',
    );
    stdout.writeln(
      'Cache Telemetry: '
      'mathLayouts=${MarkdownBuiltInRenderers.mathLayoutCount} '
      'mathHits=${MarkdownBuiltInRenderers.mathCacheHitCount} '
      'mermaidRenders=${MarkdownBuiltInRenderers.mermaidRenderCount} '
      'mermaidHits=${MarkdownBuiltInRenderers.mermaidCacheHitCount}',
    );
  }

  _FrameStats _computeStats(List<FrameTiming> timings) {
    if (timings.isEmpty) {
      return const _FrameStats(
        frameCount: 0,
        buildP50Ms: 0.0,
        buildP95Ms: 0.0,
        buildP99Ms: 0.0,
        buildMaxMs: 0.0,
        rasterP50Ms: 0.0,
        rasterP95Ms: 0.0,
        rasterP99Ms: 0.0,
        rasterMaxMs: 0.0,
        buildJankCount: 0,
        rasterJankCount: 0,
        totalJankCount: 0,
      );
    }

    final List<double> builds =
        timings
            .map((FrameTiming t) => t.buildDuration.inMicroseconds / 1000.0)
            .toList(growable: false)
          ..sort();
    final List<double> rasters =
        timings
            .map((FrameTiming t) => t.rasterDuration.inMicroseconds / 1000.0)
            .toList(growable: false)
          ..sort();

    int buildJank = 0;
    int rasterJank = 0;
    int totalJank = 0;
    for (final FrameTiming t in timings) {
      final double b = t.buildDuration.inMicroseconds / 1000.0;
      final double r = t.rasterDuration.inMicroseconds / 1000.0;
      final double total = t.totalSpan.inMicroseconds / 1000.0;
      if (b > _jankThresholdMs) {
        buildJank++;
      }
      if (r > _jankThresholdMs) {
        rasterJank++;
      }
      if (total > _jankThresholdMs) {
        totalJank++;
      }
    }

    return _FrameStats(
      frameCount: timings.length,
      buildP50Ms: _percentile(builds, 0.50),
      buildP95Ms: _percentile(builds, 0.95),
      buildP99Ms: _percentile(builds, 0.99),
      buildMaxMs: builds.last,
      rasterP50Ms: _percentile(rasters, 0.50),
      rasterP95Ms: _percentile(rasters, 0.95),
      rasterP99Ms: _percentile(rasters, 0.99),
      rasterMaxMs: rasters.last,
      buildJankCount: buildJank,
      rasterJankCount: rasterJank,
      totalJankCount: totalJank,
    );
  }

  static double _percentile(List<double> sorted, double q) {
    if (sorted.isEmpty) {
      return 0.0;
    }
    if (sorted.length == 1) {
      return sorted.first;
    }
    final double index = q * (sorted.length - 1);
    final int lower = index.floor();
    final int upper = index.ceil();
    if (lower == upper) {
      return sorted[lower];
    }
    final double frac = index - lower;
    return sorted[lower] * (1.0 - frac) + sorted[upper] * frac;
  }

  @override
  Widget build(BuildContext context) {
    const MarkdownThemeData theme = MarkdownThemeData.light();
    const MarkdownBuilderDelegates delegates = MarkdownBuilderDelegates(
      imagePolicy: MarkdownImagePolicy.block,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: MarkdownTheme(
          data: theme,
          child: switch (_phase) {
            _BenchPhase.streaming => MarkdownView.streaming(
              controller: _streamController,
              scrollController: _scrollController,
              theme: theme,
              delegates: delegates,
              padding: const EdgeInsets.all(24.0),
            ),
            _ => MarkdownView(
              _doc500,
              options: const MarkdownOptions.extended(),
              controller: _markdownController,
              scrollController: _scrollController,
              theme: theme,
              delegates: delegates,
              padding: const EdgeInsets.all(24.0),
            ),
          },
        ),
      ),
    );
  }
}

final class _FrameStats {
  const _FrameStats({
    required this.frameCount,
    required this.buildP50Ms,
    required this.buildP95Ms,
    required this.buildP99Ms,
    required this.buildMaxMs,
    required this.rasterP50Ms,
    required this.rasterP95Ms,
    required this.rasterP99Ms,
    required this.rasterMaxMs,
    required this.buildJankCount,
    required this.rasterJankCount,
    required this.totalJankCount,
  });

  final int frameCount;
  final double buildP50Ms;
  final double buildP95Ms;
  final double buildP99Ms;
  final double buildMaxMs;
  final double rasterP50Ms;
  final double rasterP95Ms;
  final double rasterP99Ms;
  final double rasterMaxMs;
  final int buildJankCount;
  final int rasterJankCount;
  final int totalJankCount;
}

String _build500SectionBenchmarkDocument() {
  final StringBuffer out = StringBuffer()
    ..writeln('# 500-Section Profile Frame Benchmark')
    ..writeln()
    ..writeln(
      'Exercises virtualized scrolling across 500 sections containing '
      'built-in `TexMath`, `BuiltInMermaidDiagram`, tables, and alerts.',
    )
    ..writeln();

  for (int i = 1; i <= 500; i++) {
    out
      ..writeln('## Section $i {#bench-$i}')
      ..writeln()
      ..writeln(
        'Section $i mixes **bold**, *italic*, `id-$i`, and inline OpenType math '
        '\$x_{$i} = \\frac{${i}a + b}{2}\$ inside prose.',
      )
      ..writeln();

    if (i % 25 == 0) {
      out
        ..writeln('```mermaid')
        ..writeln('flowchart LR')
        ..writeln('  S$i["Stage $i"] --> A$i["AST"] --> V$i["VectorGraphic"]')
        ..writeln('```')
        ..writeln();
    } else if (i % 20 == 0) {
      out
        ..writeln('\$\$')
        ..writeln('\\sum_{k=1}^{$i} k = \\frac{$i(${i + 1})}{2}')
        ..writeln('\$\$')
        ..writeln();
    } else if (i % 10 == 0) {
      out
        ..writeln('| Metric | Value | Status |')
        ..writeln('| :--- | :---: | ---: |')
        ..writeln('| Checkpoint | #$i | OK |')
        ..writeln('| Formula | \$O(\\log n)\$ | Active |')
        ..writeln();
    } else if (i % 5 == 0) {
      out
        ..writeln('> [!NOTE]')
        ..writeln('> Sliver checkpoint $i with cached math and Mermaid.')
        ..writeln();
    }
  }
  return out.toString();
}

List<String> _build48StreamingChunks() {
  return const <String>[
    '# Profile ',
    'Streaming ',
    'Benchmark\n\n',
    'Streaming ',
    'chunks ',
    'append ',
    'at 60Hz ',
    'while ',
    'freezing ',
    'completed ',
    'prefix ',
    'blocks.\n\n',
    'Inline ',
    'math ',
    r'$e^{i\pi} ',
    r'+ 1 ',
    r'= 0$ ',
    'aligns ',
    'cleanly ',
    'with ',
    r'\(\alpha ',
    r'+ \beta ',
    r'= \gamma\) ',
    'prose.\n\n',
    '> [!TIP]\n',
    '> Settled ',
    'blocks ',
    'reuse ',
    'cached ',
    'widgets ',
    'across ',
    'frames.\n\n',
    '\$\$\n',
    r'\int_{-\infty}^{\infty} ',
    r'e^{-x^2}\,dx ',
    r'= \sqrt{\pi}',
    '\n\$\$\n\n',
    '```mermaid\n',
    'flowchart LR\n',
    '  Chunk["60Hz Chunk"] --> ',
    'Tail["Active Tail"]\n',
    '  Tail --> ',
    'Frozen["Settled Sliver"]\n',
    '```\n\n',
    '| Stage | Role |\n| :--- | :--- |\n',
    '| Prefix | Frozen AST |\n',
    '| Tail | Incremental |\n\n',
    'Stream complete.\n',
  ];
}
