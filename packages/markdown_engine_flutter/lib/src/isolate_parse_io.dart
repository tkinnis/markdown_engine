import 'dart:isolate';

import 'package:markdown_engine/markdown_engine.dart';

/// Parses [source] with [engine] and [options] inside a background [Isolate],
/// falling back synchronously if spawning an isolate fails with
/// [IsolateSpawnException].
Future<MarkdownDocument> parseMarkdownInBackground(
  MarkdownEngine engine,
  String source,
  MarkdownOptions options,
) {
  return parseMarkdownWithIsolateRunner(engine, source, options);
}

/// Executes [MarkdownEngine.parse] via [runIsolate] (defaulting to
/// [Isolate.run]), falling back to synchronous execution on
/// [IsolateSpawnException].
Future<MarkdownDocument> parseMarkdownWithIsolateRunner(
  MarkdownEngine engine,
  String source,
  MarkdownOptions options, {
  Future<MarkdownDocument> Function(MarkdownDocument Function() computation)?
  runIsolate,
}) async {
  final Future<MarkdownDocument> Function(MarkdownDocument Function()) runner =
      runIsolate ?? Isolate.run<MarkdownDocument>;
  try {
    return await runner(() => engine.parse(source, options: options));
  } on IsolateSpawnException {
    return engine.parse(source, options: options);
  }
}
