import 'dart:convert';
import 'dart:io';

import 'src/reference_markdown.dart';

const List<({String path, int expectedExamples})> _specFixtures =
    <({String path, int expectedExamples})>[
      (path: 'corpus/spec/commonmark_0.31.2.json', expectedExamples: 652),
      (path: 'corpus/spec/gfm_0.29.0_spec.txt', expectedExamples: 672),
      (path: 'corpus/spec/gfm_0.29.0_extensions.txt', expectedExamples: 30),
    ];

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/sync_reference.dart [--verify [--json] | --check [--json]]',
    );
    return;
  }

  final bool verifyMode = args.contains('--verify');
  final bool checkMode = args.contains('--check');
  final bool jsonMode = args.contains('--json');

  if (!verifyMode && !checkMode) {
    stderr.writeln('ERROR: Specify --verify or --check.');
    stderr.writeln(
      'Usage: dart run tool/sync_reference.dart [--verify [--json] | --check [--json]]',
    );
    exitCode = 2;
    return;
  }

  if (verifyMode) {
    final bool ok = _verifyReference(jsonOutput: jsonMode && !checkMode);
    if (!ok) {
      exitCode = 1;
      return;
    }
  }

  if (checkMode) {
    final bool ok = await _checkUpstream(jsonOutput: jsonMode);
    if (!ok) {
      exitCode = 1;
      return;
    }
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

Future<bool> _checkUpstream({required bool jsonOutput}) async {
  final File referenceFile = File('REFERENCE.md');
  if (!referenceFile.existsSync()) {
    stderr.writeln('ERROR: Missing REFERENCE.md.');
    return false;
  }

  final String referenceText = referenceFile.readAsStringSync();
  final String? pinnedCommonmark = extractReferenceVersion(
    referenceText,
    'commonmark',
  );
  final String? pinnedGfm = extractReferenceVersion(referenceText, 'cmark-gfm');

  if (pinnedCommonmark == null ||
      pinnedCommonmark.isEmpty ||
      pinnedGfm == null ||
      pinnedGfm.isEmpty) {
    stderr.writeln(
      'ERROR: Could not extract pinned versions for `commonmark` or '
      '`cmark-gfm` from REFERENCE.md.',
    );
    return false;
  }

  final String? token = _resolveGithubToken();
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final String latestCommonmark = await _fetchGithubLatestVersion(
      client,
      owner: 'commonmark',
      repo: 'commonmark-spec',
      token: token,
    );
    final String latestGfm = await _fetchGithubLatestVersion(
      client,
      owner: 'github',
      repo: 'cmark-gfm',
      token: token,
    );

    final bool commonmarkUpToDate =
        _compareVersions(latestCommonmark, pinnedCommonmark) <= 0;
    final bool gfmUpToDate = _compareVersions(latestGfm, pinnedGfm) <= 0;
    final bool hasUpdate = !commonmarkUpToDate || !gfmUpToDate;

    final Map<String, Object?> payload = <String, Object?>{
      'hasUpdate': hasUpdate,
      'pinnedCommonmark': pinnedCommonmark,
      'latestCommonmark': latestCommonmark,
      'pinnedGfm': pinnedGfm,
      'latestGfm': latestGfm,
      'commonmark': <String, Object?>{
        'repository': 'commonmark/commonmark-spec',
        'pinned': pinnedCommonmark,
        'latest': latestCommonmark,
        'upToDate': commonmarkUpToDate,
      },
      'cmarkGfm': <String, Object?>{
        'repository': 'github/cmark-gfm',
        'pinned': pinnedGfm,
        'latest': latestGfm,
        'upToDate': gfmUpToDate,
      },
    };

    if (jsonOutput) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
    } else {
      stdout.writeln(
        'commonmark: pinned=$pinnedCommonmark latest=$latestCommonmark '
        '(${commonmarkUpToDate ? 'up to date' : 'UPDATE AVAILABLE'})',
      );
      stdout.writeln(
        'cmark-gfm: pinned=$pinnedGfm latest=$latestGfm '
        '(${gfmUpToDate ? 'up to date' : 'UPDATE AVAILABLE'})',
      );
    }
    return true;
  } catch (err) {
    stderr.writeln('ERROR: Failed to query GitHub REST API: $err');
    return false;
  } finally {
    client.close(force: true);
  }
}

String? _resolveGithubToken() {
  final String? ghToken = Platform.environment['GH_TOKEN']?.trim();
  if (ghToken != null && ghToken.isNotEmpty) {
    return ghToken;
  }
  final String? githubToken = Platform.environment['GITHUB_TOKEN']?.trim();
  if (githubToken != null && githubToken.isNotEmpty) {
    return githubToken;
  }
  return null;
}

Future<String> _fetchGithubLatestVersion(
  HttpClient client, {
  required String owner,
  required String repo,
  required String? token,
}) async {
  final Uri releaseUri = Uri.https(
    'api.github.com',
    '/repos/$owner/$repo/releases/latest',
  );
  final ({int statusCode, String body}) releaseResponse = await _getGithubJson(
    client,
    releaseUri,
    token: token,
  );

  if (releaseResponse.statusCode == HttpStatus.ok) {
    final Object? decoded = jsonDecode(releaseResponse.body);
    if (decoded is Map<String, Object?>) {
      final String? tagName = decoded['tag_name'] as String?;
      if (tagName != null && tagName.trim().isNotEmpty) {
        return _normalizeTagVersion(tagName.trim());
      }
    }
    throw FormatException(
      'Missing "tag_name" field in GitHub release response from $releaseUri',
    );
  }

  if (releaseResponse.statusCode != HttpStatus.notFound) {
    throw HttpException(
      'HTTP ${releaseResponse.statusCode} fetching $releaseUri',
      uri: releaseUri,
    );
  }

  final Uri tagsUri = Uri.https(
    'api.github.com',
    '/repos/$owner/$repo/tags',
    const <String, String>{'per_page': '10'},
  );
  final ({int statusCode, String body}) tagsResponse = await _getGithubJson(
    client,
    tagsUri,
    token: token,
  );

  if (tagsResponse.statusCode != HttpStatus.ok) {
    throw HttpException(
      'HTTP ${tagsResponse.statusCode} fetching $tagsUri',
      uri: tagsUri,
    );
  }

  final Object? decodedTags = jsonDecode(tagsResponse.body);
  if (decodedTags is List<Object?>) {
    final RegExp versionTagPattern = RegExp(r'^[vV]?\d+\.\d+');
    String? fallbackTag;
    for (final Object? entry in decodedTags) {
      if (entry is! Map<String, Object?>) {
        continue;
      }
      final String? name = (entry['name'] as String?)?.trim();
      if (name == null || name.isEmpty) {
        continue;
      }
      fallbackTag ??= _normalizeTagVersion(name);
      if (versionTagPattern.hasMatch(name)) {
        return _normalizeTagVersion(name);
      }
    }
    if (fallbackTag != null) {
      return fallbackTag;
    }
  }

  throw FormatException('No release tags found in response from $tagsUri');
}

Future<({int statusCode, String body})> _getGithubJson(
  HttpClient client,
  Uri uri, {
  required String? token,
}) async {
  final HttpClientRequest request = await client
      .getUrl(uri)
      .timeout(const Duration(seconds: 20));
  request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
  request.headers.set('X-GitHub-Api-Version', '2022-11-28');
  request.headers.set(
    HttpHeaders.userAgentHeader,
    'markdown_engine-reference-sync',
  );
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  final HttpClientResponse response = await request.close().timeout(
    const Duration(seconds: 20),
  );
  final String body = await utf8
      .decodeStream(response)
      .timeout(const Duration(seconds: 20));
  return (statusCode: response.statusCode, body: body);
}

String _normalizeTagVersion(String rawTag) {
  return rawTag.replaceFirst(RegExp(r'^[vV](?=\d)'), '');
}

int _compareVersions(String a, String b) {
  final int aDash = a.indexOf('-');
  final int bDash = b.indexOf('-');
  final String aCoreRaw = aDash == -1 ? a : a.substring(0, aDash);
  final String bCoreRaw = bDash == -1 ? b : b.substring(0, bDash);

  final int coreCmp = _compareDotSegments(
    aCoreRaw.split('.'),
    bCoreRaw.split('.'),
    treatMissingAsZero: true,
  );
  if (coreCmp != 0) {
    return coreCmp;
  }

  final String? aPre = aDash == -1 ? null : a.substring(aDash + 1);
  final String? bPre = bDash == -1 ? null : b.substring(bDash + 1);
  if (aPre == null && bPre == null) {
    return 0;
  }
  if (aPre == null) {
    return 1;
  }
  if (bPre == null) {
    return -1;
  }
  return _compareDotSegments(
    aPre.split('.'),
    bPre.split('.'),
    treatMissingAsZero: false,
  );
}

int _compareDotSegments(
  List<String> aParts,
  List<String> bParts, {
  required bool treatMissingAsZero,
}) {
  final int maxLen = aParts.length > bParts.length
      ? aParts.length
      : bParts.length;
  for (int i = 0; i < maxLen; i++) {
    if (i >= aParts.length) {
      if (treatMissingAsZero && int.tryParse(bParts[i]) == 0) {
        continue;
      }
      return -1;
    }
    if (i >= bParts.length) {
      if (treatMissingAsZero && int.tryParse(aParts[i]) == 0) {
        continue;
      }
      return 1;
    }
    final String aPart = aParts[i];
    final String bPart = bParts[i];
    final int? aNum = int.tryParse(aPart);
    final int? bNum = int.tryParse(bPart);
    if (aNum != null && bNum != null) {
      if (aNum != bNum) {
        return aNum.compareTo(bNum);
      }
      continue;
    }
    final int lexical = aPart.compareTo(bPart);
    if (lexical != 0) {
      return lexical;
    }
  }
  return 0;
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
