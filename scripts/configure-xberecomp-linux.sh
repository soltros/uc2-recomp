#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fork_dir="${UC2_XBERECOMP_DIR:-$HOME/Projects/uc2-xberecomp-linux-evaluation}"

if [[ ! -d "$fork_dir" || ! -f "$fork_dir/CMakePresets.json" ]]; then
    echo "error: XboxXBERecomp Linux checkout not found: $fork_dir" >&2
    echo "Set UC2_XBERECOMP_DIR to its path if it is elsewhere." >&2
    exit 1
fi

"$repo_root/scripts/install-xberecomp-deps.sh"

cd "$fork_dir"
exec "$repo_root/scripts/with-xberecomp-nix-env.sh" cmake --preset release
