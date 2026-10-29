# @NAME@

Zig counterpart of the TinyUSB `device_cdc` template, from `tinyusb-box new zig_usb_cdc @NAME@` (32_21_tinyusb):
a USB CDC-ACM serial port on the Raspberry Pi Pico with MicroZig's own USB stack (polled, no TinyUSB) that echoes
input upper-cased. Built with the pinned Zig 0.17.0 + MicroZig 0.17.25 of `32_24_microzig` (`microzig-box`, found via
`$BOX_MICROZIG`). VID/PID are MicroZig's Raspberry Pi defaults (2e8a:000a): use your own for products.
The package name in `build.zig.zon` stays `zig_usb_cdc_app` (its fingerprint is tied to that name); the firmware
file and the USB strings use @NAME@.

```sh
"$BOX_MICROZIG/microzig-box" zig build -Doptimize=ReleaseSmall    # zig-out/firmware/@NAME@.uf2 and .elf
tinyusb-box plan raspberry_pi_pico zig-out/firmware/@NAME@.elf    # prints the flash commands (runs nothing)
```
