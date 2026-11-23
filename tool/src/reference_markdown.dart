/// Extracts a pinned version string for [key] from a Markdown table row or
/// bullet entry in [content].
String? extractReferenceVersion(String content, String key) {
  final RegExp tableRowPattern = RegExp(
    '^\\|\\s*`${RegExp.escape(key)}`\\s*\\|\\s*`([^`\\n|]+)`',
    multiLine: true,
  );
  final RegExpMatch? rowMatch = tableRowPattern.firstMatch(content);
  if (rowMatch != null) {
    return rowMatch.group(1);
  }
  final RegExp bulletPattern = RegExp(
    '^[-*]\\s+[^\\n]*`${RegExp.escape(key)}`[^\\n]*`([^`\\n]+)`',
    multiLine: true,
  );
  final RegExpMatch? bulletMatch = bulletPattern.firstMatch(content);
  return bulletMatch?.group(1);
}

/// Extracts the recorded SHA-256 hex digest for [filePath] from a Markdown
/// table row in [content].
String? extractSpecFileSha256(String content, String filePath) {
  final RegExp rowPattern = RegExp(
    '^\\|\\s*`${RegExp.escape(filePath)}`\\s*\\|[^\\n]*`([0-9a-fA-F]{64})`',
    multiLine: true,
  );
  final RegExpMatch? match = rowPattern.firstMatch(content);
  return match?.group(1)?.toLowerCase();
}

/// Extracts the recorded example count for [filePath] from a Markdown table
/// row in [content].
int? extractSpecFileExampleCount(String content, String filePath) {
  final RegExp rowPattern = RegExp(
    '^\\|\\s*`${RegExp.escape(filePath)}`\\s*\\|[^|\\n]*\\|\\s*([0-9]+)\\s*\\|',
    multiLine: true,
  );
  final RegExpMatch? match = rowPattern.firstMatch(content);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}
