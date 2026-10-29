# 32_21_tinyusb - TinyUSB (USB device and host stack)

**TinyUSB** (MIT) is the open-source USB stack used by pico-sdk, ESP-IDF, CircuitPython and many vendor SDKs: one
code base for 50+ MCU families. This ID builds its examples (serial, mass storage, HID, WebUSB) for the
**BlackPill STM32F411CE** and the **Raspberry Pi Pico** (plus Pico 2, nRF52840, STM32G4/H5/H7 builds), runs TinyUSB's own host unit tests and
host-side descriptor/CRC checks, compares with the Rust (embassy-usb) and Zig (MicroZig) USB stacks, and prints
(never runs) the flash commands. Everything is pinned and kept inside this folder: no sudo, no system packages.
Repository name: `tinyusb_toolbox`.

Status: **ready** (doctor 50 ok, examples 18/18, templates 16/16 built by the smoke test, 2026-10-29). Using real hardware needs udev
rules (your action, see "Limitations"). Launcher: `./tinyusb-box`.

## What's included

| Component | Version | Notes |
|---|---|---|
| TinyUSB | 0.21.0 (2026-06-30) | tag archive, sha256 trust-on-first-use; 26 MB |
| ST cmsis_device_f4, stm32f4xx_hal_driver | commits 3c77349, b6f0ed3 | the commits TinyUSB 0.21.0 pins; linked into the tree |
| ARM CMSIS_5, linkermap, uf2 | commits 2b7495b, 8e1f440, c594542 | same |
| nrfx, ST cmsis_device/HAL g4, h5, h7, stm32-tcpp0203, Pico-PIO-USB | commits 11f57e5, 7c39c32/10138a4, 884b8dc/3c84eaa, 45b818c/dbfb749, 9918655, 675543b | the commits TinyUSB 0.21.0 pins; archives checked against `git fetch` of each commit (`config/pins.tsv`) |
| pico-sdk | 2.3.1 (2026-09-04) | TinyUSB comes from this ID's tree via `PICO_TINYUSB_PATH` |
| picotool, pioasm | 2.3.1 (prebuilt, pico-sdk-tools v2.3.1-0) | found via `picotool_DIR`; the SDK never builds them |
| arm-none-eabi-gcc | xPack 14.2.1-1.1 | GCC 14.2.1 + newlib/nano; the toolchain TinyUSB 0.21 CI uses; 1007 MB |
| Bend | 2.0.39 | pins group `bend` (installed by `install`), sha256 = GitHub release asset digest; only for `bend_usb_crc`; 80 MB |
| Ceedling (+ Unity 2.6.1, CMock 2.6.0) | gem 1.0.1 | in `cache/gems` (`GEM_HOME`) |
| CMake, Ninja, make, Python, Ruby, host GCC | 4.4.4, 1.13.2, 4.4, 3.12, 3.4.2, 15.3 | conda-forge via pixi (`pixi.lock`) |
| pixi | 0.81.0 | sha256 pinned in the launcher |

How the dependencies are pinned and why GCC 14: `docs/research.md`.

## Quick start

```sh
cd "$BOX_TINYUSB"                            # or: cd $BOX/30_39_tools/32_embedded/32_21_tinyusb
./tinyusb-box install && ./tinyusb-box doctor    # first setup (downloads once), then health checks
./tinyusb-box examples test                  # 18 examples: firmware builds, host tests, Rust/Zig/Bend comparisons
./tinyusb-box build device/midi_test raspberry_pi_pico   # any TinyUSB example for a board
./tinyusb-box plan raspberry_pi_pico fw.uf2  # PRINTS the flash commands; runs nothing
```

With the Box shell set up once (`box shell install --apply`), the `tinyusb-box` shim works from any folder,
and `box test|doctor|status tinyusb` run this launcher (`box clean tinyusb` is a dry run until `--apply`).
Standalone (no Box, or `BOX_INTEGRATION=0`), `./tinyusb-box` keeps its output in this folder.

## Commands

Global option: `--dry-run` / `-n` prints what a command would do. Exit codes: 0 ok, 1 failure, 2 usage error (unknown command or option, or arguments given to `where`, `status`, `doctor`, `bootstrap` or `relocate`), 3 not applicable. `help` ends with this tool's own examples and variables (`tool examples`, `tool environment`).

| Command | What it does | Example |
|---|---|---|
| `bootstrap` | pinned pixi + env + core downloads + dependency links (checksum-checked) | `./tinyusb-box bootstrap` |
| `install [--no-demos]` | bootstrap + demo downloads + build the examples | `./tinyusb-box install` |
| `update [--check\|--env]` | `--check` (default): compare pins with newest upstream; `--env`: re-solve the pixi env | `./tinyusb-box update --check` |
| `clean [--all] [--yes]` | move build/log output (`--all`: also install/, .pixi, native/, downloads) to the Trash; dry run unless `--yes` | `./tinyusb-box --dry-run clean --all` |
| `status`, `where`, `doctor` | versions and sizes, paths, health checks (exit 1 on failure) | `./tinyusb-box doctor` |
| `shell [-- cmd ...]` | bash (or a command) with arm-none-eabi-*, cmake, ninja, picotool, `TINYUSB_DIR`, `PICO_SDK_PATH` set | `./tinyusb-box shell` |
| `run <cmd> [args]` | one command inside the environment | `./tinyusb-box run arm-none-eabi-gcc --version` |
| `boards` | the boards the examples build for (`boards --all`: every TinyUSB board name) | `./tinyusb-box boards` |
| `build <example> <board> [--dir D]` | build any TinyUSB example (`examples/device\|host\|dual/...`) for a board | `./tinyusb-box build device/cdc_msc stm32f411blackpill` |
| `unit-test [test]` | TinyUSB's host unit tests (Ceedling gem + the env's host GCC) | `./tinyusb-box unit-test test_fifo` |
| `list` | read-only: attached USB devices that matter here (TinyUSB 0xcafe, Pico BOOTSEL, STM32 DFU, CMSIS-DAP / ST-Link probes) | `./tinyusb-box list` |
| `plan <board> <fw.elf\|.uf2\|.bin>` | PRINT the flash commands (picotool, UF2 copy, dfu-util, openocd, probe-rs) for the boards in `boards`; runs nothing | `./tinyusb-box plan stm32f411blackpill fw.elf` |
| `udev` | print the udev rules file path and the sudo commands to install it | `./tinyusb-box udev` |
| `bend <args>` | the pinned Bend 2.0.39 (HOME/TMPDIR in `cache/`, `BEND_NO_TELEMETRY=1`; `update`, `login`, `link`, `--publish` refused) | `./tinyusb-box bend PROOF.bend` |
| `test [--all]` | `tests/test_smoke.sh`; `--all` adds the dry-run test and the examples test | `./tinyusb-box test` |
| `new <kind> <name> [--dir D] [--force]` | create a project from `templates/` (16 kinds, see below) | `./tinyusb-box new device_cdc my_usb` |
| `examples list \| run <ex> [args] \| build [ex...] \| test [ex...]` | list, run, build or test the examples | `./tinyusb-box examples test` |
| `native [--print]` | write `native/{native.zsh,native.bash,bin/}` | `./tinyusb-box native` |
| `relocate` | after moving the folder: re-create the pixi env, rewrite `native/` | `./tinyusb-box relocate` |
| `pack [--with-cache] [--out F]` | tarball of this folder (minus envs/build) for another machine | `./tinyusb-box pack --out /tmp/t.tgz` |
| `help`, `-h`, `--help` | the command list | `./tinyusb-box help` |

## Examples and templates

The firmware examples are TinyUSB's own (`install/tinyusb-0.21.0/examples/...`), built out of tree; `examples run <ex>`
builds and prints the flash plan. Nothing here writes a device and no board is attached: firmware tests check the
artifacts (fits flash, USB task linked, VID 0xCafe in the image, entry point in flash, UF2 address/family via
`picotool info` or the UF2 header). Enumeration on a real host is NOT tested.

| Example | Boards / where | What it shows | Test checks |
|---|---|---|---|
| `cdc_msc` | BlackPill + Pico | CDC serial echo + 8 KB RAM disk | artifact checks (above) |
| `hid_composite` | BlackPill + Pico | keyboard + mouse + consumer + gamepad | same |
| `webusb_serial` | BlackPill + Pico | vendor class + BOS/MS OS 2.0 (driverless WebUSB) + CDC | same |
| `midi_test` | BlackPill + Pico | USB MIDI 1.0 device | same |
| `msc_dual_lun` | BlackPill + Pico | mass storage with two LUNs | same |
| `dfu` | BlackPill + Pico | DFU mode device (dfu-util -D/-U into RAM handlers) | same |
| `uac2_headset` | BlackPill + Pico | UAC2 headset, isochronous endpoints | same |
| `video_capture` | BlackPill + Pico | UVC camera with generated colour bars | same |
| `usbtmc` | BlackPill + Pico | USBTMC/USB488 instrument (*IDN?) | same |
| `host_cdc_msc_hid` | Pico + BlackPill | USB **host** stack: CDC, MSC, HID devices | `tuh_task_ext` linked, artifact checks |
| `dual_pio_host` | Pico | device on native USB + host on Pico-PIO-USB (GP0/GP1) | both stacks linked |
| `board_matrix` | Pico 2, nRF52840, STM32G474, WeAct H743, STM32H563 | `cdc_msc` on the other boards | per-chip flash size and start; nRF: UF2 family 0xADA52840 above the S140 area |
| `descriptor_lint` | host | each device example's and template's `usb_descriptors.c` compiled on the PC; descriptors linted | 62 sets: lengths, wTotalLength, interfaces, endpoints, IADs, strings, BOS, HID report items; one negative check |
| `pio_usb_crc` | host | Pico-PIO-USB software CRC5/CRC16 vs bit-by-bit references | all 2048 tokens, check value 0xB4C8, 1000 packets |
| `host_unit_tests` | host | TinyUSB `test/unit-test` via Ceedling 1.0.1 | 61 tests, 0 failed |
| `rust_cdc_compare` | Pico | embassy-usb CDC (32_17's `usb_cdc_app`) vs TinyUSB `cdc_dual_ports` | size table (22.6 KB vs 24.3 KB flash), entry/IRQ symbols |
| `zig_usb_cdc` | Pico | MicroZig's own USB stack, CDC echo (via 32_24) | UF2 header, UTF-16 string descriptors in the image (4.4 KB flash) |
| `bend_usb_crc` | host | Bend 2 laws + proofs (Bend pinned in this ID): PIO-USB's CRC-16 table = bitwise CRC for all 256 bytes, check value, streaming law | `bend PROOF.bend` = ALL PROOFS CHECK; a table with one wrong entry is rejected |

`descriptor_lint` also lints your own firmware: `./tinyusb-box examples run descriptor_lint <dir with usb_descriptors.c and tusb_config.h>`.

Templates (`./tinyusb-box new <kind> <name> [--dir D]`): the C ones are TinyUSB 0.21.0 examples (MIT, licence headers
kept), product string = name, CMake through `TINYUSB_DIR`; configure with `-DBOARD=stm32f411blackpill` or
`-DBOARD=raspberry_pi_pico` (any board whose deps are pinned works).

| Template | What | Smoke test builds for |
|---|---|---|
| `device_cdc` | two CDC serial ports | BlackPill, Pico |
| `device_hid` | HID composite (keyboard, mouse, consumer, gamepad) | BlackPill, Pico |
| `device_hid_generic` | raw HID 64-byte in/out (hidapi, WebHID) | BlackPill, Pico |
| `device_msc` | mass storage, two LUNs | BlackPill, Pico |
| `device_midi` | USB MIDI | BlackPill, Pico |
| `device_webusb` | WebUSB + CDC | BlackPill, Pico |
| `device_dfu` | DFU mode | BlackPill, Pico |
| `device_dfu_runtime` | DFU runtime (detach to bootloader) | BlackPill, Pico |
| `device_audio` | UAC2 headset | BlackPill, Pico |
| `device_uvc` | UVC camera (generated frames) | BlackPill, Pico |
| `device_usbtmc` | USBTMC instrument | BlackPill, Pico |
| `device_composite` | CDC + MSC composite | BlackPill, Pico |
| `host_cdc_msc_hid` | USB host for CDC/MSC/HID | Pico, BlackPill |
| `dual_pio_host` | device + PIO-USB host | Pico |
| `rust_usb_hid` | embassy-usb boot keyboard (Rust), built with 32_17's `rust-box` | Pico |
| `zig_usb_cdc` | MicroZig USB CDC echo (Zig), built with 32_24's `microzig-box` | Pico |

**Other languages.** Rust: `rust_cdc_compare`, template `rust_usb_hid` (32_17_embedded_rust via `$BOX_EMBEDDED_RUST`).
Zig: `zig_usb_cdc` example + template (32_24_microzig via `$BOX_MICROZIG`; run in a clean environment so this ID's
conda compiler flags do not reach zig's native build steps). Bend: `bend_usb_crc`, host-side proofs only, with Bend 2.0.39
pinned in this ID (`config/pins.tsv` group `bend`, installed by `install`, run by `./tinyusb-box bend`; Bend has no MCU
target). No Bend template: the example is the pattern. The Rust and Zig parts skip with exit 3 when the sibling ID is
missing (`examples test` then lists them as FAIL: boxtool counts skips as failures).

**Not used:** Linux `dummy_hcd` / USB/IP (loading the modules needs root), so nothing enumerates on this PC; ESP32-S3
needs ESP-IDF (TinyUSB's espressif family uses its own build), not part of this ID.

## Configuration and environment variables

| Variable | Default | Meaning |
|---|---|---|
| `TINYUSB_DIR`, `PICO_SDK_PATH`, `picotool_DIR`, `pioasm_DIR`, `PICO_TOOLCHAIN_PATH` | set inside the launcher | paths for your CMake builds |
| `GEM_HOME` / `GEM_PATH` | `cache/gems` | Ceedling gems; `XDG_CACHE_HOME` is `cache/xdg-cache` |
| `BOXT_OUT` | same ID path on idisk03, else the ID folder | output root (`build/`, `log/`); also settable in `config/local.env` |
| `BOXT_JOBS` | 8 (also the maximum) | parallel jobs |
| `BOXT_MIN_FREE_GB` | 8 | pause builds while less RAM is free; `BOXT_RAM_WAIT_MAX` (3600 s) gives up |
| `BOXT_NET_TIMEOUT` | 3600 | seconds for one download |
| `BOXT_PLATFORM` | detected (`linux-x64`) | override the platform |
| `GITHUB_TOKEN` | unset | optional; lifts the GitHub API limit for `update --check` |
| `BOX_INTEGRATION` | 1 | `0` = standalone: ignore `$BOX`/`$BOX_V3`, keep output in this folder |
| `NO_COLOR` | unset | set to print plain text (colour is only used on a terminal anyway) |
| `BOX_TINYUSB` | set by `box_env.sh` | path of this ID, used by the native snippet |
| `BOX_NATIVE_OFF_TINYUSB` | unset | `1` skips native mode for one shell (old name `TINYUSB_BOX_NATIVE_OFF` still honoured) |

Pins: `config/pins.tsv`; `update` never edits them.

## Where files go

| What | Where |
|---|---|
| Source, launcher, examples, template | this ID |
| Tools | `install/` (1.7 GB: Arm GCC 1.0 GB, CMSIS_5 138 MB, Bend 80 MB, ST/nRF deps, TinyUSB 26 MB, pico-sdk 30 MB, picotool/pioasm), `.pixi/` (1.1 GB), `.bin/` (pinned pixi) |
| Cache | `cache/` (1.5 GB: downloads 321 MB, pixi packages hard-linked with `.pixi`, gems 18 MB) |
| Build output and logs | `$BOX_V3/30_39_tools/32_embedded/32_21_tinyusb/{build,log}` (45 MB; `build/examples/<ex>/<board>/`) |
| udev rules file | `config/99-tinyusb-box.rules` (not installed) |

## Native mode

`./tinyusb-box native` writes `native/native.{zsh,bash}` and wrappers in `native/bin`: `arm-none-eabi-gcc`,
`arm-none-eabi-size`, `arm-none-eabi-objcopy`, `picotool` (binaries directly), `tinyusb-build`, `tinyusb-plan`
(through the launcher). Load it in every shell (zsh, bash, fish) with `box native enable tinyusb --apply`: it runs
`./tinyusb-box native` when the files are missing and rebuilds `box_env.d/native.*` (without `--apply` it only shows
the plan; `box native disable tinyusb --apply` undoes it). `BOX_NATIVE_OFF_TINYUSB=1` skips it for one shell (the old
`TINYUSB_BOX_NATIVE_OFF` still works for now). Without Box, source `native/native.zsh` or `native/native.bash` from
your shell rc.

This puts a second `arm-none-eabi-gcc` on PATH; enable it only if no other enabled native tool has one (`box native list`).

## Tests

```sh
./tinyusb-box test --all         # smoke + dry-run + examples
tests/test_smoke.sh              # tools run, every template built for its boards, a unit test, plan
tests/test_dry_run.sh            # every command in --dry-run + shellcheck
```

Last known (2026-10-29): doctor 50 ok / 0 failed; `examples test` 18/18; `test_smoke.sh` 35/35 (every template
built for its boards, incl. Rust and Zig); `test_dry_run.sh` 38/38.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Permission denied opening the board's USB device | install the udev rules (see below) or run as a user with access |
| ModemManager grabs the CDC port | the udev rules set `ID_MM_DEVICE_IGNORE` for VID 0xcafe |
| `tinyusb-box build` for another MCU family fails on missing dependencies | deps are installed for stm32f4/g4/h5/h7, rp2040/rp2350, nrf; add the family's `get_deps` entries as pins |
| Pico UF2 step tries to download or build picotool | run through the launcher: `picotool_DIR` points to the prebuilt 2.3.1 |
| `update --check` hits an API limit | export `GITHUB_TOKEN` |
| Folder was moved, env broken | `./tinyusb-box relocate` |

## Limitations / needs you

- **udev (sudo, your action):** `config/99-tinyusb-box.rules` gives your user access to TinyUSB examples (VID 0xcafe, WebUSB/hidraw), Pico BOOTSEL (2e8a:0003, 2e8a:000f) and STM32 DFU (0483:df11). Not installed:
  ```sh
  sudo cp "$BOX_TINYUSB/config/99-tinyusb-box.rules" /etc/udev/rules.d/
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```
  (`./tinyusb-box udev` prints the same.) Also `sudo usermod -aG uucp "$USER"` for serial ports, then log in again.
- **Flashing:** `plan` prints `picotool load -x` (Pico BOOTSEL), `dfu-util -a 0 -s 0x08000000:leave` (BlackPill ROM DFU) and `openocd` / `probe-rs` (SWD probe). dfu-util, openocd and probe-rs are not part of this ID (picotool is).
- VID 0xCafe is TinyUSB's test VID: a product needs its own VID/PID.
- Linux x64 is tested; arm64 pinned; macOS picotool/pioasm not pinned; Windows: use WSL2.
- Open items: `$BOX/00_09_meta/02_logs/2026_10_25_open_items.md` (uucp group, udev).

## Scripts

Each script has a `[scripts.*]` descriptor in `.box.toml` (`box scripts show 32_21`; `box scripts check 32_21` must stay clean).

- `tinyusb-box`: the launcher (POSIX sh); bootstraps the pinned pixi, keeps caches inside this folder, then runs lib/; `./tinyusb-box help` lists the commands
- `lib/boxtool.bash`: shared launcher framework (boxtool 3: bootstrap, pinned downloads, pixi env, every common command); byte-identical copy of `$BOX/00_09_meta/05_policy/templates/tool/lib/boxtool.bash` (edit there, then sync)
- `lib/tinyusb.bash`: this tool's part: TOOL_* settings, hooks (dependency links) and the extra commands (`build`, `unit-test`, `list`, `plan`, `udev`, `boards`)
- `examples/common/tu_example.sh`: helpers sourced by `examples/*/example.sh`
- `examples/<ex>/example.sh`: build/run/test for each of the 18 examples (`descriptor_lint/{harness.c,lint.py}`, `pio_usb_crc/crc_check.c`, `bend_usb_crc/*.bend`)
- `tests/test_smoke.sh`: smoke test of the tools, every template on its boards, a unit test and `plan`
- `tests/test_dry_run.sh`: every launcher command in --dry-run mode, plus shellcheck
- `native/`: written by `./tinyusb-box native`; regenerate, do not edit

## Links

- TinyUSB: <https://github.com/hathach/tinyusb/releases/tag/0.21.0>, <https://www.tinyusb.org>; pico-sdk: <https://github.com/raspberrypi/pico-sdk/releases/tag/2.3.1>; pico-sdk-tools: <https://github.com/raspberrypi/pico-sdk-tools/releases/tag/v2.3.1-0>
- xPack GCC: <https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/tag/v14.2.1-1.1>; Ceedling 1.0.1: <https://rubygems.org/gems/ceedling/versions/1.0.1>
- Dependency pinning and rationale: `docs/research.md`.
- History: `NOTES.md`. Reports: `$BOX/00_09_meta/02_logs/2026_10_25_embedded_tools2_report.md`.
- Sibling tools: `32_17_embedded_rust`, `32_24_microzig` (comparison examples), `32_15_flashers` (picotool, dfu-util, esptool), `32_18_rtos` (also uses an Arm GCC), `32_20_testing` (Ceedling 1.2.1).
