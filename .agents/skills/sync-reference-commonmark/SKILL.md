---
name: sync-reference-commonmark
description: Verifies or refreshes pinned CommonMark and github/cmark-gfm specification fixtures under corpus/spec/, updates SHA-256 digests in REFERENCE.md, regenerates doc/COVERAGE.md and refreshes doc/BENCHMARKS.md, and validates all workspace quality gates.
---

# Sync Reference CommonMark & GFM Skill (`sync-reference-commonmark`)

Use this skill whenever verifying vendored CommonMark or `cmark-gfm` specification fixtures, checking for upstream spec revisions, updating `REFERENCE.md` hashes, or refreshing `doc/COVERAGE.md` and `doc/BENCHMARKS.md`.

---

## 1. Check Reference Integrity

Run the reference verifier from the repository root:

```bash
dart run tool/sync_reference.dart --verify
```

* `--verify` checks that `corpus/spec/commonmark_0.31.2.json`, `corpus/spec/gfm_0.29.0_spec.txt`, and `corpus/spec/gfm_0.29.0_extensions.txt` match the exact SHA-256 digests and pinned versions recorded in [`REFERENCE.md`](../../../REFERENCE.md).

---

## 2. Refresh Vendored Spec Fixtures & Compute Hashes

When updating to a new CommonMark or `cmark-gfm` release:

1. Download the updated spec JSON and `cmark-gfm` test files into `corpus/spec/`:
   ```bash
   curl -fsSL https://spec.commonmark.org/<VERSION>/spec.json -o corpus/spec/commonmark_<VERSION>.json
   curl -fsSL https://raw.githubusercontent.com/github/cmark-gfm/<TAG>/test/spec.txt -o corpus/spec/gfm_<VERSION>_spec.txt
   curl -fsSL https://raw.githubusercontent.com/github/cmark-gfm/<TAG>/test/extensions.txt -o corpus/spec/gfm_<VERSION>_extensions.txt
   ```
2. Compute SHA-256 digests for each downloaded fixture:
   ```bash
   shasum -a 256 corpus/spec/*
   ```
3. Update `tool/verify_spec.dart` and `tool/sync_reference.dart` if filenames or spec metadata keys changed.

---

## 3. Update `REFERENCE.md`, Coverage & Multi-Suite Benchmark Docs

1. Update [`REFERENCE.md`](../../../REFERENCE.md) with the new pinned versions, upstream tag/source URLs, example counts, and lowercase SHA-256 digests.
2. Regenerate [`doc/COVERAGE.md`](../../../doc/COVERAGE.md) (preserving its `<IGNORE>` crash-regression note afterward) and `tool/benchmark_baseline.json`, then run all four head-to-head and profile benchmark suites on an idle host to update [`doc/BENCHMARKS.md`](../../../doc/BENCHMARKS.md). **Do NOT pass `--update-docs` to `tool/benchmark_suite.dart`**, as `--update-docs` overwrites the multi-suite `doc/BENCHMARKS.md` with standalone AOT-only tables:
   ```bash
   dart run tool/verify_spec.dart --strict --update-coverage
   dart run tool/benchmark_suite.dart --update-baseline --check-regressions --json

   (cd tool/compare && flutter pub get)
   dart compile exe tool/compare/bin/compare_parsers_aot.dart -o /tmp/compare_parsers.exe
   /tmp/compare_parsers.exe --json
   rm -f /tmp/compare_parsers.exe

   (cd tool/compare && flutter test --no-pub test/compare_flutter_bench_test.dart)
   (cd tool/compare && flutter test --no-pub test/mermaid_worker_bench_test.dart)
   dart run tool/run_macos_profile_benchmark.dart --no-pub --timeout=180
   ```
3. Update `README.md`, `packages/markdown_engine/README.md`, and `packages/markdown_engine_flutter/README.md` if coverage or benchmark tables changed.

---

## 4. Run Full Verification Gates

Before committing, verify every workspace gate passes with zero errors, warnings, or infos:

```bash
dart format --output=none --set-exit-if-changed packages tool studio
dart analyze --fatal-infos
(cd packages/markdown_engine && dart test && dart run example/main.dart && dart doc --dry-run)
(cd packages/markdown_engine_flutter && flutter test && dart doc --dry-run)
(cd packages/markdown_engine_flutter/example && flutter test)
(cd studio && flutter test)
dart run tool/check_versions.dart
dart run tool/sync_reference.dart --verify
dart run tool/verify_spec.dart --strict
dart run tool/benchmark_suite.dart --check-regressions
```

Confirm local git author configuration uses `tkinnis <219582735+tkinnis@users.noreply.github.com>` and commit using Conventional Commits without automated tool attributions.
