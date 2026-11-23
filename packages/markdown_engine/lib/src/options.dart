import 'package:meta/meta.dart';

import 'budgets.dart';
import 'security.dart';

/// Configuration options controlling Markdown parsing, extension support,
/// sanitization, and complexity budgets.
@immutable
final class MarkdownOptions {
  /// Creates Markdown parsing and rendering options.
  const MarkdownOptions({
    this.gfmTables = true,
    this.gfmStrikethrough = true,
    this.gfmTaskLists = true,
    this.gfmAutolinks = true,
    this.gfmTagFilter = true,
    this.footnotes = false,
    this.alerts = false,
    this.frontmatter = false,
    this.definitionLists = false,
    this.math = false,
    this.headingSlugs = true,
    this.highlight = false,
    this.subscript = false,
    this.superscript = false,
    this.emoji = false,
    this.smartPunctuation = false,
    this.explicitHeadingIds = false,
    this.detailsBlocks = false,
    this.figureBlocks = false,
    this.alignedBlocks = false,
    this.kbd = false,
    this.abbreviations = false,
    this.inlineBreaks = false,
    this.sanitizeHtml = false,
    this.sanitizeUrls = true,
    this.collapseNestedStrong = false,
    int? maxInputLength,
    int? maxNestingDepth,
    this.budgets = const MarkdownBudgets(),
    this.urlPolicy = const MarkdownUrlPolicy.strict(),
  }) : _maxInputLength = maxInputLength,
       _maxNestingDepth = maxNestingDepth,
       assert(
         maxInputLength == null || maxInputLength >= 0,
         'maxInputLength must be non-negative',
       ),
       assert(
         maxNestingDepth == null || maxNestingDepth >= 0,
         'maxNestingDepth must be non-negative',
       );

  /// Strict CommonMark `0.31.2` configuration with extensions disabled.
  const MarkdownOptions.commonMark({
    this.sanitizeHtml = false,
    this.sanitizeUrls = true,
    this.collapseNestedStrong = false,
    int? maxInputLength,
    int? maxNestingDepth,
    this.budgets = const MarkdownBudgets(),
    this.urlPolicy = const MarkdownUrlPolicy(),
  }) : gfmTables = false,
       gfmStrikethrough = false,
       gfmTaskLists = false,
       gfmAutolinks = false,
       gfmTagFilter = false,
       footnotes = false,
       alerts = false,
       frontmatter = false,
       definitionLists = false,
       math = false,
       headingSlugs = false,
       highlight = false,
       subscript = false,
       superscript = false,
       emoji = false,
       smartPunctuation = false,
       explicitHeadingIds = false,
       detailsBlocks = false,
       figureBlocks = false,
       alignedBlocks = false,
       kbd = false,
       abbreviations = false,
       inlineBreaks = false,
       _maxInputLength = maxInputLength,
       _maxNestingDepth = maxNestingDepth,
       assert(
         maxInputLength == null || maxInputLength >= 0,
         'maxInputLength must be non-negative',
       ),
       assert(
         maxNestingDepth == null || maxNestingDepth >= 0,
         'maxNestingDepth must be non-negative',
       );

  /// Standard GitHub Flavored Markdown (`0.29.0.gfm.13`) configuration.
  const MarkdownOptions.gfm({
    this.footnotes = true,
    this.alerts = false,
    this.frontmatter = false,
    this.definitionLists = false,
    this.math = false,
    this.headingSlugs = true,
    this.highlight = false,
    this.subscript = false,
    this.superscript = false,
    this.emoji = false,
    this.smartPunctuation = false,
    this.explicitHeadingIds = false,
    this.detailsBlocks = false,
    this.figureBlocks = false,
    this.alignedBlocks = false,
    this.kbd = false,
    this.abbreviations = false,
    this.inlineBreaks = false,
    this.sanitizeHtml = false,
    this.sanitizeUrls = true,
    this.collapseNestedStrong = false,
    int? maxInputLength,
    int? maxNestingDepth,
    this.budgets = const MarkdownBudgets(),
    this.urlPolicy = const MarkdownUrlPolicy(),
  }) : gfmTables = true,
       gfmStrikethrough = true,
       gfmTaskLists = true,
       gfmAutolinks = true,
       gfmTagFilter = true,
       _maxInputLength = maxInputLength,
       _maxNestingDepth = maxNestingDepth,
       assert(
         maxInputLength == null || maxInputLength >= 0,
         'maxInputLength must be non-negative',
       ),
       assert(
         maxNestingDepth == null || maxNestingDepth >= 0,
         'maxNestingDepth must be non-negative',
       );

  /// Extended Markdown preset enabling GFM and all optional extensions.
  const MarkdownOptions.extended({
    this.sanitizeHtml = false,
    this.sanitizeUrls = true,
    this.collapseNestedStrong = false,
    int? maxInputLength,
    int? maxNestingDepth,
    this.budgets = const MarkdownBudgets(),
    this.urlPolicy = const MarkdownUrlPolicy.strict(),
  }) : gfmTables = true,
       gfmStrikethrough = true,
       gfmTaskLists = true,
       gfmAutolinks = true,
       gfmTagFilter = true,
       footnotes = true,
       alerts = true,
       frontmatter = true,
       definitionLists = true,
       math = true,
       headingSlugs = true,
       highlight = true,
       subscript = true,
       superscript = true,
       emoji = true,
       smartPunctuation = true,
       explicitHeadingIds = true,
       detailsBlocks = true,
       figureBlocks = true,
       alignedBlocks = true,
       kbd = true,
       abbreviations = true,
       inlineBreaks = true,
       _maxInputLength = maxInputLength,
       _maxNestingDepth = maxNestingDepth,
       assert(
         maxInputLength == null || maxInputLength >= 0,
         'maxInputLength must be non-negative',
       ),
       assert(
         maxNestingDepth == null || maxNestingDepth >= 0,
         'maxNestingDepth must be non-negative',
       );

  /// Default maximum input document length in UTF-16 code units (`500000`).
  static const int defaultMaxInputLength =
      MarkdownBudgets.defaultMaxInputLength;

  /// Default maximum block or inline nesting depth (`64`).
  static const int defaultMaxNestingDepth =
      MarkdownBudgets.defaultMaxNestingDepth;

  /// Enables GFM pipe tables.
  final bool gfmTables;

  /// Enables GFM strikethrough (`~...~` / `~~...~~`).
  final bool gfmStrikethrough;

  /// Enables GFM task list checkboxes (`- [ ]` / `- [x]`).
  final bool gfmTaskLists;

  /// Enables GFM extended autolinks (`www.`, `http(s)://`, emails).
  final bool gfmAutolinks;

  /// Enables GFM disallowed raw HTML tag filtering.
  final bool gfmTagFilter;

  /// Enables footnote definitions and inline footnote references.
  final bool footnotes;

  /// Enables GitHub-style blockquote alerts (`[!NOTE]`, `[!WARNING]`, etc.).
  final bool alerts;

  /// Enables leading YAML or TOML document frontmatter extraction.
  final bool frontmatter;

  /// Enables PHP Markdown Extra style definition lists.
  final bool definitionLists;

  /// Enables inline and display math spans (`$...$`, `$$...$$`).
  final bool math;

  /// Enables deterministic GitHub-style heading anchor slug generation.
  final bool headingSlugs;

  /// Enables inline highlight syntax (`==text==`).
  final bool highlight;

  /// Enables inline subscript syntax (`~text~`) without breaking `~~strike~~`.
  final bool subscript;

  /// Enables inline superscript syntax (`^text^`).
  final bool superscript;

  /// Enables standard emoji shortcode expansion (`:rocket:`, etc.).
  final bool emoji;

  /// Enables smart punctuation (`--`, `---`, `...`, and curly quotes).
  final bool smartPunctuation;

  /// Enables explicit heading anchor IDs (`# Heading {#custom-id}`).
  final bool explicitHeadingIds;

  /// Enables structured `DetailsBlockNode` extraction for `<details>` blocks.
  final bool detailsBlocks;

  /// Enables structured `FigureBlockNode` extraction for `<figure>` blocks.
  final bool figureBlocks;

  /// Enables structured `AlignedBlockNode` extraction for `<div align="...">`.
  final bool alignedBlocks;

  /// Enables structured `KbdInlineNode` parsing for `<kbd>...</kbd>`.
  final bool kbd;

  /// Enables abbreviation definitions (`*[ABBR]: Expansion`) and `AbbrInlineNode`.
  final bool abbreviations;

  /// Parses inline `<br>` / `<br />` tags into `InlineBreakNode`s.
  final bool inlineBreaks;

  /// Strips or escapes unsafe raw HTML elements and event-handler attributes.
  final bool sanitizeHtml;

  /// Filters unsafe URI schemes such as `javascript:` and `vbscript:`.
  final bool sanitizeUrls;

  /// Collapses nested `<strong>` tags during HTML rendering to match `cmark 0.29`.
  final bool collapseNestedStrong;

  final int? _maxInputLength;
  final int? _maxNestingDepth;

  /// Complexity and resource limits applied during parsing.
  final MarkdownBudgets budgets;

  /// URL scheme and host validation policy used when [sanitizeUrls] is true.
  final MarkdownUrlPolicy urlPolicy;

  /// Maximum accepted Markdown input length in UTF-16 code units.
  int get maxInputLength => _maxInputLength ?? budgets.maxInputLength;

  /// Maximum allowed block and inline container nesting depth.
  int get maxNestingDepth => _maxNestingDepth ?? budgets.maxNestingDepth;

  /// Effective [MarkdownBudgets] merging legacy [maxInputLength] and
  /// [maxNestingDepth] overrides when provided.
  MarkdownBudgets get effectiveBudgets {
    if (_maxInputLength == null && _maxNestingDepth == null) {
      return budgets;
    }
    return budgets.copyWith(
      maxInputLength: _maxInputLength,
      maxNestingDepth: _maxNestingDepth,
    );
  }

  /// Returns a copy of these options with the specified fields replaced.
  MarkdownOptions copyWith({
    bool? gfmTables,
    bool? gfmStrikethrough,
    bool? gfmTaskLists,
    bool? gfmAutolinks,
    bool? gfmTagFilter,
    bool? footnotes,
    bool? alerts,
    bool? frontmatter,
    bool? definitionLists,
    bool? math,
    bool? headingSlugs,
    bool? highlight,
    bool? subscript,
    bool? superscript,
    bool? emoji,
    bool? smartPunctuation,
    bool? explicitHeadingIds,
    bool? detailsBlocks,
    bool? figureBlocks,
    bool? alignedBlocks,
    bool? kbd,
    bool? abbreviations,
    bool? inlineBreaks,
    bool? sanitizeHtml,
    bool? sanitizeUrls,
    bool? collapseNestedStrong,
    int? maxInputLength,
    int? maxNestingDepth,
    MarkdownBudgets? budgets,
    MarkdownUrlPolicy? urlPolicy,
  }) {
    return MarkdownOptions(
      gfmTables: gfmTables ?? this.gfmTables,
      gfmStrikethrough: gfmStrikethrough ?? this.gfmStrikethrough,
      gfmTaskLists: gfmTaskLists ?? this.gfmTaskLists,
      gfmAutolinks: gfmAutolinks ?? this.gfmAutolinks,
      gfmTagFilter: gfmTagFilter ?? this.gfmTagFilter,
      footnotes: footnotes ?? this.footnotes,
      alerts: alerts ?? this.alerts,
      frontmatter: frontmatter ?? this.frontmatter,
      definitionLists: definitionLists ?? this.definitionLists,
      math: math ?? this.math,
      headingSlugs: headingSlugs ?? this.headingSlugs,
      highlight: highlight ?? this.highlight,
      subscript: subscript ?? this.subscript,
      superscript: superscript ?? this.superscript,
      emoji: emoji ?? this.emoji,
      smartPunctuation: smartPunctuation ?? this.smartPunctuation,
      explicitHeadingIds: explicitHeadingIds ?? this.explicitHeadingIds,
      detailsBlocks: detailsBlocks ?? this.detailsBlocks,
      figureBlocks: figureBlocks ?? this.figureBlocks,
      alignedBlocks: alignedBlocks ?? this.alignedBlocks,
      kbd: kbd ?? this.kbd,
      abbreviations: abbreviations ?? this.abbreviations,
      inlineBreaks: inlineBreaks ?? this.inlineBreaks,
      sanitizeHtml: sanitizeHtml ?? this.sanitizeHtml,
      sanitizeUrls: sanitizeUrls ?? this.sanitizeUrls,
      collapseNestedStrong: collapseNestedStrong ?? this.collapseNestedStrong,
      maxInputLength: maxInputLength ?? _maxInputLength,
      maxNestingDepth: maxNestingDepth ?? _maxNestingDepth,
      budgets: budgets ?? this.budgets,
      urlPolicy: urlPolicy ?? this.urlPolicy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownOptions &&
          gfmTables == other.gfmTables &&
          gfmStrikethrough == other.gfmStrikethrough &&
          gfmTaskLists == other.gfmTaskLists &&
          gfmAutolinks == other.gfmAutolinks &&
          gfmTagFilter == other.gfmTagFilter &&
          footnotes == other.footnotes &&
          alerts == other.alerts &&
          frontmatter == other.frontmatter &&
          definitionLists == other.definitionLists &&
          math == other.math &&
          headingSlugs == other.headingSlugs &&
          highlight == other.highlight &&
          subscript == other.subscript &&
          superscript == other.superscript &&
          emoji == other.emoji &&
          smartPunctuation == other.smartPunctuation &&
          explicitHeadingIds == other.explicitHeadingIds &&
          detailsBlocks == other.detailsBlocks &&
          figureBlocks == other.figureBlocks &&
          alignedBlocks == other.alignedBlocks &&
          kbd == other.kbd &&
          abbreviations == other.abbreviations &&
          inlineBreaks == other.inlineBreaks &&
          sanitizeHtml == other.sanitizeHtml &&
          sanitizeUrls == other.sanitizeUrls &&
          collapseNestedStrong == other.collapseNestedStrong &&
          maxInputLength == other.maxInputLength &&
          maxNestingDepth == other.maxNestingDepth &&
          budgets == other.budgets &&
          urlPolicy == other.urlPolicy;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    gfmTables,
    gfmStrikethrough,
    gfmTaskLists,
    gfmAutolinks,
    gfmTagFilter,
    footnotes,
    alerts,
    frontmatter,
    definitionLists,
    math,
    headingSlugs,
    highlight,
    subscript,
    superscript,
    emoji,
    smartPunctuation,
    explicitHeadingIds,
    detailsBlocks,
    figureBlocks,
    alignedBlocks,
    kbd,
    abbreviations,
    inlineBreaks,
    sanitizeHtml,
    sanitizeUrls,
    collapseNestedStrong,
    maxInputLength,
    maxNestingDepth,
    budgets,
    urlPolicy,
  ]);

  @override
  String toString() =>
      'MarkdownOptions('
      'gfmTables: $gfmTables, '
      'gfmStrikethrough: $gfmStrikethrough, '
      'gfmTaskLists: $gfmTaskLists, '
      'gfmAutolinks: $gfmAutolinks, '
      'gfmTagFilter: $gfmTagFilter, '
      'footnotes: $footnotes, '
      'alerts: $alerts, '
      'frontmatter: $frontmatter, '
      'definitionLists: $definitionLists, '
      'math: $math, '
      'headingSlugs: $headingSlugs, '
      'highlight: $highlight, '
      'subscript: $subscript, '
      'superscript: $superscript)';
}
