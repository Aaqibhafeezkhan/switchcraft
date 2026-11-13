#!/usr/bin/env bats
load test_helper

# Only subprocesses get this PATH: neither a real package manager nor sudo can
# be reached, even on CI runners that already have all the dependencies.
deps_sandbox() {
	export SC_DEPS_BIN="$SANDBOX/deps-bin" SC_DEPS_LOG="$SANDBOX/deps.log"
	export SC_DEPS_UID=1000 SC_DEPS_FAIL='' SC_DEPS_SKIP_INSTALL=''
	export SC_DEPS_STUBS="$BATS_TEST_DIRNAME/stubs"
	export SWITCHCRAFT_BIN_DIR="$SANDBOX/.local/bin"
	mkdir -p "$SC_DEPS_BIN"
	: >"$SC_DEPS_LOG"
	local tool
	for tool in bash sh awk basename cat chmod cp dirname git grep head ln mkdir mktemp readlink rm sed ssh-keygen stat touch tr; do
		ln -s "$(command -v "$tool")" "$SC_DEPS_BIN/$tool"
	done
	cat >"$SC_DEPS_BIN/id" <<'EOF'
#!/bin/sh
printf '%s\n' "$SC_DEPS_UID"
EOF
	cat >"$SC_DEPS_BIN/sudo" <<'EOF'
#!/bin/sh
printf 'sudo %s\n' "$*" >>"$SC_DEPS_LOG"
if [ "$SC_DEPS_FAIL" = sudo ]; then
	echo 'simulated sudo failure' >&2
	exit 1
fi
exec "$@"
EOF
	cat >"$SANDBOX/package-manager" <<'EOF'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >>"$SC_DEPS_LOG"
if [ "$1" = update ]; then
	if [ "$SC_DEPS_FAIL" = update ]; then
		echo 'simulated update failure' >&2
		exit 1
	fi
	exit 0
fi
if [ "$SC_DEPS_FAIL" = install ]; then
	echo 'simulated package installation failure' >&2
	exit 1
fi
[ "$SC_DEPS_SKIP_INSTALL" = all ] && exit 0
for package in "$@"; do
	case "$package" in
	direnv) tool=direnv ;;
	gh | github-cli) tool=gh ;;
	*) continue ;;
	esac
	[ "$SC_DEPS_SKIP_INSTALL" = "$tool" ] && continue
	cp "$SC_DEPS_STUBS/$tool" "$SC_DEPS_BIN/$tool"
done
exit 0
EOF
	chmod +x "$SC_DEPS_BIN/id" "$SC_DEPS_BIN/sudo" "$SANDBOX/package-manager"
	# Keep installation and v1 migration fixtures separate from the real clone.
	cp "$SC_REPO/install.sh" "$SANDBOX/repo/install.sh"
	ln -s "$SC_REPO/bin" "$SANDBOX/repo/bin"
}

deps_manager() { ln -s "$SANDBOX/package-manager" "$SC_DEPS_BIN/$1"; }
deps_present() { cp "$SC_DEPS_STUBS/$1" "$SC_DEPS_BIN/$1"; }
deps_install() { PATH="$SC_DEPS_BIN" "$SANDBOX/repo/install.sh" "$@"; }
deps_cli() { PATH="$SC_DEPS_BIN" "$SC" "$@"; }

@test "installer needs no package manager when dependencies are present" {
	deps_sandbox
	deps_present direnv
	deps_present gh
	run deps_install --projects-root "$SANDBOX/projects"
	[ "$status" -eq 0 ]
	[ ! -s "$SC_DEPS_LOG" ]
	[ -L "$SWITCHCRAFT_BIN_DIR/switchcraft" ]
	[ -f "$SANDBOX/.config/switchcraft/config" ]
}

@test "brew installs both missing dependencies in one command without sudo" {
	deps_sandbox
	deps_manager brew
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = 'brew install direnv gh' ]
	[ -x "$SC_DEPS_BIN/direnv" ]
	[ -x "$SC_DEPS_BIN/gh" ]
}

@test "installer installs only direnv when gh is already present" {
	deps_sandbox
	deps_manager brew
	deps_present gh
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = 'brew install direnv' ]
}

@test "installer installs only gh when direnv is already present" {
	deps_sandbox
	deps_manager brew
	deps_present direnv
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = 'brew install gh' ]
}

@test "apt updates before installing dependencies as root without sudo" {
	deps_sandbox
	deps_manager apt-get
	export SC_DEPS_UID=0
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = $'apt-get update -qq\napt-get install -y direnv gh' ]
}

@test "apt uses sudo for both update and installation as a regular user" {
	deps_sandbox
	deps_manager apt-get
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = $'sudo apt-get update -qq\napt-get update -qq\nsudo apt-get install -y direnv gh\napt-get install -y direnv gh' ]
}

@test "pacman installs github-cli as root without sudo" {
	deps_sandbox
	deps_manager pacman
	export SC_DEPS_UID=0
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = 'pacman -S --noconfirm direnv github-cli' ]
}

@test "dnf installs missing dependencies using sudo" {
	deps_sandbox
	deps_manager dnf
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = $'sudo dnf install -y direnv gh\ndnf install -y direnv gh' ]
}

@test "apk installs github-cli as root without sudo" {
	deps_sandbox
	deps_manager apk
	export SC_DEPS_UID=0
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = 'apk add direnv github-cli' ]
}

@test "zypper installs missing dependencies using sudo" {
	deps_sandbox
	deps_manager zypper
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = $'sudo zypper --non-interactive install direnv gh\nzypper --non-interactive install direnv gh' ]
}

@test "brew takes priority when multiple package managers are available" {
	deps_sandbox
	deps_manager brew
	deps_manager apt-get
	run deps_install
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = 'brew install direnv gh' ]
}

@test "missing package manager fails before installing switchcraft" {
	deps_sandbox
	run deps_install
	[ "$status" -ne 0 ]
	[[ "$output" == *'missing required dependencies: direnv gh'* ]]
	[[ "$output" == *'no supported package manager'* ]]
	[[ "$output" == *'https://direnv.net/docs/installation.html'* ]]
	[[ "$output" == *'https://github.com/cli/cli#installation'* ]]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
}

@test "missing sudo fails before installing switchcraft as a regular user" {
	deps_sandbox
	deps_manager apt-get
	rm "$SC_DEPS_BIN/sudo"
	run deps_install
	[ "$status" -ne 0 ]
	[[ "$output" == *'apt-get needs root or sudo'* ]]
	[ ! -s "$SC_DEPS_LOG" ]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
}

@test "installation failure preserves package manager errors and stops setup" {
	deps_sandbox
	deps_manager brew
	export SC_DEPS_FAIL=install
	run deps_install
	[ "$status" -ne 0 ]
	[[ "$output" == *'simulated package installation failure'* ]]
	[[ "$output" == *'brew failed to install required dependencies: direnv gh'* ]]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
}

@test "apt update failure stops before attempting to install packages" {
	deps_sandbox
	deps_manager apt-get
	export SC_DEPS_UID=0 SC_DEPS_FAIL=update
	run deps_install
	[ "$status" -ne 0 ]
	[[ "$output" == *'simulated update failure'* ]]
	[[ "$output" == *'apt-get update failed'* ]]
	[ "$(cat "$SC_DEPS_LOG")" = 'apt-get update -qq' ]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
}

@test "sudo failure stops setup and identifies the missing dependencies" {
	deps_sandbox
	deps_manager dnf
	export SC_DEPS_FAIL=sudo
	run deps_install
	[ "$status" -ne 0 ]
	[[ "$output" == *'simulated sudo failure'* ]]
	[[ "$output" == *'required dependencies: direnv gh'* ]]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
}

@test "successful package manager exit is not enough when commands remain absent" {
	deps_sandbox
	deps_manager brew
	export SC_DEPS_SKIP_INSTALL=all
	run deps_install
	[ "$status" -ne 0 ]
	[[ "$output" == *'still missing from PATH after installation: direnv gh'* ]]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
}

@test "post-install validation identifies only the dependency still missing" {
	deps_sandbox
	deps_manager brew
	export SC_DEPS_SKIP_INSTALL=gh
	run deps_install
	[ "$status" -ne 0 ]
	[[ "$output" == *'still missing from PATH after installation: gh.'* ]]
	[ -x "$SC_DEPS_BIN/direnv" ]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
}

@test "reinstall preserves configuration and does not reinstall dependencies" {
	deps_sandbox
	deps_manager brew
	deps_install --projects-root "$SANDBOX/projects" >/dev/null
	printf '# my settings\n' >>"$SANDBOX/.config/switchcraft/config"
	cp "$SANDBOX/.config/switchcraft/config" "$SANDBOX/config.before"
	run deps_install --projects-root "$SANDBOX/other-projects"
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = 'brew install direnv gh' ]
	diff -q "$SANDBOX/config.before" "$SANDBOX/.config/switchcraft/config"
}

@test "installer preserves projects-root and no-signing options" {
	deps_sandbox
	deps_manager brew
	run deps_install --projects-root "$SANDBOX/projects with spaces" --no-signing
	[ "$status" -eq 0 ]
	grep -qF "projects_root = $SANDBOX/projects with spaces" "$SANDBOX/.config/switchcraft/config"
	grep -qF 'sign_commits  = false' "$SANDBOX/.config/switchcraft/config"
}

@test "installer rejects invalid arguments before installing dependencies" {
	deps_sandbox
	deps_manager brew
	run deps_install --unknown
	[ "$status" -ne 0 ]
	[ ! -s "$SC_DEPS_LOG" ]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
	run deps_install --projects-root
	[ "$status" -ne 0 ]
	[[ "$output" == *'--projects-root requires a path'* ]]
	[ ! -s "$SC_DEPS_LOG" ]
	local argument
	for argument in '' --dry-run; do
		run deps_install --projects-root "$argument"
		[ "$status" -ne 0 ]
		[[ "$output" == *'--projects-root requires a path'* ]]
		[ ! -s "$SC_DEPS_LOG" ]
		[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
	done
}

@test "installer dry-run prints dependency and setup commands without writing" {
	deps_sandbox
	deps_manager brew
	run deps_install --projects-root "$SANDBOX/projects" --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *'brew install direnv gh'* ]]
	[[ "$output" == *'init --projects-root'* ]]
	[ ! -s "$SC_DEPS_LOG" ]
	[ ! -e "$SC_DEPS_BIN/direnv" ]
	[ ! -e "$SC_DEPS_BIN/gh" ]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
}

@test "installer help and version do not install dependencies or write config" {
	deps_sandbox
	deps_manager brew
	run deps_install --help
	[ "$status" -eq 0 ]
	[[ "$output" == *'Usage: ./install.sh'* ]]
	run deps_install --version
	[ "$status" -eq 0 ]
	[[ "$output" == *'switchcraft 2.'* ]]
	[ ! -s "$SC_DEPS_LOG" ]
	[ ! -e "$SWITCHCRAFT_BIN_DIR" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
}

@test "apply uses the shared installer to recover a missing dependency" {
	sc init >/dev/null
	add_profile work work@example.com
	deps_sandbox
	deps_manager brew
	deps_present direnv
	run deps_cli apply
	[ "$status" -eq 0 ]
	[ "$(cat "$SC_DEPS_LOG")" = 'brew install gh' ]
}

@test "apply stops on dependency failure before changing user configuration" {
	sc init >/dev/null
	load_libs
	sc_cfg_add_profile work
	sc_cfg_append work name 'Test User'
	sc_cfg_append work email work@example.com
	sc_cfg_append work dir "$SANDBOX/projects/work"
	printf '[user]\n\tname = Original\n' >"$SANDBOX/.gitconfig"
	cp "$SANDBOX/.gitconfig" "$SANDBOX/gitconfig.before"
	deps_sandbox
	run deps_cli apply
	[ "$status" -ne 0 ]
	diff -q "$SANDBOX/gitconfig.before" "$SANDBOX/.gitconfig"
	[ ! -e "$SANDBOX/.gitconfig.switchcraft.bak" ]
	[ ! -e "$SANDBOX/.ssh/id_ed25519_work" ]
	[ ! -e "$SANDBOX/projects/work/.envrc" ]
	[ ! -s "$SANDBOX/.bashrc" ]
}

@test "apply dry-run describes missing dependencies without installing them" {
	sc init >/dev/null
	add_profile work work@example.com
	cp "$SANDBOX/.gitconfig" "$SANDBOX/gitconfig.before"
	deps_sandbox
	deps_manager brew
	run deps_cli --dry-run apply
	[ "$status" -eq 0 ]
	[[ "$output" == *'brew install direnv gh'* ]]
	[ ! -s "$SC_DEPS_LOG" ]
	diff -q "$SANDBOX/gitconfig.before" "$SANDBOX/.gitconfig"
}

@test "doctor reports gh as a missing required dependency without installing it" {
	sc init >/dev/null
	deps_sandbox
	deps_present direnv
	deps_manager brew
	run deps_cli doctor
	[ "$status" -ne 0 ]
	[[ "$output" == *'gh is not installed'* ]]
	[ ! -s "$SC_DEPS_LOG" ]
}

@test "installer still migrates and applies a legacy env after dependencies" {
	deps_sandbox
	deps_manager brew
	cat >"$SANDBOX/repo/.env" <<EOF
PROJECTS_ROOT='$SANDBOX/projects'
PROFILES=A
A_SLUG=work
A_GIT_NAME='Legacy User'
A_GIT_EMAIL=legacy@example.com
EOF
	run deps_install
	[ "$status" -eq 0 ]
	grep -qF '[profile work]' "$SANDBOX/.config/switchcraft/config"
	[ -f "$SANDBOX/.ssh/id_ed25519_work" ]
	[ -f "$SANDBOX/projects/work/.envrc" ]
}

@test "installer dry-run does not evaluate a legacy env or apply unwritten state" {
	deps_sandbox
	deps_manager brew
	printf 'touch "%s/evaluated"\n' "$SANDBOX" >"$SANDBOX/repo/.env"
	run deps_install -n
	[ "$status" -eq 0 ]
	[[ "$output" == *'/bin/switchcraft apply'* ]]
	[ ! -e "$SANDBOX/evaluated" ]
	[ ! -e "$SANDBOX/.config/switchcraft/config" ]
	[ ! -s "$SC_DEPS_LOG" ]
}
