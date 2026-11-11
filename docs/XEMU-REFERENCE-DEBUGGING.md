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

Then enter:

```gdb
set architecture i386
target remote localhost:1234
info registers
x/20i $eip
x/32wx $esp
```

The addresses in `analysis/disasm/asm/text.asm` and the generated recomp map
directly to the guest's Xbox virtual addresses, so a GDB stop can be correlated
with the same guest code that XboxXBERecomp translates. We will add targeted
breakpoints for the Aqueduct load once the reference trace identifies the
relevant guest call sites; tracing every frame or every short wait would stall
the emulator and produce excessive logs.
