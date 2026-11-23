import 'package:markdown_engine/markdown_engine.dart';

/// Fallback async parser used on platforms without `dart:isolate` (such as Web).
Future<MarkdownDocument> parseMarkdownInBackground(
  MarkdownEngine engine,
  String source,
  MarkdownOptions options,
) {
  return Future<MarkdownDocument>.microtask(
    () => engine.parse(source, options: options),
  );
}
