#!/usr/bin/env bash
# about: TinyUSB's own host unit tests (Ceedling 1.0 + Unity/CMock, host GCC): fifo, usbd, msc, midi2 - 61 tests
# Usage (through ./tinyusb-box examples ...): example.sh build | run | test
set -euo pipefail
OUT=${EX_OUT:?run through ./tinyusb-box examples}
act=${1:-run}
case "$act" in
  build) command -v ceedling >/dev/null || { echo "ceedling missing: tinyusb-box install"; exit 1; }; echo "ceedling $(ceedling version 2>/dev/null | sed -n 's/.*Ceedling => //p')" ;;
  run|test)
    out=$(bash "$BOXT_ROOT/tinyusb-box" unit-test 2>&1) || { tail -30 <<<"$out"; echo "FAIL ceedling"; exit 1; }
    printf '%s\n' "$out" >"$OUT/ceedling.log"
    sed -n '/OVERALL TEST SUMMARY/,/IGNORED/p' <<<"$out"
    t=$(sed -n 's/^TESTED: *//p' <<<"$out"); f=$(sed -n 's/^FAILED: *//p' <<<"$out")
    [[ "${t:-0}" -ge 50 ]] && [[ "${f:-1}" = 0 ]] || { echo "FAIL: tested ${t:-?}, failed ${f:-?}"; exit 1; }
    echo "PASS host_unit_tests ($t tests)" ;;
  *) echo "usage: example.sh build|run|test" >&2; exit 2 ;;
esac
