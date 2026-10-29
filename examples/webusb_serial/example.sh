#!/usr/bin/env bash
# about: WebUSB (vendor class + BOS/MS OS 2.0 descriptors) + CDC: browser talks to the board - BlackPill + Pico
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=device/webusb_serial
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
