import 'unicode.dart';

/// Generates deterministic GitHub-style heading anchor slugs with collision
/// deduplication (`overview`, `overview-1`, `overview-2`, ...).
final class HeadingSlugGenerator {
  /// Creates a fresh [HeadingSlugGenerator].
  HeadingSlugGenerator();

  HeadingSlugGenerator._clone(Map<String, int> counts) {
    _counts.addAll(counts);
  }

  final Map<String, int> _counts = <String, int>{};

  /// Returns an independent copy of this generator preserving recorded slug
  /// counts so incremental or streaming slices continue deduplication cleanly.
  HeadingSlugGenerator clone() => HeadingSlugGenerator._clone(_counts);

  /// Clears all recorded heading slug counts.
  void reset() => _counts.clear();

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
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    return 'section';
  }
  bool isAscii = true;
  final int len = trimmed.length;
  for (int i = 0; i < len; i++) {
    if (trimmed.codeUnitAt(i) >= 0x80) {
      isAscii = false;
      break;
    }
  }
  if (isAscii) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < len; i++) {
      final int cu = trimmed.codeUnitAt(i);
      if (cu == 0x20 || cu == 0x09) {
        out.writeCharCode(0x2D);
      } else if (cu == 0x2D || cu == 0x5F) {
        out.writeCharCode(cu);
      } else if ((cu >= 0x30 && cu <= 0x39) || (cu >= 0x61 && cu <= 0x7A)) {
        out.writeCharCode(cu);
      } else if (cu >= 0x41 && cu <= 0x5A) {
        out.writeCharCode(cu + 0x20);
      }
    }
    final String result = out.toString();
    return result.isEmpty ? 'section' : result;
  }

  final String folded = caseFold(trimmed);
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
