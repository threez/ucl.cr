# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Bumped the `ameba` dev dependency from `~> 1.6.0` to `~> 1.7.0` and fixed the
  resulting lint violations (`Style/MultilineStringLiteral`,
  `Style/VerboseNilType`, `Style/HeredocIndent`, `Lint/WhitespaceAroundMacroExpression`,
  `Style/RedundantSelf`, `Lint/SpecEqWithBoolOrNilLiteral`, `Style/RedundantBegin`,
  `Style/PercentLiteralDelimiters`).
- Restructured CI into a `lint` job (format check, ameba, compile check) and a
  `test` job (ubuntu + macos matrix) that depends on it, pinned Crystal to
  `1.20.2`, and added shard caching.
- `Makefile`: `lib/ameba/bin/ameba` now runs `shards build ameba` after
  `shards install`, since ameba 1.7.0 no longer builds its binary via a
  `postinstall` hook.

## [0.1.1]

- Initial tracked release.
