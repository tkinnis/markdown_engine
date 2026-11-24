# Release Guide

`markdown_engine` and `markdown_engine_flutter` share strict **lockstep semantic versioning** (X.Y.Z or X.Y.Z-pre). Every release updates both packages together, passes every workspace quality gate, creates a matching `vX.Y.Z` tag, and publishes `markdown_engine` to pub.dev before `markdown_engine_flutter`.

---

## 1. Lockstep Versioning Contract

`tool/check_versions.dart` enforces synchronization across five publishable metadata locations and checks internal workspace constraints on every CI run and release tag:

* `packages/markdown_engine/pubspec.yaml`: `version: X.Y.Z`
* `packages/markdown_engine_flutter/pubspec.yaml`: `version: X.Y.Z`
* `packages/markdown_engine_flutter/pubspec.yaml`: `dependencies.markdown_engine: ^X.Y.Z`
* `packages/markdown_engine/CHANGELOG.md`: top heading `## X.Y.Z`
* `packages/markdown_engine_flutter/CHANGELOG.md`: top heading `## X.Y.Z`
* Root, Studio, and example pubspecs: internal `markdown_engine` and `markdown_engine_flutter` dependencies pinned to `any`

This keeps every `markdown_engine_flutter` release bound to the matching `^X.Y.Z` release of `markdown_engine` without skew. [`REFERENCE.md`](../REFERENCE.md), package READMEs, and `publish_to: none` workspace pubspecs avoid duplicating release version numbers.

---

## 2. Pre-Release Checklist

### Step 1: Bump Lockstep Version Metadata

1. Update the lockstep `version:` field in both package pubspecs to `X.Y.Z`.
2. Update `markdown_engine: ^X.Y.Z` in `packages/markdown_engine_flutter/pubspec.yaml` (keeping `any` in the root, Studio, and example pubspecs).
3. Prepend a matching release section to [`packages/markdown_engine/CHANGELOG.md`](../packages/markdown_engine/CHANGELOG.md) and [`packages/markdown_engine_flutter/CHANGELOG.md`](../packages/markdown_engine_flutter/CHANGELOG.md) summarizing user-visible changes.
4. Run `flutter pub get` at the repository root to refresh workspace resolution.

### Step 2: Run All Verification Gates

Execute the full workspace verification suite from the repository root and confirm zero errors, warnings, or info diagnostics:

```bash
dart format --output=none --set-exit-if-changed packages tool studio
dart analyze --fatal-infos
(cd packages/markdown_engine && dart test && dart run example/main.dart && dart doc --dry-run)
(cd packages/markdown_engine_flutter && flutter test && dart doc --dry-run)
(cd packages/markdown_engine_flutter/example && flutter test)
(cd studio && flutter test)
dart run tool/check_versions.dart
dart run tool/check_versions.dart --tag "vX.Y.Z"
dart run tool/sync_reference.dart --verify
dart run tool/verify_spec.dart --strict
dart run tool/benchmark_suite.dart --check-regressions
```

### Step 3: Validate `pub publish --dry-run`

Run dry-run publishing validation for both publishable packages:

```bash
(cd packages/markdown_engine && dart pub publish --dry-run)
(cd packages/markdown_engine_flutter && flutter pub publish --dry-run)
```

Confirm both packages pass with zero errors or warnings across package metadata, `.pubignore` exclusions, examples, and license files. On package PRs and release tags, `.github/workflows/ci.yml` enforces the matching dry-run publish and `dart doc --dry-run` checks.

---

## 3. Tagging & Publishing Order

Because `markdown_engine_flutter` depends on `markdown_engine: ^X.Y.Z`, **`markdown_engine` MUST be published to pub.dev before `markdown_engine_flutter`**.

### Step 1: Commit & Tag `vX.Y.Z`

1. Commit release metadata changes using Conventional Commits (for example `chore(release): prepare vX.Y.Z`).
2. Create an annotated git tag matching the lockstep version and verify it locally:

```bash
git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
dart run tool/check_versions.dart --tag "vX.Y.Z"
```

3. Push the release commit and tag `vX.Y.Z` so `.github/workflows/ci.yml` runs the full CI suite against `--tag vX.Y.Z`.

### Step 2: Publish `packages/markdown_engine` First

Once CI passes on the tagged commit, publish the pure-Dart core package first:

```bash
(cd packages/markdown_engine && dart pub publish)
```

Confirm `markdown_engine` version `X.Y.Z` is resolved and listed on pub.dev before continuing to Step 3.

### Step 3: Publish `packages/markdown_engine_flutter` Second

After `markdown_engine` `X.Y.Z` is live on pub.dev, re-run `flutter pub publish --dry-run` inside `packages/markdown_engine_flutter` and publish:

```bash
(cd packages/markdown_engine_flutter && flutter pub publish --dry-run)
(cd packages/markdown_engine_flutter && flutter pub publish)
```

---

## 4. Post-Release Verification

* Confirm both package pages on pub.dev display matching `X.Y.Z` versions, complete READMEs, generated API documentation, and MIT license metadata.
* Verify the Docsify portal built by `.github/workflows/pages.yml` renders updated changelogs, [`doc/COVERAGE.md`](COVERAGE.md), and [`doc/BENCHMARKS.md`](BENCHMARKS.md).
