#!/usr/bin/env bash
# about: USBTMC/USB488 instrument answering *IDN? (PyVISA) - BlackPill + Pico
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=device/usbtmc
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
