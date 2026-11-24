import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tex_math_flutter/tex_math_flutter.dart' show TexMathFontBundle;

import 'built_in_math.dart';
import 'built_in_mermaid.dart';

/// Lifecycle, pre-warming, cache management, and telemetry helpers for
/// `markdown_engine_flutter`'s built-in TeX math (`tex_math_flutter`) and
/// Mermaid (`pele_dart` + `vector_graphics`) renderers.
abstract final class MarkdownBuiltInRenderers {
  /// Pre-loads the bundled OpenType math font (`NewCMMath-Regular.otf`) and
  /// primes the Mermaid diagram registry off the UI thread so subsequent math
  /// and diagram blocks render without cold-start latency.
  static Future<void> warmUp() async {
    await Future.wait<void>(<Future<void>>[
      TexMathFontBundle.loadMathFont().then((_) {}),
      BuiltInMermaidCache.instance.warmUp(),
    ]);
  }

  /// Configures dual entry-count and retained-byte LRU budgets for the built-in
  /// TeX math and Mermaid caches, immediately evicting LRU entries over budget.
  ///
  /// Throws [RangeError] if any supplied limit is `<= 0` without mutating
  /// existing cache budgets.
  static void configureCaches({
    int? mathMaxEntries,
    int? mathMaxBytes,
    int? mermaidMaxEntries,
    int? mermaidMaxBytes,
  }) {
    if (mathMaxEntries != null && mathMaxEntries <= 0) {
      throw RangeError.value(
        mathMaxEntries,
        'mathMaxEntries',
        'Must be greater than zero.',
      );
    }
    if (mathMaxBytes != null && mathMaxBytes <= 0) {
      throw RangeError.value(
        mathMaxBytes,
        'mathMaxBytes',
        'Must be greater than zero.',
      );
    }
    if (mermaidMaxEntries != null && mermaidMaxEntries <= 0) {
      throw RangeError.value(
        mermaidMaxEntries,
        'mermaidMaxEntries',
        'Must be greater than zero.',
      );
    }
    if (mermaidMaxBytes != null && mermaidMaxBytes <= 0) {
      throw RangeError.value(
        mermaidMaxBytes,
        'mermaidMaxBytes',
        'Must be greater than zero.',
      );
    }
    if (mathMaxEntries != null || mathMaxBytes != null) {
      BuiltInMathCache.instance.configure(
        maxEntries: mathMaxEntries,
        maxBytes: mathMaxBytes,
      );
    }
    if (mermaidMaxEntries != null || mermaidMaxBytes != null) {
      BuiltInMermaidCache.instance.configure(
        maxEntries: mermaidMaxEntries,
        maxBytes: mermaidMaxBytes,
      );
    }
  }

  /// Restores default entry-count and retained-byte budgets for both the TeX
  /// math and Mermaid LRU caches, evicting any entries exceeding defaults.
  static void resetCacheDefaults() {
    BuiltInMathCache.instance.resetDefaults();
    BuiltInMermaidCache.instance.resetDefaults();
  }

  /// Clears all cached TeX math display lists and compiled Mermaid diagrams,
  /// resetting telemetry counters.
  static void clearCaches() {
    BuiltInMathCache.instance.clear();
    BuiltInMermaidCache.instance.clear();
  }

  /// Releases pending background rendering state and shuts down any active
  /// persistent Mermaid worker isolate without altering cache size budgets or
  /// [usePersistentMermaidIsolate].
  static Future<void> dispose() => BuiltInMermaidCache.instance.dispose();

  /// Whether cold Mermaid diagram compilations reuse a persistent pre-warmed
  /// primary background worker isolate plus bounded lazy auxiliary burst
  /// isolates (`true`, default) instead of spawning one-shot `compute()`
  /// isolates per diagram (`false`).
  ///
  /// When enabled, `1` persistent primary isolate handles sequential work and
  /// up to [maxMermaidConcurrentWorkers] total isolates (`1` primary plus
  /// bounded lazy auxiliary burst isolates that tear down automatically when
  /// idle) serve concurrent bursts. Setting this to `false` immediately shuts
  /// down the primary and any active burst workers so no background isolate
  /// stays alive, and routes subsequent cold Mermaid compilations through
  /// one-shot `compute()`.
  static bool get usePersistentMermaidIsolate =>
      BuiltInMermaidCache.instance.usePersistentMermaidIsolate;

  /// Configures whether cold Mermaid diagram compilations reuse the persistent
  /// primary background worker isolate and bounded auxiliary burst pool or fall
  /// back to one-shot `compute()` isolates.
  static set usePersistentMermaidIsolate(bool value) {
    BuiltInMermaidCache.instance.usePersistentMermaidIsolate = value;
  }

  /// Whether the persistent primary or any auxiliary burst Mermaid worker
  /// isolate is currently active or starting up.
  static bool get isMermaidWorkerActive =>
      BuiltInMermaidCache.instance.isMermaidWorkerActive;

  /// Default maximum concurrent Mermaid background worker isolates (`1`
  /// persistent primary isolate plus up to `3` lazy auxiliary burst isolates
  /// on IO platforms, and `1` on web).
  static int get defaultMaxMermaidConcurrentWorkers =>
      BuiltInMermaidCache.defaultMaxMermaidConcurrentWorkers;

  /// Maximum total worker isolates permitted across the persistent primary
  /// Mermaid worker and any lazily spawned auxiliary burst workers.
  ///
  /// Setting this to `1` disables auxiliary burst workers while preserving the
  /// persistent primary worker isolate. Throws [RangeError] if set below `1`.
  static int get maxMermaidConcurrentWorkers =>
      BuiltInMermaidCache.maxMermaidConcurrentWorkers;

  /// Configures [maxMermaidConcurrentWorkers], shutting down idle excess burst
  /// workers immediately and retiring busy excess burst workers after their
  /// active job completes.
  static set maxMermaidConcurrentWorkers(int value) {
    BuiltInMermaidCache.maxMermaidConcurrentWorkers = value;
  }

  /// Current number of active or starting Mermaid background worker isolates
  /// across the persistent primary worker and any active auxiliary burst
  /// workers.
  static int get activeMermaidWorkerCount =>
      BuiltInMermaidCache.activeMermaidWorkerCount;

  /// Number of synchronous TeX math layout evaluations executed on cache misses.
  static int get mathLayoutCount => BuiltInMathCache.instance.layoutCount;

  /// Number of built-in math lookups satisfied from cache without relayout.
  static int get mathCacheHitCount => BuiltInMathCache.instance.hitCount;

  /// Current number of cached built-in math entries.
  static int get mathCacheLength => BuiltInMathCache.instance.length;

  /// Estimated retained bytes across all currently cached math entries.
  static int get mathCacheBytes => BuiltInMathCache.instance.currentBytes;

  /// Configured maximum entry count for the built-in math LRU cache.
  static int get mathMaxEntries => BuiltInMathCache.instance.maxEntries;

  /// Configured maximum retained byte budget for the built-in math LRU cache.
  static int get mathMaxBytes => BuiltInMathCache.instance.maxBytes;

  /// Number of cold Mermaid diagram compilations executed.
  static int get mermaidRenderCount => BuiltInMermaidCache.instance.renderCount;

  /// Number of Mermaid diagram lookups satisfied from cache without recompiling.
  static int get mermaidCacheHitCount => BuiltInMermaidCache.instance.hitCount;

  /// Current number of cached compiled Mermaid diagrams.
  static int get mermaidCacheLength => BuiltInMermaidCache.instance.length;

  /// Estimated retained bytes across all currently cached Mermaid entries.
  static int get mermaidCacheBytes => BuiltInMermaidCache.instance.currentBytes;

  /// Configured maximum entry count for the built-in Mermaid LRU cache.
  static int get mermaidMaxEntries => BuiltInMermaidCache.instance.maxEntries;

  /// Configured maximum retained byte budget for the built-in Mermaid LRU cache.
  static int get mermaidMaxBytes => BuiltInMermaidCache.instance.maxBytes;

  /// Test-only hook forcing Mermaid rendering to use background worker or
  /// `compute` isolates even under `TestWidgetsFlutterBinding`.
  @visibleForTesting
  static bool get debugForceAsyncMermaidInTests =>
      BuiltInMermaidCache.instance.debugForceAsyncInTests;

  /// Sets whether Mermaid rendering uses real background isolates during
  /// `TestWidgetsFlutterBinding` tests.
  @visibleForTesting
  static set debugForceAsyncMermaidInTests(bool value) {
    BuiltInMermaidCache.instance.debugForceAsyncInTests = value;
  }
}
