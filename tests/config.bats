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
