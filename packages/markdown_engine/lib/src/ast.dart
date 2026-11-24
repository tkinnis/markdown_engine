import 'dart:collection';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'slugs.dart';

/// Package-internal mixin making a [ListBase] strictly unmodifiable across all
/// mutating operations (including `sort`, `shuffle`, and `clear`).
mixin PackageUnmodifiableListMixin<T> on ListBase<T> {
  static Never _unsupported() =>
      throw UnsupportedError('Cannot modify an unmodifiable list');

  @override
  void operator []=(int index, T value) => _unsupported();

  @override
  set length(int newLength) => _unsupported();

  @override
  void add(T element) => _unsupported();

  @override
  void addAll(Iterable<T> iterable) => _unsupported();

  @override
  void clear() => _unsupported();

  @override
  void fillRange(int start, int end, [T? fill]) => _unsupported();

  @override
  void insert(int index, T element) => _unsupported();

  @override
  void insertAll(int index, Iterable<T> iterable) => _unsupported();

  @override
  bool remove(Object? element) => _unsupported();

  @override
  T removeAt(int index) => _unsupported();

  @override
  T removeLast() => _unsupported();

  @override
  void removeRange(int start, int end) => _unsupported();

  @override
  void removeWhere(bool Function(T element) test) => _unsupported();

  @override
  void replaceRange(int start, int end, Iterable<T> newContents) =>
      _unsupported();

  @override
  void retainWhere(bool Function(T element) test) => _unsupported();

  @override
  void setAll(int index, Iterable<T> iterable) => _unsupported();

  @override
  void setRange(
    int start,
    int end,
    Iterable<T> iterable, [
    int skipCount = 0,
  ]) => _unsupported();

  @override
  void shuffle([math.Random? random]) => _unsupported();

  @override
  void sort([int Function(T a, T b)? compare]) => _unsupported();
}

/// Compact single-element unmodifiable [List] avoiding both a growable array
/// allocation and an [UnmodifiableListView] wrapper.
final class _SingletonList<T> extends ListBase<T>
    with PackageUnmodifiableListMixin<T> {
  const _SingletonList(this._element);

  final T _element;

  @override
  int get length => 1;

  @override
  T get first => _element;

  @override
  T get last => _element;

  @override
  T get single => _element;

  @override
  bool get isEmpty => false;

  @override
  bool get isNotEmpty => true;

  @override
  T operator [](int index) {
    if (index != 0) {
      throw RangeError.index(index, this, 'index', null, 1);
    }
    return _element;
  }
}

/// Returns an unmodifiable view of [list] in O(1), avoiding redundant wrapping
/// when [list] is already empty, a [_SingletonList], or an [UnmodifiableListView].
List<T> freezeList<T>(List<T> list) {
  if (list.isEmpty) {
    return const <Never>[];
  }
  if (list is _SingletonList<T> || list is UnmodifiableListView<T>) {
    return list;
  }
  if (list.length == 1) {
    return _SingletonList<T>(list[0]);
  }
  return List<T>.unmodifiable(list);
}

/// Returns a single-element unmodifiable [List] containing [element] in one
/// small allocation.
List<T> freezeSingleton<T>(T element) => freezeFreshList<T>(<T>[element]);

/// Shared empty unmodifiable block list preserving a uniform backing list type.
final List<MarkdownBlockNode> emptyFrozenBlockList =
    UnmodifiableListView<MarkdownBlockNode>(<MarkdownBlockNode>[]);

/// Shared empty unmodifiable inline list preserving a uniform backing list type.
final List<MarkdownInlineNode> emptyFrozenInlineList =
    UnmodifiableListView<MarkdownInlineNode>(<MarkdownInlineNode>[]);

/// Shared empty unmodifiable table cell list preserving a uniform backing list type.
final List<TableCellNode> emptyFrozenTableCellList =
    UnmodifiableListView<TableCellNode>(<TableCellNode>[]);

/// Freezes a freshly created, non-escaped [list] into an immutable [List] with
/// minimal allocation overhead.
List<T> freezeFreshList<T>(List<T> list) {
  if (list.isEmpty) {
    return const <Never>[];
  }
  return UnmodifiableListView<T>(list);
}

/// Wraps an already-fixed-length, non-escaped [fixedList] directly in an
/// [UnmodifiableListView] without allocating a duplicate copy.
List<T> wrapFixedUnmodifiableList<T>(List<T> fixedList) {
  if (fixedList.isEmpty) {
    return const <Never>[];
  }
  if (fixedList is _SingletonList<T> || fixedList is UnmodifiableListView<T>) {
    return fixedList;
  }
  if (fixedList.length == 1) {
    return _SingletonList<T>(fixedList[0]);
  }
  return UnmodifiableListView<T>(fixedList);
}

/// Returns an unmodifiable map view of [map] in O(1), avoiding redundant wrapping.
Map<K, V> freezeMap<K, V>(Map<K, V> map) {
  if (map.isEmpty) {
    return const <Never, Never>{};
  }
  if (map is UnmodifiableMapView<K, V>) {
    return map;
  }
  return UnmodifiableMapView<K, V>(Map<K, V>.of(map));
}

List<T> _asUnmodifiableListView<T>(List<T> list) {
  if (list.isEmpty) {
    return const <Never>[];
  }
  if (list is _SingletonList<T> || list is UnmodifiableListView<T>) {
    return list;
  }
  return UnmodifiableListView<T>(list);
}

Map<K, V> _asUnmodifiableMapView<K, V>(Map<K, V> map) {
  if (map.isEmpty) {
    return const <Never, Never>{};
  }
  if (map is UnmodifiableMapView<K, V>) {
    return map;
  }
  return UnmodifiableMapView<K, V>(map);
}

/// Shared lazy batch computing deduplicated heading anchor slugs only when
/// `HeadingNode.slug` or `MarkdownDocument.outline` is actually accessed.
final class HeadingSlugBatch {
  /// Creates a [HeadingSlugBatch], optionally seeded with `initialGenerator`
  /// or a prefix of previously settled heading texts.
  HeadingSlugBatch([
    this._initialGenerator,
    List<String>? seedHeadingTexts,
    this._seedHeadingCount = 0,
  ]) : _seedHeadingTexts = seedHeadingTexts ?? _emptySeedTexts;

  static final List<String> _emptySeedTexts = <String>[];

  HeadingSlugGenerator? _initialGenerator;
  List<String> _seedHeadingTexts;
  final int _seedHeadingCount;
  final List<_LazyHeadingSlug> _entries = <_LazyHeadingSlug>[];
  bool _resolved = false;

  _LazyHeadingSlug _register(String text) {
    final _LazyHeadingSlug entry = _LazyHeadingSlug(this, text);
    _entries.add(entry);
    return entry;
  }

  /// Resolves all registered heading slugs in document order once.
  void resolveAll() {
    if (_resolved) {
      return;
    }
    _resolved = true;
    final HeadingSlugGenerator gen =
        _initialGenerator ?? HeadingSlugGenerator();
    final List<String> seedTexts = _seedHeadingTexts;
    if (_seedHeadingCount > 0 && seedTexts.isNotEmpty) {
      for (int i = 0; i < _seedHeadingCount; i++) {
        gen.generate(seedTexts[i]);
      }
      _seedHeadingTexts = _emptySeedTexts;
    }
    for (int i = 0; i < _entries.length; i++) {
      final _LazyHeadingSlug entry = _entries[i];
      entry._slug = gen.generate(entry._text);
    }
    _entries.clear();
    _initialGenerator = null;
  }
}

final class _LazyHeadingSlug {
  _LazyHeadingSlug(this._batch, this._text);

  final HeadingSlugBatch _batch;
  final String _text;
  String? _slug;

  String get value {
    final String? cached = _slug;
    if (cached != null) {
      return cached;
    }
    _batch.resolveAll();
    return _slug!;
  }
}

/// UTF-16 source offset and 1-based line span for a parsed AST node.
@immutable
final class SourceSpan {
  /// Creates a [SourceSpan].
  const SourceSpan({
    required this.startOffset,
    required this.endOffset,
    required this.startLine,
    required this.endLine,
  }) : assert(startOffset >= 0, 'startOffset must be non-negative'),
       assert(endOffset >= startOffset, 'endOffset must be >= startOffset'),
       assert(startLine >= 0, 'startLine must be non-negative'),
       assert(endLine >= startLine, 'endLine must be >= startLine');

  const SourceSpan._unchecked({
    required this.startOffset,
    required this.endOffset,
    required this.startLine,
    required this.endLine,
  });

  /// Empty synthetic span at offset `0`, line `0`.
  static const SourceSpan zero = SourceSpan._unchecked(
    startOffset: 0,
    endOffset: 0,
    startLine: 0,
    endLine: 0,
  );

  /// Inclusive UTF-16 start offset within the normalized source text.
  final int startOffset;

  /// Exclusive UTF-16 end offset within the normalized source text.
  final int endOffset;

  /// 1-based start line number (or `0` for synthetic nodes).
  final int startLine;

  /// 1-based inclusive end line number (or `0` for synthetic nodes).
  final int endLine;

  /// Length of the spanned slice in UTF-16 code units.
  int get length => endOffset - startOffset;

  /// Returns a shifted copy of this span for incremental AST reuse.
  SourceSpan shift(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return SourceSpan(
      startOffset: startOffset + offsetDelta,
      endOffset: endOffset + offsetDelta,
      startLine: startLine == 0 ? 0 : startLine + lineDelta,
      endLine: endLine == 0 ? 0 : endLine + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceSpan &&
          startOffset == other.startOffset &&
          endOffset == other.endOffset &&
          startLine == other.startLine &&
          endLine == other.endLine;

  @override
  int get hashCode => Object.hash(startOffset, endOffset, startLine, endLine);

  @override
  String toString() =>
      'SourceSpan($startOffset..$endOffset, L$startLine..L$endLine)';
}

/// GitHub-style blockquote alert categories.
enum AlertKind {
  /// Informational note (`[!NOTE]`).
  note,

  /// Helpful tip (`[!TIP]`).
  tip,

  /// Crucial information (`[!IMPORTANT]`).
  important,

  /// Warning notice (`[!WARNING]`).
  warning,

  /// Danger or caution notice (`[!CAUTION]`).
  caution,
}

/// Horizontal cell alignment for GFM tables and aligned containers.
enum TableAlignment {
  /// No explicit alignment specified.
  none,

  /// Left-aligned content (`:---`).
  left,

  /// Center-aligned content (`:---:`).
  center,

  /// Right-aligned content (`---:`).
  right,
}

/// Parsed document frontmatter extracted from leading YAML (`---`) or TOML
/// (`+++`) blocks.
@immutable
final class MarkdownFrontmatter {
  /// Creates a [MarkdownFrontmatter].
  const MarkdownFrontmatter({
    required this.raw,
    this.format = 'yaml',
    Map<String, Object?> entries = const <String, Object?>{},
    // ignore: prefer_initializing_formals
  }) : _entries = entries;

  /// Frontmatter syntax format (`'yaml'` or `'toml'`).
  final String format;

  /// Raw frontmatter body text between the opening and closing delimiters.
  final String raw;

  final Map<String, Object?> _entries;

  /// Parsed top-level structured scalar, list, and map entries.
  Map<String, Object?> get entries => _asUnmodifiableMapView(_entries);

  /// Looks up a scalar or structured entry by [key].
  Object? operator [](String key) => _entries[key];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownFrontmatter &&
          format == other.format &&
          raw == other.raw &&
          _deepMapEquals(_entries, other._entries);

  @override
  int get hashCode => Object.hash(format, raw, _deepMapHash(_entries));

  @override
  String toString() =>
      'MarkdownFrontmatter(format: $format, entries: ${_entries.length})';
}

/// Heading entry in a document outline with resolved anchor slug and line.
@immutable
final class MarkdownOutlineItem {
  /// Creates a [MarkdownOutlineItem].
  const MarkdownOutlineItem({
    required this.text,
    required this.level,
    required this.line,
    required this.slug,
    this.span = SourceSpan.zero,
  });

  /// Plain-text heading label.
  final String text;

  /// Heading level (`1` through `6`).
  final int level;

  /// 1-based line number where the heading begins.
  final int line;

  /// Explicit ID override or generated GitHub-style slug.
  final String slug;

  /// Source span of the heading node.
  final SourceSpan span;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownOutlineItem &&
          text == other.text &&
          level == other.level &&
          line == other.line &&
          slug == other.slug &&
          span == other.span;

  @override
  int get hashCode => Object.hash(text, level, line, slug, span);

  @override
  String toString() =>
      'MarkdownOutlineItem(H$level "$text", line: $line, slug: "$slug")';
}

/// Resolved CommonMark link reference definition (`[label]: destination "title"`).
@immutable
final class MarkdownLinkDefinition {
  /// Creates a [MarkdownLinkDefinition].
  const MarkdownLinkDefinition({
    required this.label,
    required this.normalizedLabel,
    required this.destination,
    this.title,
    this.span = SourceSpan.zero,
  });

  /// Original label text inside brackets.
  final String label;

  /// Whitespace-collapsed and Unicode-case-folded label key.
  final String normalizedLabel;

  /// Resolved link destination URI.
  final String destination;

  /// Optional unescaped title string.
  final String? title;

  /// Source span of the link reference definition.
  final SourceSpan span;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownLinkDefinition &&
          label == other.label &&
          normalizedLabel == other.normalizedLabel &&
          destination == other.destination &&
          title == other.title &&
          span == other.span;

  @override
  int get hashCode =>
      Object.hash(label, normalizedLabel, destination, title, span);
}

/// Single cell within a [TableNode] header or body row.
@immutable
final class TableCellNode {
  /// Creates a [TableCellNode].
  const TableCellNode({
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    this.alignment = TableAlignment.none,
    this.span = SourceSpan.zero,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const TableCellNode._frozen({
    required List<MarkdownInlineNode> children,
    required this.alignment,
    required this.span,
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const TableCellNode._shifted({
    required List<MarkdownInlineNode> children,
    required this.alignment,
    required this.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final List<MarkdownInlineNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Parsed inline children within this cell.
  List<MarkdownInlineNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftInlines(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  /// Column alignment assigned to this cell.
  final TableAlignment alignment;

  /// Source span of this cell.
  final SourceSpan span;

  /// Extracts normalized plain text from this cell.
  String toPlainText() => _inlinesToPlainText(_children);

  /// Returns a span-shifted copy of this cell.
  TableCellNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return TableCellNode._shifted(
      children: _children,
      alignment: alignment,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! TableCellNode ||
        alignment != other.alignment ||
        span != other.span) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children);
    }
    return _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final List<MarkdownInlineNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _children : children;
    return Object.hash(alignment, span, Object.hashAll(resolved));
  }
}

/// Term-and-definitions group within a [DefinitionListNode].
@immutable
final class DefinitionGroup {
  /// Creates a [DefinitionGroup].
  const DefinitionGroup({
    List<MarkdownInlineNode> term = const <MarkdownInlineNode>[],
    List<List<MarkdownBlockNode>> definitions =
        const <List<MarkdownBlockNode>>[],
    this.span = SourceSpan.zero,
    // ignore: prefer_initializing_formals
  }) : _term = term,
       _definitions = definitions,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const DefinitionGroup._frozen({
    required List<MarkdownInlineNode> term,
    required List<List<MarkdownBlockNode>> definitions,
    required this.span,
  }) : _term = term,
       _definitions = definitions,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const DefinitionGroup._shifted({
    required List<MarkdownInlineNode> term,
    required List<List<MarkdownBlockNode>> definitions,
    required this.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _term = term,
       _definitions = definitions,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final List<MarkdownInlineNode> _term;
  final List<List<MarkdownBlockNode>> _definitions;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Inline nodes comprising the defined term (`<dt>`).
  List<MarkdownInlineNode> get term {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _term : _asUnmodifiableListView(_term);
    }
    return freezeFreshList(
      _shiftInlines(_term, _childOffsetDelta, _childLineDelta),
    );
  }

  /// Block sequences for each `: ...` definition (`<dd>`) belonging to [term].
  List<List<MarkdownBlockNode>> get definitions {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _definitions : _asUnmodifiableListView(_definitions);
    }
    return List<List<MarkdownBlockNode>>.unmodifiable(
      _definitions
          .map(
            (List<MarkdownBlockNode> d) => freezeFreshList(
              _shiftBlocks(d, _childOffsetDelta, _childLineDelta),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Source span covering this term and its definitions.
  final SourceSpan span;

  /// Extracts plain text for this term and its definitions.
  String toPlainText() {
    final StringBuffer out = StringBuffer()..write(_inlinesToPlainText(_term));
    for (final List<MarkdownBlockNode> def in _definitions) {
      for (final MarkdownBlockNode block in def) {
        final String text = block.toPlainText();
        if (text.isNotEmpty) {
          out
            ..write('\n')
            ..write(text);
        }
      }
    }
    return out.toString();
  }

  /// Returns a span-shifted copy of this group.
  DefinitionGroup shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return DefinitionGroup._shifted(
      term: _term,
      definitions: _definitions,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! DefinitionGroup || span != other.span) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_term, other._term) &&
          _nestedBlockListEquals(_definitions, other._definitions);
    }
    return _listEquals(term, other.term) &&
        _nestedBlockListEquals(definitions, other.definitions);
  }

  @override
  int get hashCode {
    final bool unshifted = _childOffsetDelta == 0 && _childLineDelta == 0;
    final List<MarkdownInlineNode> resolvedTerm = unshifted ? _term : term;
    final List<List<MarkdownBlockNode>> resolvedDefs = unshifted
        ? _definitions
        : definitions;
    return Object.hash(
      span,
      Object.hashAll(resolvedTerm),
      Object.hashAll(
        resolvedDefs.map((List<MarkdownBlockNode> d) => Object.hashAll(d)),
      ),
    );
  }
}

/// Base class for all immutable block-level Markdown AST nodes.
@immutable
sealed class MarkdownBlockNode {
  /// Creates a [MarkdownBlockNode].
  const MarkdownBlockNode({required this.blockId, this.span = SourceSpan.zero});

  /// Stable block identifier preserved across incremental reuses.
  final String blockId;

  /// Source span covering this block node.
  final SourceSpan span;

  /// Extracts normalized plain text representation of this block.
  String toPlainText();

  /// Returns a copy with [span] shifted by [offsetDelta] and [lineDelta].
  MarkdownBlockNode shiftSpan(int offsetDelta, int lineDelta);
}

/// Leading YAML or TOML frontmatter block.
final class FrontmatterNode extends MarkdownBlockNode {
  /// Creates a [FrontmatterNode].
  const FrontmatterNode({
    required super.blockId,
    required this.frontmatter,
    super.span,
  });

  /// Parsed frontmatter payload.
  final MarkdownFrontmatter frontmatter;

  /// Frontmatter syntax format (`'yaml'` or `'toml'`).
  String get format => frontmatter.format;

  /// Raw frontmatter content between delimiters.
  String get raw => frontmatter.raw;

  /// Structured key/value entries extracted from frontmatter.
  Map<String, Object?> get entries => frontmatter.entries;

  @override
  String toPlainText() => '';

  @override
  FrontmatterNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return FrontmatterNode(
      blockId: blockId,
      frontmatter: frontmatter,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrontmatterNode &&
          blockId == other.blockId &&
          span == other.span &&
          frontmatter == other.frontmatter;

  @override
  int get hashCode => Object.hash(blockId, span, frontmatter);
}

/// ATX or setext heading block (`<h1>`..`<h6>`).
final class HeadingNode extends MarkdownBlockNode {
  /// Creates a [HeadingNode].
  const HeadingNode({
    required super.blockId,
    required this.level,
    required this.text,
    String? slug,
    this.explicitId,
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    this.isSetext = false,
    super.span,
    // ignore: prefer_initializing_formals
  }) : _slug = slug,
       _lazySlug = null,
       _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const HeadingNode._frozen({
    required super.blockId,
    required this.level,
    required this.text,
    String? slug,
    _LazyHeadingSlug? lazySlug,
    required this.explicitId,
    required List<MarkdownInlineNode> children,
    required this.isSetext,
    required super.span,
  }) : _slug = slug,
       _lazySlug = lazySlug,
       _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const HeadingNode._shifted({
    required super.blockId,
    required this.level,
    required this.text,
    required String? slug,
    required _LazyHeadingSlug? lazySlug,
    required this.explicitId,
    required List<MarkdownInlineNode> children,
    required this.isSetext,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _slug = slug,
       _lazySlug = lazySlug,
       _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  /// Heading level (`1` through `6`).
  final int level;

  /// Plain-text content of this heading.
  final String text;

  final String? _slug;
  final _LazyHeadingSlug? _lazySlug;

  /// Computed GitHub-style slug (or [explicitId]) when enabled.
  String? get slug => _slug ?? _lazySlug?.value;

  /// Explicit `{#id}` anchor attribute if present.
  final String? explicitId;

  final List<MarkdownInlineNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Parsed inline children within the heading.
  List<MarkdownInlineNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftInlines(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  /// Whether this heading was parsed from a setext underline (`===` / `---`).
  final bool isSetext;

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  HeadingNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return HeadingNode._shifted(
      blockId: blockId,
      level: level,
      text: text,
      slug: _slug,
      lazySlug: _lazySlug,
      explicitId: explicitId,
      children: _children,
      isSetext: isSetext,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! HeadingNode ||
        blockId != other.blockId ||
        span != other.span ||
        level != other.level ||
        text != other.text ||
        slug != other.slug ||
        explicitId != other.explicitId ||
        isSetext != other.isSetext) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children);
    }
    return _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final List<MarkdownInlineNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _children : children;
    return Object.hash(
      blockId,
      span,
      level,
      text,
      slug,
      explicitId,
      isSetext,
      Object.hashAll(resolved),
    );
  }
}

/// Paragraph block (`<p>`).
final class ParagraphNode extends MarkdownBlockNode {
  /// Creates a [ParagraphNode].
  const ParagraphNode({
    required super.blockId,
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const ParagraphNode._frozen({
    required super.blockId,
    required List<MarkdownInlineNode> children,
    required super.span,
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const ParagraphNode._shifted({
    required super.blockId,
    required List<MarkdownInlineNode> children,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final List<MarkdownInlineNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Parsed inline children within this paragraph.
  List<MarkdownInlineNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftInlines(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  ParagraphNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return ParagraphNode._shifted(
      blockId: blockId,
      children: _children,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ParagraphNode ||
        blockId != other.blockId ||
        span != other.span) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children);
    }
    return _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final List<MarkdownInlineNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _children : children;
    return Object.hash(blockId, span, Object.hashAll(resolved));
  }
}

/// Indented or fenced code block (`<pre><code>`).
final class CodeBlockNode extends MarkdownBlockNode {
  /// Creates a [CodeBlockNode].
  const CodeBlockNode({
    required super.blockId,
    required this.literal,
    this.info = '',
    this.language,
    this.isFenced = false,
    this.codeUnitOffset = 0,
    super.span,
  });

  /// Full unescaped info string from a fenced code block (or `''`).
  final String info;

  /// First whitespace-delimited language identifier from [info], if any.
  final String? language;

  /// Literal code content preserving newlines.
  final String literal;

  /// Whether this block used a backtick or tilde fence.
  final bool isFenced;

  /// UTF-16 offset where [literal] starts in the normalized document source.
  final int codeUnitOffset;

  @override
  String toPlainText() => literal.endsWith('\n')
      ? literal.substring(0, literal.length - 1)
      : literal;

  @override
  CodeBlockNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return CodeBlockNode(
      blockId: blockId,
      literal: literal,
      info: info,
      language: language,
      isFenced: isFenced,
      codeUnitOffset: codeUnitOffset + offsetDelta,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeBlockNode &&
          blockId == other.blockId &&
          span == other.span &&
          info == other.info &&
          language == other.language &&
          literal == other.literal &&
          isFenced == other.isFenced &&
          codeUnitOffset == other.codeUnitOffset;

  @override
  int get hashCode => Object.hash(
    blockId,
    span,
    info,
    language,
    literal,
    isFenced,
    codeUnitOffset,
  );
}

/// Blockquote container (`<blockquote>`).
final class BlockQuoteNode extends MarkdownBlockNode {
  /// Creates a [BlockQuoteNode].
  const BlockQuoteNode({
    required super.blockId,
    List<MarkdownBlockNode> children = const <MarkdownBlockNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const BlockQuoteNode._frozen({
    required super.blockId,
    required List<MarkdownBlockNode> children,
    required super.span,
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const BlockQuoteNode._shifted({
    required super.blockId,
    required List<MarkdownBlockNode> children,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final List<MarkdownBlockNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Nested blocks inside this blockquote.
  List<MarkdownBlockNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftBlocks(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  @override
  String toPlainText() => _blocksToPlainText(_children);

  @override
  BlockQuoteNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return BlockQuoteNode._shifted(
      blockId: blockId,
      children: _children,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! BlockQuoteNode ||
        blockId != other.blockId ||
        span != other.span) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children);
    }
    return _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final List<MarkdownBlockNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _children : children;
    return Object.hash(blockId, span, Object.hashAll(resolved));
  }
}

/// GitHub-style callout/alert container (`> [!NOTE]`, `> [!WARNING]`, etc.).
final class AlertNode extends MarkdownBlockNode {
  /// Creates an [AlertNode].
  const AlertNode({
    required super.blockId,
    required this.kind,
    required this.title,
    List<MarkdownBlockNode> children = const <MarkdownBlockNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const AlertNode._frozen({
    required super.blockId,
    required this.kind,
    required this.title,
    required List<MarkdownBlockNode> children,
    required super.span,
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const AlertNode._shifted({
    required super.blockId,
    required this.kind,
    required this.title,
    required List<MarkdownBlockNode> children,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  /// Alert severity/kind.
  final AlertKind kind;

  /// Human-readable alert heading (`Note`, `Tip`, `Important`, `Warning`,
  /// `Caution`).
  final String title;

  final List<MarkdownBlockNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Nested body blocks inside the alert.
  List<MarkdownBlockNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftBlocks(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  @override
  String toPlainText() {
    final String body = _blocksToPlainText(_children);
    return body.isEmpty ? title : '$title\n$body';
  }

  @override
  AlertNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return AlertNode._shifted(
      blockId: blockId,
      kind: kind,
      title: title,
      children: _children,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! AlertNode ||
        blockId != other.blockId ||
        span != other.span ||
        kind != other.kind ||
        title != other.title) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children);
    }
    return _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final List<MarkdownBlockNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _children : children;
    return Object.hash(blockId, span, kind, title, Object.hashAll(resolved));
  }
}

/// Ordered or bullet list (`<ol>` / `<ul>`).
final class ListNode extends MarkdownBlockNode {
  /// Creates a [ListNode].
  const ListNode({
    required super.blockId,
    required this.ordered,
    this.start = 1,
    this.tight = true,
    this.delimiter = '-',
    List<ListItemNode> items = const <ListItemNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _items = items,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const ListNode._frozen({
    required super.blockId,
    required this.ordered,
    required this.start,
    required this.tight,
    required this.delimiter,
    required List<ListItemNode> items,
    required super.span,
  }) : _items = items,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const ListNode._shifted({
    required super.blockId,
    required this.ordered,
    required this.start,
    required this.tight,
    required this.delimiter,
    required List<ListItemNode> items,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _items = items,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  /// Whether this is an ordered list (`<ol>`) rather than a bullet list (`<ul>`).
  final bool ordered;

  /// Starting integer for ordered lists (`1` when omitted).
  final int start;

  /// Whether paragraphs inside direct list items should be unwrapped in HTML.
  final bool tight;

  /// Marker delimiter (`'-'`, `'+'`, `'*'`, `'.'`, or `')'`).
  final String delimiter;

  final List<ListItemNode> _items;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Ordered items belonging to this list.
  List<ListItemNode> get items {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _items : _asUnmodifiableListView(_items);
    }
    return freezeFreshList(
      _items
          .map(
            (ListItemNode item) =>
                item.shiftSpan(_childOffsetDelta, _childLineDelta),
          )
          .toList(growable: false),
    );
  }

  @override
  String toPlainText() =>
      _items.map((ListItemNode item) => item.toPlainText()).join('\n');

  @override
  ListNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return ListNode._shifted(
      blockId: blockId,
      ordered: ordered,
      start: start,
      tight: tight,
      delimiter: delimiter,
      items: _items,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ListNode ||
        blockId != other.blockId ||
        span != other.span ||
        ordered != other.ordered ||
        start != other.start ||
        tight != other.tight ||
        delimiter != other.delimiter) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_items, other._items);
    }
    return _listEquals(items, other.items);
  }

  @override
  int get hashCode {
    final List<ListItemNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _items : items;
    return Object.hash(
      blockId,
      span,
      ordered,
      start,
      tight,
      delimiter,
      Object.hashAll(resolved),
    );
  }
}

/// Single list item (`<li>`), optionally carrying a GFM task checkbox state.
final class ListItemNode extends MarkdownBlockNode {
  /// Creates a [ListItemNode].
  const ListItemNode({
    required super.blockId,
    bool? taskState,
    List<MarkdownBlockNode> children = const <MarkdownBlockNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _taskStateCode = taskState == null ? -1 : (taskState ? 1 : 0),
       _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const ListItemNode._frozen({
    required super.blockId,
    required bool? taskState,
    required List<MarkdownBlockNode> children,
    required super.span,
  }) : _taskStateCode = taskState == null ? -1 : (taskState ? 1 : 0),
       _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const ListItemNode._shifted({
    required super.blockId,
    required bool? taskState,
    required List<MarkdownBlockNode> children,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _taskStateCode = taskState == null ? -1 : (taskState ? 1 : 0),
       _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final int _taskStateCode;

  /// GFM task checkbox state (`true` checked, `false` unchecked, `null` normal).
  bool? get taskState => _taskStateCode < 0 ? null : _taskStateCode != 0;

  /// Alias for [taskState] indicating whether a task item is checked.
  bool? get isChecked => taskState;

  /// Whether this item is a GFM task list item.
  bool get isTaskItem => taskState != null;

  final List<MarkdownBlockNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Nested blocks inside this list item.
  List<MarkdownBlockNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftBlocks(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  @override
  String toPlainText() => _blocksToPlainText(_children);

  @override
  ListItemNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return ListItemNode._shifted(
      blockId: blockId,
      taskState: taskState,
      children: _children,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ListItemNode ||
        blockId != other.blockId ||
        span != other.span ||
        taskState != other.taskState) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children);
    }
    return _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final List<MarkdownBlockNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _children : children;
    return Object.hash(blockId, span, taskState, Object.hashAll(resolved));
  }
}

/// GFM pipe table (`<table>`).
final class TableNode extends MarkdownBlockNode {
  /// Creates a [TableNode].
  const TableNode({
    required super.blockId,
    List<TableAlignment> alignments = const <TableAlignment>[],
    List<TableCellNode> headers = const <TableCellNode>[],
    List<List<TableCellNode>> rows = const <List<TableCellNode>>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _alignments = alignments,
       _headers = headers,
       _rows = rows,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const TableNode._frozen({
    required super.blockId,
    required List<TableAlignment> alignments,
    required List<TableCellNode> headers,
    required List<List<TableCellNode>> rows,
    required super.span,
  }) : _alignments = alignments,
       _headers = headers,
       _rows = rows,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const TableNode._shifted({
    required super.blockId,
    required List<TableAlignment> alignments,
    required List<TableCellNode> headers,
    required List<List<TableCellNode>> rows,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _alignments = alignments,
       _headers = headers,
       _rows = rows,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final List<TableAlignment> _alignments;
  final List<TableCellNode> _headers;
  final List<List<TableCellNode>> _rows;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Column alignment specifications from the delimiter row.
  List<TableAlignment> get alignments =>
      _frozen ? _alignments : _asUnmodifiableListView(_alignments);

  /// Header cells (`<thead><tr><th>`).
  List<TableCellNode> get headers {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _headers : _asUnmodifiableListView(_headers);
    }
    return freezeFreshList(
      _headers
          .map(
            (TableCellNode c) =>
                c.shiftSpan(_childOffsetDelta, _childLineDelta),
          )
          .toList(growable: false),
    );
  }

  /// Body rows (`<tbody><tr><td>`).
  List<List<TableCellNode>> get rows {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      if (_frozen) {
        return _rows;
      }
      if (_rows.isEmpty) {
        return const <List<TableCellNode>>[];
      }
      if (_rows is UnmodifiableListView<List<TableCellNode>>) {
        return _rows;
      }
      return UnmodifiableListView<List<TableCellNode>>(
        _rows
            .map((List<TableCellNode> r) => _asUnmodifiableListView(r))
            .toList(growable: false),
      );
    }
    return List<List<TableCellNode>>.unmodifiable(
      _rows
          .map(
            (List<TableCellNode> r) => freezeFreshList(
              r
                  .map(
                    (TableCellNode c) =>
                        c.shiftSpan(_childOffsetDelta, _childLineDelta),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  String toPlainText() {
    final StringBuffer out = StringBuffer()
      ..write(
        _headers.map((TableCellNode cell) => cell.toPlainText()).join('\t'),
      );
    for (final List<TableCellNode> row in _rows) {
      out
        ..write('\n')
        ..write(row.map((TableCellNode cell) => cell.toPlainText()).join('\t'));
    }
    return out.toString();
  }

  @override
  TableNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return TableNode._shifted(
      blockId: blockId,
      alignments: _alignments,
      headers: _headers,
      rows: _rows,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! TableNode ||
        blockId != other.blockId ||
        span != other.span ||
        !_listEquals(_alignments, other._alignments)) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_headers, other._headers) &&
          _nestedCellListEquals(_rows, other._rows);
    }
    return _listEquals(headers, other.headers) &&
        _nestedCellListEquals(rows, other.rows);
  }

  @override
  int get hashCode {
    final bool unshifted = _childOffsetDelta == 0 && _childLineDelta == 0;
    final List<TableCellNode> resolvedHeaders = unshifted ? _headers : headers;
    final List<List<TableCellNode>> resolvedRows = unshifted ? _rows : rows;
    return Object.hash(
      blockId,
      span,
      Object.hashAll(_alignments),
      Object.hashAll(resolvedHeaders),
      Object.hashAll(
        resolvedRows.map((List<TableCellNode> r) => Object.hashAll(r)),
      ),
    );
  }
}

/// Thematic break (`<hr />`).
final class ThematicBreakNode extends MarkdownBlockNode {
  /// Creates a [ThematicBreakNode].
  const ThematicBreakNode({required super.blockId, super.span});

  @override
  String toPlainText() => '---';

  @override
  ThematicBreakNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return ThematicBreakNode(
      blockId: blockId,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThematicBreakNode &&
          blockId == other.blockId &&
          span == other.span;

  @override
  int get hashCode => Object.hash(blockId, span);
}

/// Raw CommonMark HTML block (types 1 through 7).
final class HtmlBlockNode extends MarkdownBlockNode {
  /// Creates an [HtmlBlockNode].
  const HtmlBlockNode({
    required super.blockId,
    required this.literal,
    this.blockType = 6,
    super.span,
  });

  /// Raw HTML block lines preserving line breaks.
  final String literal;

  /// Alias for [literal].
  String get html => literal;

  /// CommonMark HTML block condition number (`1` through `7`).
  final int blockType;

  @override
  String toPlainText() => literal.trimRight();

  @override
  HtmlBlockNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return HtmlBlockNode(
      blockId: blockId,
      literal: literal,
      blockType: blockType,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HtmlBlockNode &&
          blockId == other.blockId &&
          span == other.span &&
          literal == other.literal &&
          blockType == other.blockType;

  @override
  int get hashCode => Object.hash(blockId, span, literal, blockType);
}

/// Collapsible `<details>` / `<summary>` disclosure block.
final class DetailsBlockNode extends MarkdownBlockNode {
  /// Creates a [DetailsBlockNode].
  const DetailsBlockNode({
    required super.blockId,
    required this.summary,
    List<MarkdownInlineNode> summaryInlines = const <MarkdownInlineNode>[],
    this.initiallyOpen = false,
    List<MarkdownBlockNode> children = const <MarkdownBlockNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _summaryInlines = summaryInlines,
       _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const DetailsBlockNode._frozen({
    required super.blockId,
    required this.summary,
    required List<MarkdownInlineNode> summaryInlines,
    required this.initiallyOpen,
    required List<MarkdownBlockNode> children,
    required super.span,
  }) : _summaryInlines = summaryInlines,
       _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const DetailsBlockNode._shifted({
    required super.blockId,
    required this.summary,
    required List<MarkdownInlineNode> summaryInlines,
    required this.initiallyOpen,
    required List<MarkdownBlockNode> children,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _summaryInlines = summaryInlines,
       _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  /// Plain-text summary heading.
  final String summary;

  final List<MarkdownInlineNode> _summaryInlines;

  /// Parsed inline nodes for the summary line.
  List<MarkdownInlineNode> get summaryInlines {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen
          ? _summaryInlines
          : _asUnmodifiableListView(_summaryInlines);
    }
    return freezeFreshList(
      _shiftInlines(_summaryInlines, _childOffsetDelta, _childLineDelta),
    );
  }

  /// Whether the disclosure block carries the `open` attribute.
  final bool initiallyOpen;

  final List<MarkdownBlockNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Nested body blocks inside `<details>`.
  List<MarkdownBlockNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftBlocks(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  @override
  String toPlainText() {
    final String body = _blocksToPlainText(_children);
    return body.isEmpty ? summary : '$summary\n$body';
  }

  @override
  DetailsBlockNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return DetailsBlockNode._shifted(
      blockId: blockId,
      summary: summary,
      summaryInlines: _summaryInlines,
      initiallyOpen: initiallyOpen,
      children: _children,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! DetailsBlockNode ||
        blockId != other.blockId ||
        span != other.span ||
        summary != other.summary ||
        initiallyOpen != other.initiallyOpen) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_summaryInlines, other._summaryInlines) &&
          _listEquals(_children, other._children);
    }
    return _listEquals(summaryInlines, other.summaryInlines) &&
        _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final bool unshifted = _childOffsetDelta == 0 && _childLineDelta == 0;
    return Object.hash(
      blockId,
      span,
      summary,
      initiallyOpen,
      Object.hashAll(unshifted ? _summaryInlines : summaryInlines),
      Object.hashAll(unshifted ? _children : children),
    );
  }
}

/// Explicitly aligned container block (`<div align="...">` or container).
final class AlignedBlockNode extends MarkdownBlockNode {
  /// Creates an [AlignedBlockNode].
  const AlignedBlockNode({
    required super.blockId,
    required this.alignment,
    List<MarkdownBlockNode> children = const <MarkdownBlockNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const AlignedBlockNode._frozen({
    required super.blockId,
    required this.alignment,
    required List<MarkdownBlockNode> children,
    required super.span,
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const AlignedBlockNode._shifted({
    required super.blockId,
    required this.alignment,
    required List<MarkdownBlockNode> children,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  /// Alignment applied to the contained blocks.
  final TableAlignment alignment;

  final List<MarkdownBlockNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Contained block nodes.
  List<MarkdownBlockNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftBlocks(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  @override
  String toPlainText() => _blocksToPlainText(_children);

  @override
  AlignedBlockNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return AlignedBlockNode._shifted(
      blockId: blockId,
      alignment: alignment,
      children: _children,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! AlignedBlockNode ||
        blockId != other.blockId ||
        span != other.span ||
        alignment != other.alignment) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children);
    }
    return _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final List<MarkdownBlockNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _children : children;
    return Object.hash(blockId, span, alignment, Object.hashAll(resolved));
  }
}

/// Figure container (`<figure>` + optional `<figcaption>`).
final class FigureBlockNode extends MarkdownBlockNode {
  /// Creates a [FigureBlockNode].
  const FigureBlockNode({
    required super.blockId,
    List<MarkdownBlockNode> children = const <MarkdownBlockNode>[],
    this.caption,
    List<MarkdownInlineNode> captionInlines = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _captionInlines = captionInlines,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const FigureBlockNode._frozen({
    required super.blockId,
    required List<MarkdownBlockNode> children,
    required this.caption,
    required List<MarkdownInlineNode> captionInlines,
    required super.span,
  }) : _children = children,
       _captionInlines = captionInlines,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const FigureBlockNode._shifted({
    required super.blockId,
    required List<MarkdownBlockNode> children,
    required this.caption,
    required List<MarkdownInlineNode> captionInlines,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _children = children,
       _captionInlines = captionInlines,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final List<MarkdownBlockNode> _children;

  /// Body blocks inside the figure.
  List<MarkdownBlockNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftBlocks(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  /// Plain-text figure caption, if present.
  final String? caption;

  final List<MarkdownInlineNode> _captionInlines;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Parsed inline nodes for `<figcaption>`.
  List<MarkdownInlineNode> get captionInlines {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen
          ? _captionInlines
          : _asUnmodifiableListView(_captionInlines);
    }
    return freezeFreshList(
      _shiftInlines(_captionInlines, _childOffsetDelta, _childLineDelta),
    );
  }

  @override
  String toPlainText() {
    final String body = _blocksToPlainText(_children);
    final String? cap = caption;
    if (cap == null || cap.isEmpty) {
      return body;
    }
    return body.isEmpty ? cap : '$body\n$cap';
  }

  @override
  FigureBlockNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return FigureBlockNode._shifted(
      blockId: blockId,
      children: _children,
      caption: caption,
      captionInlines: _captionInlines,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! FigureBlockNode ||
        blockId != other.blockId ||
        span != other.span ||
        caption != other.caption) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children) &&
          _listEquals(_captionInlines, other._captionInlines);
    }
    return _listEquals(children, other.children) &&
        _listEquals(captionInlines, other.captionInlines);
  }

  @override
  int get hashCode {
    final bool unshifted = _childOffsetDelta == 0 && _childLineDelta == 0;
    return Object.hash(
      blockId,
      span,
      caption,
      Object.hashAll(unshifted ? _children : children),
      Object.hashAll(unshifted ? _captionInlines : captionInlines),
    );
  }
}

/// Display-math block delimited by `$$ ... $$`.
final class MathBlockNode extends MarkdownBlockNode {
  /// Creates a [MathBlockNode].
  const MathBlockNode({
    required super.blockId,
    required this.latex,
    super.span,
  });

  /// Raw LaTeX expression content.
  final String latex;

  @override
  String toPlainText() => latex;

  @override
  MathBlockNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return MathBlockNode(
      blockId: blockId,
      latex: latex,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathBlockNode &&
          blockId == other.blockId &&
          span == other.span &&
          latex == other.latex;

  @override
  int get hashCode => Object.hash(blockId, span, latex);
}

/// PHP Markdown Extra style definition list (`<dl>`).
final class DefinitionListNode extends MarkdownBlockNode {
  /// Creates a [DefinitionListNode].
  const DefinitionListNode({
    required super.blockId,
    List<DefinitionGroup> groups = const <DefinitionGroup>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _groups = groups,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const DefinitionListNode._frozen({
    required super.blockId,
    required List<DefinitionGroup> groups,
    required super.span,
  }) : _groups = groups,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const DefinitionListNode._shifted({
    required super.blockId,
    required List<DefinitionGroup> groups,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _groups = groups,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final List<DefinitionGroup> _groups;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Term/definition groups in this definition list.
  List<DefinitionGroup> get groups {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _groups : _asUnmodifiableListView(_groups);
    }
    return freezeFreshList(
      _groups
          .map(
            (DefinitionGroup g) =>
                g.shiftSpan(_childOffsetDelta, _childLineDelta),
          )
          .toList(growable: false),
    );
  }

  @override
  String toPlainText() =>
      _groups.map((DefinitionGroup g) => g.toPlainText()).join('\n\n');

  @override
  DefinitionListNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return DefinitionListNode._shifted(
      blockId: blockId,
      groups: _groups,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! DefinitionListNode ||
        blockId != other.blockId ||
        span != other.span) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_groups, other._groups);
    }
    return _listEquals(groups, other.groups);
  }

  @override
  int get hashCode {
    final List<DefinitionGroup> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _groups : groups;
    return Object.hash(blockId, span, Object.hashAll(resolved));
  }
}

/// Single footnote definition (`[^label]: ...`).
final class FootnoteDefinitionNode extends MarkdownBlockNode {
  /// Creates a [FootnoteDefinitionNode].
  const FootnoteDefinitionNode({
    required super.blockId,
    required this.label,
    this.index = 0,
    List<MarkdownBlockNode> children = const <MarkdownBlockNode>[],
    this.referenceCount = 0,
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const FootnoteDefinitionNode._frozen({
    required super.blockId,
    required this.label,
    required this.index,
    required List<MarkdownBlockNode> children,
    required this.referenceCount,
    required super.span,
  }) : _children = children,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const FootnoteDefinitionNode._shifted({
    required super.blockId,
    required this.label,
    required this.index,
    required List<MarkdownBlockNode> children,
    required this.referenceCount,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _children = children,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  /// Raw footnote identifier label.
  final String label;

  /// 1-based reference order index (`0` if unreferenced).
  final int index;

  /// Number of references pointing to this footnote (`0` if unreferenced).
  final int referenceCount;

  final List<MarkdownBlockNode> _children;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Body blocks inside this footnote definition.
  List<MarkdownBlockNode> get children {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _children : _asUnmodifiableListView(_children);
    }
    return freezeFreshList(
      _shiftBlocks(_children, _childOffsetDelta, _childLineDelta),
    );
  }

  @override
  String toPlainText() => _blocksToPlainText(_children);

  @override
  FootnoteDefinitionNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return FootnoteDefinitionNode._shifted(
      blockId: blockId,
      label: label,
      index: index,
      referenceCount: referenceCount,
      children: _children,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! FootnoteDefinitionNode ||
        blockId != other.blockId ||
        span != other.span ||
        label != other.label ||
        index != other.index ||
        referenceCount != other.referenceCount) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_children, other._children);
    }
    return _listEquals(children, other.children);
  }

  @override
  int get hashCode {
    final List<MarkdownBlockNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0) ? _children : children;
    return Object.hash(
      blockId,
      span,
      label,
      index,
      referenceCount,
      Object.hashAll(resolved),
    );
  }
}

/// Rendered footnotes footer section (`<section class="footnotes">`).
final class FootnoteSectionNode extends MarkdownBlockNode {
  /// Creates a [FootnoteSectionNode].
  const FootnoteSectionNode({
    required super.blockId,
    List<FootnoteDefinitionNode> definitions = const <FootnoteDefinitionNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _definitions = definitions,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = false;

  const FootnoteSectionNode._frozen({
    required super.blockId,
    required List<FootnoteDefinitionNode> definitions,
    required super.span,
  }) : _definitions = definitions,
       _childOffsetDelta = 0,
       _childLineDelta = 0,
       _frozen = true;

  const FootnoteSectionNode._shifted({
    required super.blockId,
    required List<FootnoteDefinitionNode> definitions,
    required super.span,
    required int childOffsetDelta,
    required int childLineDelta,
  }) : _definitions = definitions,
       _childOffsetDelta = childOffsetDelta,
       _childLineDelta = childLineDelta,
       _frozen = false;

  final List<FootnoteDefinitionNode> _definitions;
  final int _childOffsetDelta;
  final int _childLineDelta;
  final bool _frozen;

  /// Referenced footnote definitions ordered by first citation.
  List<FootnoteDefinitionNode> get definitions {
    if (_childOffsetDelta == 0 && _childLineDelta == 0) {
      return _frozen ? _definitions : _asUnmodifiableListView(_definitions);
    }
    return freezeFreshList(
      _definitions
          .map(
            (FootnoteDefinitionNode d) =>
                d.shiftSpan(_childOffsetDelta, _childLineDelta),
          )
          .toList(growable: false),
    );
  }

  @override
  String toPlainText() => _definitions
      .map((FootnoteDefinitionNode d) => '${d.index}. ${d.toPlainText()}')
      .join('\n');

  @override
  FootnoteSectionNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return FootnoteSectionNode._shifted(
      blockId: blockId,
      definitions: _definitions,
      span: span.shift(offsetDelta, lineDelta),
      childOffsetDelta: _childOffsetDelta + offsetDelta,
      childLineDelta: _childLineDelta + lineDelta,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! FootnoteSectionNode ||
        blockId != other.blockId ||
        span != other.span) {
      return false;
    }
    if (_childOffsetDelta == other._childOffsetDelta &&
        _childLineDelta == other._childLineDelta) {
      return _listEquals(_definitions, other._definitions);
    }
    return _listEquals(definitions, other.definitions);
  }

  @override
  int get hashCode {
    final List<FootnoteDefinitionNode> resolved =
        (_childOffsetDelta == 0 && _childLineDelta == 0)
        ? _definitions
        : definitions;
    return Object.hash(blockId, span, Object.hashAll(resolved));
  }
}

/// Base class for all immutable inline Markdown AST nodes.
@immutable
sealed class MarkdownInlineNode {
  /// Creates a [MarkdownInlineNode].
  const MarkdownInlineNode({this.span = SourceSpan.zero});

  /// Source span covering this inline node.
  final SourceSpan span;

  /// Extracts plain text content from this inline node.
  String toPlainText();

  /// Returns a copy with [span] shifted by [offsetDelta] and [lineDelta].
  MarkdownInlineNode shiftSpan(int offsetDelta, int lineDelta);
}

/// Literal inline text node.
final class TextNode extends MarkdownInlineNode {
  /// Creates a [TextNode].
  const TextNode(this.text, {super.span});

  /// Decoded text string.
  final String text;

  @override
  String toPlainText() => text;

  @override
  TextNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return TextNode(text, span: span.shift(offsetDelta, lineDelta));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextNode && text == other.text && span == other.span;

  @override
  int get hashCode => Object.hash(text, span);
}

/// Soft line break within a paragraph or heading.
final class SoftBreakNode extends MarkdownInlineNode {
  /// Creates a [SoftBreakNode].
  const SoftBreakNode({super.span});

  @override
  String toPlainText() => '\n';

  @override
  SoftBreakNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return SoftBreakNode(span: span.shift(offsetDelta, lineDelta));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SoftBreakNode && span == other.span;

  @override
  int get hashCode => span.hashCode;
}

/// Hard line break (`  \n` or `\\\n`).
final class HardBreakNode extends MarkdownInlineNode {
  /// Creates a [HardBreakNode].
  const HardBreakNode({super.span});

  @override
  String toPlainText() => '\n';

  @override
  HardBreakNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return HardBreakNode(span: span.shift(offsetDelta, lineDelta));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HardBreakNode && span == other.span;

  @override
  int get hashCode => span.hashCode;
}

/// Inline code span (`<code>`).
final class CodeSpanNode extends MarkdownInlineNode {
  /// Creates a [CodeSpanNode].
  const CodeSpanNode(this.literal, {super.span});

  /// Normalized code span literal text.
  final String literal;

  /// Alias for [literal].
  String get code => literal;

  @override
  String toPlainText() => literal;

  @override
  CodeSpanNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return CodeSpanNode(literal, span: span.shift(offsetDelta, lineDelta));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeSpanNode && literal == other.literal && span == other.span;

  @override
  int get hashCode => Object.hash(literal, span);
}

/// Emphasis inline node (`<em>`).
final class EmphasisNode extends MarkdownInlineNode {
  /// Creates an [EmphasisNode].
  const EmphasisNode({
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    this.delimiter = '*',
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _frozen = false;

  const EmphasisNode._frozen({
    required List<MarkdownInlineNode> children,
    required this.delimiter,
    required super.span,
  }) : _children = children,
       _frozen = true;

  final List<MarkdownInlineNode> _children;
  final bool _frozen;

  /// Emphasized child inline nodes.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  /// Delimiter character (`'*'` or `'_'`).
  final String delimiter;

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  EmphasisNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return EmphasisNode._frozen(
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      delimiter: delimiter,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmphasisNode &&
          delimiter == other.delimiter &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(delimiter, span, Object.hashAll(_children));
}

/// Strong emphasis inline node (`<strong>`).
final class StrongNode extends MarkdownInlineNode {
  /// Creates a [StrongNode].
  const StrongNode({
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    this.delimiter = '**',
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _frozen = false;

  const StrongNode._frozen({
    required List<MarkdownInlineNode> children,
    required this.delimiter,
    required super.span,
  }) : _children = children,
       _frozen = true;

  final List<MarkdownInlineNode> _children;
  final bool _frozen;

  /// Strongly emphasized child inline nodes.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  /// Delimiter marker (`'**'` or `'__'`).
  final String delimiter;

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  StrongNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return StrongNode._frozen(
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      delimiter: delimiter,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrongNode &&
          delimiter == other.delimiter &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(delimiter, span, Object.hashAll(_children));
}

/// GFM strikethrough node (`<del>`).
final class StrikethroughNode extends MarkdownInlineNode {
  /// Creates a [StrikethroughNode].
  const StrikethroughNode({
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _frozen = false;

  const StrikethroughNode._frozen({
    required List<MarkdownInlineNode> children,
    required super.span,
  }) : _children = children,
       _frozen = true;

  final List<MarkdownInlineNode> _children;
  final bool _frozen;

  /// Struck child inline nodes.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  StrikethroughNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return StrikethroughNode._frozen(
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrikethroughNode &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(span, Object.hashAll(_children));
}

/// Highlighted inline span (`==text==` -> `<mark>`).
final class HighlightNode extends MarkdownInlineNode {
  /// Creates a [HighlightNode].
  const HighlightNode({
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _frozen = false;

  const HighlightNode._frozen({
    required List<MarkdownInlineNode> children,
    required super.span,
  }) : _children = children,
       _frozen = true;

  final List<MarkdownInlineNode> _children;
  final bool _frozen;

  /// Highlighted child inline nodes.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  HighlightNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return HighlightNode._frozen(
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HighlightNode &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(span, Object.hashAll(_children));
}

/// Subscript inline span (`~text~` -> `<sub>`).
final class SubscriptNode extends MarkdownInlineNode {
  /// Creates a [SubscriptNode].
  const SubscriptNode({
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _frozen = false;

  const SubscriptNode._frozen({
    required List<MarkdownInlineNode> children,
    required super.span,
  }) : _children = children,
       _frozen = true;

  final List<MarkdownInlineNode> _children;
  final bool _frozen;

  /// Subscripted child inline nodes.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  SubscriptNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return SubscriptNode._frozen(
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptNode &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(span, Object.hashAll(_children));
}

/// Superscript inline span (`^text^` -> `<sup>`).
final class SuperscriptNode extends MarkdownInlineNode {
  /// Creates a [SuperscriptNode].
  const SuperscriptNode({
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _frozen = false;

  const SuperscriptNode._frozen({
    required List<MarkdownInlineNode> children,
    required super.span,
  }) : _children = children,
       _frozen = true;

  final List<MarkdownInlineNode> _children;
  final bool _frozen;

  /// Superscripted child inline nodes.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  SuperscriptNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return SuperscriptNode._frozen(
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuperscriptNode &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(span, Object.hashAll(_children));
}

/// Hyperlink inline node (`<a>`).
final class LinkNode extends MarkdownInlineNode {
  /// Creates a [LinkNode].
  const LinkNode({
    required this.destination,
    String? title,
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    this.isAutolink = false,
    super.span,
    // ignore: prefer_initializing_formals
  }) : _hasTitle = title != null,
       _title = title ?? '',
       _children = children,
       _blockedDestination = false,
       _frozen = false;

  const LinkNode._frozen({
    required this.destination,
    required String? title,
    required List<MarkdownInlineNode> children,
    required this.isAutolink,
    required super.span,
  }) : _hasTitle = title != null,
       _title = title ?? '',
       _children = children,
       _blockedDestination = false,
       _frozen = true;

  const LinkNode._blocked({
    required String? title,
    required List<MarkdownInlineNode> children,
    required this.isAutolink,
    required super.span,
    bool frozen = false,
  }) : destination = '',
       _hasTitle = title != null,
       _title = title ?? '',
       _children = children,
       _blockedDestination = true,
       _frozen = frozen;

  /// Resolved link destination URI (sanitized if URL sanitization is active).
  final String destination;

  final bool _hasTitle;
  final String _title;

  /// Optional unescaped link title.
  String? get title => _hasTitle ? _title : null;

  final List<MarkdownInlineNode> _children;
  final bool _blockedDestination;
  final bool _frozen;

  /// Visible link label inline nodes.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  /// Whether this link was created from a CommonMark or GFM autolink.
  final bool isAutolink;

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  LinkNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    if (_blockedDestination) {
      return LinkNode._blocked(
        title: title,
        children: _shiftInlines(_children, offsetDelta, lineDelta),
        isAutolink: isAutolink,
        span: span.shift(offsetDelta, lineDelta),
        frozen: true,
      );
    }
    return LinkNode._frozen(
      destination: destination,
      title: title,
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      isAutolink: isAutolink,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkNode &&
          destination == other.destination &&
          _hasTitle == other._hasTitle &&
          _title == other._title &&
          isAutolink == other.isAutolink &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(
    destination,
    title,
    isAutolink,
    span,
    Object.hashAll(_children),
  );
}

/// Image inline node (`<img>`).
final class ImageNode extends MarkdownInlineNode {
  /// Creates an [ImageNode].
  const ImageNode({
    required this.destination,
    required this.alt,
    this.title,
    this.width,
    this.height,
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _blockedDestination = false,
       _frozen = false;

  const ImageNode._frozen({
    required this.destination,
    required this.alt,
    required this.title,
    required this.width,
    required this.height,
    required List<MarkdownInlineNode> children,
    required super.span,
  }) : _children = children,
       _blockedDestination = false,
       _frozen = true;

  const ImageNode._blocked({
    required this.alt,
    required this.title,
    required this.width,
    required this.height,
    required List<MarkdownInlineNode> children,
    required super.span,
    bool frozen = false,
  }) : destination = '',
       _children = children,
       _blockedDestination = true,
       _frozen = frozen;

  /// Image URI destination (sanitized if URL sanitization is active).
  final String destination;

  /// Normalized plain-text alternate description.
  final String alt;

  /// Optional unescaped image title.
  final String? title;

  /// Optional explicit pixel width attribute.
  final int? width;

  /// Optional explicit pixel height attribute.
  final int? height;

  final List<MarkdownInlineNode> _children;
  final bool _blockedDestination;
  final bool _frozen;

  /// Parsed inline children extracted for the image alt description.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  @override
  String toPlainText() => alt;

  @override
  ImageNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    if (_blockedDestination) {
      return ImageNode._blocked(
        alt: alt,
        title: title,
        width: width,
        height: height,
        children: _shiftInlines(_children, offsetDelta, lineDelta),
        span: span.shift(offsetDelta, lineDelta),
        frozen: true,
      );
    }
    return ImageNode._frozen(
      destination: destination,
      alt: alt,
      title: title,
      width: width,
      height: height,
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageNode &&
          destination == other.destination &&
          alt == other.alt &&
          title == other.title &&
          width == other.width &&
          height == other.height &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(
    destination,
    alt,
    title,
    width,
    height,
    span,
    Object.hashAll(_children),
  );
}

/// Inline LaTeX math node (`$...$`).
final class MathInlineNode extends MarkdownInlineNode {
  /// Creates a [MathInlineNode].
  const MathInlineNode(this.latex, {super.span});

  /// Raw LaTeX expression content.
  final String latex;

  @override
  String toPlainText() => latex;

  @override
  MathInlineNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return MathInlineNode(latex, span: span.shift(offsetDelta, lineDelta));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathInlineNode && latex == other.latex && span == other.span;

  @override
  int get hashCode => Object.hash(latex, span);
}

/// Inline footnote citation (`[^label]`).
final class FootnoteRefNode extends MarkdownInlineNode {
  /// Creates a [FootnoteRefNode].
  const FootnoteRefNode({
    required this.label,
    required this.index,
    this.occurrenceIndex = 1,
    super.span,
  });

  /// Referenced footnote label.
  final String label;

  /// 1-based footnote number in order of first reference.
  final int index;

  /// 1-based occurrence count for this specific [label].
  final int occurrenceIndex;

  @override
  String toPlainText() => '[$index]';

  @override
  FootnoteRefNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return FootnoteRefNode(
      label: label,
      index: index,
      occurrenceIndex: occurrenceIndex,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FootnoteRefNode &&
          label == other.label &&
          index == other.index &&
          occurrenceIndex == other.occurrenceIndex &&
          span == other.span;

  @override
  int get hashCode => Object.hash(label, index, occurrenceIndex, span);
}

/// Keyboard input inline node (`<kbd>`).
final class KbdInlineNode extends MarkdownInlineNode {
  /// Creates a [KbdInlineNode].
  const KbdInlineNode({
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _frozen = false;

  const KbdInlineNode._frozen({
    required List<MarkdownInlineNode> children,
    required super.span,
  }) : _children = children,
       _frozen = true;

  final List<MarkdownInlineNode> _children;
  final bool _frozen;

  /// Inline contents of the `<kbd>` tag.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  KbdInlineNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return KbdInlineNode._frozen(
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KbdInlineNode &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(span, Object.hashAll(_children));
}

/// Abbreviation inline node (`<abbr title="...">`).
final class AbbrInlineNode extends MarkdownInlineNode {
  /// Creates an [AbbrInlineNode].
  const AbbrInlineNode({
    required this.title,
    List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
    super.span,
    // ignore: prefer_initializing_formals
  }) : _children = children,
       _frozen = false;

  const AbbrInlineNode._frozen({
    required this.title,
    required List<MarkdownInlineNode> children,
    required super.span,
  }) : _children = children,
       _frozen = true;

  /// Expanded abbreviation definition title.
  final String title;

  final List<MarkdownInlineNode> _children;
  final bool _frozen;

  /// Visible abbreviation text nodes.
  List<MarkdownInlineNode> get children =>
      _frozen ? _children : _asUnmodifiableListView(_children);

  @override
  String toPlainText() => _inlinesToPlainText(_children);

  @override
  AbbrInlineNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return AbbrInlineNode._frozen(
      title: title,
      children: _shiftInlines(_children, offsetDelta, lineDelta),
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AbbrInlineNode &&
          title == other.title &&
          span == other.span &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(title, span, Object.hashAll(_children));
}

/// Inline anchor target node (`<a id="..."></a>`).
final class AnchorInlineNode extends MarkdownInlineNode {
  /// Creates an [AnchorInlineNode].
  const AnchorInlineNode(this.id, {super.span});

  /// Anchor identifier string.
  final String id;

  @override
  String toPlainText() => '';

  @override
  AnchorInlineNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return AnchorInlineNode(id, span: span.shift(offsetDelta, lineDelta));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnchorInlineNode && id == other.id && span == other.span;

  @override
  int get hashCode => Object.hash(id, span);
}

/// Theme-aware `<picture>` element with light and dark image sources.
final class PictureInlineNode extends MarkdownInlineNode {
  /// Creates a [PictureInlineNode].
  const PictureInlineNode({
    required this.lightSource,
    required this.darkSource,
    required this.alt,
    super.span,
  });

  /// Light-mode fallback image URL.
  final String lightSource;

  /// Dark-mode image source URL (`prefers-color-scheme: dark`).
  final String darkSource;

  /// Alternate text description.
  final String alt;

  @override
  String toPlainText() => alt;

  @override
  PictureInlineNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return PictureInlineNode(
      lightSource: lightSource,
      darkSource: darkSource,
      alt: alt,
      span: span.shift(offsetDelta, lineDelta),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PictureInlineNode &&
          lightSource == other.lightSource &&
          darkSource == other.darkSource &&
          alt == other.alt &&
          span == other.span;

  @override
  int get hashCode => Object.hash(lightSource, darkSource, alt, span);
}

/// Inline line-break element (`<br />`).
final class InlineBreakNode extends MarkdownInlineNode {
  /// Creates an [InlineBreakNode].
  const InlineBreakNode({super.span});

  @override
  String toPlainText() => '\n';

  @override
  InlineBreakNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return InlineBreakNode(span: span.shift(offsetDelta, lineDelta));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InlineBreakNode && span == other.span;

  @override
  int get hashCode => span.hashCode;
}

/// Raw inline HTML tag, comment, declaration, or processing instruction.
final class RawHtmlInlineNode extends MarkdownInlineNode {
  /// Creates a [RawHtmlInlineNode].
  const RawHtmlInlineNode(this.html, {super.span});

  /// Raw HTML token string.
  final String html;

  /// Alias for [html].
  String get literal => html;

  @override
  String toPlainText() => '';

  @override
  RawHtmlInlineNode shiftSpan(int offsetDelta, int lineDelta) {
    if (offsetDelta == 0 && lineDelta == 0) {
      return this;
    }
    return RawHtmlInlineNode(html, span: span.shift(offsetDelta, lineDelta));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawHtmlInlineNode && html == other.html && span == other.span;

  @override
  int get hashCode => Object.hash(html, span);
}

String _inlinesToPlainText(List<MarkdownInlineNode> nodes) {
  final int len = nodes.length;
  if (len == 0) {
    return '';
  }
  if (len == 1) {
    return nodes[0].toPlainText();
  }
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < len; i++) {
    out.write(nodes[i].toPlainText());
  }
  return out.toString();
}

String _blocksToPlainText(List<MarkdownBlockNode> blocks) {
  final int len = blocks.length;
  if (len == 0) {
    return '';
  }
  if (len == 1) {
    return blocks[0].toPlainText();
  }
  final List<String> parts = <String>[];
  for (int i = 0; i < len; i++) {
    final String text = blocks[i].toPlainText();
    if (text.isNotEmpty) {
      parts.add(text);
    }
  }
  return parts.join('\n\n');
}

List<MarkdownInlineNode> _shiftInlines(
  List<MarkdownInlineNode> nodes,
  int offsetDelta,
  int lineDelta,
) {
  final int len = nodes.length;
  if (len == 0) {
    return const <MarkdownInlineNode>[];
  }
  if (len == 1) {
    return _SingletonList<MarkdownInlineNode>(
      nodes[0].shiftSpan(offsetDelta, lineDelta),
    );
  }
  return List<MarkdownInlineNode>.unmodifiable(
    List<MarkdownInlineNode>.generate(
      len,
      (int i) => nodes[i].shiftSpan(offsetDelta, lineDelta),
      growable: false,
    ),
  );
}

List<MarkdownBlockNode> _shiftBlocks(
  List<MarkdownBlockNode> blocks,
  int offsetDelta,
  int lineDelta,
) {
  final int len = blocks.length;
  if (len == 0) {
    return const <MarkdownBlockNode>[];
  }
  if (len == 1) {
    return _SingletonList<MarkdownBlockNode>(
      blocks[0].shiftSpan(offsetDelta, lineDelta),
    );
  }
  return List<MarkdownBlockNode>.unmodifiable(
    List<MarkdownBlockNode>.generate(
      len,
      (int i) => blocks[i].shiftSpan(offsetDelta, lineDelta),
      growable: false,
    ),
  );
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

bool _nestedCellListEquals(
  List<List<TableCellNode>> a,
  List<List<TableCellNode>> b,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (!_listEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

bool _nestedBlockListEquals(
  List<List<MarkdownBlockNode>> a,
  List<List<MarkdownBlockNode>> b,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (!_listEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

bool _deepMapEquals(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<Object?, Object?> entry in a.entries) {
    if (!b.containsKey(entry.key) ||
        !_deepValueEquals(entry.value, b[entry.key])) {
      return false;
    }
  }
  return true;
}

bool _deepValueEquals(Object? a, Object? b) {
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (!_deepValueEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    return _deepMapEquals(a, b);
  }
  return a == b;
}

int _deepMapHash(Map<Object?, Object?> map) {
  return Object.hashAllUnordered(
    map.entries.map(
      (MapEntry<Object?, Object?> e) =>
          Object.hash(e.key, _deepValueHash(e.value)),
    ),
  );
}

int _deepValueHash(Object? value) {
  if (value is List<Object?>) {
    return Object.hashAll(value.map(_deepValueHash));
  }
  if (value is Map<Object?, Object?>) {
    return _deepMapHash(value);
  }
  return value.hashCode;
}

/// Package-internal helper constructing a [LinkNode] whose destination was
/// blocked by URL policy so HTML export omits `href`.
LinkNode createBlockedLinkNode({
  String? title,
  List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
  bool isAutolink = false,
  SourceSpan span = SourceSpan.zero,
  bool frozen = false,
}) => LinkNode._blocked(
  title: title,
  children: children,
  isAutolink: isAutolink,
  span: span,
  frozen: frozen,
);

/// Package-internal helper constructing an [ImageNode] whose destination was
/// blocked by URL policy so HTML export omits `src`.
ImageNode createBlockedImageNode({
  required String alt,
  String? title,
  int? width,
  int? height,
  List<MarkdownInlineNode> children = const <MarkdownInlineNode>[],
  SourceSpan span = SourceSpan.zero,
  bool frozen = false,
}) => ImageNode._blocked(
  alt: alt,
  title: title,
  width: width,
  height: height,
  children: children,
  span: span,
  frozen: frozen,
);

/// Package-internal constructors creating AST nodes backed by already-frozen
/// lists so getters return O(1) without wrapping in [UnmodifiableListView].
ParagraphNode createFrozenParagraphNode({
  required String blockId,
  required List<MarkdownInlineNode> children,
  required SourceSpan span,
}) => ParagraphNode._frozen(blockId: blockId, children: children, span: span);

HeadingNode createFrozenHeadingNode({
  required String blockId,
  required int level,
  required String text,
  String? slug,
  HeadingSlugBatch? slugBatch,
  String? explicitId,
  required List<MarkdownInlineNode> children,
  required bool isSetext,
  required SourceSpan span,
}) => HeadingNode._frozen(
  blockId: blockId,
  level: level,
  text: text,
  slug: slug,
  lazySlug: slugBatch?._register(text),
  explicitId: explicitId,
  children: children,
  isSetext: isSetext,
  span: span,
);

BlockQuoteNode createFrozenBlockQuoteNode({
  required String blockId,
  required List<MarkdownBlockNode> children,
  required SourceSpan span,
}) => BlockQuoteNode._frozen(blockId: blockId, children: children, span: span);

AlertNode createFrozenAlertNode({
  required String blockId,
  required AlertKind kind,
  required String title,
  required List<MarkdownBlockNode> children,
  required SourceSpan span,
}) => AlertNode._frozen(
  blockId: blockId,
  kind: kind,
  title: title,
  children: children,
  span: span,
);

ListNode createFrozenListNode({
  required String blockId,
  required bool ordered,
  required int start,
  required bool tight,
  required String delimiter,
  required List<ListItemNode> items,
  required SourceSpan span,
}) => ListNode._frozen(
  blockId: blockId,
  ordered: ordered,
  start: start,
  tight: tight,
  delimiter: delimiter,
  items: items,
  span: span,
);

ListItemNode createFrozenListItemNode({
  required String blockId,
  required bool? taskState,
  required List<MarkdownBlockNode> children,
  required SourceSpan span,
}) => ListItemNode._frozen(
  blockId: blockId,
  taskState: taskState,
  children: children,
  span: span,
);

TableCellNode createFrozenTableCellNode({
  required List<MarkdownInlineNode> children,
  required TableAlignment alignment,
  required SourceSpan span,
}) =>
    TableCellNode._frozen(children: children, alignment: alignment, span: span);

TableNode createFrozenTableNode({
  required String blockId,
  required List<TableAlignment> alignments,
  required List<TableCellNode> headers,
  required List<List<TableCellNode>> rows,
  required SourceSpan span,
}) => TableNode._frozen(
  blockId: blockId,
  alignments: alignments,
  headers: headers,
  rows: rows,
  span: span,
);

DetailsBlockNode createFrozenDetailsBlockNode({
  required String blockId,
  required String summary,
  required List<MarkdownInlineNode> summaryInlines,
  required bool initiallyOpen,
  required List<MarkdownBlockNode> children,
  required SourceSpan span,
}) => DetailsBlockNode._frozen(
  blockId: blockId,
  summary: summary,
  summaryInlines: summaryInlines,
  initiallyOpen: initiallyOpen,
  children: children,
  span: span,
);

AlignedBlockNode createFrozenAlignedBlockNode({
  required String blockId,
  required TableAlignment alignment,
  required List<MarkdownBlockNode> children,
  required SourceSpan span,
}) => AlignedBlockNode._frozen(
  blockId: blockId,
  alignment: alignment,
  children: children,
  span: span,
);

FigureBlockNode createFrozenFigureBlockNode({
  required String blockId,
  required List<MarkdownBlockNode> children,
  required String? caption,
  required List<MarkdownInlineNode> captionInlines,
  required SourceSpan span,
}) => FigureBlockNode._frozen(
  blockId: blockId,
  children: children,
  caption: caption,
  captionInlines: captionInlines,
  span: span,
);

DefinitionGroup createFrozenDefinitionGroup({
  required List<MarkdownInlineNode> term,
  required List<List<MarkdownBlockNode>> definitions,
  required SourceSpan span,
}) => DefinitionGroup._frozen(term: term, definitions: definitions, span: span);

DefinitionListNode createFrozenDefinitionListNode({
  required String blockId,
  required List<DefinitionGroup> groups,
  required SourceSpan span,
}) => DefinitionListNode._frozen(blockId: blockId, groups: groups, span: span);

FootnoteDefinitionNode createFrozenFootnoteDefinitionNode({
  required String blockId,
  required String label,
  required int index,
  required int referenceCount,
  required List<MarkdownBlockNode> children,
  required SourceSpan span,
}) => FootnoteDefinitionNode._frozen(
  blockId: blockId,
  label: label,
  index: index,
  referenceCount: referenceCount,
  children: children,
  span: span,
);

FootnoteSectionNode createFrozenFootnoteSectionNode({
  required String blockId,
  required List<FootnoteDefinitionNode> definitions,
  required SourceSpan span,
}) => FootnoteSectionNode._frozen(
  blockId: blockId,
  definitions: definitions,
  span: span,
);

EmphasisNode createFrozenEmphasisNode({
  required List<MarkdownInlineNode> children,
  required String delimiter,
  required SourceSpan span,
}) =>
    EmphasisNode._frozen(children: children, delimiter: delimiter, span: span);

StrongNode createFrozenStrongNode({
  required List<MarkdownInlineNode> children,
  required String delimiter,
  required SourceSpan span,
}) => StrongNode._frozen(children: children, delimiter: delimiter, span: span);

StrikethroughNode createFrozenStrikethroughNode({
  required List<MarkdownInlineNode> children,
  required SourceSpan span,
}) => StrikethroughNode._frozen(children: children, span: span);

HighlightNode createFrozenHighlightNode({
  required List<MarkdownInlineNode> children,
  required SourceSpan span,
}) => HighlightNode._frozen(children: children, span: span);

SubscriptNode createFrozenSubscriptNode({
  required List<MarkdownInlineNode> children,
  required SourceSpan span,
}) => SubscriptNode._frozen(children: children, span: span);

SuperscriptNode createFrozenSuperscriptNode({
  required List<MarkdownInlineNode> children,
  required SourceSpan span,
}) => SuperscriptNode._frozen(children: children, span: span);

LinkNode createFrozenLinkNode({
  required String destination,
  required String? title,
  required List<MarkdownInlineNode> children,
  required bool isAutolink,
  required SourceSpan span,
}) => LinkNode._frozen(
  destination: destination,
  title: title,
  children: children,
  isAutolink: isAutolink,
  span: span,
);

ImageNode createFrozenImageNode({
  required String destination,
  required String alt,
  required String? title,
  required int? width,
  required int? height,
  required List<MarkdownInlineNode> children,
  required SourceSpan span,
}) => ImageNode._frozen(
  destination: destination,
  alt: alt,
  title: title,
  width: width,
  height: height,
  children: children,
  span: span,
);

KbdInlineNode createFrozenKbdInlineNode({
  required List<MarkdownInlineNode> children,
  required SourceSpan span,
}) => KbdInlineNode._frozen(children: children, span: span);

AbbrInlineNode createFrozenAbbrInlineNode({
  required String title,
  required List<MarkdownInlineNode> children,
  required SourceSpan span,
}) => AbbrInlineNode._frozen(title: title, children: children, span: span);

/// Returns whether [node]'s original destination was cleared by URL policy.
bool isBlockedLinkNode(LinkNode node) => node._blockedDestination;

/// Returns whether [node]'s original destination was cleared by URL policy.
bool isBlockedImageNode(ImageNode node) => node._blockedDestination;

/// Package-internal raw child accessors avoiding span-shift cloning when only
/// reading non-span content (HTML rendering, plain text, remote image walks).
List<MarkdownInlineNode> rawHeadingInlines(HeadingNode n) => n._children;
List<MarkdownInlineNode> rawParagraphInlines(ParagraphNode n) => n._children;
List<MarkdownBlockNode> rawBlockQuoteChildren(BlockQuoteNode n) => n._children;
List<MarkdownBlockNode> rawAlertChildren(AlertNode n) => n._children;
List<ListItemNode> rawListItems(ListNode n) => n._items;
List<MarkdownBlockNode> rawListItemChildren(ListItemNode n) => n._children;
List<TableCellNode> rawTableHeaders(TableNode n) => n._headers;
List<List<TableCellNode>> rawTableRows(TableNode n) => n._rows;
List<MarkdownInlineNode> rawTableCellInlines(TableCellNode n) => n._children;
List<MarkdownInlineNode> rawDetailsSummaryInlines(DetailsBlockNode n) =>
    n._summaryInlines;
List<MarkdownBlockNode> rawDetailsChildren(DetailsBlockNode n) => n._children;
List<MarkdownBlockNode> rawAlignedChildren(AlignedBlockNode n) => n._children;
List<MarkdownBlockNode> rawFigureChildren(FigureBlockNode n) => n._children;
List<MarkdownInlineNode> rawFigureCaptionInlines(FigureBlockNode n) =>
    n._captionInlines;
List<DefinitionGroup> rawDefinitionGroups(DefinitionListNode n) => n._groups;
List<MarkdownInlineNode> rawDefinitionTerm(DefinitionGroup g) => g._term;
List<List<MarkdownBlockNode>> rawDefinitionBodies(DefinitionGroup g) =>
    g._definitions;
List<MarkdownBlockNode> rawFootnoteDefChildren(FootnoteDefinitionNode n) =>
    n._children;
List<FootnoteDefinitionNode> rawFootnoteSectionDefs(FootnoteSectionNode n) =>
    n._definitions;

SourceSpan createUncheckedSpan({
  required int startOffset,
  required int endOffset,
  required int startLine,
  required int endLine,
}) => SourceSpan._unchecked(
  startOffset: startOffset,
  endOffset: endOffset,
  startLine: startLine,
  endLine: endLine,
);
