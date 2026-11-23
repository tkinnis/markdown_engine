# Contributing to `markdown_engine`

Thank you for contributing to **`markdown_engine`**. This monorepo houses a pure-Dart CommonMark `0.31.2` and GitHub Flavored Markdown (`0.29.0.gfm.13`) parser, extension suite, incremental streaming engine, and Flutter rendering package without a WebView or JavaScript runtime.

Before opening an issue or submitting a pull request, review the architectural invariants, setup instructions, and verification gates below.

---

## 1. Core Architectural Invariants

1. **Pure-Dart SDK Boundary**: Everything under `packages/markdown_engine/lib/` must use standard pure-Dart libraries (`dart:core`, `dart:collection`, `dart:convert`, `dart:math`, `dart:typed_data`) with `dependencies:` restricted strictly to `meta: ^1.16.0`. Never import `flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*` inside the core package.
2. **Dart `^3.8.0` Compatibility**: Keep both `packages/markdown_engine` and `packages/markdown_engine_flutter` compatible with Dart `^3.8.0` and Flutter `>=3.32.0`. Never use Dart 3.12+ private named-parameter shorthands (`this._field`); use explicit initializer lists (with `// ignore: prefer_initializing_formals` where needed).
3. **Flutter `3.50+` Import Scoping**: Inside `packages/markdown_engine_flutter/lib/`, import `package:flutter/widgets.dart` and scope any `package:flutter/material.dart` imports with explicit `show` clauses and `// ignore: deprecated_member_use`.
4. **CommonMark & GFM Spec Parity**: Core syntax and GFM extensions target the pinned `CommonMark 0.31.2` and `github/cmark-gfm 0.29.0.gfm.13` fixtures vendored in `corpus/spec/` and tracked in [`REFERENCE.md`](REFERENCE.md).
5. **Lockstep Package Versioning**: `packages/markdown_engine` and `packages/markdown_engine_flutter` share identical versions across both `pubspec.yaml` files, both changelogs, and the core dependency constraint, verified by `tool/check_versions.dart`.

---

## 2. Development Setup

### Prerequisites

* **Flutter & Dart SDK**: Flutter `>=3.32.0` with Dart `^3.8.0` for `packages/markdown_engine` and `packages/markdown_engine_flutter` (full `pub` workspace resolution including `studio/` requires Flutter `>=3.47.0` and Dart `^3.13.0`).

### Installing Dependencies

```bash
git clone https://github.com/tkinnis/markdown_engine.git
cd markdown_engine
flutter pub get
```

---

## 3. Quality Gates & Verification

Every pull request must pass all repository formatting, static analysis, test, spec, and reference checks:

### Code Formatting & Static Analysis

```bash
dart format --output=none --set-exit-if-changed packages tool studio
dart analyze --fatal-infos
```

### Package, Example & Studio Test Suites

```bash
(cd packages/markdown_engine && dart test && dart run example/main.dart && dart doc --dry-run)
(cd packages/markdown_engine_flutter && flutter test && dart doc --dry-run)
(cd packages/markdown_engine_flutter/example && flutter test)
(cd studio && flutter test)
```

### Version, Reference, Spec & Benchmark Gates

```bash
dart run tool/check_versions.dart
dart run tool/sync_reference.dart --verify
dart run tool/verify_spec.dart
dart run tool/benchmark_suite.dart --check-regressions
```

---

## 4. Commit Message & Pull Request Guidelines

We follow the [**Conventional Commits**](https://www.conventionalcommits.org/) specification:

| Prefix | Usage |
| :--- | :--- |
| `feat(scope): ...` | New CommonMark/GFM rules, AST nodes, extensions, streaming support, or Flutter widget capabilities. |
| `fix(scope): ...` | Bug fixes in block/inline parsing, HTML/text export, sanitization, streaming diffing, or Flutter rendering. |
| `docs(scope): ...` | Documentation, dartdoc comments, coverage or benchmark reports, and reference updates. |
| `refactor(scope): ...` | Internal restructuring without behavioral changes. |
| `test(scope): ...` | Unit, widget, spec, security, or streaming test additions. |
| `chore(scope): ...` | Workspace config, CI workflows, dependency updates, or tooling scripts. |

When submitting a pull request:

1. Keep changes focused on a single concern.
2. Add unit, widget, spec, or security tests covering any bug fix or new capability.
3. Omit automated tool credits, trailer attributions, or synthetic author tags from commit messages and pull request descriptions.
4. Keep Markdown prose paragraphs on a single line with no hard-wrapped line breaks inside paragraphs.

---

## 5. Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold its standards.
