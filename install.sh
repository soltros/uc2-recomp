#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GAME_DIR=${1:-"$ROOT/../Unreal Championship 2 - The Liandri Conflict"}
GAME_DIR=$(CDPATH= cd -- "$GAME_DIR" && pwd)
RUNTIME=${XBOX_LINUX_DIR:-"$ROOT/../xbox-linux"}

command -v nix >/dev/null 2>&1 || { echo "Install Nix with flakes enabled, then rerun ./install.sh." >&2; exit 1; }
if [ ! -d "$RUNTIME/.git" ]; then
    if [ -e "$RUNTIME" ]; then echo "Runtime path exists but is not an Xbox Linux git checkout: $RUNTIME" >&2; exit 1; fi
    git clone https://github.com/soltros/xbox-linux.git "$RUNTIME"
fi

python3 - "$ROOT/target.json" "$GAME_DIR/default.xbe" <<'PY'
import hashlib,json,sys
target=json.load(open(sys.argv[1]))
actual=hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest()
if actual != target['sha256']:
    raise SystemExit(f"XBE hash mismatch: expected {target['sha256']}, got {actual}")
print(f"Verified {sys.argv[2]} ({actual})")
PY

# Provision the shared runtime/toolchain as a common prerequisite. UC2 execution
# is not implemented yet; this project currently produces analysis reports only.
"$RUNTIME/tools/install_runtime.sh"
cd "$ROOT"
nix develop --command python3 -m unittest discover -s tests -v
nix develop --command python3 tools/workspace.py verify --game-dir "$GAME_DIR"
nix develop --command python3 tools/workspace.py xbe --game-dir "$GAME_DIR" --title uc2
nix develop --command python3 tools/workspace.py packages --game-dir "$GAME_DIR" --title uc2

printf '\nUC2 analysis environment is ready. Reports are under %s/reports/uc2/.\n' "$ROOT"
printf 'The shared runtime is installed, but this project does not yet have a UC2 launcher or executable title recomp.\n'
