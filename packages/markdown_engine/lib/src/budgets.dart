import 'package:meta/meta.dart';

/// Complexity and resource limits enforced while parsing untrusted Markdown.
@immutable
final class MarkdownBudgets {
  /// Creates a [MarkdownBudgets] configuration.
  const MarkdownBudgets({
    this.maxInputLength = defaultMaxInputLength,
    this.maxNestingDepth = defaultMaxNestingDepth,
    this.maxBlocks = defaultMaxBlocks,
    this.maxTableColumns = defaultMaxTableColumns,
    this.maxTableRows = defaultMaxTableRows,
    this.maxHtmlBytes = defaultMaxHtmlBytes,
    this.maxTokens = defaultMaxTokens,
  }) : assert(maxInputLength >= 0, 'maxInputLength must be non-negative'),
       assert(maxNestingDepth >= 0, 'maxNestingDepth must be non-negative'),
       assert(maxBlocks >= 0, 'maxBlocks must be non-negative'),
       assert(maxTableColumns >= 0, 'maxTableColumns must be non-negative'),
       assert(maxTableRows >= 0, 'maxTableRows must be non-negative'),
       assert(maxHtmlBytes >= 0, 'maxHtmlBytes must be non-negative'),
       assert(maxTokens >= 0, 'maxTokens must be non-negative');

  /// Default maximum input document length in UTF-16 code units (`500000`).
  static const int defaultMaxInputLength = 500000;

  /// Default maximum block or inline container nesting depth (`64`).
  static const int defaultMaxNestingDepth = 64;

  /// Default maximum number of block AST nodes emitted for a document (`50000`).
  static const int defaultMaxBlocks = 50000;

  /// Default maximum number of columns parsed in a single GFM table (`128`).
  static const int defaultMaxTableColumns = 128;

  /// Default maximum number of body rows parsed in a single GFM table (`10000`).
  static const int defaultMaxTableRows = 10000;

  /// Default maximum total raw HTML byte/code-unit output budget (`250000`).
  static const int defaultMaxHtmlBytes = 250000;

  /// Default maximum inline token / delimiter budget (`500000`).
  static const int defaultMaxTokens = 500000;

  /// Maximum accepted Markdown input length in UTF-16 code units.
  final int maxInputLength;

  /// Maximum allowed block and inline container nesting depth.
  final int maxNestingDepth;

  /// Maximum number of block nodes permitted during parsing.
  final int maxBlocks;

  /// Maximum number of columns permitted per table.
  final int maxTableColumns;

  /// Maximum number of body rows permitted per table.
  final int maxTableRows;

  /// Maximum cumulative raw HTML size allowed before escaping/truncation.
  final int maxHtmlBytes;

  /// Maximum inline scanner/delimiter budget per document.
  final int maxTokens;

  /// Returns a copy of these budgets with the specified fields replaced.
  MarkdownBudgets copyWith({
    int? maxInputLength,
    int? maxNestingDepth,
    int? maxBlocks,
    int? maxTableColumns,
    int? maxTableRows,
    int? maxHtmlBytes,
    int? maxTokens,
  }) {
    return MarkdownBudgets(
      maxInputLength: maxInputLength ?? this.maxInputLength,
      maxNestingDepth: maxNestingDepth ?? this.maxNestingDepth,
      maxBlocks: maxBlocks ?? this.maxBlocks,
      maxTableColumns: maxTableColumns ?? this.maxTableColumns,
      maxTableRows: maxTableRows ?? this.maxTableRows,
      maxHtmlBytes: maxHtmlBytes ?? this.maxHtmlBytes,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownBudgets &&
          maxInputLength == other.maxInputLength &&
          maxNestingDepth == other.maxNestingDepth &&
          maxBlocks == other.maxBlocks &&
          maxTableColumns == other.maxTableColumns &&
          maxTableRows == other.maxTableRows &&
          maxHtmlBytes == other.maxHtmlBytes &&
          maxTokens == other.maxTokens;

  @override
  int get hashCode => Object.hash(
    maxInputLength,
    maxNestingDepth,
    maxBlocks,
    maxTableColumns,
    maxTableRows,
    maxHtmlBytes,
    maxTokens,
  );

  @override
  String toString() =>
      'MarkdownBudgets('
      'maxInputLength: $maxInputLength, '
      'maxNestingDepth: $maxNestingDepth, '
      'maxBlocks: $maxBlocks, '
      'maxTableColumns: $maxTableColumns, '
      'maxTableRows: $maxTableRows, '
      'maxHtmlBytes: $maxHtmlBytes, '
      'maxTokens: $maxTokens)';
}
