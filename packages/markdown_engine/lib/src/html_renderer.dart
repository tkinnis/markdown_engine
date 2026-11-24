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

  bool get _outputBudgetReached => buffer.length >= budgets.maxOutputBytes;

  void renderBlocks(List<MarkdownBlockNode> blocks) {
    final int len = blocks.length;
    for (int i = 0; i < len; i++) {
      if (_outputBudgetReached) {
        return;
      }
      renderBlock(blocks[i]);
    }
  }

  void renderBlock(MarkdownBlockNode block) {
    if (_outputBudgetReached) {
      return;
    }
    switch (block) {
      case FrontmatterNode():
        return;
      case HeadingNode():
        final String tag = 'h${block.level}';
        buffer
          ..write('<')
          ..write(tag);
        if (options.explicitHeadingIds && block.explicitId != null) {
          buffer.write(' id="');
          writeEscapedHtml(buffer, block.explicitId!);
          buffer.write('"');
        }
        buffer.write('>');
        renderInlines(rawHeadingInlines(block));
        buffer
          ..write('</')
          ..write(tag)
          ..writeln('>');
      case ParagraphNode():
        buffer.write('<p>');
        renderInlines(rawParagraphInlines(block));
        buffer.writeln('</p>');
      case CodeBlockNode():
        buffer.write('<pre><code');
        final String? lang = block.language;
        if (block.isFenced && lang != null && lang.isNotEmpty) {
          buffer.write(' class="language-');
          writeEscapedHtml(buffer, lang);
          buffer.write('"');
        }
        buffer.write('>');
        writeEscapedHtml(buffer, block.literal);
        buffer.writeln('</code></pre>');
      case BlockQuoteNode():
        buffer.writeln('<blockquote>');
        renderBlocks(rawBlockQuoteChildren(block));
        buffer.writeln('</blockquote>');
      case AlertNode():
        buffer
          ..write('<div class="markdown-alert markdown-alert-')
          ..write(block.kind.name)
          ..writeln('">')
          ..write('<p class="markdown-alert-title">');
        writeEscapedHtml(buffer, block.title);
        buffer.writeln('</p>');
        renderBlocks(rawAlertChildren(block));
        buffer.writeln('</div>');
      case ListNode():
        if (block.ordered) {
          if (block.start == 1) {
            buffer.writeln('<ol>');
          } else {
            buffer
              ..write('<ol start="')
              ..write(block.start)
              ..writeln('">');
          }
        } else {
          buffer.writeln('<ul>');
        }
        final List<ListItemNode> listItems = rawListItems(block);
        for (int i = 0; i < listItems.length; i++) {
          if (_outputBudgetReached) {
            break;
          }
          _renderListItem(listItems[i], tight: block.tight);
        }
        buffer.writeln(block.ordered ? '</ol>' : '</ul>');
      case ListItemNode():
        _renderListItem(block, tight: false);
      case TableNode():
        buffer
          ..writeln('<table>')
          ..writeln('<thead>')
          ..writeln('<tr>');
        final List<TableCellNode> headers = rawTableHeaders(block);
        for (int i = 0; i < headers.length; i++) {
          final TableCellNode header = headers[i];
          buffer.write('<th');
          _writeAlignmentAttr(header.alignment);
          buffer.write('>');
          renderInlines(rawTableCellInlines(header));
          buffer.writeln('</th>');
        }
        buffer
          ..writeln('</tr>')
          ..writeln('</thead>');
        final List<List<TableCellNode>> rows = rawTableRows(block);
        if (rows.isNotEmpty) {
          buffer.writeln('<tbody>');
          for (int r = 0; r < rows.length; r++) {
            if (_outputBudgetReached) {
              break;
            }
            final List<TableCellNode> row = rows[r];
            buffer.writeln('<tr>');
            for (int c = 0; c < row.length; c++) {
              final TableCellNode cell = row[c];
              buffer.write('<td');
              _writeAlignmentAttr(cell.alignment);
              buffer.write('>');
              renderInlines(rawTableCellInlines(cell));
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
        final List<MarkdownInlineNode> summaryInlines =
            rawDetailsSummaryInlines(block);
        if (summaryInlines.isNotEmpty) {
          renderInlines(summaryInlines);
        } else {
          writeEscapedHtml(buffer, block.summary);
        }
        buffer.writeln('</summary>');
        renderBlocks(rawDetailsChildren(block));
        buffer.writeln('</details>');
      case AlignedBlockNode():
        buffer
          ..write('<div align="')
          ..write(block.alignment.name)
          ..writeln('">');
        renderBlocks(rawAlignedChildren(block));
        buffer.writeln('</div>');
      case FigureBlockNode():
        buffer.writeln('<figure>');
        renderBlocks(rawFigureChildren(block));
        if (block.caption != null) {
          buffer.write('<figcaption>');
          final List<MarkdownInlineNode> capInlines = rawFigureCaptionInlines(
            block,
          );
          if (capInlines.isNotEmpty) {
            renderInlines(capInlines);
          } else {
            writeEscapedHtml(buffer, block.caption!);
          }
          buffer.writeln('</figcaption>');
        }
        buffer.writeln('</figure>');
      case MathBlockNode():
        buffer
          ..write(r'<div class="math math-display">')
          ..write('\$\$\n');
        writeEscapedHtml(buffer, block.latex);
        buffer.writeln('\n\$\$</div>');
      case DefinitionListNode():
        buffer.writeln('<dl>');
        final List<DefinitionGroup> groups = rawDefinitionGroups(block);
        for (int i = 0; i < groups.length; i++) {
          if (_outputBudgetReached) {
            break;
          }
          final DefinitionGroup group = groups[i];
          buffer.write('<dt>');
          renderInlines(rawDefinitionTerm(group));
          buffer.writeln('</dt>');
          final List<List<MarkdownBlockNode>> defs = rawDefinitionBodies(group);
          for (int j = 0; j < defs.length; j++) {
            if (_outputBudgetReached) {
              break;
            }
            final List<MarkdownBlockNode> def = defs[j];
            if (def.length == 1 && def.first is ParagraphNode) {
              buffer.write('<dd>');
              renderInlines(rawParagraphInlines(def.first as ParagraphNode));
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
        final List<FootnoteDefinitionNode> fnDefs = rawFootnoteSectionDefs(
          block,
        );
        for (int i = 0; i < fnDefs.length; i++) {
          if (_outputBudgetReached) {
            break;
          }
          _renderFootnoteDefinition(fnDefs[i]);
        }
        buffer
          ..writeln('</ol>')
          ..writeln('</section>');
    }
  }

  void _renderListItem(ListItemNode item, {required bool tight}) {
    final List<MarkdownBlockNode> children = rawListItemChildren(item);
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
        if (_outputBudgetReached) {
          break;
        }
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
          renderInlines(rawParagraphInlines(child));
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
      if (_outputBudgetReached) {
        break;
      }
      final MarkdownBlockNode child = children[i];
      if (i == 0 && item.taskState != null && child is ParagraphNode) {
        buffer.write('<p>');
        _writeTaskCheckbox(item.taskState!);
        buffer.write(' ');
        renderInlines(rawParagraphInlines(child));
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
    buffer
      ..write('<li id="fn-')
      ..write(escapedLabel)
      ..writeln('">');
    final List<MarkdownBlockNode> children = rawFootnoteDefChildren(def);
    final String backrefs = _buildFootnoteBackrefs(def, escapedLabel);

    if (children.isEmpty) {
      buffer
        ..writeln(backrefs)
        ..writeln('</li>');
      return;
    }

    for (int i = 0; i < children.length; i++) {
      if (_outputBudgetReached) {
        break;
      }
      final MarkdownBlockNode child = children[i];
      final bool isLast = i == children.length - 1;
      if (isLast && child is ParagraphNode) {
        buffer.write('<p>');
        renderInlines(rawParagraphInlines(child));
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
    final int len = nodes.length;
    if (len == 1) {
      if (!_outputBudgetReached) {
        _renderInline(nodes[0]);
      }
      return;
    }
    for (int i = 0; i < len; i++) {
      if (_outputBudgetReached) {
        return;
      }
      _renderInline(nodes[i]);
    }
  }

  void _renderInline(MarkdownInlineNode node) {
    if (_outputBudgetReached) {
      return;
    }
    switch (node) {
      case TextNode():
        writeEscapedHtml(buffer, node.text);
      case SoftBreakNode():
        buffer.writeln();
      case HardBreakNode():
        buffer.writeln('<br />');
      case InlineBreakNode():
        buffer.write('<br />');
      case CodeSpanNode():
        buffer.write('<code>');
        writeEscapedHtml(buffer, node.literal);
        buffer.write('</code>');
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
        final bool blocked =
            isBlockedLinkNode(node) ||
            (options.sanitizeUrls &&
                node.destination.isNotEmpty &&
                !options.urlPolicy.isAllowed(node.destination));
        buffer.write('<a');
        if (!blocked) {
          buffer
            ..write(' href="')
            ..write(percentEncodeUrl(node.destination))
            ..write('"');
        }
        if (node.title != null) {
          buffer.write(' title="');
          writeEscapedHtml(buffer, node.title!);
          buffer.write('"');
        }
        buffer.write('>');
        renderInlines(node.children);
        buffer.write('</a>');
      case ImageNode():
        final bool blocked =
            isBlockedImageNode(node) ||
            (options.sanitizeUrls &&
                node.destination.isNotEmpty &&
                !options.urlPolicy.isAllowed(node.destination));
        buffer.write('<img');
        if (!blocked) {
          buffer
            ..write(' src="')
            ..write(percentEncodeUrl(node.destination))
            ..write('"');
        }
        buffer.write(' alt="');
        writeEscapedHtml(buffer, node.alt);
        buffer.write('"');
        if (node.title != null) {
          buffer.write(' title="');
          writeEscapedHtml(buffer, node.title!);
          buffer.write('"');
        }
        if (node.width != null) {
          buffer
            ..write(' width="')
            ..write(node.width)
            ..write('"');
        }
        if (node.height != null) {
          buffer
            ..write(' height="')
            ..write(node.height)
            ..write('"');
        }
        buffer.write(' />');
      case MathInlineNode():
        buffer.write(r'<span class="math math-inline">$');
        writeEscapedHtml(buffer, node.latex);
        buffer.write(r'$</span>');
      case FootnoteRefNode():
        final String escaped = percentEncodeHrefFragment(node.label);
        final String occSuffix = node.occurrenceIndex > 1
            ? '-${node.occurrenceIndex}'
            : '';
        buffer
          ..write('<sup class="footnote-ref"><a href="#fn-')
          ..write(escaped)
          ..write('" id="fnref-')
          ..write(escaped)
          ..write(occSuffix)
          ..write('" data-footnote-ref>')
          ..write(node.index)
          ..write('</a></sup>');
      case KbdInlineNode():
        buffer.write('<kbd>');
        renderInlines(node.children);
        buffer.write('</kbd>');
      case AbbrInlineNode():
        buffer.write('<abbr title="');
        writeEscapedHtml(buffer, node.title);
        buffer.write('">');
        renderInlines(node.children);
        buffer.write('</abbr>');
      case AnchorInlineNode():
        buffer.write('<a id="');
        writeEscapedHtml(buffer, node.id);
        buffer.write('"></a>');
      case PictureInlineNode():
        final String light = options.sanitizeUrls
            ? options.urlPolicy.sanitize(node.lightSource)
            : node.lightSource;
        final String dark = options.sanitizeUrls
            ? options.urlPolicy.sanitize(node.darkSource)
            : node.darkSource;
        buffer.write('<picture>');
        if (dark.isNotEmpty) {
          buffer
            ..write('<source media="(prefers-color-scheme: dark)" srcset="')
            ..write(percentEncodeUrl(dark))
            ..write('">');
        }
        buffer.write('<img');
        if (light.isNotEmpty) {
          buffer
            ..write(' src="')
            ..write(percentEncodeUrl(light))
            ..write('"');
        }
        buffer.write(' alt="');
        writeEscapedHtml(buffer, node.alt);
        buffer.write('">');
        buffer.write('</picture>');
      case RawHtmlInlineNode():
        _writeRawHtml(node.html, allowLineTermination: false);
    }
  }

  void _writeRawHtml(String raw, {required bool allowLineTermination}) {
    if (_rawHtmlBytesEmitted + raw.length > budgets.maxHtmlBytes) {
      writeEscapedHtml(buffer, raw);
      if (allowLineTermination && !raw.endsWith('\n')) {
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
