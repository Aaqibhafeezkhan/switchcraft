#!/usr/bin/env bash
# ==================================================================
# install.sh — install runtime dependencies, then put switchcraft on your PATH.
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

# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=lib/deps.sh
source "$REPO_DIR/lib/deps.sh"

init_args=()
while (($#)); do
	case "$1" in
	-n | --dry-run)
		SC_DRY_RUN=1
		shift
		;;
	-y | --yes)
		SC_YES=1
		shift
		;;
	--projects-root)
		[[ -n "${2:-}" && "${2:-}" != -* ]] || die "install: --projects-root requires a path"
		init_args+=("$1" "$2")
		shift 2
		;;
	--no-signing)
		init_args+=("$1")
		shift
		;;
	-h | --help)
		cat <<EOF
Usage: ./install.sh [options]

Install missing direnv and gh dependencies, add switchcraft to PATH, and initialize its config.

  --projects-root <path>   directory containing your project folders
  --no-signing            do not enable global SSH commit signing
  -n, --dry-run           show planned changes without installing or writing
  -y, --yes               assume yes for switchcraft prompts
  -h, --help              this help
  -V, --version           switchcraft version
EOF
		exit 0
		;;
	-V | --version) exec "$SELF" --version ;;
	*) die "install: unknown option $1 — try: ./install.sh --help" ;;
	esac
done
export SC_DRY_RUN SC_YES

is_dry && info "dry run — nothing will be installed or written"
sc_deps_ensure

sc_mkdir "$BIN_DIR"
sc_run ln -sfn "$SELF" "$BIN_DIR/switchcraft"
ok "switchcraft → $BIN_DIR/switchcraft"

case ":${PATH:-}:" in
*":$BIN_DIR:"*) ;;
*)
	printf '\033[1;33m  !\033[0m %s is not on your PATH. Add this to your shell rc:\n' "$BIN_DIR"
	# shellcheck disable=SC2016 # $PATH is advice for the user's rc, not for us
	printf '      export PATH="%s:$PATH"\n' "$BIN_DIR"
	;;
esac

sc_run "$SELF" init "${init_args[@]+"${init_args[@]}"}"

# A v1 .env is migrated by `init`; reconcile straight away so an upgrade is a
# single command.
if [[ -f "$REPO_DIR/.env" ]]; then
	sc_run "$SELF" apply
fi
