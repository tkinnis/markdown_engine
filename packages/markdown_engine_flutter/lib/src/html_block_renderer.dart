import 'package:flutter/foundation.dart' show immutable;
import 'package:markdown_engine/markdown_engine.dart';

/// Maximum HTML element nesting depth permitted during block parsing.
const int maxHtmlBlockDepth = 32;

/// Maximum rows emitted for a single HTML `<table>`.
const int maxHtmlTableRows = 500;

/// Maximum columns emitted for a single HTML `<table>` row.
const int maxHtmlTableColumns = 64;

/// Maximum `colspan` expansion permitted on a single `<td>` or `<th>`.
const int maxHtmlColspan = 16;

/// Maximum `<li>` items emitted across an HTML block fragment.
const int maxHtmlListItems = 1000;

/// Maximum [MarkdownBlockNode] instances emitted across an HTML block fragment.
const int maxHtmlBlocks = 1000;

/// Maximum [MarkdownInlineNode] instances emitted across an HTML block fragment.
const int maxHtmlInlines = 4000;

/// Single parsed top-level block emitted from an [HtmlBlockNode] fragment.
@immutable
final class HtmlBlockEntry {
  /// Creates an [HtmlBlockEntry].
  const HtmlBlockEntry(this.block, {this.tableCaption});

  /// Converted AST block node ready for widget rendering.
  final MarkdownBlockNode block;

  /// Optional parsed `<caption>` inline nodes when [block] is a [TableNode].
  final List<MarkdownInlineNode>? tableCaption;
}

const Map<String, String> _namedHtmlEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': '\'',
  'nbsp': '\u00A0',
  'ensp': '\u2002',
  'emsp': '\u2003',
  'thinsp': '\u2009',
  'ndash': '\u2013',
  'mdash': '\u2014',
  'hellip': '\u2026',
  'lsquo': '\u2018',
  'rsquo': '\u2019',
  'ldquo': '\u201C',
  'rdquo': '\u201D',
  'laquo': '\u00AB',
  'raquo': '\u00BB',
  'copy': '\u00A9',
  'reg': '\u00AE',
  'trade': '\u2122',
  'times': '\u00D7',
  'divide': '\u00F7',
  'plusmn': '\u00B1',
  'minus': '\u2212',
  'bull': '\u2022',
  'middot': '\u00B7',
  'deg': '\u00B0',
  'sect': '\u00A7',
  'para': '\u00B6',
  'larr': '\u2190',
  'uarr': '\u2191',
  'rarr': '\u2192',
  'darr': '\u2193',
  'harr': '\u2194',
  'le': '\u2264',
  'ge': '\u2265',
  'ne': '\u2260',
  'asymp': '\u2248',
  'infin': '\u221E',
  'euro': '\u20AC',
  'pound': '\u00A3',
  'yen': '\u00A5',
  'cent': '\u00A2',
  'frac12': '\u00BD',
  'frac14': '\u00BC',
  'frac34': '\u00BE',
  'prime': '\u2032',
  'Prime': '\u2033',
};

/// Decodes common HTML named, decimal (`&#...;`), and hexadecimal (`&#x...;`)
/// character references in a single linear pass.
///
/// Must only be invoked on post-tokenization text payloads and attribute values,
/// never on raw HTML prior to tokenization.
String decodeHtmlEntities(String input) {
  if (!input.contains('&')) {
    return input;
  }
  StringBuffer? out;
  int last = 0;
  int i = 0;
  final int len = input.length;
  while (i < len) {
    if (input.codeUnitAt(i) != 0x26) {
      i++;
      continue;
    }
    final int semi = input.indexOf(';', i + 1);
    if (semi == -1 || semi - i > 16) {
      i++;
      continue;
    }
    final String body = input.substring(i + 1, semi);
    String? replacement;
    if (body.startsWith('#')) {
      final int? cp;
      if (body.length > 2 && (body[1] == 'x' || body[1] == 'X')) {
        cp = int.tryParse(body.substring(2), radix: 16);
      } else if (body.length > 1) {
        cp = int.tryParse(body.substring(1), radix: 10);
      } else {
        cp = null;
      }
      if (cp != null) {
        final bool valid =
            cp > 0 && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF);
        replacement = valid ? String.fromCharCode(cp) : '\uFFFD';
      }
    } else {
      replacement =
          _namedHtmlEntities[body] ?? _namedHtmlEntities[body.toLowerCase()];
    }
    if (replacement != null) {
      out ??= StringBuffer();
      if (i > last) {
        out.write(input.substring(last, i));
      }
      out.write(replacement);
      i = semi + 1;
      last = i;
    } else {
      i++;
    }
  }
  if (out == null) {
    return input;
  }
  if (last < len) {
    out.write(input.substring(last));
  }
  return out.toString();
}

/// Extracts decoded plain text from [rawHtml] after stripping comments and
/// dangerous HTML elements in a single linear scan.
String extractSafeHtmlPlainText(String rawHtml) {
  if (rawHtml.isEmpty) {
    return '';
  }
  final List<_HtmlToken> tokens = _tokenizeHtml(rawHtml);
  final StringBuffer out = StringBuffer();
  for (final _HtmlToken token in tokens) {
    if (token.kind == _HtmlTokenKind.text) {
      out.write(decodeHtmlEntities(token.rawText));
    }
  }
  return out.toString().trim();
}

/// Parses an HTML block fragment into structured [HtmlBlockEntry] nodes using
/// linear-time tokenization, post-tokenization entity decoding, and bounded
/// depth and element budgets.
List<HtmlBlockEntry> parseHtmlBlockFragment(
  String rawHtml, {
  required String parentBlockId,
  MarkdownUrlPolicy? urlPolicy,
}) {
  if (rawHtml.trim().isEmpty) {
    return const <HtmlBlockEntry>[];
  }
  final List<_HtmlToken> tokens = _tokenizeHtml(rawHtml);
  if (tokens.isEmpty) {
    return const <HtmlBlockEntry>[];
  }
  final _HtmlElement root = _buildHtmlTree(tokens);
  final _HtmlAstBuilder builder = _HtmlAstBuilder(
    parentBlockId: parentBlockId,
    urlPolicy: urlPolicy,
  );
  return builder.convertRoot(root);
}

enum _HtmlTokenKind { openTag, closeTag, text }

final class _HtmlToken {
  const _HtmlToken.open(this.name, this.attrs, {required this.selfClosing})
    : kind = _HtmlTokenKind.openTag,
      rawText = '';

  const _HtmlToken.close(this.name)
    : kind = _HtmlTokenKind.closeTag,
      attrs = const <String, String>{},
      selfClosing = false,
      rawText = '';

  const _HtmlToken.text(this.rawText)
    : kind = _HtmlTokenKind.text,
      name = '',
      attrs = const <String, String>{},
      selfClosing = false;

  final _HtmlTokenKind kind;
  final String name;
  final Map<String, String> attrs;
  final bool selfClosing;
  final String rawText;
}

const Set<String> _dangerousVoidTags = <String>{
  'base',
  'embed',
  'input',
  'link',
  'meta',
};

const Set<String> _dangerousRawTextTags = <String>{
  'noembed',
  'noframes',
  'plaintext',
  'script',
  'style',
  'textarea',
  'title',
  'xmp',
};

const Set<String> _dangerousContainerTags = <String>{
  'applet',
  'button',
  'form',
  'iframe',
  'noscript',
  'object',
  'option',
  'select',
  'svg',
  'template',
};

const Set<String> _voidHtmlTags = <String>{
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

bool _isDangerousTag(String tag) =>
    _dangerousVoidTags.contains(tag) ||
    _dangerousRawTextTags.contains(tag) ||
    _dangerousContainerTags.contains(tag);

bool _isAsciiWhitespace(int cu) =>
    cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0C || cu == 0x0D;

bool _isAsciiAlpha(int cu) =>
    (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A);

bool _isAsciiDigit(int cu) => cu >= 0x30 && cu <= 0x39;

bool _isTagNameChar(int cu) =>
    _isAsciiAlpha(cu) || _isAsciiDigit(cu) || cu == 0x2D || cu == 0x3A;

bool _matchesAsciiIgnoreCase(String input, int offset, String lowerTarget) {
  final int targetLen = lowerTarget.length;
  if (offset < 0 || offset + targetLen > input.length) {
    return false;
  }
  for (int i = 0; i < targetLen; i++) {
    int cu = input.codeUnitAt(offset + i);
    if (cu >= 0x41 && cu <= 0x5A) {
      cu += 0x20;
    }
    if (cu != lowerTarget.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

List<_HtmlToken> _tokenizeHtml(String html) {
  final List<_HtmlToken> tokens = <_HtmlToken>[];
  final int len = html.length;
  int pos = 0;

  while (pos < len) {
    final int lt = html.indexOf('<', pos);
    if (lt == -1) {
      tokens.add(_HtmlToken.text(html.substring(pos)));
      break;
    }
    if (lt > pos) {
      tokens.add(_HtmlToken.text(html.substring(pos, lt)));
      pos = lt;
    }

    if (pos + 1 >= len) {
      tokens.add(const _HtmlToken.text('<'));
      break;
    }

    // HTML comment (`<!-- ... -->`, or unclosed to EOF).
    if (html.startsWith('<!--', pos)) {
      final int endComment = html.indexOf('-->', pos + 4);
      if (endComment == -1) {
        pos = len;
        break;
      }
      pos = endComment + 3;
      continue;
    }

    final int nextCu = html.codeUnitAt(pos + 1);

    // Declarations / processing instructions (`<!...>`, `<?...>`).
    if (nextCu == 0x21 || nextCu == 0x3F) {
      final int gt = html.indexOf('>', pos + 2);
      if (gt == -1) {
        pos = len;
        break;
      }
      pos = gt + 1;
      continue;
    }

    // Closing tag (`</tag>`).
    if (nextCu == 0x2F) {
      if (pos + 2 >= len || !_isAsciiAlpha(html.codeUnitAt(pos + 2))) {
        tokens.add(const _HtmlToken.text('<'));
        pos++;
        continue;
      }
      int nameEnd = pos + 3;
      while (nameEnd < len && _isTagNameChar(html.codeUnitAt(nameEnd))) {
        nameEnd++;
      }
      int scan = nameEnd;
      while (scan < len && _isAsciiWhitespace(html.codeUnitAt(scan))) {
        scan++;
      }
      final int gt = html.indexOf('>', scan);
      if (gt == -1) {
        tokens.add(_HtmlToken.text(html.substring(pos)));
        pos = len;
        break;
      }
      final String tagName = html.substring(pos + 2, nameEnd).toLowerCase();
      if (!_isDangerousTag(tagName)) {
        tokens.add(_HtmlToken.close(tagName));
      }
      pos = gt + 1;
      continue;
    }

    // Opening tag (`<tag ...>`).
    if (!_isAsciiAlpha(nextCu)) {
      tokens.add(const _HtmlToken.text('<'));
      pos++;
      continue;
    }

    int nameEnd = pos + 2;
    while (nameEnd < len && _isTagNameChar(html.codeUnitAt(nameEnd))) {
      nameEnd++;
    }
    if (nameEnd < len) {
      final int afterCu = html.codeUnitAt(nameEnd);
      if (!_isAsciiWhitespace(afterCu) && afterCu != 0x3E && afterCu != 0x2F) {
        tokens.add(const _HtmlToken.text('<'));
        pos++;
        continue;
      }
    }

    final String tagName = html.substring(pos + 1, nameEnd).toLowerCase();
    final Map<String, String> attrs = <String, String>{};
    bool selfClosing = false;
    int? tagEnd;
    int i = nameEnd;

    while (i < len) {
      while (i < len && _isAsciiWhitespace(html.codeUnitAt(i))) {
        i++;
      }
      if (i >= len) {
        break;
      }
      final int cu = html.codeUnitAt(i);
      if (cu == 0x3E) {
        tagEnd = i + 1;
        break;
      }
      if (cu == 0x2F) {
        if (i + 1 < len && html.codeUnitAt(i + 1) == 0x3E) {
          selfClosing = true;
          tagEnd = i + 2;
          break;
        }
        i++;
        continue;
      }
      final int attrStart = i;
      while (i < len) {
        final int c = html.codeUnitAt(i);
        if (_isAsciiWhitespace(c) || c == 0x3D || c == 0x3E || c == 0x2F) {
          break;
        }
        i++;
      }
      if (i == attrStart) {
        i++;
        continue;
      }
      final String attrName = html.substring(attrStart, i).toLowerCase();
      while (i < len && _isAsciiWhitespace(html.codeUnitAt(i))) {
        i++;
      }
      String attrValue = '';
      if (i < len && html.codeUnitAt(i) == 0x3D) {
        i++;
        while (i < len && _isAsciiWhitespace(html.codeUnitAt(i))) {
          i++;
        }
        if (i < len) {
          final int q = html.codeUnitAt(i);
          if (q == 0x22 || q == 0x27) {
            i++;
            final int valStart = i;
            while (i < len && html.codeUnitAt(i) != q) {
              i++;
            }
            attrValue = decodeHtmlEntities(html.substring(valStart, i));
            if (i < len && html.codeUnitAt(i) == q) {
              i++;
            }
          } else {
            final int valStart = i;
            while (i < len) {
              final int c = html.codeUnitAt(i);
              if (_isAsciiWhitespace(c) || c == 0x3E) {
                break;
              }
              i++;
            }
            attrValue = decodeHtmlEntities(html.substring(valStart, i));
          }
        }
      }
      if (!attrs.containsKey(attrName)) {
        attrs[attrName] = attrValue;
      }
    }

    if (tagEnd == null) {
      if (_isDangerousTag(tagName)) {
        pos = len;
        break;
      }
      tokens.add(_HtmlToken.text(html.substring(pos)));
      pos = len;
      break;
    }

    if (_dangerousVoidTags.contains(tagName)) {
      pos = tagEnd;
      continue;
    }
    if (_dangerousRawTextTags.contains(tagName)) {
      pos = _skipDangerousElement(html, tagEnd, tagName, allowNesting: false);
      continue;
    }
    if (_dangerousContainerTags.contains(tagName)) {
      if (selfClosing) {
        pos = tagEnd;
      } else {
        pos = _skipDangerousElement(html, tagEnd, tagName, allowNesting: true);
      }
      continue;
    }

    final bool isVoid = selfClosing || _voidHtmlTags.contains(tagName);
    tokens.add(_HtmlToken.open(tagName, attrs, selfClosing: isVoid));
    pos = tagEnd;
  }

  return tokens;
}

int _skipDangerousElement(
  String html,
  int start,
  String tagName, {
  required bool allowNesting,
}) {
  final int len = html.length;
  final int tagLen = tagName.length;
  int depth = 1;
  int i = start;

  while (i < len) {
    final int lt = html.indexOf('<', i);
    if (lt == -1) {
      return len;
    }
    if (lt + 1 >= len) {
      return len;
    }
    final int nextCu = html.codeUnitAt(lt + 1);
    if (nextCu == 0x2F) {
      final int nameStart = lt + 2;
      if (nameStart + tagLen <= len &&
          _matchesAsciiIgnoreCase(html, nameStart, tagName)) {
        int after = nameStart + tagLen;
        while (after < len && _isAsciiWhitespace(html.codeUnitAt(after))) {
          after++;
        }
        if (after < len && html.codeUnitAt(after) == 0x3E) {
          depth--;
          if (depth <= 0) {
            return after + 1;
          }
          i = after + 1;
          continue;
        }
      }
    } else if (allowNesting &&
        lt + 1 + tagLen < len &&
        _matchesAsciiIgnoreCase(html, lt + 1, tagName)) {
      final int afterName = html.codeUnitAt(lt + 1 + tagLen);
      if (_isAsciiWhitespace(afterName) ||
          afterName == 0x3E ||
          afterName == 0x2F) {
        final int gt = html.indexOf('>', lt + 1 + tagLen);
        if (gt == -1) {
          return len;
        }
        final bool selfClosed = html.codeUnitAt(gt - 1) == 0x2F;
        if (!selfClosed) {
          depth++;
        }
        i = gt + 1;
        continue;
      }
    }
    i = lt + 1;
  }

  return len;
}

sealed class _HtmlNode {}

final class _HtmlText extends _HtmlNode {
  _HtmlText(this.rawText);

  final String rawText;
}

final class _HtmlElement extends _HtmlNode {
  _HtmlElement(this.tag, this.attrs);

  final String tag;
  final Map<String, String> attrs;
  final List<_HtmlNode> children = <_HtmlNode>[];
}

const Set<String> _implicitParagraphClosers = <String>{
  'address',
  'article',
  'aside',
  'blockquote',
  'center',
  'details',
  'div',
  'dl',
  'fieldset',
  'figure',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'ul',
};

const Set<String> _headingTags = <String>{'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

const Set<String> _tableScopeBoundaryTags = <String>{
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'th',
  'td',
  'caption',
};

const Set<String> _containerScopeBoundaryTags = <String>{
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'th',
  'td',
  'caption',
  'ul',
  'ol',
  'li',
  'dl',
  'dt',
  'dd',
  'blockquote',
  'details',
  'figure',
};

_HtmlElement _buildHtmlTree(List<_HtmlToken> tokens) {
  final _HtmlElement root = _HtmlElement('#root', const <String, String>{});
  final List<_HtmlElement> stack = <_HtmlElement>[root];

  void popDownTo(int targetIndex) {
    while (stack.length - 1 >= targetIndex && stack.length > 1) {
      stack.removeLast();
    }
  }

  void closeIfOpenWithin(
    Set<String> targets, {
    Set<String> stopAt = _containerScopeBoundaryTags,
  }) {
    for (int i = stack.length - 1; i >= 1; i--) {
      final String t = stack[i].tag;
      if (targets.contains(t)) {
        popDownTo(i);
        return;
      }
      if (stopAt.contains(t)) {
        return;
      }
    }
  }

  for (final _HtmlToken token in tokens) {
    switch (token.kind) {
      case _HtmlTokenKind.text:
        stack.last.children.add(_HtmlText(token.rawText));
      case _HtmlTokenKind.openTag:
        final String tag = token.name;
        if (tag == 'li') {
          closeIfOpenWithin(
            const <String>{'li'},
            stopAt: const <String>{'ul', 'ol', 'table', 'td', 'th', 'dl'},
          );
        } else if (tag == 'dt' || tag == 'dd') {
          closeIfOpenWithin(
            const <String>{'dt', 'dd'},
            stopAt: const <String>{'dl', 'table', 'td', 'th', 'ul', 'ol'},
          );
        } else if (tag == 'td' || tag == 'th') {
          closeIfOpenWithin(
            const <String>{'td', 'th'},
            stopAt: const <String>{'tr', 'thead', 'tbody', 'tfoot', 'table'},
          );
        } else if (tag == 'tr') {
          closeIfOpenWithin(
            const <String>{'tr', 'td', 'th'},
            stopAt: const <String>{'thead', 'tbody', 'tfoot', 'table'},
          );
        } else if (tag == 'thead' ||
            tag == 'tbody' ||
            tag == 'tfoot' ||
            tag == 'caption' ||
            tag == 'colgroup') {
          closeIfOpenWithin(
            const <String>{
              'thead',
              'tbody',
              'tfoot',
              'caption',
              'colgroup',
              'tr',
              'td',
              'th',
            },
            stopAt: const <String>{'table'},
          );
        } else if (_implicitParagraphClosers.contains(tag)) {
          closeIfOpenWithin(const <String>{'p'});
          if (_headingTags.contains(tag)) {
            closeIfOpenWithin(_headingTags);
          }
        }

        final _HtmlElement elem = _HtmlElement(tag, token.attrs);
        stack.last.children.add(elem);
        if (!token.selfClosing && stack.length < maxHtmlBlockDepth) {
          stack.add(elem);
        }
      case _HtmlTokenKind.closeTag:
        final String tag = token.name;
        if (tag == 'table') {
          for (int i = stack.length - 1; i >= 1; i--) {
            if (stack[i].tag == 'table') {
              popDownTo(i);
              break;
            }
          }
        } else if (tag == 'thead' ||
            tag == 'tbody' ||
            tag == 'tfoot' ||
            tag == 'caption' ||
            tag == 'colgroup') {
          closeIfOpenWithin(<String>{tag}, stopAt: const <String>{'table'});
        } else if (tag == 'tr') {
          closeIfOpenWithin(
            const <String>{'tr'},
            stopAt: const <String>{'thead', 'tbody', 'tfoot', 'table'},
          );
        } else if (tag == 'td' || tag == 'th') {
          closeIfOpenWithin(
            <String>{tag},
            stopAt: const <String>{'tr', 'table'},
          );
        } else if (tag == 'ul' || tag == 'ol') {
          closeIfOpenWithin(
            <String>{tag},
            stopAt: const <String>{'table', 'td', 'th', 'dl'},
          );
        } else if (tag == 'li') {
          closeIfOpenWithin(
            const <String>{'li'},
            stopAt: const <String>{'ul', 'ol', 'table', 'td', 'th'},
          );
        } else if (tag == 'dl') {
          closeIfOpenWithin(
            const <String>{'dl'},
            stopAt: const <String>{'table', 'td', 'th', 'ul', 'ol'},
          );
        } else if (tag == 'dt' || tag == 'dd') {
          closeIfOpenWithin(
            <String>{tag},
            stopAt: const <String>{'dl', 'table', 'td', 'th'},
          );
        } else {
          closeIfOpenWithin(<String>{tag}, stopAt: _tableScopeBoundaryTags);
        }
    }
  }

  return root;
}

final class _HtmlLinkContext {
  const _HtmlLinkContext({required this.destination, this.title});

  final String destination;
  final String? title;
}

final class _ParsedCell {
  const _ParsedCell({
    required this.children,
    required this.alignment,
    required this.colspan,
    required this.isTh,
  });

  final List<MarkdownInlineNode> children;
  final TableAlignment alignment;
  final int colspan;
  final bool isTh;
}

final class _ParsedRow {
  const _ParsedRow(this.cells);

  final List<_ParsedCell> cells;
}

final class _HtmlAstBuilder {
  _HtmlAstBuilder({required this.parentBlockId, this.urlPolicy});

  final String parentBlockId;
  final MarkdownUrlPolicy? urlPolicy;

  int _blockCount = 0;
  int _inlineCount = 0;
  int _listItemCount = 0;
  int _nestedIdCounter = 0;

  bool get _canAddBlock => _blockCount < maxHtmlBlocks;
  bool get _canAddInline => _inlineCount < maxHtmlInlines;

  String _nextNestedBlockId(String prefix) {
    final int id = _nestedIdCounter++;
    return '$prefix-b$id';
  }

  List<HtmlBlockEntry> convertRoot(_HtmlElement root) {
    final List<HtmlBlockEntry> rawEntries = <HtmlBlockEntry>[];
    _collectTopLevelEntries(
      root.children,
      out: rawEntries,
      activeLink: null,
      depth: 0,
    );
    if (rawEntries.isEmpty) {
      return const <HtmlBlockEntry>[];
    }
    final List<HtmlBlockEntry> indexed = <HtmlBlockEntry>[];
    for (int idx = 0; idx < rawEntries.length; idx++) {
      final HtmlBlockEntry entry = rawEntries[idx];
      final String topId = '$parentBlockId-h$idx';
      indexed.add(
        HtmlBlockEntry(
          _withBlockId(entry.block, topId),
          tableCaption: entry.tableCaption,
        ),
      );
    }
    return indexed;
  }

  MarkdownBlockNode _withBlockId(MarkdownBlockNode node, String newId) {
    switch (node) {
      case ParagraphNode():
        return ParagraphNode(
          blockId: newId,
          children: node.children,
          span: node.span,
        );
      case HeadingNode():
        return HeadingNode(
          blockId: newId,
          level: node.level,
          text: node.text,
          slug: node.slug,
          explicitId: node.explicitId,
          children: node.children,
          isSetext: node.isSetext,
          span: node.span,
        );
      case CodeBlockNode():
        return CodeBlockNode(
          blockId: newId,
          literal: node.literal,
          info: node.info,
          language: node.language,
          isFenced: node.isFenced,
          codeUnitOffset: node.codeUnitOffset,
          span: node.span,
        );
      case BlockQuoteNode():
        return BlockQuoteNode(
          blockId: newId,
          children: node.children,
          span: node.span,
        );
      case ListNode():
        return ListNode(
          blockId: newId,
          ordered: node.ordered,
          start: node.start,
          tight: node.tight,
          delimiter: node.delimiter,
          items: node.items,
          span: node.span,
        );
      case TableNode():
        return TableNode(
          blockId: newId,
          alignments: node.alignments,
          headers: node.headers,
          rows: node.rows,
          span: node.span,
        );
      case ThematicBreakNode():
        return ThematicBreakNode(blockId: newId, span: node.span);
      case DetailsBlockNode():
        return DetailsBlockNode(
          blockId: newId,
          summary: node.summary,
          summaryInlines: node.summaryInlines,
          initiallyOpen: node.initiallyOpen,
          children: node.children,
          span: node.span,
        );
      case AlignedBlockNode():
        return AlignedBlockNode(
          blockId: newId,
          alignment: node.alignment,
          children: node.children,
          span: node.span,
        );
      case FigureBlockNode():
        return FigureBlockNode(
          blockId: newId,
          children: node.children,
          caption: node.caption,
          captionInlines: node.captionInlines,
          span: node.span,
        );
      case DefinitionListNode():
        return DefinitionListNode(
          blockId: newId,
          groups: node.groups,
          span: node.span,
        );
      case FrontmatterNode():
      case AlertNode():
      case ListItemNode():
      case HtmlBlockNode():
      case MathBlockNode():
      case FootnoteDefinitionNode():
      case FootnoteSectionNode():
        return node;
    }
  }

  void _collectTopLevelEntries(
    List<_HtmlNode> nodes, {
    required List<HtmlBlockEntry> out,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddBlock) {
      return;
    }
    final List<_HtmlNode> pendingInlines = <_HtmlNode>[];

    void flushPendingInlines() {
      if (pendingInlines.isEmpty || !_canAddBlock) {
        pendingInlines.clear();
        return;
      }
      final List<MarkdownInlineNode> inlines = _buildNormalizedInlines(
        pendingInlines,
        activeLink: activeLink,
        depth: depth + 1,
      );
      pendingInlines.clear();
      if (inlines.isNotEmpty) {
        _blockCount++;
        out.add(
          HtmlBlockEntry(
            ParagraphNode(
              blockId: _nextNestedBlockId(parentBlockId),
              children: inlines,
            ),
          ),
        );
      }
    }

    for (final _HtmlNode node in nodes) {
      if (!_canAddBlock) {
        break;
      }
      if (node is _HtmlElement && _isBlockElement(node)) {
        flushPendingInlines();
        if (node.tag == 'div' &&
            _extractAlignment(node.attrs) == TableAlignment.none) {
          _collectTopLevelEntries(
            node.children,
            out: out,
            activeLink: activeLink,
            depth: depth + 1,
          );
        } else if (node.tag == 'a') {
          final _HtmlLinkContext? childLink =
              _extractLinkContext(node.attrs) ?? activeLink;
          final String? anchorId = _extractAnchorId(node.attrs);
          final int beforeCount = out.length;
          _collectTopLevelEntries(
            node.children,
            out: out,
            activeLink: childLink,
            depth: depth + 1,
          );
          if (anchorId != null) {
            _attachAnchorToEntries(
              out,
              startIndex: beforeCount,
              anchorId: anchorId,
              idPrefix: parentBlockId,
            );
          }
        } else {
          final HtmlBlockEntry? entry = _convertBlockElement(
            node,
            idPrefix: parentBlockId,
            activeLink: activeLink,
            depth: depth + 1,
          );
          if (entry != null) {
            out.add(entry);
          }
        }
      } else {
        pendingInlines.add(node);
      }
    }
    flushPendingInlines();
  }

  List<MarkdownBlockNode> _convertBlockChildren(
    List<_HtmlNode> nodes, {
    required String idPrefix,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddBlock) {
      return const <MarkdownBlockNode>[];
    }
    final List<MarkdownBlockNode> out = <MarkdownBlockNode>[];
    final List<_HtmlNode> pendingInlines = <_HtmlNode>[];

    void flushPendingInlines() {
      if (pendingInlines.isEmpty || !_canAddBlock) {
        pendingInlines.clear();
        return;
      }
      final List<MarkdownInlineNode> inlines = _buildNormalizedInlines(
        pendingInlines,
        activeLink: activeLink,
        depth: depth + 1,
      );
      pendingInlines.clear();
      if (inlines.isNotEmpty) {
        _blockCount++;
        out.add(
          ParagraphNode(
            blockId: _nextNestedBlockId(idPrefix),
            children: inlines,
          ),
        );
      }
    }

    for (final _HtmlNode node in nodes) {
      if (!_canAddBlock) {
        break;
      }
      if (node is _HtmlElement && _isBlockElement(node)) {
        flushPendingInlines();
        if ((node.tag == 'div' ||
                node.tag == 'section' ||
                node.tag == 'article' ||
                node.tag == 'header' ||
                node.tag == 'footer' ||
                node.tag == 'main' ||
                node.tag == 'aside' ||
                node.tag == 'nav' ||
                node.tag == 'fieldset' ||
                node.tag == 'address') &&
            _extractAlignment(node.attrs) == TableAlignment.none) {
          out.addAll(
            _convertBlockChildren(
              node.children,
              idPrefix: idPrefix,
              activeLink: activeLink,
              depth: depth + 1,
            ),
          );
        } else if (node.tag == 'a') {
          final _HtmlLinkContext? childLink =
              _extractLinkContext(node.attrs) ?? activeLink;
          final String? anchorId = _extractAnchorId(node.attrs);
          final int beforeCount = out.length;
          out.addAll(
            _convertBlockChildren(
              node.children,
              idPrefix: idPrefix,
              activeLink: childLink,
              depth: depth + 1,
            ),
          );
          if (anchorId != null) {
            _attachAnchorToBlocks(
              out,
              startIndex: beforeCount,
              anchorId: anchorId,
              idPrefix: idPrefix,
            );
          }
        } else {
          final HtmlBlockEntry? entry = _convertBlockElement(
            node,
            idPrefix: idPrefix,
            activeLink: activeLink,
            depth: depth + 1,
          );
          if (entry != null) {
            if (entry.block is TableNode &&
                entry.tableCaption != null &&
                entry.tableCaption!.isNotEmpty &&
                _canAddBlock) {
              _blockCount++;
              out.add(
                AlignedBlockNode(
                  blockId: _nextNestedBlockId(idPrefix),
                  alignment: TableAlignment.center,
                  children: <MarkdownBlockNode>[
                    ParagraphNode(
                      blockId: _nextNestedBlockId(idPrefix),
                      children: entry.tableCaption!,
                    ),
                  ],
                ),
              );
            }
            out.add(entry.block);
          }
        }
      } else {
        pendingInlines.add(node);
      }
    }
    flushPendingInlines();
    return out;
  }

  ParagraphNode? _createAnchorFallbackParagraph(
    String idPrefix,
    String anchorId,
  ) {
    if (!_canAddBlock) {
      return null;
    }
    _blockCount++;
    _inlineCount++;
    return ParagraphNode(
      blockId: _nextNestedBlockId(idPrefix),
      children: <MarkdownInlineNode>[AnchorInlineNode(anchorId)],
    );
  }

  void _attachAnchorToEntries(
    List<HtmlBlockEntry> out, {
    required int startIndex,
    required String anchorId,
    required String idPrefix,
  }) {
    if (!_canAddInline) {
      return;
    }
    if (out.length > startIndex) {
      final HtmlBlockEntry firstEntry = out[startIndex];
      final MarkdownBlockNode? attached = _prependAnchorToBlock(
        firstEntry.block,
        anchorId,
      );
      if (attached != null) {
        _inlineCount++;
        out[startIndex] = HtmlBlockEntry(
          attached,
          tableCaption: firstEntry.tableCaption,
        );
        return;
      }
      final ParagraphNode? fallback = _createAnchorFallbackParagraph(
        idPrefix,
        anchorId,
      );
      if (fallback != null) {
        out.insert(startIndex, HtmlBlockEntry(fallback));
      }
      return;
    }
    final ParagraphNode? fallback = _createAnchorFallbackParagraph(
      idPrefix,
      anchorId,
    );
    if (fallback != null) {
      out.add(HtmlBlockEntry(fallback));
    }
  }

  void _attachAnchorToBlocks(
    List<MarkdownBlockNode> out, {
    required int startIndex,
    required String anchorId,
    required String idPrefix,
  }) {
    if (!_canAddInline) {
      return;
    }
    if (out.length > startIndex) {
      final MarkdownBlockNode? attached = _prependAnchorToBlock(
        out[startIndex],
        anchorId,
      );
      if (attached != null) {
        _inlineCount++;
        out[startIndex] = attached;
        return;
      }
      final ParagraphNode? fallback = _createAnchorFallbackParagraph(
        idPrefix,
        anchorId,
      );
      if (fallback != null) {
        out.insert(startIndex, fallback);
      }
      return;
    }
    final ParagraphNode? fallback = _createAnchorFallbackParagraph(
      idPrefix,
      anchorId,
    );
    if (fallback != null) {
      out.add(fallback);
    }
  }

  MarkdownBlockNode? _prependAnchorToBlock(
    MarkdownBlockNode block,
    String anchorId,
  ) {
    final AnchorInlineNode anchor = AnchorInlineNode(anchorId);
    switch (block) {
      case ParagraphNode():
        return ParagraphNode(
          blockId: block.blockId,
          children: <MarkdownInlineNode>[anchor, ...block.children],
          span: block.span,
        );
      case HeadingNode():
        return HeadingNode(
          blockId: block.blockId,
          level: block.level,
          text: block.text,
          slug: block.slug,
          explicitId: block.explicitId,
          children: <MarkdownInlineNode>[anchor, ...block.children],
          isSetext: block.isSetext,
          span: block.span,
        );
      case AlignedBlockNode():
        if (block.children.isEmpty) {
          return null;
        }
        final MarkdownBlockNode? first = _prependAnchorToBlock(
          block.children.first,
          anchorId,
        );
        if (first == null) {
          return null;
        }
        return AlignedBlockNode(
          blockId: block.blockId,
          alignment: block.alignment,
          children: <MarkdownBlockNode>[first, ...block.children.skip(1)],
          span: block.span,
        );
      case BlockQuoteNode():
        if (block.children.isEmpty) {
          return null;
        }
        final MarkdownBlockNode? first = _prependAnchorToBlock(
          block.children.first,
          anchorId,
        );
        if (first == null) {
          return null;
        }
        return BlockQuoteNode(
          blockId: block.blockId,
          children: <MarkdownBlockNode>[first, ...block.children.skip(1)],
          span: block.span,
        );
      case FigureBlockNode():
        if (block.children.isNotEmpty) {
          final MarkdownBlockNode? first = _prependAnchorToBlock(
            block.children.first,
            anchorId,
          );
          if (first != null) {
            return FigureBlockNode(
              blockId: block.blockId,
              children: <MarkdownBlockNode>[first, ...block.children.skip(1)],
              caption: block.caption,
              captionInlines: block.captionInlines,
              span: block.span,
            );
          }
        }
        if (block.captionInlines.isNotEmpty ||
            (block.caption != null && block.caption!.isNotEmpty)) {
          final List<MarkdownInlineNode> caption =
              block.captionInlines.isNotEmpty
              ? block.captionInlines
              : <MarkdownInlineNode>[TextNode(block.caption!)];
          return FigureBlockNode(
            blockId: block.blockId,
            children: block.children,
            caption: block.caption,
            captionInlines: <MarkdownInlineNode>[anchor, ...caption],
            span: block.span,
          );
        }
        return null;
      case DetailsBlockNode():
        final List<MarkdownInlineNode> summary = block.summaryInlines.isNotEmpty
            ? block.summaryInlines
            : <MarkdownInlineNode>[TextNode(block.summary)];
        return DetailsBlockNode(
          blockId: block.blockId,
          summary: block.summary,
          summaryInlines: <MarkdownInlineNode>[anchor, ...summary],
          initiallyOpen: block.initiallyOpen,
          children: block.children,
          span: block.span,
        );
      case ListNode():
        if (block.items.isEmpty) {
          return null;
        }
        final MarkdownBlockNode? first = _prependAnchorToBlock(
          block.items.first,
          anchorId,
        );
        if (first is! ListItemNode) {
          return null;
        }
        return ListNode(
          blockId: block.blockId,
          ordered: block.ordered,
          start: block.start,
          tight: block.tight,
          delimiter: block.delimiter,
          items: <ListItemNode>[first, ...block.items.skip(1)],
          span: block.span,
        );
      case ListItemNode():
        if (block.children.isEmpty) {
          return null;
        }
        final MarkdownBlockNode? first = _prependAnchorToBlock(
          block.children.first,
          anchorId,
        );
        if (first == null) {
          return null;
        }
        return ListItemNode(
          blockId: block.blockId,
          taskState: block.taskState,
          children: <MarkdownBlockNode>[first, ...block.children.skip(1)],
          span: block.span,
        );
      case TableNode():
        if (block.headers.isNotEmpty) {
          final TableCellNode first = block.headers.first;
          return TableNode(
            blockId: block.blockId,
            alignments: block.alignments,
            headers: <TableCellNode>[
              TableCellNode(
                children: <MarkdownInlineNode>[anchor, ...first.children],
                alignment: first.alignment,
                span: first.span,
              ),
              ...block.headers.skip(1),
            ],
            rows: block.rows,
            span: block.span,
          );
        }
        if (block.rows.isNotEmpty && block.rows.first.isNotEmpty) {
          final List<TableCellNode> firstRow = block.rows.first;
          final TableCellNode firstCell = firstRow.first;
          final List<TableCellNode> updatedRow = <TableCellNode>[
            TableCellNode(
              children: <MarkdownInlineNode>[anchor, ...firstCell.children],
              alignment: firstCell.alignment,
              span: firstCell.span,
            ),
            ...firstRow.skip(1),
          ];
          return TableNode(
            blockId: block.blockId,
            alignments: block.alignments,
            headers: block.headers,
            rows: <List<TableCellNode>>[updatedRow, ...block.rows.skip(1)],
            span: block.span,
          );
        }
        return null;
      case DefinitionListNode():
        if (block.groups.isEmpty) {
          return null;
        }
        final DefinitionGroup first = block.groups.first;
        return DefinitionListNode(
          blockId: block.blockId,
          groups: <DefinitionGroup>[
            DefinitionGroup(
              term: <MarkdownInlineNode>[anchor, ...first.term],
              definitions: first.definitions,
            ),
            ...block.groups.skip(1),
          ],
          span: block.span,
        );
      case CodeBlockNode():
      case ThematicBreakNode():
      case FrontmatterNode():
      case AlertNode():
      case HtmlBlockNode():
      case MathBlockNode():
      case FootnoteDefinitionNode():
      case FootnoteSectionNode():
        return null;
    }
  }

  HtmlBlockEntry? _convertBlockElement(
    _HtmlElement elem, {
    required String idPrefix,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddBlock) {
      return null;
    }
    final String tag = elem.tag;

    if (tag == 'hr') {
      _blockCount++;
      return HtmlBlockEntry(
        ThematicBreakNode(blockId: _nextNestedBlockId(idPrefix)),
      );
    }

    if (tag == 'pre') {
      final String? language = _extractPreLanguage(elem);
      final String literal = _extractVerbatimPreText(elem);
      _blockCount++;
      return HtmlBlockEntry(
        CodeBlockNode(
          blockId: _nextNestedBlockId(idPrefix),
          literal: literal,
          info: language ?? '',
          language: language,
        ),
      );
    }

    if (tag == 'table') {
      return _convertTable(
        elem,
        idPrefix: idPrefix,
        activeLink: activeLink,
        depth: depth,
      );
    }

    if (tag == 'dl') {
      final DefinitionListNode? dl = _convertDefinitionList(
        elem,
        idPrefix: idPrefix,
        activeLink: activeLink,
        depth: depth,
      );
      return dl == null ? null : HtmlBlockEntry(dl);
    }

    if (tag == 'ul' || tag == 'ol') {
      final ListNode? list = _convertList(
        elem,
        idPrefix: idPrefix,
        activeLink: activeLink,
        depth: depth,
      );
      return list == null ? null : HtmlBlockEntry(list);
    }

    if (tag == 'blockquote') {
      final List<MarkdownBlockNode> children = _convertBlockChildren(
        elem.children,
        idPrefix: idPrefix,
        activeLink: activeLink,
        depth: depth + 1,
      );
      if (children.isEmpty || !_canAddBlock) {
        return null;
      }
      _blockCount++;
      return HtmlBlockEntry(
        BlockQuoteNode(
          blockId: _nextNestedBlockId(idPrefix),
          children: children,
        ),
      );
    }

    if (tag == 'details') {
      return _convertDetails(
        elem,
        idPrefix: idPrefix,
        activeLink: activeLink,
        depth: depth,
      );
    }

    if (tag == 'figure') {
      return _convertFigure(
        elem,
        idPrefix: idPrefix,
        activeLink: activeLink,
        depth: depth,
      );
    }

    if (_headingTags.contains(tag)) {
      final int level = int.parse(tag.substring(1));
      final List<MarkdownInlineNode> inlines = _buildNormalizedInlines(
        elem.children,
        activeLink: activeLink,
        depth: depth + 1,
      );
      if (!_canAddBlock) {
        return null;
      }
      final String? explicitId = _nonEmptyOrNull(elem.attrs['id']);
      final String plainText = inlines
          .map((MarkdownInlineNode n) => n.toPlainText())
          .join();
      _blockCount++;
      final HeadingNode heading = HeadingNode(
        blockId: _nextNestedBlockId(idPrefix),
        level: level,
        text: plainText,
        explicitId: explicitId,
        children: inlines,
      );
      final TableAlignment align = _extractAlignment(elem.attrs);
      if (align != TableAlignment.none && _canAddBlock) {
        _blockCount++;
        return HtmlBlockEntry(
          AlignedBlockNode(
            blockId: _nextNestedBlockId(idPrefix),
            alignment: align,
            children: <MarkdownBlockNode>[heading],
          ),
        );
      }
      return HtmlBlockEntry(heading);
    }

    if (tag == 'p') {
      final TableAlignment align = _extractAlignment(elem.attrs);
      if (elem.children.any(
        (_HtmlNode c) => c is _HtmlElement && _isBlockElement(c),
      )) {
        final List<MarkdownBlockNode> children = _convertBlockChildren(
          elem.children,
          idPrefix: idPrefix,
          activeLink: activeLink,
          depth: depth + 1,
        );
        if (children.isEmpty || !_canAddBlock) {
          return null;
        }
        if (align != TableAlignment.none) {
          _blockCount++;
          return HtmlBlockEntry(
            AlignedBlockNode(
              blockId: _nextNestedBlockId(idPrefix),
              alignment: align,
              children: children,
            ),
          );
        }
        if (children.length == 1) {
          return HtmlBlockEntry(children.first);
        }
        _blockCount++;
        return HtmlBlockEntry(
          AlignedBlockNode(
            blockId: _nextNestedBlockId(idPrefix),
            alignment: TableAlignment.left,
            children: children,
          ),
        );
      }
      final List<MarkdownInlineNode> inlines = _buildNormalizedInlines(
        elem.children,
        activeLink: activeLink,
        depth: depth + 1,
      );
      if (inlines.isEmpty || !_canAddBlock) {
        return null;
      }
      _blockCount++;
      final ParagraphNode para = ParagraphNode(
        blockId: _nextNestedBlockId(idPrefix),
        children: inlines,
      );
      if (align != TableAlignment.none && _canAddBlock) {
        _blockCount++;
        return HtmlBlockEntry(
          AlignedBlockNode(
            blockId: _nextNestedBlockId(idPrefix),
            alignment: align,
            children: <MarkdownBlockNode>[para],
          ),
        );
      }
      return HtmlBlockEntry(para);
    }

    if (tag == 'center') {
      final List<MarkdownBlockNode> children = _convertBlockChildren(
        elem.children,
        idPrefix: idPrefix,
        activeLink: activeLink,
        depth: depth + 1,
      );
      if (children.isEmpty || !_canAddBlock) {
        return null;
      }
      _blockCount++;
      return HtmlBlockEntry(
        AlignedBlockNode(
          blockId: _nextNestedBlockId(idPrefix),
          alignment: TableAlignment.center,
          children: children,
        ),
      );
    }

    // `div`, `section`, `article`, `header`, `footer`, `main`, `aside`, etc.
    final TableAlignment align = _extractAlignment(elem.attrs);
    final List<MarkdownBlockNode> children = _convertBlockChildren(
      elem.children,
      idPrefix: idPrefix,
      activeLink: activeLink,
      depth: depth + 1,
    );
    if (children.isEmpty || !_canAddBlock) {
      return null;
    }
    if (align != TableAlignment.none) {
      _blockCount++;
      return HtmlBlockEntry(
        AlignedBlockNode(
          blockId: _nextNestedBlockId(idPrefix),
          alignment: align,
          children: children,
        ),
      );
    }
    if (children.length == 1) {
      return HtmlBlockEntry(children.first);
    }
    _blockCount++;
    return HtmlBlockEntry(
      AlignedBlockNode(
        blockId: _nextNestedBlockId(idPrefix),
        alignment: TableAlignment.none,
        children: children,
      ),
    );
  }

  HtmlBlockEntry? _convertDetails(
    _HtmlElement elem, {
    required String idPrefix,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (!_canAddBlock) {
      return null;
    }
    final bool initiallyOpen = elem.attrs.containsKey('open');
    List<MarkdownInlineNode> summaryInlines = const <MarkdownInlineNode>[];
    final List<_HtmlNode> bodyNodes = <_HtmlNode>[];
    bool foundSummary = false;

    for (final _HtmlNode child in elem.children) {
      if (!foundSummary && child is _HtmlElement && child.tag == 'summary') {
        foundSummary = true;
        summaryInlines = _buildNormalizedInlines(
          child.children,
          activeLink: activeLink,
          depth: depth + 1,
        );
      } else {
        bodyNodes.add(child);
      }
    }

    final String summaryText = summaryInlines
        .map((MarkdownInlineNode n) => n.toPlainText())
        .join()
        .trim();
    final List<MarkdownBlockNode> bodyBlocks = _convertBlockChildren(
      bodyNodes,
      idPrefix: idPrefix,
      activeLink: activeLink,
      depth: depth + 1,
    );
    _blockCount++;
    return HtmlBlockEntry(
      DetailsBlockNode(
        blockId: _nextNestedBlockId(idPrefix),
        summary: summaryText.isEmpty ? 'Details' : summaryText,
        summaryInlines: summaryInlines,
        initiallyOpen: initiallyOpen,
        children: bodyBlocks,
      ),
    );
  }

  HtmlBlockEntry? _convertFigure(
    _HtmlElement elem, {
    required String idPrefix,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (!_canAddBlock) {
      return null;
    }
    List<MarkdownInlineNode> captionInlines = const <MarkdownInlineNode>[];
    final List<_HtmlNode> bodyNodes = <_HtmlNode>[];
    bool foundCaption = false;

    for (final _HtmlNode child in elem.children) {
      if (!foundCaption && child is _HtmlElement && child.tag == 'figcaption') {
        foundCaption = true;
        captionInlines = _buildNormalizedInlines(
          child.children,
          activeLink: activeLink,
          depth: depth + 1,
        );
      } else {
        bodyNodes.add(child);
      }
    }

    final List<MarkdownBlockNode> bodyBlocks = _convertBlockChildren(
      bodyNodes,
      idPrefix: idPrefix,
      activeLink: activeLink,
      depth: depth + 1,
    );
    final String captionText = captionInlines
        .map((MarkdownInlineNode n) => n.toPlainText())
        .join()
        .trim();
    _blockCount++;
    return HtmlBlockEntry(
      FigureBlockNode(
        blockId: _nextNestedBlockId(idPrefix),
        children: bodyBlocks,
        caption: captionText.isEmpty ? null : captionText,
        captionInlines: captionInlines,
      ),
    );
  }

  ListNode? _convertList(
    _HtmlElement elem, {
    required String idPrefix,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddBlock) {
      return null;
    }
    final bool ordered = elem.tag == 'ol';
    final int start = ordered
        ? (int.tryParse((elem.attrs['start'] ?? '').trim()) ?? 1)
        : 1;
    final List<ListItemNode> items = <ListItemNode>[];
    bool tight = true;

    for (final _HtmlNode child in elem.children) {
      if (_listItemCount >= maxHtmlListItems || !_canAddBlock) {
        break;
      }
      if (child is _HtmlText) {
        if (_isAllAsciiWhitespace(child.rawText)) {
          continue;
        }
        final List<MarkdownInlineNode> looseInlines = _buildNormalizedInlines(
          <_HtmlNode>[child],
          activeLink: activeLink,
          depth: depth + 1,
        );
        if (looseInlines.isNotEmpty && _canAddBlock) {
          _listItemCount++;
          _blockCount++;
          items.add(
            ListItemNode(
              blockId: _nextNestedBlockId(idPrefix),
              children: <MarkdownBlockNode>[
                ParagraphNode(
                  blockId: _nextNestedBlockId(idPrefix),
                  children: looseInlines,
                ),
              ],
            ),
          );
        }
        continue;
      }
      if (child is _HtmlElement && child.tag == 'li') {
        _listItemCount++;
        if (child.children.any(
          (_HtmlNode c) => c is _HtmlElement && c.tag == 'p',
        )) {
          tight = false;
        }
        final List<MarkdownBlockNode> itemBlocks = _convertBlockChildren(
          child.children,
          idPrefix: idPrefix,
          activeLink: activeLink,
          depth: depth + 1,
        );
        if (!_canAddBlock) {
          break;
        }
        _blockCount++;
        items.add(
          ListItemNode(
            blockId: _nextNestedBlockId(idPrefix),
            children: itemBlocks,
          ),
        );
      }
    }

    if (items.isEmpty || !_canAddBlock) {
      return null;
    }
    _blockCount++;
    return ListNode(
      blockId: _nextNestedBlockId(idPrefix),
      ordered: ordered,
      start: start,
      tight: tight,
      delimiter: ordered ? '.' : '-',
      items: items,
    );
  }

  DefinitionListNode? _convertDefinitionList(
    _HtmlElement elem, {
    required String idPrefix,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddBlock) {
      return null;
    }
    final List<DefinitionGroup> groups = <DefinitionGroup>[];
    List<MarkdownInlineNode>? currentTerm;
    List<List<MarkdownBlockNode>> currentDefs = <List<MarkdownBlockNode>>[];

    void flushGroup() {
      if (currentTerm != null) {
        groups.add(
          DefinitionGroup(term: currentTerm!, definitions: currentDefs),
        );
        currentTerm = null;
        currentDefs = <List<MarkdownBlockNode>>[];
      }
    }

    void visitDlChildren(List<_HtmlNode> children, int currentDepth) {
      if (currentDepth >= maxHtmlBlockDepth) {
        return;
      }
      for (final _HtmlNode child in children) {
        if (!_canAddBlock) {
          return;
        }
        if (child is! _HtmlElement) {
          continue;
        }
        if (child.tag == 'div') {
          visitDlChildren(child.children, currentDepth + 1);
        } else if (child.tag == 'dt') {
          flushGroup();
          currentTerm = _buildNormalizedInlines(
            child.children,
            activeLink: activeLink,
            depth: currentDepth + 1,
          );
        } else if (child.tag == 'dd') {
          currentTerm ??= const <MarkdownInlineNode>[];
          final List<MarkdownBlockNode> defBlocks = _convertBlockChildren(
            child.children,
            idPrefix: idPrefix,
            activeLink: activeLink,
            depth: currentDepth + 1,
          );
          if (defBlocks.isNotEmpty) {
            currentDefs.add(defBlocks);
          }
        }
      }
    }

    visitDlChildren(elem.children, depth + 1);
    flushGroup();

    if (groups.isEmpty || !_canAddBlock) {
      return null;
    }
    _blockCount++;
    return DefinitionListNode(
      blockId: _nextNestedBlockId(idPrefix),
      groups: groups,
    );
  }

  HtmlBlockEntry? _convertTable(
    _HtmlElement tableElem, {
    required String idPrefix,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddBlock) {
      return null;
    }
    List<MarkdownInlineNode>? captionInlines;
    final List<_ParsedRow> theadRows = <_ParsedRow>[];
    final List<_ParsedRow> bodyRows = <_ParsedRow>[];
    final List<_ParsedRow> tfootRows = <_ParsedRow>[];
    final List<_ParsedCell> looseCells = <_ParsedCell>[];

    int totalRows = 0;

    void flushLooseCells(List<_ParsedRow> target) {
      if (looseCells.isNotEmpty && totalRows < maxHtmlTableRows) {
        target.add(_ParsedRow(List<_ParsedCell>.of(looseCells)));
        totalRows++;
      }
      looseCells.clear();
    }

    _ParsedRow? parseTr(_HtmlElement trElem) {
      final List<_ParsedCell> cells = <_ParsedCell>[];
      final List<_HtmlNode> strayNodes = <_HtmlNode>[];
      int rowColCount = 0;

      for (final _HtmlNode child in trElem.children) {
        if (child is _HtmlElement && (child.tag == 'th' || child.tag == 'td')) {
          if (rowColCount >= maxHtmlTableColumns) {
            continue;
          }
          final int colspan = _parseColspan(
            child.attrs['colspan'],
            remainingCols: maxHtmlTableColumns - rowColCount,
          );
          final List<MarkdownInlineNode> cellInlines =
              _buildNormalizedInlineCell(
                child.children,
                activeLink: activeLink,
                depth: depth + 2,
              );
          cells.add(
            _ParsedCell(
              children: cellInlines,
              alignment: _extractAlignment(child.attrs),
              colspan: colspan,
              isTh: child.tag == 'th',
            ),
          );
          rowColCount += colspan;
        } else {
          strayNodes.add(child);
        }
      }

      if (cells.isEmpty &&
          strayNodes.isNotEmpty &&
          rowColCount < maxHtmlTableColumns) {
        final List<MarkdownInlineNode> fallbackInlines =
            _buildNormalizedInlineCell(
              strayNodes,
              activeLink: activeLink,
              depth: depth + 2,
            );
        if (fallbackInlines.isNotEmpty) {
          cells.add(
            _ParsedCell(
              children: fallbackInlines,
              alignment: TableAlignment.none,
              colspan: 1,
              isTh: false,
            ),
          );
        }
      }

      return cells.isEmpty ? null : _ParsedRow(cells);
    }

    void collectSectionRows(List<_HtmlNode> children, List<_ParsedRow> target) {
      for (final _HtmlNode child in children) {
        if (totalRows >= maxHtmlTableRows) {
          break;
        }
        if (child is! _HtmlElement) {
          continue;
        }
        if (child.tag == 'tr') {
          flushLooseCells(target);
          final _ParsedRow? row = parseTr(child);
          if (row != null) {
            target.add(row);
            totalRows++;
          }
        } else if (child.tag == 'th' || child.tag == 'td') {
          if (looseCells.length < maxHtmlTableColumns) {
            looseCells.add(
              _ParsedCell(
                children: _buildNormalizedInlineCell(
                  child.children,
                  activeLink: activeLink,
                  depth: depth + 2,
                ),
                alignment: _extractAlignment(child.attrs),
                colspan: _parseColspan(
                  child.attrs['colspan'],
                  remainingCols: maxHtmlTableColumns,
                ),
                isTh: child.tag == 'th',
              ),
            );
          }
        }
      }
      flushLooseCells(target);
    }

    for (final _HtmlNode child in tableElem.children) {
      if (child is! _HtmlElement) {
        continue;
      }
      switch (child.tag) {
        case 'caption':
          if (captionInlines == null) {
            final List<MarkdownInlineNode> parsedCap = _buildNormalizedInlines(
              child.children,
              activeLink: activeLink,
              depth: depth + 1,
            );
            if (parsedCap.isNotEmpty) {
              captionInlines = parsedCap;
            }
          }
        case 'colgroup':
        case 'col':
          break;
        case 'thead':
          collectSectionRows(child.children, theadRows);
        case 'tbody':
          collectSectionRows(child.children, bodyRows);
        case 'tfoot':
          collectSectionRows(child.children, tfootRows);
        case 'tr':
          if (totalRows < maxHtmlTableRows) {
            flushLooseCells(bodyRows);
            final _ParsedRow? row = parseTr(child);
            if (row != null) {
              bodyRows.add(row);
              totalRows++;
            }
          }
        case 'th':
        case 'td':
          if (looseCells.length < maxHtmlTableColumns) {
            looseCells.add(
              _ParsedCell(
                children: _buildNormalizedInlineCell(
                  child.children,
                  activeLink: activeLink,
                  depth: depth + 2,
                ),
                alignment: _extractAlignment(child.attrs),
                colspan: _parseColspan(
                  child.attrs['colspan'],
                  remainingCols: maxHtmlTableColumns,
                ),
                isTh: child.tag == 'th',
              ),
            );
          }
        default:
          break;
      }
    }
    flushLooseCells(bodyRows);

    final List<_ParsedRow> nonHeaderPool = <_ParsedRow>[
      ...bodyRows,
      ...tfootRows,
    ];

    _ParsedRow? promotedHeaderRow;
    final List<_ParsedRow> remainingRows = <_ParsedRow>[];

    if (theadRows.isNotEmpty) {
      promotedHeaderRow = theadRows.first;
      for (int i = 1; i < theadRows.length; i++) {
        // Extra <thead> rows render in body with bolded cells.
        remainingRows.add(
          _ParsedRow(<_ParsedCell>[
            for (final _ParsedCell c in theadRows[i].cells)
              _ParsedCell(
                children: c.children,
                alignment: c.alignment,
                colspan: c.colspan,
                isTh: true,
              ),
          ]),
        );
      }
      remainingRows.addAll(nonHeaderPool);
    } else if (nonHeaderPool.isNotEmpty) {
      final _ParsedRow first = nonHeaderPool.first;
      final bool isLeadingAllTh =
          first.cells.isNotEmpty &&
          first.cells.every((_ParsedCell cell) => cell.isTh);
      if (isLeadingAllTh) {
        promotedHeaderRow = first;
        remainingRows.addAll(nonHeaderPool.skip(1));
      } else {
        remainingRows.addAll(nonHeaderPool);
      }
    }

    List<TableCellNode> expandRow(_ParsedRow row, {required bool boldTh}) {
      final List<TableCellNode> expanded = <TableCellNode>[];
      for (final _ParsedCell cell in row.cells) {
        if (expanded.length >= maxHtmlTableColumns) {
          break;
        }
        final int span = cell.colspan.clamp(
          1,
          maxHtmlTableColumns - expanded.length,
        );
        final List<MarkdownInlineNode> children =
            (boldTh && cell.isTh && cell.children.isNotEmpty)
            ? <MarkdownInlineNode>[StrongNode(children: cell.children)]
            : cell.children;
        expanded.add(
          TableCellNode(children: children, alignment: cell.alignment),
        );
        for (int p = 1; p < span; p++) {
          expanded.add(TableCellNode(alignment: cell.alignment));
        }
      }
      return expanded;
    }

    final List<TableCellNode> expandedHeaders = promotedHeaderRow == null
        ? const <TableCellNode>[]
        : expandRow(promotedHeaderRow, boldTh: false);

    final List<List<TableCellNode>> expandedRows = <List<TableCellNode>>[
      for (final _ParsedRow row in remainingRows) expandRow(row, boldTh: true),
    ];

    int maxCols = expandedHeaders.length;
    for (final List<TableCellNode> row in expandedRows) {
      if (row.length > maxCols) {
        maxCols = row.length;
      }
    }

    if (maxCols == 0) {
      if (captionInlines != null && captionInlines.isNotEmpty && _canAddBlock) {
        _blockCount++;
        return HtmlBlockEntry(
          AlignedBlockNode(
            blockId: _nextNestedBlockId(idPrefix),
            alignment: TableAlignment.center,
            children: <MarkdownBlockNode>[
              ParagraphNode(
                blockId: _nextNestedBlockId(idPrefix),
                children: captionInlines,
              ),
            ],
          ),
        );
      }
      return null;
    }

    List<TableCellNode> padRow(List<TableCellNode> row) {
      if (row.length >= maxCols) {
        return row;
      }
      return <TableCellNode>[
        ...row,
        for (int c = row.length; c < maxCols; c++) const TableCellNode(),
      ];
    }

    final List<TableCellNode> finalHeaders = expandedHeaders.isEmpty
        ? const <TableCellNode>[]
        : padRow(expandedHeaders);
    final List<List<TableCellNode>> finalRows = <List<TableCellNode>>[
      for (final List<TableCellNode> row in expandedRows) padRow(row),
    ];

    final List<TableAlignment> alignments = <TableAlignment>[
      for (int c = 0; c < maxCols; c++)
        c < finalHeaders.length
            ? finalHeaders[c].alignment
            : TableAlignment.none,
    ];

    if (!_canAddBlock) {
      return null;
    }
    _blockCount++;
    return HtmlBlockEntry(
      TableNode(
        blockId: _nextNestedBlockId(idPrefix),
        alignments: alignments,
        headers: finalHeaders,
        rows: finalRows,
      ),
      tableCaption: captionInlines,
    );
  }

  List<MarkdownInlineNode> _buildNormalizedInlineCell(
    List<_HtmlNode> nodes, {
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    final List<MarkdownInlineNode> raw = <MarkdownInlineNode>[];
    _appendCellInlines(nodes, out: raw, activeLink: null, depth: depth);
    return _applyActiveLink(_normalizeInlineList(raw), activeLink);
  }

  void _appendCellInlines(
    List<_HtmlNode> nodes, {
    required List<MarkdownInlineNode> out,
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddInline) {
      return;
    }
    for (int i = 0; i < nodes.length; i++) {
      if (!_canAddInline) {
        break;
      }
      final _HtmlNode node = nodes[i];
      if (node is _HtmlText) {
        _appendInlineNode(node, out: out, activeLink: activeLink, depth: depth);
        continue;
      }
      if (node is _HtmlElement) {
        if (node.tag == 'pre') {
          final String text = _extractVerbatimPreText(node);
          if (text.isNotEmpty) {
            final CodeSpanNode code = CodeSpanNode(text);
            out.add(
              activeLink == null
                  ? code
                  : LinkNode(
                      destination: activeLink.destination,
                      title: activeLink.title,
                      children: <MarkdownInlineNode>[code],
                    ),
            );
            _inlineCount++;
          }
        } else if (node.tag == 'table') {
          // Flatten nested tables inside a cell safely without recursion blowup.
          final List<MarkdownInlineNode> nested = _flattenTableInlines(
            node,
            activeLink: activeLink,
            depth: depth + 1,
          );
          if (nested.isNotEmpty) {
            if (out.isNotEmpty && out.last is! InlineBreakNode) {
              out.add(const InlineBreakNode());
            }
            out.addAll(nested);
          }
        } else if (_isBlockElement(node) && node.tag != 'a') {
          if (out.isNotEmpty && out.last is! InlineBreakNode) {
            out.add(const InlineBreakNode());
          }
          _appendCellInlines(
            node.children,
            out: out,
            activeLink: activeLink,
            depth: depth + 1,
          );
          if (i + 1 < nodes.length &&
              out.isNotEmpty &&
              out.last is! InlineBreakNode) {
            out.add(const InlineBreakNode());
          }
        } else {
          _appendInlineNode(
            node,
            out: out,
            activeLink: activeLink,
            depth: depth,
          );
        }
      }
    }
  }

  List<MarkdownInlineNode> _flattenTableInlines(
    _HtmlElement tableElem, {
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddInline) {
      return const <MarkdownInlineNode>[];
    }
    final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];

    void walk(List<_HtmlNode> nodes, int d) {
      if (d >= maxHtmlBlockDepth || !_canAddInline) {
        return;
      }
      for (final _HtmlNode n in nodes) {
        if (!_canAddInline) {
          return;
        }
        if (n is _HtmlText) {
          _appendInlineNode(n, out: out, activeLink: activeLink, depth: d);
        } else if (n is _HtmlElement) {
          if (n.tag == 'td' || n.tag == 'th') {
            if (out.isNotEmpty && out.last is! InlineBreakNode) {
              out.add(const TextNode(' '));
            }
            walk(n.children, d + 1);
          } else if (n.tag == 'tr') {
            if (out.isNotEmpty && out.last is! InlineBreakNode) {
              out.add(const InlineBreakNode());
            }
            walk(n.children, d + 1);
          } else {
            walk(n.children, d + 1);
          }
        }
      }
    }

    walk(tableElem.children, depth);
    return out;
  }

  List<MarkdownInlineNode> _buildNormalizedInlines(
    List<_HtmlNode> nodes, {
    required _HtmlLinkContext? activeLink,
    required int depth,
  }) {
    final List<MarkdownInlineNode> raw = <MarkdownInlineNode>[];
    for (final _HtmlNode node in nodes) {
      if (!_canAddInline) {
        break;
      }
      _appendInlineNode(node, out: raw, activeLink: null, depth: depth);
    }
    return _applyActiveLink(_normalizeInlineList(raw), activeLink);
  }

  List<MarkdownInlineNode> _applyActiveLink(
    List<MarkdownInlineNode> nodes,
    _HtmlLinkContext? activeLink,
  ) {
    if (activeLink == null || nodes.isEmpty) {
      return nodes;
    }
    final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
    final List<MarkdownInlineNode> run = <MarkdownInlineNode>[];

    void flushRun() {
      if (run.isEmpty) {
        return;
      }
      _inlineCount++;
      out.add(
        LinkNode(
          destination: activeLink.destination,
          title: activeLink.title,
          children: List<MarkdownInlineNode>.of(run),
        ),
      );
      run.clear();
    }

    for (final MarkdownInlineNode node in nodes) {
      if (node is LinkNode || node is AnchorInlineNode) {
        flushRun();
        out.add(node);
      } else {
        run.add(node);
      }
    }
    flushRun();
    return out;
  }

  void _appendInlineNode(
    _HtmlNode node, {
    required List<MarkdownInlineNode> out,
    required _HtmlLinkContext? activeLink,
    required int depth,
    bool preserveWhitespace = false,
  }) {
    if (depth >= maxHtmlBlockDepth || !_canAddInline) {
      return;
    }
    if (node is _HtmlText) {
      final String collapsed = preserveWhitespace
          ? node.rawText
          : _collapseAsciiWhitespace(node.rawText);
      final String text = decodeHtmlEntities(collapsed);
      if (text.isEmpty) {
        return;
      }
      final TextNode textNode = TextNode(text);
      _inlineCount++;
      out.add(
        activeLink == null
            ? textNode
            : LinkNode(
                destination: activeLink.destination,
                title: activeLink.title,
                children: <MarkdownInlineNode>[textNode],
              ),
      );
      return;
    }

    if (node is! _HtmlElement) {
      return;
    }
    final String tag = node.tag;

    if (tag == 'br') {
      _inlineCount++;
      out.add(const InlineBreakNode());
      return;
    }

    if (tag == 'img') {
      final ImageNode? img = _parseImageElement(node);
      if (img != null) {
        _inlineCount++;
        out.add(
          activeLink == null
              ? img
              : LinkNode(
                  destination: activeLink.destination,
                  title: activeLink.title,
                  children: <MarkdownInlineNode>[img],
                ),
        );
      }
      return;
    }

    if (tag == 'picture') {
      final MarkdownInlineNode? pic = _parsePictureElement(node);
      if (pic != null) {
        _inlineCount++;
        out.add(
          activeLink == null
              ? pic
              : LinkNode(
                  destination: activeLink.destination,
                  title: activeLink.title,
                  children: <MarkdownInlineNode>[pic],
                ),
        );
      }
      return;
    }

    if (tag == 'code') {
      if (_containsOnlySimpleCodeChildren(node.children)) {
        final String codeText = _extractCodeLiteral(node.children);
        final CodeSpanNode span = CodeSpanNode(codeText);
        _inlineCount++;
        out.add(
          activeLink == null
              ? span
              : LinkNode(
                  destination: activeLink.destination,
                  title: activeLink.title,
                  children: <MarkdownInlineNode>[span],
                ),
        );
      } else {
        final List<MarkdownInlineNode> inner = <MarkdownInlineNode>[];
        for (final _HtmlNode child in node.children) {
          _appendInlineNode(
            child,
            out: inner,
            activeLink: activeLink,
            depth: depth + 1,
            preserveWhitespace: true,
          );
        }
        if (inner.isNotEmpty) {
          out
            ..add(const RawHtmlInlineNode('<code>'))
            ..addAll(inner)
            ..add(const RawHtmlInlineNode('</code>'));
          _inlineCount += 2;
        }
      }
      return;
    }

    if (tag == 'a') {
      final String? anchorId = _extractAnchorId(node.attrs);
      if (anchorId != null) {
        _inlineCount++;
        out.add(AnchorInlineNode(anchorId));
      }
      final _HtmlLinkContext? linkCtx =
          _extractLinkContext(node.attrs) ?? activeLink;
      final List<MarkdownInlineNode> inner = <MarkdownInlineNode>[];
      for (final _HtmlNode child in node.children) {
        _appendInlineNode(
          child,
          out: inner,
          activeLink: null,
          depth: depth + 1,
          preserveWhitespace: preserveWhitespace,
        );
      }
      if (inner.isEmpty) {
        return;
      }
      if (linkCtx != null) {
        _inlineCount++;
        out.add(
          LinkNode(
            destination: linkCtx.destination,
            title: linkCtx.title,
            children: inner,
          ),
        );
      } else {
        out.addAll(inner);
      }
      return;
    }

    final List<MarkdownInlineNode> children = <MarkdownInlineNode>[];
    for (final _HtmlNode child in node.children) {
      if (!_canAddInline) {
        break;
      }
      _appendInlineNode(
        child,
        out: children,
        activeLink: null,
        depth: depth + 1,
        preserveWhitespace: preserveWhitespace,
      );
    }

    if (tag == 'kbd') {
      final List<MarkdownInlineNode> normalized = _normalizeInlineList(
        children,
      );
      _inlineCount++;
      final KbdInlineNode kbd = KbdInlineNode(children: normalized);
      out.add(
        activeLink == null
            ? kbd
            : LinkNode(
                destination: activeLink.destination,
                title: activeLink.title,
                children: <MarkdownInlineNode>[kbd],
              ),
      );
      return;
    }

    if (tag == 'abbr') {
      final String title = (node.attrs['title'] ?? '').trim();
      final List<MarkdownInlineNode> normalized = _normalizeInlineList(
        children,
      );
      if (title.isNotEmpty) {
        _inlineCount++;
        final AbbrInlineNode abbr = AbbrInlineNode(
          title: title,
          children: normalized,
        );
        out.add(
          activeLink == null
              ? abbr
              : LinkNode(
                  destination: activeLink.destination,
                  title: activeLink.title,
                  children: <MarkdownInlineNode>[abbr],
                ),
        );
      } else {
        _wrapOrAddInlines(normalized, out: out, activeLink: activeLink);
      }
      return;
    }

    if (children.isEmpty) {
      final String? anchorId = _extractAnchorId(node.attrs);
      if (anchorId != null) {
        _inlineCount++;
        out.add(AnchorInlineNode(anchorId));
      }
      return;
    }

    switch (tag) {
      case 'strong':
      case 'b':
        _inlineCount++;
        final StrongNode strong = StrongNode(children: children);
        _wrapOrAddInline(strong, out: out, activeLink: activeLink);
      case 'em':
      case 'i':
      case 'cite':
      case 'dfn':
        _inlineCount++;
        final EmphasisNode em = EmphasisNode(children: children);
        _wrapOrAddInline(em, out: out, activeLink: activeLink);
      case 'del':
      case 's':
      case 'strike':
        _inlineCount++;
        final StrikethroughNode del = StrikethroughNode(children: children);
        _wrapOrAddInline(del, out: out, activeLink: activeLink);
      case 'mark':
        _inlineCount++;
        final HighlightNode mark = HighlightNode(children: children);
        _wrapOrAddInline(mark, out: out, activeLink: activeLink);
      case 'sub':
        _inlineCount++;
        final SubscriptNode sub = SubscriptNode(children: children);
        _wrapOrAddInline(sub, out: out, activeLink: activeLink);
      case 'sup':
        _inlineCount++;
        final SuperscriptNode sup = SuperscriptNode(children: children);
        _wrapOrAddInline(sup, out: out, activeLink: activeLink);
      case 'u':
      case 'ins':
        _emitRawTagPair(
          open: '<$tag>',
          close: '</$tag>',
          children: children,
          out: out,
          activeLink: activeLink,
        );
      case 'small':
        _emitRawTagPair(
          open: '<small>',
          close: '</small>',
          children: children,
          out: out,
          activeLink: activeLink,
        );
      case 'q':
        _emitRawTagPair(
          open: '<q>',
          close: '</q>',
          children: children,
          out: out,
          activeLink: activeLink,
        );
      case 'samp':
        _emitRawTagPair(
          open: '<samp>',
          close: '</samp>',
          children: children,
          out: out,
          activeLink: activeLink,
        );
      case 'var':
        _emitRawTagPair(
          open: '<var>',
          close: '</var>',
          children: children,
          out: out,
          activeLink: activeLink,
        );
      default:
        final String? anchorId = _extractAnchorId(node.attrs);
        if (anchorId != null) {
          _inlineCount++;
          out.add(AnchorInlineNode(anchorId));
        }
        _wrapOrAddInlines(children, out: out, activeLink: activeLink);
    }
  }

  void _wrapOrAddInline(
    MarkdownInlineNode node, {
    required List<MarkdownInlineNode> out,
    required _HtmlLinkContext? activeLink,
  }) {
    if (activeLink == null) {
      out.add(node);
    } else {
      out.add(
        LinkNode(
          destination: activeLink.destination,
          title: activeLink.title,
          children: <MarkdownInlineNode>[node],
        ),
      );
    }
  }

  void _wrapOrAddInlines(
    List<MarkdownInlineNode> nodes, {
    required List<MarkdownInlineNode> out,
    required _HtmlLinkContext? activeLink,
  }) {
    if (activeLink == null) {
      out.addAll(nodes);
    } else {
      out.add(
        LinkNode(
          destination: activeLink.destination,
          title: activeLink.title,
          children: nodes,
        ),
      );
    }
  }

  void _emitRawTagPair({
    required String open,
    required String close,
    required List<MarkdownInlineNode> children,
    required List<MarkdownInlineNode> out,
    required _HtmlLinkContext? activeLink,
  }) {
    _inlineCount += 2;
    final List<MarkdownInlineNode> wrapped = <MarkdownInlineNode>[
      RawHtmlInlineNode(open),
      ...children,
      RawHtmlInlineNode(close),
    ];
    _wrapOrAddInlines(wrapped, out: out, activeLink: activeLink);
  }

  _HtmlLinkContext? _extractLinkContext(Map<String, String> attrs) {
    final String? rawHref = attrs['href'];
    if (rawHref == null) {
      return null;
    }
    final String href = rawHref.trim();
    if (href.isEmpty) {
      return null;
    }
    final bool allowed = urlPolicy == null || urlPolicy!.isAllowed(href);
    return _HtmlLinkContext(
      destination: allowed ? href : '',
      title: _nonEmptyOrNull(attrs['title']),
    );
  }
}

bool _isBlockElement(_HtmlElement elem) {
  switch (elem.tag) {
    case 'address':
    case 'article':
    case 'aside':
    case 'blockquote':
    case 'center':
    case 'details':
    case 'div':
    case 'dl':
    case 'fieldset':
    case 'figure':
    case 'footer':
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
    case 'header':
    case 'hr':
    case 'main':
    case 'nav':
    case 'ol':
    case 'p':
    case 'pre':
    case 'section':
    case 'table':
    case 'ul':
      return true;
    case 'a':
      return elem.children.any(
        (_HtmlNode child) => child is _HtmlElement && _isBlockElement(child),
      );
    default:
      return false;
  }
}

TableAlignment _extractAlignment(Map<String, String> attrs) {
  final String? alignAttr = attrs['align'];
  if (alignAttr != null) {
    final TableAlignment parsed = _parseAlignmentKeyword(alignAttr);
    if (parsed != TableAlignment.none) {
      return parsed;
    }
  }
  final String? styleAttr = attrs['style'];
  if (styleAttr != null && styleAttr.isNotEmpty) {
    final TableAlignment parsed = _parseTextAlignFromStyle(styleAttr);
    if (parsed != TableAlignment.none) {
      return parsed;
    }
  }
  return TableAlignment.none;
}

TableAlignment _parseAlignmentKeyword(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'center':
      return TableAlignment.center;
    case 'right':
    case 'end':
      return TableAlignment.right;
    case 'left':
    case 'start':
      return TableAlignment.left;
    default:
      return TableAlignment.none;
  }
}

TableAlignment _parseTextAlignFromStyle(String style) {
  int start = 0;
  final int len = style.length;
  while (start < len) {
    int end = style.indexOf(';', start);
    if (end == -1) {
      end = len;
    }
    final int colon = style.indexOf(':', start);
    if (colon != -1 && colon < end) {
      final String prop = style.substring(start, colon).trim().toLowerCase();
      if (prop == 'text-align') {
        String val = style.substring(colon + 1, end).trim().toLowerCase();
        if (val.endsWith('!important')) {
          val = val.substring(0, val.length - 10).trim();
        }
        final TableAlignment parsed = _parseAlignmentKeyword(val);
        if (parsed != TableAlignment.none) {
          return parsed;
        }
      }
    }
    start = end + 1;
  }
  return TableAlignment.none;
}

int _parseColspan(String? raw, {required int remainingCols}) {
  if (raw == null || raw.isEmpty) {
    return 1;
  }
  final int? parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed <= 1) {
    return 1;
  }
  final int bounded = parsed > maxHtmlColspan ? maxHtmlColspan : parsed;
  return bounded > remainingCols ? remainingCols : bounded;
}

String? _extractAnchorId(Map<String, String> attrs) =>
    _nonEmptyOrNull(attrs['id']) ?? _nonEmptyOrNull(attrs['name']);

String? _nonEmptyOrNull(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _parseHtmlDimension(String? raw) {
  if (raw == null) {
    return null;
  }
  String s = raw.trim().toLowerCase();
  if (s.endsWith('px')) {
    s = s.substring(0, s.length - 2).trim();
  }
  final int? parsed = int.tryParse(s);
  if (parsed == null || parsed <= 0) {
    return null;
  }
  return parsed;
}

ImageNode? _parseImageElement(_HtmlElement img) {
  final String src = (img.attrs['src'] ?? '').trim();
  if (src.isEmpty) {
    return null;
  }
  return ImageNode(
    destination: src,
    alt: img.attrs['alt'] ?? '',
    title: img.attrs['title'],
    width: _parseHtmlDimension(img.attrs['width']),
    height: _parseHtmlDimension(img.attrs['height']),
  );
}

MarkdownInlineNode? _parsePictureElement(_HtmlElement picture) {
  String darkSource = '';
  String lightFallback = '';
  ImageNode? fallbackImg;

  for (final _HtmlNode child in picture.children) {
    if (child is! _HtmlElement) {
      continue;
    }
    if (child.tag == 'source') {
      final String media = (child.attrs['media'] ?? '').toLowerCase();
      final String candidate = _extractFirstSrcsetUrl(
        child.attrs['srcset'] ?? '',
      );
      if (candidate.isEmpty) {
        continue;
      }
      if (_mediaTargetsColorScheme(media, 'dark') && darkSource.isEmpty) {
        darkSource = candidate;
      } else if (_mediaTargetsColorScheme(media, 'light') &&
          lightFallback.isEmpty) {
        lightFallback = candidate;
      }
    } else if (child.tag == 'img' && fallbackImg == null) {
      fallbackImg = _parseImageElement(child);
    }
  }

  final String lightSource = fallbackImg?.destination ?? lightFallback;
  if (darkSource.isNotEmpty) {
    final String effectiveLight = lightSource.isNotEmpty
        ? lightSource
        : darkSource;
    return PictureInlineNode(
      lightSource: effectiveLight,
      darkSource: darkSource,
      alt: fallbackImg?.alt ?? '',
    );
  }
  return fallbackImg;
}

bool _mediaTargetsColorScheme(String mediaLower, String scheme) {
  final int idx = mediaLower.indexOf('prefers-color-scheme');
  if (idx == -1) {
    return false;
  }
  final int colon = mediaLower.indexOf(':', idx);
  if (colon == -1) {
    return false;
  }
  int p = colon + 1;
  while (p < mediaLower.length &&
      _isAsciiWhitespace(mediaLower.codeUnitAt(p))) {
    p++;
  }
  return mediaLower.startsWith(scheme, p);
}

String _extractFirstSrcsetUrl(String srcset) {
  final String trimmed = srcset.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (_matchesAsciiIgnoreCase(trimmed, 0, 'data:')) {
    for (int i = 0; i < trimmed.length; i++) {
      if (_isAsciiWhitespace(trimmed.codeUnitAt(i))) {
        return trimmed.substring(0, i);
      }
    }
    return trimmed;
  }
  final int comma = trimmed.indexOf(',');
  final String firstEntry = comma == -1
      ? trimmed
      : trimmed.substring(0, comma).trim();
  for (int i = 0; i < firstEntry.length; i++) {
    if (_isAsciiWhitespace(firstEntry.codeUnitAt(i))) {
      return firstEntry.substring(0, i);
    }
  }
  return firstEntry;
}

String? _extractPreLanguage(_HtmlElement preElem) {
  final String? onPre = _extractLanguageClass(preElem.attrs['class']);
  if (onPre != null) {
    return onPre;
  }
  for (final _HtmlNode child in preElem.children) {
    if (child is _HtmlElement && child.tag == 'code') {
      final String? onCode = _extractLanguageClass(child.attrs['class']);
      if (onCode != null) {
        return onCode;
      }
    }
  }
  return null;
}

String? _extractLanguageClass(String? classAttr) {
  if (classAttr == null || classAttr.trim().isEmpty) {
    return null;
  }
  int start = 0;
  final int len = classAttr.length;
  while (start < len) {
    while (start < len && _isAsciiWhitespace(classAttr.codeUnitAt(start))) {
      start++;
    }
    if (start >= len) {
      break;
    }
    int end = start;
    while (end < len && !_isAsciiWhitespace(classAttr.codeUnitAt(end))) {
      end++;
    }
    final String token = classAttr.substring(start, end);
    final String lower = token.toLowerCase();
    if (lower.startsWith('language-') && token.length > 9) {
      return token.substring(9);
    }
    if (lower.startsWith('lang-') && token.length > 5) {
      return token.substring(5);
    }
    start = end + 1;
  }
  return null;
}

String _extractVerbatimPreText(_HtmlElement preElem) {
  final StringBuffer out = StringBuffer();

  void walk(List<_HtmlNode> nodes, int depth) {
    if (depth >= maxHtmlBlockDepth) {
      return;
    }
    for (final _HtmlNode node in nodes) {
      if (node is _HtmlText) {
        out.write(decodeHtmlEntities(node.rawText));
      } else if (node is _HtmlElement) {
        if (node.tag == 'br') {
          out.write('\n');
        } else {
          walk(node.children, depth + 1);
        }
      }
    }
  }

  walk(preElem.children, 0);
  return out.toString();
}

bool _containsOnlySimpleCodeChildren(List<_HtmlNode> nodes) {
  for (final _HtmlNode node in nodes) {
    if (node is _HtmlElement) {
      if (node.tag == 'br') {
        continue;
      }
      return false;
    }
  }
  return true;
}

String _extractCodeLiteral(List<_HtmlNode> nodes) {
  final StringBuffer out = StringBuffer();
  for (final _HtmlNode node in nodes) {
    if (node is _HtmlText) {
      out.write(decodeHtmlEntities(node.rawText));
    } else if (node is _HtmlElement && node.tag == 'br') {
      out.write('\n');
    }
  }
  return out.toString();
}

bool _isAllAsciiWhitespace(String input) {
  for (int i = 0; i < input.length; i++) {
    if (!_isAsciiWhitespace(input.codeUnitAt(i))) {
      return false;
    }
  }
  return true;
}

String _collapseAsciiWhitespace(String input) {
  StringBuffer? out;
  int last = 0;
  int i = 0;
  final int len = input.length;

  while (i < len) {
    final int cu = input.codeUnitAt(i);
    if (!_isAsciiWhitespace(cu)) {
      i++;
      continue;
    }
    int end = i + 1;
    while (end < len && _isAsciiWhitespace(input.codeUnitAt(end))) {
      end++;
    }
    if (end - i > 1 || cu != 0x20) {
      out ??= StringBuffer();
      if (i > last) {
        out.write(input.substring(last, i));
      }
      out.writeCharCode(0x20);
      last = end;
    }
    i = end;
  }

  if (out == null) {
    return input;
  }
  if (last < len) {
    out.write(input.substring(last));
  }
  return out.toString();
}

List<MarkdownInlineNode> _normalizeInlineList(List<MarkdownInlineNode> raw) {
  if (raw.isEmpty) {
    return const <MarkdownInlineNode>[];
  }
  final _InlineSpaceNormalizer normalizer = _InlineSpaceNormalizer();
  final List<MarkdownInlineNode> pass1 = normalizer.normalizeList(raw);
  return _trimTrailingSpaces(pass1);
}

final class _InlineSpaceNormalizer {
  bool atStartOrAfterSpace = true;

  List<MarkdownInlineNode> normalizeList(List<MarkdownInlineNode> nodes) {
    final List<MarkdownInlineNode> out = <MarkdownInlineNode>[];
    for (final MarkdownInlineNode node in nodes) {
      final MarkdownInlineNode? normalized = _normalizeNode(node);
      if (normalized == null) {
        continue;
      }
      if (normalized is InlineBreakNode || normalized is HardBreakNode) {
        final List<MarkdownInlineNode> trimmed = _trimTrailingSpaces(out);
        out
          ..clear()
          ..addAll(trimmed)
          ..add(normalized);
        continue;
      }
      if (normalized is RawHtmlInlineNode &&
          normalized.html.startsWith('</') &&
          out.isNotEmpty &&
          out.last is RawHtmlInlineNode &&
          (out.last as RawHtmlInlineNode).html ==
              '<${normalized.html.substring(2)}') {
        out.removeLast();
        continue;
      }
      if (normalized is TextNode && out.isNotEmpty && out.last is TextNode) {
        final TextNode prev = out.last as TextNode;
        out[out.length - 1] = TextNode(prev.text + normalized.text);
      } else {
        out.add(normalized);
      }
    }
    return out;
  }

  MarkdownInlineNode? _normalizeNode(MarkdownInlineNode node) {
    switch (node) {
      case TextNode():
        String s = node.text;
        if (atStartOrAfterSpace && s.startsWith(' ')) {
          s = s.substring(1);
        }
        if (s.isEmpty) {
          return null;
        }
        atStartOrAfterSpace = s.endsWith(' ');
        return TextNode(s);
      case InlineBreakNode():
      case HardBreakNode():
        atStartOrAfterSpace = true;
        return node;
      case SoftBreakNode():
        if (atStartOrAfterSpace) {
          return null;
        }
        atStartOrAfterSpace = true;
        return const TextNode(' ');
      case CodeSpanNode():
      case ImageNode():
      case PictureInlineNode():
      case MathInlineNode():
      case FootnoteRefNode():
      case KbdInlineNode():
      case AbbrInlineNode():
        atStartOrAfterSpace = false;
        return node;
      case AnchorInlineNode():
        return node;
      case RawHtmlInlineNode():
        if (node.html == '<q>') {
          atStartOrAfterSpace = true;
        } else if (node.html == '</q>') {
          atStartOrAfterSpace = false;
        }
        return node;
      case StrongNode():
        final List<MarkdownInlineNode> children = normalizeList(node.children);
        return children.isEmpty ? null : StrongNode(children: children);
      case EmphasisNode():
        final List<MarkdownInlineNode> children = normalizeList(node.children);
        return children.isEmpty ? null : EmphasisNode(children: children);
      case StrikethroughNode():
        final List<MarkdownInlineNode> children = normalizeList(node.children);
        return children.isEmpty ? null : StrikethroughNode(children: children);
      case HighlightNode():
        final List<MarkdownInlineNode> children = normalizeList(node.children);
        return children.isEmpty ? null : HighlightNode(children: children);
      case SubscriptNode():
        final List<MarkdownInlineNode> children = normalizeList(node.children);
        return children.isEmpty ? null : SubscriptNode(children: children);
      case SuperscriptNode():
        final List<MarkdownInlineNode> children = normalizeList(node.children);
        return children.isEmpty ? null : SuperscriptNode(children: children);
      case LinkNode():
        final List<MarkdownInlineNode> children = normalizeList(node.children);
        return children.isEmpty
            ? null
            : LinkNode(
                destination: node.destination,
                title: node.title,
                children: children,
              );
    }
  }
}

List<MarkdownInlineNode> _trimTrailingSpaces(List<MarkdownInlineNode> nodes) {
  if (nodes.isEmpty) {
    return const <MarkdownInlineNode>[];
  }
  final List<MarkdownInlineNode> copy = List<MarkdownInlineNode>.of(nodes);
  while (copy.isNotEmpty) {
    final MarkdownInlineNode last = copy.last;
    if (last is TextNode) {
      final String trimmed = last.text.endsWith(' ')
          ? last.text.substring(0, last.text.length - 1)
          : last.text;
      if (trimmed.isEmpty) {
        copy.removeLast();
        continue;
      }
      copy[copy.length - 1] = TextNode(trimmed);
      break;
    }
    if (last is StrongNode) {
      final List<MarkdownInlineNode> inner = _trimTrailingSpaces(last.children);
      if (inner.isEmpty) {
        copy.removeLast();
        continue;
      }
      copy[copy.length - 1] = StrongNode(children: inner);
      break;
    }
    if (last is EmphasisNode) {
      final List<MarkdownInlineNode> inner = _trimTrailingSpaces(last.children);
      if (inner.isEmpty) {
        copy.removeLast();
        continue;
      }
      copy[copy.length - 1] = EmphasisNode(children: inner);
      break;
    }
    if (last is StrikethroughNode) {
      final List<MarkdownInlineNode> inner = _trimTrailingSpaces(last.children);
      if (inner.isEmpty) {
        copy.removeLast();
        continue;
      }
      copy[copy.length - 1] = StrikethroughNode(children: inner);
      break;
    }
    if (last is HighlightNode) {
      final List<MarkdownInlineNode> inner = _trimTrailingSpaces(last.children);
      if (inner.isEmpty) {
        copy.removeLast();
        continue;
      }
      copy[copy.length - 1] = HighlightNode(children: inner);
      break;
    }
    if (last is SubscriptNode) {
      final List<MarkdownInlineNode> inner = _trimTrailingSpaces(last.children);
      if (inner.isEmpty) {
        copy.removeLast();
        continue;
      }
      copy[copy.length - 1] = SubscriptNode(children: inner);
      break;
    }
    if (last is SuperscriptNode) {
      final List<MarkdownInlineNode> inner = _trimTrailingSpaces(last.children);
      if (inner.isEmpty) {
        copy.removeLast();
        continue;
      }
      copy[copy.length - 1] = SuperscriptNode(children: inner);
      break;
    }
    if (last is LinkNode) {
      final List<MarkdownInlineNode> inner = _trimTrailingSpaces(last.children);
      if (inner.isEmpty) {
        copy.removeLast();
        continue;
      }
      copy[copy.length - 1] = LinkNode(
        destination: last.destination,
        title: last.title,
        children: inner,
      );
      break;
    }
    if (last is RawHtmlInlineNode && last.html != '</q>') {
      // Trim trailing space inside transparent wrapper tags (e.g. `<u>hi </u>`),
      // but keep the raw tag token itself.
      if (copy.length >= 2) {
        final List<MarkdownInlineNode> prefix = _trimTrailingSpaces(
          copy.sublist(0, copy.length - 1),
        );
        if (prefix.isEmpty) {
          return const <MarkdownInlineNode>[];
        }
        return <MarkdownInlineNode>[...prefix, last];
      }
    }
    break;
  }
  return copy;
}
