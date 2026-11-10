# Unreal Championship 2: The Liandri Conflict Recomp

An experimental Linux recomp built with [XboxXBERecomp](https://github.com/datfooldive/DEFJAM-XBERecomp-Linux), its XBE analysis/code-generation tools, and its Linux runtime. The runtime renders through Vulkan. This repository contains no game binaries, assets, or generated guest code; provide your own game files locally.

This project is licensed under GPL-3.0-only. See [LICENSE](LICENSE). XboxXBERecomp and its dependencies remain separately licensed.

## Status

XboxXBERecomp recognizes the title as Unreal Championship 2 (`0x4D570021`), with XDK 5849 and guest entry point `0x0026867F`. The generated Linux executable built successfully from the local XBE. Its first run reaches SDL audio initialization and then faults when UC2 probes the NV2A register window at guest address `0xFD001804`.

The Linux fork initially reserved this Xbox device aperture as inaccessible memory. A runtime fix is committed in the local XboxXBERecomp checkout as `2206710` (push is pending network access); the rebuilt executable compiles, but still needs a desktop run to verify startup beyond that fault. Direct3D ABI mappings in `config/uc2.toml` are provisional and will be audited as runtime diagnostics expose the next issues. Rendered gameplay is not yet verified.

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

The title config uses XboxXBERecomp's symbol scanner and register/stack calling-convention mappings. The current D3D mapping list was assembled from the UC2 XBE's generated x86 call sites; it is not yet fully runtime-validated. Use the fault PC, guest registers, and generated instruction comments in `generated/uc2/` to audit each call. Keep generated outputs and game content out of Git.
