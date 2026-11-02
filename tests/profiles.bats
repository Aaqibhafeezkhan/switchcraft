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

@test "a profile without Terraform gets no TF_CLI_CONFIG_FILE export" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	add_profile work work@company.com
	# The export makes Terraform ignore the user's own ~/.terraformrc, so it
	# must never appear for a profile that said nothing about Terraform.
	! grep -q TF_CLI_CONFIG_FILE "$SANDBOX/projects/work/.envrc"
	[ ! -e "$(tfrc work)" ]
	[ "$(grep -c '^export' "$SANDBOX/projects/work/.envrc")" -eq 2 ]
}

@test "--tf-token-cmd writes a tfrc and exports TF_CLI_CONFIG_FILE" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	local cmd
	cmd="$(tf_token_script ATfake.atlasv1.s3cr3t)"
	sc add work --name 'Test User' --email work@company.com --tf-token-cmd "$cmd" >/dev/null 2>&1
	grep -q "TF_CLI_CONFIG_FILE=$(tfrc work)" "$SANDBOX/projects/work/.envrc"
	grep -q 'credentials "app.terraform.io"' "$(tfrc work)"
	grep -q 'ATfake.atlasv1.s3cr3t' "$(tfrc work)"
}

@test "the generated tfrc is not world readable" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	run file_mode "$(tfrc work)"
	[ "$output" = "600" ]
}

@test "repeatable --tf-host writes one credentials block per host" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" \
		--tf-host app.terraform.io --tf-host my-tfe.corp.com >/dev/null 2>&1
	[ "$(grep -c '^credentials ' "$(tfrc work)")" -eq 2 ]
	grep -q 'credentials "my-tfe.corp.com"' "$(tfrc work)"
}

@test "a Terraform profile with no token still gets a tfrc, with the reason in it" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	# tf_host alone enables the layer; the export already points here, so the
	# file has to exist even when the token could not be resolved.
	sc add work --name 'Test User' --email work@company.com \
		--tf-host app.terraform.io >/dev/null 2>&1
	[ -f "$(tfrc work)" ]
	grep -q 'No token for app.terraform.io' "$(tfrc work)"
	! grep -q 'token = ""' "$(tfrc work)"
}

@test "a bad --tf-host is rejected" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	run sc add work --name x --email x@y.z --tf-host 'not a host'
	[ "$status" -ne 0 ]
}

@test "list and status show the terraform layer only when it applies" {
	sc init --projects-root "$SANDBOX/projects" >/dev/null
	sc add work --name 'Test User' --email work@company.com \
		--tf-token-cmd "$(tf_token_script ATfake.atlasv1.s3cr3t)" >/dev/null 2>&1
	add_profile personal me@gmail.com

	run sc list
	[[ "$output" == *"terraform"* ]]
	[[ "$output" == *"app.terraform.io"* ]]

	run sc status "$SANDBOX/projects/work"
	[[ "$output" == *"terraform"* ]]
	run sc status "$SANDBOX/projects/personal"
	[[ "$output" != *"terraform"* ]]
}
