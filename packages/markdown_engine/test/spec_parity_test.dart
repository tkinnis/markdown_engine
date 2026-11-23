import 'dart:convert';
import 'dart:io';

import 'package:markdown_engine/markdown_engine.dart';
import 'package:test/test.dart';

String _corpusRoot() {
  if (Directory('corpus').existsSync()) {
    return 'corpus';
  }
  return '../../corpus';
}

List<
  ({
    int example,
    String section,
    String markdown,
    String html,
    String tag,
    bool disabled,
    bool ignored,
  })
>
_loadCmarkTxt(String path) {
  final List<String> lines = File(path).readAsLinesSync();
  final RegExp fenceOpen = RegExp(r'^`{32} example(?:\s+(.*))?$');
  final RegExp fenceClose = RegExp(r'^`{32}$');
  final RegExp heading = RegExp(r'^#{1,6}\s+(.+)$');

  final List<
    ({
      int example,
      String section,
      String markdown,
      String html,
      String tag,
      bool disabled,
      bool ignored,
    })
  >
  cases =
      <
        ({
          int example,
          String section,
          String markdown,
          String html,
          String tag,
          bool disabled,
          bool ignored,
        })
      >[];

  String currentSection = 'General';
  int exampleNumber = 0;
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final RegExpMatch? match = fenceOpen.firstMatch(line);
    if (match != null) {
      exampleNumber++;
      final String tag = (match.group(1) ?? '').trim();
      final List<String> mdLines = <String>[];
      final List<String> htmlLines = <String>[];
      i++;
      while (i < lines.length && lines[i] != '.') {
        mdLines.add(lines[i].replaceAll('\u2192', '\t'));
        i++;
      }
      i++;
      while (i < lines.length && !fenceClose.hasMatch(lines[i])) {
        htmlLines.add(lines[i].replaceAll('\u2192', '\t'));
        i++;
      }
      final String rawHtml = htmlLines.join('\n');
      cases.add((
        example: exampleNumber,
        section: currentSection,
        markdown: '${mdLines.join('\n')}\n',
        html: htmlLines.isEmpty ? '' : '$rawHtml\n',
        tag: tag,
        disabled: tag == 'disabled',
        ignored: rawHtml.trim() == '<IGNORE>',
      ));
      continue;
    }
    final RegExpMatch? hMatch = heading.firstMatch(line);
    if (hMatch != null) {
      currentSection = hMatch.group(1)!.trim();
    }
  }
  return cases;
}

void main() {
  const MarkdownEngine engine = MarkdownEngine();
  final String root = _corpusRoot();

  test('passes 100% of CommonMark 0.31.2 specification (652/652)', () {
    final List<Object?> raw =
        jsonDecode(File('$root/spec/commonmark_0.31.2.json').readAsStringSync())
            as List<Object?>;
    expect(raw.length, 652);

    const MarkdownOptions opts = MarkdownOptions.commonMark();
    int passed = 0;
    for (final Object? item in raw) {
      final Map<String, Object?> map = item as Map<String, Object?>;
      final int example = map['example'] as int;
      final String section = map['section'] as String;
      final String markdown = map['markdown'] as String;
      final String expected = map['html'] as String;
      final String actual = engine.renderToHtml(markdown, options: opts);
      expect(
        actual,
        expected,
        reason: 'CommonMark #$example ($section) failed',
      );
      passed++;
    }
    expect(passed, 652);
  });

  test('passes 100% of GFM 0.29.0.gfm.13 core spec (670/670 active)', () {
    final List<
      ({
        int example,
        String section,
        String markdown,
        String html,
        String tag,
        bool disabled,
        bool ignored,
      })
    >
    cases = _loadCmarkTxt('$root/spec/gfm_0.29.0_spec.txt');
    expect(cases.length, 672);

    int active = 0;
    for (final c in cases) {
      if (c.disabled) {
        continue;
      }
      active++;
      final MarkdownOptions opts =
          const MarkdownOptions.commonMark(collapseNestedStrong: true).copyWith(
            gfmTables: c.tag == 'table',
            gfmStrikethrough: c.tag == 'strikethrough',
            gfmAutolinks: c.tag == 'autolink',
            gfmTagFilter: c.tag == 'tagfilter',
          );
      final String actual = engine.renderToHtml(c.markdown, options: opts);
      expect(
        actual,
        c.html,
        reason: 'GFM spec #${c.example} (${c.section}) [${c.tag}] failed',
      );
    }
    expect(active, 670);
  });

  test('passes 100% of GFM 0.29.0.gfm.13 extensions suite (29/29 active)', () {
    final List<
      ({
        int example,
        String section,
        String markdown,
        String html,
        String tag,
        bool disabled,
        bool ignored,
      })
    >
    cases = _loadCmarkTxt('$root/spec/gfm_0.29.0_extensions.txt');
    expect(cases.length, 30);

    const MarkdownOptions opts = MarkdownOptions.gfm(headingSlugs: false);
    int active = 0;
    for (final c in cases) {
      if (c.disabled || c.ignored) {
        // Still exercise parser on ignored crash-regression fixtures.
        engine.renderToHtml(c.markdown, options: opts);
        continue;
      }
      active++;
      final String actual = engine.renderToHtml(c.markdown, options: opts);
      expect(
        actual,
        c.html,
        reason: 'GFM extensions #${c.example} (${c.section}) failed',
      );
    }
    expect(active, 29);
  });
}
