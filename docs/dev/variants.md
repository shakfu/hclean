# Variants

hclean is one of four tools that recursively remove development detritus. This file compares them, so that a change to one can be weighed against the others.

## Snapshot

Facts below come from reading each tool's source, README and CHANGELOG on 2026-10-03. [features.md](features.md) lists each feature and which tool has it.

| Tool | Language | Revision | Source lines | Tests |
|-|-|-|-|-|
| hclean | Haskell | 0.1.0 + Unreleased | 1.4k | 116 |
| oclean | OCaml | `42c0b6a` + Unreleased | 1.0k | 114 |
| cclean | C++17 | 0.3.0 (`0927f41`) | 5.0k | 416 unit checks, 234 CLI checks |
| rclean | Rust | 0.5.0 (`59a0598`) + Unreleased | 2.5k | 134 |

rclean's repository and crate are now named `reclean`; the binary installed as `rclean` is 0.4.2. hclean was ported from rclean 0.4. Source lines exclude tests.

## Lineage

- rclean 0.4 came first.

- hclean ported rclean 0.4 to Haskell.

- oclean ported hclean 0.1.0 to OCaml and fixed 11 hclean defects.

- hclean's Unreleased section backports those fixes, plus later changes.

- cclean is an independent design with a different command line.

- rclean 0.5 adopted several cclean features: `-D`, `--larger-than`, `"schema": 1`, exit status 3, the single-key prompt, parallel removal.

The tools now form two groups. hclean and oclean keep the rclean 0.4 command line. cclean and rclean 0.5 share the newer design.

## Features

| | hclean | oclean | rclean | cclean |
|-|-|-|-|-|
| Command line | rclean 0.4 flags | same as hclean | rclean 0.4 flags, `--preset` removed, `-D` and `--larger-than` added | `cclean [OPTION...] ROOT [PATTERN...]` |
| `--glob` vs defaults | replaces | replaces | replaces | adds; `--no-defaults` replaces |
| `--preset` | yes | yes | no | no |
| Defaults include shell history | no | no | no | no |
| `-B` build artifacts | marker beside it; `.git` beside it or in an ancestor below `~` | same as hclean | marker and `.git` beside it; outermost project only | same as rclean; `project_roots` for monorepos |
| `-D` dependency trees | no | no | yes, beside a lock file, with restore command | yes, plus `dependency_markers` |
| `--older-than` | yes | yes | yes | yes |
| `--larger-than` | no | no | yes | yes |
| Symlinks | `-i`, `-r` | `-i`, `-r` | `-i`, `-r` | matched link always unlinked, never followed |
| Protected directories | fixed list; `--no-protect` | fixed list; `--no-protect` | configurable; `.venv`, `venv` excluded by default | fixed list; `--no-skip` |
| Prompt | line on stderr with count; end of input is no | same as hclean | single key; typeahead discarded | single key; typeahead discarded |
| Size units | binary (KiB) | decimal (KB) | binary (KiB) | binary (KiB) |
| Bytes freed | measured: size before minus what a failure left | summed as files are unlinked | scan sizes of removed targets | scan sizes of all targets; printed only when no removal failed |
| JSON | matches, summary, stats, failures | same as hclean | adds `schema`, `config`, `reasons`, `restore`, `warnings` | `schema`, `config`, per-reason stats, `restore`, `warnings` |
| Exit codes | 0, 1 | 0, 1 | 0, 1, 2, 3 | 0, 1, 2, 3 |
| One removal fails | continues; exit 1 | continues; exit 1 | continues; exit 1 | continues; exit 1 |
| Non-UTF-8 names | raw bytes in text; invalid JSON | same as hclean | U+FFFD in text and JSON; text quotes names and escapes control characters | `\xNN` in text; U+FFFD in JSON |
| Parallelism | none | none | walk and removal | walk, sizing and removal; splits targets of 4,096+ entries |
| Removal | `removePathForcibly` by path | `lstat`/`unlink` by path | descriptor-relative `O_NOFOLLOW` walk, then dev/inode check (Unix) | descriptor-relative `O_NOFOLLOW` walk, then dev/inode check |
| Read-only directory inside a target | made writable, then removed | made writable through a descriptor checked against `lstat`, if the user owns it | fails | fails |
| Library | internal split, not installed | internal split, not installed | `lib.rs` | installable `libcclean.a` and headers |
| Runtime dependencies | `base`, `directory`, `filepath`, `time`, `unix` | stdlib, `unix` | 12 crates | stdlib, pthreads |
| CI | Linux, macOS | Linux (OCaml 4.14), macOS (OCaml 5) | Linux, macOS | Linux (gcc, clang), macOS |

## Configuration

Discovery differs more than any other area.

| | hclean | oclean | rclean | cclean |
|-|-|-|-|-|
| File | `.hclean.toml` | `.oclean.toml` | `.reclean.toml` | `.cclean.toml` |
| Read when | `-c` given | `-c` given | `-c` given | always, unless `--no-config` |
| Search starts at | working directory | working directory | working directory | `ROOT` |
| Search stops | below `~` | below `~` | at `/` | at `/` |
| Global fallback | `hclean/config.toml` under `$XDG_CONFIG_HOME` or `~/.config` | `oclean/config.toml` under `$XDG_CONFIG_HOME` or `~/.config` | same, as `reclean/config.toml`; macOS falls back to `~/Library/Application Support` with a warning; Windows uses `%APPDATA%` | none |
| Relative `path` resolves against | the file's directory; the working directory for the global file | the working directory | the working directory | no `path` key |
| Files read per run | one | one | one | one |
| `-w` writes to | `--path` | `--path` | working directory | no writer |
| `--exclude` and the file's excludes | command line replaces | command line replaces | command line extends | command line replaces |
| Unknown keys | ignored | ignored | error | error |
| Missing keys | default | default | default; missing `patterns` means the built-in list | default; built-in patterns stay on through `defaults = true` |
| Bare `-c` with no file found | runs without one | runs without one | error | not applicable |

## Open decisions

Each item needs a choice that applies to all four tools.

- **Size units.** oclean uses decimal units to match Finder. The other three use binary units. Changing either side changes JSON `*_size_human` fields.

- **`path` resolution.** Only hclean resolves a relative `path` against the config file's directory.

- **Home boundary.** hclean and oclean stop config discovery and the `-B` `.git` search below `~`. rclean and cclean search to `/`; cclean documents the risk.

- **`-B` repository rule.** hclean and oclean accept a `.git` in an ancestor, which covers workspace members. rclean and cclean require it beside the directory and skip nested repositories.

A black-box test suite that takes the binary as a parameter, like `cclean/tests/cli.sh`, would turn each table row above into a check.
