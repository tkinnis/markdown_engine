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
    this.remoteImagesApproved = false,
    this.onLoadRemoteImages,
    this.autoScrollToAnchors = true,
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

  /// Whether remote images have been approved by the caller when [imagePolicy]
  /// is [MarkdownImagePolicy.ask].
  final bool remoteImagesApproved;

  /// Callback invoked when the user clicks "Load remote images" in
  /// [MarkdownImagePolicy.ask] mode.
  final VoidCallback? onLoadRemoteImages;

  /// Whether `#fragment` links automatically invoke
  /// `MarkdownController.scrollToAnchor` when a controller is attached.
  ///
  /// Defaults to `true`. Set to `false` when handling `#fragment` links
  /// exclusively inside [onTapLink].
  final bool autoScrollToAnchors;

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
    bool? remoteImagesApproved,
    VoidCallback? onLoadRemoteImages,
    bool? autoScrollToAnchors,
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
      remoteImagesApproved: remoteImagesApproved ?? this.remoteImagesApproved,
      onLoadRemoteImages: onLoadRemoteImages ?? this.onLoadRemoteImages,
      autoScrollToAnchors: autoScrollToAnchors ?? this.autoScrollToAnchors,
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

  /// Normalizes [destination] by unwrapping optional angle brackets (`<...>`)
  /// and stripping control, whitespace, and invisible zero-width characters.
  static String normalizeUrlDestination(String destination) {
    String working = _stripControlAndWhitespaceForUrl(destination);
    if (working.length >= 2 &&
        working.codeUnitAt(0) == 0x3C &&
        working.codeUnitAt(working.length - 1) == 0x3E) {
      working = _stripControlAndWhitespaceForUrl(
        working.substring(1, working.length - 1),
      );
    }
    return working;
  }

  /// Returns whether [destination] points to a remote or external URI address
  /// (`http://`, `https://`, `ftp://`, `smb://`, `file://`, other non-`data:`
  /// schemes, or authority-relative `//`, `\\`, `/\`, `\/`) after normalizing
  /// angle brackets and stripping control/whitespace obfuscation.
  static bool isRemoteImageUrl(String destination) {
    final String normalized = normalizeUrlDestination(destination);
    if (normalized.isEmpty || normalized.startsWith('#')) {
      return false;
    }
    if (_startsWithAuthorityPrefix(normalized)) {
      return true;
    }
    final String? scheme = _extractUrlScheme(normalized);
    if (scheme == null || scheme == 'data') {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownBuilderDelegates &&
          imagePolicy == other.imagePolicy &&
          remoteImagesApproved == other.remoteImagesApproved &&
          onLoadRemoteImages == other.onLoadRemoteImages &&
          autoScrollToAnchors == other.autoScrollToAnchors &&
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
    remoteImagesApproved,
    onLoadRemoteImages,
    autoScrollToAnchors,
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

String _stripControlAndWhitespaceForUrl(String input) {
  StringBuffer? out;
  int last = 0;
  for (int i = 0; i < input.length; i++) {
    final int cu = input.codeUnitAt(i);
    if (_isStrippedUrlChar(cu)) {
      out ??= StringBuffer();
      if (i > last) {
        out.write(input.substring(last, i));
      }
      last = i + 1;
    }
  }
  if (out == null) {
    return input;
  }
  if (last < input.length) {
    out.write(input.substring(last));
  }
  return out.toString();
}

bool _isStrippedUrlChar(int cu) {
  if (cu <= 0x20 || cu == 0x7F) {
    return true;
  }
  if (cu < 0x80) {
    return false;
  }
  return (cu >= 0x80 && cu <= 0x9F) ||
      cu == 0x00A0 ||
      cu == 0x00AD ||
      cu == 0x034F ||
      cu == 0x061C ||
      cu == 0x1680 ||
      cu == 0x180E ||
      (cu >= 0x2000 && cu <= 0x200F) ||
      (cu >= 0x2028 && cu <= 0x202F) ||
      cu == 0x205F ||
      (cu >= 0x2060 && cu <= 0x206F) ||
      cu == 0x3000 ||
      cu == 0xFEFF;
}

bool _startsWithAuthorityPrefix(String cleaned) {
  if (cleaned.length < 2) {
    return false;
  }
  final int c0 = cleaned.codeUnitAt(0);
  final int c1 = cleaned.codeUnitAt(1);
  return (c0 == 0x2F || c0 == 0x5C) && (c1 == 0x2F || c1 == 0x5C);
}

String? _extractUrlScheme(String cleaned) {
  if (cleaned.isEmpty) {
    return null;
  }
  final int first = cleaned.codeUnitAt(0);
  if (!_isAsciiAlpha(first)) {
    return null;
  }
  for (int i = 1; i < cleaned.length; i++) {
    final int cu = cleaned.codeUnitAt(i);
    if (cu == 0x3A) {
      return cleaned.substring(0, i).toLowerCase();
    }
    if (cu == 0x2F || cu == 0x5C || cu == 0x3F || cu == 0x23) {
      return null;
    }
    if (!(_isAsciiAlpha(cu) ||
        (cu >= 0x30 && cu <= 0x39) ||
        cu == 0x2B ||
        cu == 0x2D ||
        cu == 0x2E)) {
      return null;
    }
  }
  return null;
}

bool _isAsciiAlpha(int cu) =>
    (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A);
