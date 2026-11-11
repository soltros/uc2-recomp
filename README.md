# Unreal Championship 2: The Liandri Conflict Recomp

An experimental Linux recomp built with [XboxXBERecomp](https://github.com/datfooldive/DEFJAM-XBERecomp-Linux), its XBE analysis/code-generation tools, and its Linux runtime. The runtime renders through Vulkan. This repository contains no game binaries, assets, or generated guest code; provide your own game files locally.

This project is licensed under GPL-3.0-only. See [LICENSE](LICENSE). XboxXBERecomp and its dependencies remain separately licensed.

## Status

XboxXBERecomp recognizes the title as Unreal Championship 2 (`0x4D570021`), with XDK 5849 and guest entry point `0x0026867F`. The Linux executable builds from local game files and renders the front-end UI, including menu text, portraits, and weapon icons. Screenshots from 2026-11-11 still show missing/black preview areas and other incomplete assets. In the latest available run at 13:28, the user navigated into a CTF match; the title displayed its animated loading screen, opened `CTF-Downfall.lin` and its three XPR packages, and remained there until the window was closed at 59.532 seconds. Audio played. A gameplay frame has not yet been verified.

That 13:28 run used an older binary and did not include the latest file-handle tracing. The current build adds handle correlation to package-open and file-transfer logs; a new run through the match-load transition is needed to determine whether the map packages are being read and where loading stops. The Linux fork is built from the separate XboxXBERecomp checkout, with UC2-specific tool changes recorded as patches under `patches/xberecomp/`. Keep generated outputs and game content out of Git.

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
./scripts/run-diagnostic.sh
```

The launcher writes a timestamped log to `diagnostic_logs/` and captures a frame every second (press F3 in the game window to capture one immediately). It stays open until you close the game window. Set `UC2_XBERECOMP_BIN` to run another executable.

## ABI and graphics work

The title config uses XboxXBERecomp's symbol scanner and register/stack calling-convention mappings. The XDK 5849 scan identified 13 LTCG D3D entries whose register-use shape differs from the reference library. The custom overrides and their call-site evidence are documented in [the UC2 ABI audit](docs/UC2-ABI-AUDIT.md). Visible gameplay is still needed to validate the draw path end to end. Keep generated outputs and game content out of Git.
