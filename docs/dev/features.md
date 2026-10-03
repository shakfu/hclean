# Features

Every feature across hclean, oclean, rclean and cclean, as of 2026-10-03.
[variants.md](variants.md) compares how the tools differ; this file lists
what each feature is and which tool has it. Paths are relative to each tool's
repository. rclean's repository is `reclean`.

## Matrix

| Category | Feature | hclean | oclean | rclean | cclean |
|-|-|-|-|-|-|
| Matching | Glob patterns | yes | yes | yes | yes |
| | Built-in default patterns | yes | yes | yes | yes |
| | Presets | yes | yes | - | - |
| | Excludes | yes | yes | yes | yes |
| | Protected directories | yes | yes | yes | yes |
| | Default excludes | - | - | yes | - |
| | Build artifact detection | yes | yes | yes | yes |
| | Dependency tree detection | - | - | yes | yes |
| | Custom dependency markers | - | - | - | yes |
| | Monorepo project roots | - | - | - | yes |
| Filters | Age filter | yes | yes | yes | yes |
| | Size filter | - | - | yes | yes |
| Symlinks | Matched symlink removal | opt-in | opt-in | opt-in | always |
| | Broken symlink removal | yes | yes | yes | - |
| Safety | Dry run | yes | yes | yes | yes |
| | Confirmation prompt | line | line | single key | single key |
| | Skip confirmation | yes | yes | yes | yes |
| | Continue after a failed removal | yes | yes | yes | yes |
| | Identity check before removal | - | - | yes | yes |
| | Descriptor-relative removal | - | - | - | yes |
| | Home boundary | yes | yes | - | - |
| Configuration | Config file | yes | yes | yes | yes |
| | Upward discovery | yes | yes | yes | yes |
| | Global config file | yes | yes | yes | - |
| | Explicit config file | yes | yes | yes | yes |
| | Opt-out of config | default | default | default | `--no-config` |
| | Starter config writer | yes | yes | yes | - |
| | File-relative `path` | yes | - | - | n/a |
| Output | Match listing | yes | yes | yes | yes |
| | Per-pattern statistics | yes | yes | yes | - |
| | Per-reason breakdown | - | - | yes | yes |
| | JSON output | yes | yes | yes | yes |
| | JSON schema version | - | - | yes | yes |
| | Restore command | - | - | yes | yes |
| | Bytes freed | yes | yes | yes | yes |
| | Progress indicator | yes | yes | yes | yes |
| | Colour | - | - | - | yes |
| | Verbose log | yes | yes | yes | yes |
| | Quiet mode | yes | yes | yes | - |
| | Pattern listing | yes | yes | yes | - |
| | Shell completions | - | - | yes | - |
| | Unreadable-path exit status | - | - | yes | yes |
| | Safe display of file names | partial | partial | yes | yes |
| Performance | Parallel scan | - | - | yes | yes |
| | Parallel removal | - | - | yes | yes |
| | Split removal of large targets | - | - | - | yes |
| Packaging | Library | internal | internal | yes | installable |
| | No third-party dependencies | yes | yes | - | yes |
| | CI | yes | yes | yes | yes |

## Matching

### Glob patterns

- description: Globs select paths by name, with `*`, `?`, `**` and character classes.
- purpose: Users name what to remove without listing each path.
- implemented by: `src/HClean/Glob.hs` (hclean), `src/glob.ml` (oclean), `src/lib.rs` via `globset` (rclean), `src/glob.cpp` (cclean) -- all four.

### Built-in default patterns

- description: A fixed list of caches and OS debris is matched when no pattern is given.
- purpose: A bare run cleans the common cases safely.
- implemented by: `src/HClean/Preset.hs` (hclean), `src/preset.ml` (oclean), `src/constants.rs` (rclean), `include/cclean/defaults.hpp` (cclean) -- all four.

### Presets

- description: Named pattern sets such as `python`, `node` and `rust` are selected with `--preset`.
- purpose: Users pick an ecosystem without writing its globs.
- implemented by: `src/HClean/Preset.hs` (hclean), `src/preset.ml` (oclean) -- hclean and oclean.

### Excludes

- description: Exclude globs prune the walk, so a matching directory is neither removed nor entered.
- purpose: Users protect specific trees, such as fixtures, from broad patterns.
- implemented by: `src/HClean/Scan.hs` (hclean), `src/scan.ml` (oclean), `src/lib.rs` (rclean), `src/scan.cpp` (cclean) -- all four.

### Protected directories

- description: `.git`, `.hg`, `.svn`, `.config`, `.ssh` and `.gnupg` are never matched or entered.
- purpose: These hold history and credentials that a false match would destroy.
- implemented by: `src/HClean/Preset.hs` and `src/HClean/Scan.hs` (hclean), `src/preset.ml` and `src/scan.ml` (oclean), `src/constants.rs` and `src/lib.rs` (rclean), `include/cclean/defaults.hpp` and `src/scan.cpp` (cclean) -- all four.

### Default excludes

- description: `.venv` and `venv` are excluded unless the user replaces the exclude list.
- purpose: Scanning a virtualenv finds hundreds of caches nobody wants removed.
- implemented by: `src/constants.rs` (rclean) -- rclean only.

### Build artifact detection

- description: `-B` matches output directories such as `build` and `target` only beside their project marker and a `.git`.
- purpose: These names are too ordinary to match safely by name alone.
- implemented by: `src/HClean/Scan.hs` (hclean), `src/scan.ml` (oclean), `src/constants.rs` and `src/lib.rs` (rclean), `include/cclean/defaults.hpp` and `src/project.cpp` (cclean) -- all four.

### Dependency tree detection

- description: `-D` matches `node_modules`, `.venv` and `vendor` only beside the lock file that pins them.
- purpose: Only a lock file says which tree its package manager can restore exactly.
- implemented by: `src/constants.rs` and `src/lib.rs` (rclean), `include/cclean/defaults.hpp` and `src/project.cpp` (cclean) -- rclean and cclean.

### Custom dependency markers

- description: `dependency_markers` adds directory and lock-file pairs to the built-in dependency table.
- purpose: Ecosystems outside the built-in list get the same lock-file guard.
- implemented by: `src/config.cpp` and `src/scan.cpp` (cclean) -- cclean only.

### Monorepo project roots

- description: `project_roots` names package directories that count as projects without their own `.git`.
- purpose: A monorepo has one `.git`, so its packages would otherwise never qualify for `-B`.
- implemented by: `src/config.cpp` and `src/project.cpp` (cclean) -- cclean only.

## Filters

### Age filter

- description: `--older-than` keeps only targets older than a duration such as `30d`.
- purpose: Recently used caches stay, avoiding a rebuild the user is about to need.
- implemented by: `src/HClean/Scan.hs` (hclean), `src/scan.ml` (oclean), `src/lib.rs` (rclean), `src/filters.cpp` (cclean) -- all four.

### Size filter

- description: `--larger-than` keeps only targets of at least a given size.
- purpose: Users reclaim the most space with the fewest removals.
- implemented by: `src/lib.rs` (rclean), `src/filters.cpp` (cclean) -- rclean and cclean.

## Symlinks

### Matched symlink removal

- description: A symlink that matches a pattern is removed as a link, never followed.
- purpose: Removing a link must not remove what it points to.
- implemented by: `src/HClean/Scan.hs` (hclean), `src/scan.ml` (oclean), `src/lib.rs` (rclean), `src/scan.cpp` (cclean) -- all four; hclean, oclean and rclean require `-i`.

### Broken symlink removal

- description: `-r` removes dangling symlinks regardless of pattern.
- purpose: Dead links left by moved or deleted targets clutter a tree.
- implemented by: `src/HClean/Scan.hs` (hclean), `src/scan.ml` (oclean), `src/lib.rs` (rclean) -- hclean, oclean and rclean.

## Safety

### Dry run

- description: `--dry-run` lists what would be removed and removes nothing.
- purpose: Users check a pattern before it deletes anything.
- implemented by: `app/Main.hs` (hclean), `bin/main.ml` (oclean), `src/lib.rs` (rclean), `cli/main.cpp` (cclean) -- all four.

### Confirmation prompt

- description: Removal waits for the user to answer yes after seeing the match list.
- purpose: Deletion is permanent, so the user approves the list first.
- implemented by: `app/Main.hs` (hclean), `bin/main.ml` (oclean), `src/lib.rs` (rclean), `cli/terminal.cpp` (cclean) -- all four; rclean and cclean take a single key and discard typeahead.

### Skip confirmation

- description: `-y` removes without prompting.
- purpose: Scripts and CI runs have nobody to answer.
- implemented by: `app/CLI.hs` (hclean), `bin/cli.ml` (oclean), `src/main.rs` (rclean), `cli/options.cpp` (cclean) -- all four.

### Continue after a failed removal

- description: A target that cannot be removed is reported, and the remaining targets are still removed.
- purpose: One unreadable directory should not leave the rest of the tree uncleaned.
- implemented by: `src/HClean/Delete.hs` (hclean), `src/delete.ml` (oclean), `src/lib.rs` (rclean), `src/remove.cpp` (cclean) -- all four.

### Identity check before removal

- description: Removal refuses a target whose device and inode differ from what the scan recorded.
- purpose: A path replaced between the prompt and removal is not the one the user approved.
- implemented by: `src/lib.rs` (rclean), `src/remove.cpp` (cclean) -- rclean and cclean.

### Descriptor-relative removal

- description: Each path component is opened with `O_NOFOLLOW` through its parent's descriptor.
- purpose: A symlink swapped in mid-run cannot redirect removal outside the root.
- implemented by: `src/remove.cpp` (cclean) -- cclean only.

### Home boundary

- description: Config discovery and the `-B` `.git` search stop below the home directory.
- purpose: A config file or dotfiles repository in `~` would otherwise apply to every project under it.
- implemented by: `src/HClean/Util.hs` (hclean), `src/util.ml` (oclean) -- hclean and oclean.

## Configuration

### Config file

- description: A TOML file sets patterns, excludes and flags for repeated runs.
- purpose: A project records its cleaning rules once instead of in every command.
- implemented by: `src/HClean/Config.hs` (hclean), `src/config.ml` (oclean), `src/lib.rs` and `src/main.rs` (rclean), `src/config.cpp` and `src/toml.cpp` (cclean) -- all four.

### Upward discovery

- description: The nearest config file in the start directory or an ancestor is used.
- purpose: Running from any subdirectory picks up the project's rules.
- implemented by: `src/HClean/Config.hs` (hclean), `src/config.ml` (oclean), `src/lib.rs` (rclean), `src/config.cpp` (cclean) -- all four.

### Global config file

- description: A per-user file in the user config directory applies when no project file is found.
- purpose: User-wide settings live outside any project.
- implemented by: `src/HClean/Config.hs` (hclean), `src/config.ml` (oclean), `src/lib.rs` (rclean) -- hclean, oclean and rclean.

### Explicit config file

- description: `-c FILE` (cclean: `--config FILE`) reads the named file instead of searching.
- purpose: Scripts get the same result regardless of what sits above the checkout.
- implemented by: `app/CLI.hs` (hclean), `bin/cli.ml` (oclean), `src/main.rs` (rclean), `cli/options.cpp` (cclean) -- all four.

### Opt-out of config

- description: A run reads no config file at all.
- purpose: CI runs must not depend on a file in a parent directory.
- implemented by: the default without `-c` (hclean, oclean, rclean), `--no-config` in `cli/options.cpp` (cclean) -- all four.

### Starter config writer

- description: `-w` writes a starter config file and refuses to overwrite one.
- purpose: Users start from a valid file instead of the documentation.
- implemented by: `src/HClean/Config.hs` and `app/Main.hs` (hclean), `src/config.ml` (oclean), `src/main.rs` (rclean) -- hclean, oclean and rclean.

### File-relative `path`

- description: A relative `path` in a project config resolves against the file's directory.
- purpose: `path = "."` scans the project, wherever the run starts beneath it.
- implemented by: `src/HClean/Config.hs` (hclean) -- hclean only.

## Output

### Match listing

- description: Every match is printed before anything is removed.
- purpose: The user reviews exactly what the prompt approves.
- implemented by: `src/HClean/Report.hs` (hclean), `src/report.ml` (oclean), `src/lib.rs` (rclean), `cli/main.cpp` (cclean) -- all four.

### Per-pattern statistics

- description: `--stats` prints the count and size matched by each pattern.
- purpose: Users see which pattern accounts for the space.
- implemented by: `src/HClean/Report.hs` (hclean), `src/report.ml` (oclean), `src/lib.rs` (rclean) -- hclean, oclean and rclean.

### Per-reason breakdown

- description: Totals are split by why a target matched: pattern, build artifact or dependency.
- purpose: The reasons differ in what it costs to restore a target.
- implemented by: `src/lib.rs` (rclean), `cli/main.cpp` (cclean) -- rclean and cclean.

### JSON output

- description: `--format json` writes one machine-readable document to stdout.
- purpose: Scripts consume results without parsing text.
- implemented by: `src/HClean/Report.hs` (hclean), `src/report.ml` (oclean), `src/lib.rs` (rclean), `src/json.cpp` (cclean) -- all four.

### JSON schema version

- description: The JSON document opens with `"schema": 1`.
- purpose: Consumers refuse a shape they do not know instead of misreading it.
- implemented by: `src/lib.rs` (rclean), `src/json.cpp` (cclean) -- rclean and cclean.

### Restore command

- description: Each dependency target carries the command that reinstalls it, such as `npm ci`.
- purpose: Users know how to undo a removal before they confirm it.
- implemented by: `src/constants.rs` (rclean), `include/cclean/defaults.hpp` (cclean) -- rclean and cclean.

### Bytes freed

- description: A summary after removal reports the bytes reclaimed.
- purpose: Users see what the run achieved.
- implemented by: `src/HClean/Delete.hs` (hclean), `src/delete.ml` (oclean), `src/lib.rs` (rclean), `cli/main.cpp` (cclean) -- all four; [variants.md](variants.md) compares how each counts.

### Progress indicator

- description: Long scans and removals show activity on stderr, only on a terminal.
- purpose: A large tree otherwise looks hung.
- implemented by: `app/Progress.hs` (hclean), `bin/progress.ml` (oclean), `src/lib.rs` via `indicatif` (rclean), `cli/terminal.cpp` (cclean) -- all four.

### Colour

- description: Directories, totals and failures are coloured, honouring `NO_COLOR` and `--color`.
- purpose: Failures stand out in a long listing.
- implemented by: `cli/terminal.cpp` (cclean) -- cclean only.

### Verbose log

- description: `-v` logs each match and removal.
- purpose: Users diagnose why something did or did not match.
- implemented by: `app/Main.hs` (hclean), `bin/main.ml` (oclean), `src/main.rs` (rclean), `cli/main.cpp` (cclean) -- all four.

### Quiet mode

- description: `-q` suppresses the match listing and summary.
- purpose: Scripts want only errors.
- implemented by: `app/Main.hs` (hclean), `bin/main.ml` (oclean), `src/main.rs` (rclean) -- hclean, oclean and rclean.

### Pattern listing

- description: `-l` prints the patterns a run would use.
- purpose: Users check the effective pattern set without scanning.
- implemented by: `app/Main.hs` (hclean), `bin/main.ml` (oclean), `src/main.rs` (rclean) -- hclean, oclean and rclean.

### Shell completions

- description: `--completions SHELL` prints a completion script for bash, zsh, fish, elvish or PowerShell.
- purpose: Shells complete flags without the user reading `--help`.
- implemented by: `src/main.rs` via `clap_complete` (rclean) -- rclean only.

### Unreadable-path exit status

- description: Exit status 3 means the run completed but part of the tree could not be read.
- purpose: Scripts tell a partial scan from a failed removal.
- implemented by: `src/main.rs` (rclean), `cli/main.cpp` (cclean) -- rclean and cclean.

### Safe display of file names

- description: File names print without crashing, and control characters cannot forge or erase listing lines.
- purpose: The listing is what the user approves, so a hostile name must not alter it.
- implemented by: `app/Main.hs` (hclean), `src/report.ml` (oclean), `src/lib.rs` (rclean), `src/text.cpp` (cclean) -- all four; hclean and oclean print raw bytes and do not escape control characters in text.

## Performance

### Parallel scan

- description: Directory walking and sizing run across all cores.
- purpose: Large trees scan in a fraction of the time.
- implemented by: `src/lib.rs` (rclean), `src/scan.cpp` (cclean) -- rclean and cclean.

### Parallel removal

- description: Targets are removed concurrently, with results reported in list order.
- purpose: Removal is one syscall per entry and dominates run time.
- implemented by: `src/lib.rs` (rclean), `src/remove.cpp` (cclean) -- rclean and cclean.

### Split removal of large targets

- description: A target of 4,096 or more entries is divided across the worker pool.
- purpose: A single large `target/` or `node_modules` would otherwise use one core.
- implemented by: `src/remove.cpp` (cclean) -- cclean only.

## Packaging

### Library

- description: Scanning, reporting and removal live in a library separate from the command line.
- purpose: The logic is testable, and reusable without prompts or exit codes.
- implemented by: `src/HClean/` (hclean), `src/` (oclean), `src/lib.rs` (rclean), `libcclean.a` with headers in `include/cclean/` (cclean) -- all four; only cclean installs it.

### No third-party dependencies

- description: The build uses only the language's standard library and its bundled packages.
- purpose: The tool builds anywhere the compiler does, with nothing to fetch.
- implemented by: `hclean.cabal` (hclean), `Makefile` (oclean), `CMakeLists.txt` (cclean) -- hclean, oclean and cclean; rclean uses 12 crates.

### CI

- description: Every push runs the test suite on Linux and macOS.
- purpose: Platform-specific failures surface before release.
- implemented by: `.github/workflows/ci.yml` (all four) -- all four.
