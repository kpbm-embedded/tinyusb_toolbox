# @NAME@: USB host, from `tinyusb-box new host_cdc_msc_hid @NAME@` (32_21_tinyusb).
# Based on TinyUSB 0.21.0 examples/host/cdc_msc_hid (MIT). Board support (hw/bsp) comes from TINYUSB_DIR (tinyusb-box shell).
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
  ${CMAKE_CURRENT_SOURCE_DIR}/src/cdc_app.c
  ${CMAKE_CURRENT_SOURCE_DIR}/src/hid_app.c
  ${CMAKE_CURRENT_SOURCE_DIR}/src/main.c
  ${CMAKE_CURRENT_SOURCE_DIR}/src/msc_app.c
)
target_include_directories(${PROJECT_NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
family_configure_host_example(${PROJECT_NAME} noos)
