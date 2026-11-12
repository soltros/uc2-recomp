#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
trace_log_dir="${XEMU_LOG_DIR:-$repo_root/diagnostic_logs}"
xemu_bin="${XEMU_BIN:-xemu}"
attach_existing=0

if [[ "${1:-}" == "--attach" ]]; then
    attach_existing=1
    shift
fi

if ((attach_existing)) && (($# != 0)); then
    echo "usage: $0 [--attach] [xemu argument ...]" >&2
    echo "error: --attach does not accept Xemu launch arguments." >&2
    exit 2
fi

if ((!attach_existing)) && ! command -v "$xemu_bin" >/dev/null 2>&1; then
    echo "error: Xemu executable not found: $xemu_bin" >&2
    echo "Set XEMU_BIN to the Xemu executable path." >&2
    exit 1
fi
if ! command -v ss >/dev/null 2>&1; then
    echo "error: ss is required to wait for Xemu's guest GDB server." >&2
    exit 1
fi
if ((!attach_existing)) && ss -H -ltn 'sport = :1234' | rg -q .; then
    echo "error: TCP port 1234 is already in use; close the existing guest debugger first." >&2
    exit 1
fi

mkdir -p "$trace_log_dir"
stamp="$(date +%Y%m%d_%H%M%S)"
trace_log="$trace_log_dir/xemu_guest_$stamp.log"

if ((attach_existing)); then
    echo "Attaching the UC2 reference capture to the running Xemu guest."
    echo "  enable its guest GDB server in Debug -> Monitor with: gdbserver"
    echo "  Xemu console log: not captured (Xemu was started separately)"
else
    echo "Starting the Xemu UC2 reference capture."
    echo "  Xemu console log: diagnostic_logs/xemu_<timestamp>.log"
fi
echo "  guest trace log:  $trace_log"
echo "  navigate to the same CTF-Aqueduct match; close Xemu when finished"

if ((!attach_existing)); then
    "$repo_root/scripts/run-xemu-debug.sh" "$@" &
    xemu_pid=$!
fi

port_ready=0
for ((attempt = 0; attempt < 300; attempt++)); do
    if ((!attach_existing)) && ! kill -0 "$xemu_pid" 2>/dev/null; then
        wait "$xemu_pid" || true
        echo "error: Xemu exited before its guest GDB server became available." >&2
        exit 1
    fi
    if ss -H -ltn 'sport = :1234' | rg -q .; then
        port_ready=1
        break
    fi
    sleep 0.1
done

if ((port_ready == 0)); then
    echo "error: no guest GDB server appeared on localhost:1234 within 30 seconds." >&2
    if ((attach_existing)); then
        echo "In Xemu, open Debug -> Monitor and enter 'gdbserver', then retry." >&2
    else
        echo "Close Xemu, then check its console log before retrying." >&2
    fi
    exit 1
fi

echo "Guest GDB server is ready; attaching the UC2 trace."
set +e
nix shell nixpkgs#gdb -c gdb -q -batch -x "$repo_root/scripts/xemu-uc2-trace.gdb" 2>&1 | tee "$trace_log"
gdb_status=${PIPESTATUS[0]}
set -e

if ((gdb_status != 0 && attach_existing)) && ! ss -H -ltn 'sport = :1234' | rg -q .; then
    echo "Guest GDB server closed; keeping the completed trace at $trace_log."
    gdb_status=0
fi

if ((gdb_status != 0)); then
    if ((attach_existing)); then
        echo "GDB exited with status $gdb_status. The existing Xemu instance was left alone." >&2
    else
        echo "GDB exited with status $gdb_status. Xemu remains open; close it manually." >&2
    fi
    exit "$gdb_status"
fi

if ((!attach_existing)); then
    wait "$xemu_pid" || true
fi
echo "Xemu reference capture saved to $trace_log"
