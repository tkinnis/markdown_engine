## Summary

<!-- Briefly describe what this pull request changes and why. -->

Fixes #<!-- issue number, if applicable -->

## Scope

- [ ] **Core Parser / AST / Exporters / Streaming (`packages/markdown_engine`)**
- [ ] **CommonMark / GFM Spec Parity & Security (`corpus/`, `tool/verify_spec.dart`)**
- [ ] **Flutter Widgets, Slivers, HTML Blocks & Built-In Math/Mermaid (`packages/markdown_engine_flutter`)**
- [ ] **Studio (`studio/`) / Tooling (`tool/`) / Documentation (`doc/`)**

## Quality Gate Checklist

- [ ] `dart format --output=none --set-exit-if-changed packages tool studio` passes.
- [ ] `dart analyze --fatal-infos` reports 0 issues across the workspace (and in `tool/compare`).
- [ ] `dart test` passes in `packages/markdown_engine`, and `dart run example/main.dart` plus `dart doc --dry-run` succeed.
- [ ] `flutter test` passes in `packages/markdown_engine_flutter`, `packages/markdown_engine_flutter/example`, and `studio`, and `dart doc --dry-run` succeeds in `packages/markdown_engine_flutter`.
- [ ] `dart run tool/check_versions.dart`, `dart run tool/sync_reference.dart --verify`, `dart run tool/verify_spec.dart --strict`, and `dart run tool/benchmark_suite.dart --check-regressions` pass.
- [ ] Pure-Dart boundary preserved (`packages/markdown_engine/lib/` contains no `package:flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*` imports).
