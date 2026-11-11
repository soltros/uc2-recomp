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
    libxfixes libxrender libxkbcommon libxcb wayland libdecor libffi pipewire
    libpulseaudio alsa-lib systemd wayland-scanner libxscrnsaver libxtst
    libxinerama libdrm libgbm libthai fribidi libusb1
    libjack2 sndio
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
    'nixpkgs#libxcb^out,dev'
    'nixpkgs#wayland^out,dev'
    'nixpkgs#libdecor^out,dev'
    'nixpkgs#libffi^out,dev'
    'nixpkgs#pipewire^out,dev'
    'nixpkgs#libpulseaudio^out,dev'
    'nixpkgs#alsa-lib^out,dev'
    'nixpkgs#systemd^out,dev,man'
    'nixpkgs#wayland-scanner'
    'nixpkgs#libxscrnsaver'
    'nixpkgs#libxtst'
    'nixpkgs#libxinerama^out,dev'
    'nixpkgs#libdrm^out,dev'
    'nixpkgs#libgbm'
    'nixpkgs#libthai^out,dev'
    'nixpkgs#fribidi^out,dev'
    'nixpkgs#libusb1^out,dev'
    'nixpkgs#libjack2^out,dev'
    'nixpkgs#sndio'
)

echo "Replacing runtime-only profile entries with entries that include development outputs..."
profile_json="$(nix profile list --json)"
profile_changes=0
restore_profile() {
    echo "Restoring the previous Nix profile generation(s)..." >&2
    for ((i = 0; i < profile_changes; i++)); do
        nix profile rollback || true
    done
}

if python3 -c 'import json, sys; sys.exit(0 if "xorgproto" in json.load(sys.stdin)["elements"] else 1)' <<<"$profile_json"; then
    if ! nix profile remove xorgproto; then
        echo "Could not replace the existing xorgproto profile entry." >&2
        exit 1
    fi
    ((profile_changes += 1))
fi
if ! nix profile add --priority 4 'nixpkgs#xorgproto'; then
    echo "Could not add Xorg protocol headers; restoring the previous Nix profile." >&2
    restore_profile
    exit 1
fi
((profile_changes += 1))
mapfile -t installed_entries < <(
    python3 -c 'import json, sys; items = json.load(sys.stdin)["elements"]; print("\n".join(name for name in sys.argv[1:] if name in items))' \
        "${replace[@]}" <<<"$profile_json"
)
if ((${#installed_entries[@]})); then
    if ! nix profile remove "${installed_entries[@]}"; then
        echo "Could not replace existing runtime-only profile entries." >&2
        restore_profile
        exit 1
    fi
    ((profile_changes += 1))
fi
if ! nix profile add "${installables[@]}"; then
    echo "Install failed." >&2
    restore_profile
    exit 1
fi
echo "Development outputs installed in the Nix profile."
