#!/usr/bin/env bash
# shellcheck shell=bash
# gh.sh — one gh CLI config dir per profile.

# sc_gh_logged_in <config-dir>
# GH_TOKEN/GITHUB_TOKEN in the environment make `gh auth status` succeed no
# matter which config dir is active, which used to report logins that never
# happened. Clearing them in a subshell is what makes this check mean something.
sc_gh_logged_in() {
	has_cmd gh || return 1
	(
		unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
		GH_CONFIG_DIR="$1" gh auth status --hostname github.com >/dev/null 2>&1
	)
}

# sc_gh_user <config-dir> — the logged-in login, or nothing.
sc_gh_user() {
	has_cmd gh || return 1
	(
		unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
		GH_CONFIG_DIR="$1" gh api user --jq .login 2>/dev/null
	)
}

# sc_gh_login <config-dir> <token>
sc_gh_login() {
	local dir="$1" token="$2"
	has_cmd gh || return 1
	[[ -n "$token" ]] || return 1
	if is_dry; then
		dry "gh auth login (config dir $dir)"
		return 0
	fi
	(
		unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
		export GH_CONFIG_DIR="$dir"
		gh auth login --hostname github.com --git-protocol ssh --with-token <<<"$token"
	)
}
