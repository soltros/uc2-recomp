#!/usr/bin/env bash
set -euo pipefail

# Run a command with Nix profile development libraries visible to pkg-config,
# CMake, and the runtime linker. Example:
#   ./scripts/with-xberecomp-nix-env.sh cmake --preset release

profile="${UC2_NIX_PROFILE:-$HOME/.nix-profile}"
if [[ ! -d "$profile" ]]; then
    echo "error: Nix profile not found: $profile" >&2
    exit 1
fi
if [[ $# -eq 0 ]]; then
    echo "usage: $0 command [argument ...]" >&2
    exit 2
fi

export PKG_CONFIG_PATH="$profile/lib/pkgconfig:$profile/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="$profile${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export VULKAN_SDK="${VULKAN_SDK:-$profile}"
export LD_LIBRARY_PATH="$profile/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$@"
