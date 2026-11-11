# Unreal Championship 2: The Liandri Conflict Recomp

An experimental Linux recomp built with [XboxXBERecomp](https://github.com/datfooldive/DEFJAM-XBERecomp-Linux), its XBE analysis/code-generation tools, and its Linux runtime. The runtime renders through Vulkan. This repository contains no game binaries, assets, or generated guest code; provide your own game files locally.

This project is licensed under GPL-3.0-only. See [LICENSE](LICENSE). XboxXBERecomp and its dependencies remain separately licensed.

## Status

XboxXBERecomp recognizes the title as Unreal Championship 2 (`0x4D570021`), with XDK 5849 and guest entry point `0x0026867F`. The Linux executable builds from local game files. On an AMD Radeon RX 6700 XT using Vulkan, the 2026-11-10 diagnostic run stayed open for 37 seconds at about 60 FPS and exited cleanly when the window was closed. Audio played, but the display remained black after the loading screen; rendered gameplay is not yet verified.

Commit `34e3dd5` initializes the guest D3D push/fence state through UC2's XDK routine. This fixed the previous guest crash. The available automatic frame capture was taken during an earlier one-draw transition and was black; later in the run, the runtime reported 8–12 draws per frame. A capture from that later state is still needed to trace the black screen.

The Linux fork is built from the separate XboxXBERecomp checkout, with UC2-specific tool changes recorded as patches under `patches/xberecomp/`. The optimized development build keeps boot and per-frame Info logs enabled. The repo is GPL-3.0-only and keeps game files, generated guest code, and build output outside Git.

## Requirements

- Linux x86-64, CMake 3.25+, Ninja or another supported build tool, and Clang/Clang++ with C++20 support
- The XboxXBERecomp Linux checkout and the Linux development dependencies documented there
- A legally acquired, extracted Unreal Championship 2 game directory containing `default.xbe`

## Local game files

The build expects `assets/default.xbe`. By default, `scripts/build-xberecomp-linux.sh` links `assets/` to the ignored `game/` path. The existing `game/` symlink can point to the user's extracted game directory. To use another location, set `UC2_GAME_DIR` when building. Neither path nor game files are committed.

Set `XBERECOMP_ROOT` to the XboxXBERecomp checkout if it is not at `~/Projects/uc2-xberecomp-linux-evaluation`:

```sh
XBERECOMP_ROOT="$HOME/Projects/uc2-xberecomp-linux-evaluation" \
  ./scripts/build-xberecomp-linux.sh
```

The script configures the project and builds `build-xberecomp/uc2_recomp`. XboxXBERecomp generates the guest C++ translation under the ignored `generated/uc2/` directory from the local XBE and `config/uc2.toml`.

## Run and capture diagnostics

```sh
RECOMP_WATCHDOG_SECS=45 ./scripts/run-diagnostic.sh
```

The launcher writes a timestamped log to `diagnostic_logs/` and configures frame capture there (press F3 in the game window). Set `UC2_XBERECOMP_BIN` to run another executable. Omit `RECOMP_WATCHDOG_SECS` to let the game run until it is closed.

## ABI and graphics work

The title config uses XboxXBERecomp's symbol scanner and register/stack calling-convention mappings. The XDK 5849 signature scan identified 13 LTCG D3D entry points whose register use differs from the reference library. Their custom ABI mappings are in `config/uc2.toml`; call-site setup in the generated UC2 x86 code supplies additional argument-order evidence. The D3D push-state initializer mapping is verified directly: its caller loads the device into ESI before calling `0x003867A0`, and the callee accesses the device through ESI. The remaining mappings still need broader semantic and runtime validation. Keep generated outputs and game content out of Git.
