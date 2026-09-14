# TODO

Open work for hclean, roughly in priority order. Items marked **confirmed** were reproduced against the current build.

## Critical

## High

### Known issues

- [ ] **A failed removal aborts the run** — confirmed. The first `removeFile` or `removePathForcibly` that throws (a read-only parent directory, for instance) escapes to the top level, so the remaining targets are never removed, the error is printed with a `HasCallStack` backtrace, and the run exits 1. The JSON report's `failures` array exists for exactly this and is always empty. Removal should collect per-target failures, keep going, report them in both output formats, and exit non-zero once at the end.

  ```sh
  mkdir -p t/ro/__pycache__ t/rw/__pycache__ && chmod a-w t/ro
  hclean -p t -y   # t/rw/__pycache__ survives
  ```

- [ ] **Filenames that are not valid UTF-8 crash the output** — confirmed. The scan finds them, but printing one throws `<stdout>: commitBuffer: invalid argument (cannot encode character …)` part-way through a line, and the run exits 1. Setting the standard handles to a transliterating or surrogate-escaping encoding at startup would fix it.

  ```sh
  mkdir -p t/d && touch t/d/$'\xff\xfe.pyc' && hclean -p t -d -g '**/*.pyc'
  ```

## Medium

### Known issues

- [ ] **Uncaught exceptions print a backtrace.** Any I/O error that reaches the top level shows GHC's `HasCallStack` frames, which is noise for a command line tool. A top-level handler should print `hclean: <message>` and exit non-zero.

### Improvements

- [ ] **Glob patterns cannot escape a metacharacter.** There is no way to match a literal `*`, `?` or `[`, because `\` is normalised to `/` so that Windows-style patterns work. Either pick a different escape character or make `\` an escape outside of path separators.

- [ ] **Config file covers only part of the options.** `older_than`, the output format, `quiet` and `no_protect` have no key, so a config file cannot express everything the command line can.

- [ ] **`--path` cannot override a config file's `path`.** `optRoot` has no way to distinguish an explicit `--path .` from the default, so the file wins. Making it a `Maybe FilePath` in `HClean.Types` would settle the precedence properly.

- [ ] **The version string lives in two places** — `versionText` in `app/CLI.hs` and `version:` in `hclean.cabal` — and will drift. Use the generated `Paths_hclean` module instead.

- [ ] **Text output has no total.** `--stats` reports per-pattern counts and sizes; the JSON report also carries `total_count` and `total_size`. A closing total line would make the two agree.

- [ ] **No coverage of the executable's own wiring.** The library and the argument parser are tested, but prompting, deletion and exit codes are only exercised by hand. A golden test that drives the built binary would close the gap.

- [ ] **No CI.** Nothing runs `cabal test` on push.

## Low

### Improvements

- [ ] **Terminal width is guessed.** The activity indicator reads `COLUMNS` and otherwise assumes 80 columns, because neither `unix` nor `base` exposes `TIOCGWINSZ`. A small FFI binding would let it fill the real width and react to `SIGWINCH`.

- [ ] **The indicator is untested on a terminal.** `test/ProgressSpec.hs` covers the line rendering and the non-terminal paths; the live painting is only verified by hand under `script -qec`. A pty-driven test would close that gap.

## Considered and declined

Recorded so they are not raised again without new evidence.

- **Parallel directory scanning.** The walk is I/O bound and the output order is deliberately deterministic; concurrency would mean a hand-rolled scheduler (the project takes no dependencies) plus a sorting pass, for no measured gain. Revisit only with a profile showing the walk is the bottleneck.

- **Circular symlink detection.** Not needed: the walk recurses only into an entry that is a directory *and* not a symlink, so a link loop cannot make it diverge. Covered by a regression test in `test/ScanSpec.hs`.

- **A SIGINT handler.** The RTS already turns an interrupt into an abort with a non-zero exit, and a handler cannot make a partially removed directory tree whole, so it would add nothing.

- **Escaping non-ASCII in JSON.** Unnecessary — any character above `U+001F` other than `"` and `\` is legal unescaped in a UTF-8 JSON document. Control characters are escaped as `\uXXXX`.
