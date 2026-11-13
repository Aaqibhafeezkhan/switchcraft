#!/usr/bin/env bash
# shellcheck shell=bash
# deps.sh — install missing runtime dependencies before changing user config.

sc_deps_fail() {
	note "direnv installation: https://direnv.net/docs/installation.html"
	note "gh installation: https://github.com/cli/cli#installation"
	die "$1"
}

sc_deps_ensure() {
	local dep manager='' candidate package
	local -a missing=() packages=() command=()
	for dep in direnv gh; do
		has_cmd "$dep" || missing+=("$dep")
	done
	((${#missing[@]})) || return 0

	for candidate in brew apt-get pacman dnf apk zypper; do
		if has_cmd "$candidate"; then
			manager="$candidate"
			break
		fi
	done
	[[ -n "$manager" ]] || sc_deps_fail \
		"missing required dependencies: ${missing[*]}; no supported package manager found. Install them manually, then rerun this command."

	command=("$manager")
	if [[ "$manager" != brew && "$(id -u)" != 0 ]]; then
		has_cmd sudo || sc_deps_fail \
			"cannot install required dependencies: ${missing[*]}; $manager needs root or sudo. Install them manually, then rerun this command."
		command=(sudo "$manager")
	fi

	for dep in "${missing[@]}"; do
		package="$dep"
		case "$manager:$dep" in
		pacman:gh | apk:gh) package=github-cli ;;
		esac
		packages+=("$package")
	done

	info "installing required dependencies: ${missing[*]} ($manager)"
	case "$manager" in
	brew) sc_run "${command[@]}" install "${packages[@]}" ;;
	apt-get)
		sc_run "${command[@]}" update -qq || sc_deps_fail \
			"apt-get update failed; required dependencies still missing: ${missing[*]}. Fix your package repositories or install them manually, then retry."
		sc_run "${command[@]}" install -y "${packages[@]}"
		;;
	pacman) sc_run "${command[@]}" -S --noconfirm "${packages[@]}" ;;
	dnf) sc_run "${command[@]}" install -y "${packages[@]}" ;;
	apk) sc_run "${command[@]}" add "${packages[@]}" ;;
	zypper) sc_run "${command[@]}" --non-interactive install "${packages[@]}" ;;
	esac || sc_deps_fail \
		"$manager failed to install required dependencies: ${missing[*]}. Check permissions and configured repositories, or install them manually, then retry."

	# A dry run cannot discover executables it only pretended to install.
	is_dry && return 0
	missing=()
	for dep in direnv gh; do
		has_cmd "$dep" || missing+=("$dep")
	done
	((${#missing[@]} == 0)) || sc_deps_fail \
		"required dependencies still missing from PATH after installation: ${missing[*]}. Fix your PATH or install them manually, then retry."
	ok "required dependencies available"
}
