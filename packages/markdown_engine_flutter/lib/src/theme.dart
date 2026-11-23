// Keeps ColorScheme/Theme/ThemeData compatibility with Flutter 3.32-3.50+ callers.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show ColorScheme, Theme, ThemeData;
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart' show AlertKind;

/// Color triple styling a single GitHub-style alert callout block.
@immutable
final class MarkdownAlertColors {
  /// Creates a [MarkdownAlertColors] specification.
  const MarkdownAlertColors({
    required this.border,
    required this.background,
    required this.foreground,
  });

  /// Accent color painted along the alert leading border.
  final Color border;

  /// Soft surface tint painted behind the alert body.
  final Color background;

  /// Foreground color used for the alert icon and title label.
  final Color foreground;

  /// Returns a copy with selected color fields replaced.
  MarkdownAlertColors copyWith({
    Color? border,
    Color? background,
    Color? foreground,
  }) {
    return MarkdownAlertColors(
      border: border ?? this.border,
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
    );
  }

  /// Linearly interpolates between two [MarkdownAlertColors] instances.
  static MarkdownAlertColors lerp(
    MarkdownAlertColors a,
    MarkdownAlertColors b,
    double t,
  ) {
    return MarkdownAlertColors(
      border: Color.lerp(a.border, b.border, t) ?? b.border,
      background: Color.lerp(a.background, b.background, t) ?? b.background,
      foreground: Color.lerp(a.foreground, b.foreground, t) ?? b.foreground,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownAlertColors &&
          border == other.border &&
          background == other.background &&
          foreground == other.foreground;

  @override
  int get hashCode => Object.hash(border, background, foreground);
}

/// Complete palette styling all five [AlertKind] callout severities.
@immutable
final class MarkdownAlertPalette {
  /// Creates a [MarkdownAlertPalette] for all five GitHub alert kinds.
  const MarkdownAlertPalette({
    required this.note,
    required this.tip,
    required this.important,
    required this.warning,
    required this.caution,
  });

  /// Default light-mode alert palette aligned with GitHub callout conventions.
  const MarkdownAlertPalette.light()
    : note = const MarkdownAlertColors(
        border: Color(0xFF0969DA),
        background: Color(0x140969DA),
        foreground: Color(0xFF0969DA),
      ),
      tip = const MarkdownAlertColors(
        border: Color(0xFF1A7F37),
        background: Color(0x141A7F37),
        foreground: Color(0xFF1A7F37),
      ),
      important = const MarkdownAlertColors(
        border: Color(0xFF8250DF),
        background: Color(0x148250DF),
        foreground: Color(0xFF8250DF),
      ),
      warning = const MarkdownAlertColors(
        border: Color(0xFF9A6700),
        background: Color(0x18D29922),
        foreground: Color(0xFF9A6700),
      ),
      caution = const MarkdownAlertColors(
        border: Color(0xFFCF222E),
        background: Color(0x14CF222E),
        foreground: Color(0xFFCF222E),
      );

  /// Default dark-mode alert palette with accessible high-contrast tones.
  const MarkdownAlertPalette.dark()
    : note = const MarkdownAlertColors(
        border: Color(0xFF58A6FF),
        background: Color(0x2258A6FF),
        foreground: Color(0xFF79C0FF),
      ),
      tip = const MarkdownAlertColors(
        border: Color(0xFF3FB950),
        background: Color(0x223FB950),
        foreground: Color(0xFF56D364),
      ),
      important = const MarkdownAlertColors(
        border: Color(0xFFA371F7),
        background: Color(0x22A371F7),
        foreground: Color(0xFFD2A8FF),
      ),
      warning = const MarkdownAlertColors(
        border: Color(0xFFD29922),
        background: Color(0x22D29922),
        foreground: Color(0xFFE3B341),
      ),
      caution = const MarkdownAlertColors(
        border: Color(0xFFF85149),
        background: Color(0x22F85149),
        foreground: Color(0xFFFF7B72),
      );

  /// Colors for `[!NOTE]` callouts.
  final MarkdownAlertColors note;

  /// Colors for `[!TIP]` callouts.
  final MarkdownAlertColors tip;

  /// Colors for `[!IMPORTANT]` callouts.
  final MarkdownAlertColors important;

  /// Colors for `[!WARNING]` callouts.
  final MarkdownAlertColors warning;

  /// Colors for `[!CAUTION]` callouts.
  final MarkdownAlertColors caution;

  /// Returns the [MarkdownAlertColors] assigned to [kind].
  MarkdownAlertColors forKind(AlertKind kind) {
    switch (kind) {
      case AlertKind.note:
        return note;
      case AlertKind.tip:
        return tip;
      case AlertKind.important:
        return important;
      case AlertKind.warning:
        return warning;
      case AlertKind.caution:
        return caution;
    }
  }

  /// Returns a copy of this palette with selected alert kinds replaced.
  MarkdownAlertPalette copyWith({
    MarkdownAlertColors? note,
    MarkdownAlertColors? tip,
    MarkdownAlertColors? important,
    MarkdownAlertColors? warning,
    MarkdownAlertColors? caution,
  }) {
    return MarkdownAlertPalette(
      note: note ?? this.note,
      tip: tip ?? this.tip,
      important: important ?? this.important,
      warning: warning ?? this.warning,
      caution: caution ?? this.caution,
    );
  }

  /// Linearly interpolates between two [MarkdownAlertPalette] instances.
  static MarkdownAlertPalette lerp(
    MarkdownAlertPalette a,
    MarkdownAlertPalette b,
    double t,
  ) {
    return MarkdownAlertPalette(
      note: MarkdownAlertColors.lerp(a.note, b.note, t),
      tip: MarkdownAlertColors.lerp(a.tip, b.tip, t),
      important: MarkdownAlertColors.lerp(a.important, b.important, t),
      warning: MarkdownAlertColors.lerp(a.warning, b.warning, t),
      caution: MarkdownAlertColors.lerp(a.caution, b.caution, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownAlertPalette &&
          note == other.note &&
          tip == other.tip &&
          important == other.important &&
          warning == other.warning &&
          caution == other.caution;

  @override
  int get hashCode => Object.hash(note, tip, important, warning, caution);
}

/// Immutable theme values governing Markdown colors, surfaces, alert palettes,
/// typography scales, spacing, and font families in Flutter widgets.
@immutable
final class MarkdownThemeData {
  /// Creates a custom [MarkdownThemeData].
  const MarkdownThemeData({
    this.brightness = Brightness.light,
    required this.foreground,
    required this.muted,
    required this.accent,
    this.linkColor,
    required this.codeBackground,
    this.codeForeground,
    required this.border,
    this.blockquoteBorder,
    this.blockquoteBackground,
    this.tableBorder,
    this.tableHeaderBackground,
    this.tableStripeBackground,
    this.highlightFill = const Color(0x66FDE047),
    this.alertPalette = const MarkdownAlertPalette.light(),
    this.fontSize = 16.0,
    this.lineHeight = 1.55,
    this.codeFontSize = 14.0,
    this.codeLineHeight = 1.45,
    this.blockSpacing = 12.0,
    this.h1Scale = 2.0,
    this.h2Scale = 1.6,
    this.h3Scale = 1.35,
    this.h4Scale = 1.15,
    this.h5Scale = 1.0,
    this.h6Scale = 0.9,
    this.headingLineHeight = 1.25,
    this.fontFamily,
    this.codeFontFamily,
  });

  /// Built-in high-contrast light Markdown theme.
  const MarkdownThemeData.light({
    this.fontSize = 16.0,
    this.lineHeight = 1.55,
    this.codeFontSize = 14.0,
    this.codeLineHeight = 1.45,
    this.blockSpacing = 12.0,
    this.h1Scale = 2.0,
    this.h2Scale = 1.6,
    this.h3Scale = 1.35,
    this.h4Scale = 1.15,
    this.h5Scale = 1.0,
    this.h6Scale = 0.9,
    this.headingLineHeight = 1.25,
    this.fontFamily,
    this.codeFontFamily,
  }) : brightness = Brightness.light,
       foreground = const Color(0xFF0F172A),
       muted = const Color(0xFF475569),
       accent = const Color(0xFF0284C7),
       linkColor = const Color(0xFF0284C7),
       codeBackground = const Color(0xFFF1F5F9),
       codeForeground = const Color(0xFF0F172A),
       border = const Color(0xFFE2E8F0),
       blockquoteBorder = const Color(0xFFCBD5E1),
       blockquoteBackground = const Color(0xFFF8FAFC),
       tableBorder = const Color(0xFFCBD5E1),
       tableHeaderBackground = const Color(0xFFF1F5F9),
       tableStripeBackground = const Color(0xFFF8FAFC),
       highlightFill = const Color(0x66FDE047),
       alertPalette = const MarkdownAlertPalette.light();

  /// Built-in high-contrast dark Markdown theme.
  const MarkdownThemeData.dark({
    this.fontSize = 16.0,
    this.lineHeight = 1.55,
    this.codeFontSize = 14.0,
    this.codeLineHeight = 1.45,
    this.blockSpacing = 12.0,
    this.h1Scale = 2.0,
    this.h2Scale = 1.6,
    this.h3Scale = 1.35,
    this.h4Scale = 1.15,
    this.h5Scale = 1.0,
    this.h6Scale = 0.9,
    this.headingLineHeight = 1.25,
    this.fontFamily,
    this.codeFontFamily,
  }) : brightness = Brightness.dark,
       foreground = const Color(0xFFE2E8F0),
       muted = const Color(0xFF94A3B8),
       accent = const Color(0xFF38BDF8),
       linkColor = const Color(0xFF38BDF8),
       codeBackground = const Color(0xFF1E293B),
       codeForeground = const Color(0xFFE2E8F0),
       border = const Color(0xFF334155),
       blockquoteBorder = const Color(0xFF475569),
       blockquoteBackground = const Color(0xFF0F172A),
       tableBorder = const Color(0xFF334155),
       tableHeaderBackground = const Color(0xFF1E293B),
       tableStripeBackground = const Color(0xFF162032),
       highlightFill = const Color(0x55CA8A04),
       alertPalette = const MarkdownAlertPalette.dark();

  /// Derives a [MarkdownThemeData] from a Material [ColorScheme].
  factory MarkdownThemeData.fromColorScheme(
    ColorScheme scheme, {
    double fontSize = 16.0,
    String? fontFamily,
    String? codeFontFamily,
  }) {
    final bool isDark = scheme.brightness == Brightness.dark;
    final Color codeBg = scheme.surfaceContainerHighest.withValues(
      alpha: isDark ? 0.6 : 0.55,
    );
    return MarkdownThemeData(
      brightness: scheme.brightness,
      foreground: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      accent: scheme.primary,
      linkColor: scheme.primary,
      codeBackground: codeBg,
      codeForeground: scheme.onSurface,
      border: scheme.outlineVariant,
      blockquoteBorder: scheme.outline,
      blockquoteBackground: scheme.surfaceContainerLow,
      tableBorder: scheme.outlineVariant,
      tableHeaderBackground: scheme.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.65 : 0.7,
      ),
      tableStripeBackground: scheme.surfaceContainerLow.withValues(alpha: 0.65),
      highlightFill: isDark ? const Color(0x55CA8A04) : const Color(0x66FDE047),
      alertPalette: isDark
          ? const MarkdownAlertPalette.dark()
          : const MarkdownAlertPalette.light(),
      fontSize: fontSize,
      codeFontSize: (fontSize * 0.875).clamp(11.0, 28.0),
      fontFamily: fontFamily,
      codeFontFamily: codeFontFamily,
    );
  }

  /// Derives a [MarkdownThemeData] from the ambient Material [Theme] in
  /// [context].
  factory MarkdownThemeData.fromTheme(
    BuildContext context, {
    double? fontSize,
    String? codeFontFamily,
  }) {
    final ThemeData themeData = Theme.of(context);
    final double resolvedSize =
        fontSize ??
        themeData.textTheme.bodyLarge?.fontSize ??
        themeData.textTheme.bodyMedium?.fontSize ??
        16.0;
    return MarkdownThemeData.fromColorScheme(
      themeData.colorScheme,
      fontSize: resolvedSize,
      fontFamily: themeData.textTheme.bodyMedium?.fontFamily,
      codeFontFamily: codeFontFamily,
    );
  }

  /// Default fallback theme used when no ancestor theme is configured.
  static const MarkdownThemeData fallback = MarkdownThemeData.light();

  /// Platform monospace fallback chain used for code spans and code blocks.
  static const List<String> defaultCodeFontFallback = <String>[
    'SF Mono',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'Courier New',
    'monospace',
  ];

  /// Brightness mode used for theme-aware widgets such as `<picture>` sources.
  final Brightness brightness;

  /// Primary text foreground color.
  final Color foreground;

  /// Secondary color for blockquotes, footnotes, metadata, and captions.
  final Color muted;

  /// Primary accent color for links and interactive accents.
  final Color accent;

  /// Optional explicit link color overriding [accent].
  final Color? linkColor;

  /// Surface background color for code spans and fenced code blocks.
  final Color codeBackground;

  /// Optional explicit foreground color for code spans and fenced code blocks.
  final Color? codeForeground;

  /// General border and horizontal rule color.
  final Color border;

  /// Optional leading bar color for blockquotes overriding [border].
  final Color? blockquoteBorder;

  /// Optional container background tint for blockquotes.
  final Color? blockquoteBackground;

  /// Optional table grid border color overriding [border].
  final Color? tableBorder;

  /// Optional background color for table header rows.
  final Color? tableHeaderBackground;

  /// Optional alternating zebra stripe background color for table body rows.
  final Color? tableStripeBackground;

  /// Background fill color applied to highlighted inline spans (`==text==`).
  final Color highlightFill;

  /// Palette styling all five GitHub-style alert callouts.
  final MarkdownAlertPalette alertPalette;

  /// Base logical font size for body paragraphs.
  final double fontSize;

  /// Line-height multiplier for body paragraphs and lists.
  final double lineHeight;

  /// Base logical font size for fenced code blocks.
  final double codeFontSize;

  /// Line-height multiplier for fenced code blocks.
  final double codeLineHeight;

  /// Vertical spacing between adjacent top-level Markdown blocks.
  final double blockSpacing;

  /// Font-size scale multiplier for H1 headings relative to [fontSize].
  final double h1Scale;

  /// Font-size scale multiplier for H2 headings relative to [fontSize].
  final double h2Scale;

  /// Font-size scale multiplier for H3 headings relative to [fontSize].
  final double h3Scale;

  /// Font-size scale multiplier for H4 headings relative to [fontSize].
  final double h4Scale;

  /// Font-size scale multiplier for H5 headings relative to [fontSize].
  final double h5Scale;

  /// Font-size scale multiplier for H6 headings relative to [fontSize].
  final double h6Scale;

  /// Line-height multiplier applied to headings.
  final double headingLineHeight;

  /// Optional primary body/heading font family.
  final String? fontFamily;

  /// Optional monospace font family for inline code spans and code blocks.
  final String? codeFontFamily;

  /// Resolved link foreground color (`linkColor ?? accent`).
  Color get effectiveLinkColor => linkColor ?? accent;

  /// Resolved code foreground color (`codeForeground ?? foreground`).
  Color get effectiveCodeForeground => codeForeground ?? foreground;

  /// Resolved blockquote border color (`blockquoteBorder ?? border`).
  Color get effectiveBlockquoteBorder => blockquoteBorder ?? border;

  /// Resolved blockquote background color.
  Color get effectiveBlockquoteBackground =>
      blockquoteBackground ?? codeBackground.withValues(alpha: 0.45);

  /// Resolved table grid border color (`tableBorder ?? border`).
  Color get effectiveTableBorder => tableBorder ?? border;

  /// Resolved table header background color.
  Color get effectiveTableHeaderBackground =>
      tableHeaderBackground ?? codeBackground;

  /// Resolved table alternating row background color.
  Color get effectiveTableStripeBackground =>
      tableStripeBackground ?? codeBackground.withValues(alpha: 0.35);

  /// Resolved monospace font family (`codeFontFamily ?? 'monospace'`).
  String get effectiveCodeFontFamily => codeFontFamily ?? 'monospace';

  /// Computes the logical font size for a heading [level] (`1` through `6`).
  double headingFontSize(int level) {
    switch (level) {
      case 1:
        return fontSize * h1Scale;
      case 2:
        return fontSize * h2Scale;
      case 3:
        return fontSize * h3Scale;
      case 4:
        return fontSize * h4Scale;
      case 5:
        return fontSize * h5Scale;
      default:
        return fontSize * h6Scale;
    }
  }

  /// Builds the base [TextStyle] for body prose.
  TextStyle bodyTextStyle({Color? color}) {
    return TextStyle(
      color: color ?? foreground,
      fontSize: fontSize,
      height: lineHeight,
      fontFamily: fontFamily,
    );
  }

  /// Builds the [TextStyle] for a heading of [level] (`1` through `6`).
  TextStyle headingTextStyle(int level) {
    return TextStyle(
      color: level == 6 ? muted : foreground,
      fontSize: headingFontSize(level),
      height: headingLineHeight,
      fontWeight: FontWeight.w700,
      fontFamily: fontFamily,
    );
  }

  /// Builds the monospace [TextStyle] for fenced code blocks.
  TextStyle codeTextStyle({double? fontSizeOverride}) {
    return TextStyle(
      color: effectiveCodeForeground,
      fontSize: fontSizeOverride ?? codeFontSize,
      height: codeLineHeight,
      fontFamily: effectiveCodeFontFamily,
      fontFamilyFallback: defaultCodeFontFallback,
    );
  }

  /// Returns a copy of this theme with selected fields replaced.
  MarkdownThemeData copyWith({
    Brightness? brightness,
    Color? foreground,
    Color? muted,
    Color? accent,
    Color? linkColor,
    Color? codeBackground,
    Color? codeForeground,
    Color? border,
    Color? blockquoteBorder,
    Color? blockquoteBackground,
    Color? tableBorder,
    Color? tableHeaderBackground,
    Color? tableStripeBackground,
    Color? highlightFill,
    MarkdownAlertPalette? alertPalette,
    double? fontSize,
    double? lineHeight,
    double? codeFontSize,
    double? codeLineHeight,
    double? blockSpacing,
    double? h1Scale,
    double? h2Scale,
    double? h3Scale,
    double? h4Scale,
    double? h5Scale,
    double? h6Scale,
    double? headingLineHeight,
    String? fontFamily,
    String? codeFontFamily,
  }) {
    return MarkdownThemeData(
      brightness: brightness ?? this.brightness,
      foreground: foreground ?? this.foreground,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      linkColor: linkColor ?? this.linkColor,
      codeBackground: codeBackground ?? this.codeBackground,
      codeForeground: codeForeground ?? this.codeForeground,
      border: border ?? this.border,
      blockquoteBorder: blockquoteBorder ?? this.blockquoteBorder,
      blockquoteBackground: blockquoteBackground ?? this.blockquoteBackground,
      tableBorder: tableBorder ?? this.tableBorder,
      tableHeaderBackground:
          tableHeaderBackground ?? this.tableHeaderBackground,
      tableStripeBackground:
          tableStripeBackground ?? this.tableStripeBackground,
      highlightFill: highlightFill ?? this.highlightFill,
      alertPalette: alertPalette ?? this.alertPalette,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      codeFontSize: codeFontSize ?? this.codeFontSize,
      codeLineHeight: codeLineHeight ?? this.codeLineHeight,
      blockSpacing: blockSpacing ?? this.blockSpacing,
      h1Scale: h1Scale ?? this.h1Scale,
      h2Scale: h2Scale ?? this.h2Scale,
      h3Scale: h3Scale ?? this.h3Scale,
      h4Scale: h4Scale ?? this.h4Scale,
      h5Scale: h5Scale ?? this.h5Scale,
      h6Scale: h6Scale ?? this.h6Scale,
      headingLineHeight: headingLineHeight ?? this.headingLineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
    );
  }

  /// Linearly interpolates between two [MarkdownThemeData] instances.
  static MarkdownThemeData lerp(
    MarkdownThemeData a,
    MarkdownThemeData b,
    double t,
  ) {
    return MarkdownThemeData(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      foreground: Color.lerp(a.foreground, b.foreground, t) ?? b.foreground,
      muted: Color.lerp(a.muted, b.muted, t) ?? b.muted,
      accent: Color.lerp(a.accent, b.accent, t) ?? b.accent,
      linkColor: Color.lerp(a.effectiveLinkColor, b.effectiveLinkColor, t),
      codeBackground:
          Color.lerp(a.codeBackground, b.codeBackground, t) ?? b.codeBackground,
      codeForeground: Color.lerp(
        a.effectiveCodeForeground,
        b.effectiveCodeForeground,
        t,
      ),
      border: Color.lerp(a.border, b.border, t) ?? b.border,
      blockquoteBorder: Color.lerp(
        a.effectiveBlockquoteBorder,
        b.effectiveBlockquoteBorder,
        t,
      ),
      blockquoteBackground: Color.lerp(
        a.effectiveBlockquoteBackground,
        b.effectiveBlockquoteBackground,
        t,
      ),
      tableBorder: Color.lerp(
        a.effectiveTableBorder,
        b.effectiveTableBorder,
        t,
      ),
      tableHeaderBackground: Color.lerp(
        a.effectiveTableHeaderBackground,
        b.effectiveTableHeaderBackground,
        t,
      ),
      tableStripeBackground: Color.lerp(
        a.effectiveTableStripeBackground,
        b.effectiveTableStripeBackground,
        t,
      ),
      highlightFill:
          Color.lerp(a.highlightFill, b.highlightFill, t) ?? b.highlightFill,
      alertPalette: MarkdownAlertPalette.lerp(
        a.alertPalette,
        b.alertPalette,
        t,
      ),
      fontSize: a.fontSize + (b.fontSize - a.fontSize) * t,
      lineHeight: a.lineHeight + (b.lineHeight - a.lineHeight) * t,
      codeFontSize: a.codeFontSize + (b.codeFontSize - a.codeFontSize) * t,
      codeLineHeight:
          a.codeLineHeight + (b.codeLineHeight - a.codeLineHeight) * t,
      blockSpacing: a.blockSpacing + (b.blockSpacing - a.blockSpacing) * t,
      h1Scale: a.h1Scale + (b.h1Scale - a.h1Scale) * t,
      h2Scale: a.h2Scale + (b.h2Scale - a.h2Scale) * t,
      h3Scale: a.h3Scale + (b.h3Scale - a.h3Scale) * t,
      h4Scale: a.h4Scale + (b.h4Scale - a.h4Scale) * t,
      h5Scale: a.h5Scale + (b.h5Scale - a.h5Scale) * t,
      h6Scale: a.h6Scale + (b.h6Scale - a.h6Scale) * t,
      headingLineHeight:
          a.headingLineHeight + (b.headingLineHeight - a.headingLineHeight) * t,
      fontFamily: t < 0.5 ? a.fontFamily : b.fontFamily,
      codeFontFamily: t < 0.5 ? a.codeFontFamily : b.codeFontFamily,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownThemeData &&
          brightness == other.brightness &&
          foreground == other.foreground &&
          muted == other.muted &&
          accent == other.accent &&
          linkColor == other.linkColor &&
          codeBackground == other.codeBackground &&
          codeForeground == other.codeForeground &&
          border == other.border &&
          blockquoteBorder == other.blockquoteBorder &&
          blockquoteBackground == other.blockquoteBackground &&
          tableBorder == other.tableBorder &&
          tableHeaderBackground == other.tableHeaderBackground &&
          tableStripeBackground == other.tableStripeBackground &&
          highlightFill == other.highlightFill &&
          alertPalette == other.alertPalette &&
          fontSize == other.fontSize &&
          lineHeight == other.lineHeight &&
          codeFontSize == other.codeFontSize &&
          codeLineHeight == other.codeLineHeight &&
          blockSpacing == other.blockSpacing &&
          h1Scale == other.h1Scale &&
          h2Scale == other.h2Scale &&
          h3Scale == other.h3Scale &&
          h4Scale == other.h4Scale &&
          h5Scale == other.h5Scale &&
          h6Scale == other.h6Scale &&
          headingLineHeight == other.headingLineHeight &&
          fontFamily == other.fontFamily &&
          codeFontFamily == other.codeFontFamily;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    brightness,
    foreground,
    muted,
    accent,
    linkColor,
    codeBackground,
    codeForeground,
    border,
    blockquoteBorder,
    blockquoteBackground,
    tableBorder,
    tableHeaderBackground,
    tableStripeBackground,
    highlightFill,
    alertPalette,
    fontSize,
    lineHeight,
    codeFontSize,
    codeLineHeight,
    blockSpacing,
    h1Scale,
    h2Scale,
    h3Scale,
    h4Scale,
    h5Scale,
    h6Scale,
    headingLineHeight,
    fontFamily,
    codeFontFamily,
  ]);
}

/// Inherited theme supplying [MarkdownThemeData] to descendant Markdown widgets.
final class MarkdownTheme extends InheritedTheme {
  /// Creates an inherited Markdown theme wrapping [child].
  const MarkdownTheme({super.key, required this.data, required super.child});

  /// Theme colors and typography settings propagated to descendants.
  final MarkdownThemeData data;

  /// Returns the closest [MarkdownThemeData] ancestor, falling back to the
  /// active Material [Theme] in [context].
  static MarkdownThemeData of(BuildContext context) {
    final MarkdownTheme? inherited = context
        .dependOnInheritedWidgetOfExactType<MarkdownTheme>();
    if (inherited != null) {
      return inherited.data;
    }
    return MarkdownThemeData.fromTheme(context);
  }

  /// Returns the closest [MarkdownThemeData] ancestor, or `null` if absent.
  static MarkdownThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MarkdownTheme>()?.data;
  }

  @override
  Widget wrap(BuildContext context, Widget child) {
    return MarkdownTheme(data: data, child: child);
  }

  @override
  bool updateShouldNotify(MarkdownTheme oldWidget) => data != oldWidget.data;
}
