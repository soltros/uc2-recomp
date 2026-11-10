#!/usr/bin/env bash
set -euo pipefail

# Add the development outputs needed to build the Linux XboxXBERecomp fork.
# The main compiler/runtime packages are installed separately in the user's
# Nix profile; this fills in the headers, pkg-config files, and shaderc library.

if ! command -v nix >/dev/null 2>&1; then
    echo "error: nix is not on PATH" >&2
    exit 1
fi

installables=(
    'nixpkgs#shaderc^dev'
    'nixpkgs#shaderc^lib'
    'nixpkgs#vulkan-loader^dev'
    'nixpkgs#libx11^dev'
    'nixpkgs#libxext^dev'
    'nixpkgs#libxrandr^dev'
    'nixpkgs#libxcursor^dev'
    'nixpkgs#libxi^dev'
    'nixpkgs#libxfixes^dev'
    'nixpkgs#libxrender^dev'
    'nixpkgs#libxkbcommon^dev'
    'nixpkgs#wayland^dev'
    'nixpkgs#libdecor^dev'
    'nixpkgs#pipewire^dev'
    'nixpkgs#libpulseaudio^dev'
    'nixpkgs#alsa-lib^dev'
    'nixpkgs#systemd^dev'
)

echo "Installing the development outputs required by the UC2 XboxXBERecomp build..."
nix profile install "${installables[@]}"
echo "Development outputs installed."
