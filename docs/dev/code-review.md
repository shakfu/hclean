# hclean review

Reviewed at commit `05715f3` (v0.1.0), 2026-09-06. GHC 9.6.7, cabal 3.14.2.0, aarch64-darwin.

## Build and test results

| Step | Result |
|-|-|
| `cabal build` | Clean. 12 modules, no warnings under `-Wall -Wcompat -Wincomplete-record-updates`. |
| `cabal test` / `make test` | 74/74 pass. |
| `make` | **Fails on this machine.** See finding 6. Succeeds with a one-flag change. |

All findings below were reproduced against a binary built from this tree.

## Assessment

The module split is correct and the boundary is real, not nominal. `src/HClean/*` takes no `argv`, prints nothing, and calls no `exitWith`; `app/` holds parsing, prompting and exit codes. `HClean.Scan.scanWith` taking `ScanHooks` is the right shape — the progress indicator is a caller concern, and the scanner does not know it exists.

The zero-dependency constraint is honoured and mostly cost-free. The glob matcher (79 lines), the JSON writer (35 lines) and the test harness (103 lines) are each smaller than the dependency they replace. The TOML reader is the exception: it is where the constraint has produced something fragile (finding 7).

Safety defaults are sound: `lstat` throughout, no symlink following, matched directories not descended, protected-name list, confirmation before deletion. The symlink-loop argument in `TODO.md` is correct — `walk` is reached only when `isDir && not link`, so divergence is impossible.

`TODO.md` is unusually honest. Three of the defects I would otherwise have led with are already recorded as confirmed, including the most serious one. The "Considered and declined" section is the right way to record negative decisions. The findings below exclude everything already tracked there; see the last section for the cross-reference.

## Findings

Ordered by severity.

### 1. `--configfile` with no path never searches ancestors (Config.hs:48, 82)

`resolveConfig DiscoverConfig` calls `discoverConfig "."`. The climb terminates after one step, because `takeDirectory "." == "."`:

```
> (normalise ".", takeDirectory ".")
(".",".")
```

So `parent == dir` on the first iteration, `climb` gives up and falls through to `~/.config/rclean/config.toml`. Upward discovery — advertised in `README.md`, in the `--help` text and in the CHANGELOG — does not work from the executable.

```sh
mkdir -p t/nested/deep && printf 'patterns = ["**/*.marker"]\n' > t/.rclean.toml
touch t/nested/deep/x.marker
cd t/nested/deep && hclean -c --dry-run     # prints nothing
hclean -c ../../.rclean.toml --dry-run      # prints x.marker
```

The two discovery tests (`test/ConfigSpec.hs:55,59`) pass `discoverConfig` an absolute path, so they exercise the loop but not the call site. The `resolveConfig` test at line 73 covers `NoConfig` and `ConfigFile` only; `DiscoverConfig` has no test at all. That is why a passing suite coexists with a broken feature.

Fix: `discoverConfig =<< getCurrentDirectory`, or `makeAbsolute` inside `discoverConfig`. Add a `DiscoverConfig` case to the `resolveConfig` test using `withCurrentDirectory`.

### 2. `--build-artifacts` misses every workspace subproject (Scan.hs:76)

`isBuildArtifact` requires `.git` in the *same directory* as the candidate. In a Cargo, Gradle or pnpm workspace, `.git` sits at the repository root and the build output sits under each member.

```sh
mkdir -p t/.git t/crates/foo/target t/target
touch t/Cargo.toml t/crates/foo/Cargo.toml
hclean -p t -B -g '**/__nomatch' --dry-run
# Matched: t/target
# crates/foo/target is not matched
```

This is the case the flag exists for. `CHANGELOG.md` describes the rule as the marker sitting "beside them inside a git repository", which reads as repository-wide containment; the code implements sibling `.git`. The test at `test/ScanSpec.hs` ("requires the marker file, not just a repository") pins the current behaviour, so it will not catch the change.

Fix: walk upward from `parent` looking for `.git` (bounded by the scan root), keeping the requirement that the marker file be adjacent to the artifact directory. That preserves the safety property — a bare `build/` with no marker still does not match — while covering monorepos.

Alternative framing worth considering: drop the `.git` requirement entirely. The marker file is what makes the directory build output; the repository check adds little beyond a weak "this looks like a project" signal, and it is what breaks here. If it stays, it should be documented as *sibling* `.git`.

### 3. `--quiet` prompts for confirmation with nothing on screen (Main.hs:57-60)

`renderText` is suppressed by `optQuiet`, but `confirm` still runs and still prints `Do you want to delete the above? [y/N]`. There is no "above".

```sh
hclean -g '**/*.pyc' -q      # prompt appears; the list did not
```

A confirmation prompt for an unseen list is worse than no prompt: it trains the answer without conveying the content. Either `-q` should imply `-y` (explicit, documented), or `-q` should print a count (`3 item(s) matched. Delete?`), or the combination should be rejected at parse time. The count is the least surprising.

### 4. `--remove-broken-symlinks` ignores `--older-than` (Scan.hs:126, 130)

`old` gates the `matched` branch but not the broken-symlink branch, which is tested first:

```haskell
let matched = old && (artifact || any (`globMatch` rel) patterns)
...
| link && optBrokenSymlinks o && not intact -> found (...)
```

A user writing `hclean -r -o 30d` is asking to remove broken links older than thirty days. They get every broken link in the tree.

```sh
ln -s /nonexistent dangling
hclean -r -g '**/__nomatch' -o 52w --dry-run    # matches dangling, created seconds ago
```

Pattern-independence for `-r` is defensible and matches the flag's wording. Age independence is not — `--older-than` is a global restriction on what may be touched, and silently dropping it in one branch is the kind of inconsistency that costs a user data. Move the `old` check to cover both branches.

### 5. `--list` ignores `--glob` (Main.hs:98-101)

`listedPatterns` consults `optPresets` and falls back to `defaultPatterns`. `optIncludes` is never read, so `--list` cannot show the patterns a run would actually use:

```sh
hclean -g '**/*.log' -l      # prints the common+python defaults
```

`HClean.Preset.resolvePatterns` already computes the correct answer and is already imported by `Main`. `listedPatterns` is a duplicate of it that disagrees. Delete it and call `resolvePatterns`. `--list` is the flag a cautious user reaches for before a destructive run, so a wrong answer here is worse than the line count suggests.

### 6. `make` breaks whenever a GHC package environment file exists (Makefile:10)

```
src/HClean/Glob.hs:8:1: error:
    Could not load module 'System.FilePath'
    It is a member of the hidden package 'filepath-1.5.2.0'.
```

Cause: `ghc` loads `~/.ghc/<arch>-<ghc>/environments/default` when present, which hides every package the environment does not name. Any prior `cabal install --lib` creates one. The build then fails for `directory`, `filepath`, `time` and `unix` alike.

Adding `-package-env=-` to the recipe fixes it (verified; full `-O2 -Wall` build succeeds, no warnings). Naming the packages explicitly with `-package` would also work and documents the dependency set in the one place that does not already have it.

Related: `make test` runs `cabal test`, so the `make` path has no test coverage and this failure mode does not show up in a `make test` run.

### 7. TOML keys are matched by prefix, and comments are not stripped (Config.hs:116)

```haskell
lookupValue key text = listToMaybe
  [ ... | l <- lines text, key `isPrefixOf` trim l, '=' `elem` l ]
```

Two consequences:

- Any line whose key *starts with* the wanted key wins. No pair of the ten documented keys collides, so this is latent rather than live — but a future key (`path_style`, `patterns_extra`) or a typo silently binds to the wrong option.

- `path = "." # comment` yields `. # comment`, because `unquote` requires the last character to be a quote. TOML comments are legal anywhere; the reader treats them as data.

Fix: split on the first `=`, `trim` the left side, compare for equality; strip from an unquoted `#` to end of line before parsing the value.

### 8. `relativeTo` silently corrupts paths when the base is relative (Scan.hs:59)

```haskell
relativeTo base p = intercalate "/" (drop (length (segments base)) (segments p))
  where segments = splitDirectories . normalise
```

`normalise "."` is `["."]` (length 1) but `normalise "./foo/bar"` is `["foo","bar"]`. Dropping one segment yields `"bar"`, losing `foo`:

```
> relativeTo "." "./foo/bar"
"bar"
```

The executable escapes this because `Main.runClean` calls `makeAbsolute` before `scanWith`. The library does not: `HClean.Scan.scan` is exported, `README.md` advertises the library as directly reusable, and `scan opts "." patterns` matches the wrong paths against every include and exclude pattern.

Fix: `makeAbsolute` the base inside `scan`/`scanWith`, or use `System.FilePath.stripPrefix`-style logic that verifies the prefix rather than counting segments.

### 9. `matchSegment` backtracks exponentially (Glob.hs:35)

`matchSegment ('*':ps) xs = any (matchSegment ps) (suffixes xs)` re-explores every split point with no memoisation.

```sh
touch "$(python3 -c 'print("a"*200+"c")')"
hclean -g "$(python3 -c 'print("*a"*14+"*b")')" --dry-run
# still running at 30s, one file in the tree
```

Practical severity is low — the pattern is user-supplied and self-inflicted — but the fix is small and standard: when the remaining pattern after `*` has no further `*`, match it against the tail directly; otherwise memoise on `(pattern index, string index)`, which makes it O(n*m).

### 10. Directory sizes are measured even when nothing prints them (Main.hs:54)

`runClean` calls `summarize` unconditionally, and `summarize` walks every matched directory tree to compute `targetSize`. In the default path — text format, `--stats` off — `renderText` prints only `Matched: <path>` lines and discards every size.

For `hclean --preset node` over a tree of `node_modules` directories, that is a full recursive walk of the largest thing in the tree, for output that is thrown
away. Gate the measurement on `optStats opts || optFormat opts == JsonFormat`.

### 11. `validGlob` accepts `[]`, which then matches nothing (Glob.hs:78)

`balanced` treats `"]" isPrefixOf xs` as a satisfied class, but `parseClass` requires a non-empty item list before accepting `]` as the terminator (correct — it implements the shell rule that a leading `]` is literal). So `x[]y` passes validation and silently matches nothing:

```sh
hclean -g 'x[]y' --dry-run    # exit 0, no output, no diagnostic
```

Low impact; the cost is a silent no-op instead of the `invalid glob pattern` message the user would get from `x[y`. Aligning `validGlob` with `parseClass` — or better, replacing it with "does `parseClass` succeed on every class in this pattern" — removes the second implementation of the same rule.

### 12. Documentation drift

- `CHANGELOG.md` says "a test suite ... with 65 tests". The suite reports 74.

- `README.md` and `--help` both promise ancestor discovery for `-c` (finding 1).

- `TODO.md` states the terminal width is read from `COLUMNS`. True, but `COLUMNS` is a shell variable that is not exported by default in bash or zsh, so `Progress.terminalWidth` falls back to 80 in essentially every real invocation. Worth saying so, since it changes the priority of the `TIOCGWINSZ` item.

## Already tracked in TODO.md

Reproduced, not re-reported:

- Failed removal aborts the run. Confirmed exactly as described — with a read-only parent, `z1.pyc` and `z2.pyc` both survived because `aro/x.pyc` sorted first and threw. This is the most serious defect in the project and the `failures` array is hardcoded to `[]` (`Report.hs`), so JSON consumers are told the run was clean.

- Non-UTF-8 filenames crash output.

- Uncaught exceptions print `HasCallStack` frames.

- Config file covers only part of the options.

- `--path` cannot override a config file's `path`.

- Version string duplicated between `CLI.hs` and `hclean.cabal`.

- No CI.

One correction to the TODO's framing: "No coverage of the executable's own wiring" is filed under Improvements. Findings 1, 3 and 5 are all defects in that wiring, and all three would have been caught by the golden test it proposes. It belongs under Known issues.

## Suggested order

1. Finding 6 — one flag, unblocks `make` for anyone with a package environment.

2. Finding 1 — feature that does not work; small fix, missing test is obvious.

3. Finding 5 — deleting `listedPatterns` in favour of `resolvePatterns` is a net line reduction.

4. TODO's removal-failure item — the real bug, and the largest change.

5. Findings 3 and 4 — safety inconsistencies, small fixes.

6. Finding 2 — needs a design decision (drop the `.git` check, or climb).

7. The rest.

Findings 1, 3, 4 and 5 share a root cause: `app/` has no end-to-end test. A single golden test that runs the built binary against a fixture tree and compares stdout, stderr and exit code would have caught all four.

---

This review covers correctness, safety and build reproducibility. It does not cover performance profiling under load, Windows behaviour (`unix` is a hard dependency, so the package does not build there), or a line-by-line audit of the test suite. Ask if any of those is worth a pass.

## Appendix: validation record

Every claim above was executed, not inferred. This appendix records the environment, the build and test runs, and the verbatim reproduction for each finding. Paths are shortened to the fixture root; the tool prints absolute paths.

### Environment

```
GHC          9.6.7        (/Users/sa/.ghcup/bin/ghc)
cabal        3.14.2.0
platform     aarch64-darwin, Darwin 25.6.0
commit       05715f3 (v0.1.0), working tree clean
binary       built from this tree with -O2 -Wall
```

### Build and test

```
$ cabal build
[1 of 9] Compiling HClean.Glob ... [9 of 9] Compiling HClean
[1 of 3] Compiling Progress ... [4 of 4] Linking .../hclean
                                        -- no warnings

$ cabal test
74/74 tests passed
Test suite hclean-test: PASS

$ make
src/HClean/Glob.hs:8:1: error:
    Could not load module 'System.FilePath'
    It is a member of the hidden package 'filepath-1.5.2.0'.
    ...
make: *** [hclean] Error 1
```

Cause isolated by re-running `ghc` with verbose package resolution:

```
$ ghc -isrc -iapp -outputdir /tmp/x -O0 -o /tmp/hclean-test app/Main.hs
Loaded package environment from /Users/sa/.ghc/aarch64-darwin-9.6.7/environments/default
                                        -- then the same hidden-package errors
```

Fix verified:

```
$ ghc -package-env=- -isrc -iapp -outputdir build -O2 -Wall -o hclean app/Main.hs
[12 of 12] Linking hclean               -- succeeds, no warnings
$ ./hclean --version
hclean 0.1.0
```

### Finding 1 — `-c` does not search ancestors

```
$ mkdir -p f1/nested/deep && printf 'patterns = ["**/*.marker"]\n' > f1/.rclean.toml
$ touch f1/nested/deep/x.marker
$ cd f1/nested/deep

$ hclean -c --dry-run
                                        -- no output

$ hclean -c ../../.rclean.toml --dry-run
Matched: .../f1/nested/deep/x.marker
```

Mechanism confirmed directly against `System.FilePath`:

```
> (normalise ".", takeDirectory ".", takeDirectory (normalise "."))
(".",".",".")
```

### Finding 2 — `--build-artifacts` misses workspace members

```
$ mkdir -p f2/.git f2/crates/foo/target f2/target
$ touch f2/Cargo.toml f2/crates/foo/Cargo.toml

$ hclean -p f2 -B -g '**/__nomatch' --dry-run
Matched: .../f2/target
                                        -- f2/crates/foo/target absent
```

### Finding 3 — `--quiet` prompts with nothing shown

```
$ mkdir -p f3 && touch f3/a.pyc
$ hclean -p f3 -g '**/*.pyc' -q < /dev/null
Do you want to delete the above? [y/N] hclean: <stdin>: hGetLine: end of file
exit=1
```

Two defects in one line. The prompt refers to a listing `-q` suppressed, and the EOF is unhandled — the run fails safe (nothing deleted, exit 1) but reports a raw GHC exception rather than treating end of input as "no".

### Finding 4 — `-r` ignores `--older-than`

```
$ mkdir -p f4 && ln -s /nonexistent f4/dangling
$ hclean -p f4 -r -g '**/__nomatch' -o 52w --dry-run
Matched: .../f4/dangling
                                        -- link created seconds earlier
```

Excludes were checked separately and do prune the broken-symlink branch, which places the defect in the `old` guard specifically, not in branch ordering.

### Finding 5 — `--list` ignores `--glob`

```
$ hclean -g '**/*.log' -l | head -3
**/.DS_Store
**/.bash_history
**/.python_history
                                        -- the common+python defaults
```

### Finding 7 — TOML comments are read as data

```
$ printf 'path = "." # comment\n' > f7/c.toml
$ hclean -c f7/c.toml --dry-run
invalid path: "." # comment
exit=1
```

The quotes survive too: `unquote` requires the last character to be `"`, and the comment displaced it.

The prefix-matching half of this finding is latent, not live. No pair of the ten documented keys is a prefix of another — `path` and `patterns` diverge at the fourth character — so a config listing `patterns` before `path` parses correctly. Verified:

```
$ printf 'patterns = ["**/*.log"]\npath = "sub"\n' > .rclean.toml
$ hclean -c .rclean.toml --dry-run
Matched: .../sub/b.log                  -- path correctly bound to "sub"
```

### Finding 8 — `relativeTo` with a relative base

```
> relativeTo "." "./foo/bar"
["bar"]                                 -- "foo" dropped
> relativeTo "/a/b" "/a/b/c/d"
["c","d"]                               -- correct when absolute
```

Not reachable through the executable: `Main.runClean` calls `makeAbsolute` first. Reachable through the exported library API the README advertises.

### Finding 9 — exponential glob backtracking

```
$ touch "$(python3 -c 'print("a"*200+"c")')"
$ time timeout 30 hclean -g "$(python3 -c 'print("*a"*14+"*b")')" --dry-run
29.61s user 0.10s system 99% cpu 30.006 total
                                        -- killed by timeout, one file in tree
```

A 7-star pattern against the same file completes in 0.24s, confirming the growth is in the star count rather than the tree.

### Finding 11 — `[]` accepted then matches nothing

```
$ hclean -p f11 -g 'x[]y' --dry-run
exit=0                                  -- silent, no match, no diagnostic

$ hclean -p f11 -g 'x[y' --dry-run
invalid glob pattern: x[y
exit=1                                  -- the diagnostic the first case wanted
```

### Finding 12 — test count drift

```
$ grep -n "65 tests" CHANGELOG.md
61:- A test suite (`cabal test` or `make test`) with 65 tests and its own small

$ cabal test
74/74 tests passed
```

### Tracked item — a failed removal aborts the run

Reproduced to confirm `TODO.md` is accurate, including the part that matters most: removable targets sorted after the failure are never attempted.

```
$ mkdir -p fT/aro && touch fT/aro/x.pyc fT/z1.pyc fT/z2.pyc && chmod 555 fT/aro
$ hclean -p fT -g '**/*.pyc' -y -q
hclean: .../fT/aro/x.pyc: removeLink: permission denied (Permission denied)
exit=1

$ find fT -name '*.pyc' | sort
./aro/x.pyc
./z1.pyc                                -- removable, never attempted
./z2.pyc                                -- removable, never attempted
```

With `--format json` the report is printed before deletion begins, so `failures` is emitted as `[]` on the same run that then fails:

```
{"matches":[...],"summary":{...,"dry_run":false},"stats":[...],"failures":[]}
hclean: .../ro/b.pyc: removeLink: permission denied (Permission denied)
```

Ordering is the aggravating factor. The `failures` array cannot ever be populated at its current position in `runClean`, independent of the missing error handling in `Main.delete`.

### Checks that passed

Recorded so they are not re-litigated.

- Glob semantics: `**/file.txt` matches at the root; a bare `deep.txt` matches a basename at any depth; `a/**/*.txt` anchors to the scan root. All correct.

- Exclude patterns prune the walk, including for broken symlinks.

- Protected directories are not entered; `--no-protect` re-enables them.

- `--build-artifacts` correctly declines a `build/` with no marker file.

- Config precedence: a command-line list replaces the file's list; a file cannot switch off a command-line boolean; quoted scalars are unquoted.

- Symlink loops terminate, as `TODO.md` claims.

- `removePath` on a symlink to a directory removes the link, not the target — `removePathForcibly` does not follow symlinks, so `doesDirectoryExist` following them is not exploitable here.

- `formatSize` cannot emit scientific notation: `twoDecimals` only ever receives values in [1, 1024).

- Fixture trees for every finding were removed after the run; `git status` is clean.
