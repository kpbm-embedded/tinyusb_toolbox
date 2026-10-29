#!/usr/bin/env bash
# about: UAC2 audio headset: speaker + microphone, volume/mute (isochronous endpoints) - BlackPill + Pico
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=device/uac2_headset
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
