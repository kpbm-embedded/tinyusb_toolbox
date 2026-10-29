#!/usr/bin/env bash
# about: HOST test: builds each device example's and template's usb_descriptors.c on the PC and lints the descriptors (no board)
# Usage (through ./tinyusb-box examples ...): example.sh build | run [src-dir ...] | test
#   run <dir>: lint your own firmware: <dir> holds usb_descriptors.c + tusb_config.h (e.g. a `new` project's src/)
# harness.c calls the descriptor callbacks with the host GCC (one MCU's config: RP2040 and STM32F4 builds both run);
# lint.py checks lengths, wTotalLength, interfaces, endpoints, IADs, strings, BOS and HID report descriptors.
set -euo pipefail
OUT=${EX_OUT:?run through ./tinyusb-box examples}
TU=${TINYUSB_DIR:?}
# TinyUSB device examples (with usb_descriptors.c) + this ID's templates
EXAMPLES="cdc_dual_ports cdc_msc cdc_uac2 dfu dfu_runtime hid_boot_interface hid_composite hid_generic_inout
hid_multiple_interface midi_test msc_dual_lun mtp printer_to_cdc uac2_headset uac2_speaker_fb usbtmc video_capture webusb_serial"
MCUS="OPT_MCU_RP2040 OPT_MCU_STM32F4"
lint_dir() { # label src-dir mcu -> 0/1
  local label=$1 src=$2 mcu=$3 exe="$OUT/bin/${1//\//_}_$3"
  mkdir -p "$OUT/bin"
  if ! cc -std=gnu11 -O0 -w -DCFG_TUSB_MCU="$mcu" -DBOARD_TUD_RHPORT=0 -DBOARD_TUH_RHPORT=1 '-D__not_in_flash(x)=' -I"$src" -I"$TU/src" -I"$TU/hw" \
      "$EX_DIR/harness.c" "$src/usb_descriptors.c" -o "$exe" >"$exe.log" 2>&1; then
    echo "FAIL $label ($mcu): harness does not compile"; tail -5 "$exe.log"; return 1
  fi
  "$exe" >"$exe.dump" || { echo "FAIL $label ($mcu): harness crashed"; return 1; }
  python -I "$EX_DIR/lint.py" --name "$label (${mcu#OPT_MCU_})" "$exe.dump"
}
all() {
  local rc=0 n=0 e t m tmp
  for e in $EXAMPLES; do for m in $MCUS; do lint_dir "device/$e" "$TU/examples/device/$e/src" "$m" || rc=1; n=$((n+1)); done; done
  tmp="$OUT/templates"; mkdir -p "$tmp"
  for t in "$BOXT_ROOT"/templates/*/src/usb_descriptors.c; do
    t=${t%/src/usb_descriptors.c}; t=${t##*/}
    [[ -d "$tmp/lint_$t" ]] || bash "$BOXT_ROOT/tinyusb-box" new "$t" "lint_$t" --dir "$tmp" >/dev/null
    for m in $MCUS; do lint_dir "template/$t" "$tmp/lint_$t/src" "$m" || rc=1; n=$((n+1)); done
  done
  echo "descriptor_lint: $n descriptor sets checked"
  return "$rc"
}
case "${1:-run}" in
  build) cc --version | head -1 ;;
  run)
    shift || true
    if [[ $# -eq 0 ]]; then all; else rc=0; for d in "$@"; do lint_dir "$(basename "$(dirname "$(realpath "$d")")")" "$(realpath "$d")" OPT_MCU_RP2040 || rc=1; done; exit "$rc"; fi ;;
  test)
    all
    # the linter must catch a broken descriptor: corrupt wTotalLength in one dump and expect a FAIL
    f="$OUT/bin/device_cdc_msc_OPT_MCU_RP2040.dump"
    sed -E 's/^(CFG 0902)..../\1ffff/' "$f" >"$f.broken"
    if python -I "$EX_DIR/lint.py" --name negative "$f.broken" >/dev/null; then echo "FAIL: lint.py accepted a wrong wTotalLength"; exit 1; fi
    echo "ok   negative check: a wrong wTotalLength is reported"
    echo "PASS descriptor_lint" ;;
  *) echo "usage: example.sh build|run [src-dir ...]|test" >&2; exit 2 ;;
esac
