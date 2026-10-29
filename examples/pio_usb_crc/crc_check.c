// crc_check.c: host test of Pico-PIO-USB's table-driven USB CRCs (pio_usb_crc example, 32_21_tinyusb).
// PIO-USB computes token CRC5 and data CRC16 in software (the RP2040 has no USB PHY on those pins), so a
// wrong table entry would break every host transfer. Compares the tables with bit-by-bit references
// written from the USB 2.0 spec (CRC5 poly x^5+x^2+1, CRC16 poly x^16+x^15+x^2+1, LSB first).
#include <stdint.h>
#include <stdio.h>
#include "usb_crc.h"

static uint8_t ref_crc5(uint16_t data11) {  // 11-bit token field, result already inverted
  uint8_t crc = 0x1f;
  for (int i = 0; i < 11; i++) {
    int bit = (data11 >> i) & 1;
    int fb = (crc ^ bit) & 1;
    crc >>= 1;
    if (fb) crc ^= 0x14;  // reflected 0x05
  }
  return (uint8_t)(~crc & 0x1f);
}

static uint16_t ref_crc16(const uint8_t *p, uint16_t n) {  // CRC-16/USB: init 0xffff, reflected 0x8005, xorout 0xffff
  uint16_t crc = 0xffff;
  for (uint16_t i = 0; i < n; i++) {
    crc ^= p[i];
    for (int b = 0; b < 8; b++) crc = (crc & 1) ? (uint16_t)((crc >> 1) ^ 0xa001) : (uint16_t)(crc >> 1);
  }
  return (uint16_t)~crc;
}

int main(void) {
  int fail = 0;
  for (uint16_t d = 0; d < 2048; d++) {
    uint8_t got = calc_usb_crc5(d), want = ref_crc5(d);
    if (got != want) { if (fail++ < 5) printf("FAIL crc5(0x%03x) = 0x%02x, want 0x%02x\n", d, got, want); }
  }
  printf("crc5: 2048 token values checked\n");
  const uint8_t check[] = "123456789";
  uint16_t c = calc_usb_crc16(check, 9);
  printf("crc16(\"123456789\") = 0x%04x (CRC-16/USB check value 0xb4c8)\n", c);
  if (c != 0xb4c8 || ref_crc16(check, 9) != 0xb4c8) { printf("FAIL crc16 check value\n"); fail++; }
  uint8_t buf[64];
  uint32_t x = 12345;
  for (int t = 0; t < 1000; t++) {  // random data packets up to 64 bytes (full-speed max)
    uint16_t n = (uint16_t)(t % 65);
    for (int i = 0; i < n; i++) { x = x * 1103515245u + 12345u; buf[i] = (uint8_t)(x >> 16); }
    if (calc_usb_crc16(buf, n) != ref_crc16(buf, n)) { if (fail++ < 5) printf("FAIL crc16 packet %d (len %u)\n", t, n); }
  }
  printf("crc16: 1000 packets of 0..64 bytes checked\n");
  return fail ? 1 : 0;
}
