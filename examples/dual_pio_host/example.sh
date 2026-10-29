#!/usr/bin/env bash
# about: device + host at once: CDC device on native USB, Pico-PIO-USB host on GP0/GP1 (HID -> CDC) - Pico
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=dual/host_hid_to_device_cdc
TU_BOARDS=raspberry_pi_pico TU_SYMS="tud_task_ext tuh_task_ext"
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
