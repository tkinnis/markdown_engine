import 'ast.dart';
import 'budgets.dart';
import 'options.dart';
import 'security.dart';
import 'url_utils.dart';

/// Renders parsed [MarkdownBlockNode]s into CommonMark `0.31.2` and
/// `cmark-gfm 0.29.0.gfm.13` compliant HTML.
final class HtmlRenderer {
  /// Creates an [HtmlRenderer] configured with [options].
  const HtmlRenderer({this.options = const MarkdownOptions()});

  /// Options controlling tagfilter, sanitization, and rendering behavior.
  final MarkdownOptions options;

  /// Renders [blocks] to an HTML string.
  String render(List<MarkdownBlockNode> blocks) {
    if (blocks.isEmpty) {
      return '';
    }
    final _HtmlRenderState state = _HtmlRenderState(
      options: options,
      budgets: options.effectiveBudgets,
    );
    state.renderBlocks(blocks);
    return state.buffer.toString();
  }
}

final class _HtmlRenderState {
  _HtmlRenderState({required this.options, required this.budgets});

  final MarkdownOptions options;
  final MarkdownBudgets budgets;
  final StringBuffer buffer = StringBuffer();
  int _rawHtmlBytesEmitted = 0;
  bool _inStrong = false;

  void renderBlocks(List<MarkdownBlockNode> blocks) {
    for (final MarkdownBlockNode block in blocks) {
      renderBlock(block);
    }
  }

  void renderBlock(MarkdownBlockNode block) {
    switch (block) {
      case FrontmatterNode():
        return;
      case HeadingNode():
        final String tag = 'h${block.level}';
        buffer.write('<$tag');
        if (options.explicitHeadingIds && block.explicitId != null) {
          buffer
            ..write(' id="')
            ..write(escapeHtmlText(block.explicitId!))
            ..write('"');
        }
        buffer.write('>');
        renderInlines(block.children);
        buffer
          ..write('</')
          ..write(tag)
          ..writeln('>');
      case ParagraphNode():
        buffer.write('<p>');
        renderInlines(block.children);
        buffer.writeln('</p>');
      case CodeBlockNode():
        buffer.write('<pre><code');
        final String? lang = block.language;
        if (block.isFenced && lang != null && lang.isNotEmpty) {
          buffer
            ..write(' class="language-')
            ..write(escapeHtmlText(lang))
            ..write('"');
        }
        buffer
          ..write('>')
          ..write(escapeHtmlText(block.literal))
          ..writeln('</code></pre>');
      case BlockQuoteNode():
        buffer.writeln('<blockquote>');
        renderBlocks(block.children);
        buffer.writeln('</blockquote>');
      case AlertNode():
        buffer
          ..write('<div class="markdown-alert markdown-alert-')
          ..write(block.kind.name)
          ..writeln('">')
          ..write('<p class="markdown-alert-title">')
          ..write(escapeHtmlText(block.title))
          ..writeln('</p>');
        renderBlocks(block.children);
        buffer.writeln('</div>');
      case ListNode():
        if (block.ordered) {
          if (block.start == 1) {
            buffer.writeln('<ol>');
          } else {
            buffer.writeln('<ol start="${block.start}">');
          }
        } else {
          buffer.writeln('<ul>');
        }
        for (final ListItemNode item in block.items) {
          _renderListItem(item, tight: block.tight);
        }
        buffer.writeln(block.ordered ? '</ol>' : '</ul>');
      case ListItemNode():
        _renderListItem(block, tight: false);
      case TableNode():
        buffer
          ..writeln('<table>')
          ..writeln('<thead>')
          ..writeln('<tr>');
        for (final TableCellNode header in block.headers) {
          buffer.write('<th');
          _writeAlignmentAttr(header.alignment);
          buffer.write('>');
          renderInlines(header.children);
          buffer.writeln('</th>');
        }
        buffer
          ..writeln('</tr>')
          ..writeln('</thead>');
        if (block.rows.isNotEmpty) {
          buffer.writeln('<tbody>');
          for (final List<TableCellNode> row in block.rows) {
            buffer.writeln('<tr>');
            for (final TableCellNode cell in row) {
              buffer.write('<td');
              _writeAlignmentAttr(cell.alignment);
              buffer.write('>');
              renderInlines(cell.children);
              buffer.writeln('</td>');
            }
            buffer.writeln('</tr>');
          }
          buffer.writeln('</tbody>');
        }
        buffer.writeln('</table>');
      case ThematicBreakNode():
        buffer.writeln('<hr />');
      case HtmlBlockNode():
        _writeRawHtml(block.literal, allowLineTermination: true);
      case DetailsBlockNode():
        buffer.write('<details');
        if (block.initiallyOpen) {
          buffer.write(' open');
        }
        buffer
          ..writeln('>')
          ..write('<summary>');
        if (block.summaryInlines.isNotEmpty) {
          renderInlines(block.summaryInlines);
        } else {
          buffer.write(escapeHtmlText(block.summary));
        }
        buffer.writeln('</summary>');
        renderBlocks(block.children);
        buffer.writeln('</details>');
      case AlignedBlockNode():
        buffer
          ..write('<div align="')
          ..write(block.alignment.name)
          ..writeln('">');
        renderBlocks(block.children);
        buffer.writeln('</div>');
      case FigureBlockNode():
        buffer.writeln('<figure>');
        renderBlocks(block.children);
        if (block.caption != null) {
          buffer.write('<figcaption>');
          if (block.captionInlines.isNotEmpty) {
            renderInlines(block.captionInlines);
          } else {
            buffer.write(escapeHtmlText(block.caption!));
          }
          buffer.writeln('</figcaption>');
        }
        buffer.writeln('</figure>');
      case MathBlockNode():
        buffer
          ..write(r'<div class="math math-display">')
          ..write('\$\$\n')
          ..write(escapeHtmlText(block.latex))
          ..writeln('\n\$\$</div>');
      case DefinitionListNode():
        buffer.writeln('<dl>');
        for (final DefinitionGroup group in block.groups) {
          buffer.write('<dt>');
          renderInlines(group.term);
          buffer.writeln('</dt>');
          for (final List<MarkdownBlockNode> def in group.definitions) {
            if (def.length == 1 && def.first is ParagraphNode) {
              buffer.write('<dd>');
              renderInlines((def.first as ParagraphNode).children);
              buffer.writeln('</dd>');
            } else {
              buffer.writeln('<dd>');
              renderBlocks(def);
              buffer.writeln('</dd>');
            }
          }
        }
        buffer.writeln('</dl>');
      case FootnoteDefinitionNode():
        _renderFootnoteDefinition(block);
      case FootnoteSectionNode():
        buffer
          ..writeln('<section class="footnotes" data-footnotes>')
          ..writeln('<ol>');
        for (final FootnoteDefinitionNode def in block.definitions) {
          _renderFootnoteDefinition(def);
        }
        buffer
          ..writeln('</ol>')
          ..writeln('</section>');
    }
  }

  void _renderListItem(ListItemNode item, {required bool tight}) {
    final List<MarkdownBlockNode> children = item.children;
    if (children.isEmpty) {
      if (item.taskState != null) {
        buffer.write('<li>');
        _writeTaskCheckbox(item.taskState!);
        buffer.writeln('</li>');
      } else {
        buffer.writeln('<li></li>');
      }
      return;
    }

    if (tight) {
      for (int i = 0; i < children.length; i++) {
        final MarkdownBlockNode child = children[i];
        final bool isFirst = i == 0;
        final bool isLast = i == children.length - 1;
        if (child is ParagraphNode) {
          if (isFirst) {
            buffer.write('<li>');
            if (item.taskState != null) {
              _writeTaskCheckbox(item.taskState!);
              buffer.write(' ');
            }
          } else if (children[i - 1] is ParagraphNode) {
            buffer.writeln();
          }
          renderInlines(child.children);
          if (isLast) {
            buffer.writeln('</li>');
          } else if (children[i + 1] is! ParagraphNode) {
            buffer.writeln();
          }
        } else {
          if (isFirst) {
            buffer.writeln('<li>');
            if (item.taskState != null) {
              _writeTaskCheckbox(item.taskState!);
              buffer.writeln();
            }
          }
          renderBlock(child);
          if (isLast) {
            buffer.writeln('</li>');
          }
        }
      }
      return;
    }

    // Loose list item.
    buffer.writeln('<li>');
    for (int i = 0; i < children.length; i++) {
      final MarkdownBlockNode child = children[i];
      if (i == 0 && item.taskState != null && child is ParagraphNode) {
        buffer.write('<p>');
        _writeTaskCheckbox(item.taskState!);
        buffer.write(' ');
        renderInlines(child.children);
        buffer.writeln('</p>');
      } else {
        if (i == 0 && item.taskState != null) {
          _writeTaskCheckbox(item.taskState!);
          buffer.writeln();
        }
        renderBlock(child);
      }
    }
    buffer.writeln('</li>');
  }

  void _writeTaskCheckbox(bool checked) {
    if (checked) {
      buffer.write('<input type="checkbox" checked="" disabled="" />');
    } else {
      buffer.write('<input type="checkbox" disabled="" />');
    }
  }

  void _renderFootnoteDefinition(FootnoteDefinitionNode def) {
    final String escapedLabel = percentEncodeHrefFragment(def.label);
    buffer.writeln('<li id="fn-$escapedLabel">');
    final List<MarkdownBlockNode> children = def.children;
    final String backrefs = _buildFootnoteBackrefs(def, escapedLabel);

    if (children.isEmpty) {
      buffer
        ..writeln(backrefs)
        ..writeln('</li>');
      return;
    }

    for (int i = 0; i < children.length; i++) {
      final MarkdownBlockNode child = children[i];
      final bool isLast = i == children.length - 1;
      if (isLast && child is ParagraphNode) {
        buffer.write('<p>');
        renderInlines(child.children);
        buffer
          ..write(' ')
          ..write(backrefs)
          ..writeln('</p>');
      } else {
        renderBlock(child);
        if (isLast) {
          buffer.writeln(backrefs);
        }
      }
    }
    buffer.writeln('</li>');
  }

  String _buildFootnoteBackrefs(
    FootnoteDefinitionNode def,
    String escapedLabel,
  ) {
    final int count = def.referenceCount > 0 ? def.referenceCount : 1;
    final List<String> parts = <String>[];
    for (int occ = 1; occ <= count; occ++) {
      final String idSuffix = occ > 1 ? '-$occ' : '';
      final String idxAttr = occ > 1 ? '${def.index}-$occ' : '${def.index}';
      final String supPart = occ > 1
          ? '<sup class="footnote-ref">$occ</sup>'
          : '';
      parts.add(
        '<a href="#fnref-$escapedLabel$idSuffix" '
        'class="footnote-backref" '
        'data-footnote-backref '
        'data-footnote-backref-idx="$idxAttr" '
        'aria-label="Back to reference $idxAttr">↩$supPart</a>',
      );
    }
    return parts.join(' ');
  }

  void _writeAlignmentAttr(TableAlignment alignment) {
    switch (alignment) {
      case TableAlignment.none:
        return;
      case TableAlignment.left:
        buffer.write(' align="left"');
      case TableAlignment.center:
        buffer.write(' align="center"');
      case TableAlignment.right:
        buffer.write(' align="right"');
    }
  }

  void renderInlines(List<MarkdownInlineNode> nodes) {
    for (final MarkdownInlineNode node in nodes) {
      _renderInline(node);
    }
  }

  void _renderInline(MarkdownInlineNode node) {
    switch (node) {
      case TextNode():
        buffer.write(escapeHtmlText(node.text));
      case SoftBreakNode():
        buffer.writeln();
      case HardBreakNode():
        buffer.writeln('<br />');
      case InlineBreakNode():
        buffer.write('<br />');
      case CodeSpanNode():
        buffer
          ..write('<code>')
          ..write(escapeHtmlText(node.literal))
          ..write('</code>');
      case EmphasisNode():
        final bool prevStrong = _inStrong;
        _inStrong = false;
        buffer.write('<em>');
        renderInlines(node.children);
        buffer.write('</em>');
        _inStrong = prevStrong;
      case StrongNode():
        if (options.collapseNestedStrong && _inStrong) {
          renderInlines(node.children);
        } else {
          final bool prev = _inStrong;
          _inStrong = true;
          buffer.write('<strong>');
          renderInlines(node.children);
          buffer.write('</strong>');
          _inStrong = prev;
        }
      case StrikethroughNode():
        buffer.write('<del>');
        renderInlines(node.children);
        buffer.write('</del>');
      case HighlightNode():
        buffer.write('<mark>');
        renderInlines(node.children);
        buffer.write('</mark>');
      case SubscriptNode():
        buffer.write('<sub>');
        renderInlines(node.children);
        buffer.write('</sub>');
      case SuperscriptNode():
        buffer.write('<sup>');
        renderInlines(node.children);
        buffer.write('</sup>');
      case LinkNode():
        final String href = options.sanitizeUrls
            ? options.urlPolicy.sanitize(node.destination)
            : node.destination;
        buffer
          ..write('<a href="')
          ..write(percentEncodeUrl(href))
          ..write('"');
        if (node.title != null) {
          buffer
            ..write(' title="')
            ..write(escapeHtmlText(node.title!))
            ..write('"');
        }
        buffer.write('>');
        renderInlines(node.children);
        buffer.write('</a>');
      case ImageNode():
        final String src = options.sanitizeUrls
            ? options.urlPolicy.sanitize(node.destination)
            : node.destination;
        buffer
          ..write('<img src="')
          ..write(percentEncodeUrl(src))
          ..write('" alt="')
          ..write(escapeHtmlText(node.alt))
          ..write('"');
        if (node.title != null) {
          buffer
            ..write(' title="')
            ..write(escapeHtmlText(node.title!))
            ..write('"');
        }
        if (node.width != null) {
          buffer.write(' width="${node.width}"');
        }
        if (node.height != null) {
          buffer.write(' height="${node.height}"');
        }
        buffer.write(' />');
      case MathInlineNode():
        buffer
          ..write(r'<span class="math math-inline">$')
          ..write(escapeHtmlText(node.latex))
          ..write(r'$</span>');
      case FootnoteRefNode():
        final String escaped = percentEncodeHrefFragment(node.label);
        final String occSuffix = node.occurrenceIndex > 1
            ? '-${node.occurrenceIndex}'
            : '';
        buffer
          ..write('<sup class="footnote-ref"><a href="#fn-$escaped" ')
          ..write('id="fnref-$escaped$occSuffix" data-footnote-ref>')
          ..write(node.index)
          ..write('</a></sup>');
      case KbdInlineNode():
        buffer.write('<kbd>');
        renderInlines(node.children);
        buffer.write('</kbd>');
      case AbbrInlineNode():
        buffer
          ..write('<abbr title="')
          ..write(escapeHtmlText(node.title))
          ..write('">');
        renderInlines(node.children);
        buffer.write('</abbr>');
      case AnchorInlineNode():
        buffer
          ..write('<a id="')
          ..write(escapeHtmlText(node.id))
          ..write('"></a>');
      case PictureInlineNode():
        final String light = options.sanitizeUrls
            ? options.urlPolicy.sanitize(node.lightSource)
            : node.lightSource;
        final String dark = options.sanitizeUrls
            ? options.urlPolicy.sanitize(node.darkSource)
            : node.darkSource;
        buffer
          ..write('<picture>')
          ..write('<source media="(prefers-color-scheme: dark)" srcset="')
          ..write(percentEncodeUrl(dark))
          ..write('">')
          ..write('<img src="')
          ..write(percentEncodeUrl(light))
          ..write('" alt="')
          ..write(escapeHtmlText(node.alt))
          ..write('">')
          ..write('</picture>');
      case RawHtmlInlineNode():
        _writeRawHtml(node.html, allowLineTermination: false);
    }
  }

  void _writeRawHtml(String raw, {required bool allowLineTermination}) {
    if (_rawHtmlBytesEmitted + raw.length > budgets.maxHtmlBytes) {
      final String escaped = escapeHtmlText(raw);
      buffer.write(escaped);
      if (allowLineTermination && !escaped.endsWith('\n')) {
        buffer.writeln();
      }
      return;
    }

    String output = raw;
    if (options.sanitizeHtml) {
      output = sanitizeRawHtml(output, options.urlPolicy);
      if (output.isEmpty) {
        return;
      }
    } else if (options.gfmTagFilter) {
      output = applyGfmTagFilter(output);
    }
    _rawHtmlBytesEmitted += output.length;
    buffer.write(output);
    if (allowLineTermination && !output.endsWith('\n')) {
      buffer.writeln();
    }
  }
}
