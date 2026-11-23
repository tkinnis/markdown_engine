import 'package:meta/meta.dart';

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
  });

  /// Default blocked URI schemes (`javascript`, `vbscript`, `data`).
  static const Set<String> defaultBlockedSchemes = <String>{
    'javascript',
    'vbscript',
    'data',
  };

  /// Schemes explicitly rejected (matched lowercase after stripping control chars).
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

  static final RegExp _safeImageDataPattern = RegExp(
    r'^data:image/(?:png|jpe?g|gif|webp);base64,[A-Za-z0-9+/=]+$',
    caseSensitive: false,
  );

  /// Returns whether [url] is permitted by this policy.
  bool isAllowed(String url) {
    final String cleaned = _stripControlAndAsciiWhitespace(url);
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
      if (cleaned.startsWith('//') && allowedHosts != null) {
        return _isAllowedHost(cleaned.substring(2));
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

    if (allowedHosts != null) {
      final int colonIndex = cleaned.indexOf(':');
      final String afterScheme = cleaned.substring(colonIndex + 1);
      if (afterScheme.startsWith('//')) {
        return _isAllowedHost(afterScheme.substring(2));
      }
    }
    return true;
  }

  /// Returns [url] if permitted by this policy, or [fallback] otherwise.
  String sanitize(String url, {String fallback = ''}) {
    return isAllowed(url) ? url : fallback;
  }

  bool _isAllowedHost(String authorityAndRest) {
    final Set<String>? hosts = allowedHosts;
    if (hosts == null) {
      return true;
    }
    int end = authorityAndRest.length;
    for (int i = 0; i < authorityAndRest.length; i++) {
      final int cu = authorityAndRest.codeUnitAt(i);
      if (cu == 0x2F || cu == 0x3F || cu == 0x23) {
        end = i;
        break;
      }
    }
    String authority = authorityAndRest.substring(0, end);
    final int atIndex = authority.lastIndexOf('@');
    if (atIndex >= 0) {
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
          _setEquals(blockedSchemes, other.blockedSchemes) &&
          _nullableSetEquals(allowedSchemes, other.allowedSchemes) &&
          _nullableSetEquals(allowedHosts, other.allowedHosts) &&
          allowRelative == other.allowRelative &&
          allowFragments == other.allowFragments &&
          allowSafeImageDataUrls == other.allowSafeImageDataUrls;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(blockedSchemes),
    allowedSchemes == null ? null : Object.hashAllUnordered(allowedSchemes!),
    allowedHosts == null ? null : Object.hashAllUnordered(allowedHosts!),
    allowRelative,
    allowFragments,
    allowSafeImageDataUrls,
  );
}

String _stripControlAndAsciiWhitespace(String input) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    final int cu = input.codeUnitAt(i);
    if (cu <= 0x20 || cu == 0x7F) {
      continue;
    }
    out.writeCharCode(cu);
  }
  return out.toString();
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
    if (cu == 0x2F || cu == 0x3F || cu == 0x23) {
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

bool _setEquals(Set<String> a, Set<String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  return a.containsAll(b);
}

bool _nullableSetEquals(Set<String>? a, Set<String>? b) {
  if (a == null && b == null) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  return _setEquals(a, b);
}

final RegExp _gfmTagFilterPattern = RegExp(
  r'<(?=(?:title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext)(?:[\x00-\x20/>]|$))',
  caseSensitive: false,
);

/// Escapes GFM disallowed raw HTML opening tags (`<script`, `<style`, `<iframe`,
/// etc.) by replacing the leading `<` with `&lt;`.
String applyGfmTagFilter(String html) {
  return html.replaceAll(_gfmTagFilterPattern, '&lt;');
}

const Set<String> _unsafeHtmlElements = <String>{
  'script',
  'style',
  'iframe',
  'object',
  'embed',
  'applet',
  'base',
  'link',
  'meta',
  'title',
  'textarea',
  'xmp',
  'noembed',
  'noframes',
  'plaintext',
  'svg',
  'math',
  'form',
  'frame',
  'frameset',
};

final RegExp _dangerousBlockTagPattern = RegExp(
  r'<\s*(script|style|iframe|object|embed|applet|svg|math|title|textarea|xmp|noembed|noframes|plaintext|form|frame|frameset)\b[^>]*>[\s\S]*?<\s*/\s*\1\s*>|<\s*(?:script|style|iframe|object|embed|applet|base|link|meta|title|textarea|xmp|noembed|noframes|plaintext|svg|math|form|frame|frameset)\b[^>]*\/?>',
  caseSensitive: false,
);

final RegExp _genericHtmlTagPattern = RegExp(
  r'<(\/?)([A-Za-z][A-Za-z0-9-]*)((?:\s+[^<>]*)?)\s*(\/?)>',
);

final RegExp _htmlAttributePattern = RegExp(
  r'''([A-Za-z_:][A-Za-z0-9_.:-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
);

/// Sanitizes raw HTML strings by stripping unsafe elements, `on*` event
/// handlers, `srcdoc`, unsafe CSS `url(...)`/`expression(...)`, and dangerous
/// URI attributes according to [urlPolicy].
String sanitizeRawHtml(String html, MarkdownUrlPolicy urlPolicy) {
  if (html.isEmpty) {
    return html;
  }
  final String withoutDangerous = html.replaceAll(
    _dangerousBlockTagPattern,
    '',
  );
  return withoutDangerous.replaceAllMapped(_genericHtmlTagPattern, (
    Match match,
  ) {
    final String slash = match.group(1) ?? '';
    final String tagName = match.group(2) ?? '';
    final String rawAttrs = match.group(3) ?? '';
    final String selfClose = match.group(4) ?? '';
    final String lowerTag = tagName.toLowerCase();

    if (_unsafeHtmlElements.contains(lowerTag)) {
      return '';
    }
    if (slash.isNotEmpty) {
      return '</$tagName>';
    }

    final StringBuffer attrBuffer = StringBuffer();
    for (final Match attr in _htmlAttributePattern.allMatches(rawAttrs)) {
      final String name = attr.group(1)!;
      final String lowerName = name.toLowerCase();
      if (lowerName.startsWith('on') || lowerName == 'srcdoc') {
        continue;
      }
      final String? doubleVal = attr.group(2);
      final String? singleVal = attr.group(3);
      final String? bareVal = attr.group(4);
      final String? value = doubleVal ?? singleVal ?? bareVal;
      if (value == null) {
        attrBuffer
          ..write(' ')
          ..write(name);
        continue;
      }
      if (lowerName == 'style') {
        final String cleanedStyle = _stripControlAndAsciiWhitespace(
          value,
        ).toLowerCase();
        if (cleanedStyle.contains('javascript:') ||
            cleanedStyle.contains('vbscript:') ||
            cleanedStyle.contains('expression(') ||
            cleanedStyle.contains('data:text/html')) {
          continue;
        }
      }
      if (lowerName == 'href' ||
          lowerName == 'src' ||
          lowerName == 'action' ||
          lowerName == 'formaction' ||
          lowerName == 'poster' ||
          lowerName == 'xlink:href') {
        if (!urlPolicy.isAllowed(value)) {
          continue;
        }
      }
      final String quote = singleVal != null && doubleVal == null ? "'" : '"';
      attrBuffer
        ..write(' ')
        ..write(name)
        ..write('=')
        ..write(quote)
        ..write(value)
        ..write(quote);
    }

    final String closing = selfClose.isNotEmpty ? ' />' : '>';
    return '<$tagName$attrBuffer$closing';
  });
}
