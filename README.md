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
- The Linux/OpenGL runtime and generated game code compile and link. Plain
  single-configuration CMake builds now default to `Release`; generated guest
  code is CPU-intensive, and an unoptimized build advanced through startup too
  slowly.
- The POSIX host initializes xboxrecomp's optional MCPX APU model when
  `RECOMP_AC97_READY=1` is set. This lets DirectSound initialize; without it,
  DirectSound returns `DSERR_NODRIVER` and the title skips D3D setup.
- An optimized headless run loaded `D:\Movies\UC2_Logos.xmv`,
  `D:\Textures\Movies\UI_LoadingMovie.xmv`, and
  `Z:\XboxMaps\Menu.lin`. Texture captures include the teal UC2 loading
  animation, and the GPU submitted over 5,600 draws in 90 seconds without a
  guest fault. Earlier windowed runs displayed the studio logos. A windowed
  menu/gameplay run and controller response still need validation.
- Release mode exposed an unsupported `F7 TEST` instruction in xboxrecomp's
  POSIX x86-64 MMIO decoder. The decoder fix and focused test are in
  [`soltros/xboxrecomp` commit d832e03](https://github.com/soltros/xboxrecomp/commit/d832e03).
  The test passes with `ctest --test-dir /tmp/mmio-decode-x86_64-build
  --output-on-failure`.
- The diagnostic launcher enables paced vblank and caps guest delays at 1 ms
  so startup can pass the title's roughly 49-day sleep. Set
  `RECOMP_WATCHDOG_SECS=0` explicitly when launching from a shell that may
  already export a watchdog timeout.

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

Single-configuration builds default to `Release` because the generated guest
code performs CPU-intensive work such as XMV video decoding. Select
`-DCMAKE_BUILD_TYPE=Debug` explicitly when debugging the host or generated
code.

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
