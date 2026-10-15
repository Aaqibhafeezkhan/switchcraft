#!/usr/bin/env bats
load test_helper

@test "init creates a config with the projects root" {
	run sc init --projects-root "$SANDBOX/projects"
	[ "$status" -eq 0 ]
	[ -f "$SANDBOX/.config/switchcraft/config" ]
	grep -q "projects_root = $SANDBOX/projects" "$SANDBOX/.config/switchcraft/config"
}

@test "config file is not world readable" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	run file_mode "$SANDBOX/.config/switchcraft/config"
	[ "$output" = "600" ]
}

@test "add creates key, git profile, envrc and includeIf" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	run add_profile work work@company.com
	[ "$status" -eq 0 ]
	[ -f "$SANDBOX/.ssh/id_ed25519_work" ]
	[ -f "$SANDBOX/.ssh/id_ed25519_work.pub" ]
	[ -f "$SANDBOX/.config/git-profiles/work" ]
	[ -f "$SANDBOX/projects/work/.envrc" ]
	gitconfig | grep -q 'includeIf "gitdir:'"$SANDBOX"'/projects/work/"'
}

@test "the private key is not world readable" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run file_mode "$SANDBOX/.ssh/id_ed25519_work"
	[ "$output" = "600" ]
}

@test "git inside a managed directory uses the profile identity" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	git -C "$SANDBOX/projects/work" init -q
	run git -C "$SANDBOX/projects/work" config user.email
	[ "$output" = "work@company.com" ]
}

@test "two profiles stay independent" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	add_profile personal me@gmail.com
	git -C "$SANDBOX/projects/work" init -q
	git -C "$SANDBOX/projects/personal" init -q
	[ "$(git -C "$SANDBOX/projects/work" config user.email)" = "work@company.com" ]
	[ "$(git -C "$SANDBOX/projects/personal" config user.email)" = "me@gmail.com" ]
	[ "$(git -C "$SANDBOX/projects/work" config user.signingkey)" = "$SANDBOX/.ssh/id_ed25519_work.pub" ]
}

@test "envrc exports the per-profile Claude and gh dirs" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run cat "$SANDBOX/projects/work/.envrc"
	[[ "$output" == *"CLAUDE_CONFIG_DIR=$SANDBOX/.claude-work"* ]]
	[[ "$output" == *"GH_CONFIG_DIR=$SANDBOX/.config/gh-work"* ]]
}

@test "invalid profile names are rejected" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	run sc add "Work Account" --name x --email x@y.z
	[ "$status" -ne 0 ]
	run sc add "../escape" --name x --email x@y.z
	[ "$status" -ne 0 ]
}

@test "adding the same profile twice fails instead of clobbering" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	run sc add work --name other --email other@x.com
	[ "$status" -ne 0 ]
	grep -q 'email = work@company.com' "$SANDBOX/.config/switchcraft/config"
}

@test "list shows every profile" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	add_profile personal me@gmail.com
	run sc list
	[[ "$output" == *work* ]]
	[[ "$output" == *personal* ]]
	[[ "$output" == *me@gmail.com* ]]
}
