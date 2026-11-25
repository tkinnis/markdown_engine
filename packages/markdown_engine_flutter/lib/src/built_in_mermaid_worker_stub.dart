import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:pele_dart/pele_dart.dart' as pele;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

/// Compiled `vector_graphics` Mermaid payload or structured failure returned
/// by [PersistentMermaidWorker] or [compileMermaidCompute].
typedef MermaidWorkerReply = ({
  Uint8List? compiledBytes,
  String? svg,
  double width,
  double height,
  String? semanticsLabel,
  String? errorCode,
  String? errorMessage,
  bool cacheable,
});

/// Primitive-only isolate-safe serialization record for [pele.PelePalette].
typedef SerializedPelePalette = ({
  String bg,
  String fg,
  String? fgOnLight,
  String? fgOnDark,
  String? muted,
  String? line,
  String? surface,
  String surfaceAlt,
  String? border,
  String? accent,
  String? code,
  String critical,
  double radius,
  double strokeWidth,
  double thickStrokeWidth,
  double hairlineStrokeWidth,
  String fontFamily,
  String monoFontFamily,
  List<String> colors,
});

/// Serializes [palette] into an isolate-safe primitive record.
SerializedPelePalette encodePelePalette(pele.PelePalette palette) {
  return (
    bg: palette.bg,
    fg: palette.fg,
    fgOnLight: palette.fgOnLight,
    fgOnDark: palette.fgOnDark,
    muted: palette.muted,
    line: palette.line,
    surface: palette.surface,
    surfaceAlt: palette.surfaceAlt,
    border: palette.border,
    accent: palette.accent,
    code: palette.code,
    critical: palette.critical,
    radius: palette.radius,
    strokeWidth: palette.strokeWidth,
    thickStrokeWidth: palette.thickStrokeWidth,
    hairlineStrokeWidth: palette.hairlineStrokeWidth,
    fontFamily: palette.fontFamily,
    monoFontFamily: palette.monoFontFamily,
    colors: List<String>.of(palette.colors, growable: false),
  );
}

/// Reconstructs a [pele.PelePalette] from [data].
pele.PelePalette decodePelePalette(SerializedPelePalette data) {
  return pele.PelePalette(
    bg: data.bg,
    fg: data.fg,
    fgOnLight: data.fgOnLight,
    fgOnDark: data.fgOnDark,
    muted: data.muted,
    line: data.line,
    surface: data.surface,
    surfaceAlt: data.surfaceAlt,
    border: data.border,
    accent: data.accent,
    code: data.code,
    critical: data.critical,
    radius: data.radius,
    strokeWidth: data.strokeWidth,
    thickStrokeWidth: data.thickStrokeWidth,
    hairlineStrokeWidth: data.hairlineStrokeWidth,
    fontFamily: data.fontFamily,
    monoFontFamily: data.monoFontFamily,
    colors: data.colors,
  );
}

final RegExp _ariaLabelRegex = RegExp(r'\baria-label="([^"]+)"');

String? _extractAriaLabel(String svg) {
  final RegExpMatch? match = _ariaLabelRegex.firstMatch(svg);
  if (match == null) {
    return null;
  }
  final String? raw = match.group(1)?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', '\'')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// Synchronously renders Mermaid [code] with [palette] via `pele_dart` and
/// compiles the flattened SVG into `vector_graphics` bytes.
MermaidWorkerReply compileMermaidSync(String code, pele.PelePalette palette) {
  try {
    final pele.RenderResult rendered = pele.render(
      code,
      pele.RenderOptions(
        outputMode: pele.SvgOutputMode.flattened,
        palette: palette,
      ),
    );
    final Uint8List compiled = vg.encodeSvg(
      xml: rendered.svg,
      debugName: 'mermaid',
      theme: const vg.SvgTheme(),
      enableClippingOptimizer: false,
      enableMaskingOptimizer: false,
      enableOverdrawOptimizer: false,
    );
    final double safeWidth = (rendered.width.isFinite && rendered.width > 0.0)
        ? rendered.width
        : 320.0;
    final double safeHeight =
        (rendered.height.isFinite && rendered.height > 0.0)
        ? rendered.height
        : 180.0;
    final String label =
        _extractAriaLabel(rendered.svg) ?? '${rendered.type} diagram';
    return (
      compiledBytes: compiled,
      svg: rendered.svg,
      width: safeWidth,
      height: safeHeight,
      semanticsLabel: label,
      errorCode: null,
      errorMessage: null,
      cacheable: true,
    );
  } on pele.PeleError catch (error) {
    return (
      compiledBytes: null,
      svg: null,
      width: 0.0,
      height: 0.0,
      semanticsLabel: null,
      errorCode: error.code,
      errorMessage: error.message,
      cacheable: true,
    );
  } on Object catch (error) {
    return (
      compiledBytes: null,
      svg: null,
      width: 0.0,
      height: 0.0,
      semanticsLabel: null,
      errorCode: 'engineFailed',
      errorMessage: 'Failed to render Mermaid diagram: $error',
      cacheable: true,
    );
  }
}

MermaidWorkerReply _compileMermaidComputeEntry(
  (String code, SerializedPelePalette palette) request,
) {
  return compileMermaidSync(request.$1, decodePelePalette(request.$2));
}

/// Compiles Mermaid [code] against [palette] using a one-shot `compute` call.
Future<MermaidWorkerReply> compileMermaidCompute(
  String code,
  pele.PelePalette palette,
) {
  return compute<(String, SerializedPelePalette), MermaidWorkerReply>(
    _compileMermaidComputeEntry,
    (code, encodePelePalette(palette)),
  );
}

/// Web-safe stub for [PersistentMermaidWorker] on platforms without
/// `dart:io` isolate pools, delegating Mermaid compilation through `compute`.
final class PersistentMermaidWorker {
  /// Default maximum concurrent Mermaid worker isolates (`1` on stub
  /// platforms).
  static const int defaultMaxConcurrentWorkers = 1;

  int _maxConcurrentWorkers = defaultMaxConcurrentWorkers;

  /// Always `false` on platforms without persistent background isolates.
  bool get isActive => false;

  /// Always `0` on platforms without persistent background isolates.
  int get activeWorkerCount => 0;

  /// Maximum total worker isolates permitted across the primary isolate and
  /// auxiliary burst isolates.
  ///
  /// Throws [RangeError] if set to a value less than `1`.
  int get maxConcurrentWorkers => _maxConcurrentWorkers;

  set maxConcurrentWorkers(int value) {
    if (value < 1) {
      throw RangeError.value(
        value,
        'maxConcurrentWorkers',
        'Must be at least 1.',
      );
    }
    _maxConcurrentWorkers = value;
  }

  /// Primes Mermaid diagram compilation via `compute`.
  Future<void> warmUp() async {
    await compileMermaidCompute(
      'flowchart LR\n  A --> B',
      pele.PelePalette.light,
    );
  }

  /// Compiles Mermaid [code] against [palette] through `compute`.
  Future<MermaidWorkerReply> compile(String code, pele.PelePalette palette) {
    return compileMermaidCompute(code, palette);
  }

  /// No-op on platforms without a persistent background isolate.
  Future<void> shutdown() async {}

  /// Test-only primary isolate identity (always `null` on stub platforms).
  @visibleForTesting
  int? get debugIsolateIdentity => null;

  /// Test-only active worker isolate identities (always empty on stub
  /// platforms).
  @visibleForTesting
  List<int> get debugWorkerIsolateIdentities => const <int>[];

  /// Test-only idle timeout for auxiliary burst workers (unused on stub
  /// platforms).
  @visibleForTesting
  Duration debugBurstWorkerIdleTimeout = const Duration(seconds: 15);

  /// Test-only hook (no-op on platforms without `dart:isolate`).
  @visibleForTesting
  void debugKillIsolateWithoutReset() {}

  /// Test-only hook (no-op on platforms without `dart:isolate`).
  @visibleForTesting
  void debugTriggerUncaughtError() {}

  /// Test-only callback hook (unused on platforms without `dart:isolate`).
  @visibleForTesting
  Object? Function({required bool isPrimary})? debugSpawnErrorInjector;
}
