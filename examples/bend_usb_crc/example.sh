#!/usr/bin/env bash
# about: Bend 2 laws + proofs: Pico-PIO-USB's CRC-16 table = bitwise USB CRC for all 256 bytes, check value, streaming law (host only)
# Usage (through ./tinyusb-box examples ...): example.sh build | run | test
# Bend runs on the PC only (it has no MCU target): it proves facts about the table the dual_pio_host firmware ships.
# The pinned Bend 2.0.39 is part of this ID (pins group bend, `./tinyusb-box install`), run via `./tinyusb-box bend`.
set -euo pipefail
OUT=${EX_OUT:?run through ./tinyusb-box examples}
BB() { bash "$BOXT_ROOT/tinyusb-box" bend "$@"; }
[[ -x "$BOXT_ROOT/install/bend/bin/bend" ]] || { echo "Bend not installed: ./tinyusb-box install (pins group bend)"; exit 1; }
W="$OUT/work"
prepare() { # sources + the table generated from the pinned Pico-PIO-USB
  mkdir -p "$W"; cp "$EX_DIR"/*.bend "$W/"
  python -I "$EX_DIR/gen_table.py" "$TINYUSB_DIR/hw/mcu/raspberry_pi/Pico-PIO-USB/src/usb_crc.c" "$W/table16.bend"
}
case "${1:-run}" in
  build) prepare; (cd "$W" && BB usb_crc.bend -o "$OUT/usb_crc.c") ;;   # Bend's C output (CPU program); not built here
  run) prepare; (cd "$W" && BB usb_crc.bend && BB PROOF.bend) ;;
  test)
    prepare
    out=$(cd "$W" && BB usb_crc.bend 2>&1); echo "$out" | tail -1
    [[ "$(tail -1 <<<"$out")" = "crc16_usb(123456789) = 46280" ]] || { echo "FAIL: check value"; exit 1; }
    # `bend PROOF.bend` checks types, termination and every law; ALL PROOFS CHECK or it failed
    out=$(cd "$W" && BB PROOF.bend 2>&1) || { echo "$out"; echo "FAIL: PROOF.bend"; exit 1; }
    grep -q '^ALL PROOFS CHECK' <<<"$out" || { echo "$out"; echo "FAIL: PROOF.bend not proven"; exit 1; }
    echo "PROOF.bend: ALL PROOFS CHECK"
    # negative control: one wrong table entry must make the proof fail
    mkdir -p "$OUT/bad"; cp "$W"/*.bend "$OUT/bad/"
    sed -i 's/\[0, 49345,/[0, 49346,/' "$OUT/bad/table16.bend"
    cmp -s "$W/table16.bend" "$OUT/bad/table16.bend" && { echo "FAIL: mutation changed nothing"; exit 1; }
    if (cd "$OUT/bad" && BB PROOF.bend) >"$OUT/bad.log" 2>&1; then echo "FAIL: a wrong table entry was accepted"; exit 1; fi
    grep -q 'SOME PROOFS FAIL' "$OUT/bad.log" || { cat "$OUT/bad.log"; echo "FAIL: unexpected error in the negative control"; exit 1; }
    echo "negative control (table[1] off by one) rejected"
    echo "PASS bend_usb_crc" ;;
  *) echo "usage: example.sh build|run|test" >&2; exit 2 ;;
esac
