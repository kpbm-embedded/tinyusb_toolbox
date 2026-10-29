#!/usr/bin/env bash
# about: USB HOST stack: enumerates CDC, MSC and HID devices - Pico (native host) + BlackPill (OTG FS host)
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=host/cdc_msc_hid
TU_SYMS=tuh_task_ext TU_VID=0
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
