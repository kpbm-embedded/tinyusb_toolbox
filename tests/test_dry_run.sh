#!/usr/bin/env bash
# Every tinyusb-box command in --dry-run mode, help and exit codes (no downloads, builds, moves or device writes),
# plus shellcheck of every script. Usage: tests/test_dry_run.sh
set -uo pipefail   # no -e: every check runs and failures are counted
HERE=$(cd "$(dirname "$0")/.." && pwd -P)
B="$HERE/tinyusb-box"
pass=0; failn=0
check() { # name expected-regex cmd...
  local name=$1 re=$2; shift 2
  local out rc
  out=$(timeout 300 "$@" 2>&1); rc=$?
  if [[ "$rc" -eq 0 ]] && grep -qE -- "$re" <<<"$out"; then
    printf 'ok    %s\n' "$name"; pass=$((pass+1))
  else
    printf 'FAIL  %s (rc=%s)\n%s\n' "$name" "$rc" "$(tail -5 <<<"$out" | sed 's/^/      /')"; failn=$((failn+1))
  fi
}
check_exit() { # name expected-exit-code cmd...
  local name=$1 want=$2 rc; shift 2
  timeout 120 "$@" >/dev/null 2>&1; rc=$?
  if [[ "$rc" -eq "$want" ]]; then printf 'ok    %s (exit %s)\n' "$name" "$rc"; pass=$((pass+1))
  else printf 'FAIL  %s (exit %s, want %s)\n' "$name" "$rc" "$want"; failn=$((failn+1)); fi
}
check help        'usage: \./tinyusb-box'                  "$B" help
check help-flag     'environment'                           "$B" --help
check help-short    'tinyusb-box examples'                  "$B" -h
check_exit unknown-cmd     2                                     "$B" no-such-command
check_exit usage-plan      2                                     "$B" plan
check_exit bad-board       2                                     "$B" plan no-such-board x.elf
check_exit usage-build     2                                     "$B" build
check where       '^tinyusb '                              "$B" where
check bootstrap   'pixi .*install'                         "$B" --dry-run bootstrap
check install     'gem install .*ceedling|example\.sh build' "$B" --dry-run install
check update      'curl https://api.github.com/repos/hathach/tinyusb' "$B" --dry-run update
check update-env  '\+ timeout .* update'                   "$B" --dry-run update --env
check clean       'nothing to clean|dry run: re-run with --yes' "$B" clean
check clean-all   'dry run: re-run with --yes'             "$B" clean --all
check status      '^  tinyusb '                            "$B" status
check doctor      'doctor: [0-9]+ ok'                      bash -c "'$B' doctor || true"
check shell       '\+ true'                                "$B" --dry-run shell -- true
check run         '\+ arm-none-eabi-gcc --version'         "$B" --dry-run run arm-none-eabi-gcc --version
check test        'test_smoke\.sh'                         "$B" --dry-run test
check new         '\+ copy .*templates/device_cdc'         "$B" --dry-run new device_cdc demo --dir /nonexistent
check ex-list     'cdc_msc .*CDC'                          "$B" examples list
check ex-run      'example\.sh run'                        "$B" --dry-run examples run cdc_msc
check ex-build    'example\.sh build'                      "$B" --dry-run examples build
check ex-test     'example\.sh test'                       "$B" --dry-run examples test
check native      'picotool install/picotool'              "$B" --dry-run native
check relocate    'pixi env already matches|re-creating'   "$B" --dry-run relocate
check pack        '\+ tar .*-cf .*tinyusb-box_'            "$B" --dry-run pack
check boards      'stm32f411blackpill'                     "$B" boards
check build       '\+ cmake -S .*examples/device/cdc_msc .*-DBOARD=raspberry_pi_pico' "$B" --dry-run build device/cdc_msc raspberry_pi_pico
check unit-test   'ceedling test:all'                      "$B" --dry-run unit-test
check list        'TinyUSB|no TinyUSB'                     "$B" list
check plan-pico   'PRINTED ONLY'                           "$B" plan raspberry_pi_pico x.elf
check plan-bp     'dfu-util -a 0 -s 0x08000000:leave'      "$B" plan stm32f411blackpill x.elf
check udev        'sudo udevadm control --reload-rules'    "$B" udev
if command -v shellcheck >/dev/null; then
  mapfile -t files < <(cd "$HERE" && { echo tinyusb-box; ls lib/*.bash tests/*.sh examples/*/example.sh examples/common/*.sh; })
  if out=$(cd "$HERE" && shellcheck -x "${files[@]}" 2>&1); then printf 'ok    shellcheck (%s files)\n' "${#files[@]}"; pass=$((pass+1))
  else printf 'FAIL  shellcheck\n%s\n' "$(head -30 <<<"$out")"; failn=$((failn+1)); fi
else printf 'skip  shellcheck (not installed)\n'; fi
echo "dry-run: $pass ok, $failn failed"
[[ "$failn" -eq 0 ]]
