#!/usr/bin/env bash
# uninstall.sh — reverse everything install.sh and switchcraft did.
# Keeps your SSH keys, Claude history and project files unless --purge.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SWITCHCRAFT_BIN_DIR:-$HOME/.local/bin}"

"$REPO_DIR/bin/switchcraft" uninstall "$@"

if [[ -L "$BIN_DIR/switchcraft" ]]; then
	rm -f "$BIN_DIR/switchcraft"
	printf '\033[1;32m  ✓\033[0m removed %s/switchcraft\n' "$BIN_DIR"
fi
printf '    this clone can now be deleted\n'
