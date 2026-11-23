import 'ast.dart';

/// Result of extracting a leading YAML or TOML frontmatter block.
final class ParsedFrontmatter {
  /// Creates a [ParsedFrontmatter].
  const ParsedFrontmatter({
    required this.node,
    required this.bodyStartOffset,
    required this.bodyStartLine,
  });

  /// Parsed frontmatter AST block.
  final FrontmatterNode node;

  /// UTF-16 offset where the document body begins after the closing fence.
  final int bodyStartOffset;

  /// 1-based line number where the document body begins.
  final int bodyStartLine;
}

/// Attempts to parse leading YAML (`---`) or TOML (`+++`) frontmatter at the
/// very beginning of normalized [source].
ParsedFrontmatter? tryParseFrontmatter(String source) {
  if (source.isEmpty) {
    return null;
  }
  final int firstNl = source.indexOf('\n');
  final String firstLine = firstNl == -1
      ? source
      : source.substring(0, firstNl);
  final String trimmedFirst = firstLine.trimRight();

  String? format;
  if (trimmedFirst == '---') {
    format = 'yaml';
  } else if (trimmedFirst == '+++') {
    format = 'toml';
  } else {
    return null;
  }

  if (firstNl == -1) {
    return null;
  }

  int cursor = firstNl + 1;
  int lineNumber = 2;
  final int rawStart = cursor;

  while (cursor <= source.length) {
    final int nextNl = source.indexOf('\n', cursor);
    final String line = nextNl == -1
        ? source.substring(cursor)
        : source.substring(cursor, nextNl);
    final String trimmed = line.trimRight();

    final bool isCloser = format == 'yaml'
        ? (trimmed == '---' || trimmed == '...')
        : (trimmed == '+++');

    if (isCloser) {
      final String raw = source.substring(rawStart, cursor);
      final int endOffset = nextNl == -1 ? source.length : nextNl + 1;
      final Map<String, Object?> entries = format == 'yaml'
          ? _parseYamlEntries(raw)
          : _parseTomlEntries(raw);
      final FrontmatterNode node = FrontmatterNode(
        blockId: 'frontmatter-0',
        frontmatter: MarkdownFrontmatter(
          raw: raw.endsWith('\n') ? raw.substring(0, raw.length - 1) : raw,
          format: format,
          entries: entries,
        ),
        span: SourceSpan(
          startOffset: 0,
          endOffset: endOffset,
          startLine: 1,
          endLine: lineNumber,
        ),
      );
      return ParsedFrontmatter(
        node: node,
        bodyStartOffset: endOffset,
        bodyStartLine: nextNl == -1 ? lineNumber : lineNumber + 1,
      );
    }

    if (nextNl == -1) {
      break;
    }
    cursor = nextNl + 1;
    lineNumber++;
  }
  return null;
}

Map<String, Object?> _parseYamlEntries(String raw) {
  final Map<String, Object?> entries = <String, Object?>{};
  final List<String> lines = raw.split('\n');
  String? currentListKey;

  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    // YAML list item under the preceding key.
    if (currentListKey != null &&
        (line.startsWith(' ') ||
            line.startsWith('\t') ||
            line.startsWith('-')) &&
        trimmed.startsWith('-')) {
      final String itemRaw = trimmed.length > 1
          ? trimmed.substring(1).trim()
          : '';
      final Object? existing = entries[currentListKey];
      if (existing is List<Object?>) {
        existing.add(_parseYamlScalar(itemRaw));
      }
      continue;
    }

    final int colon = line.indexOf(':');
    if (colon <= 0) {
      currentListKey = null;
      continue;
    }

    final String key = line.substring(0, colon).trim();
    if (key.isEmpty) {
      currentListKey = null;
      continue;
    }
    final String rest = line.substring(colon + 1).trim();
    if (rest.isEmpty) {
      entries[key] = <Object?>[];
      currentListKey = key;
    } else if (rest.startsWith('[') && rest.endsWith(']')) {
      entries[key] = _parseInlineArray(rest.substring(1, rest.length - 1));
      currentListKey = null;
    } else {
      entries[key] = _parseYamlScalar(rest);
      currentListKey = null;
    }
  }
  return entries;
}

Map<String, Object?> _parseTomlEntries(String raw) {
  final Map<String, Object?> entries = <String, Object?>{};
  final List<String> lines = raw.split('\n');
  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final int eq = trimmed.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final String key = _unquote(trimmed.substring(0, eq).trim());
    final String val = trimmed.substring(eq + 1).trim();
    if (val.startsWith('[') && val.endsWith(']')) {
      entries[key] = _parseInlineArray(val.substring(1, val.length - 1));
    } else {
      entries[key] = _parseYamlScalar(val);
    }
  }
  return entries;
}

List<Object?> _parseInlineArray(String inner) {
  final List<Object?> items = <Object?>[];
  if (inner.trim().isEmpty) {
    return items;
  }
  final StringBuffer current = StringBuffer();
  String? quote;
  for (int i = 0; i < inner.length; i++) {
    final String ch = inner[i];
    if (quote != null) {
      if (ch == '\\' && i + 1 < inner.length) {
        current
          ..write(ch)
          ..write(inner[i + 1]);
        i++;
        continue;
      }
      current.write(ch);
      if (ch == quote) {
        quote = null;
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      current.write(ch);
    } else if (ch == ',') {
      final String token = current.toString().trim();
      if (token.isNotEmpty) {
        items.add(_parseYamlScalar(token));
      }
      current.clear();
    } else {
      current.write(ch);
    }
  }
  final String tail = current.toString().trim();
  if (tail.isNotEmpty) {
    items.add(_parseYamlScalar(tail));
  }
  return items;
}

Object? _parseYamlScalar(String value) {
  if (value.isEmpty || value == 'null' || value == '~') {
    return null;
  }
  if ((value.startsWith('"') && value.endsWith('"') && value.length >= 2) ||
      (value.startsWith("'") && value.endsWith("'") && value.length >= 2)) {
    return _unquote(value);
  }
  if (value == 'true') {
    return true;
  }
  if (value == 'false') {
    return false;
  }
  final int? asInt = int.tryParse(value);
  if (asInt != null) {
    return asInt;
  }
  final double? asDouble = double.tryParse(value);
  if (asDouble != null && !value.contains(' ')) {
    return asDouble;
  }
  return value;
}

String _unquote(String raw) {
  if (raw.length >= 2 &&
      ((raw.startsWith('"') && raw.endsWith('"')) ||
          (raw.startsWith("'") && raw.endsWith("'")))) {
    return raw.substring(1, raw.length - 1);
  }
  return raw;
}
