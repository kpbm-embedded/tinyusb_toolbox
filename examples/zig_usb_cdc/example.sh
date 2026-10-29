#!/usr/bin/env bash
# about: Zig alternative: MicroZig's own USB stack, CDC echo on the Pico (32_24_microzig) - build + UF2/ELF/descriptor-string checks
# Usage (through ./tinyusb-box examples ...): example.sh build | run | test
# Needs 32_24_microzig (BOX_MICROZIG or the sibling folder): pinned Zig 0.17.0 + MicroZig 0.17.25; exit 3 (skip) when missing.
set -euo pipefail
OUT=${EX_OUT:?run through ./tinyusb-box examples}
MZ_ID=""
for d in "${BOX_MICROZIG:-}" "$BOXT_ROOT/../32_24_microzig"; do
  [[ -n "$d" ]] && [[ -x "$d/microzig-box" ]] && { MZ_ID=$(cd -P "$d" && pwd -P); break; }
done
[[ -n "$MZ_ID" ]] || { echo "skip: 32_24_microzig not found (set BOX_MICROZIG)"; exit 3; }
FW="$OUT/firmware"
build() {
  # clean environment: this launcher's pixi env (conda compiler flags) and output paths must not reach zig's
  # native build steps (regz links against libc) or microzig-box's own output selection
  (cd "$EX_DIR" && env -i HOME="$HOME" PATH=/usr/bin:/bin LANG=C.UTF-8 BOX_INTEGRATION="${BOX_INTEGRATION:-1}" \
    "$MZ_ID/microzig-box" zig build --cache-dir "$OUT/.zig-cache" --prefix "$OUT" -Doptimize=ReleaseSmall) \
    >"$OUT/zig.log" 2>&1 || { tail -30 "$OUT/zig.log"; exit 1; }
}
case "${1:-run}" in
  build) build; ls -l "$FW" ;;
  run) build; arm-none-eabi-size "$FW/zig_usb_cdc.elf"; echo "flash: hold BOOTSEL, copy $FW/zig_usb_cdc.uf2 to RPI-RP2 (or ./tinyusb-box plan raspberry_pi_pico $FW/zig_usb_cdc.elf)" ;;
  test)
    build
    grep -q UF2 <<<"$(head -c 4 "$FW/zig_usb_cdc.uf2")" || { echo "FAIL: not UF2"; exit 1; }
    # MicroZig writes no picotool binary-info block: read the first UF2 block header instead
    python -I -c 'import struct,sys; m0,m1,fl,addr,_,_,_,fam=struct.unpack("<8I",open(sys.argv[1],"rb").read(32)); sys.exit(0 if (m0,addr,fam)==(0x0A324655,0x10000000,0xE48BFF56) else 1)' \
      "$FW/zig_usb_cdc.uf2" || { echo "FAIL: first UF2 block not RP2040 family at 0x10000000"; exit 1; }
    arm-none-eabi-objcopy -O binary "$FW/zig_usb_cdc.elf" "$OUT/zig_usb_cdc.bin"
    # string descriptors are built at comptime, so they sit in flash as UTF-16LE
    python -I -c 'import sys; d=open(sys.argv[1],"rb").read(); sys.exit(0 if all(s.encode("utf-16-le") in d for s in sys.argv[2:]) else 1)' \
      "$OUT/zig_usb_cdc.bin" zig_usb_cdc BOX-ZIG-0001 || { echo "FAIL: USB string descriptors not in the image"; exit 1; }
    echo "zig_usb_cdc: $(arm-none-eabi-size "$FW/zig_usb_cdc.elf" | awk 'NR==2 {print $1+$2}') B flash (TinyUSB cdc_dual_ports on the Pico: see rust_cdc_compare)"
    echo "PASS zig_usb_cdc" ;;
  *) echo "usage: example.sh build|run|test" >&2; exit 2 ;;
esac
