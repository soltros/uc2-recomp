#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p diagnostic_logs
stamp=$(date +%Y%m%d_%H%M%S)
log="diagnostic_logs/uc2_recomp_${stamp}.log"
watchdog_secs="${UC2_DIAG_WATCHDOG_SECS:-0}"
binary="${UC2_RECOMP_BIN:-}"
if [[ -z "$binary" ]]; then
  if [[ -x build-glibc244/uc2_recomp ]]; then
    binary=build-glibc244/uc2_recomp
  else
    binary=build/uc2_recomp
  fi
fi

env \
  RECOMP_AC97_READY=1 \
  RECOMP_EXT_VMA=1 \
  RECOMP_PB_EXEC=1 \
  RECOMP_FB_WINDOW=1 \
  RECOMP_GL_PRESENT=1 \
  RECOMP_AUDIO_HOST=1 \
  RECOMP_AUDIO_WAV="${RECOMP_AUDIO_WAV:-diagnostic_logs/uc2_audio_${stamp}.wav}" \
  RECOMP_AUDIO_WAV_SECS="${RECOMP_AUDIO_WAV_SECS:-45}" \
  RECOMP_TEX_STATE=1 \
  RECOMP_TEX_DUMP="${RECOMP_TEX_DUMP:-diagnostic_logs/uc2_texture_${stamp}_}" \
  RECOMP_TEX_DUMP_EVERY="${RECOMP_TEX_DUMP_EVERY:-30}" \
  RECOMP_FB_DUMP="${RECOMP_FB_DUMP:-diagnostic_logs/uc2_frame_${stamp}_}" \
  RECOMP_USB=1 \
  RECOMP_USB_STATS=1 \
  RECOMP_KEYBOARD=1 \
  RECOMP_KEY_TRACE=1 \
  RECOMP_INPUT_DIAG=1 \
  RECOMP_VBLANK="${RECOMP_VBLANK:-paced}" \
  RECOMP_DELAY_CAP_MS="${RECOMP_DELAY_CAP_MS:-1}" \
  RECOMP_WATCHDOG_SECS="$watchdog_secs" \
  RECOMP_PEEK="${RECOMP_PEEK:-0x393888,0x391410,0x80267000,0x802C6080,0x802CCDFC}" \
  "$binary" 2>&1 | tee "$log"
