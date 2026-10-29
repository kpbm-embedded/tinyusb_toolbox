#!/usr/bin/env bash
# about: DFU mode device, alt FLASH/EEPROM (dfu-util -D/-U into RAM handlers) - BlackPill + Pico
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=device/dfu
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
