import 'unicode.dart';

/// Generates deterministic GitHub-style heading anchor slugs with collision
/// deduplication (`overview`, `overview-1`, `overview-2`, ...).
final class HeadingSlugGenerator {
  /// Creates a fresh [HeadingSlugGenerator].
  HeadingSlugGenerator();

  final Map<String, int> _counts = <String, int>{};

  /// Computes a unique GitHub-style slug for heading [text].
  String generate(String text) {
    final String base = slugifyHeadingText(text);
    final int? seen = _counts[base];
    if (seen == null) {
      _counts[base] = 1;
      return base;
    }
    _counts[base] = seen + 1;
    String candidate = '$base-$seen';
    while (_counts.containsKey(candidate)) {
      final int next = _counts[base]!;
      _counts[base] = next + 1;
      candidate = '$base-$next';
    }
    _counts[candidate] = 1;
    return candidate;
  }
}

/// Converts raw heading [text] to a normalized GitHub-style anchor slug.
///
/// Spaces become hyphens (`-`), ASCII letters are lowercased, punctuation and
/// symbols other than `-` and `_` are stripped, and non-ASCII letters/digits
/// are preserved (case-folded) so UTF-8 headings produce readable slugs.
String slugifyHeadingText(String text) {
  final String folded = caseFold(text.trim());
  final StringBuffer out = StringBuffer();
  for (final int cp in folded.runes) {
    if (cp == 0x20 || cp == 0x09) {
      out.writeCharCode(0x2D);
    } else if (cp == 0x2D || cp == 0x5F) {
      out.writeCharCode(cp);
    } else if ((cp >= 0x30 && cp <= 0x39) || (cp >= 0x61 && cp <= 0x7A)) {
      out.writeCharCode(cp);
    } else if (cp >= 0x80 &&
        !isUnicodeWhitespace(cp) &&
        !isUnicodePunctuation(cp)) {
      out.writeCharCode(cp);
    }
  }
  final String result = out.toString();
  return result.isEmpty ? 'section' : result;
}
