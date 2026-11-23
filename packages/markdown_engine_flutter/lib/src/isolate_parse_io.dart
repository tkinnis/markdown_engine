import 'dart:isolate';

import 'package:markdown_engine/markdown_engine.dart';

/// Parses [source] with [engine] and [options] inside a background [Isolate].
Future<MarkdownDocument> parseMarkdownInBackground(
  MarkdownEngine engine,
  String source,
  MarkdownOptions options,
) {
  return Isolate.run<MarkdownDocument>(
    () => engine.parse(source, options: options),
  );
}
