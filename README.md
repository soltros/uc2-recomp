# Unreal Championship 2: The Liandri Conflict Recomp

An experimental Linux recomp project based on the upstream **xboxrecomp**
toolkit and its runtime libraries:

<https://github.com/sp00nznet/xboxrecomp>

The project is licensed under GPL-3.0-or-later. Original game files and
generated recomp output are not included in this repository. To work on the
project, provide your own legally obtained game files locally under `game/`.

## Current status

- XBE parsing succeeds with xboxrecomp v0.17.0.
- `default.xbe` identifies the title as Unreal Championship 2, title ID
  `0x4D570021`, with guest entry point `0x0026867F`.
- The XBE contains 18 sections, 156 kernel imports, and was built with XDK
  5849.
- Function analysis, code generation, and Linux runtime bring-up are next.

## Requirements

- Linux x86-64
- xboxrecomp checkout
- Python 3.10+ with Capstone
- CMake 3.20+, C compiler, SDL2, OpenGL, libepoxy, OpenSSL, and FFmpeg
- Your own extracted Unreal Championship 2 files

Install runtime build dependencies as described by xboxrecomp's
`tools/linux/install_deps.sh`. The toolkit's `templates/new-game` is the
starting point for this project; Linux host startup follows its POSIX runtime
API (`xbox_PosixMmioFault` and `xbox_HostWindowMain`).

## Local game files

Put the extracted game files under `game/`, preserving their directory
structure. `game/` and known Xbox game file formats are ignored by Git.

## License

This project is distributed under GPL-3.0-or-later. See [LICENSE](LICENSE).
The xboxrecomp toolkit is a separate dependency under its own license.
