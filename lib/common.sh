#!/usr/bin/env bash
# shellcheck shell=bash
# common.sh — logging, dry-run plumbing and safe file writes.
# Sourced by bin/switchcraft; never executed directly.

SC_DRY_RUN="${SC_DRY_RUN:-0}"
SC_YES="${SC_YES:-0}"

# Marker fences. Every file switchcraft touches is edited between these, so a
# re-run replaces only its own block and `uninstall` can reverse it exactly.
SC_BEGIN='# >>> switchcraft >>>'
SC_END='# <<< switchcraft <<<'

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	SC_BLUE=$'\033[1;34m'
	SC_GREEN=$'\033[1;32m'
	SC_YELLOW=$'\033[1;33m'
	SC_RED=$'\033[1;31m'
	SC_DIM=$'\033[2m'
	SC_BOLD=$'\033[1m'
	SC_OFF=$'\033[0m'
else
	# shellcheck disable=SC2034 # SC_BOLD is used by bin/switchcraft
	SC_BLUE='' SC_GREEN='' SC_YELLOW='' SC_RED='' SC_DIM='' SC_BOLD='' SC_OFF=''
fi

info() { printf '%s==>%s %s\n' "$SC_BLUE" "$SC_OFF" "$*"; }
ok() { printf '%s  ✓%s %s\n' "$SC_GREEN" "$SC_OFF" "$*"; }
warn() { printf '%s  !%s %s\n' "$SC_YELLOW" "$SC_OFF" "$*" >&2; }
bad() { printf '%s  ✗%s %s\n' "$SC_RED" "$SC_OFF" "$*" >&2; }
note() { printf '%s    %s%s\n' "$SC_DIM" "$*" "$SC_OFF"; }
die() {
	printf '%s  ✗%s %s\n' "$SC_RED" "$SC_OFF" "$*" >&2
	exit 1
}

dry() { printf '%s  ~%s %s%s%s\n' "$SC_DIM" "$SC_OFF" "$SC_DIM" "$*" "$SC_OFF"; }
is_dry() { [[ "$SC_DRY_RUN" == 1 ]]; }

# sc_run <cmd...> — execute, or describe it under --dry-run.
# Not named run(): bats (and other harnesses) own that name.
sc_run() {
	if is_dry; then
		dry "$*"
		return 0
	fi
	"$@"
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed.${2:+ $2}"
}
has_cmd() { command -v "$1" >/dev/null 2>&1; }

confirm() {
	[[ "$SC_YES" == 1 ]] && return 0
	is_dry && return 0
	local reply
	printf '%s??%s %s [y/N] ' "$SC_YELLOW" "$SC_OFF" "$*"
	read -r reply || return 1
	[[ "$reply" == [yY]* ]]
}

# ------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------

sc_xdg_config() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

# sc_resolve <path> — follow a symlink chain to the real file, so writing to
# ~/.gitconfig edits the file inside a dotfiles repo instead of replacing the
# symlink that points at it.
sc_resolve() {
	local p="$1" target n=0
	while [[ -L "$p" ]]; do
		n=$((n + 1))
		((n > 40)) && die "symlink loop while resolving $1"
		target="$(readlink "$p")"
		case "$target" in
		/*) p="$target" ;;
		*) p="$(dirname "$p")/$target" ;;
		esac
	done
	printf '%s\n' "$p"
}

# ------------------------------------------------------------------
# File writes — all mutation goes through these so --dry-run is honest
# ------------------------------------------------------------------

sc_mkdir() {
	local d
	for d in "$@"; do
		[[ -d "$d" ]] && continue
		if is_dry; then
			dry "mkdir -p $d"
		else
			mkdir -p "$d"
		fi
	done
}

# sc_write <path> [mode] < content
sc_write() {
	local path="$1" mode="${2:-}" body
	body="$(cat)"
	if is_dry; then
		dry "write $path${mode:+ (mode $mode)}"
		return 0
	fi
	mkdir -p "$(dirname "$path")"
	printf '%s\n' "$body" >"$path"
	[[ -n "$mode" ]] && chmod "$mode" "$path"
	return 0
}

# sc_backup_once <path> — keep one pristine copy before the first edit.
sc_backup_once() {
	local path="$1" bak="$1.switchcraft.bak"
	[[ -f "$path" ]] || return 0
	[[ -e "$bak" ]] && return 0
	if is_dry; then
		dry "backup $path -> $bak"
		return 0
	fi
	cp -p "$path" "$bak"
	note "backup saved: $bak"
}

# sc_block_strip <file> — the file without switchcraft's block (to stdout).
sc_block_strip() {
	local file="$1"
	[[ -f "$file" ]] || return 0
	awk -v b="$SC_BEGIN" -v e="$SC_END" '
    index($0, b) { skip = 1; next }
    index($0, e) { skip = 0; next }
    !skip        { print }
  ' "$file"
}

# sc_block_apply <file> [mode] < body
# Replaces switchcraft's fenced block in <file>, creating the file if needed.
# Preserves symlinks (writes through to the real target) and takes one backup.
sc_block_apply() {
	local file="$1" mode="${2:-}" body real tmp
	body="$(cat)"
	real="$(sc_resolve "$file")"

	if is_dry; then
		dry "update switchcraft block in $real"
		return 0
	fi

	sc_backup_once "$real"
	mkdir -p "$(dirname "$real")"
	tmp="$(mktemp "${TMPDIR:-/tmp}/switchcraft.XXXXXX")"
	{
		sc_block_strip "$real"
		printf '%s\n%s\n%s\n' "$SC_BEGIN" "$body" "$SC_END"
	} >"$tmp"
	# cat (not mv) so the destination keeps its inode, mode and symlink chain.
	cat "$tmp" >"$real"
	rm -f "$tmp"
	[[ -n "$mode" ]] && chmod "$mode" "$real"
	return 0
}

# sc_block_remove <file> [prune] — drop switchcraft's block, leave the rest
# untouched. With prune=1, a file left with nothing but blank lines is deleted,
# so uninstalling does not litter empty .envrc files around.
sc_block_remove() {
	local file="$1" prune="${2:-0}" real tmp
	real="$(sc_resolve "$file")"
	[[ -f "$real" ]] || return 0
	grep -qF "$SC_BEGIN" "$real" 2>/dev/null || return 0
	if is_dry; then
		dry "remove switchcraft block from $real"
		return 0
	fi
	tmp="$(mktemp "${TMPDIR:-/tmp}/switchcraft.XXXXXX")"
	sc_block_strip "$real" >"$tmp"
	if [[ "$prune" == 1 ]] && ! grep -q '[^[:space:]]' "$tmp"; then
		rm -f "$tmp" "$real"
		ok "removed $real (nothing left in it)"
		return 0
	fi
	cat "$tmp" >"$real"
	rm -f "$tmp"
	ok "switchcraft block removed from $real"
}

# sc_render <template> KEY=VALUE... — literal {{KEY}} substitution.
# Deliberately not sed (& and | in a name corrupt the output) and not
# ${body//pat/rep} either: since bash 5.2 an unquoted & in the replacement
# expands to the matched text, which turned "A & B" into "A {{NAME}} B".
sc_render() {
	local tpl="$1" body kv k v out pre
	shift
	body="$(cat "$tpl")"
	for kv in "$@"; do
		k="{{${kv%%=*}}}"
		v="${kv#*=}"
		out=''
		while [[ "$body" == *"$k"* ]]; do
			pre="${body%%"$k"*}"
			out+="$pre$v"
			body="${body#*"$k"}"
		done
		body="$out$body"
	done
	printf '%s\n' "$body"
}

# sc_real <path> — the canonical path, with every symlink resolved.
# git resolves symlinks before matching includeIf, so a rule written for the
# logical path never fires. macOS makes this routine rather than exotic: /var
# is a symlink to /private/var, so anything under $TMPDIR is affected.
sc_real() {
	local p
	p="$(sc_abs "$1")"
	if [[ -d "$p" ]]; then
		(cd "$p" 2>/dev/null && pwd -P) || printf '%s\n' "$p"
	else
		printf '%s\n' "$p"
	fi
}

# sc_slug_ok <slug> — profile names become directory and file names.
sc_slug_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; }

# sc_abs <path> — absolute, ~ expanded, no trailing slash. No existence check.
sc_abs() {
	local p="$1"
	# shellcheck disable=SC2088 # the tilde is matched as a literal, then expanded
	if [[ "$p" == '~' ]]; then
		p="$HOME"
	elif [[ "$p" == '~/'* ]]; then
		p="$HOME/${p:2}"
	elif [[ "$p" != /* ]]; then
		p="$PWD/$p"
	fi
	while [[ "$p" == */ && "$p" != "/" ]]; do p="${p%/}"; done
	printf '%s\n' "$p"
}

# sc_file_mode <path> — octal permissions, on GNU and BSD alike.
sc_file_mode() {
	stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'
}
