# Security policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub's private vulnerability reporting](https://github.com/FernandoPazCavalcante/switchcraft/security/advisories/new)
rather than opening a public issue. I will acknowledge within a few days.

## What this tool touches

switchcraft is a local configuration tool. It reads and writes:

| Path | What for |
| --- | --- |
| global git config (`~/.gitconfig` or `$XDG_CONFIG_HOME/git/config`) | the `includeIf` block, inside fences, backed up once first |
| `~/.config/git-profiles/<profile>` | the rendered per-profile git config |
| `~/.ssh/id_ed25519_<profile>{,.pub}` | one key pair per account, mode 600 |
| `~/.config/switchcraft/config` | your profiles, mode 600 |
| `~/.config/switchcraft/credentials-<profile>` | resolved HTTPS token, mode 600 |
| `~/.config/switchcraft/allowed_signers` | lets local git verify your own signatures |
| your shell rc | direnv's hook, inside fences |
| each linked directory's `.envrc` | the two exports, inside fences |
| `~/.claude-<profile>/`, `~/.config/gh-<profile>/` | created; written by those tools |

It never sends anything anywhere. The only network access is `ssh -T
git@github.com` during `doctor`, to ask GitHub which account a key belongs to.

## Threat model and known trade-offs

Be aware of these; they are deliberate choices, not oversights.

- **Keys have no passphrase by default.** The point of the tool is that `cd` is
  enough, and a passphrase prompt on every push defeats that. Run
  `SC_ASK_PASSPHRASE=1 switchcraft apply` to be prompted instead, and use
  `ssh-agent`. Anyone with read access to your `$HOME` can use an unprotected
  key.
- **Tokens are resolved from a command, not stored.** `token_cmd` keeps the
  secret in your password manager. The *resolved* token is still written to
  `credentials-<profile>` in plaintext (mode 600) because that is the format
  git's `store` helper reads. Omit `--token-cmd` entirely if you only use SSH
  remotes — nothing is written then.
- **`token_cmd` is executed.** It is a command line you wrote, run as you. Do
  not put a config file you did not write into `~/.config/switchcraft/`.
- **Per-directory isolation is not a security boundary.** It prevents mistakes,
  not attacks. Any process you run can read every profile's keys and configs.
- **`GH_TOKEN`/`GITHUB_TOKEN` in your environment override everything**,
  including the per-directory `gh` account. `doctor` warns when it sees one.

## Not vulnerabilities

- A profile not applying because the path is a symlink — that is the documented
  gotcha; `doctor` reports it.
- Secrets in your own `~/.config/switchcraft/` — that file is yours, mode 600.
