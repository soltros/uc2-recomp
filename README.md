# Unreal Championship 2 Recomp Research

Title-specific analysis and recompilation preparation for *Unreal Championship 2: The Liandri Conflict* on Original Xbox. This repository is independent from the general Xbox Linux runtime project; it consumes that runtime only if/when an execution target is developed.

## Legal and source boundaries

Original project code is GPL-3.0-only; see [LICENSE](LICENSE). The parser under `vendor/xboxrecomp-parser/` retains its upstream MIT license. No executable, extracted game data, save data, or generated translation is included. You must provide your own legally obtained extraction. The committed manifest contains file paths, sizes, and hashes only.

## Setup

For a one-command setup on x86-64 Linux with Nix flakes enabled, put your legally obtained extraction anywhere and run:

```sh
./install.sh "/path/to/Unreal Championship 2 - The Liandri Conflict"
```

The installer checks the exact XBE hash, clones/builds the separate shared runtime/toolchain, runs the tests, and produces local XBE and package reports. It does not copy or upload game files. `XBOX_LINUX_DIR=/path/to/xbox-linux` can select an existing runtime checkout.

You can also clone the repositories side by side:

```sh
git clone https://github.com/soltros/uc2-recomp.git
git clone https://github.com/soltros/xbox-linux.git
```

The default extraction location is `../Unreal Championship 2 - The Liandri Conflict/default.xbe`; alternatively pass any extraction directory to `install.sh`.

On x86-64 Linux with Nix:

```sh
nix develop
python3 -m unittest discover -s tests -v
python3 tools/workspace.py verify --game-dir "../Unreal Championship 2 - The Liandri Conflict"
python3 tools/workspace.py xbe --game-dir "../Unreal Championship 2 - The Liandri Conflict" --title uc2
python3 tools/workspace.py packages --game-dir "../Unreal Championship 2 - The Liandri Conflict" --title uc2
```

Current scope is bounded UE2X package metadata validation. `.LIN` handling, bytecode, native bindings, and runtime execution are not yet implemented. See [research status](docs/STATUS.md).
