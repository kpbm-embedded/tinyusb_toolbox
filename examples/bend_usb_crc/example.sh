#!/usr/bin/env bash
# about: Bend 2 laws + proofs: Pico-PIO-USB's CRC-16 table = bitwise USB CRC for all 256 bytes, check value, streaming law (host only; needs 32_31_bend)
# Usage (through ./tinyusb-box examples ...): example.sh build | run | test
# Bend runs on the PC only (no MCU support claimed): it checks the table the dual_pio_host firmware ships.
# bend-box is found via BOX_BEND or the sibling folder 32_31_bend; without it the example exits 3 (skip).
set -euo pipefail
OUT=${EX_OUT:?run through ./tinyusb-box examples}
BEND_ID=""
for d in "${BOX_BEND:-}" "$BOXT_ROOT/../32_31_bend"; do
  [[ -n "$d" ]] && [[ -x "$d/bend-box" ]] && { BEND_ID=$(cd -P "$d" && pwd -P); break; }
done
[[ -n "$BEND_ID" ]] || { echo "skip: 32_31_bend (bend-box) not found (set BOX_BEND); this ID does not download Bend"; exit 3; }
BB() { env -i HOME="$HOME" PATH=/usr/bin:/bin LANG=C.UTF-8 BOX_INTEGRATION="${BOX_INTEGRATION:-1}" "$BEND_ID/bend-box" "$@"; }
W="$OUT/work"
prepare() { # sources + the table generated from the pinned Pico-PIO-USB
  mkdir -p "$W"; cp "$EX_DIR"/*.bend "$W/"
  python -I "$EX_DIR/gen_table.py" "$TINYUSB_DIR/hw/mcu/raspberry_pi/Pico-PIO-USB/src/usb_crc.c" "$W/table16.bend"
}
case "${1:-run}" in
  build) prepare; BB build "$W/usb_crc.bend" -o "$OUT/usb_crc.c" ;;
  run) prepare; BB bend "$W/usb_crc.bend"; BB check "$W/PROOF.bend" ;;
  test)
    prepare
    out=$(BB bend "$W/usb_crc.bend" 2>&1); echo "$out" | tail -1
    [[ "$(tail -1 <<<"$out")" = "crc16_usb(123456789) = 46280" ]] || { echo "FAIL: check value"; exit 1; }
    BB check "$W/PROOF.bend" || { echo "FAIL: PROOF.bend"; exit 1; }
    BB verdict "$W/PROOF.bend" >"$OUT/verdict.log" 2>&1 || { cat "$OUT/verdict.log"; echo "FAIL: verdict"; exit 1; }
    echo "verdict: $(grep -m1 'PROOFS' "$OUT/verdict.log")"
    # negative control: one wrong table entry must make the proof fail
    mkdir -p "$OUT/bad"; cp "$W"/*.bend "$OUT/bad/"
    sed -i 's/\[0, 49345,/[0, 49346,/' "$OUT/bad/table16.bend"
    cmp -s "$W/table16.bend" "$OUT/bad/table16.bend" && { echo "FAIL: mutation changed nothing"; exit 1; }
    if BB check "$OUT/bad/PROOF.bend" >"$OUT/bad.log" 2>&1; then echo "FAIL: a wrong table entry was accepted"; exit 1; fi
    grep -q 'SOME PROOFS FAIL' "$OUT/bad.log" || { cat "$OUT/bad.log"; echo "FAIL: unexpected error in the negative control"; exit 1; }
    echo "negative control (table[1] off by one) rejected"
    echo "PASS bend_usb_crc" ;;
  *) echo "usage: example.sh build|run|test" >&2; exit 2 ;;
esac
