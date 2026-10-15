# switchcraft 🪄

[![ci](https://github.com/FernandoPazCavalcante/switchcraft/actions/workflows/ci.yml/badge.svg)](https://github.com/FernandoPazCavalcante/switchcraft/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![shell: bash](https://img.shields.io/badge/shell-bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![platform: linux | macos](https://img.shields.io/badge/platform-linux%20%7C%20macos-lightgrey.svg)](#requirements)

**The folder decides who you are.** Your GitHub identity, SSH key, commit
signature, `gh` account and Claude Code login all switch when you `cd`.

*switch* + witch*craft* — the magic of switching accounts without doing a thing.

🇧🇷 [Leia em português](README.pt-BR.md)

<!-- Replace this block with docs/demo.gif once recorded: vhs docs/demo.tape -->

```console
$ cd ~/projects/work && switchcraft status

  directory   /home/you/projects/work
  profile     work
  git         Your Name <you@company.com>
  ssh key     /home/you/.ssh/id_ed25519_work
  claude      /home/you/.claude-work           ✓
  gh          /home/you/.config/gh-work        ✓
  effective   you@company.com                  ✓

$ cd ~/projects/personal && switchcraft status

  directory   /home/you/projects/personal
  profile     personal
  git         Your Name <you@gmail.com>
  ssh key     /home/you/.ssh/id_ed25519_personal
  claude      /home/you/.claude-personal       ✓
  gh          /home/you/.config/gh-personal    ✓
  effective   you@gmail.com                    ✓
```

Nothing was typed between those two commands except `cd`.

## Why

If you work across more than one organization at the same time — a day job and
a client, an employer and your own side projects — every context has its own
GitHub account, its own SSH key, and now its own Claude Code login.

Forget to switch once and you push a commit signed with the wrong identity to
the wrong org. You find out in the PR, in front of everyone.

The usual answers each cover one layer. `includeIf` handles name and email.
`~/.ssh/config` handles keys. An alias handles `CLAUDE_CONFIG_DIR`. You end up
maintaining four mechanisms that can disagree with each other, and nothing tells
you when one of them is wrong.

switchcraft wires all five layers to the same switch — the directory you are in —
and ships a `doctor` that tells you which layer is broken when something is off.

## Quick start

```bash
git clone https://github.com/FernandoPazCavalcante/switchcraft.git
cd switchcraft && ./install.sh
```

That puts `switchcraft` on your PATH and asks where your projects live. Then add
an identity per account:

```bash
switchcraft add work \
  --name 'Your Name' --email you@company.com --github-user you-at-work

switchcraft add personal \
  --name 'Your Name' --email you@gmail.com --github-user you
```

Each `add` generates an SSH key, writes a git profile, creates the folder, and
wires its `.envrc`. Two manual steps are left, once per account:

1. **Register the public key on GitHub** — add `~/.ssh/id_ed25519_<profile>.pub`
   **twice**: once as an *Authentication key* (clone/push) and once as a
   *Signing key* (so commits show as Verified).
2. **Log in to Claude Code** from inside the folder:
   ```bash
   cd ~/projects/work && claude   # /login, then leave with /exit
   ```

Then check your work:

```bash
switchcraft doctor
```

It names every missing piece and the exact command to fix it.

## Commands

| Command | What it does |
| --- | --- |
| `switchcraft init` | create the config |
| `switchcraft add <profile>` | add an identity (key, git profile, folder, `.envrc`) |
| `switchcraft link <profile> <dir>` | bind **any** directory to a profile |
| `switchcraft unlink <dir>` | stop managing a directory, leaving its files alone |
| `switchcraft list` | every profile and where it applies |
| `switchcraft status [dir]` | which identity applies here, and whether it is live |
| `switchcraft doctor` | check all five layers and say what is missing |
| `switchcraft apply` | reconcile everything from the config (idempotent) |
| `switchcraft remove <profile>` | drop an identity (`--purge` also deletes its key and history) |
| `switchcraft uninstall` | reverse every change on this machine |

Add `--dry-run` to any command to see what it would write without writing it.

## How it works

| Layer | Mechanism |
| --- | --- |
| Git identity (name/email) | `includeIf "gitdir:…"` in your global git config |
| SSH key per account | `core.sshCommand` per profile (remotes stay plain `git@github.com`) |
| Commit signing | `user.signingkey` per profile + `gpg.format = ssh` |
| HTTPS credentials | `credential.helper = store --file=…` per profile |
| GitHub CLI account | `GH_CONFIG_DIR` exported by `.envrc` (direnv) |
| Claude Code account | `CLAUDE_CONFIG_DIR` exported by `.envrc` (direnv) |

Commits are signed with the same SSH key that authenticates the account, so
there is no GPG to manage.

Everything switchcraft writes into a file you already own goes between
`# >>> switchcraft >>>` fences, so a re-run replaces only its own block and
`uninstall` reverses it exactly. Your global git config is backed up once,
before the first edit, to `~/.gitconfig.switchcraft.bak`.

### Identity by remote, not just by folder

A directory rule cannot help a repo you cloned somewhere else. On git 2.36+ you
can match on the remote URL instead, so the identity follows the *repository*
wherever it lands:

```bash
switchcraft add work --name 'Your Name' --email you@company.com \
  --remote 'git@github.com:company/**'
```

Any clone of that org gets the work identity, from any path on disk.

## Why not just…

| Instead of switchcraft | What that gives you | What it leaves out |
| --- | --- | --- |
| `includeIf` by hand | name and email per folder | SSH key, signing, `gh`, Claude Code — and you maintain the blocks yourself |
| `git config --local` per repo | the right identity in that one repo | you have to remember, for every new clone. Forgetting is the whole problem |
| an alias for `CLAUDE_CONFIG_DIR` | two Claude accounts | you still pick the account by typing the right alias, and git/ssh/gh are untouched |
| `gh auth switch` | the `gh` account | it is global, not per directory, and says nothing about git, ssh or Claude |
| `~/.ssh/config` host aliases | a key per account | every remote URL has to be rewritten; identity, `gh` and Claude are untouched |
| [gitswitch](https://github.com/UzairRehman4/gitswitch), [gh-account-switcher](https://github.com/calghar/gh-account-switcher) | git identity and SSH per folder | no Claude Code, no per-directory `gh`, no `doctor`, no reversible uninstall |

switchcraft is those five layers on one switch, reversible, with a `doctor` that
tells you which layer is broken.

## Requirements

- **bash** 3.2+ (so stock macOS works), **git**, **ssh-keygen**
- **[direnv](https://direnv.net)** — installed for you via brew, apt, pacman, dnf, apk or zypper
- **git 2.36+** only for `--remote` matching; directory matching works on any version
- optional: **[gh](https://cli.github.com)** for per-directory GitHub CLI accounts
- optional: **[Claude Code](https://claude.com/claude-code)** for per-directory logins

Shells: bash, zsh, fish, tcsh and elvish get their hook written automatically.
Anything else (nushell, for example) prints the line to add yourself.

Tested on Linux and macOS in CI.

## Gotchas

These cost real time to discover. They are properties of the tools involved, not
bugs in switchcraft.

- **`cd` inside a running Claude session does not switch accounts.** Environment
  variables are fixed when a process starts, so direnv cannot change a live
  session. Exit and start `claude` again from the target folder.
- **`gh` inside a Claude session follows the session's directory, not your
  `cd`.** Same reason: `GH_CONFIG_DIR` was inherited at launch.
- **Do not Ctrl+C after logging in to Claude Code.** Credentials are flushed to
  disk on a graceful shutdown; SIGINT kills the process first and the login is
  silently lost. Leave with `/exit` or Ctrl+D.
- **The path in your git config may not look like the one you typed.** git
  resolves symlinks before matching `includeIf`, so switchcraft writes the
  *canonical* path into the rule. On macOS that is the normal case rather than
  an edge case — `/var` is a symlink to `/private/var`, so anything under
  `$TMPDIR` is affected. Writing the logical path would mean the rule never
  fires and you commit as your global identity, which is the whole failure this
  tool exists to prevent.
- **Clone via SSH** (`git@github.com:…`) to use the per-account keys. HTTPS
  remotes work too, through the per-profile credential file, but then the key
  and the signature are not involved.

## Security

- Private keys, tokens and Claude credentials are generated or fetched **per
  machine** and never enter this repository. The repo versions structure and
  templates only — which is why it can be public.
- Keys are generated **without a passphrase** so that `cd` stays frictionless.
  Set `SC_ASK_PASSPHRASE=1` before `add` or `apply` to be prompted instead, and
  use an agent.
- Personal access tokens are **not stored in the config**. Point switchcraft at
  a command that prints one instead, so the secret stays in your password
  manager:
  ```bash
  switchcraft add work --token-cmd 'pass show github/work'
  ```
  The resolved token lands in `~/.config/switchcraft/credentials-<profile>`
  (mode 600), outside your working tree.
- Found something sensitive? See [SECURITY.md](SECURITY.md).

## Troubleshooting

Run `switchcraft doctor` first — it covers most of this. Then:

| Symptom | Cause | Fix |
| --- | --- | --- |
| commits use the wrong email | the directory is not linked, or a parent directory is linked to another profile | `switchcraft status` in that folder; it names the profile that wins |
| `echo $CLAUDE_CONFIG_DIR` is empty | direnv's hook is not loaded, or the dir is not allowed | open a new terminal, then `direnv allow <dir>` |
| `gh` shows the wrong account | `GH_TOKEN` or `GITHUB_TOKEN` is exported in your environment and overrides everything | `unset GH_TOKEN GITHUB_TOKEN` |
| commits show "No signature" locally | the allowed-signers file is missing | `switchcraft apply` (GitHub verifies regardless — this is cosmetic) |
| key rejected by GitHub | the public key is not registered, or only as an auth key | add the `.pub` twice: Authentication **and** Signing |
| Claude Code asks to log in again | the previous session was killed with Ctrl+C | log in again and leave with `/exit` |

## Uninstall

```bash
./uninstall.sh            # removes every block switchcraft wrote
./uninstall.sh --purge    # also deletes the keys, gh and Claude config dirs
```

Without `--purge` your SSH keys, Claude conversation history and config are
kept. Project files are never touched.

## Upgrading from v1

v1 kept your data in a `.env` inside the clone. v2 moves it to
`~/.config/switchcraft/config` so the tool no longer depends on where it was
cloned. Running `./install.sh` migrates an existing `.env` automatically; only
tokens are not carried over, since v2 reads them from a command instead.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
The test suite runs against a throwaway `$HOME`, so you can hack on the
installer without risking your own setup:

```bash
bats tests/
```

Good first issues are
[tagged](https://github.com/FernandoPazCavalcante/switchcraft/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).

## License

[MIT](LICENSE) © Fernando Paz Silva Cavalcante
