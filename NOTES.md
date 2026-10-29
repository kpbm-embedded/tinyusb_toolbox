# 32_21_tinyusb: notes

## 2026-10-25: created
- New ID in the Box tool style (launcher `tinyusb-box`, `lib/boxtool.bash` copied unchanged from
  32_10_qemu, hooks in `lib/tinyusb.bash`; pixi binary copied from 32_10_qemu).
- TinyUSB 0.21.0 deps: instead of `tools/get_deps.py` (git clones into the tree), the commits it
  lists for stm32f4 (+ CMSIS_5) are pinned as GitHub commit archives and symlinked into the tree by
  `bootstrap`. First BlackPill build linked but failed in the post-build step: `tools/linkermap`
  (and `tools/uf2`) are mandatory get_deps entries too; added as pins.
- Pico: pico-sdk 2.3.1 release tarball + prebuilt picotool/pioasm from pico-sdk-tools via
  `picotool_DIR`/`pioasm_DIR`: no download or host-tool build during CMake. Works first time.
- Ceedling 1.0.1 gem into `cache/gems` (GEM_HOME, GEM_SPEC_CACHE in the ID; ~/.gem untouched).
  The first unit-test run used the OS gcc; added conda `c-compiler` to the env (+~0.3 GB, total 2.9 GB).
  Ceedling writes `_build` next to project.yml, so `unit-test` runs on a copy in $BUILD/unit-test
  (src/lib/hw symlinked). 61/61 tests pass ("ASSERT FAILED" lines in the log are expected output).
- Example test bug (mine): the BlackPill entry-point check compared the string "0x800391d" with
  "0x0800"; now a numeric range check.
- Mistake: while testing link_deps I trash-put the dep symlinks by hand and logged them afterwards.
- Stars 12 months ago from a Wayback snapshot (GitHub stargazer API 404).
- Results: doctor 31 ok / 0 failed, examples test 4/4 (3 firmware x 2 boards + 61 unit tests),
  tests/test_smoke.sh 8/8, tests/test_dry_run.sh 29/29.

## 2026-10-25: style pass
- lib/boxtool.bash re-synced from 32_06_renode (md5 0c5ba426...: usage_error, unknown command/usage -> exit 2, fuller help).
- Launcher rewritten in bash (set -euo pipefail, [[ ]]) after 32_13_arduino/arduino-box; same pixi v0.81.0 + sha256 table.
- Tool usage errors use usage_error; help has tool examples/environment; dry-run suite checks --help, -h and exit 2.
- Scripts converted to [[ ]]; lib Python with argparse help, type hints, pathlib.

## 2026-10-25: readability pass 2 (script_style.md, scripts/README)
- lib/boxtool.bash (reference `00_09_meta/05_policy/templates/tool/lib/boxtool.bash`, synced to all 24 copies):
  `where`/`status`/`doctor`/`bootstrap`/`relocate` reject extra arguments (exit 2); colour only on a terminal
  and never with `NO_COLOR`; help lists `NO_COLOR`.
- Examples/environment moved out of the command list into hook_help; examples/common/tu_example.sh:
  `arm-none-eabi-nm | grep -q` -> here-string (pipefail flake).
- README: exit codes, `BOX_INTEGRATION` and `NO_COLOR` rows. Backups:
  `00_09_meta/02_logs/config_backups/2026_10_25_readability2_embedded_tools/`.

## 2026-10-29: examples, templates, more boards, git (repo `tinyusb_toolbox`)
- Pins: nrfx, ST cmsis_device/HAL for G4, H5, H7, stm32-tcpp0203 and Pico-PIO-USB, the commits TinyUSB 0.21.0's
  tools/get_deps.py names. Three are upstream tags (nrfx v3.14.0, cmsis_device_h5 v1.7.0, stm32-tcpp0203 v1.2.3); six
  sit between tags, so the source of truth is the commit in the tagged TinyUSB release. No digest is published for
  commit archives: each archive was compared file by file with `git fetch --depth 1 <commit>` (identical), then sha256.
- 14 new examples: midi_test, msc_dual_lun, dfu, uac2_headset, video_capture, usbtmc, host_cdc_msc_hid, dual_pio_host,
  board_matrix (Pico 2, nRF52840, G474, WeAct H743, H563), descriptor_lint, pio_usb_crc, rust_cdc_compare, zig_usb_cdc,
  bend_usb_crc. 15 new templates (12 TinyUSB-based C, host_cdc_msc_hid, dual_pio_host, rust_usb_hid, zig_usb_cdc);
  the smoke test now builds every template for its boards.
- descriptor_lint: the first version flagged cdc_uac2 for reusing an endpoint; alternate settings of one interface
  may do that (fixed in lint.py). Some usb_descriptors.c need `tud_control_xfer` and pico-sdk's `__not_in_flash`:
  stubbed in the host harness.
- nRF builds give no .bin: the check makes one with objcopy and a UF2 (family 0xADA52840) with TinyUSB's uf2conv.py.
- zig_usb_cdc: microzig-box inherited this launcher's pixi env (conda LDFLAGS) and failed linking regz; it now runs
  under `env -i`. MicroZig writes no picotool binary info and stores strings as UTF-16, so the test reads the UF2
  header and searches UTF-16. Zig packages need a name-bound fingerprint: the template keeps the package name fixed.
- Rust: embassy-usb CDC 22.6 KB flash vs TinyUSB cdc_dual_ports 24.3 KB on the Pico; Zig (MicroZig, polled) 4.4 KB.
- Bend: proofs that Pico-PIO-USB's CRC-16 table equals the bitwise CRC (generated from its usb_crc.c), check value,
  streaming law; `--verdict` passes, a table with one wrong entry is rejected. Linear args needed `+`; lists are not
  Data, so the table check walks the list instead of indexing it. My first draft (guessed syntax) went to the Trash.
- Mistake: the template generator wrote a `.boards` file into each template (copied by `new`); moved to the Trash
  (logged), the board list lives in tests/test_smoke.sh.
- dummy_hcd / USB/IP not used (root needed). Hardware not tested: enumeration, flashing, PIO-USB timing.
- Results: doctor 49 ok / 0 failed; examples test 18/18; test_smoke.sh 35/35; test_dry_run.sh 35/35.
