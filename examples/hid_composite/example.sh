#!/usr/bin/env bash
# about: HID composite: keyboard + mouse + consumer + gamepad on one interface - BlackPill + Pico
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=device/hid_composite
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
