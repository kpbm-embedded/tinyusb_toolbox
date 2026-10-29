# shellcheck shell=bash disable=SC2015,SC2034  # d_* return 0; TOOL_* are read by boxtool.bash
# tinyusb-box: tool part (hooks for lib/boxtool.bash). TinyUSB (USB device/host stack) built with
# its own CMake examples for the BlackPill (stm32f411blackpill) and the Pico (raspberry_pi_pico),
# using a pinned xPack arm-none-eabi-gcc, the ST/CMSIS deps TinyUSB's get_deps.py would clone
# (same commits, as pinned archives), pico-sdk + prebuilt picotool/pioasm. Ceedling (Ruby gem,
# GEM_HOME inside the ID) runs TinyUSB's host unit tests. Never flashes: `plan` prints commands.
pin_ver() { sed -n "s/^$1\t\([^\t]*\)\t.*/\1/p" "${BOXT_ROOT:?}/config/pins.tsv" | head -1; }
TOOL_TITLE="32_21_tinyusb: TinyUSB $(pin_ver tinyusb) + arm-none-eabi-gcc $(pin_ver arm-none-eabi-gcc) + pico-sdk $(pin_ver pico-sdk)"
TOOL_INSTALL_WHAT="Ceedling gem + the example firmware build (examples build)"
CEEDLING_VERSION=1.0.1   # TinyUSB test/unit-test/project.yml asks for >= 1.0.0
TOOL_HELP_USE="  boards                  the boards the examples build for (+ every TinyUSB board name: boards --all)
  build <example> <board> [--dir D]   build any TinyUSB example (examples/device|host|dual/...) for a board
  unit-test [test]        TinyUSB's host unit tests (Ceedling gem + the env's host GCC), e.g. unit-test test_fifo
  list                    read-only: USB devices now attached that matter here (TinyUSB 0xcafe, Pico BOOTSEL,
                          STM32 DFU, CMSIS-DAP/ST-Link probes)
  plan <board> <fw.elf|.uf2|.bin>   PRINT the flash commands (picotool/dfu-util/openocd); runs nothing
  udev                    print the udev rules file path + the sudo commands to install it"
hook_help() { # printed after boxtool's help: tool-specific examples and environment
  cat <<EOF

tool examples
  ./$BOXT_NAME build device/midi_test raspberry_pi_pico   any TinyUSB example for a board
  ./$BOXT_NAME unit-test test_fifo                        one Ceedling test file
  ./$BOXT_NAME plan stm32f411blackpill fw.elf             print (never run) the flash commands
tool environment
  set inside: TINYUSB_DIR, PICO_SDK_PATH, picotool_DIR, pioasm_DIR, PICO_TOOLCHAIN_PATH,
  GEM_HOME/GEM_PATH (Ceedling gems in cache/gems), XDG_CACHE_HOME (cache/xdg-cache)
EOF
}
# shellcheck source-path=SCRIPTDIR source=boxtool.bash
. "$BOXT_ROOT/lib/boxtool.bash"

# TinyUSB dependency layout: <path inside the TinyUSB tree> <pin name> (what tools/get_deps.py clones)
TU_DEPS="hw/mcu/st/cmsis_device_f4 cmsis_device_f4
hw/mcu/st/stm32f4xx_hal_driver stm32f4xx_hal_driver
lib/CMSIS_5 cmsis_5
tools/linkermap linkermap
tools/uf2 uf2
hw/mcu/nordic/nrfx nrfx
hw/mcu/st/cmsis_device_g4 cmsis_device_g4
hw/mcu/st/stm32g4xx_hal_driver stm32g4xx_hal_driver
hw/mcu/st/cmsis_device_h7 cmsis_device_h7
hw/mcu/st/stm32h7xx_hal_driver stm32h7xx_hal_driver
hw/mcu/st/cmsis_device_h5 cmsis_device_h5
hw/mcu/st/stm32h5xx_hal_driver stm32h5xx_hal_driver
hw/mcu/st/stm32-tcpp0203 stm32_tcpp0203
hw/mcu/raspberry_pi/Pico-PIO-USB pico_pio_usb"
EX_BOARDS="stm32f411blackpill raspberry_pi_pico"
GEMS="$ROOT/cache/gems"

hook_env() {
  local p
  for p in "$GEMS/bin" "$INST/pico-sdk-tools/pioasm" "$INST/picotool/picotool" "$INST/arm-none-eabi-gcc/bin"; do
    [[ -d "$p" ]] && PATH="$p:$PATH"
  done
  export PATH TINYUSB_BOX_ROOT="$ROOT" TINYUSB_DIR="$INST/tinyusb" PICO_SDK_PATH="$INST/pico-sdk"
  export picotool_DIR="$INST/picotool/picotool" pioasm_DIR="$INST/pico-sdk-tools/pioasm"
  export PICO_TOOLCHAIN_PATH="$INST/arm-none-eabi-gcc/bin"
  # Ruby gems (Ceedling) inside the ID, never ~/.gem / ~/.local/share/gem
  export GEM_HOME="$GEMS" GEM_PATH="$GEMS" GEM_SPEC_CACHE="$ROOT/cache/gem-specs" XDG_CACHE_HOME="$ROOT/cache/xdg-cache"
}

link_deps() { # relative symlinks: TinyUSB tree -> install/<dep> (inside this ID)
  local rel pin dst up d
  while read -r rel pin; do
    dst="$INST/tinyusb/$rel"
    [[ -e "$INST/$pin" ]] || { warn "$pin not installed"; continue; }
    [[ -L "$dst" ]] && [[ -e "$dst" ]] && continue
    d=${rel%/*} up=..                                    # hw/mcu/st -> ../../..
    while [[ $d == */* ]]; do up="../$up"; d=${d#*/}; done
    run mkdir -p "$(dirname "$dst")"
    run ln -sfn "../$up/$pin" "$dst"
  done <<<"$TU_DEPS"
}

hook_bootstrap() {
  cachedir_tag "$ROOT/cache"
  [[ -e "$INST/tinyusb" ]] || [[ "$DRY" = 1 ]] || return 0
  link_deps
}

install_ceedling() {
  if [[ -x "$GEMS/bin/ceedling" ]] && "$GEMS/bin/ceedling" version 2>/dev/null | grep "Ceedling => $CEEDLING_VERSION" >/dev/null; then return 0; fi
  info "installing the ceedling $CEEDLING_VERSION gem into cache/gems (rubygems.org, pinned version)"
  run timeout "$NET_TIMEOUT" gem install --no-document --install-dir "$GEMS" --bindir "$GEMS/bin" "ceedling:$CEEDLING_VERSION"
}

hook_install() { # demos-flag
  activate
  install_ceedling
  info "building the example firmware (examples build)"
  cmd_examples build
}

hook_status() {
  local e n=0
  for e in $(ex_list); do [[ -d "$BUILD/examples/$e" ]] && n=$((n+1)); done
  printf '  %-22s %s of %s built in %s\n' examples "$n" "$(ex_list | wc -l)" "$BUILD/examples"
  printf '  %-22s %s\n' ceedling "$([[ -x "$GEMS/bin/ceedling" ]] && echo "$CEEDLING_VERSION (cache/gems)" || echo 'not installed (install)')"
}

hook_doctor() {
  local v rel pin
  v=$(arm-none-eabi-gcc --version 2>/dev/null | head -1) && d_ok "$v" || d_fail "arm-none-eabi-gcc missing"
  [[ "$(command -v arm-none-eabi-gcc)" = "$INST/arm-none-eabi-gcc/bin/arm-none-eabi-gcc" ]] && d_ok "arm-none-eabi-gcc is the pinned xPack copy" || d_fail "arm-none-eabi-gcc is not the pinned copy: $(command -v arm-none-eabi-gcc)"
  [[ -r "$INST/tinyusb/src/tusb.h" ]] && d_ok "TinyUSB $(pin_ver tinyusb) sources" || d_fail "TinyUSB sources missing"
  while read -r rel pin; do
    [[ -e "$INST/tinyusb/$rel/." ]] && d_ok "dep $rel -> $pin $(pin_ver "$pin")" || d_fail "dep $rel missing (./$NAME bootstrap)"
  done <<<"$TU_DEPS"
  [[ -r "$PICO_SDK_PATH/pico_sdk_init.cmake" ]] && d_ok "pico-sdk $(pin_ver pico-sdk) (PICO_SDK_PATH)" || d_fail "pico-sdk missing"
  v=$(picotool version 2>/dev/null | head -1) && d_ok "$v (prebuilt, picotool_DIR)" || d_fail "picotool not runnable"
  v=$(pioasm --version 2>/dev/null | head -1); [[ -x "$INST/pico-sdk-tools/pioasm/pioasm" ]] && d_ok "pioasm ${v:-present} (prebuilt, pioasm_DIR)" || d_fail "pioasm missing"
  v=$(cmake --version 2>/dev/null | head -1) && d_ok "$v" || d_fail "cmake missing"
  v=$(ninja --version 2>/dev/null) && d_ok "ninja $v" || d_fail "ninja missing"
  v=$(ruby --version 2>/dev/null | cut -d' ' -f1-2) && d_ok "$v (env)" || d_fail "ruby missing in the env"
  if [[ -x "$GEMS/bin/ceedling" ]]; then d_ok "ceedling $CEEDLING_VERSION (cache/gems)"; else d_warn "ceedling not installed (./$NAME install)"; fi
  [[ -r "$ROOT/config/99-tinyusb-box.rules" ]] && d_ok "udev rules file in config/ (install by hand: ./$NAME udev)" || d_warn "udev rules file missing"
}

hook_native_bins() {
  echo "arm-none-eabi-gcc install/arm-none-eabi-gcc/bin/arm-none-eabi-gcc"
  echo "arm-none-eabi-size install/arm-none-eabi-gcc/bin/arm-none-eabi-size"
  echo "arm-none-eabi-objcopy install/arm-none-eabi-gcc/bin/arm-none-eabi-objcopy"
  echo "picotool install/picotool/picotool/picotool"
  echo "tinyusb-build @build"
  echo "tinyusb-plan @plan"
}

tool_cmd_boards() {
  echo "example boards: $EX_BOARDS"
  echo "  stm32f411blackpill  BlackPill STM32F411CE (family stm32f4, USB OTG FS, DFU bootloader in ROM)"
  echo "  raspberry_pi_pico   Raspberry Pi Pico (family rp2040, BOOTSEL UF2 bootloader in ROM)"
  echo "also built by examples/board_matrix (deps pinned): raspberry_pi_pico2 (RP2350), feather_nrf52840_express"
  echo "  (nice!nano / Pro Micro nRF52840: same UF2 bootloader + S140 layout), stm32g474nucleo (WeAct G431 family),"
  echo "  stm32h743_weact, stm32h563nucleo (WeAct H562 family). ESP32-S3 needs ESP-IDF: not part of this ID."
  if [[ "${1:-}" = --all ]]; then
    echo "all TinyUSB boards (hw/bsp/<family>/boards/<board>; only stm32f4 + rp2040 deps are installed):"
    find "$INST/tinyusb/hw/bsp" -mindepth 3 -maxdepth 3 -path '*/boards/*' -type d -printf '  %P\n' 2>/dev/null | sed 's#/boards/# #' | sort | column -c 120
  fi
}

# build <example> <board> [--dir D]: CMake configure + build of a TinyUSB example out of tree.
tu_build() { # example-rel-path board build-dir
  local tex=$1 board=$2 bdir=$3 src
  src="$INST/tinyusb/examples/$tex"
  [[ -r "$src/CMakeLists.txt" ]] || usage_error "no TinyUSB example $tex (examples/device|host|dual/<name>)"
  run cmake -S "$src" -B "$bdir" -G Ninja -DBOARD="$board" -DCMAKE_BUILD_TYPE=MinSizeRel -Wno-dev
  run cmake --build "$bdir" -j "$JOBS"
}
tool_cmd_build() {
  [[ $# -ge 2 ]] || usage_error "usage: ./$NAME build <example e.g. device/cdc_msc> <board> [--dir D]"
  local tex=$1 board=$2 dir=""; shift 2
  [[ "${1:-}" = --dir ]] && dir=${2:?--dir needs a path}
  tex=${tex#examples/}
  activate
  dir=${dir:-$BUILD/tu/${tex//\//_}/$board}
  wait_for_ram
  tu_build "$tex" "$board" "$dir"
  [[ "$DRY" = 1 ]] || { info "output in $dir:"; find "$dir" -maxdepth 1 -name '*.elf' -o -maxdepth 1 -name '*.uf2' -o -maxdepth 1 -name '*.bin' -o -maxdepth 1 -name '*.hex' | sed 's/^/  /'; }
}

# unit-test: Ceedling on a copy of TinyUSB's test/unit-test (Ceedling writes _build next to
# project.yml, so the tree is copied to $BUILD/unit-test; src/ is referenced through a symlink).
tool_cmd_unit-test() {
  activate
  local w="$BUILD/unit-test" t=${1:-all}
  [[ -x "$GEMS/bin/ceedling" ]] || [[ "$DRY" = 1 ]] || die "ceedling not installed: ./$NAME install"
  if [[ "$DRY" = 1 ]]; then printf '+ copy test/unit-test -> %s; ceedling test:%s\n' "$w" "$t"; return 0; fi
  mkdir -p "$w/test"
  cp -R "$INST/tinyusb/test/unit-test/." "$w/test/unit-test/"
  ln -sfn "$INST/tinyusb/src" "$w/src"
  ln -sfn "$INST/tinyusb/lib" "$w/lib"
  ln -sfn "$INST/tinyusb/hw" "$w/hw"
  cd "$w/test/unit-test" && timeout 1800 ceedling "test:$t"
}

# list: read-only USB enumeration from sysfs (no lsusb needed, nothing written)
tool_cmd_list() {
  local d vid pid prod man found=0
  for d in /sys/bus/usb/devices/*; do
    [[ -r "$d/idVendor" ]] || continue
    vid=$(cat "$d/idVendor"); pid=$(cat "$d/idProduct")
    prod=$(cat "$d/product" 2>/dev/null || true); man=$(cat "$d/manufacturer" 2>/dev/null || true)
    case "$vid:$pid" in
      cafe:*) what="TinyUSB example firmware" ;;
      2e8a:0003|2e8a:000f) what="Raspberry Pi RP2040/RP2350 BOOTSEL (UF2 drive + picotool)" ;;
      0d28:0204|2e8a:000c) what="CMSIS-DAP probe" ;;
      2e8a:*) what="Raspberry Pi device" ;;
      0483:df11) what="STM32 ROM DFU bootloader (BlackPill: hold BOOT0, tap NRST)" ;;
      0483:374*|0483:375*) what="ST-Link probe" ;;
      *) continue ;;
    esac
    found=1
    printf '  %s:%s  %-60s %s %s (%s)\n' "$vid" "$pid" "$what" "$man" "$prod" "${d##*/}"
  done
  [[ "$found" = 1 ]] || echo "  (no TinyUSB / Pico / STM32 DFU / probe device attached)"
}

# plan <board> <file>: PRINT the commands that would flash the file. Runs nothing.
tool_cmd_plan() {
  local b=${1:-} fw=${2:-}
  [[ -n "$b" ]] && [[ -n "$fw" ]] || usage_error "usage: ./$NAME plan <board, see boards> <firmware.elf|.uf2|.bin>"
  local base=${fw%.*}
  echo "# flash plan for $b: PRINTED ONLY, nothing was run. Check the file, then copy-paste."
  case "$b" in
    raspberry_pi_pico|pico)
      echo "# 1. hold BOOTSEL while plugging the Pico in (it shows as RPI-RP2, 2e8a:0003)"
      echo "picotool info"
      echo "picotool load -v -x '${base}.uf2'        # or: cp '${base}.uf2' /run/media/\$USER/RPI-RP2/"
      echo "# with a debug probe instead (CMSIS-DAP / Picoprobe):"
      echo "openocd -f interface/cmsis-dap.cfg -f target/rp2040.cfg -c 'adapter speed 5000' -c \"program ${base}.elf verify reset exit\"" ;;
    stm32f411blackpill|blackpill)
      echo "# A. ROM DFU bootloader: hold BOOT0, tap NRST, release BOOT0 (shows as 0483:df11)"
      echo "dfu-util -a 0 -s 0x08000000:leave -D '${base}.bin'"
      echo "# B. ST-Link / CMSIS-DAP probe on SWD:"
      echo "openocd -f interface/stlink.cfg -f target/stm32f4x.cfg -c \"program ${base}.elf verify reset exit\""
      echo "probe-rs download --chip STM32F411CEUx '${base}.elf'" ;;
    raspberry_pi_pico2|pico2)
      echo "# 1. hold BOOTSEL while plugging the Pico 2 in (RP2350, shows as RP2350, 2e8a:000f)"
      echo "picotool load -v -x '${base}.uf2'        # or copy the .uf2 to the RP2350 drive" ;;
    feather_nrf52840_express|nicenano|promicro_nrf52840)
      echo "# Adafruit UF2 bootloader (nice!nano, Pro Micro nRF52840, Feather): double-tap reset, a drive appears"
      echo "cp '${base}.uf2' /run/media/\$USER/NICENANO/     # drive name differs per board (FTHR840BOOT, ...)"
      echo "# with an SWD probe instead (keeps the SoftDevice area untouched):"
      echo "probe-rs download --chip nRF52840_xxAA '${base}.elf'" ;;
    stm32g474nucleo|stm32h743_weact|stm32h563nucleo|weact_g431|weact_h743|weact_h562)
      local chip; case "$b" in stm32g474nucleo|weact_g431) chip=STM32G431CBUx ;; stm32h743_weact|weact_h743) chip=STM32H743VITx ;; *) chip=STM32H562RGTx ;; esac
      echo "# A. ROM DFU bootloader: hold BOOT0, tap reset (0483:df11)"
      echo "dfu-util -a 0 -s 0x08000000:leave -D '${base}.bin'"
      echo "# B. SWD probe (chip name for the WeAct board; the build used the TinyUSB board $b):"
      echo "probe-rs download --chip $chip '${base}.elf'" ;;
    *) usage_error "unknown board $b (stm32f411blackpill | raspberry_pi_pico | raspberry_pi_pico2 | feather_nrf52840_express | stm32g474nucleo | stm32h743_weact | stm32h563nucleo)" ;;
  esac
  echo "# then: ./$NAME list   (the example enumerates as cafe:4xxx)"
}

tool_cmd_udev() {
  echo "# udev rules for TinyUSB examples (VID 0xcafe), Pico BOOTSEL/picotool, STM32 DFU: $ROOT/config/99-tinyusb-box.rules"
  echo "# not installed by $NAME (needs root). To install, run yourself:"
  echo "sudo cp '$ROOT/config/99-tinyusb-box.rules' /etc/udev/rules.d/"
  echo "sudo udevadm control --reload-rules && sudo udevadm trigger"
}

boxt_main "$@"
