import 'dart:collection';

import 'package:meta/meta.dart';

import 'ast.dart';
import 'ast_walkers.dart';
import 'html_renderer.dart';
import 'options.dart';

/// Immutable parsed Markdown document containing original source, effective
/// options, AST blocks, frontmatter, outline, footnotes, link definitions,
/// abbreviations, and export helpers.
@immutable
final class MarkdownDocument {
  /// Creates a parsed [MarkdownDocument].
  ///
  /// When [abbreviations], [normalizedSource], or [idGeneration] are supplied
  /// by the parser, incremental updates reuse them directly without
  /// re-normalizing [source] or scanning block IDs.
  const MarkdownDocument({
    required String source,
    this.options = const MarkdownOptions(),
    List<MarkdownBlockNode> blocks = const <MarkdownBlockNode>[],
    this.frontmatter,
    List<MarkdownOutlineItem> outline = const <MarkdownOutlineItem>[],
    List<FootnoteDefinitionNode> footnotes = const <FootnoteDefinitionNode>[],
    List<String> remoteImageAddresses = const <String>[],
    Map<String, MarkdownLinkDefinition> linkDefinitions =
        const <String, MarkdownLinkDefinition>{},
    Map<String, String> abbreviations = const <String, String>{},
    String? normalizedSource,
    String? html,
    int? idGeneration,
    // ignore: prefer_initializing_formals
  }) : _source = source,
       _sourceDeferred = false,
       _blocks = blocks,
       _outline = outline,
       _footnotes = footnotes,
       _remoteImageAddresses = remoteImageAddresses,
       _linkDefinitions = linkDefinitions,
       _abbreviations = abbreviations,
       _normalizedSource = normalizedSource ?? '',
       _normDeferred = normalizedSource == null,
       _html = html,
       _idGeneration = idGeneration ?? -1,
       _collectionsFrozen = false,
       _lazy = null;

  const MarkdownDocument._frozen({
    required String? source,
    required this.options,
    required List<MarkdownBlockNode> blocks,
    required this.frontmatter,
    required List<MarkdownOutlineItem> outline,
    required List<FootnoteDefinitionNode> footnotes,
    required List<String> remoteImageAddresses,
    required Map<String, MarkdownLinkDefinition> linkDefinitions,
    required Map<String, String> abbreviations,
    required String? normalizedSource,
    required String? html,
    required int? idGeneration,
    required _DocumentLazyState? lazy,
  }) : _source = source ?? '',
       _sourceDeferred = source == null,
       _blocks = blocks,
       _outline = outline,
       _footnotes = footnotes,
       _remoteImageAddresses = remoteImageAddresses,
       _linkDefinitions = linkDefinitions,
       _abbreviations = abbreviations,
       _normalizedSource = normalizedSource ?? '',
       _normDeferred = normalizedSource == null,
       _html = html,
       _idGeneration = idGeneration ?? -1,
       _collectionsFrozen = true,
       _lazy = lazy;

  final String _source;
  final bool _sourceDeferred;

  /// Original Markdown source string passed to the parser.
  String get source => _sourceDeferred ? _lazy!.resolveSource() : _source;

  /// Effective [MarkdownOptions] used when parsing [source].
  final MarkdownOptions options;

  final List<MarkdownBlockNode> _blocks;

  /// Extracted YAML or TOML frontmatter, if present and enabled.
  final MarkdownFrontmatter? frontmatter;

  final List<MarkdownOutlineItem> _outline;
  final List<FootnoteDefinitionNode> _footnotes;
  final List<String> _remoteImageAddresses;
  final Map<String, MarkdownLinkDefinition> _linkDefinitions;
  final Map<String, String> _abbreviations;
  final String _normalizedSource;
  final bool _normDeferred;
  final String? _html;
  final int _idGeneration;
  final bool _collectionsFrozen;
  final _DocumentLazyState? _lazy;

  /// Ordered top-level AST block nodes produced by parsing.
  List<MarkdownBlockNode> get blocks =>
      _collectionsFrozen ? _blocks : _unmodifiableList(_blocks);

  /// Document heading outline entries in source order.
  List<MarkdownOutlineItem> get outline {
    final _DocumentLazyState? lazy = _lazy;
    if (lazy != null && lazy.lazyOutline) {
      return lazy.resolveOutline(_blocks, options);
    }
    return _collectionsFrozen ? _outline : _unmodifiableList(_outline);
  }

  /// Footnote definitions parsed from the document.
  List<FootnoteDefinitionNode> get footnotes =>
      _collectionsFrozen ? _footnotes : _unmodifiableList(_footnotes);

  /// Deduplicated remote (`http:`/`https:`/`//`) image addresses referenced in AST.
  List<String> get remoteImageAddresses {
    final _DocumentLazyState? lazy = _lazy;
    if (lazy != null && lazy.lazyRemoteImages) {
      return lazy.resolveRemoteImages(_blocks, options);
    }
    return _collectionsFrozen
        ? _remoteImageAddresses
        : _unmodifiableList(_remoteImageAddresses);
  }

  /// Resolved link reference definitions keyed by normalized label.
  Map<String, MarkdownLinkDefinition> get linkDefinitions => _collectionsFrozen
      ? _linkDefinitions
      : _unmodifiableMap(_linkDefinitions);

  /// Extracted abbreviation definitions (`*[ABBR]: Title`).
  Map<String, String> get abbreviations =>
      _collectionsFrozen ? _abbreviations : _unmodifiableMap(_abbreviations);

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
    for (int i = 0; i < _blocks.length; i++) {
      final String text = _blocks[i].toPlainText();
      if (text.isNotEmpty) {
        parts.add(text);
      }
    }
    return parts.join('\n\n');
  }

  /// Serializes this document metadata and AST structure into a JSON-compatible
  /// map.
  Map<String, Object?> toJson() {
    final List<MarkdownOutlineItem> resolvedOutline = outline;
    final List<String> resolvedRemoteImages = remoteImageAddresses;
    return <String, Object?>{
      'blockCount': _blocks.length,
      if (frontmatter != null)
        'frontmatter': <String, Object?>{
          'format': frontmatter!.format,
          'entries': frontmatter!.entries,
        },
      'outline': resolvedOutline
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
      'remoteImageAddresses': resolvedRemoteImages,
      'html': toHtml(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownDocument &&
          source == other.source &&
          options == other.options &&
          frontmatter == other.frontmatter &&
          _listEquals(_blocks, other._blocks) &&
          _listEquals(outline, other.outline) &&
          _listEquals(_footnotes, other._footnotes) &&
          _listEquals(remoteImageAddresses, other.remoteImageAddresses) &&
          _mapEquals(_linkDefinitions, other._linkDefinitions) &&
          _mapEquals(_abbreviations, other._abbreviations) &&
          _html == other._html;

  @override
  int get hashCode => Object.hash(
    source,
    options,
    frontmatter,
    Object.hashAll(_blocks),
    Object.hashAll(outline),
    Object.hashAll(_footnotes),
    Object.hashAll(remoteImageAddresses),
    Object.hashAllUnordered(
      _linkDefinitions.entries.map(
        (MapEntry<String, MarkdownLinkDefinition> e) =>
            Object.hash(e.key, e.value),
      ),
    ),
    Object.hashAllUnordered(
      _abbreviations.entries.map(
        (MapEntry<String, String> e) => Object.hash(e.key, e.value),
      ),
    ),
    _html,
  );

  @override
  String toString() {
    final int len = _sourceDeferred ? _lazy!.sourceLength : _source.length;
    return 'MarkdownDocument(blocks: ${_blocks.length}, length: $len)';
  }
}

final class _DocumentLazyState {
  _DocumentLazyState({
    List<String>? sourceChunks,
    this.sourceChunkCount = 0,
    this.sourceLength = 0,
    required this.lazyOutline,
    required this.lazyRemoteImages,
  }) : sourceChunks = sourceChunks ?? _emptySourceChunks;

  static final List<String> _emptySourceChunks = <String>[];

  final List<String> sourceChunks;
  final int sourceChunkCount;
  final int sourceLength;
  final bool lazyOutline;
  final bool lazyRemoteImages;
  String? _resolvedSource;
  List<MarkdownOutlineItem>? _resolvedOutline;
  List<String>? _resolvedRemoteImages;

  String resolveSource() {
    final String? cached = _resolvedSource;
    if (cached != null) {
      return cached;
    }
    if (sourceChunkCount == 0) {
      return _resolvedSource = '';
    }
    final List<String> chunks = sourceChunks;
    if (sourceChunkCount == 1) {
      return _resolvedSource = chunks[0];
    }
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < sourceChunkCount; i++) {
      out.write(chunks[i]);
    }
    return _resolvedSource = out.toString();
  }

  List<MarkdownOutlineItem> resolveOutline(
    List<MarkdownBlockNode> blocks,
    MarkdownOptions options,
  ) {
    final List<MarkdownOutlineItem>? cached = _resolvedOutline;
    if (cached != null) {
      return cached;
    }
    return _resolvedOutline = collectOutlineFromBlocks(
      blocks,
      options: options,
    );
  }

  List<String> resolveRemoteImages(
    List<MarkdownBlockNode> blocks,
    MarkdownOptions options,
  ) {
    final List<String>? cached = _resolvedRemoteImages;
    if (cached != null) {
      return cached;
    }
    return _resolvedRemoteImages = collectRemoteImagesFromBlocks(
      blocks,
      options: options,
    );
  }
}

/// Package-internal constructor creating a frozen [MarkdownDocument] with
/// optional lazy [source], [outline], and [remoteImageAddresses] computation.
MarkdownDocument createFrozenDocument({
  String? source,
  List<String>? sourceChunks,
  int sourceChunkCount = 0,
  int sourceLength = 0,
  MarkdownOptions options = const MarkdownOptions(),
  List<MarkdownBlockNode>? blocks,
  MarkdownFrontmatter? frontmatter,
  List<MarkdownOutlineItem>? outline,
  List<FootnoteDefinitionNode> footnotes = const <FootnoteDefinitionNode>[],
  List<String>? remoteImageAddresses,
  Map<String, MarkdownLinkDefinition> linkDefinitions =
      const <String, MarkdownLinkDefinition>{},
  Map<String, String> abbreviations = const <String, String>{},
  String? normalizedSource,
  String? html,
  int? idGeneration,
}) {
  final List<MarkdownBlockNode> resolvedBlocks = blocks ?? emptyFrozenBlockList;
  final bool lazyOutline = outline == null && resolvedBlocks.isNotEmpty;
  final bool lazyRemoteImages =
      remoteImageAddresses == null && resolvedBlocks.isNotEmpty;
  final bool needsLazy = source == null || lazyOutline || lazyRemoteImages;
  return MarkdownDocument._frozen(
    source: source,
    options: options,
    blocks: resolvedBlocks,
    frontmatter: frontmatter,
    outline: outline ?? const <MarkdownOutlineItem>[],
    footnotes: footnotes,
    remoteImageAddresses: remoteImageAddresses ?? const <String>[],
    linkDefinitions: linkDefinitions,
    abbreviations: abbreviations,
    normalizedSource: normalizedSource,
    html: html,
    idGeneration: idGeneration,
    lazy: needsLazy
        ? _DocumentLazyState(
            sourceChunks: sourceChunks,
            sourceChunkCount: sourceChunkCount,
            sourceLength: sourceLength,
            lazyOutline: lazyOutline,
            lazyRemoteImages: lazyRemoteImages,
          )
        : null,
  );
}

/// Fast-path internal constructor for streaming document snapshots.
@pragma('vm:prefer-inline')
MarkdownDocument createStreamingDocument({
  String? source,
  List<String>? sourceChunks,
  int sourceChunkCount = 0,
  int sourceLength = 0,
  required MarkdownOptions options,
  required List<MarkdownBlockNode> blocks,
  required MarkdownFrontmatter? frontmatter,
  bool? hasBlocks,
  List<FootnoteDefinitionNode> footnotes = const <FootnoteDefinitionNode>[],
  Map<String, MarkdownLinkDefinition> linkDefinitions =
      const <String, MarkdownLinkDefinition>{},
  Map<String, String> abbreviations = const <String, String>{},
  String? normalizedSource,
}) {
  final bool lazyMeta = hasBlocks ?? blocks.isNotEmpty;
  return MarkdownDocument._frozen(
    source: source,
    options: options,
    blocks: blocks,
    frontmatter: frontmatter,
    outline: const <MarkdownOutlineItem>[],
    footnotes: footnotes,
    remoteImageAddresses: const <String>[],
    linkDefinitions: linkDefinitions,
    abbreviations: abbreviations,
    normalizedSource: normalizedSource,
    html: null,
    idGeneration: null,
    lazy: _DocumentLazyState(
      sourceChunks: sourceChunks,
      sourceChunkCount: sourceChunkCount,
      sourceLength: sourceLength,
      lazyOutline: lazyMeta,
      lazyRemoteImages: lazyMeta,
    ),
  );
}

/// Returns whether [doc]'s outline has already been eagerly or lazily resolved.
bool hasResolvedDocumentOutline(MarkdownDocument doc) {
  final _DocumentLazyState? lazy = doc._lazy;
  return lazy == null || !lazy.lazyOutline || lazy._resolvedOutline != null;
}

/// Returns whether [doc]'s remote image list has already been resolved.
bool hasResolvedDocumentRemoteImages(MarkdownDocument doc) {
  final _DocumentLazyState? lazy = doc._lazy;
  return lazy == null ||
      !lazy.lazyRemoteImages ||
      lazy._resolvedRemoteImages != null;
}

/// Package-internal accessor returning the cached normalized source string if
/// previously computed for [doc].
String? cachedNormalizedSource(MarkdownDocument doc) =>
    doc._normDeferred ? null : doc._normalizedSource;

/// Package-internal accessor returning the cached incremental ID generation
/// counter for [doc], or `null` if constructed externally.
int? cachedIdGeneration(MarkdownDocument doc) =>
    doc._idGeneration < 0 ? null : doc._idGeneration;

/// Package-internal accessor returning the raw top-level blocks list of [doc].
List<MarkdownBlockNode> rawDocumentBlocks(MarkdownDocument doc) => doc._blocks;

/// Package-internal accessor returning the raw outline list of [doc].
List<MarkdownOutlineItem> rawDocumentOutline(MarkdownDocument doc) =>
    doc.outline;

/// Package-internal accessor returning the raw remote images list of [doc].
List<String> rawDocumentRemoteImages(MarkdownDocument doc) =>
    doc.remoteImageAddresses;

List<T> _unmodifiableList<T>(List<T> list) {
  if (list.isEmpty) {
    return const <Never>[];
  }
  if (list is UnmodifiableListView<T>) {
    return list;
  }
  return UnmodifiableListView<T>(list);
}

Map<K, V> _unmodifiableMap<K, V>(Map<K, V> map) {
  if (map.isEmpty) {
    return const <Never, Never>{};
  }
  if (map is UnmodifiableMapView<K, V>) {
    return map;
  }
  return UnmodifiableMapView<K, V>(map);
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
