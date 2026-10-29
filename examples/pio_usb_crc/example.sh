#!/usr/bin/env bash
# about: HOST test: Pico-PIO-USB's software CRC5/CRC16 (used by dual_pio_host) vs bit-by-bit references from the USB spec
# Usage (through ./tinyusb-box examples ...): example.sh build | run | test
set -euo pipefail
OUT=${EX_OUT:?run through ./tinyusb-box examples}
PIO="$TINYUSB_DIR/hw/mcu/raspberry_pi/Pico-PIO-USB/src"
build() {
  [[ -r "$PIO/usb_crc.c" ]] || { echo "Pico-PIO-USB missing: ./tinyusb-box bootstrap"; exit 1; }
  # usb_crc.h includes pico/stdlib.h only for the RAM-placement macros: a host stub makes them no-ops
  mkdir -p "$OUT/stub/pico"
  printf '%s\n' '#pragma once' '#include <stdint.h>' '#define __not_in_flash(x)' '#define __not_in_flash_func(f) f' \
    '#define __time_critical_func(f) f' >"$OUT/stub/pico/stdlib.h"
  cc -std=gnu11 -O2 -Wall -Wextra -I"$OUT/stub" -I"$PIO" "$EX_DIR/crc_check.c" "$PIO/usb_crc.c" -o "$OUT/crc_check"
}
case "${1:-run}" in
  build) build ;;
  run|test) build; "$OUT/crc_check"; echo "PASS pio_usb_crc" ;;
  *) echo "usage: example.sh build|run|test" >&2; exit 2 ;;
esac
