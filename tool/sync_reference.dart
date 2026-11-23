import 'dart:convert';
import 'dart:io';

import 'src/reference_markdown.dart';

const List<({String path, int expectedExamples})> _specFixtures =
    <({String path, int expectedExamples})>[
      (path: 'corpus/spec/commonmark_0.31.2.json', expectedExamples: 652),
      (path: 'corpus/spec/gfm_0.29.0_spec.txt', expectedExamples: 672),
      (path: 'corpus/spec/gfm_0.29.0_extensions.txt', expectedExamples: 30),
    ];

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/sync_reference.dart [--verify [--json]]',
    );
    return;
  }

  final bool verifyMode = args.contains('--verify');
  final bool jsonMode = args.contains('--json');

  if (!verifyMode) {
    stderr.writeln('ERROR: Specify --verify.');
    stderr.writeln(
      'Usage: dart run tool/sync_reference.dart [--verify [--json]]',
    );
    exitCode = 2;
    return;
  }

  final bool ok = _verifyReference(jsonOutput: jsonMode);
  if (!ok) {
    exitCode = 1;
  }
}

bool _verifyReference({required bool jsonOutput}) {
  final File referenceFile = File('REFERENCE.md');
  if (!referenceFile.existsSync()) {
    stderr.writeln('ERROR: Missing REFERENCE.md.');
    return false;
  }

  final String referenceText = referenceFile.readAsStringSync();
  final List<String> errors = <String>[];
  final Map<String, Object?> verifiedFiles = <String, Object?>{};

  final String? commonmarkVersion = extractReferenceVersion(
    referenceText,
    'commonmark',
  );
  if (commonmarkVersion == null || commonmarkVersion.isEmpty) {
    errors.add('Missing `commonmark` pinned version in REFERENCE.md.');
  }
  final String? gfmVersion = extractReferenceVersion(
    referenceText,
    'cmark-gfm',
  );
  if (gfmVersion == null || gfmVersion.isEmpty) {
    errors.add('Missing `cmark-gfm` pinned version in REFERENCE.md.');
  }

  for (final ({String path, int expectedExamples}) fixture in _specFixtures) {
    final File file = File(fixture.path);
    if (!file.existsSync()) {
      errors.add('Missing spec fixture: ${fixture.path}.');
      continue;
    }

    final String? computedSha = _computeFileSha256(fixture.path);
    if (computedSha == null) {
      errors.add('Unable to compute SHA-256 digest of ${fixture.path}.');
      continue;
    }

    final String? documentedSha = extractSpecFileSha256(
      referenceText,
      fixture.path,
    );
    if (documentedSha == null) {
      errors.add(
        'Missing SHA-256 digest row for `${fixture.path}` in REFERENCE.md.',
      );
    } else if (documentedSha != computedSha) {
      errors.add(
        'SHA-256 mismatch for `${fixture.path}`: actual=$computedSha, '
        'REFERENCE.md=$documentedSha.',
      );
    }

    final int? documentedCount = extractSpecFileExampleCount(
      referenceText,
      fixture.path,
    );
    if (documentedCount == null) {
      errors.add(
        'Missing example count for `${fixture.path}` in REFERENCE.md.',
      );
    } else if (documentedCount != fixture.expectedExamples) {
      errors.add(
        'Example count mismatch for `${fixture.path}`: '
        'REFERENCE.md=$documentedCount, expected=${fixture.expectedExamples}.',
      );
    }

    verifiedFiles[fixture.path] = <String, Object?>{
      'sha256': computedSha,
      'examples': documentedCount,
    };
  }

  if (errors.isNotEmpty) {
    for (final String error in errors) {
      stderr.writeln('ERROR: $error');
    }
    return false;
  }

  if (jsonOutput) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'verified': true,
        'commonmark': commonmarkVersion,
        'cmarkGfm': gfmVersion,
        'files': verifiedFiles,
      }),
    );
  } else {
    stdout.writeln(
      'REFERENCE.md verified: CommonMark $commonmarkVersion, '
      'cmark-gfm $gfmVersion (${_specFixtures.length} spec fixtures).',
    );
  }
  return true;
}

String? _computeFileSha256(String path) {
  final List<List<String>> candidates = <List<String>>[
    <String>['shasum', '-a', '256', path],
    <String>['sha256sum', path],
    <String>[
      'python3',
      '-c',
      'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())',
      path,
    ],
  ];

  for (final List<String> cmd in candidates) {
    try {
      final ProcessResult result = Process.runSync(cmd.first, cmd.sublist(1));
      if (result.exitCode == 0) {
        final String output = (result.stdout as String).trim();
        final RegExpMatch? match = RegExp(
          r'([0-9a-fA-F]{64})',
        ).firstMatch(output);
        if (match != null) {
          return match.group(1)!.toLowerCase();
        }
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}
