#!/usr/bin/env bash
# Every test runs against a throwaway $HOME, so running the suite can never
# touch your real git config, keys or shell rc.

setup() {
	SC_REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	# Canonical, so a test can compare paths literally. On macOS $TMPDIR sits
	# under /var, which is a symlink to /private/var, and switchcraft writes the
	# resolved path into its rules — as git requires. The two tests that cover
	# symlinked paths create their own symlink instead of relying on this.
	SANDBOX="$(cd "$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/sc.XXXXXX")" && pwd -P)"

	export HOME="$SANDBOX"
	export XDG_CONFIG_HOME="$SANDBOX/.config"
	export SWITCHCRAFT_SHELL=/bin/bash
	export SC_OFFLINE=1 NO_COLOR=1 SC_YES=1
	export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
	unset GH_TOKEN GITHUB_TOKEN GH_CONFIG_DIR CLAUDE_CONFIG_DIR SWITCHCRAFT_CONFIG

	mkdir -p "$SANDBOX/projects"
	: >"$SANDBOX/.bashrc"
	SC="$SC_REPO/bin/switchcraft"
}

teardown() {
	[[ -n "${SANDBOX:-}" ]] && rm -rf "$SANDBOX"
	return 0
}

# sc <args...> — run the CLI under test
sc() { "$SC" "$@"; }

# add_profile <name> <email> — the common two-line fixture
add_profile() {
	sc add "$1" --name 'Test User' --email "$2" --github-user "gh-$1" >/dev/null 2>&1
}

# load_libs — for unit-testing library functions directly
load_libs() {
	export SC_ROOT="$SC_REPO" SC_LIB="$SC_REPO/lib" SC_TEMPLATES="$SC_REPO/templates"
	# shellcheck source=/dev/null
	for m in common config git ssh direnv gh; do source "$SC_REPO/lib/$m.sh"; done
}

gitconfig() { cat "$SANDBOX/.gitconfig"; }

# file_mode <path> — octal permissions on GNU and BSD alike
file_mode() {
	stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}
