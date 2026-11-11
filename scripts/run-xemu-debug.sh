#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xemu_bin="${XEMU_BIN:-xemu}"
log_dir="${XEMU_LOG_DIR:-$repo_root/diagnostic_logs}"

if ! command -v "$xemu_bin" >/dev/null 2>&1; then
    echo "error: Xemu executable not found: $xemu_bin" >&2
    echo "Set XEMU_BIN to the Xemu executable path." >&2
    exit 1
fi

mkdir -p "$log_dir"
stamp="$(date +%Y%m%d_%H%M%S)"
log="$log_dir/xemu_$stamp.log"

echo "Xemu UC2 reference run"
echo "  executable: $xemu_bin"
echo "  log:        $log"
echo "  guest GDB:  localhost:1234"
echo "  stop:       close the Xemu window when finished"

# Xemu forwards -s to QEMU to expose its guest GDB server. Capture both output
# streams because Xemu and QEMU diagnostic messages are written to stderr.
"$xemu_bin" -s "$@" 2>&1 | tee "$log"
