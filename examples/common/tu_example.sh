# shellcheck shell=bash
# tu_example.sh: sourced by examples/<ex>/example.sh with TU_EX=<TinyUSB example path> set.
# Optional: TU_BOARDS (default BlackPill + Pico), TU_SYMS (task symbols that must be linked; default
# tud_task_ext, host examples: tuh_task_ext), TU_VID=0 for host-only images (no device descriptor).
# build: TinyUSB's own CMake example, out of tree, for each board ($EX_OUT/<board>/)
# run:   prints the flash plan (never flashes)        test: build + artifact checks
set -euo pipefail
OUT=${EX_OUT:?run through ./tinyusb-box examples}
: "${TU_EX:?}" "${TU_BOARDS:=stm32f411blackpill raspberry_pi_pico}" "${TU_SYMS:=tud_task_ext}" "${TU_VID:=1}"
name=${TU_EX##*/}
build() {
  local b
  for b in $TU_BOARDS; do
    cmake -S "${TINYUSB_DIR:?}/examples/$TU_EX" -B "$OUT/$b" -G Ninja -DBOARD="$b" -DCMAKE_BUILD_TYPE=MinSizeRel -Wno-dev \
      >"$OUT/$b.cmake.log" 2>&1 || { tail -30 "$OUT/$b.cmake.log"; exit 1; }
    cmake --build "$OUT/$b" -j "${BOXT_JOBS:-4}" >"$OUT/$b.build.log" 2>&1 || { tail -30 "$OUT/$b.build.log"; exit 1; }
    echo "built $b: $(arm-none-eabi-size "$OUT/$b/$name.elf" | tail -1 | awk '{print "text " $1 " B, data " $2 " B, bss " $3 " B"}')"
  done
}
flash_of() { # board -> "flash-size first-address" (the user's boards; nRF: whole flash, the UF2 bootloader sits above the app)
  case "$1" in
    stm32f411blackpill) echo "$((512*1024)) 0x08000000" ;;
    stm32g474nucleo)    echo "$((512*1024)) 0x08000000" ;;   # same family as the WeAct G431 (128 KB there)
    stm32h563nucleo)    echo "$((2048*1024)) 0x08000000" ;;  # WeAct H562 has 2 MB too
    stm32h743_weact)    echo "$((2048*1024)) 0x08000000" ;;
    raspberry_pi_pico)  echo "$((2048*1024)) 0x10000000" ;;
    raspberry_pi_pico2) echo "$((4096*1024)) 0x10000000" ;;
    feather_nrf52840_express) echo "$((1024*1024)) 0x00000000" ;;
    *) echo "0 0" ;;
  esac
}
check() { # board: artifacts exist, fit the chip, link the USB task(s), carry VID 0xCafe, start in flash
  local b=$1 elf="$OUT/$1/$name.elf" text flash base s entry nm
  [[ -s "$elf" ]] || { echo "FAIL $b: no $elf"; return 1; }
  read -r flash base <<<"$(flash_of "$b")"
  text=$(arm-none-eabi-size "$elf" | awk 'NR==2 {print $1 + $2}')
  [[ "$flash" -gt 0 ]] && [[ "$text" -lt "$flash" ]] || { echo "FAIL $b: $text B > flash $flash B (or unknown board)"; return 1; }
  nm=$(arm-none-eabi-nm "$elf")
  for s in $TU_SYMS; do grep -q " T $s\$" <<<"$nm" || { echo "FAIL $b: $s missing"; return 1; }; done
  # device descriptor: bLength 0x12, bDescriptorType 0x01, ..., idVendor 0xCafe (little endian fe ca)
  if [[ "$TU_VID" = 1 ]]; then
    [[ -s "$OUT/$b/$name.bin" ]] || arm-none-eabi-objcopy -O binary "$elf" "$OUT/$b/$name.bin"   # nrf builds: hex/uf2 only
    python -I -c 'import sys; d=open(sys.argv[1],"rb").read(); sys.exit(0 if b"\xfe\xca" in d else 1)' "$OUT/$b/$name.bin" \
      || { echo "FAIL $b: VID 0xcafe not in $name.bin"; return 1; }
  fi
  entry=$(arm-none-eabi-readelf -h "$elf" | awk '/Entry point/ {print $4}')
  [[ $((entry)) -ge $((base)) ]] && [[ $((entry)) -lt $((base + flash)) ]] || { echo "FAIL $b: entry $entry not in flash"; return 1; }
  case "$b" in
    raspberry_pi_pico*)
      [[ -s "$OUT/$b/$name.uf2" ]] || { echo "FAIL $b: no uf2"; return 1; }
      picotool info -a "$OUT/$b/$name.uf2" >"$OUT/$b.picotool-info.txt" 2>&1 || { cat "$OUT/$b.picotool-info.txt"; return 1; }
      grep -q 'binary start:.*0x10000000' "$OUT/$b.picotool-info.txt" || { echo "FAIL $b: uf2 not at XIP 0x10000000"; return 1; }
      echo "ok   $b: $name.uf2 ($(du -k "$OUT/$b/$name.uf2" | cut -f1) KB), $text B flash, picotool: $(grep -m1 'name:' "$OUT/$b.picotool-info.txt" | xargs)" ;;
    feather_nrf52840_express)   # nice!nano / Pro Micro nRF52840 use the same Adafruit UF2 bootloader + S140 layout
      arm-none-eabi-objcopy -O ihex "$elf" "$OUT/$b/$name.hex"
      python -I "$TINYUSB_DIR/tools/uf2/utils/uf2conv.py" -f 0xADA52840 -c -o "$OUT/$b/$name.uf2" "$OUT/$b/$name.hex" >"$OUT/$b.uf2conv.log" 2>&1 \
        || { cat "$OUT/$b.uf2conv.log"; return 1; }
      python -I -c 'import struct,sys; d=open(sys.argv[1],"rb").read(512); m0,m1,fl,addr,_,_,_,fam=struct.unpack("<8I",d[:32]); sys.exit(0 if m0==0x0A324655 and fam==0xADA52840 and addr>=0x26000 else 1)' "$OUT/$b/$name.uf2" \
        || { echo "FAIL $b: UF2 header (magic, family 0xADA52840, address >= 0x26000)"; return 1; }
      echo "ok   $b: $name.elf $text B flash, entry $entry (after the S140 SoftDevice area), UF2 family 0xADA52840" ;;
    *) echo "ok   $b: $name.elf $text B flash of $((flash/1024)) KB, entry $entry" ;;
  esac
}
act=${1:-run}
case "$act" in
  build) build ;;
  run)
    build
    for b in $TU_BOARDS; do
      bash "$BOXT_ROOT/tinyusb-box" plan "$b" "$OUT/$b/$name.elf"; echo
    done ;;
  test)
    build
    rc=0; for b in $TU_BOARDS; do check "$b" || rc=1; done
    [[ "$rc" = 0 ]] && echo "PASS $name ($TU_BOARDS)"; exit "$rc" ;;
  *) echo "usage: example.sh build|run|test" >&2; exit 2 ;;
esac
