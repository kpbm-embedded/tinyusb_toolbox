#!/usr/bin/env bash
# about: Rust alternative: embassy-usb CDC-ACM (32_17_embedded_rust usb_cdc_app) vs TinyUSB cdc_dual_ports on the Pico - size table (build only)
# Usage (through ./tinyusb-box examples ...): example.sh build | run | test
# Needs 32_17_embedded_rust (BOX_EMBEDDED_RUST or the sibling folder): its pinned Rust + embassy; exit 3 (skip) when missing.
# The Rust app is created with `rust-box new usb_cdc_app` in this example's output folder and built there.
set -euo pipefail
OUT=${EX_OUT:?run through ./tinyusb-box examples}
RUST_ID=""
for d in "${BOX_EMBEDDED_RUST:-}" "$BOXT_ROOT/../32_17_embedded_rust"; do
  [[ -n "$d" ]] && [[ -x "$d/rust-box" ]] && { RUST_ID=$(cd -P "$d" && pwd -P); break; }
done
[[ -n "$RUST_ID" ]] || { echo "skip: 32_17_embedded_rust not found (set BOX_EMBEDDED_RUST)"; exit 3; }
RB="$RUST_ID/rust-box"
APP="$OUT/rust/tu_rust_cdc"
ELF_RS="$OUT/cargo-target/thumbv6m-none-eabi/release/tu_rust_cdc"
ELF_TU="$OUT/tinyusb/cdc_dual_ports.elf"
build() {
  [[ -d "$APP" ]] || "$RB" new usb_cdc_app tu_rust_cdc --dir "$OUT/rust" >/dev/null
  RUST_BOX_TARGET_DIR="$OUT/cargo-target" "$RB" run bash -c "cd '$APP' && cargo build --release --offline 2>/dev/null || cargo build --release" \
    >"$OUT/cargo.log" 2>&1 || { tail -30 "$OUT/cargo.log"; exit 1; }
  cmake -S "$TINYUSB_DIR/examples/device/cdc_dual_ports" -B "$OUT/tinyusb" -G Ninja -DBOARD=raspberry_pi_pico \
    -DCMAKE_BUILD_TYPE=MinSizeRel -Wno-dev >"$OUT/cmake.log" 2>&1 || { tail -30 "$OUT/cmake.log"; exit 1; }
  cmake --build "$OUT/tinyusb" -j "${BOXT_JOBS:-4}" >"$OUT/ninja.log" 2>&1 || { tail -30 "$OUT/ninja.log"; exit 1; }
}
row() { arm-none-eabi-size "$2" | awk -v n="$1" 'NR==2 {printf "  %-34s flash %7d B  RAM %6d B\n", n, $1+$2, $2+$3}'; }
table() {
  echo "Pico (RP2040), USB CDC-ACM device, release builds:"
  row "TinyUSB 0.21 C (2x CDC, no RTOS)" "$ELF_TU"
  row "embassy-usb Rust (1x CDC, async)" "$ELF_RS"
  echo "  (Rust image includes defmt-rtt logging and the embassy executor; TinyUSB includes the BSP and 2 ports)"
}
case "${1:-run}" in
  build) build ;;
  run) build; table ;;
  test)
    build; table | tee "$OUT/sizes.txt"
    for f in "$ELF_TU" "$ELF_RS"; do
      [[ -s "$f" ]] || { echo "FAIL: no $f"; exit 1; }
      e=$(arm-none-eabi-readelf -h "$f" | awk '/Entry point/ {print $4}')
      [[ $((e)) -ge $((0x10000000)) ]] && [[ $((e)) -lt $((0x10200000)) ]] || { echo "FAIL: $f entry $e not in XIP flash"; exit 1; }
    done
    grep -q 'USBCTRL_IRQ' <<<"$(arm-none-eabi-nm "$ELF_RS")" || { echo "FAIL: embassy-usb IRQ handler not linked"; exit 1; }
    grep -q ' T tud_cdc_n_write$' <<<"$(arm-none-eabi-nm "$ELF_TU")" || { echo "FAIL: TinyUSB CDC not linked"; exit 1; }
    echo "PASS rust_cdc_compare" ;;
  *) echo "usage: example.sh build|run|test" >&2; exit 2 ;;
esac
