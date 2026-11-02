#!/usr/bin/env bats
# The config is parsed, never sourced. These tests pin that contract.
load test_helper

setup_config() {
	load_libs
	export SWITCHCRAFT_CONFIG="$SANDBOX/cfg"
	cat >"$SANDBOX/cfg" <<'EOF'
projects_root = /home/me/projects
sign_commits  = true

[profile work]
name  = Ada & Grace | Co
email = ada@company.com
dir   = /home/me/projects/work
dir   = /mnt/other/client
remote = git@github.com:company/*
tf_token_cmd = printf tok-work
tf_host = app.terraform.io
tf_host = my-tfe.corp.com

[profile personal]
name  = Ada
email = ada@gmail.com
dir   = /home/me/projects/personal
EOF
}

@test "global keys are read" {
	setup_config
	[ "$(sc_cfg_global projects_root)" = "/home/me/projects" ]
	[ "$(sc_cfg_global sign_commits)" = "true" ]
	[ "$(sc_cfg_global missing fallback)" = "fallback" ]
}

@test "profiles are listed in order" {
	setup_config
	run sc_cfg_profiles
	[ "${lines[0]}" = "work" ]
	[ "${lines[1]}" = "personal" ]
}

@test "values with metacharacters round-trip literally" {
	setup_config
	[ "$(sc_cfg_get work name)" = "Ada & Grace | Co" ]
}

@test "repeatable keys return every value" {
	setup_config
	run sc_cfg_get_all work dir
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "/home/me/projects/work" ]
	[ "${lines[1]}" = "/mnt/other/client" ]
}

@test "keys do not leak across sections" {
	setup_config
	[ "$(sc_cfg_get personal email)" = "ada@gmail.com" ]
	run sc_cfg_get_all personal remote
	[ -z "$output" ]
}

@test "the deepest matching directory decides the profile" {
	setup_config
	[ "$(sc_cfg_profile_for_dir /home/me/projects/work)" = "work" ]
	[ "$(sc_cfg_profile_for_dir /home/me/projects/work/repo/deep)" = "work" ]
	[ "$(sc_cfg_profile_for_dir /mnt/other/client)" = "work" ]
	[ -z "$(sc_cfg_profile_for_dir /tmp/unmanaged)" ]
}

@test "a sibling directory with a shared prefix does not match" {
	setup_config
	[ -z "$(sc_cfg_profile_for_dir /home/me/projects/work-other)" ]
}

@test "append and remove edit only the target section" {
	setup_config
	sc_cfg_append work dir /new/path
	run sc_cfg_get_all work dir
	[ "${#lines[@]}" -eq 3 ]
	[ "$(sc_cfg_get personal email)" = "ada@gmail.com" ]
	sc_cfg_remove_value work dir /new/path
	run sc_cfg_get_all work dir
	[ "${#lines[@]}" -eq 2 ]
}

@test "removing a profile leaves the others intact" {
	setup_config
	sc_cfg_remove_profile work
	run sc_cfg_profiles
	[ "$output" = "personal" ]
	[ "$(sc_cfg_get personal email)" = "ada@gmail.com" ]
	[ "$(sc_cfg_global projects_root)" = "/home/me/projects" ]
}

@test "comments and blank lines are ignored" {
	load_libs
	export SWITCHCRAFT_CONFIG="$SANDBOX/cfg2"
	printf '# a comment\n\nprojects_root = /x\n\n[profile p]\n# another\nemail = p@x.com\n' >"$SANDBOX/cfg2"
	[ "$(sc_cfg_global projects_root)" = "/x" ]
	[ "$(sc_cfg_get p email)" = "p@x.com" ]
}

@test "shell metacharacters in the config are never executed" {
	load_libs
	export SWITCHCRAFT_CONFIG="$SANDBOX/cfg3"
	printf 'projects_root = /x\n[profile p]\nname = $(touch %s/pwned)`touch %s/pwned2`\n' \
		"$SANDBOX" "$SANDBOX" >"$SANDBOX/cfg3"
	run sc_cfg_get p name
	[ ! -e "$SANDBOX/pwned" ]
	[ ! -e "$SANDBOX/pwned2" ]
}

@test "tf_host defaults to app.terraform.io and is repeatable" {
	setup_config
	run sc_tf_hosts work
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "app.terraform.io" ]
	[ "${lines[1]}" = "my-tfe.corp.com" ]
	run sc_tf_hosts personal
	[ "$output" = "app.terraform.io" ]
}

@test "the Terraform layer is enabled by its data, not a flag" {
	setup_config
	sc_tf_enabled work
	! sc_tf_enabled personal
	sc_tf_any_enabled
}

@test "tf_rc overrides the generated path" {
	setup_config
	[ "$(sc_tf_rc_file personal)" = "$SANDBOX/.config/switchcraft/terraform-personal.tfrc" ]
	sc_cfg_append personal tf_rc /somewhere/else.tfrc
	[ "$(sc_tf_rc_file personal)" = "/somewhere/else.tfrc" ]
}

@test "TF_TOKEN_ names follow Terraform's own encoding" {
	load_libs
	[ "$(sc_tf_env_name app.terraform.io)" = "TF_TOKEN_app_terraform_io" ]
	# hyphens double, so a host containing both can still be decoded
	[ "$(sc_tf_env_name my-tfe.corp.com)" = "TF_TOKEN_my__tfe_corp_com" ]
	[ "$(sc_tf_env_name APP.Terraform.IO)" = "TF_TOKEN_app_terraform_io" ]
}

@test "a non-ASCII host is refused rather than encoded wrong" {
	load_libs
	# Terraform punycodes these and bash cannot, so they must not pass. Under
	# en_US.UTF-8 the range a-z collates accented letters, which is why the
	# validator pins LC_ALL=C.
	! sc_tf_host_ok 'café.fr'
	! sc_tf_host_ok 'not a host'
	! sc_tf_host_ok '-bad.com'
	sc_tf_host_ok 'app.terraform.io'
	sc_tf_host_ok 'my-tfe.corp.com'
}

@test "a value that is not a token is refused rather than escaped" {
	load_libs
	sc_tf_token_ok 'ATxxxx.atlasv1.yy-_=~+/'
	! sc_tf_token_ok 'tok"quote'
	! sc_tf_token_ok 'tok$(touch /tmp/sc-pwned)'
	! sc_tf_token_ok ''
	[ ! -e /tmp/sc-pwned ]
}

@test "the HCL escape neutralises quotes and backslashes" {
	load_libs
	[ "$(sc_tf_escape 'a"b\c')" = 'a\"b\\c' ]
}
