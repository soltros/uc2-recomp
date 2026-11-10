#!/usr/bin/env bash
set -euo pipefail

# Add the development outputs needed to build the Linux XboxXBERecomp fork.
# Nix profiles identify one entry per package name, so replace the existing
# runtime-only entries with entries that include both runtime and dev outputs.

if ! command -v nix >/dev/null 2>&1; then
    echo "error: nix is not on PATH" >&2
    exit 1
fi

replace=(
    shaderc vulkan-loader libx11 libxext libxrandr libxcursor libxi
    libxfixes libxrender libxkbcommon wayland libdecor pipewire
    libpulseaudio alsa-lib systemd xorgproto
)

installables=(
    'nixpkgs#shaderc^out,lib,bin,dev'
    'nixpkgs#vulkan-loader^out,dev'
    'nixpkgs#libx11^out,dev'
    'nixpkgs#libxext^out,dev'
    'nixpkgs#libxrandr^out,dev'
    'nixpkgs#libxcursor^out,dev'
    'nixpkgs#libxi^out,dev'
    'nixpkgs#libxfixes^out,dev'
    'nixpkgs#libxrender^out,dev'
    'nixpkgs#libxkbcommon^out,dev'
    'nixpkgs#wayland^out,dev'
    'nixpkgs#libdecor^out,dev'
    'nixpkgs#pipewire^out,dev'
    'nixpkgs#libpulseaudio^out,dev'
    'nixpkgs#alsa-lib^out,dev'
    'nixpkgs#systemd^out,dev,man'
    'nixpkgs#xorgproto'
)

echo "Replacing runtime-only profile entries with entries that include development outputs..."
profile_json="$(nix profile list --json)"
mapfile -t installed_entries < <(
    python3 -c 'import json, sys; items = json.load(sys.stdin)["elements"]; print("\n".join(name for name in sys.argv[1:] if name in items))' \
        "${replace[@]}" <<<"$profile_json"
)
if ((${#installed_entries[@]})); then
    nix profile remove "${installed_entries[@]}"
fi
if ! nix profile add "${installables[@]}"; then
    echo "Install failed; restoring the previous Nix profile generation." >&2
    nix profile rollback || true
    exit 1
fi
echo "Development outputs installed in the Nix profile."
