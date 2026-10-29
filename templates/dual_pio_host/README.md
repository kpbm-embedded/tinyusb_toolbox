# @NAME@

Device + host at once on the Pico: native USB is a CDC device, Pico-PIO-USB (GP0/GP1) a host that forwards HID reports. From `tinyusb-box new dual_pio_host @NAME@` (32_21_tinyusb), based on TinyUSB 0.21.0 `examples/dual/host_hid_to_device_cdc` (MIT,
licence header kept in each file). `src/tusb_config.h` selects the classes, `src/usb_descriptors.c` (where present) the
VID/PID and strings; the product string is "@NAME@". VID 0xCafe is TinyUSB's test VID: get your own for products.

    tinyusb-box shell -- bash -c 'cmake -S . -B build -G Ninja -DBOARD=raspberry_pi_pico && cmake --build build'
    tinyusb-box plan raspberry_pi_pico build/@NAME@.elf   # prints the flash commands (runs nothing)

Boards checked by the 32_21 smoke test: raspberry_pi_pico. Other boards: any TinyUSB board whose family deps are installed
(`tinyusb-box boards --all`; nRF52840, STM32G4/H5/H7 deps are pinned too).
