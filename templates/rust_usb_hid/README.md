# @NAME@

Rust counterpart of the TinyUSB `device_hid` template, from `tinyusb-box new rust_usb_hid @NAME@` (32_21_tinyusb):
a USB HID boot keyboard on the Raspberry Pi Pico with embassy-usb. Pull GP15 to GND and it types "hi" + Enter.
Built with the pinned Rust of `32_17_embedded_rust` (`rust-box`, found via `$BOX_EMBEDDED_RUST`); `Cargo.lock` and
`rust-toolchain.toml` are the ones of its `usb_cdc_app` template, so the build works offline from its cargo cache.
Test VID/PID 0xc0de:0xcafe: use your own for anything you ship.

```sh
"$BOX_EMBEDDED_RUST/rust-box" run bash -c 'cd @NAME@ && cargo build --release'
"$BOX_EMBEDDED_RUST/rust-box" uf2 target/thumbv6m-none-eabi/release/@NAME@ -o @NAME@.uf2   # BOOTSEL copy
```
