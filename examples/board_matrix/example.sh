#!/usr/bin/env bash
# about: cdc_msc on the other boards: Pico 2 (RP2350), nRF52840, STM32G474 (G431 family), WeAct H743, STM32H563 (H562 family)
# Usage (through ./tinyusb-box examples ...): example.sh build | run (prints flash plan) | test
TU_EX=device/cdc_msc
TU_BOARDS="raspberry_pi_pico2 feather_nrf52840_express stm32g474nucleo stm32h743_weact stm32h563nucleo"
# shellcheck source-path=SCRIPTDIR source=../common/tu_example.sh
. ../common/tu_example.sh "$@"
