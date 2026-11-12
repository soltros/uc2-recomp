# Xemu reference debugging

Xemu is a diagnostic reference only. The UC2 recomp and its fixes remain based
on XboxXBERecomp; this workflow does not add Xemu to the game's runtime.

## Capture a reference run

Launch Xemu through the repo helper:

```sh
./scripts/run-xemu-debug.sh
```

The helper saves Xemu's standard output and error to a timestamped file in
`diagnostic_logs/` and enables QEMU's guest GDB server on `localhost:1234`.
Set `XEMU_BIN` if Xemu is not on `PATH`, or `XEMU_LOG_DIR` to choose another
log directory. Optional Xemu arguments can be passed after the script name.

## Inspect guest execution

With Xemu running, attach a multi-architecture GDB in another terminal:

```sh
gdb-multiarch
```

To inspect the current guest state manually, enter:

```gdb
set architecture i386
target remote localhost:1234
info registers
x/20i $eip
x/32wx $esp
```

For the Aqueduct loading trace, use the checked-in GDB command file instead;
it logs UC2's shared `NtCreateFile` wrapper return (path, status, handle),
`NtCreateEvent` outputs, `NtClose` calls, and all seven direct `NtReadFile`
call sites found in the XBE, including the requested length, file offset, and
returned NTSTATUS. This makes it possible to follow handle reuse as well as
event signaling. To start Xemu and attach the trace
from one terminal, run:

```sh
./scripts/run-xemu-uc2-trace.sh
```

The helper opens Xemu with its guest GDB server, waits for port `1234`, and
attaches GDB in batch mode. Navigate to the same CTF-Aqueduct match and close
Xemu when finished; it stores separate timestamped Xemu and guest trace logs in
`diagnostic_logs/`. Optional Xemu arguments can be passed after the helper.
For a currently running Xemu instance, attach manually with:

```sh
nix shell nixpkgs#gdb -c gdb -q -batch -x scripts/xemu-uc2-trace.gdb 2>&1 \
  | tee "diagnostic_logs/xemu_guest_$(date +%Y%m%d_%H%M%S).log"
```

The GDB script automatically continues after each logged call so you can
navigate to the same CTF-Aqueduct match. It records the match worker's context
and handle pair, samples all six raw wait arguments, and traces set, clear, or
pulse calls on those handles. It also captures the game's long-lived
single-object wait, then traces operations on that wait's handle, along with
non-timeout worker results and completion-handler entry/return. Compare those
records with the recomp's `UC2 wait raw args` and `UC2 wait-handle` lines to
see whether the reference signals the main loading event after opening the
map packages and whether the worker handles resolve to the same object types.
The trace also records the five XPP call sites that invoke `KeSetEvent`, since
the XPP async-completion path signals dispatcher objects through that kernel
API rather than the `NtSetEvent` wrapper. Those records include the XPP call
site and the event object's pointer and arguments. It also records XPP's
`ObReferenceObjectByHandle` result, mapping the file/event handle to the
dispatcher object's guest address for correlation with the wait list.
At the post-call breakpoints, the kernel export has already popped its stdcall
arguments, so each event handle is read from `[ESP+4]` after the wrapper's
return address. This keeps the set/clear/pulse records tied to the actual
worker handles.
Both the Xemu console log and GDB trace stay outside the tracked game/source
files.

The addresses in `analysis/disasm/asm/text.asm` and the generated recomp map
directly to the guest's Xbox virtual addresses, so a GDB stop can be correlated
with the same guest code that XboxXBERecomp translates. The wait and event
breakpoints are sampled or filtered to the active match worker's handles;
tracing every frame or every short wait would stall the emulator and produce
excessive logs.
