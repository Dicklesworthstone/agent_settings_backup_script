# Changelog

All notable changes to [Agent Settings Backup (asb)](https://github.com/Dicklesworthstone/agent_settings_backup_script) are documented here.

Versions follow [Semantic Versioning](https://semver.org/). v0.2.0 has an annotated git tag but no GitHub Release; v0.1.0 and v0.3.0 are identified by VERSION file bumps in the commit history.

---

## [v0.3.1] — 2026-08-15

First tagged GitHub Release (assets: `asb`, `checksums.txt`), cut so the installer's primary `releases/latest/download` path resolves instead of always falling back to raw `main`.

### Fixed

- **`eval "$(asb completion zsh)"` no longer errors** — the zsh completion script tail is now guarded so eval-based installs work ([`6a5bc94`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/6a5bc941f70b86e6a2e4f6f127e615302b088f47))
- **Installer quiets the missing-release fallback** — falling back to raw `main` when no GitHub Release exists is no longer noisy ([`9a5a4b1`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/9a5a4b18a6998bdd554b747658eee20edff06f16))

### Changed

- CI status badges removed from README (GH Actions throttling made them misleading) ([`c6e8a7a`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/c6e8a7ac2c8f42746c6c66be05f9f26ec80af894))

---

## [v0.3.0] — 2026-01-21 (untagged)

VERSION bumped in commit [`2091367`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/20913676a9718a538f7a87d9cce10f5bb68365ab). Development spans 2026-01-21 through 2026-03-13 (HEAD [`1ad6405`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/1ad6405acaf4f3a2592576c9c456395fe6ffaf7e)).

### New Commands

- **Backup tags** (`asb tag`) — Name important backups with `asb tag claude v1.0`, list with `--list`, delete with `--delete`; first introduced in [`4a3d98c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/4a3d98cc0556e54d20ded7095dae805c5d846533)
- **Restore from tags** — `asb restore claude v1.0` resolves tag names to commits automatically, eliminating the need to remember commit hashes ([`4a3d98c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/4a3d98cc0556e54d20ded7095dae805c5d846533))
- **Statistics** (`asb stats`) — View backup size, commit count, changes-per-week, and activity metrics for all agents or a single agent ([`7709a70`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/7709a70930dc1e9995527950a536fcd98cb7aafa))
- **Auto-discovery** (`asb discover`) — Scan the filesystem for new AI coding agents; add them interactively or automatically with `--auto`; list candidates with `--list` ([`a69a688`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/a69a688941a35eb3c7e3e7a1348cdb0953c78a96))
- **Scheduled backups** (`asb schedule`) — Install cron jobs (`--cron`) or systemd user timers (`--systemd`) with `--interval daily|weekly|hourly`; manage with `--status` and `--remove` ([`831fb4c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/831fb4c7b2248991e9dbc58f862ba259e424f473))
- **Backup verification** (`asb verify`) — Check backup repository integrity for all or specific agents; distinguishes failed, skipped, and not-found cases ([`831fb4c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/831fb4c7b2248991e9dbc58f862ba259e424f473), improved in [`a4a7028`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/a4a70282ef64ebf694fed2341acf3d763609b9ff))
- **Hooks** (`asb hooks`) — Run user-defined scripts before/after backup and restore operations via `~/.config/asb/hooks/{pre,post}-{backup,restore}.d/` directories; pre-hook failure aborts, post-hook failure warns; environment variables `ASB_AGENT`, `ASB_SOURCE`, `ASB_BACKUP_DIR`, `ASB_OPERATION`, `ASB_COMMIT` passed to scripts ([`928c06c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/928c06c34a9020c3854fb4ef5f11bac0206fe0db), [`7709a70`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/7709a70930dc1e9995527950a536fcd98cb7aafa))

### Structured Output

- **JSON output** (`--json` / `-j`) — Machine-readable JSON output for every command: backup, restore, list, history, diff, stats, discover, export, import, verify; built incrementally across [`83b299e`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/83b299e689f38dc665619d853ce7d88022f320eb), [`4a3d98c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/4a3d98cc0556e54d20ded7095dae805c5d846533), [`928c06c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/928c06c34a9020c3854fb4ef5f11bac0206fe0db), [`7709a70`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/7709a70930dc1e9995527950a536fcd98cb7aafa), [`a69a688`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/a69a688941a35eb3c7e3e7a1348cdb0953c78a96), [`06aca36`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/06aca364036ab746885838706f5980163d147f48)
- **TOON format** (`--format toon`) — Tabular structured output via `tru` (toon_rust); `--format json` also accepted as explicit alternative to `--json` ([`6352340`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/6352340828989b5866a9b605b99abfb92480518f))
- JSON helper functions: `json_output`, `json_error`, `json_escape_string`, `json_array` for safe serialization

### Agent Support

- **3 new agents**: Plandex (`~/.plandex-home`), Qwen Code (`~/.qwen`), Amazon Q (`~/.q`) ([`831fb4c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/831fb4c7b2248991e9dbc58f862ba259e424f473))
- **Custom agents** — Persist user-discovered agents in `~/.config/asb/custom_agents` (key=folder format) for automatic inclusion via `load_custom_agents` ([`a69a688`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/a69a688941a35eb3c7e3e7a1348cdb0953c78a96))

### Bug Fixes

- Improve verify command output: track skipped agents, show display name in warnings, distinguish failed vs not-found in summary ([`a4a7028`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/a4a70282ef64ebf694fed2341acf3d763609b9ff))
- Improve backup script reliability with better error handling and file processing edge cases ([`7b6e600`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/7b6e600019e0e3d283139eaeadebc2a1873df482))
- Fix shellcheck warnings: replace `A && B || C` with proper `if-then-fi` in `log_debug`, quote expansions in parameter patterns, use printf format specifiers ([`c74f8be`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/c74f8be60f928da32c04e7979b6fce370571aacc))
- Fix CI test failures: fall back to `/tmp` when `TMPDIR` is unavailable, add `XXXXXXXX` suffixes to all `mktemp -t` templates ([`9ae57e2`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/9ae57e219b19bdf71b9c1879781c154e92ed2b96))
- Use modern bash 4+ on macOS CI runners for associative array support (`declare -A` requires bash >= 4.0; macOS ships 3.2) ([`99bb595`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/99bb595f2aad8fc335491ab99fb6de7b091c1f79))
- Suppress human-readable log messages when `--json` is active so stdout contains only valid JSON ([`06aca36`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/06aca364036ab746885838706f5980163d147f48))

### Testing

- Comprehensive E2E test suite covering: concurrent operations, discovery, error paths, large files, stats, symlinks, tags, unicode filenames, verify, hooks, JSON validation, scheduling, and conflict detection ([`a69a688`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/a69a688941a35eb3c7e3e7a1348cdb0953c78a96))
- Unit test framework with harness (`tests/unit/`): agent_exists, config functions, discovery functions, git functions, JSON functions, logging ([`a69a688`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/a69a688941a35eb3c7e3e7a1348cdb0953c78a96))
- GitHub Actions CI workflow (`test.yml`): ShellCheck lint + E2E + unit tests on Ubuntu and macOS ([`a69a688`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/a69a688941a35eb3c7e3e7a1348cdb0953c78a96), [`06aca36`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/06aca364036ab746885838706f5980163d147f48))
- E2E test script for TOON format: `--format json|toon` flags, tabular output, `tru` encode/decode round-trip ([`d075f66`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/d075f6681f28f9684786e48d186e2de1c3bcd3a4))
- Enhanced conflict detection tests with timestamp collision and concurrent backup scenarios ([`7933d11`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/7933d11fee1c2992d2f08787ff0636eba3feafe5))
- Diagnostic output for `test_dryrun_backup_shows_preview` to debug macOS-vs-Ubuntu differences ([`eb21153`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/eb211535960a9f76b8466312f2669ddc65f61b96))
- Diff parsing reproduction test and JSON validation tests ([`fa8a48d`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/fa8a48dce75f74a06e86141bd4b1f12093b234ae), [`6ce735c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/6ce735ce20330bcfe94f74c232a6ac143481b565))
- Allow sourcing `asb` for unit tests via `ASB_SOURCED=true` without executing `main`

### CI/CD

- ACFS installer change notification workflow: triggers `repository_dispatch` to the Agent CLI Flywheel Stack when `install.sh` changes, includes SHA256 checksum and concurrency control ([`f0e8e27`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/f0e8e2736164d8bbd13db889c05297d639d48fdf))

### Documentation and Metadata

- Update AGENTS.md with latest multi-agent conventions, fix typos, add master branch sync instructions ([`32d10a4`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/32d10a4dacd1ab1a9f33937ea121872d8ffc7f0f))
- Update README with v0.3 features: structured output examples, hooks documentation, FAQ, troubleshooting guide
- Add project illustration (`asb_illustration.webp`) and GitHub social preview image ([`33a6c55`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/33a6c5531752c3ec5e3686898e69f9ac2b593c79), [`58262df`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/58262df3c663e246cf9e20d2d378398c3aff8066))

### License

- Update license from MIT to MIT with OpenAI/Anthropic Rider ([`20411f5`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/20411f5cf80f703d84a2753982d0a060d0d6b107), [`ce4d373`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/ce4d3737b6c75207c2740a8e13d476feef287d55))

### Housekeeping

- Remove stale macOS resource fork file `._asb_illustration.png` ([`1ad6405`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/1ad6405acaf4f3a2592576c9c456395fe6ffaf7e))
- Add test space directory and binary artifacts to `.gitignore` ([`81f6c7f`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/81f6c7f28695872a1f860585d8c29fdfe8d9b6eb))

### Script Growth

`asb` grew from 1,726 lines (v0.2.0) to 4,083 lines, adding 7 new commands (`tag`, `stats`, `discover`, `verify`, `schedule`, `hooks`, and structured output format selection) and JSON/TOON output for every existing command.

---

## [v0.2.0] — 2026-01-21

Annotated git tag [`v0.2.0`](https://github.com/Dicklesworthstone/agent_settings_backup_script/releases/tag/v0.2.0) at commit [`bdfba33`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/bdfba339db35876d8a57921b7b36240719d188b9). No corresponding GitHub Release. The major feature work landed in [`ddfa290`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/ddfa290544b324ded01edc289c166547c0c0bd16) (2026-01-20); the version bump followed.

### New Commands

- **Export** (`asb export <agent> [file]`) — Create portable `.tar.gz` archives of any agent's backup; pipe support for remote transfer (`asb export claude - | ssh remote "asb import -"`) and encryption (`| gpg -c`)
- **Import** (`asb import <file>`) — Restore backup archives onto a new machine
- **Configuration** (`asb config init|show`) — Create and inspect persistent settings in `~/.config/asb/config` (XDG-compliant)
- **Shell completion** (`asb completion bash|zsh|fish`) — Tab completion for commands and agent names

### Operational Improvements

- **Dry-run mode** (`-n` / `--dry-run`) — Preview changes on any command without writing to the filesystem
- **Restore confirmation** — Interactive preview of exactly which files will change before restoring; skip with `--force`
- **Global options** — `-n/--dry-run`, `-f/--force`, `-v/--verbose` parsed before command dispatch, applying to any subcommand

### Bug Fixes

- Fix hidden file handling: use `/.` syntax in `cp` fallback to include dotfiles ([`519fa8c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/519fa8c6adfffdbff922b9ab456b50655c65de8e))
- Fix `list_backups()` sorting by collecting lines in array before sort ([`519fa8c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/519fa8c6adfffdbff922b9ab456b50655c65de8e))
- Fix `show_diff()` trap scope using `RETURN` instead of `EXIT` ([`519fa8c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/519fa8c6adfffdbff922b9ab456b50655c65de8e))
- Prevent `.git` directory from being copied from source during backup ([`519fa8c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/519fa8c6adfffdbff922b9ab456b50655c65de8e))
- Resolve nested trap issue in `install.sh` by passing `temp_dir` between functions ([`519fa8c`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/519fa8c6adfffdbff922b9ab456b50655c65de8e))
- Exclude `.gitignore` from rsync `--delete` to prevent backup repo gitignore removal ([`90ab467`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/90ab467899e9aec1087ac4da70d84befd5503f22))

### Testing

- Initial test infrastructure: `scripts/run_tests.sh`, `scripts/test_lib.sh` assertion helpers
- Test scripts for dry-run, config support, conflict detection, and E2E operations
- Test fixtures for claude, codex, and cursor agents

### Documentation

- Remove shell comments from install code blocks for clean copy-paste ([`86e4e9d`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/86e4e9db401262916060addeeaec904d64fd739f))
- Add AGENTS.md for multi-agent development conventions
- Expand README with export/import, config, dry-run, and completion documentation

### Script Growth

`asb` grew from 687 lines (v0.1.0) to 1,726 lines, adding 4 new commands (`export`, `import`, `config`, `completion`) and global option parsing.

---

## [v0.1.0] — 2026-01-19

Initial release at commit [`2d3bed4`](https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/2d3bed44895f4c401817c70c19486179eba1ac1b). No git tag or GitHub Release.

### Core Capabilities

- **Git-versioned backups** — Every backup is a git commit with full history; each agent gets its own repository under `~/.agent_settings_backups/`
- **Core commands** — `backup [agents...]`, `restore <agent> [commit]`, `list`, `history <agent>`, `diff <agent>`, `init`, `help`, `version`
- **Efficient syncing** — Uses `rsync` for incremental backups with automatic fallback to `cp`

### Agent Support

- **10 supported agents** — Claude (`~/.claude`), Codex (`~/.codex`), Cursor (`~/.cursor`), Gemini (`~/.gemini`), Cline (`~/.cline`), Amp (`~/.amp`), Aider (`~/.aider`), OpenCode (`~/.opencode`), Factory (`~/.factory`), Windsurf (`~/.windsurf`)

### Configuration

- **Environment variables** — `ASB_BACKUP_ROOT`, `ASB_AUTO_COMMIT`, `ASB_VERBOSE` for configuration without files
- **Default exclusions** — `*.log`, `cache/`, `Cache/`, `.cache/`, `*.sqlite3-wal`, `*.sqlite3-shm` excluded from backup via `.gitignore`

### Installation and Distribution

- **Curl-pipe installer** — `curl -fsSL .../install.sh | bash` with self-cleanup
- **GitHub Actions release workflow** — Triggered on `v*` tags; runs tests, creates checksums, publishes GitHub release with `asb` binary and `checksums.txt`

### Architecture

- Single-file bash script (687 lines), no external dependencies beyond `git` (and optionally `rsync`)
- Associative arrays for agent definitions (`AGENT_FOLDERS`, `AGENT_NAMES`)
- Colored, structured terminal output with `NO_COLOR` support

---

[v0.3.0]: https://github.com/Dicklesworthstone/agent_settings_backup_script/compare/v0.2.0...main
[v0.2.0]: https://github.com/Dicklesworthstone/agent_settings_backup_script/releases/tag/v0.2.0
[v0.1.0]: https://github.com/Dicklesworthstone/agent_settings_backup_script/commit/2d3bed44895f4c401817c70c19486179eba1ac1b
