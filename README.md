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
- The Linux/OpenGL runtime and generated game code compile and link. The first
  boot currently stops during SDL3 loading because the installed SDL2
  compatibility library and executable resolve different glibc versions.

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

The `analysis/`, `src/recomp/gen/`, and `build/` directories are local outputs
and are not committed.

## License

This project is distributed under GPL-3.0-only. See [LICENSE](LICENSE).
The xboxrecomp toolkit is a separate dependency under its own license.
