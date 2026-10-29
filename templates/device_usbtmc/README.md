# @NAME@

USBTMC/USB488 instrument answering *IDN? (PyVISA, sigrok). From `tinyusb-box new device_usbtmc @NAME@` (32_21_tinyusb), based on TinyUSB 0.21.0 `examples/device/usbtmc` (MIT,
licence header kept in each file). `src/tusb_config.h` selects the classes, `src/usb_descriptors.c` (where present) the
VID/PID and strings; the product string is "@NAME@". VID 0xCafe is TinyUSB's test VID: get your own for products.

    tinyusb-box shell -- bash -c 'cmake -S . -B build -G Ninja -DBOARD=stm32f411blackpill && cmake --build build'
    tinyusb-box shell -- bash -c 'cmake -S . -B build-raspberry_pi_pico -G Ninja -DBOARD=raspberry_pi_pico && cmake --build build-raspberry_pi_pico'
    tinyusb-box plan stm32f411blackpill build/@NAME@.elf   # prints the flash commands (runs nothing)

Boards checked by the 32_21 smoke test: stm32f411blackpill, raspberry_pi_pico. Other boards: any TinyUSB board whose family deps are installed
(`tinyusb-box boards --all`; nRF52840, STM32G4/H5/H7 deps are pinned too).
