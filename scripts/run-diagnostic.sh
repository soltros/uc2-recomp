#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mkdir -p diagnostic_logs
stamp="$(date +%Y%m%d_%H%M%S)"
log="diagnostic_logs/xberecomp_${stamp}.log"
capture_dir="${XBE_CAPTURE_DIR:-$repo_root/diagnostic_logs/xberecomp_frames}"
mkdir -p "$capture_dir"
watchdog_secs="${RECOMP_WATCHDOG_SECS:-${UC2_DIAG_WATCHDOG_SECS:-0}}"

if [[ -n "${UC2_XBERECOMP_BIN:-}" ]]; then
    binary="$UC2_XBERECOMP_BIN"
elif [[ -x "$repo_root/build-xberecomp/uc2_recomp" ]]; then
    binary="$repo_root/build-xberecomp/uc2_recomp"
else
    binary="/tmp/uc2-xberecomp-live/build/uc2_recomp"
fi

if [[ ! -x "$binary" ]]; then
    echo "error: XboxXBERecomp executable not found: $binary" >&2
    echo "Set UC2_XBERECOMP_BIN to its path." >&2
    exit 1
fi
if [[ ! "$watchdog_secs" =~ ^[0-9]+$ ]]; then
    echo "error: RECOMP_WATCHDOG_SECS must be a non-negative integer" >&2
    exit 2
fi

# The Linux fork's runtime expects the host C++ library. Use the matching runtime
# from the built recompiler toolchain when Nix has not exposed it in the profile.
xberecomp_dir="${UC2_XBERECOMP_DIR:-$HOME/Projects/uc2-xberecomp-linux-evaluation}"
compiler="${UC2_XBERECOMP_COMPILER:-$xberecomp_dir/out/build/release/compiler/xbe_recomp}"
if [[ -x "$compiler" ]]; then
    cxx_runtime="$(ldd "$compiler" 2>/dev/null | awk '$1 == "libstdc++.so.6" && $2 == "=>" && $3 ~ /^\// { print $3; exit }')"
    if [[ -n "$cxx_runtime" && -f "$cxx_runtime" ]]; then
        export LD_LIBRARY_PATH="$(dirname "$cxx_runtime")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
fi

runner=("$binary")
if ((watchdog_secs > 0)); then
    runner=(timeout --signal=TERM --kill-after=5s "${watchdog_secs}s" "$binary")
fi

echo "XboxXBERecomp UC2 diagnostic run"
echo "  executable: $binary"
echo "  sha256:     $(sha256sum "$binary" | cut -d ' ' -f 1)"
echo "  log:        $log"
echo "  captures:   $capture_dir (press F3 to capture a frame)"
if ((watchdog_secs > 0)); then
    echo "  watchdog:   ${watchdog_secs}s"
fi

set +e
"$repo_root/scripts/with-xberecomp-nix-env.sh" env \
    XBE_PERF=1 \
    XBE_CAPTURE_DIR="$capture_dir" \
    "${runner[@]}" 2>&1 | tee "$log"
statuses=("${PIPESTATUS[@]}")
set -e

runner_status="${statuses[0]}"
tee_status="${statuses[1]}"
if ((tee_status != 0)); then
    exit "$tee_status"
fi
exit "$runner_status"
