#!/usr/bin/env bash
# about: CDC serial echo + 8 KB RAM mass-storage disk (README.TXT) - BlackPill + Pico
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=device/cdc_msc
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
