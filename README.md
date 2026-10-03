# hclean

Dependency-free Haskell command-line utility for recursively cleaning development detritus.

A port of `rclean` that keeps its safe defaults: protected directories, dry-run support, confirmation before deletion, symlink guards, age filtering, build-artifact detection, configuration discovery, statistics and JSON output. It uses only GHC's standard library packages (`base`, `directory`, `filepath`, `time` and `unix`).

## Building

```sh
cabal build        # or: make
```

`make` produces the `hclean` executable in the project root; `cabal build` places it under `dist-newstyle/`. Run the tests with `make test` (or `cabal test`).

## Usage

```sh
hclean --dry-run
hclean --glob '**/*.log' --skip-confirmation
hclean --preset node --dry-run
```

Run `hclean --help` for the full option list.

Matches are printed on stdout. The confirmation prompt (`Delete N item(s)? [y/N]`) goes to stderr, so stdout carries only the report; end of input answers no. With `--format json` the report is printed after removal, and its `failures` array lists every target that could not be removed. A failed removal does not stop the run: hclean removes what it can, names each failure, then exits 1. Directory sizes are measured only for `--stats` and JSON output.

After removal, a `Removed N item(s), SIZE.` line reports the bytes actually freed; `-q` suppresses it. In JSON these are `freed_size` and `freed_size_human` in `summary`. Sizes are apparent sizes (`st_size`), not disk blocks.

While scanning or removing, hclean shows an activity indicator on stderr — a spinner, a running count and the path it is currently looking at:

```
| scanning, 32519 entries  .../app/node_modules/simple-get/package.json
```

It appears only when stderr is a terminal and only once the work has run for a quarter of a second, so quick runs and piped output stay clean, and it is erased before the results are printed. `--progress` forces reporting on even when stderr is not a terminal, where it prints a single `scanned N entries` line at the end; `--no-progress` turns it off entirely.

Release notes are in [CHANGELOG.md](CHANGELOG.md); known issues and planned work are in [TODO.md](TODO.md).

## Layout

The project is split into a library and a thin command-line front end:

```
src/HClean.hs          re-exports the library
src/HClean/Types.hs    Options, OutputFormat, Target
src/HClean/Glob.hs     glob matching and validation
src/HClean/Preset.hs   named pattern sets, protected directories
src/HClean/Scan.hs     directory walking, build-artifact detection, sizes
src/HClean/Report.hs   summaries, text and JSON rendering
src/HClean/Delete.hs   removal
src/HClean/Config.hs   .hclean.toml reading, discovery and writing
src/HClean/Util.hs     duration parsing and other small helpers
app/CLI.hs             argument parsing and help text
app/Progress.hs        the stderr activity indicator
app/Main.hs            wiring, prompting and exit codes
test/                  test suite (a small dependency-free harness)
```

The library never reads `argv`, prompts, or exits; those belong to the executable, so the scanning and reporting code can be reused or tested directly.

## Patterns

Patterns are matched against paths relative to the scan root. A pattern with no slash matches a basename anywhere in the tree; `**` spans any number of directories; within one path segment `*` matches any run of characters, `?` matches one, and `[abc]`, `[a-z]`, `[!abc]` match a character class. A directory that matches is removed whole and is not descended into. An unterminated or empty class (`[abc`, `x[]y`) is rejected, in excludes as well as includes.

## Build artifacts

`-B` matches build output directories (`build`, `dist`, `target`, `.next`, `_build`, `zig-out` and others). A directory matches only when the project marker that produces it (`Cargo.toml`, `package.json`, `mix.exs`, ...) sits beside it, and a `.git` exists in that directory or an ancestor below the home directory. The ancestor rule covers workspace members such as `crates/foo/target`; the home boundary keeps a dotfiles repository in `~` from qualifying every project under it.

## Configuration

`hclean -c` reads `.hclean.toml` from the working directory or the nearest ancestor that has one, falling back to the global `hclean/config.toml` under `$XDG_CONFIG_HOME`, or under `~/.config` when that is unset or relative. The search stops below the home directory, so a `.hclean.toml` in `~` or above it is never read; user-wide settings belong in the global file. Only one file is read per run, and files are not merged. `hclean -c FILE` reads a specific file; without `-c`, no configuration is read.

```toml
path = "."
patterns = ["**/__pycache__", "**/*.pyc"]
exclude_patterns = ["**/vendor"]
presets = ["python", "node"]
dry_run = false
skip_confirmation = false
stats_mode = false
include_symlinks = false
remove_broken_symlinks = false
build_artifacts = false
```

The reader accepts top-level keys with string, boolean and string-array values, and `#` comments. Reading stops at the first table header. Unknown keys are ignored; a known key with a value of the wrong type is an error.

Precedence: a list given on the command line (`--glob`, `--exclude`, `--preset`) replaces the file's list entirely rather than adding to it; a boolean set on the command line cannot be switched off by the file; and `--path` overrides the file's `path`.

A relative `path` is resolved against the directory holding the file, so `path = "."` scans that directory wherever hclean is run from beneath it. The global file belongs to no tree, so its relative `path` is resolved against the working directory.

## Known limitations

- JSON output copies file-name bytes as they are, so a name that is not valid UTF-8 produces invalid JSON. Text output prints such names as their original bytes.
