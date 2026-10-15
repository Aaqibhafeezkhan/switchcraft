# Contributing

Thanks for looking. switchcraft is a small bash project, so the bar to
contribute is mostly "can you run the tests" — and you can, safely.

## The tests never touch your machine

Every test runs against a throwaway `$HOME` created by `mktemp`, with stubs for
`direnv` and `gh` on the `PATH`. Nothing in `tests/` can modify your real git
config, SSH keys or shell rc.

```bash
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
/tmp/bats/bin/bats tests/
```

Or with bats already installed:

```bash
bats tests/
bats tests/safety.bats          # one file
bats --filter 'symlink' tests/  # one test
```

## Before you open a PR

The CI runs exactly these three things:

```bash
shellcheck --shell=bash --severity=style \
  bin/switchcraft lib/*.sh install.sh uninstall.sh tests/test_helper.bash
shfmt -d bin/switchcraft lib/*.sh install.sh uninstall.sh tests/test_helper.bash
bats tests/
```

Run `shfmt -w` to fix formatting (tabs, as in `.editorconfig`).

## Project shape

```
bin/switchcraft     subcommand dispatch, one cmd_* function per command
lib/common.sh       logging, dry-run plumbing, fenced-block editing, templating
lib/config.sh       reads and writes ~/.config/switchcraft/config
lib/git.sh          git profiles, includeIf block, signing, HTTPS credentials
lib/ssh.sh          one ed25519 key per profile
lib/direnv.sh       per-shell hook, and the .envrc in each directory
lib/gh.sh           one gh config dir per profile
templates/          the rendered git profile
```

## Rules that matter

These are the invariants the test suite exists to protect. A PR that breaks one
will fail CI:

1. **Never clobber a file the user owns.** Everything written into an existing
   file goes between `# >>> switchcraft >>>` fences, via `sc_block_apply`.
2. **Never break a symlink.** `~/.gitconfig` is often a symlink into a dotfiles
   repo. Write through it (`sc_resolve`), never replace it.
3. **Everything is idempotent.** Running `apply` twice must produce
   byte-identical files.
4. **Everything is reversible.** If you add a side effect, teach
   `cmd_uninstall` to undo it.
5. **`--dry-run` writes nothing.** Route new writes through `sc_write`,
   `sc_mkdir`, `sc_block_apply` or `sc_run` — never a bare redirect.
6. **The config is data, never code.** It is parsed, not sourced. A backtick in
   a display name must not execute.
7. **bash 3.2 compatible**, so stock macOS works: no associative arrays, no
   `mapfile`, no `${var,,}`.

## Style

- Conventional commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`).
- Comments explain *why*, not *what*. If a line looks odd, say what breaks
  without it.
- User-facing strings use the existing `info`/`ok`/`warn`/`note`/`die` helpers.

## Recording the demo

`docs/demo.tape` is the source of the README demo. With
[vhs](https://github.com/charmbracelet/vhs) installed:

```bash
vhs docs/demo.tape    # writes docs/demo.gif
```

## Scope

switchcraft switches identity by directory. In scope: more forges (GitLab,
Codeberg), more shells, more agent CLIs, better diagnostics. Out of scope:
managing the contents of your repos, or anything that needs a daemon.
