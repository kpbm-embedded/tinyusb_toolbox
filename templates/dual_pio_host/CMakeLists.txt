# @NAME@: device + host at once on the Pico, from `tinyusb-box new dual_pio_host @NAME@` (32_21_tinyusb).
# Based on TinyUSB 0.21.0 examples/dual/host_hid_to_device_cdc (MIT). Board support (hw/bsp) comes from TINYUSB_DIR (tinyusb-box shell).
#   cmake -S . -B build -G Ninja -DBOARD=raspberry_pi_pico
cmake_minimum_required(VERSION 3.20)
if(NOT DEFINED ENV{TINYUSB_DIR})
  message(FATAL_ERROR "TINYUSB_DIR is not set: build inside `tinyusb-box shell`")
endif()
include($ENV{TINYUSB_DIR}/hw/bsp/family_support.cmake)
project(@NAME@ C CXX ASM)
family_initialize_project(${PROJECT_NAME} ${CMAKE_CURRENT_LIST_DIR})
add_executable(${PROJECT_NAME})
target_sources(${PROJECT_NAME} PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/src/main.c
  ${CMAKE_CURRENT_SOURCE_DIR}/src/usb_descriptors.c
)
target_include_directories(${PROJECT_NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
family_configure_dual_usb_example(${PROJECT_NAME} noos)
if(FAMILY STREQUAL rp2040)   # Pico-PIO-USB does not build with TinyUSB's -Werror set
  target_compile_options(${PROJECT_NAME} PUBLIC -Wno-error=shadow -Wno-error=cast-align -Wno-error=cast-qual
    -Wno-error=redundant-decls -Wno-error=sign-conversion -Wno-error=conversion -Wno-error=sign-compare -Wno-error=unused-function)
endif()
