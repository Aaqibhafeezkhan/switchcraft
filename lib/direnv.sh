#!/usr/bin/env bash
# shellcheck shell=bash
# direnv.sh — the hook that makes CLAUDE_CONFIG_DIR and GH_CONFIG_DIR follow cd.

sc_shell_kind() {
	local s="${SWITCHCRAFT_SHELL:-${SHELL:-bash}}"
	printf '%s\n' "$(basename "$s")"
}

# sc_shell_rc [kind] — the rc file for that shell, or "" when unsupported.
sc_shell_rc() {
	local kind="${1:-$(sc_shell_kind)}"
	case "$kind" in
	bash) printf '%s\n' "$HOME/.bashrc" ;;
	zsh) printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
	fish) printf '%s\n' "$(sc_xdg_config)/fish/config.fish" ;;
	tcsh | csh) printf '%s\n' "$HOME/.cshrc" ;;
	elvish) printf '%s\n' "$(sc_xdg_config)/elvish/rc.elv" ;;
	*) printf '\n' ;;
	esac
}

# sc_direnv_hook_line [kind] — each shell needs its own syntax; writing the
# bash form into a fish config is how this used to break.
sc_direnv_hook_line() {
	local kind="${1:-$(sc_shell_kind)}"
	# The single quotes are the point: these strings are written verbatim into
	# the user's rc file, where their shell expands them.
	# shellcheck disable=SC2016
	case "$kind" in
	bash | zsh) printf 'eval "$(direnv hook %s)"\n' "$kind" ;;
	fish) printf 'direnv hook fish | source\n' ;;
	tcsh | csh) printf 'eval `direnv hook tcsh`\n' ;;
	elvish) printf 'eval (direnv hook elvish)\n' ;;
	*) printf '\n' ;;
	esac
}

sc_direnv_install() {
	has_cmd direnv && return 0
	info "installing direnv..."
	if has_cmd brew; then
		sc_run brew install direnv || warn "brew install direnv failed"
	elif has_cmd apt-get && has_cmd sudo; then
		sc_run sudo apt-get update -qq || warn "apt-get update failed"
		sc_run sudo apt-get install -y direnv || warn "apt install direnv failed"
	elif has_cmd pacman && has_cmd sudo; then
		sc_run sudo pacman -S --noconfirm direnv || warn "pacman install direnv failed"
	elif has_cmd dnf && has_cmd sudo; then
		sc_run sudo dnf install -y direnv || warn "dnf install direnv failed"
	elif has_cmd apk && has_cmd sudo; then
		sc_run sudo apk add direnv || warn "apk install direnv failed"
	elif has_cmd zypper && has_cmd sudo; then
		sc_run sudo zypper --non-interactive install direnv || warn "zypper install direnv failed"
	else
		warn "install direnv manually: https://direnv.net/docs/installation.html"
		return 1
	fi
	has_cmd direnv
}

# sc_direnv_hook_apply — idempotent, fenced, and honest about unknown shells.
sc_direnv_hook_apply() {
	local kind rc line
	kind="$(sc_shell_kind)"
	rc="$(sc_shell_rc "$kind")"
	line="$(sc_direnv_hook_line "$kind")"

	if [[ -z "$rc" || -z "$line" ]]; then
		warn "unknown shell '$kind' — add direnv's hook yourself:"
		note "https://direnv.net/docs/hook.html"
		return 0
	fi

	if [[ -f "$rc" ]] && grep -qF 'direnv hook' "$rc" 2>/dev/null &&
		! grep -qF "$SC_BEGIN" "$rc" 2>/dev/null; then
		ok "direnv hook already present in $rc (left as is)"
		return 0
	fi

	printf '%s\n' "$line" | sc_block_apply "$rc"
	ok "direnv hook ($kind) in $rc"
	note "open a new terminal, or run: $line"
}

# sc_envrc_body <profile>
sc_envrc_body() {
	local p="$1"
	printf 'export CLAUDE_CONFIG_DIR=%s\n' "$(sc_profile_claude_dir "$p")"
	printf 'export GH_CONFIG_DIR=%s\n' "$(sc_profile_gh_dir "$p")"
}

# sc_envrc_apply <profile> <dir> — fenced, so a user's own .envrc survives.
sc_envrc_apply() {
	local p="$1" dir="$2"
	sc_mkdir "$dir"
	sc_envrc_body "$p" | sc_block_apply "$dir/.envrc"
	if has_cmd direnv; then
		sc_run direnv allow "$dir" >/dev/null 2>&1 || warn "direnv allow failed for $dir"
	fi
	ok ".envrc → $dir"
}
