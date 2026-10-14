# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — unreleased

Rewritten from a one-shot installer into a CLI. Your configuration now lives in
`~/.config/switchcraft/config` instead of a `.env` inside the clone, so the tool
no longer depends on where it was cloned.

### Added

- A `switchcraft` command with `init`, `add`, `remove`, `link`, `unlink`,
  `list`, `status`, `apply`, `doctor` and `uninstall`.
- `switchcraft link <profile> <dir>` binds **any** directory to a profile. v1
  could only manage folders directly under `PROJECTS_ROOT`.
- `--remote` matching via `includeIf "hasconfig:remote.*.url:…"` (git 2.36+), so
  an identity can follow a repository instead of a path.
- `switchcraft doctor`: checks keys, their registration on GitHub, the direnv
  hook, signing settings, symlinked paths that silently defeat `includeIf`, a
  leaking `GH_TOKEN`, Claude Code logins and credential permissions.
- `switchcraft status`: the identity that applies here, and whether direnv has
  actually made it live.
- `--dry-run` on every command.
- `uninstall.sh` / `switchcraft uninstall`, which reverses every change.
- SSH commit signing is configured automatically, including the
  `allowedSignersFile` that makes local verification work.
- Tokens are read from a command (`--token-cmd 'pass show github/work'`) instead
  of being stored in a config file.
- 41 bats tests running against a throwaway `$HOME`, plus CI on Linux and macOS
  with shellcheck and shfmt.
- `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`.

### Fixed

- The global git config is no longer replaced with `mv`. A `~/.gitconfig` that
  is a symlink into a dotfiles repo is written **through**, keeping the symlink,
  and a backup is taken once before the first edit.
- `.envrc` is edited between fences instead of being truncated, so your own
  exports in a managed directory survive a re-run.
- `.git-credentials` entries for other hosts are preserved instead of being
  overwritten.
- The direnv hook is written with the right syntax to the right file per shell.
  fish previously got bash syntax appended to `~/.bashrc`.
- `gh auth status` is checked with `GH_TOKEN`/`GITHUB_TOKEN` cleared, so a token
  in the environment can no longer make switchcraft report a login that never
  happened.
- Template rendering is literal: `&`, `|` and `\` in a display name no longer
  corrupt the generated profile.
- Profile names are validated, so a space or a slash cannot leak into paths.
- `apt-get update` runs before `apt-get install`, which failed on fresh
  containers.
- `XDG_CONFIG_HOME` is respected, and `~/.config/git/config` is used as the
  global config when that is what git would read.
- Credential files moved out of the working tree into `~/.config/switchcraft/`.

### Changed

- `./install.sh` now only puts `switchcraft` on your `PATH` and hands over to
  it. An existing v1 `.env` is migrated automatically.

## [1.0.0] — 2026-08-02

First release: directory-based identity switching for GitHub and Claude Code via
`includeIf`, a dedicated SSH key per account, SSH commit signing, and
`CLAUDE_CONFIG_DIR` through direnv. Idempotent `install.sh` with personal data
in a gitignored `.env`.
