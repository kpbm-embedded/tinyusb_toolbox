#!/usr/bin/env bash
# shellcheck disable=SC2015  # "a && ok || bad" chains are intended
# Smoke test of the installed tinyusb-box: the pinned compilers/tools run, every template
# builds for its boards (BlackPill and/or Pico) in a temp dir, one TinyUSB unit test runs, plan prints.
# Usage: tests/test_smoke.sh
set -uo pipefail   # no -e: every check runs and failures are counted
HERE=$(cd "$(dirname "$0")/.." && pwd -P)
B="$HERE/tinyusb-box"
pass=0; failn=0
ok()  { printf 'ok    %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL  %s\n' "$*"; failn=$((failn+1)); }
tmp=$(mktemp -d)
cleanup() { if command -v trash-put >/dev/null; then trash-put "$tmp"; fi; }   # own temp dir; never rm
trap cleanup EXIT

v=$("$B" run arm-none-eabi-gcc --version 2>&1 | head -1); grep -q 'xPack GNU Arm Embedded GCC' <<<"$v" && ok "$v" || bad "arm-none-eabi-gcc: $v"
v=$("$B" run picotool version 2>&1 | head -1); grep -q '^picotool v2' <<<"$v" && ok "$v" || bad "picotool: $v"
v=$("$B" run cmake --version 2>&1 | head -1); grep -q 'cmake version' <<<"$v" && ok "$v" || bad "cmake: $v"
# every template: instantiate with `new`, build for its boards, the name must be in the image (product string)
TEMPLATE_BOARDS="device_cdc:stm32f411blackpill,raspberry_pi_pico
device_hid:stm32f411blackpill,raspberry_pi_pico
device_hid_generic:stm32f411blackpill,raspberry_pi_pico
device_msc:stm32f411blackpill,raspberry_pi_pico
device_midi:stm32f411blackpill,raspberry_pi_pico
device_webusb:stm32f411blackpill,raspberry_pi_pico
device_dfu:stm32f411blackpill,raspberry_pi_pico
device_dfu_runtime:stm32f411blackpill,raspberry_pi_pico
device_audio:stm32f411blackpill,raspberry_pi_pico
device_uvc:stm32f411blackpill,raspberry_pi_pico
device_usbtmc:stm32f411blackpill,raspberry_pi_pico
device_composite:stm32f411blackpill,raspberry_pi_pico
host_cdc_msc_hid:raspberry_pi_pico,stm32f411blackpill
dual_pio_host:raspberry_pi_pico
rust_usb_hid:rust
zig_usb_cdc:zig"
[[ $(wc -l <<<"$TEMPLATE_BOARDS") -eq $(find "$HERE/templates" -mindepth 1 -maxdepth 1 -type d | wc -l) ]] \
  && ok "every template is in the smoke list" || bad "templates/ and the smoke list differ"
while IFS=: read -r kind boards; do
  nm="smoke_${kind}"
  if ! "$B" new "$kind" "$nm" --dir "$tmp" >/dev/null 2>&1; then bad "tinyusb-box new $kind"; continue; fi
  if [[ "$boards" = rust ]]; then   # embassy-usb template: built with 32_17_embedded_rust's pinned Rust
    rb=""; for d in "${BOX_EMBEDDED_RUST:-}" "$HERE/../32_17_embedded_rust"; do [[ -n "$d" ]] && [[ -x "$d/rust-box" ]] && { rb="$d/rust-box"; break; }; done
    if [[ -z "$rb" ]]; then printf 'skip  template %s: 32_17_embedded_rust not found (BOX_EMBEDDED_RUST)\n' "$kind"; continue; fi
    tgt="$("$B" where | awk '$1=="build" {print $2}')/smoke-cargo-target"   # reused between runs, regenerable
    out=$(RUST_BOX_TARGET_DIR="$tgt" "$rb" run bash -c "cd '$tmp/$nm' && { cargo build --release --offline || cargo build --release; }" 2>&1)
    elf="$tgt/thumbv6m-none-eabi/release/$nm"
    [[ -s "$elf" ]] && grep -qaF "$nm" "$elf" && ok "template $kind: Pico via rust-box ($("$B" run arm-none-eabi-size "$elf" | awk 'NR==2 {print $1+$2}') B flash, name in image)" \
      || { bad "template $kind"; tail -8 <<<"$out" | sed 's/^/      /'; }
    continue
  fi
  if [[ "$boards" = zig ]]; then   # MicroZig template: built with 32_24_microzig's pinned Zig (clean environment)
    mz=""; for d in "${BOX_MICROZIG:-}" "$HERE/../32_24_microzig"; do [[ -n "$d" ]] && [[ -x "$d/microzig-box" ]] && { mz="$d/microzig-box"; break; }; done
    if [[ -z "$mz" ]]; then printf 'skip  template %s: 32_24_microzig not found (BOX_MICROZIG)\n' "$kind"; continue; fi
    zc="$("$B" where | awk '$1=="build" {print $2}')/smoke-zig-cache"
    out=$(cd "$tmp/$nm" && env -i HOME="$HOME" PATH=/usr/bin:/bin LANG=C.UTF-8 "$mz" zig build --cache-dir "$zc" --prefix "$tmp/$nm/zig-out" -Doptimize=ReleaseSmall 2>&1)
    uf2="$tmp/$nm/zig-out/firmware/$nm.uf2"
    [[ -s "$uf2" ]] && grep -q UF2 <<<"$(head -c 4 "$uf2")" && ok "template $kind: Pico via microzig-box ($("$B" run arm-none-eabi-size "${uf2%.uf2}.elf" | awk 'NR==2 {print $1+$2}') B flash)" \
      || { bad "template $kind"; tail -8 <<<"$out" | sed 's/^/      /'; }
    continue
  fi
  for board in ${boards//,/ }; do
    out=$("$B" run bash -c "cd '$tmp/$nm' && cmake -S . -B build-$board -G Ninja -DBOARD=$board -Wno-dev >cfg-$board.log 2>&1 && cmake --build build-$board -j 4 >bld-$board.log 2>&1 || { tail -20 cfg-$board.log bld-$board.log; exit 1; }; arm-none-eabi-size build-$board/$nm.elf" 2>&1) \
      && grep -q "$nm.elf" <<<"$out" && grep -qaF "$nm" "$tmp/$nm/build-$board/$nm.bin" \
      && ok "template $kind: $board ($(tail -1 <<<"$out" | awk '{print $1+$2}') B flash, name in image)" \
      || { bad "template $kind: $board"; tail -8 <<<"$out" | sed 's/^/      /'; }
  done
done <<<"$TEMPLATE_BOARDS"
out=$("$B" unit-test test_fifo 2>&1); grep -q 'FAILED: *0' <<<"$out" && ok "ceedling: $(grep -m1 'TESTED' <<<"$out" | xargs) (test_fifo)" || { bad "ceedling test_fifo"; tail -8 <<<"$out" | sed 's/^/      /'; }
out=$("$B" plan raspberry_pi_pico fw.elf 2>&1); grep -q '^picotool load' <<<"$out" && grep -q 'PRINTED ONLY' <<<"$out" && ok "plan prints (does not run) picotool load" || bad "plan"
echo "smoke: $pass ok, $failn failed"
[[ "$failn" -eq 0 ]]
