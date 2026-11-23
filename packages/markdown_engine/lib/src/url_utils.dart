import 'entities.dart';
import 'unicode.dart';

/// Escapes plain text for safe HTML element body output (`&`, `<`, `>`, `"`).
String escapeHtmlText(String text) {
  final StringBuffer out = StringBuffer();
  int last = 0;
  for (int i = 0; i < text.length; i++) {
    final int cu = text.codeUnitAt(i);
    String? replacement;
    switch (cu) {
      case 0x26:
        replacement = '&amp;';
      case 0x3C:
        replacement = '&lt;';
      case 0x3E:
        replacement = '&gt;';
      case 0x22:
        replacement = '&quot;';
      default:
        break;
    }
    if (replacement != null) {
      if (i > last) {
        out.write(text.substring(last, i));
      }
      out.write(replacement);
      last = i + 1;
    }
  }
  if (last == 0) {
    return text;
  }
  if (last < text.length) {
    out.write(text.substring(last));
  }
  return out.toString();
}

/// Unescapes CommonMark backslash escapes and HTML character references inside
/// link destinations, titles, and fenced code info strings.
String unescapeMarkdownString(String input) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < input.length) {
    final int cu = input.codeUnitAt(i);
    if (cu == 0x5C && i + 1 < input.length) {
      final int next = input.codeUnitAt(i + 1);
      if (isAsciiPunctuation(next)) {
        out.writeCharCode(next);
        i += 2;
        continue;
      }
    } else if (cu == 0x26) {
      final ({String text, int nextIndex})? decoded = decodeCharacterReference(
        input,
        i,
      );
      if (decoded != null) {
        out.write(decoded.text);
        i = decoded.nextIndex;
        continue;
      }
    }
    out.writeCharCode(cu);
    i++;
  }
  return out.toString();
}

/// Percent-encodes a resolved destination URL for HTML `href`/`src` attributes
/// matching CommonMark `0.31.2` and `cmark-gfm` (`houdini_escape_href`) rules.
String percentEncodeUrl(String url) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < url.length) {
    final int cu = url.codeUnitAt(i);
    if (cu == 0x25 &&
        i + 2 < url.length &&
        _isHexDigit(url.codeUnitAt(i + 1)) &&
        _isHexDigit(url.codeUnitAt(i + 2))) {
      out.write(url.substring(i, i + 3));
      i += 3;
      continue;
    }
    if (cu == 0x26) {
      out.write('&amp;');
      i++;
      continue;
    }
    if (cu == 0x27) {
      out.write('&#x27;');
      i++;
      continue;
    }
    if (cu < 0x80 && _isHrefSafeAscii(cu)) {
      out.writeCharCode(cu);
      i++;
      continue;
    }
    // Encode full UTF-8 byte sequence of the Unicode scalar value.
    int cp = cu;
    int step = 1;
    if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < url.length) {
      final int low = url.codeUnitAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        cp = 0x10000 + ((cu - 0xD800) << 10) + (low - 0xDC00);
        step = 2;
      }
    }
    _writeUtf8PercentEncoded(out, cp);
    i += step;
  }
  return out.toString();
}

/// Percent-encodes URL characters while leaving `'` unencoded (`cmark-gfm`
/// footnote `href`/`id` attribute normalization).
String percentEncodeHrefFragment(String fragment) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < fragment.length) {
    final int cu = fragment.codeUnitAt(i);
    if (cu < 0x80 && _isHrefSafeAscii(cu) && cu != 0x27 && cu != 0x26) {
      out.writeCharCode(cu);
      i++;
      continue;
    }
    if (cu == 0x27) {
      out.write('&#x27;');
      i++;
      continue;
    }
    if (cu == 0x26) {
      out.write('&amp;');
      i++;
      continue;
    }
    int cp = cu;
    int step = 1;
    if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < fragment.length) {
      final int low = fragment.codeUnitAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        cp = 0x10000 + ((cu - 0xD800) << 10) + (low - 0xDC00);
        step = 2;
      }
    }
    _writeUtf8PercentEncoded(out, cp);
    i += step;
  }
  return out.toString();
}

/// Normalizes a CommonMark link reference label by trimming leading/trailing
/// whitespace, collapsing internal whitespace runs to a single space, and
/// applying full Unicode case folding.
String normalizeLinkLabel(String rawLabel) {
  final StringBuffer collapsed = StringBuffer();
  bool inSpace = false;
  bool seenNonSpace = false;
  for (int i = 0; i < rawLabel.length; i++) {
    final int cu = rawLabel.codeUnitAt(i);
    if (isAsciiWhitespace(cu)) {
      if (seenNonSpace) {
        inSpace = true;
      }
    } else {
      if (inSpace) {
        collapsed.writeCharCode(0x20);
        inSpace = false;
      }
      collapsed.writeCharCode(cu);
      seenNonSpace = true;
    }
  }
  return caseFold(collapsed.toString());
}

void _writeUtf8PercentEncoded(StringBuffer out, int cp) {
  if (cp <= 0x7F) {
    _writeHexByte(out, cp);
  } else if (cp <= 0x7FF) {
    _writeHexByte(out, 0xC0 | (cp >> 6));
    _writeHexByte(out, 0x80 | (cp & 0x3F));
  } else if (cp <= 0xFFFF) {
    _writeHexByte(out, 0xE0 | (cp >> 12));
    _writeHexByte(out, 0x80 | ((cp >> 6) & 0x3F));
    _writeHexByte(out, 0x80 | (cp & 0x3F));
  } else {
    _writeHexByte(out, 0xF0 | (cp >> 18));
    _writeHexByte(out, 0x80 | ((cp >> 12) & 0x3F));
    _writeHexByte(out, 0x80 | ((cp >> 6) & 0x3F));
    _writeHexByte(out, 0x80 | (cp & 0x3F));
  }
}

void _writeHexByte(StringBuffer out, int byte) {
  const String digits = '0123456789ABCDEF';
  out
    ..write('%')
    ..write(digits[(byte >> 4) & 0xF])
    ..write(digits[byte & 0xF]);
}

bool _isHexDigit(int cu) =>
    (cu >= 0x30 && cu <= 0x39) ||
    (cu >= 0x41 && cu <= 0x46) ||
    (cu >= 0x61 && cu <= 0x66);

// Safe ASCII characters left unencoded by CommonMark / cmark_houdini_escape_href:
// alnum, - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , #
bool _isHrefSafeAscii(int cu) {
  if ((cu >= 0x41 && cu <= 0x5A) ||
      (cu >= 0x61 && cu <= 0x7A) ||
      (cu >= 0x30 && cu <= 0x39)) {
    return true;
  }
  switch (cu) {
    case 0x21: // !
    case 0x23: // #
    case 0x24: // $
    case 0x26: // &
    case 0x28: // (
    case 0x29: // )
    case 0x2A: // *
    case 0x2B: // +
    case 0x2C: // ,
    case 0x2D: // -
    case 0x2E: // .
    case 0x2F: // /
    case 0x3A: // :
    case 0x3B: // ;
    case 0x3D: // =
    case 0x3F: // ?
    case 0x40: // @
    case 0x5F: // _
    case 0x7E: // ~
      return true;
    default:
      return false;
  }
}
