import 'package:meta/meta.dart';

import 'ast.dart';
import 'html_renderer.dart';
import 'options.dart';

/// Immutable parsed Markdown document containing original source, effective
/// options, AST blocks, frontmatter, outline, footnotes, link definitions, and
/// export helpers.
@immutable
final class MarkdownDocument {
  /// Creates a parsed [MarkdownDocument].
  const MarkdownDocument({
    required this.source,
    this.options = const MarkdownOptions(),
    List<MarkdownBlockNode> blocks = const <MarkdownBlockNode>[],
    this.frontmatter,
    List<MarkdownOutlineItem> outline = const <MarkdownOutlineItem>[],
    List<FootnoteDefinitionNode> footnotes = const <FootnoteDefinitionNode>[],
    List<String> remoteImageAddresses = const <String>[],
    Map<String, MarkdownLinkDefinition> linkDefinitions =
        const <String, MarkdownLinkDefinition>{},
    String? html,
    // ignore: prefer_initializing_formals
  }) : _blocks = blocks,
       _outline = outline,
       _footnotes = footnotes,
       _remoteImageAddresses = remoteImageAddresses,
       _linkDefinitions = linkDefinitions,
       _html = html;

  /// Original Markdown source string passed to the parser.
  final String source;

  /// Effective [MarkdownOptions] used when parsing [source].
  final MarkdownOptions options;

  final List<MarkdownBlockNode> _blocks;

  /// Extracted YAML or TOML frontmatter, if present and enabled.
  final MarkdownFrontmatter? frontmatter;

  final List<MarkdownOutlineItem> _outline;
  final List<FootnoteDefinitionNode> _footnotes;
  final List<String> _remoteImageAddresses;
  final Map<String, MarkdownLinkDefinition> _linkDefinitions;
  final String? _html;

  /// Ordered top-level AST block nodes produced by parsing.
  List<MarkdownBlockNode> get blocks =>
      List<MarkdownBlockNode>.unmodifiable(_blocks);

  /// Document heading outline entries in source order.
  List<MarkdownOutlineItem> get outline =>
      List<MarkdownOutlineItem>.unmodifiable(_outline);

  /// Footnote definitions parsed from the document.
  List<FootnoteDefinitionNode> get footnotes =>
      List<FootnoteDefinitionNode>.unmodifiable(_footnotes);

  /// Deduplicated remote (`http:`/`https:`) image addresses referenced in AST.
  List<String> get remoteImageAddresses =>
      List<String>.unmodifiable(_remoteImageAddresses);

  /// Resolved link reference definitions keyed by normalized label.
  Map<String, MarkdownLinkDefinition> get linkDefinitions =>
      Map<String, MarkdownLinkDefinition>.unmodifiable(_linkDefinitions);

  /// Whether the document contains no parsed block content.
  bool get isEmpty => _blocks.isEmpty;

  /// Renders this document into CommonMark/GFM HTML output.
  String toHtml() {
    final String? cachedHtml = _html;
    if (cachedHtml != null) {
      return cachedHtml;
    }
    return HtmlRenderer(options: options).render(_blocks);
  }

  /// Extracts normalized plain text from this document.
  String toPlainText() {
    if (_blocks.isEmpty) {
      return '';
    }
    final List<String> parts = <String>[];
    for (final MarkdownBlockNode block in _blocks) {
      final String text = block.toPlainText();
      if (text.isNotEmpty) {
        parts.add(text);
      }
    }
    return parts.join('\n\n');
  }

  /// Serializes this document metadata and AST structure into a JSON-compatible
  /// map.
  Map<String, Object?> toJson() => <String, Object?>{
    'blockCount': _blocks.length,
    if (frontmatter != null)
      'frontmatter': <String, Object?>{
        'format': frontmatter!.format,
        'entries': frontmatter!.entries,
      },
    'outline': _outline
        .map(
          (MarkdownOutlineItem item) => <String, Object?>{
            'text': item.text,
            'level': item.level,
            'line': item.line,
            'slug': item.slug,
          },
        )
        .toList(growable: false),
    'footnotes': _footnotes
        .map(
          (FootnoteDefinitionNode fn) => <String, Object?>{
            'label': fn.label,
            'index': fn.index,
            'referenceCount': fn.referenceCount,
          },
        )
        .toList(growable: false),
    'remoteImageAddresses': _remoteImageAddresses,
    'html': toHtml(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownDocument &&
          source == other.source &&
          options == other.options &&
          frontmatter == other.frontmatter &&
          _listEquals(_blocks, other._blocks) &&
          _listEquals(_outline, other._outline) &&
          _listEquals(_footnotes, other._footnotes) &&
          _listEquals(_remoteImageAddresses, other._remoteImageAddresses) &&
          _mapEquals(_linkDefinitions, other._linkDefinitions) &&
          _html == other._html;

  @override
  int get hashCode => Object.hash(
    source,
    options,
    frontmatter,
    Object.hashAll(_blocks),
    Object.hashAll(_outline),
    Object.hashAll(_footnotes),
    Object.hashAll(_remoteImageAddresses),
    Object.hashAllUnordered(
      _linkDefinitions.entries.map(
        (MapEntry<String, MarkdownLinkDefinition> e) =>
            Object.hash(e.key, e.value),
      ),
    ),
    _html,
  );

  @override
  String toString() =>
      'MarkdownDocument(blocks: ${_blocks.length}, length: ${source.length})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<K, V> entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
