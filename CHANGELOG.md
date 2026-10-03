# Changelog

All notable changes to hclean are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Fixes backported from [oclean](https://github.com/shakfu/oclean), each with a regression test.

### Added

- After removal, a `Removed N item(s), SIZE.` line reports the bytes freed, and JSON `summary` carries `freed_size` and `freed_size_human`. A target's bytes are its size before removal minus what a failed removal left, so the figure excludes failures and `removePathForcibly` still clears read-only subdirectories. This costs one walk per removed target.

### Fixed

- `-w` checked for the file and then wrote it, so a dangling symlink named `.hclean.toml` was followed and its target created. The file is now created with `O_EXCL`, which refuses any existing path.

- A failed removal aborted the run: later targets were left in place and a `HasCallStack` backtrace was printed. hclean now removes what it can, names each failure on stderr or in the JSON `failures` array (previously always empty), and exits 1.

- A file name that is not valid UTF-8 threw `commitBuffer: invalid argument` part-way through the listing. stdout and stderr now use the file system encoding, which writes such names back as their original bytes.

- Bare `-c` never searched above the working directory. Discovery started from `.`, and `takeDirectory "."` is `.`, so it went straight to the global file.

- `-B` required `.git` beside the build directory, so workspace members such as `crates/foo/target` never matched. A `.git` in an ancestor now qualifies, up to but not including the home directory: a home directory kept under git (dotfiles) would otherwise have qualified every project beneath it.

- `-r` ignored `--older-than` and removed dangling links of any age.

- `-l` ignored `--glob` and printed the defaults.

- The confirmation prompt went to stdout, which corrupted JSON output, and under `-q` it asked about a list it had not shown. It now goes to stderr and states the count: `Delete N item(s)? [y/N]`. End of input answers no instead of throwing.

- Config keys were matched by prefix, so `path_style = "x"` set `path`. Inline comments became part of the value, and a value of the wrong type was read as false or empty. Keys now match exactly, `#` comments are stripped, reading stops at the first table header, and type errors are reported. Literal (`'...'`) strings and the escapes `\"`, `\\`, `\n`, `\t`, `\r` are accepted.

- `--path` could not override a config file's `path`, because an explicit `--path .` was indistinguishable from the default. `optRoot` is now a `Maybe FilePath`.

- Glob matching was exponential in the number of `*`: `*a` x14 then `*b` against a 201-character name ran past 10 s, and now takes 20 ms.

- `x[]y` and `[!]` were accepted and matched nothing. They are now rejected. Excludes were not validated at all, so an exclude with a broken class silently protected nothing; they are now checked like includes.

- Every run measured matched directories, a second walk of each match. Sizes are now measured only for `--stats` and JSON output.

- `scan` with a relative base dropped leading segments from relative paths (`relativeTo "." "./foo/bar"` is `bar`), so anchored patterns and excludes failed for library callers. Relative paths are now built during the walk.

- `make` failed when a GHC environment file (`~/.ghc/<arch>-<os>-<ver>/environments/default`) hid `directory` or `filepath`, though `cabal build` succeeded. The Makefile now ignores environment files and exposes only the five `build-depends` packages, so an import missing from `hclean.cabal` fails under `make` too.

### Changed

- The config file is `.hclean.toml`, and the global file is `hclean/config.toml` under the XDG config directory. hclean read rclean's `.rclean.toml`, which rclean 0.5 no longer uses; a name of its own keeps hclean from reading a file written for another tool. Rename existing files.

- The global config file honours `XDG_CONFIG_HOME`: it is `$XDG_CONFIG_HOME/hclean/config.toml` when that is absolute, else `~/.config/hclean/config.toml` as before.

- The `common` and `python` presets, and so the defaults, no longer include `.bash_history` or `.python_history`. Shell and REPL history is user data that nothing rebuilds; remove it with `-g '**/.bash_history'` if wanted.

- A relative `path` in a config file is resolved against the file's directory, not the working directory. Before, `path = "."` in a discovered `.hclean.toml` scanned whichever subdirectory hclean ran from. The global file keeps resolving against the working directory, since a `path = "."` there would otherwise always scan `~/.config/hclean`.

- Bare `-c` no longer reads a `.hclean.toml` in the home directory or above it. With the file-relative `path` above, a `~/.hclean.toml` holding `path = "."` would have scanned all of `~` from any directory under it that has no closer `.hclean.toml`.

- `-w` writes `.hclean.toml` into `--path` instead of the working directory, and fails with `invalid path` when that is not a directory.

- Every fatal message starts with `hclean: `. I/O errors that reach the top level are caught and printed the same way. GHC 9.6 already prints them so; GHC 9.10 and later would add a backtrace.

- Library API: `resolveConfig` and `applyConfig` return `Either String Options`; `summarize` takes a flag saying whether to measure directories; `renderJson` takes the failures and the bytes freed; `removeTargets` takes a per-target action and returns the failures and the bytes freed; `removePath` returns the error instead of throwing.

- The test suite goes from 74 to 114 tests. `test/MainSpec.hs` drives the built binary, which cabal puts on `PATH` through `build-tool-depends`.

- CI runs `make test` and `make` on Linux and macOS. Linux runs the non-UTF-8 file name test, which APFS cannot host.

## [0.1.0] - 2026-08-31

First release: a dependency-free Haskell port of `rclean` that recursively removes development detritus. It uses only GHC's standard library packages (`base`, `directory`, `filepath`, `time`, `unix`).

The **Changed** and **Fixed** entries below are relative to the pre-release single-file prototype (commit `4e98d49`), for anyone who built from it.

### Added

- Recursive scanning that matches glob patterns against paths relative to the scan root. A pattern without a slash matches a basename anywhere in the tree, `**` spans any number of directories, and within a segment `*`, `?` and character classes (`[abc]`, `[a-z]`, `[!abc]`, `[^abc]`) are supported. A matching directory is removed whole and is not descended into.

- Safety defaults: protected directories (`.git`, `.hg`, `.svn`, `.config`, `.ssh`, `.gnupg`) are never entered, symlinks are skipped unless requested, symlinked directories are never followed, and deletion is confirmed interactively unless `--skip-confirmation` is given.

- `--dry-run` to preview matches without removing anything.

- Presets of ready-made patterns — `common`, `python`, `node`, `rust`, `java`, `c`, `go` and `all` — selected with `--preset` and listable with `--list`. Preset names are matched without regard to case.

- `--build-artifacts`, which removes build output directories (`build`, `dist`, `target`, `.next`, `.gradle`, `zig-out`, `_build` and others) only when the project marker that produces them (`Cargo.toml`, `package.json`, `CMakeLists.txt`, `mix.exs`, …) sits beside them inside a git repository.

- `--older-than` age filtering with `s`, `m`, `h`, `d` and `w` units.

- `--include-symlinks` and `--remove-broken-symlinks`.

- `--exclude` patterns that prune the walk, and `--no-protect` to disable the protected-directory list.

- `--stats` for per-pattern counts and sizes, and `--quiet` to suppress the match listing.

- `--format json` output with matches, totals, per-pattern statistics and a `failures` array.

- Configuration through `.rclean.toml`: `--configfile PATH` reads one file, bare `--configfile` searches the working directory and its ancestors and then `~/.config/rclean/config.toml`. Supported keys are `path`, `patterns`, `exclude_patterns`, `presets`, `dry_run`, `skip_confirmation`, `stats_mode`, `include_symlinks`, `remove_broken_symlinks` and `build_artifacts`. Command line options take precedence; see the README for the exact rules.

- `--write-configfile` to write a starter `.rclean.toml`, which refuses to overwrite an existing file.

- An activity indicator on stderr — a spinner, a running count and the path being visited — shown while scanning, measuring and removing. It appears only when stderr is a terminal and only after a quarter of a second of work, and is erased before results are printed, so quick runs and piped output are untouched. `--progress` forces it on, printing a single `scanned N entries` line when stderr is not a terminal; `--no-progress` disables it.

- `--verbose`, which logs the scan root, the patterns in use, every match and every removal to stderr, interleaved with the indicator without either overwriting the other.

- A test suite (`cabal test` or `make test`) with 65 tests and its own small harness, so it adds no dependencies.

### Changed

- Split the single-file implementation into a library and a command line front end. `src/HClean/*` provides globbing, presets, scanning, reporting, configuration and deletion, and never reads `argv`, prompts, or exits; `app/` holds argument parsing, the help text, prompting and exit codes.

- `Target` records whether a match is a directory instead of carrying a `FileStatus`, which makes the reporting code usable without touching disk.

- `scanWith` accepts `ScanHooks` so a front end can observe entries and matches as they are found; `scan` keeps the previous behaviour.

- `--version` prints to stdout instead of stderr.

- Error messages name the offending value: `unknown preset 'nope' (…)` and `invalid glob pattern: **/[unclosed`.

- `--help` documents `--configfile`, `--quiet`, `--verbose`, `--progress`, `--help` and `--version`, which were accepted but undocumented.

- `--verbose` and `--progress` now have an effect; they were previously parsed and ignored.

- Configuration files are read strictly, so the handle does not stay open for the life of the process.

- A malformed duration distinguishes a missing unit from an unknown one.

- `make` builds through `-isrc -iapp` into `build/` instead of leaving object files beside the sources.

### Fixed

- `--older-than` read the digits of a duration backwards, so `30m` meant three minutes and `12h` meant twenty-one hours.

- Sizes of 1 KiB and above were rendered as `4..8 KiB` instead of `4.88 KiB`, in both text and JSON output.

- Quoted scalars in `.rclean.toml` kept their quotes, so `path = "."` failed with `invalid path: "."` — the `path` key never worked.

- Answering the deletion prompt with `Y` was treated as "no".

- JSON output emitted raw control characters, which could produce a document no parser would accept; they are now escaped as `\uXXXX`.

- `--preset` accepted only lowercase names.

- Removed a dead `isRoot` parameter in the scanner and an always-empty `defaultExcludes` list.

[0.1.0]: https://github.com/shakfu/hclean/releases/tag/v0.1.0
