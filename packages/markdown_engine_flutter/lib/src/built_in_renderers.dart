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

  /// Clears all cached TeX math display lists and compiled Mermaid diagrams,
  /// resetting telemetry counters.
  static void clearCaches() {
    BuiltInMathCache.instance.clear();
    BuiltInMermaidCache.instance.clear();
  }

  /// Releases pending background rendering state cleanly.
  static Future<void> dispose() => BuiltInMermaidCache.instance.dispose();

  /// Number of synchronous TeX math layout evaluations executed on cache misses.
  static int get mathLayoutCount => BuiltInMathCache.instance.layoutCount;

  /// Number of built-in math lookups satisfied from cache without relayout.
  static int get mathCacheHitCount => BuiltInMathCache.instance.hitCount;

  /// Current number of cached built-in math entries.
  static int get mathCacheLength => BuiltInMathCache.instance.length;

  /// Number of cold Mermaid diagram compilations executed.
  static int get mermaidRenderCount => BuiltInMermaidCache.instance.renderCount;

  /// Number of Mermaid diagram lookups satisfied from cache without recompiling.
  static int get mermaidCacheHitCount => BuiltInMermaidCache.instance.hitCount;

  /// Current number of cached compiled Mermaid diagrams.
  static int get mermaidCacheLength => BuiltInMermaidCache.instance.length;

  /// Test-only hook forcing Mermaid rendering to use background `compute`
  /// isolates even under `TestWidgetsFlutterBinding`.
  @visibleForTesting
  static bool get debugForceAsyncMermaidInTests =>
      BuiltInMermaidCache.instance.debugForceAsyncInTests;

  @visibleForTesting
  static set debugForceAsyncMermaidInTests(bool value) {
    BuiltInMermaidCache.instance.debugForceAsyncInTests = value;
  }
}
