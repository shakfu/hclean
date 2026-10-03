# TODO

Open work for hclean, roughly in priority order. Items marked **confirmed** were reproduced against the current build.

## Critical

## High

## Medium

### Known issues

- [ ] **JSON with a non-UTF-8 file name is invalid.** The name's bytes are copied as they are. Escaping them as U+FFFD, as cclean does, would keep the document valid at the cost of a lossy path.

### Improvements

- [ ] **Glob patterns cannot escape a metacharacter.** There is no way to match a literal `*`, `?` or `[`, because `\` is normalised to `/` so that Windows-style patterns work. Either pick a different escape character or make `\` an escape outside of path separators.

- [ ] **Config file covers only part of the options.** `older_than`, the output format, `quiet` and `no_protect` have no key, so a config file cannot express everything the command line can.

- [ ] **The version string lives in two places** — `versionText` in `app/CLI.hs` and `version:` in `hclean.cabal` — and will drift. Use the generated `Paths_hclean` module instead.

- [ ] **Text output has no total.** `--stats` reports per-pattern counts and sizes; the JSON report also carries `total_count` and `total_size`. A closing total line would make the two agree.

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
