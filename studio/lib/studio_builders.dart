import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_engine/markdown_engine.dart';
import 'package:markdown_engine_flutter/markdown_engine_flutter.dart';

/// Summary of hyperlink destinations in a [MarkdownDocument] evaluated against
/// a [MarkdownUrlPolicy].
@immutable
final class StudioLinkAudit {
  /// Creates a [StudioLinkAudit].
  const StudioLinkAudit({
    required this.allowedCount,
    required this.blockedOrSanitizedCount,
  });

  /// Number of links whose destination is non-empty and allowed by the policy.
  final int allowedCount;

  /// Number of links whose destination was stripped or rejected by the policy.
  final int blockedOrSanitizedCount;

  /// Total [LinkNode] count found across the document AST.
  int get totalCount => allowedCount + blockedOrSanitizedCount;
}

/// Walks [document] and counts allowed versus blocked/sanitized [LinkNode]s
/// under [policy].
StudioLinkAudit auditDocumentLinks(
  MarkdownDocument document,
  MarkdownUrlPolicy policy,
) {
  int allowed = 0;
  int blocked = 0;

  void walkInlines(List<MarkdownInlineNode> nodes) {
    for (final MarkdownInlineNode node in nodes) {
      switch (node) {
        case LinkNode():
          final String dest = node.destination.trim();
          if (dest.isNotEmpty && policy.isAllowed(dest)) {
            allowed++;
          } else {
            blocked++;
          }
          walkInlines(node.children);
        case EmphasisNode():
          walkInlines(node.children);
        case StrongNode():
          walkInlines(node.children);
        case StrikethroughNode():
          walkInlines(node.children);
        case HighlightNode():
          walkInlines(node.children);
        case SubscriptNode():
          walkInlines(node.children);
        case SuperscriptNode():
          walkInlines(node.children);
        case KbdInlineNode():
          walkInlines(node.children);
        case AbbrInlineNode():
          walkInlines(node.children);
        case ImageNode():
          walkInlines(node.children);
        case TextNode():
        case SoftBreakNode():
        case HardBreakNode():
        case InlineBreakNode():
        case CodeSpanNode():
        case MathInlineNode():
        case FootnoteRefNode():
        case AnchorInlineNode():
        case PictureInlineNode():
        case RawHtmlInlineNode():
          break;
      }
    }
  }

  void walkBlocks(List<MarkdownBlockNode> blocks) {
    for (final MarkdownBlockNode block in blocks) {
      switch (block) {
        case HeadingNode():
          walkInlines(block.children);
        case ParagraphNode():
          walkInlines(block.children);
        case BlockQuoteNode():
          walkBlocks(block.children);
        case AlertNode():
          walkBlocks(block.children);
        case ListNode():
          for (final ListItemNode item in block.items) {
            walkBlocks(item.children);
          }
        case ListItemNode():
          walkBlocks(block.children);
        case TableNode():
          for (final TableCellNode cell in block.headers) {
            walkInlines(cell.children);
          }
          for (final List<TableCellNode> row in block.rows) {
            for (final TableCellNode cell in row) {
              walkInlines(cell.children);
            }
          }
        case DetailsBlockNode():
          walkInlines(block.summaryInlines);
          walkBlocks(block.children);
        case AlignedBlockNode():
          walkBlocks(block.children);
        case FigureBlockNode():
          walkBlocks(block.children);
          walkInlines(block.captionInlines);
        case DefinitionListNode():
          for (final DefinitionGroup group in block.groups) {
            walkInlines(group.term);
            for (final List<MarkdownBlockNode> def in group.definitions) {
              walkBlocks(def);
            }
          }
        case FootnoteDefinitionNode():
          walkBlocks(block.children);
        case FootnoteSectionNode():
          for (final FootnoteDefinitionNode def in block.definitions) {
            walkBlocks(def.children);
          }
        case FrontmatterNode():
        case CodeBlockNode():
        case ThematicBreakNode():
        case HtmlBlockNode():
        case MathBlockNode():
          break;
      }
    }
  }

  walkBlocks(document.blocks);
  return StudioLinkAudit(
    allowedCount: allowed,
    blockedOrSanitizedCount: blocked,
  );
}

/// Builds the Studio [MarkdownBuilderDelegates] using built-in
/// `tex_math_flutter` math and `pele_dart` Mermaid rendering alongside
/// syntax-highlighted non-Mermaid code blocks and [MarkdownUrlPolicy] checks.
MarkdownBuilderDelegates buildStudioDelegates({
  MarkdownThemeData? theme,
  required MarkdownUrlPolicy urlPolicy,
  required MarkdownLinkTapCallback onTapLink,
  required VoidCallback onLoadRemoteImages,
  bool remoteImagesApproved = false,
}) {
  return MarkdownBuilderDelegates(
    imagePolicy: MarkdownImagePolicy.ask,
    remoteImagesApproved: remoteImagesApproved,
    urlPolicy: urlPolicy,
    onTapLink: onTapLink,
    onLoadRemoteImages: onLoadRemoteImages,
    codeBlockBuilder: buildStudioCodeBlock,
  );
}

/// Top-level [MarkdownCodeBlockBuilder] rendering non-Mermaid fenced and
/// indented code blocks with lightweight syntax highlighting and copy action.
Widget buildStudioCodeBlock(BuildContext context, CodeBlockNode node) {
  return _StudioSyntaxCodeBlock(
    key: ValueKey<String>('studio-code-${node.blockId}'),
    node: node,
  );
}

final class _StudioSyntaxCodeBlock extends StatefulWidget {
  const _StudioSyntaxCodeBlock({super.key, required this.node});

  final CodeBlockNode node;

  @override
  State<_StudioSyntaxCodeBlock> createState() => _StudioSyntaxCodeBlockState();
}

final class _StudioSyntaxCodeBlockState extends State<_StudioSyntaxCodeBlock> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copyCode() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.node.literal)));
    _resetTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final MarkdownThemeData theme = MarkdownTheme.of(context);
    final String? lang = widget.node.language;
    final String badgeText = (lang != null && lang.isNotEmpty) ? lang : 'code';
    final String raw = widget.node.literal;
    final String trimmed = raw.endsWith('\n')
        ? raw.substring(0, raw.length - 1)
        : raw;
    final int lineCount = trimmed.isEmpty
        ? 1
        : '\n'.allMatches(trimmed).length + 1;
    final TextStyle baseCodeStyle = theme.codeTextStyle();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.codeBackground,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.border, width: 1.0),
              ),
            ),
            child: Row(
              children: <Widget>[
                SelectionContainer.disabled(
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6.0,
                        vertical: 2.0,
                      ),
                      decoration: BoxDecoration(
                        color: theme.border.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: theme.accent,
                          fontSize: theme.codeFontSize * 0.8,
                          fontWeight: FontWeight.w700,
                          fontFamily: theme.effectiveCodeFontFamily,
                          fontFamilyFallback:
                              MarkdownThemeData.defaultCodeFontFallback,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                SelectionContainer.disabled(
                  child: ExcludeSemantics(
                    child: Text(
                      '$lineCount L',
                      style: TextStyle(
                        color: theme.muted,
                        fontSize: theme.codeFontSize * 0.78,
                        fontFamily: theme.effectiveCodeFontFamily,
                        fontFamilyFallback:
                            MarkdownThemeData.defaultCodeFontFallback,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                SelectionContainer.disabled(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4.0),
                    onTap: _copyCode,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6.0,
                        vertical: 2.0,
                      ),
                      child: Text(
                        _copied ? 'Copied' : 'Copy',
                        style: TextStyle(
                          color: _copied ? theme.accent : theme.muted,
                          fontSize: theme.fontSize * 0.78,
                          fontWeight: FontWeight.w600,
                          fontFamily: theme.fontFamily,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12.0),
            child: trimmed.length > 20000
                ? MarkdownRichText(trimmed, style: baseCodeStyle)
                : MarkdownRichText.rich(
                    TextSpan(
                      style: baseCodeStyle,
                      children: _highlightCodeSpans(trimmed, theme),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

const Set<String> _codeKeywords = <String>{
  'abstract',
  'as',
  'async',
  'await',
  'bool',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'def',
  'double',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'from',
  'function',
  'if',
  'implements',
  'import',
  'in',
  'int',
  'is',
  'late',
  'let',
  'null',
  'override',
  'required',
  'return',
  'sealed',
  'static',
  'String',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
};

List<InlineSpan> _highlightCodeSpans(String code, MarkdownThemeData theme) {
  final Color commentColor = theme.muted;
  final Color stringColor = theme.alertPalette.tip.foreground;
  final Color keywordColor = theme.alertPalette.important.foreground;
  final Color numberColor = theme.alertPalette.warning.foreground;
  final Color typeColor = theme.accent;

  final List<InlineSpan> spans = <InlineSpan>[];
  final StringBuffer plainBuffer = StringBuffer();

  void flushPlain() {
    if (plainBuffer.isNotEmpty) {
      spans.add(TextSpan(text: plainBuffer.toString()));
      plainBuffer.clear();
    }
  }

  int i = 0;
  final int len = code.length;
  while (i < len) {
    final int cu = code.codeUnitAt(i);

    // Line comments (`// ...` or `# ...`).
    if ((cu == 0x2F && i + 1 < len && code.codeUnitAt(i + 1) == 0x2F) ||
        cu == 0x23) {
      flushPlain();
      final int nl = code.indexOf('\n', i);
      final int end = nl == -1 ? len : nl;
      spans.add(
        TextSpan(
          text: code.substring(i, end),
          style: TextStyle(color: commentColor, fontStyle: FontStyle.italic),
        ),
      );
      i = end;
      continue;
    }

    // Block comments (`/* ... */`).
    if (cu == 0x2F && i + 1 < len && code.codeUnitAt(i + 1) == 0x2A) {
      flushPlain();
      final int closeIdx = code.indexOf('*/', i + 2);
      final int end = closeIdx == -1 ? len : closeIdx + 2;
      spans.add(
        TextSpan(
          text: code.substring(i, end),
          style: TextStyle(color: commentColor, fontStyle: FontStyle.italic),
        ),
      );
      i = end;
      continue;
    }

    // Quoted strings (`'...'` or `"..."`).
    if (cu == 0x27 || cu == 0x22) {
      flushPlain();
      final int quote = cu;
      int j = i + 1;
      while (j < len) {
        final int ch = code.codeUnitAt(j);
        if (ch == 0x5C && j + 1 < len) {
          j += 2;
          continue;
        }
        j++;
        if (ch == quote || ch == 0x0A) {
          break;
        }
      }
      spans.add(
        TextSpan(
          text: code.substring(i, j),
          style: TextStyle(color: stringColor),
        ),
      );
      i = j;
      continue;
    }

    // Numeric literals.
    if (_isAsciiDigit(cu) &&
        (i == 0 || !_isIdentChar(code.codeUnitAt(i - 1)))) {
      flushPlain();
      int j = i + 1;
      while (j < len) {
        final int ch = code.codeUnitAt(j);
        if (_isAsciiDigit(ch) ||
            ch == 0x2E ||
            ch == 0x78 ||
            ch == 0x58 ||
            (ch >= 0x41 && ch <= 0x46) ||
            (ch >= 0x61 && ch <= 0x66) ||
            ch == 0x5F) {
          j++;
        } else {
          break;
        }
      }
      spans.add(
        TextSpan(
          text: code.substring(i, j),
          style: TextStyle(color: numberColor),
        ),
      );
      i = j;
      continue;
    }

    // Identifiers, keywords, and PascalCase type names.
    if (_isIdentStart(cu)) {
      int j = i + 1;
      while (j < len && _isIdentChar(code.codeUnitAt(j))) {
        j++;
      }
      final String word = code.substring(i, j);
      if (_codeKeywords.contains(word)) {
        flushPlain();
        spans.add(
          TextSpan(
            text: word,
            style: TextStyle(color: keywordColor, fontWeight: FontWeight.w600),
          ),
        );
      } else if (cu >= 0x41 && cu <= 0x5A && word.length > 1) {
        flushPlain();
        spans.add(
          TextSpan(
            text: word,
            style: TextStyle(color: typeColor),
          ),
        );
      } else {
        plainBuffer.write(word);
      }
      i = j;
      continue;
    }

    plainBuffer.writeCharCode(cu);
    i++;
  }

  flushPlain();
  return spans;
}

bool _isAsciiDigit(int cu) => cu >= 0x30 && cu <= 0x39;

bool _isIdentStart(int cu) =>
    (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A) || cu == 0x5F;

bool _isIdentChar(int cu) => _isIdentStart(cu) || _isAsciiDigit(cu);
