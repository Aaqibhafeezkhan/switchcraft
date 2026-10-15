#!/usr/bin/env bats
# The regressions that matter most: switchcraft must never eat a file it did
# not create.
load test_helper

@test "a gitconfig symlinked into a dotfiles repo is written through, not replaced" {
	mkdir -p "$SANDBOX/dotfiles"
	printf '[alias]\n\tst = status\n' >"$SANDBOX/dotfiles/gitconfig"
	ln -s "$SANDBOX/dotfiles/gitconfig" "$SANDBOX/.gitconfig"

	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com

	[ -L "$SANDBOX/.gitconfig" ]
	[ "$(readlink "$SANDBOX/.gitconfig")" = "$SANDBOX/dotfiles/gitconfig" ]
	grep -q 'st = status' "$SANDBOX/dotfiles/gitconfig"
	grep -q 'switchcraft' "$SANDBOX/dotfiles/gitconfig"
}

@test "pre-existing gitconfig settings survive" {
	printf '[user]\n\tname = Preexisting\n[alias]\n\tco = checkout\n' >"$SANDBOX/.gitconfig"
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	gitconfig | grep -q 'name = Preexisting'
	gitconfig | grep -q 'co = checkout'
}

@test "a backup is taken before the first gitconfig edit" {
	printf '[alias]\n\tst = status\n' >"$SANDBOX/.gitconfig"
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	[ -f "$SANDBOX/.gitconfig.switchcraft.bak" ]
	grep -q 'st = status' "$SANDBOX/.gitconfig.switchcraft.bak"
	! grep -q 'switchcraft' "$SANDBOX/.gitconfig.switchcraft.bak"
}

@test "the user's own .envrc exports survive a re-apply" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	echo 'export MY_OWN_VAR=keepme' >>"$SANDBOX/projects/work/.envrc"
	sc apply >/dev/null 2>&1
	grep -q 'MY_OWN_VAR=keepme' "$SANDBOX/projects/work/.envrc"
	grep -q 'CLAUDE_CONFIG_DIR' "$SANDBOX/projects/work/.envrc"
}

@test "an existing direnv hook is left alone" {
	printf '# mine\neval "$(direnv hook bash)"\n' >"$SANDBOX/.bashrc"
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	[ "$(grep -c 'direnv hook' "$SANDBOX/.bashrc")" -eq 1 ]
	grep -q '# mine' "$SANDBOX/.bashrc"
}

@test "credentials for other hosts are not discarded" {
	load_libs
	local cred="$SANDBOX/creds"
	printf 'https://someone:tok@gitlab.com\n' >"$cred"
	sc_git_cred_upsert "$cred" user1 tok1 github.com
	grep -q 'gitlab.com' "$cred"
	grep -q 'https://user1:tok1@github.com' "$cred"
	# replacing the github entry must not duplicate it
	sc_git_cred_upsert "$cred" user1 tok2 github.com
	[ "$(grep -c 'github.com' "$cred")" -eq 1 ]
	grep -q 'tok2' "$cred"
}

@test "credential files are created mode 600" {
	load_libs
	sc_git_cred_upsert "$SANDBOX/creds" user1 tok1 github.com
	run file_mode "$SANDBOX/creds"
	[ "$output" = "600" ]
}

@test "dry-run writes absolutely nothing" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	printf '[alias]\n\tst = status\n' >"$SANDBOX/.gitconfig"
	cp "$SANDBOX/.gitconfig" "$SANDBOX/before"
	run sc --dry-run add work --name x --email x@y.z --github-user x
	[ "$status" -eq 0 ]
	diff -q "$SANDBOX/before" "$SANDBOX/.gitconfig"
	[ ! -e "$SANDBOX/.ssh/id_ed25519_work" ]
	[ ! -e "$SANDBOX/projects/work/.envrc" ]
	! grep -q 'profile work' "$SANDBOX/.config/switchcraft/config"
}

@test "a display name containing shell metacharacters is stored literally" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add weird --name 'A & B | C \\ $(touch /tmp/sc-pwned)' --email w@x.com --github-user w >/dev/null 2>&1
	[ ! -e /tmp/sc-pwned ]
	grep -q 'A & B | C' "$SANDBOX/.config/git-profiles/weird"
}
