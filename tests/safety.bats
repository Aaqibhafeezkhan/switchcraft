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

@test "a tfrc switchcraft did not write is never clobbered" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1

	# tf_rc points at the file switchcraft generates — but it can be aimed
	# anywhere, including at something the user wrote by hand.
	printf 'plugin_cache_dir = "/mine"\n' >"$SANDBOX/mine.tfrc"
	cp "$SANDBOX/mine.tfrc" "$SANDBOX/mine.before"
	load_libs
	sc_cfg_append work tf_rc "$SANDBOX/mine.tfrc"

	run sc apply
	[ "$status" -ne 0 ]
	[[ "$output" == *"point tf_rc elsewhere"* ]]
	diff -q "$SANDBOX/mine.before" "$SANDBOX/mine.tfrc"
}

@test "tf_rc_extra is appended verbatim and never executed" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	printf 'plugin_cache_dir = "/cache"\n# $(touch %s/pwned) `touch %s/pwned2`\n' \
		"$SANDBOX" "$SANDBOX" >"$SANDBOX/extra.tfrc"
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	load_libs
	sc_cfg_append work tf_rc_extra "$SANDBOX/extra.tfrc"
	sc apply >/dev/null 2>&1

	grep -q 'plugin_cache_dir = "/cache"' "$(tfrc work)"
	grep -qF 'touch '"$SANDBOX"'/pwned' "$(tfrc work)"
	[ ! -e "$SANDBOX/pwned" ]
	[ ! -e "$SANDBOX/pwned2" ]
}

@test "the Terraform token never reaches the config or an .envrc" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	! grep -q 's3cr3t' "$SANDBOX/.config/switchcraft/config"
	! grep -rq 's3cr3t' "$SANDBOX/projects"
	# the command that resolves it is what gets stored
	grep -q 'tf_token_cmd = ' "$SANDBOX/.config/switchcraft/config"
}

@test "dry-run writes no tfrc" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	run sc --dry-run add work --name x --email x@y.z \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)"
	[ "$status" -eq 0 ]
	[ ! -e "$(tfrc work)" ]
	! grep -q 'profile work' "$SANDBOX/.config/switchcraft/config"
}
