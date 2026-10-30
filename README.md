# Unreal Championship 2 Recomp Research

Title-specific analysis and recompilation preparation for *Unreal Championship 2: The Liandri Conflict* on Original Xbox. This repository is independent from the general Xbox Linux runtime project; it consumes that runtime only if/when an execution target is developed.

## Legal and source boundaries

Original project code is GPL-3.0-only; see [LICENSE](LICENSE). The parser under `vendor/xboxrecomp-parser/` retains its upstream MIT license. No executable, extracted game data, save data, or generated translation is included. You must provide your own legally obtained extraction. The committed manifest contains file paths, sizes, and hashes only.

## Setup

Clone this repository and, for shared Linux runtime work, the tool separately:

```sh
git clone https://github.com/soltros/uc2-recomp.git
git clone https://github.com/soltros/xbox-linux.git
```

Place your extracted folder beside both repositories as `../Unreal Championship 2 - The Liandri Conflict/default.xbe`, or update `target.json` locally. The executable hash is verified before analysis.

On x86-64 Linux with Nix:

```sh
nix develop
python3 -m unittest discover -s tests -v
python3 tools/workspace.py baseline
python3 tools/workspace.py packages --title uc2
```

Current scope is bounded UE2X package metadata validation. `.LIN` handling, bytecode, native bindings, and runtime execution are not yet implemented. See [research status](docs/STATUS.md).
