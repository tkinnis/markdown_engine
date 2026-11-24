import 'package:meta/meta.dart';

import 'ast.dart';
import 'block_parser.dart';
import 'document.dart';
import 'inline_parser.dart';
import 'options.dart';

/// Stateless entry point for parsing Markdown text into a [MarkdownDocument]
/// and exporting HTML or plain text outputs.
@immutable
final class MarkdownEngine {
  /// Creates a [MarkdownEngine] with optional [defaultOptions].
  const MarkdownEngine({this.defaultOptions = const MarkdownOptions()});

  /// Default options applied when per-call options are omitted.
  final MarkdownOptions defaultOptions;

  /// Parses [source] into an immutable [MarkdownDocument].
  MarkdownDocument parse(String source, {MarkdownOptions? options}) {
    final MarkdownOptions effective = options ?? defaultOptions;
    if (source.length > effective.maxInputLength) {
      throw RangeError.value(
        source.length,
        'source.length',
        'Input exceeds maxInputLength (${effective.maxInputLength}).',
      );
    }

    if (source.isEmpty) {
      return createFrozenDocument(
        source: source,
        options: effective,
        blocks: emptyFrozenBlockList,
        outline: const <MarkdownOutlineItem>[],
        footnotes: const <FootnoteDefinitionNode>[],
        remoteImageAddresses: const <String>[],
        normalizedSource: '',
        html: '',
      );
    }

    final Phase1Result phase1 = parseBlocks(source, effective);
    final Phase2Result phase2 = parseInlines(phase1, effective);

    return createFrozenDocument(
      source: source,
      options: effective,
      blocks: phase2.blocks,
      frontmatter: phase1.frontmatter?.frontmatter,
      footnotes: phase2.footnotes,
      linkDefinitions: phase1.linkDefinitions,
      abbreviations: phase1.abbreviations,
      normalizedSource: phase1.normalizedSource,
      idGeneration: 0,
    );
  }

  /// Parses [source] and renders it directly to HTML.
  String renderToHtml(String source, {MarkdownOptions? options}) {
    return parse(source, options: options).toHtml();
  }

  /// Parses [source] and returns normalized plain text.
  String toPlainText(String source, {MarkdownOptions? options}) {
    return parse(source, options: options).toPlainText();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownEngine && defaultOptions == other.defaultOptions;

  @override
  int get hashCode => defaultOptions.hashCode;
}
