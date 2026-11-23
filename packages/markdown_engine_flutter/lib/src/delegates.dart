import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown_engine/markdown_engine.dart'
    show
        CodeBlockNode,
        ImageNode,
        MarkdownUrlPolicy,
        MathBlockNode,
        MathInlineNode;

/// Policy governing whether remote (`http://`, `https://`, or protocol-relative)
/// images are blocked, require explicit user consent, or load automatically.
enum MarkdownImagePolicy {
  /// Never load remote images; render a non-network placeholder instead.
  block,

  /// Display an interactive placeholder allowing the user to approve loading.
  ask,

  /// Load remote images permitted by [MarkdownUrlPolicy].
  load,
}

/// Builder returning a custom [InlineSpan] for an inline LaTeX [MathInlineNode].
///
/// The enclosing [linkRecognizer] is passed when the math span sits inside an
/// active sanitized hyperlink so tapping the formula can trigger the link.
typedef MarkdownMathInlineBuilder =
    InlineSpan Function(
      BuildContext context,
      MathInlineNode node,
      TextStyle style,
      GestureRecognizer? linkRecognizer,
    );

/// Builder returning a custom widget for a display LaTeX [MathBlockNode].
typedef MarkdownMathBlockBuilder =
    Widget Function(BuildContext context, MathBlockNode node);

/// Builder optionally returning a diagram widget for a fenced [CodeBlockNode]
/// (for example `mermaid` blocks), or `null` to fall back to code rendering.
typedef MarkdownDiagramBuilder =
    Widget? Function(BuildContext context, CodeBlockNode node);

/// Builder returning a custom widget for a [CodeBlockNode].
typedef MarkdownCodeBlockBuilder =
    Widget Function(BuildContext context, CodeBlockNode node);

/// Builder returning a custom widget for an allowed [ImageNode].
typedef MarkdownImageBuilder =
    Widget Function(BuildContext context, ImageNode node);

/// Callback invoked when the user taps an allowed link destination.
typedef MarkdownLinkTapCallback =
    void Function(String destination, String? title);

/// Callback invoked when the user taps an allowed `http` or `https` web URI.
typedef MarkdownWebLinkCallback = void Function(Uri uri);

/// Pluggable rendering hooks and security policies for Markdown widgets.
@immutable
final class MarkdownBuilderDelegates {
  /// Creates a [MarkdownBuilderDelegates] bundle.
  const MarkdownBuilderDelegates({
    this.imagePolicy = MarkdownImagePolicy.block,
    this.onLoadRemoteImages,
    this.mathInlineBuilder,
    this.mathBlockBuilder,
    this.diagramBuilder,
    this.codeBlockBuilder,
    this.imageBuilder,
    this.onTapLink,
    this.onOpenWebLink,
    this.urlPolicy,
  });

  /// Policy governing remote image loading (`block` by default for privacy).
  final MarkdownImagePolicy imagePolicy;

  /// Callback invoked when the user clicks "Load remote images" in
  /// [MarkdownImagePolicy.ask] mode.
  final VoidCallback? onLoadRemoteImages;

  /// Optional custom renderer for inline `$...$` math nodes.
  final MarkdownMathInlineBuilder? mathInlineBuilder;

  /// Optional custom renderer for display `$$...$$` math blocks.
  final MarkdownMathBlockBuilder? mathBlockBuilder;

  /// Optional custom diagram renderer inspected before [codeBlockBuilder].
  final MarkdownDiagramBuilder? diagramBuilder;

  /// Optional custom renderer overriding the default fenced code block widget.
  final MarkdownCodeBlockBuilder? codeBlockBuilder;

  /// Optional custom renderer for images permitted by [imagePolicy] and
  /// [MarkdownUrlPolicy].
  final MarkdownImageBuilder? imageBuilder;

  /// Callback invoked when any allowed link is tapped.
  final MarkdownLinkTapCallback? onTapLink;

  /// Callback invoked when an allowed `http`/`https` web link is tapped.
  final MarkdownWebLinkCallback? onOpenWebLink;

  /// Optional [MarkdownUrlPolicy] overriding the parsed document's URL policy
  /// for interactive link and image gating.
  final MarkdownUrlPolicy? urlPolicy;

  /// Returns a copy of these delegates with selected fields replaced.
  MarkdownBuilderDelegates copyWith({
    MarkdownImagePolicy? imagePolicy,
    VoidCallback? onLoadRemoteImages,
    MarkdownMathInlineBuilder? mathInlineBuilder,
    MarkdownMathBlockBuilder? mathBlockBuilder,
    MarkdownDiagramBuilder? diagramBuilder,
    MarkdownCodeBlockBuilder? codeBlockBuilder,
    MarkdownImageBuilder? imageBuilder,
    MarkdownLinkTapCallback? onTapLink,
    MarkdownWebLinkCallback? onOpenWebLink,
    MarkdownUrlPolicy? urlPolicy,
  }) {
    return MarkdownBuilderDelegates(
      imagePolicy: imagePolicy ?? this.imagePolicy,
      onLoadRemoteImages: onLoadRemoteImages ?? this.onLoadRemoteImages,
      mathInlineBuilder: mathInlineBuilder ?? this.mathInlineBuilder,
      mathBlockBuilder: mathBlockBuilder ?? this.mathBlockBuilder,
      diagramBuilder: diagramBuilder ?? this.diagramBuilder,
      codeBlockBuilder: codeBlockBuilder ?? this.codeBlockBuilder,
      imageBuilder: imageBuilder ?? this.imageBuilder,
      onTapLink: onTapLink ?? this.onTapLink,
      onOpenWebLink: onOpenWebLink ?? this.onOpenWebLink,
      urlPolicy: urlPolicy ?? this.urlPolicy,
    );
  }

  /// Resolves the effective [MarkdownUrlPolicy] against [fallback].
  MarkdownUrlPolicy resolveUrlPolicy(MarkdownUrlPolicy fallback) =>
      urlPolicy ?? fallback;

  /// Returns whether [destination] points to a remote network address
  /// (`http://`, `https://`, or protocol-relative `//`).
  static bool isRemoteImageUrl(String destination) {
    final String trimmed = destination.trim().toLowerCase();
    return trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('//');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownBuilderDelegates &&
          imagePolicy == other.imagePolicy &&
          onLoadRemoteImages == other.onLoadRemoteImages &&
          mathInlineBuilder == other.mathInlineBuilder &&
          mathBlockBuilder == other.mathBlockBuilder &&
          diagramBuilder == other.diagramBuilder &&
          codeBlockBuilder == other.codeBlockBuilder &&
          imageBuilder == other.imageBuilder &&
          onTapLink == other.onTapLink &&
          onOpenWebLink == other.onOpenWebLink &&
          urlPolicy == other.urlPolicy;

  @override
  int get hashCode => Object.hash(
    imagePolicy,
    onLoadRemoteImages,
    mathInlineBuilder,
    mathBlockBuilder,
    diagramBuilder,
    codeBlockBuilder,
    imageBuilder,
    onTapLink,
    onOpenWebLink,
    urlPolicy,
  );
}
