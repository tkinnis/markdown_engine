import 'dart:convert';
import 'dart:io';

import 'package:markdown_engine/markdown_engine.dart';

import 'src/cli_args.dart';

const String _commonMarkSpecPath = 'corpus/spec/commonmark_0.31.2.json';
const String _gfmSpecPath = 'corpus/spec/gfm_0.29.0_spec.txt';
const String _gfmExtensionsPath = 'corpus/spec/gfm_0.29.0_extensions.txt';
const String _coverageDocPath = 'doc/COVERAGE.md';

/// Parsed CommonMark or GFM specification example.
final class SpecTestCase {
  /// Creates a specification test case.
  const SpecTestCase({
    required this.suite,
    required this.exampleNumber,
    required this.section,
    required this.markdown,
    required this.expectedHtml,
    this.tag = '',
    this.ignored = false,
    this.disabled = false,
  });

  /// Suite identifier (`commonmark`, `gfm_spec`, or `gfm_extensions`).
  final String suite;

  /// 1-based example number within the suite.
  final int exampleNumber;

  /// Specification heading section name.
  final String section;

  /// Raw Markdown input fixture (with spec tab arrows expanded).
  final String markdown;

  /// Expected HTML output from the specification.
  final String expectedHtml;

  /// Optional cmark-gfm tag (`table`, `autolink`, `strikethrough`, etc.).
  final String tag;

  /// Whether expected output is `<IGNORE>` (crash-regression fixture).
  final bool ignored;

  /// Whether the upstream example is marked `disabled`.
  final bool disabled;
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/verify_spec.dart '
      '[--suite=all|commonmark|gfm|extensions] '
      '[--update-coverage] [--strict] [--json]',
    );
    return;
  }

  final String suiteFilter = parseStringFlag(args, 'suite') ?? 'all';
  final bool updateCoverage = args.contains('--update-coverage');
  final bool strict = args.contains('--strict');
  final bool jsonOutput = args.contains('--json');
  final bool verbose = args.contains('--verbose');

  final List<SpecTestCase> commonmarkCases = _loadCommonMarkJson(
    _commonMarkSpecPath,
  );
  final List<SpecTestCase> gfmSpecCases = _loadCmarkTxtSpec(
    _gfmSpecPath,
    suite: 'gfm_spec',
  );
  final List<SpecTestCase> gfmExtensionCases = _loadCmarkTxtSpec(
    _gfmExtensionsPath,
    suite: 'gfm_extensions',
  );

  final List<SpecTestCase> selected = <SpecTestCase>[
    if (suiteFilter == 'all' || suiteFilter == 'commonmark') ...commonmarkCases,
    if (suiteFilter == 'all' || suiteFilter == 'gfm') ...gfmSpecCases,
    if (suiteFilter == 'all' || suiteFilter == 'extensions')
      ...gfmExtensionCases,
  ];

  if (selected.isEmpty) {
    stderr.writeln('ERROR: Unknown or empty --suite filter "$suiteFilter".');
    exitCode = 2;
    return;
  }

  const MarkdownEngine engine = MarkdownEngine();
  final Map<String, _SuiteStats> statsBySuite = <String, _SuiteStats>{};
  int totalActive = 0;
  int totalPassed = 0;

  for (final SpecTestCase testCase in selected) {
    final _SuiteStats suiteStats = statsBySuite.putIfAbsent(
      testCase.suite,
      () => _SuiteStats(testCase.suite),
    );
    suiteStats.total++;

    if (testCase.disabled) {
      suiteStats.disabled++;
      continue;
    }

    final MarkdownOptions options = _optionsForCase(testCase);

    final String actualHtml = engine.renderToHtml(
      testCase.markdown,
      options: options,
    );

    if (testCase.ignored) {
      suiteStats.ignored++;
      suiteStats.passed++;
      totalActive++;
      totalPassed++;
      continue;
    }

    totalActive++;
    if (actualHtml == testCase.expectedHtml) {
      suiteStats.passed++;
      totalPassed++;
    } else {
      suiteStats.failed++;
      if (verbose && !jsonOutput) {
        stderr.writeln(
          'FAIL [${testCase.suite} #${testCase.exampleNumber} '
          '(${testCase.section})]:\n'
          '  MD:  ${jsonEncode(testCase.markdown)}\n'
          '  EXP: ${jsonEncode(testCase.expectedHtml)}\n'
          '  ACT: ${jsonEncode(actualHtml)}',
        );
      }
    }
  }

  if (updateCoverage) {
    final String markdown = _renderCoverageMarkdown(
      commonmarkStats: statsBySuite['commonmark'],
      gfmSpecStats: statsBySuite['gfm_spec'],
      gfmExtStats: statsBySuite['gfm_extensions'],
    );
    File(_coverageDocPath).writeAsStringSync(markdown);
    if (!jsonOutput) {
      stdout.writeln('Updated $_coverageDocPath.');
    }
  }

  if (jsonOutput) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'suiteFilter': suiteFilter,
        'activeCases': totalActive,
        'passedCases': totalPassed,
        'suites': <String, Object?>{
          for (final _SuiteStats s in statsBySuite.values)
            s.name: <String, Object?>{
              'total': s.total,
              'passed': s.passed,
              'failed': s.failed,
              'disabled': s.disabled,
              'ignored': s.ignored,
            },
        },
      }),
    );
  } else {
    for (final _SuiteStats s in statsBySuite.values) {
      final int active = s.total - s.disabled;
      stdout.writeln(
        '${s.name}: ${s.passed}/$active passed '
        '(failed: ${s.failed}, disabled: ${s.disabled}, ignored: ${s.ignored})',
      );
    }
  }

  if (totalPassed != totalActive && (!updateCoverage || strict)) {
    exitCode = 1;
  }
}

List<SpecTestCase> _loadCommonMarkJson(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    throw StateError('Missing CommonMark spec JSON: $path');
  }
  final List<Object?> rawList =
      jsonDecode(file.readAsStringSync()) as List<Object?>;
  final List<SpecTestCase> cases = <SpecTestCase>[];
  for (final Object? item in rawList) {
    final Map<String, Object?> map = item as Map<String, Object?>;
    cases.add(
      SpecTestCase(
        suite: 'commonmark',
        exampleNumber: map['example'] as int,
        section: map['section'] as String,
        markdown: map['markdown'] as String,
        expectedHtml: map['html'] as String,
      ),
    );
  }
  return cases;
}

List<SpecTestCase> _loadCmarkTxtSpec(String path, {required String suite}) {
  final File file = File(path);
  if (!file.existsSync()) {
    throw StateError('Missing GFM spec fixture: $path');
  }

  final List<String> lines = file.readAsLinesSync();
  final List<SpecTestCase> cases = <SpecTestCase>[];
  final RegExp fenceOpen = RegExp(r'^`{32} example(?:\s+(.*))?$');
  final RegExp fenceClose = RegExp(r'^`{32}$');
  final RegExp headingPattern = RegExp(r'^#{1,6}\s+(.+)$');

  String currentSection = 'General';
  int exampleNumber = 0;

  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final RegExpMatch? fenceMatch = fenceOpen.firstMatch(line);
    if (fenceMatch != null) {
      exampleNumber++;
      final String tag = (fenceMatch.group(1) ?? '').trim();
      final List<String> mdLines = <String>[];
      final List<String> htmlLines = <String>[];

      i++;
      while (i < lines.length && lines[i] != '.') {
        mdLines.add(lines[i].replaceAll('\u2192', '\t'));
        i++;
      }
      if (i >= lines.length || lines[i] != '.') {
        throw FormatException(
          'Missing "." separator in $path at line ${i + 1}',
        );
      }

      i++;
      while (i < lines.length && !fenceClose.hasMatch(lines[i])) {
        htmlLines.add(lines[i].replaceAll('\u2192', '\t'));
        i++;
      }
      if (i >= lines.length) {
        throw FormatException('Unclosed example block in $path at line $i');
      }

      final String markdown = '${mdLines.join('\n')}\n';
      final String rawHtml = htmlLines.join('\n');
      final bool isIgnored = rawHtml.trim() == '<IGNORE>';
      final String expectedHtml = htmlLines.isEmpty ? '' : '$rawHtml\n';

      cases.add(
        SpecTestCase(
          suite: suite,
          exampleNumber: exampleNumber,
          section: currentSection,
          markdown: markdown,
          expectedHtml: expectedHtml,
          tag: tag,
          ignored: isIgnored,
          disabled: tag == 'disabled',
        ),
      );
      continue;
    }

    // Fallback support for bare `.\n...\n.\n...\n.` test blocks if present.
    if (line == '.') {
      exampleNumber++;
      final List<String> mdLines = <String>[];
      final List<String> htmlLines = <String>[];
      i++;
      while (i < lines.length && lines[i] != '.') {
        mdLines.add(lines[i].replaceAll('\u2192', '\t'));
        i++;
      }
      i++;
      while (i < lines.length && lines[i] != '.') {
        htmlLines.add(lines[i].replaceAll('\u2192', '\t'));
        i++;
      }
      final String markdown = '${mdLines.join('\n')}\n';
      final String rawHtml = htmlLines.join('\n');
      cases.add(
        SpecTestCase(
          suite: suite,
          exampleNumber: exampleNumber,
          section: currentSection,
          markdown: markdown,
          expectedHtml: htmlLines.isEmpty ? '' : '$rawHtml\n',
          ignored: rawHtml.trim() == '<IGNORE>',
        ),
      );
      continue;
    }

    final RegExpMatch? headingMatch = headingPattern.firstMatch(line);
    if (headingMatch != null) {
      currentSection = headingMatch.group(1)!.trim();
    }
  }

  return cases;
}

String _renderCoverageMarkdown({
  _SuiteStats? commonmarkStats,
  _SuiteStats? gfmSpecStats,
  _SuiteStats? gfmExtStats,
}) {
  final StringBuffer out = StringBuffer()
    ..writeln('# Specification Coverage Matrix')
    ..writeln()
    ..writeln(
      'This report is generated by `dart run tool/verify_spec.dart '
      '--update-coverage` against the vendored CommonMark `0.31.2` and '
      '`cmark-gfm 0.29.0.gfm.13` fixtures in `corpus/spec/`.',
    )
    ..writeln()
    ..writeln('## Summary by Suite')
    ..writeln()
    ..writeln('| Suite | Passed | Failed | Disabled | Total | Pass Rate |')
    ..writeln('| :--- | ---: | ---: | ---: | ---: | ---: |');

  for (final _SuiteStats? s in <_SuiteStats?>[
    commonmarkStats,
    gfmSpecStats,
    gfmExtStats,
  ]) {
    if (s == null) {
      continue;
    }
    final int active = s.total - s.disabled;
    final String pct = active > 0
        ? '${(s.passed * 100.0 / active).toStringAsFixed(1)}%'
        : '0.0%';
    out.writeln(
      '| `${s.name}` | ${s.passed} | ${s.failed} | ${s.disabled} | '
      '${s.total} | $pct |',
    );
  }
  return out.toString();
}

final class _SuiteStats {
  _SuiteStats(this.name);

  final String name;
  int total = 0;
  int passed = 0;
  int failed = 0;
  int disabled = 0;
  int ignored = 0;
}

MarkdownOptions _optionsForCase(SpecTestCase testCase) {
  if (testCase.suite == 'commonmark') {
    return const MarkdownOptions.commonMark();
  }
  if (testCase.suite == 'gfm_spec') {
    final String tag = testCase.tag;
    return MarkdownOptions.commonMark(collapseNestedStrong: true).copyWith(
      gfmTables: tag == 'table',
      gfmStrikethrough: tag == 'strikethrough',
      gfmAutolinks: tag == 'autolink',
      gfmTagFilter: tag == 'tagfilter',
    );
  }
  return const MarkdownOptions.gfm(headingSlugs: false);
}
