#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mkdir -p diagnostic_logs
stamp="$(date +%Y%m%d_%H%M%S)"
log="diagnostic_logs/xberecomp_${stamp}.log"
capture_dir="${XBE_CAPTURE_DIR:-$repo_root/diagnostic_logs/xberecomp_frames}"
mkdir -p "$capture_dir"
capture_after_secs="${RECOMP_CAPTURE_AFTER_SECS:-}"
capture_interval_secs="${RECOMP_CAPTURE_INTERVAL_SECS:-1}"

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
if [[ -n "$capture_after_secs" && ! "$capture_after_secs" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    echo "error: RECOMP_CAPTURE_AFTER_SECS must be comma-separated non-negative seconds" >&2
    exit 2
fi
if [[ ! "$capture_interval_secs" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: RECOMP_CAPTURE_INTERVAL_SECS must be a positive integer" >&2
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

echo "XboxXBERecomp UC2 diagnostic run" | tee "$log"
echo "  executable: $binary" | tee -a "$log"
echo "  sha256:     $(sha256sum "$binary" | cut -d ' ' -f 1)" | tee -a "$log"
echo "  log:        $log" | tee -a "$log"
if [[ -n "$capture_after_secs" ]]; then
    capture_description="at ${capture_after_secs}s"
else
    capture_description="every ${capture_interval_secs}s"
fi
echo "  captures:   $capture_dir (automatic captures $capture_description; F3 also works)" | tee -a "$log"
echo "  stop:       close the game window when finished" | tee -a "$log"

set +e
"$repo_root/scripts/with-xberecomp-nix-env.sh" env \
    XBE_PERF=1 \
    XBE_CAPTURE_DIR="$capture_dir" \
    "$binary" >>"$log" 2>&1 &
runner_pid=$!

# The Linux fork installs SIGUSR1 as a frame-capture request (the same action
# as F3). Walk through wrapper processes so the signal reaches uc2_recomp.
capture_pid=""
if [[ "$capture_after_secs" != "0" ]]; then
    (
        request_capture() {
            if ! kill -0 "$runner_pid" 2>/dev/null; then
                return 1
            fi
            target_pid="$runner_pid"
            while child_pid="$(pgrep -P "$target_pid" 2>/dev/null | head -n 1)" && [[ -n "$child_pid" ]]; do
                target_pid="$child_pid"
            done
            if kill -USR1 "$target_pid" 2>/dev/null; then
                echo "[diagnostic] requested automatic frame capture at ${capture_time}s from pid $target_pid" >>"$log"
            else
                echo "[diagnostic] automatic frame capture at ${capture_time}s failed for pid $target_pid" >>"$log"
            fi
            return 0
        }

        if [[ -n "$capture_after_secs" ]]; then
            previous=0
            IFS=',' read -r -a capture_times <<<"$capture_after_secs"
            for capture_time in "${capture_times[@]}"; do
                delay=$((capture_time - previous))
                previous=$capture_time
                if ((delay > 0)); then sleep "$delay"; fi
                request_capture || break
            done
        else
            capture_time=0
            while kill -0 "$runner_pid" 2>/dev/null; do
                sleep "$capture_interval_secs"
                capture_time=$((capture_time + capture_interval_secs))
                request_capture || break
            done
        fi
    ) &
    capture_pid=$!
fi

tail --pid="$runner_pid" -n +1 -f "$log" &
tail_pid=$!
wait "$runner_pid"
runner_status=$?
if [[ -n "$capture_pid" ]]; then
    kill "$capture_pid" 2>/dev/null || true
    wait "$capture_pid" 2>/dev/null || true
fi
wait "$tail_pid" 2>/dev/null || true
set -e

exit "$runner_status"
