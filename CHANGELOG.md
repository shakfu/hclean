# Changelog

All notable changes to hclean are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-31

First release: a dependency-free Haskell port of `rclean` that recursively
removes development detritus. It uses only GHC's standard library packages
(`base`, `directory`, `filepath`, `time`, `unix`).

The **Changed** and **Fixed** entries below are relative to the pre-release
single-file prototype (commit `4e98d49`), for anyone who built from it.

### Added

- Recursive scanning that matches glob patterns against paths relative to the
  scan root. A pattern without a slash matches a basename anywhere in the tree,
  `**` spans any number of directories, and within a segment `*`, `?` and
  character classes (`[abc]`, `[a-z]`, `[!abc]`, `[^abc]`) are supported. A
  matching directory is removed whole and is not descended into.
- Safety defaults: protected directories (`.git`, `.hg`, `.svn`, `.config`,
  `.ssh`, `.gnupg`) are never entered, symlinks are skipped unless requested,
  symlinked directories are never followed, and deletion is confirmed
  interactively unless `--skip-confirmation` is given.
- `--dry-run` to preview matches without removing anything.
- Presets of ready-made patterns — `common`, `python`, `node`, `rust`, `java`,
  `c`, `go` and `all` — selected with `--preset` and listable with `--list`.
  Preset names are matched without regard to case.
- `--build-artifacts`, which removes build output directories (`build`, `dist`,
  `target`, `.next`, `.gradle`, `zig-out`, `_build` and others) only when the
  project marker that produces them (`Cargo.toml`, `package.json`,
  `CMakeLists.txt`, `mix.exs`, …) sits beside them inside a git repository.
- `--older-than` age filtering with `s`, `m`, `h`, `d` and `w` units.
- `--include-symlinks` and `--remove-broken-symlinks`.
- `--exclude` patterns that prune the walk, and `--no-protect` to disable the
  protected-directory list.
- `--stats` for per-pattern counts and sizes, and `--quiet` to suppress the
  match listing.
- `--format json` output with matches, totals, per-pattern statistics and a
  `failures` array.
- Configuration through `.rclean.toml`: `--configfile PATH` reads one file,
  bare `--configfile` searches the working directory and its ancestors and then
  `~/.config/rclean/config.toml`. Supported keys are `path`, `patterns`,
  `exclude_patterns`, `presets`, `dry_run`, `skip_confirmation`, `stats_mode`,
  `include_symlinks`, `remove_broken_symlinks` and `build_artifacts`.
  Command line options take precedence; see the README for the exact rules.
- `--write-configfile` to write a starter `.rclean.toml`, which refuses to
  overwrite an existing file.
- An activity indicator on stderr — a spinner, a running count and the path
  being visited — shown while scanning, measuring and removing. It appears only
  when stderr is a terminal and only after a quarter of a second of work, and is
  erased before results are printed, so quick runs and piped output are
  untouched. `--progress` forces it on, printing a single `scanned N entries`
  line when stderr is not a terminal; `--no-progress` disables it.
- `--verbose`, which logs the scan root, the patterns in use, every match and
  every removal to stderr, interleaved with the indicator without either
  overwriting the other.
- A test suite (`cabal test` or `make test`) with 65 tests and its own small
  harness, so it adds no dependencies.

### Changed

- Split the single-file implementation into a library and a command line front
  end. `src/HClean/*` provides globbing, presets, scanning, reporting,
  configuration and deletion, and never reads `argv`, prompts, or exits;
  `app/` holds argument parsing, the help text, prompting and exit codes.
- `Target` records whether a match is a directory instead of carrying a
  `FileStatus`, which makes the reporting code usable without touching disk.
- `scanWith` accepts `ScanHooks` so a front end can observe entries and matches
  as they are found; `scan` keeps the previous behaviour.
- `--version` prints to stdout instead of stderr.
- Error messages name the offending value: `unknown preset 'nope' (…)` and
  `invalid glob pattern: **/[unclosed`.
- `--help` documents `--configfile`, `--quiet`, `--verbose`, `--progress`,
  `--help` and `--version`, which were accepted but undocumented.
- `--verbose` and `--progress` now have an effect; they were previously parsed
  and ignored.
- Configuration files are read strictly, so the handle does not stay open for
  the life of the process.
- A malformed duration distinguishes a missing unit from an unknown one.
- `make` builds through `-isrc -iapp` into `build/` instead of leaving object
  files beside the sources.

### Fixed

- `--older-than` read the digits of a duration backwards, so `30m` meant three
  minutes and `12h` meant twenty-one hours.
- Sizes of 1 KiB and above were rendered as `4..8 KiB` instead of `4.88 KiB`,
  in both text and JSON output.
- Quoted scalars in `.rclean.toml` kept their quotes, so `path = "."` failed
  with `invalid path: "."` — the `path` key never worked.
- Answering the deletion prompt with `Y` was treated as "no".
- JSON output emitted raw control characters, which could produce a document no
  parser would accept; they are now escaped as `\uXXXX`.
- `--preset` accepted only lowercase names.
- Removed a dead `isRoot` parameter in the scanner and an always-empty
  `defaultExcludes` list.

[0.1.0]: https://github.com/shakfu/hclean/releases/tag/v0.1.0
