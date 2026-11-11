#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_root="${XBERECOMP_ROOT:-$HOME/Projects/uc2-xberecomp-linux-evaluation}"
game_dir="${UC2_GAME_DIR:-$repo_root/game}"
build_dir="${UC2_BUILD_DIR:-$repo_root/build-xberecomp}"
jobs="${UC2_BUILD_JOBS:-4}"

if [[ ! -f "$game_dir/default.xbe" ]]; then
    echo "error: default.xbe not found under $game_dir" >&2
    echo "Set UC2_GAME_DIR to your extracted game directory." >&2
    exit 1
fi
game_dir="$(cd "$game_dir" && pwd -P)"

if [[ -e "$repo_root/assets/default.xbe" ]]; then
    echo "Using local game files in $repo_root/assets"
elif [[ -e "$repo_root/assets" || -L "$repo_root/assets" ]]; then
    echo "error: assets exists but does not contain default.xbe: $repo_root/assets" >&2
    exit 1
else
    ln -s "$game_dir" "$repo_root/assets"
fi

if [[ ! -f "$tool_root/sdk/cmake/XbeRecomp.cmake" ]]; then
    echo "error: XboxXBERecomp checkout not found: $tool_root" >&2
    echo "Set XBERECOMP_ROOT to its root directory." >&2
    exit 1
fi

# Keep UC2-specific XboxXBERecomp fixes reproducible when building against a
# fresh checkout of the Linux fork. Each patch is a no-op when already applied.
for tool_patch in "$repo_root"/patches/xberecomp/*.patch; do
    if git -C "$tool_root" apply --reverse --check "$tool_patch" >/dev/null 2>&1; then
        echo "$(basename "$tool_patch") is already applied."
    elif git -C "$tool_root" apply --check "$tool_patch"; then
        git -C "$tool_root" apply "$tool_patch"
        echo "Applied $(basename "$tool_patch") to XboxXBERecomp."
    elif [[ "$(basename "$tool_patch")" == "0001-uc2-runtime-fixes.patch" ]] && \
         rg -q 'map_device_window' "$tool_root/sdk/runtime/kernel/memory.cpp" && \
         rg -q 'kNv2aBase' "$tool_root/sdk/runtime/kernel/memory.h" && \
         rg -q 'applied unset texture-stage defaults' "$tool_root/sdk/runtime/xdk/d3d8.cpp" && \
         rg -q 'HAS_D3D_SimpleRenderStateEncode' "$tool_root/sdk/runtime/xdk/d3d8.cpp"; then
        # Later UC2 patches edit adjacent lines in d3d8.cpp, so Git cannot
        # reverse-check this original multi-file patch as a single unit. Verify
        # its distinct runtime fixes are present before treating it as applied.
        echo "$(basename "$tool_patch") fixes are already present (overlapped by later UC2 patches)."
    elif [[ "$(basename "$tool_patch")" == "0005-hle-uc2-directsound-create-stream.patch" ]] && \
         rg -q 'static uint32_t CreateStream\(uint32_t desc, uint32_t out\)' "$tool_root/sdk/runtime/xdk/dsound.cpp" && \
         rg -q 'HLE_STDCALL\(DirectSoundCreateStream, 2\) \{ return CreateStream\(a\[0\], a\[1\]\); \}' "$tool_root/sdk/runtime/xdk/dsound.cpp" && \
         rg -q 'HLE_STDCALL\(IDirectSound_CreateSoundStream, 4\) \{ return CreateStream\(a\[1\], a\[2\]\); \}' "$tool_root/sdk/runtime/xdk/dsound.cpp"; then
        # The B0098 diagnostic wrapper edits the same adjacent block, preventing
        # Git's all-hunks reverse check from recognizing this applied patch.
        echo "$(basename "$tool_patch") fixes are already present (overlapped by the B0098 diagnostic wrapper)."
    else
        echo "error: cannot apply $(basename "$tool_patch") to $tool_root" >&2
        exit 1
    fi
done

# Nix keeps libxcb's development headers in a store output that may not be
# merged into the profile include tree. SDL's Vulkan/X11 sources need this
# header even though the runtime loader is already on the profile library path.
if [[ -z "${CPATH:-}" && ! -f "$HOME/.nix-profile/include/xcb/xcb.h" ]]; then
    for candidate in /nix/store/*-libxcb-*-dev/include; do
        if [[ -f "$candidate/xcb/xcb.h" ]]; then
            export CPATH="$candidate"
            break
        fi
    done
fi

configure_args=(
    -S "$repo_root" -B "$build_dir"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER=clang
    -DCMAKE_CXX_COMPILER=clang++
    -DCMAKE_C_FLAGS=-march=x86-64-v2
    -DCMAKE_CXX_FLAGS=-march=x86-64-v2
    -DXBERECOMP_ROOT="$tool_root"
)
fetch_root="$tool_root/out/build/release/_deps"
for dep in ZYDIS TOMLPLUSPLUS IMGUI SDL3 VMA; do
    dep_lower="$(printf '%s' "$dep" | tr '[:upper:]' '[:lower:]')"
    source_dir="$fetch_root/${dep_lower}-src"
    if [[ -d "$source_dir" ]]; then
        configure_args+=("-DFETCHCONTENT_SOURCE_DIR_${dep}=$source_dir")
    fi
done

"$repo_root/scripts/with-xberecomp-nix-env.sh" cmake "${configure_args[@]}"
"$repo_root/scripts/with-xberecomp-nix-env.sh" cmake --build "$build_dir" --parallel "$jobs"
