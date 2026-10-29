# 32_21_tinyusb - why TinyUSB, and how its dependencies are pinned

## Why TinyUSB (state of the art, research 2026-10-25)

| Tool | Stars now / ~12 mo ago | Releases last 12 mo, latest | Licence | Sources |
|---|---|---|---|---|
| TinyUSB | 7,236 / 6,157 (Wayback 2025-10-20) | 2 (0.20.0 2025-11-20, 0.21.0 2026-06-30); last commit 2026-10-24 | MIT | <https://www.tinyusb.org>, <https://github.com/hathach/tinyusb>, <https://components.espressif.com/components/espressif/tinyusb/versions/0.21.0~2/readme>, pico-sdk ships it as `lib/tinyusb` |

Best in class: the USB stack that Raspberry Pi (pico-sdk), Espressif (esp_tinyusb), Adafruit (CircuitPython/Arduino)
and Zephyr-adjacent projects build on; device + host + Type-C, 50+ families, thread-safe without an RTOS, MIT.
Alternatives (vendor stacks: ST USB Device/USBX, libopencm3 usb) are single-family.

## How dependencies are pinned

TinyUSB's `tools/get_deps.py` would `git clone` its deps into the tree; here the same commits come as pinned
archives into `install/<dep>-<commit>` and `bootstrap` links them (relative symlinks) to the paths TinyUSB expects
(`hw/mcu/st/...`, `lib/CMSIS_5`, `tools/linkermap`, `tools/uf2`). Only the stm32f4 + rp2040 deps are installed;
other families need their get_deps entries added as pins in `config/pins.tsv`.

pico-sdk 2.x wants picotool for UF2s: the prebuilt one is found via `picotool_DIR`, so the SDK never downloads or
builds it. GCC 14.2.1 rather than 15.2.1: this is the toolchain TinyUSB 0.21 and pico-sdk 2.3 use in CI; 15.x is a
deliberate pin change.

| Dep | Commit / version |
|---|---|
| ST cmsis_device_f4 | 3c77349 |
| ST stm32f4xx_hal_driver | b6f0ed3 |
| ARM CMSIS_5 | 2b7495b (5.9.0) |
| linkermap / uf2 (build helpers) | 8e1f440 / c594542 |
