import 'package:meta/meta.dart';

import 'entities.dart';
import 'unicode.dart';
import 'url_utils.dart';

/// Policy governing allowed and blocked URI schemes and hosts for links and
/// images when URL sanitization is enabled.
@immutable
final class MarkdownUrlPolicy {
  /// Creates a [MarkdownUrlPolicy].
  const MarkdownUrlPolicy({
    this.blockedSchemes = defaultBlockedSchemes,
    this.allowedSchemes,
    this.allowedHosts,
    this.allowRelative = true,
    this.allowFragments = true,
    this.allowSafeImageDataUrls = false,
    this.allowProtocolRelative = false,
    this.allowUserInfo = false,
  });

  /// Creates a strict allowlist [MarkdownUrlPolicy] permitting only `http`,
  /// `https`, and `mailto` schemes (plus relative/fragment URLs when enabled),
  /// while rejecting protocol-relative (`//`) and userinfo (`@`) authority URLs.
  const MarkdownUrlPolicy.strict({
    this.allowedSchemes = defaultStrictSchemes,
    this.blockedSchemes = defaultBlockedSchemes,
    this.allowedHosts,
    this.allowRelative = true,
    this.allowFragments = true,
    this.allowSafeImageDataUrls = false,
    this.allowProtocolRelative = false,
    this.allowUserInfo = false,
  });

  /// Default blocked URI schemes (`javascript`, `vbscript`, `data`).
  static const Set<String> defaultBlockedSchemes = <String>{
    'javascript',
    'vbscript',
    'data',
  };

  /// Strict default allowlisted URI schemes (`http`, `https`, `mailto`).
  static const Set<String> defaultStrictSchemes = <String>{
    'http',
    'https',
    'mailto',
  };

  /// Schemes explicitly rejected (matched lowercase after stripping control and
  /// whitespace characters).
  final Set<String> blockedSchemes;

  /// Optional allowlist of schemes. When non-null, only these schemes (plus
  /// relative/fragment URLs if enabled) are permitted.
  final Set<String>? allowedSchemes;

  /// Optional allowlist of hosts for URLs containing an authority (`//host`).
  final Set<String>? allowedHosts;

  /// Whether relative paths without an explicit scheme are allowed.
  final bool allowRelative;

  /// Whether `#fragment` links are allowed.
  final bool allowFragments;

  /// Whether non-SVG raster image `data:` URLs (`png`, `jpeg`, `jpg`, `gif`,
  /// `webp`) are allowed even when `data` is in [blockedSchemes].
  final bool allowSafeImageDataUrls;

  /// Whether protocol-relative authority URLs (`//host/path`) are allowed.
  final bool allowProtocolRelative;

  /// Whether authority userinfo (`user:pass@host`) is allowed.
  final bool allowUserInfo;

  static final RegExp _safeImageDataPattern = RegExp(
    r'^data:image/(?:png|jpe?g|gif|webp);base64,[A-Za-z0-9+/=]+$',
    caseSensitive: false,
  );

  /// Returns whether [url] is permitted by this policy.
  bool isAllowed(String url) {
    final String cleaned = stripControlAndWhitespaceForUrl(url);
    if (cleaned.isEmpty) {
      return allowRelative;
    }
    if (cleaned.startsWith('#')) {
      return allowFragments;
    }

    final String? scheme = _extractScheme(cleaned);
    if (scheme == null) {
      if (!allowRelative) {
        return false;
      }
      if (_startsWithAuthorityPrefix(cleaned)) {
        if (!allowProtocolRelative) {
          return false;
        }
        final String authorityAndRest = cleaned.substring(2);
        if (!allowUserInfo && _authorityHasUserInfo(authorityAndRest)) {
          return false;
        }
        if (allowedHosts != null) {
          return _isAllowedHost(authorityAndRest);
        }
        return true;
      }
      return true;
    }

    if (scheme == 'data' &&
        allowSafeImageDataUrls &&
        _safeImageDataPattern.hasMatch(cleaned)) {
      return true;
    }

    if (allowedSchemes != null) {
      bool found = false;
      for (final String allowed in allowedSchemes!) {
        if (allowed.toLowerCase() == scheme) {
          found = true;
          break;
        }
      }
      if (!found) {
        return false;
      }
    } else {
      for (final String blocked in blockedSchemes) {
        if (blocked.toLowerCase() == scheme) {
          return false;
        }
      }
    }

    final int colonIndex = cleaned.indexOf(':');
    final String afterScheme = cleaned.substring(colonIndex + 1);
    if (afterScheme.isNotEmpty) {
      final int c0 = afterScheme.codeUnitAt(0);
      // Reject backslash authority differentials such as `https:\\evil` or
      // `https:/\evil` which browsers normalize to `https://evil`.
      if (c0 == 0x5C ||
          (c0 == 0x2F &&
              afterScheme.length > 1 &&
              afterScheme.codeUnitAt(1) == 0x5C)) {
        return false;
      }
      if (afterScheme.startsWith('//')) {
        final String authorityAndRest = afterScheme.substring(2);
        if (!allowUserInfo && _authorityHasUserInfo(authorityAndRest)) {
          return false;
        }
        if (allowedHosts != null) {
          return _isAllowedHost(authorityAndRest);
        }
      }
    }
    return true;
  }

  /// Returns [url] if permitted by this policy, or [fallback] otherwise.
  String sanitize(String url, {String fallback = ''}) {
    return isAllowed(url) ? url : fallback;
  }

  bool _authorityHasUserInfo(String authorityAndRest) {
    for (int i = 0; i < authorityAndRest.length; i++) {
      final int cu = authorityAndRest.codeUnitAt(i);
      if (cu == 0x40) {
        return true;
      }
      if (cu == 0x2F || cu == 0x5C || cu == 0x3F || cu == 0x23) {
        return false;
      }
    }
    return false;
  }

  bool _isAllowedHost(String authorityAndRest) {
    final Set<String>? hosts = allowedHosts;
    if (hosts == null) {
      return true;
    }
    int end = authorityAndRest.length;
    for (int i = 0; i < authorityAndRest.length; i++) {
      final int cu = authorityAndRest.codeUnitAt(i);
      if (cu == 0x2F || cu == 0x5C || cu == 0x3F || cu == 0x23) {
        end = i;
        break;
      }
    }
    String authority = authorityAndRest.substring(0, end);
    final int atIndex = authority.lastIndexOf('@');
    if (atIndex >= 0) {
      if (!allowUserInfo) {
        return false;
      }
      authority = authority.substring(atIndex + 1);
    }
    if (authority.startsWith('[')) {
      final int closeBracket = authority.indexOf(']');
      if (closeBracket > 0) {
        authority = authority.substring(0, closeBracket + 1);
      }
    } else {
      final int portColon = authority.indexOf(':');
      if (portColon >= 0) {
        authority = authority.substring(0, portColon);
      }
    }
    if (authority.isEmpty) {
      return false;
    }
    final String normalizedHost = authority.toLowerCase();
    for (final String allowed in hosts) {
      if (allowed.toLowerCase() == normalizedHost) {
        return true;
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownUrlPolicy &&
          _normalizedSetEquals(blockedSchemes, other.blockedSchemes) &&
          _nullableNormalizedSetEquals(allowedSchemes, other.allowedSchemes) &&
          _nullableNormalizedSetEquals(allowedHosts, other.allowedHosts) &&
          allowRelative == other.allowRelative &&
          allowFragments == other.allowFragments &&
          allowSafeImageDataUrls == other.allowSafeImageDataUrls &&
          allowProtocolRelative == other.allowProtocolRelative &&
          allowUserInfo == other.allowUserInfo;

  @override
  int get hashCode => Object.hash(
    _normalizedSetHash(blockedSchemes),
    allowedSchemes == null ? null : _normalizedSetHash(allowedSchemes!),
    allowedHosts == null ? null : _normalizedSetHash(allowedHosts!),
    allowRelative,
    allowFragments,
    allowSafeImageDataUrls,
    allowProtocolRelative,
    allowUserInfo,
  );
}

/// Strips ASCII/Unicode control, whitespace, and invisible zero-width/bidi
/// format characters from [input] prior to URI scheme/authority inspection.
String stripControlAndWhitespaceForUrl(String input) {
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
  if ((cu >= 0x80 && cu <= 0x9F) ||
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
      cu == 0xFEFF) {
    return true;
  }
  return false;
}

bool _startsWithAuthorityPrefix(String cleaned) {
  if (cleaned.length < 2) {
    return false;
  }
  final int c0 = cleaned.codeUnitAt(0);
  final int c1 = cleaned.codeUnitAt(1);
  return (c0 == 0x2F || c0 == 0x5C) && (c1 == 0x2F || c1 == 0x5C);
}

String? _extractScheme(String cleaned) {
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

bool _isAsciiAlnum(int cu) => _isAsciiAlpha(cu) || (cu >= 0x30 && cu <= 0x39);

bool _normalizedSetEquals(Set<String> a, Set<String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.isEmpty && b.isEmpty) {
    return true;
  }
  final Set<String> normA = a.map((String e) => e.toLowerCase()).toSet();
  final Set<String> normB = b.map((String e) => e.toLowerCase()).toSet();
  if (normA.length != normB.length) {
    return false;
  }
  return normA.containsAll(normB);
}

bool _nullableNormalizedSetEquals(Set<String>? a, Set<String>? b) {
  if (a == null && b == null) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  return _normalizedSetEquals(a, b);
}

int _normalizedSetHash(Set<String> set) {
  return Object.hashAllUnordered(set.map((String e) => e.toLowerCase()));
}

final RegExp _gfmTagFilterPattern = RegExp(
  r'<(?=(?:title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)(?:[\x00-\x20/>]|$))',
  caseSensitive: false,
);

/// Escapes GFM disallowed raw HTML opening tags (`<script`, `<style`, `<iframe`,
/// etc.) by replacing the leading `<` with `&lt;`.
String applyGfmTagFilter(String html) {
  if (!html.contains('<')) {
    return html;
  }
  return html.replaceAll(_gfmTagFilterPattern, '&lt;');
}

/// Decodes HTML5 named character references and semicolon-optional numeric
/// character references inside HTML attribute values.
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
    final ({String text, int nextIndex})? standard = decodeCharacterReference(
      input,
      i,
    );
    if (standard != null) {
      out ??= StringBuffer();
      if (i > last) {
        out.write(input.substring(last, i));
      }
      out.write(standard.text);
      i = standard.nextIndex;
      last = i;
      continue;
    }
    // HTML5 semicolon-less numeric character references (`&#106`, `&#x6a`).
    if (i + 2 < len && input.codeUnitAt(i + 1) == 0x23) {
      final int marker = input.codeUnitAt(i + 2);
      if (marker == 0x78 || marker == 0x58) {
        int j = i + 3;
        int digits = 0;
        int value = 0;
        while (j < len && digits < 7) {
          final int hex = _hexVal(input.codeUnitAt(j));
          if (hex < 0) {
            break;
          }
          value = (value << 4) | hex;
          digits++;
          j++;
        }
        if (digits >= 1) {
          out ??= StringBuffer();
          if (i > last) {
            out.write(input.substring(last, i));
          }
          final int cp = (value == 0 || value > 0x10FFFF) ? 0xFFFD : value;
          out.writeCharCode(cp);
          if (j < len && input.codeUnitAt(j) == 0x3B) {
            j++;
          }
          i = j;
          last = i;
          continue;
        }
      } else if (marker >= 0x30 && marker <= 0x39) {
        int j = i + 2;
        int digits = 0;
        int value = 0;
        while (j < len && digits < 8) {
          final int cu = input.codeUnitAt(j);
          if (cu < 0x30 || cu > 0x39) {
            break;
          }
          value = value * 10 + (cu - 0x30);
          digits++;
          j++;
        }
        if (digits >= 1) {
          out ??= StringBuffer();
          if (i > last) {
            out.write(input.substring(last, i));
          }
          final int cp = (value == 0 || value > 0x10FFFF) ? 0xFFFD : value;
          out.writeCharCode(cp);
          if (j < len && input.codeUnitAt(j) == 0x3B) {
            j++;
          }
          i = j;
          last = i;
          continue;
        }
      }
    }
    i++;
  }
  if (out == null) {
    return input;
  }
  if (last < len) {
    out.write(input.substring(last));
  }
  return out.toString();
}

int _hexVal(int cu) {
  if (cu >= 0x30 && cu <= 0x39) {
    return cu - 0x30;
  }
  if (cu >= 0x41 && cu <= 0x46) {
    return cu - 0x41 + 10;
  }
  if (cu >= 0x61 && cu <= 0x66) {
    return cu - 0x61 + 10;
  }
  return -1;
}

const Set<String> _allowedHtmlTags = <String>{
  'a',
  'abbr',
  'acronym',
  'address',
  'article',
  'aside',
  'b',
  'bdi',
  'bdo',
  'big',
  'blockquote',
  'br',
  'caption',
  'center',
  'cite',
  'code',
  'col',
  'colgroup',
  'data',
  'dd',
  'del',
  'details',
  'dfn',
  'dir',
  'div',
  'dl',
  'dt',
  'em',
  'figcaption',
  'figure',
  'font',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hgroup',
  'hr',
  'i',
  'img',
  'ins',
  'kbd',
  'li',
  'main',
  'mark',
  'menu',
  'nav',
  'ol',
  'p',
  'picture',
  'pre',
  'q',
  'rp',
  'rt',
  'ruby',
  's',
  'samp',
  'search',
  'section',
  'small',
  'source',
  'span',
  'strike',
  'strong',
  'sub',
  'summary',
  'sup',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'time',
  'tr',
  'tt',
  'u',
  'ul',
  'var',
  'wbr',
};

const Set<String> _rawTextSubtreeStripElements = <String>{
  'script',
  'style',
  'iframe',
  'noembed',
  'noframes',
  'noscript',
  'title',
  'textarea',
  'xmp',
};

const Set<String> _containerSubtreeStripElements = <String>{
  'svg',
  'math',
  'template',
  'object',
  'applet',
  'form',
  'frameset',
};

const Set<String> _singleUrlAttributes = <String>{
  'href',
  'src',
  'background',
  'cite',
  'longdesc',
  'poster',
  'action',
  'formaction',
  'xlink:href',
};

const Set<String> _blockedAttributes = <String>{
  'srcdoc',
  'http-equiv',
  'formaction',
  'dynsrc',
  'lowsrc',
  'xmlns',
};

/// Sanitizes raw HTML strings in linear time using an HTML5-style state-machine
/// tokenizer and strict allowlist, stripping unsafe elements/subtrees
/// (`<script>`, `<style>`, `<iframe>`, `<object>`, `<embed>`, `<svg>`, `<math>`,
/// `<noscript>`, `<template>`, `<form>`, `<meta>`, etc.), `on*` event handlers,
/// `srcdoc`, unsafe CSS `url(...)`/`expression(...)`, and disallowed URI
/// attributes according to [urlPolicy].
String sanitizeRawHtml(String html, MarkdownUrlPolicy urlPolicy) {
  if (html.isEmpty || !html.contains('<')) {
    return html;
  }

  final StringBuffer out = StringBuffer();
  final int len = html.length;
  int i = 0;

  while (i < len) {
    final int lt = html.indexOf('<', i);
    if (lt == -1) {
      out.write(html.substring(i));
      break;
    }
    if (lt > i) {
      out.write(html.substring(i, lt));
    }

    if (lt + 1 >= len) {
      out.write('&lt;');
      break;
    }

    final int nextCu = html.codeUnitAt(lt + 1);

    // 1. HTML comments `<!-- ... -->` (plus short `<!-->`, `<!--->`) and
    // declarations `<!...>`.
    if (nextCu == 0x21) {
      if (html.startsWith('<!--', lt)) {
        if (html.startsWith('<!-->', lt)) {
          i = lt + 5;
          continue;
        }
        if (html.startsWith('<!--->', lt)) {
          i = lt + 6;
          continue;
        }
        final int end = html.indexOf('-->', lt + 4);
        if (end == -1) {
          i = len;
        } else {
          i = end + 3;
        }
        continue;
      }
      if (html.startsWith('<![CDATA[', lt)) {
        final int end = html.indexOf(']]>', lt + 9);
        i = end == -1 ? len : end + 3;
        continue;
      }
      final int end = html.indexOf('>', lt + 2);
      i = end == -1 ? len : end + 1;
      continue;
    }

    // 2. Processing instructions `<? ... ?>`.
    if (nextCu == 0x3F) {
      final int end = html.indexOf('?>', lt + 2);
      i = end == -1 ? len : end + 2;
      continue;
    }

    // 3. Closing tag `</tagname ...>`.
    if (nextCu == 0x2F) {
      if (lt + 2 >= len || !_isAsciiAlpha(html.codeUnitAt(lt + 2))) {
        out.write('&lt;');
        i = lt + 1;
        continue;
      }
      int pos = lt + 2;
      while (pos < len && _isTagNameChar(html.codeUnitAt(pos))) {
        pos++;
      }
      final String lowerTag = html.substring(lt + 2, pos).toLowerCase();
      final _ParsedTagTail? tail = _scanTagAttributesToClose(
        html,
        pos,
        collectAttrs: false,
      );
      if (tail == null) {
        // Unclosed tag at EOF: drop safely in O(1) without rescanning.
        i = len;
        continue;
      }
      if (_allowedHtmlTags.contains(lowerTag)) {
        out
          ..write('</')
          ..write(lowerTag)
          ..write('>');
      }
      i = tail.nextIndex;
      continue;
    }

    // 4. Opening tag `<tagname ...>`.
    if (!_isAsciiAlpha(nextCu)) {
      out.write('&lt;');
      i = lt + 1;
      continue;
    }

    int pos = lt + 1;
    while (pos < len && _isTagNameChar(html.codeUnitAt(pos))) {
      pos++;
    }
    final String lowerTag = html.substring(lt + 1, pos).toLowerCase();
    final bool isAllowedTag = _allowedHtmlTags.contains(lowerTag);
    final _ParsedTagTail? tail = _scanTagAttributesToClose(
      html,
      pos,
      collectAttrs: isAllowedTag,
    );
    if (tail == null) {
      // Unclosed tag at EOF: drop safely.
      i = len;
      continue;
    }
    i = tail.nextIndex;

    if (lowerTag == 'plaintext') {
      // `<plaintext>` consumes everything until EOF.
      i = len;
      continue;
    }
    if (_rawTextSubtreeStripElements.contains(lowerTag)) {
      i = _skipUntilRawTextClose(html, i, lowerTag);
      continue;
    }
    if (_containerSubtreeStripElements.contains(lowerTag)) {
      if (!(tail.selfClosing && (lowerTag == 'svg' || lowerTag == 'math'))) {
        i = _skipUntilContainerClose(html, i, lowerTag);
      }
      continue;
    }
    if (!isAllowedTag) {
      // Strip non-allowlisted tags (e.g. <meta>, <base>, <link>, <embed>).
      continue;
    }

    out
      ..write('<')
      ..write(lowerTag);

    if (tail.attrs.isNotEmpty) {
      final Set<String> seenAttrs = <String>{};
      for (final _RawHtmlAttr attr in tail.attrs) {
        final String lowerName = attr.name.toLowerCase();
        if (!seenAttrs.add(lowerName)) {
          continue;
        }
        if (lowerName.startsWith('on') ||
            _blockedAttributes.contains(lowerName)) {
          continue;
        }
        if (!_isSafeAttrName(lowerName)) {
          continue;
        }
        final String? rawValue = attr.value;
        if (rawValue == null) {
          out
            ..write(' ')
            ..write(lowerName);
          continue;
        }
        final String decoded = decodeHtmlEntities(rawValue);
        if (lowerName == 'style') {
          if (!_isSafeInlineStyle(decoded, urlPolicy)) {
            continue;
          }
        } else if (_singleUrlAttributes.contains(lowerName)) {
          if (decoded.trim().isEmpty || !urlPolicy.isAllowed(decoded)) {
            continue;
          }
        } else if (lowerName == 'srcset') {
          if (!_isAllowedSrcset(decoded, urlPolicy)) {
            continue;
          }
        } else if (lowerName == 'ping') {
          if (!_isAllowedPing(decoded, urlPolicy)) {
            continue;
          }
        }
        out
          ..write(' ')
          ..write(lowerName)
          ..write('="');
        writeEscapedHtml(out, decoded);
        out.write('"');
      }
    }

    out.write(tail.selfClosing ? ' />' : '>');
  }

  return out.toString();
}

final class _RawHtmlAttr {
  const _RawHtmlAttr(this.name, this.value);

  final String name;
  final String? value;
}

final class _ParsedTagTail {
  const _ParsedTagTail({
    required this.nextIndex,
    required this.selfClosing,
    required this.attrs,
  });

  final int nextIndex;
  final bool selfClosing;
  final List<_RawHtmlAttr> attrs;
}

_ParsedTagTail? _scanTagAttributesToClose(
  String html,
  int start, {
  required bool collectAttrs,
}) {
  final int len = html.length;
  int pos = start;
  bool selfClosing = false;
  final List<_RawHtmlAttr> attrs = collectAttrs
      ? <_RawHtmlAttr>[]
      : const <_RawHtmlAttr>[];

  while (pos < len) {
    final int cu = html.codeUnitAt(pos);
    if (_isHtmlWs(cu)) {
      pos++;
      continue;
    }
    if (cu == 0x3E) {
      return _ParsedTagTail(
        nextIndex: pos + 1,
        selfClosing: selfClosing,
        attrs: attrs,
      );
    }
    if (cu == 0x2F) {
      selfClosing = true;
      pos++;
      continue;
    }

    // Any attribute name after `/` clears `selfClosing` per HTML5.
    selfClosing = false;
    final int nameStart = pos;
    while (pos < len) {
      final int ncu = html.codeUnitAt(pos);
      if (_isHtmlWs(ncu) || ncu == 0x3D || ncu == 0x2F || ncu == 0x3E) {
        break;
      }
      pos++;
    }
    final String attrName = html.substring(nameStart, pos);

    while (pos < len && _isHtmlWs(html.codeUnitAt(pos))) {
      pos++;
    }

    String? attrValue;
    if (pos < len && html.codeUnitAt(pos) == 0x3D) {
      pos++; // consume '='
      while (pos < len && _isHtmlWs(html.codeUnitAt(pos))) {
        pos++;
      }
      if (pos >= len) {
        return null;
      }
      final int q = html.codeUnitAt(pos);
      if (q == 0x22 || q == 0x27) {
        pos++;
        final int closeQ = html.indexOf(q == 0x22 ? '"' : "'", pos);
        if (closeQ == -1) {
          return null;
        }
        if (collectAttrs) {
          attrValue = html.substring(pos, closeQ);
        }
        pos = closeQ + 1;
      } else {
        final int valStart = pos;
        while (pos < len) {
          final int vcu = html.codeUnitAt(pos);
          if (_isHtmlWs(vcu) || vcu == 0x3E) {
            break;
          }
          pos++;
        }
        if (pos >= len) {
          return null;
        }
        if (collectAttrs) {
          attrValue = html.substring(valStart, pos);
        }
      }
    }

    if (collectAttrs && attrName.isNotEmpty) {
      attrs.add(_RawHtmlAttr(attrName, attrValue));
    }
  }
  return null;
}

int _skipUntilRawTextClose(String html, int start, String lowerTag) {
  final int len = html.length;
  final int tagLen = lowerTag.length;
  int i = start;
  while (i < len) {
    final int lt = html.indexOf('<', i);
    if (lt == -1) {
      return len;
    }
    if (lt + 2 + tagLen <= len && html.codeUnitAt(lt + 1) == 0x2F) {
      if (_equalsLowerAt(html, lt + 2, lowerTag)) {
        final int after = lt + 2 + tagLen;
        if (after < len) {
          final int c = html.codeUnitAt(after);
          if (c == 0x3E) {
            return after + 1;
          }
          if (_isHtmlWs(c) || c == 0x2F) {
            final int gt = html.indexOf('>', after);
            return gt == -1 ? len : gt + 1;
          }
        }
      }
    }
    i = lt + 1;
  }
  return len;
}

int _skipUntilContainerClose(String html, int start, String lowerTag) {
  final int len = html.length;
  final int tagLen = lowerTag.length;
  int depth = 1;
  int i = start;
  while (i < len && depth > 0) {
    final int lt = html.indexOf('<', i);
    if (lt == -1) {
      return len;
    }
    if (lt + 2 + tagLen <= len && html.codeUnitAt(lt + 1) == 0x2F) {
      if (_equalsLowerAt(html, lt + 2, lowerTag)) {
        final int after = lt + 2 + tagLen;
        if (after < len) {
          final int c = html.codeUnitAt(after);
          if (c == 0x3E) {
            depth--;
            i = after + 1;
            continue;
          }
          if (_isHtmlWs(c) || c == 0x2F) {
            final _ParsedTagTail? tail = _scanTagAttributesToClose(
              html,
              after,
              collectAttrs: false,
            );
            if (tail == null) {
              return len;
            }
            depth--;
            i = tail.nextIndex;
            continue;
          }
        }
      }
    } else if (lt + 1 + tagLen <= len &&
        _equalsLowerAt(html, lt + 1, lowerTag)) {
      final int after = lt + 1 + tagLen;
      if (after < len) {
        final int c = html.codeUnitAt(after);
        if (c == 0x3E) {
          depth++;
          i = after + 1;
          continue;
        }
        if (_isHtmlWs(c) || c == 0x2F) {
          final _ParsedTagTail? tail = _scanTagAttributesToClose(
            html,
            after,
            collectAttrs: false,
          );
          if (tail == null) {
            return len;
          }
          if (!(tail.selfClosing &&
              (lowerTag == 'svg' || lowerTag == 'math'))) {
            depth++;
          }
          i = tail.nextIndex;
          continue;
        }
      }
    }
    i = lt + 1;
  }
  return i;
}

bool _equalsLowerAt(String haystack, int start, String lowerNeedle) {
  if (start + lowerNeedle.length > haystack.length) {
    return false;
  }
  for (int i = 0; i < lowerNeedle.length; i++) {
    int a = haystack.codeUnitAt(start + i);
    if (a >= 0x41 && a <= 0x5A) {
      a += 0x20;
    }
    if (a != lowerNeedle.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

bool _isHtmlWs(int cu) =>
    cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D || cu == 0x0C;

bool _isTagNameChar(int cu) => _isAsciiAlnum(cu) || cu == 0x2D;

bool _isSafeAttrName(String lowerName) {
  if (lowerName.isEmpty) {
    return false;
  }
  final int c0 = lowerName.codeUnitAt(0);
  if (!(c0 >= 0x61 && c0 <= 0x7A) && c0 != 0x5F && c0 != 0x3A) {
    return false;
  }
  for (int i = 1; i < lowerName.length; i++) {
    final int cu = lowerName.codeUnitAt(i);
    if (!((cu >= 0x61 && cu <= 0x7A) ||
        (cu >= 0x30 && cu <= 0x39) ||
        cu == 0x5F ||
        cu == 0x2E ||
        cu == 0x3A ||
        cu == 0x2D)) {
      return false;
    }
  }
  return true;
}

bool _isAllowedSrcset(String srcset, MarkdownUrlPolicy urlPolicy) {
  final String trimmed = srcset.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  int i = 0;
  final int len = trimmed.length;
  bool foundAny = false;
  while (i < len) {
    while (i < len &&
        (isAsciiWhitespace(trimmed.codeUnitAt(i)) ||
            trimmed.codeUnitAt(i) == 0x2C)) {
      i++;
    }
    if (i >= len) {
      break;
    }
    final int urlStart = i;
    // Handle `data:...` candidate which may contain a comma after `;base64,`.
    if (_equalsLowerAt(trimmed, i, 'data:')) {
      while (i < len && !isAsciiWhitespace(trimmed.codeUnitAt(i))) {
        i++;
      }
    } else {
      while (i < len &&
          !isAsciiWhitespace(trimmed.codeUnitAt(i)) &&
          trimmed.codeUnitAt(i) != 0x2C) {
        i++;
      }
    }
    final String candidateUrl = trimmed.substring(urlStart, i);
    if (candidateUrl.isEmpty || !urlPolicy.isAllowed(candidateUrl)) {
      return false;
    }
    foundAny = true;
    // Consume optional width/density descriptor until next `,`.
    while (i < len && trimmed.codeUnitAt(i) != 0x2C) {
      i++;
    }
    if (i < len && trimmed.codeUnitAt(i) == 0x2C) {
      i++;
    }
  }
  return foundAny;
}

bool _isAllowedPing(String ping, MarkdownUrlPolicy urlPolicy) {
  final String trimmed = ping.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  int i = 0;
  bool foundAny = false;
  while (i < trimmed.length) {
    while (i < trimmed.length && isAsciiWhitespace(trimmed.codeUnitAt(i))) {
      i++;
    }
    if (i >= trimmed.length) {
      break;
    }
    final int start = i;
    while (i < trimmed.length && !isAsciiWhitespace(trimmed.codeUnitAt(i))) {
      i++;
    }
    final String url = trimmed.substring(start, i);
    if (!urlPolicy.isAllowed(url)) {
      return false;
    }
    foundAny = true;
  }
  return foundAny;
}

bool _isSafeInlineStyle(String decodedStyle, MarkdownUrlPolicy urlPolicy) {
  // Strip CSS /* ... */ comments and decode CSS backslash escapes (`\6a `,
  // `\6a`, `\a`) before checking dangerous tokens or `url(...)` arguments.
  final String normalizedCss = _decodeCssEscapesAndStripComments(decodedStyle);
  final String compactLower = stripControlAndWhitespaceForUrl(
    normalizedCss,
  ).toLowerCase();

  if (compactLower.contains('javascript:') ||
      compactLower.contains('vbscript:') ||
      compactLower.contains('livescript:') ||
      compactLower.contains('mocha:') ||
      compactLower.contains('expression(') ||
      compactLower.contains('behavior:') ||
      compactLower.contains('-moz-binding:') ||
      compactLower.contains('-o-link') ||
      compactLower.contains('@import')) {
    return false;
  }

  // Validate every `url(...)` value in the decoded CSS.
  final String lowerCss = normalizedCss.toLowerCase();
  int search = 0;
  while (search < lowerCss.length) {
    final int urlIdx = lowerCss.indexOf('url(', search);
    if (urlIdx == -1) {
      break;
    }
    int valStart = urlIdx + 4;
    while (valStart < normalizedCss.length &&
        isAsciiWhitespace(normalizedCss.codeUnitAt(valStart))) {
      valStart++;
    }
    if (valStart >= normalizedCss.length) {
      return false;
    }
    String extracted;
    int afterClose;
    final int firstCu = normalizedCss.codeUnitAt(valStart);
    if (firstCu == 0x22 || firstCu == 0x27) {
      final int closeQ = normalizedCss.indexOf(
        firstCu == 0x22 ? '"' : "'",
        valStart + 1,
      );
      if (closeQ == -1) {
        return false;
      }
      extracted = normalizedCss.substring(valStart + 1, closeQ);
      int p = closeQ + 1;
      while (p < normalizedCss.length &&
          isAsciiWhitespace(normalizedCss.codeUnitAt(p))) {
        p++;
      }
      if (p >= normalizedCss.length || normalizedCss.codeUnitAt(p) != 0x29) {
        return false;
      }
      afterClose = p + 1;
    } else {
      final int closeParen = normalizedCss.indexOf(')', valStart);
      if (closeParen == -1) {
        return false;
      }
      extracted = normalizedCss.substring(valStart, closeParen).trim();
      afterClose = closeParen + 1;
    }
    if (!urlPolicy.isAllowed(extracted)) {
      return false;
    }
    search = afterClose;
  }

  return true;
}

String _decodeCssEscapesAndStripComments(String css) {
  if (!css.contains(r'\') && !css.contains('/*')) {
    return css;
  }
  final StringBuffer out = StringBuffer();
  int i = 0;
  final int len = css.length;
  while (i < len) {
    final int cu = css.codeUnitAt(i);
    if (cu == 0x2F && i + 1 < len && css.codeUnitAt(i + 1) == 0x2A) {
      final int endComment = css.indexOf('*/', i + 2);
      if (endComment == -1) {
        break;
      }
      i = endComment + 2;
      continue;
    }
    if (cu == 0x5C && i + 1 < len) {
      final int next = css.codeUnitAt(i + 1);
      if (next == 0x0A || next == 0x0D || next == 0x0C) {
        i += 2;
        if (next == 0x0D && i < len && css.codeUnitAt(i) == 0x0A) {
          i++;
        }
        continue;
      }
      final int firstHex = _hexVal(next);
      if (firstHex >= 0) {
        int val = 0;
        int digits = 0;
        int j = i + 1;
        while (j < len && digits < 6) {
          final int h = _hexVal(css.codeUnitAt(j));
          if (h < 0) {
            break;
          }
          val = (val << 4) | h;
          digits++;
          j++;
        }
        // Optional single whitespace after CSS hex escape.
        if (j < len && _isHtmlWs(css.codeUnitAt(j))) {
          j++;
        }
        final int cp = (val == 0 || val > 0x10FFFF) ? 0xFFFD : val;
        out.writeCharCode(cp);
        i = j;
        continue;
      }
      out.writeCharCode(next);
      i += 2;
      continue;
    }
    out.writeCharCode(cu);
    i++;
  }
  return out.toString();
}
