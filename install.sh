#!/usr/bin/env bash
# ==================================================================
# install.sh — put `switchcraft` on your PATH, then hand over to it.
#
#   git clone https://github.com/FernandoPazCavalcante/switchcraft
#   cd switchcraft && ./install.sh
#
# Everything else lives in `switchcraft` itself:
#   switchcraft add work --name 'You' --email you@company.com
#   switchcraft status
# ==================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SWITCHCRAFT_BIN_DIR:-$HOME/.local/bin}"
SELF="$REPO_DIR/bin/switchcraft"

[[ -x "$SELF" ]] || {
	echo "bin/switchcraft is missing or not executable — is this a complete clone?" >&2
	exit 1
}

mkdir -p "$BIN_DIR"
ln -sfn "$SELF" "$BIN_DIR/switchcraft"
printf '\033[1;32m  ✓\033[0m switchcraft → %s/switchcraft\n' "$BIN_DIR"

case ":${PATH:-}:" in
*":$BIN_DIR:"*) ;;
*)
	printf '\033[1;33m  !\033[0m %s is not on your PATH. Add this to your shell rc:\n' "$BIN_DIR"
	# shellcheck disable=SC2016 # $PATH is advice for the user's rc, not for us
	printf '      export PATH="%s:$PATH"\n' "$BIN_DIR"
	;;
esac

"$SELF" init "$@"

# A v1 .env is migrated by `init`; reconcile straight away so an upgrade is a
# single command.
if [[ -f "$REPO_DIR/.env" ]]; then
	"$SELF" apply
fi
