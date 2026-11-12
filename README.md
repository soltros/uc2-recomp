# Unreal Championship 2: The Liandri Conflict Recomp

An experimental Linux recomp built with [XboxXBERecomp](https://github.com/datfooldive/DEFJAM-XBERecomp-Linux), its XBE analysis/code-generation tools, and its Linux runtime. The runtime renders through Vulkan. This repository contains no game binaries, assets, or generated guest code; provide your own game files locally.

This project is licensed under GPL-3.0-only. See [LICENSE](LICENSE). XboxXBERecomp and its dependencies remain separately licensed.

## Status

XboxXBERecomp recognizes the title as Unreal Championship 2 (`0x4D570021`), with XDK 5849 and guest entry point `0x0026867F`. The Linux executable renders the front-end UI, including menu text, portraits, and weapon icons, though previews and other assets remain incomplete. The latest successful recomp run (2026-11-11 15:00) reached CTF-Aqueduct, opened its `.lin` and three XPR packages, then remained on the animated loading screen. The main guest thread reset event `0xB0000C40` and waited indefinitely; no reads from those map package handles were logged. Frame captures show the loading screen being presented, but no gameplay frame has been verified. A later 15:43 launch failed before the game started because SDL reported no available video device.

The latest local binary was rebuilt with Xbox file-handle synchronous/asynchronous semantics and tracing for map-file open options. Successful I/O on asynchronous handles now returns `STATUS_PENDING` after recording the completed IOSB and signaling the file object/event. This build has not yet been run through the match-load transition. Use `./scripts/build-xberecomp-linux.sh` to apply the checked-in patches to the separate XboxXBERecomp checkout and rebuild; use `./scripts/run-diagnostic.sh` for a timestamped manual run. UC2-specific tool changes remain recorded under `patches/xberecomp/`. Keep generated outputs and game content out of Git.

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

The launcher writes a timestamped log to `diagnostic_logs/` and captures a frame every second. It stays open until you close the game window. Set `UC2_XBERECOMP_BIN` to run another executable.

Pressing F3 also captures the current GPU frame and prints guest thread stacks at info level. Routine loader traces also log stack context at info level; actual crashes and guest traps retain error-level register and stack dumps. Automatic captures avoid the stack dump; use those for routine runs and press F3 when a thread-stack snapshot is useful.

## ABI and graphics work

The title config uses XboxXBERecomp's symbol scanner and register/stack calling-convention mappings. The XDK 5849 scan identified 13 LTCG D3D entries whose register-use shape differs from the reference library. The custom overrides and their call-site evidence are documented in [the UC2 ABI audit](docs/UC2-ABI-AUDIT.md). Visible gameplay is still needed to validate the draw path end to end. Keep generated outputs and game content out of Git.
