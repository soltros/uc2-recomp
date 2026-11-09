# Unreal Championship 2: The Liandri Conflict Recomp

An experimental Linux recomp project based on the upstream **xboxrecomp**
toolkit and its runtime libraries:

<https://github.com/sp00nznet/xboxrecomp>

The project uses only xboxrecomp's parser, analysis pipeline, generated
recompilation, and runtime APIs. Linux rendering uses xboxrecomp's bundled
SDL2/OpenGL backend. The project is licensed under GPL-3.0-only. Original game
files and generated recomp output are not included in this repository. Provide
your own game files locally under `game/`.

## Current status

- XBE parsing succeeds with xboxrecomp v0.17.0.
- `default.xbe` identifies the title as Unreal Championship 2, title ID
  `0x4D570021`, with guest entry point `0x0026867F`.
- The XBE contains 18 sections, 156 kernel imports, and was built with XDK
  5849.
- Full disassembly covered 1.23 million instructions across all executable
  sections and found 13,942 functions.
- Function identification classified 17,072 entries, including discovered
  vtable thunks. ABI analysis wrote 13,942 entries and identified 2,790
  `thiscall` functions.
- xboxrecomp generated 13,943 functions into 56 local C chunks, plus the
  dispatch table and register header. These outputs are ignored by Git.
- The Linux/OpenGL runtime and generated game code compile and link. Building
  with the host GCC 16.2 toolchain resolved an SDL2-compat/glibc version
  mismatch seen with GCC 15.2.
- The POSIX host initializes xboxrecomp's optional MCPX APU model when
  `RECOMP_AC97_READY=1` is set. This lets DirectSound initialize; without it,
  DirectSound returns `DSERR_NODRIVER` and the title skips D3D setup.
- First visible output is confirmed: with the xboxrecomp pushbuffer executor
  enabled, the SDL/OpenGL window displays the game's splash screen. The title
  opens `D:\Startup\UC2Startup.xpr`, `D:\Movies\UC2_Logos.xmv`, and
  `D:\System\Localization\int\Core.int`; the GPU log records two flips,
  a surface clear, and a rasterized draw. It then stops submitting new GPU
  work, with the pushbuffer PUT and GET pointers equal. A 20-second local
  watchdog confirms the guest stops inside `KeDelayExecutionThread`, called
  from guest VA `0x0001A2F6` with timeout `0xFFFFFED8` (a roughly 49-day delay).
  Before that wait it resolves startup data through function `0x00260B87`.
  The window and APU shut down cleanly. Gameplay, controls, audio quality, and
  sustained rendering still need validation.
- With the opt-in `RECOMP_DELAY_CAP_MS=1` diagnostic setting and paced
  vblank enabled, a local headless run advanced past that wait and produced
  13,528 flips and clears over 20 seconds. It later entered another long
  delay. This confirms the wait is gating startup progress, but the visible
  result and control response still need a user-window run.
- The POSIX host now watches for the title's D3D semaphore and registers its
  guest address with xboxrecomp's pushbuffer executor. This is intended to let
  the executor publish `BACK_END_WRITE_SEMAPHORE_RELEASE` progress where the
  title waits. The latest run logged target `0x80267000` and advanced beyond
  the earlier queue stall to two flips and a surface clear. Closing the window
  now shuts down SDL audio and the APU cleanly. No watchdog or input diagnostics
  were enabled in that run, so sustained rendering and controls remain
  unverified.

## Requirements

- Linux x86-64
- xboxrecomp checkout
- Python 3.10+ with Capstone
- CMake 3.20+, a C compiler and build tool, SDL2, OpenGL, libepoxy, and OpenSSL
- Your own extracted Unreal Championship 2 files

Install runtime build dependencies as described by xboxrecomp's
`tools/linux/install_deps.sh`. The POSIX host uses xboxrecomp's
`xbox_PosixMmioFault` and `xbox_HostWindowMain` APIs.

## Local game files

Put the extracted game files under `game/`, preserving their directory
structure. `game/` and known Xbox game file formats are ignored by Git.

## Regenerate and build

Set `UC2` to this checkout and `XBOXRECOMP_DIR` to the xboxrecomp checkout.
Run the following from the xboxrecomp directory after placing your game files
under `$UC2/game/`:

```sh
mkdir -p "$UC2/analysis"
python3 -m tools.xbe_parser "$UC2/game/default.xbe" --json "$UC2/analysis/uc2_analysis.json"
python3 -m tools.disasm "$UC2/game/default.xbe" --analysis-json "$UC2/analysis/uc2_analysis.json" --output "$UC2/analysis/disasm"
python3 -m tools.func_id "$UC2/game/default.xbe" --functions "$UC2/analysis/disasm/functions.json" --strings "$UC2/analysis/disasm/strings.json" --xrefs "$UC2/analysis/disasm/xrefs.json" --output "$UC2/analysis/func_id"
python3 -m tools.abi_analysis "$UC2/game/default.xbe" --disasm-dir "$UC2/analysis/disasm" --func-id-dir "$UC2/analysis/func_id" --output-dir "$UC2/analysis/abi"
python3 -m tools.recomp "$UC2/game/default.xbe" --game-name "Unreal Championship 2: The Liandri Conflict" --all --split 250 --gen-dir "$UC2/src/recomp/gen" --disasm-dir "$UC2/analysis/disasm" --func-id-dir "$UC2/analysis/func_id" --abi-dir "$UC2/analysis/abi"
```

Then configure and build the Linux executable:

```sh
cmake -S "$UC2" -B "$UC2/build" -DXBOXRECOMP_DIR="$XBOXRECOMP_DIR"
cmake --build "$UC2/build" --parallel 2
```

Run with the Xbox memory extension, APU model, pushbuffer executor, and
framebuffer window enabled:

```sh
cd "$UC2"
RECOMP_AC97_READY=1 RECOMP_EXT_VMA=1 RECOMP_PB_EXEC=1 RECOMP_FB_WINDOW=1 \
RECOMP_KEYBOARD=1 ./build/uc2_recomp
```

The Linux framebuffer presenter uses SDL, while the toolkit's D3D8
compatibility layer targets OpenGL. `RECOMP_FB_WINDOW=1` opens the toolkit's
host window; omit it to run headless.

`RECOMP_KEYBOARD=1` enables the toolkit's keyboard controller mapping in the
focused window (Enter maps to Xbox START). Keyboard input was disabled in the
first splash-screen run, so menu navigation has not yet been checked.

Run the diagnostic launcher to capture input state, the guest watchdog,
texture registers, and periodic snapshots of textures used by the renderer.
Logs and texture BMPs are kept under the ignored `diagnostic_logs/` directory.
The latest user run reached 203 flips at about 6 FPS, then stopped advancing;
the snapshots should show whether the movie texture continues changing:

```sh
./scripts/run-diagnostic.sh
```

The launcher enables keyboard input, input diagnostics, and key tracing. It
defaults to paced 60 Hz vblank and caps guest delays at 1 ms so startup can
advance past the title's roughly 49-day sleep. The runtime logs each shortened
delay. The watchdog is disabled by default so the game can keep running. Set
`RECOMP_WATCHDOG_SECS=60` to capture guest state and exit with status 3 after
60 seconds. With the window focused, press Enter to test START; the launcher
logs key events and controller state. Override `RECOMP_VBLANK` or
`RECOMP_DELAY_CAP_MS` to change these diagnostic defaults.

The launcher captures every 30th bind of an already-seen texture. Set
`RECOMP_TEX_DUMP_EVERY=60` for fewer snapshots, or set
`RECOMP_TEX_DUMP_EVERY=0` to capture only the first use of each texture.

The `analysis/`, `src/recomp/gen/`, and `build/` directories are local outputs
and are not committed.

## License

This project is distributed under GPL-3.0-only. See [LICENSE](LICENSE).
The xboxrecomp toolkit is a separate dependency under its own license.
