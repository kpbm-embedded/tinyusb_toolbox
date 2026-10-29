#!/usr/bin/env bash
# about: USB MIDI 1.0 device: plays a note sequence, reads incoming MIDI - BlackPill + Pico
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=device/midi_test
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
