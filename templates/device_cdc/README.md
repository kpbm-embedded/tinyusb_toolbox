# @NAME@

TinyUSB device firmware from `tinyusb-box new device_cdc @NAME@` (32_21_tinyusb): two CDC serial
ports (input on either is echoed to both: port 0 lower-case, port 1 upper-case), based on TinyUSB's `cdc_dual_ports` example (MIT).
`src/tusb_config.h` selects the classes, `src/usb_descriptors.c` the VID/PID and strings
(product string "@NAME@"; VID 0xCafe is TinyUSB's test VID: get your own for products).

    tinyusb-box shell -- bash -c 'cmake -S . -B build -G Ninja -DBOARD=raspberry_pi_pico && cmake --build build'
    tinyusb-box shell -- bash -c 'cmake -S . -B build-bp -G Ninja -DBOARD=stm32f411blackpill && cmake --build build-bp'
    tinyusb-box plan raspberry_pi_pico build/@NAME@.elf   # prints the flash commands (runs nothing)

Board support (clock, pins, LED, button) comes from TinyUSB's `hw/bsp/<family>/boards/<board>`
inside the 32_21_tinyusb install; the folder itself holds only your sources.
