## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] `bats tests/` passes
- [ ] `shellcheck --shell=bash --severity=style bin/switchcraft lib/*.sh install.sh uninstall.sh` is clean
- [ ] `shfmt -d` is clean
- [ ] If it adds a side effect, `switchcraft uninstall` reverses it
- [ ] If it writes to a user-owned file, it goes between the `# >>> switchcraft >>>` fences
- [ ] `--dry-run` still writes nothing
- [ ] A test covers the change

## How I verified it

<!-- The commands you ran. A sandbox run is fine:
     HOME=$(mktemp -d) ./bin/switchcraft init --projects-root "$HOME/projects" -->
