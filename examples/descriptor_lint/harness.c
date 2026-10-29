// harness.c: host-side dump of a TinyUSB device's descriptors (descriptor_lint example, 32_21_tinyusb).
// Compiled on the PC together with the firmware's own usb_descriptors.c and tusb_config.h; calls the
// descriptor callbacks the device stack would call during enumeration and prints them as hex lines
// ("DEV", "CFG", "STR <i>", "BOS", "HIDREP <instance>": exactly wDescriptorLength bytes) for lint.py. No USB hardware involved.
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "tusb.h"

// optional callbacks: weak so that a firmware without them still links (address is NULL then)
uint8_t const *tud_descriptor_bos_cb(void) __attribute__((weak));
uint8_t const *tud_hid_descriptor_report_cb(uint8_t instance) __attribute__((weak));
uint8_t const *tud_descriptor_other_speed_configuration_cb(uint8_t index) __attribute__((weak));

// board_api.h functions some usb_descriptors.c use for the serial number string
size_t board_get_unique_id(uint8_t id[], size_t max_len) {
  static const uint8_t uid[8] = {0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0};
  size_t n = max_len < sizeof(uid) ? max_len : sizeof(uid);
  memcpy(id, uid, n);
  return n;
}
size_t board_usb_get_serial(uint16_t desc_str1[], size_t max_chars) {
  const char *s = "123456789ABCDEF0";
  size_t n = strlen(s) < max_chars ? strlen(s) : max_chars;
  for (size_t i = 0; i < n; i++) desc_str1[i] = (uint16_t)s[i];
  return n;
}
uint32_t board_millis(void) { return 0; }
// device-stack function referenced by vendor control handlers in some usb_descriptors.c (never called here)
bool tud_control_xfer(uint8_t rhport, tusb_control_request_t const *request, void *buffer, uint16_t len) {
  (void)rhport; (void)request; (void)buffer; (void)len;
  return true;
}
void board_led_write(bool state) { (void)state; }

static void hexline(const char *tag, int idx, const uint8_t *p, size_t n) {
  if (idx >= 0) printf("%s %d ", tag, idx); else printf("%s ", tag);
  for (size_t i = 0; i < n; i++) printf("%02x", p[i]);
  printf("\n");
}

int main(void) {
  const uint8_t *dev = tud_descriptor_device_cb();
  hexline("DEV", -1, dev, dev[0]);
  const uint8_t *cfg = tud_descriptor_configuration_cb(0);
  hexline("CFG", -1, cfg, (size_t)(cfg[2] | (cfg[3] << 8)));
  for (int i = 0; i < 16; i++) {
    const uint16_t *s = tud_descriptor_string_cb((uint8_t)i, 0x0409);
    if (!s) continue;
    hexline("STR", i, (const uint8_t *)s, (size_t)(s[0] & 0xff));
  }
  if (tud_descriptor_bos_cb) {
    const uint8_t *b = tud_descriptor_bos_cb();
    if (b) hexline("BOS", -1, b, (size_t)(b[2] | (b[3] << 8)));
  }
  if (tud_hid_descriptor_report_cb) {
    // the n-th HID class descriptor (type 0x21) in CFG belongs to HID instance n; its wDescriptorLength
    // (bytes 7..8) is the report descriptor length the host will request
    size_t total = (size_t)(cfg[2] | (cfg[3] << 8)), off = 0;
    int inst = 0;
    while (off + 2 <= total && cfg[off] >= 2) {
      if (cfg[off + 1] == 0x21 && cfg[off] >= 9) {
        const uint8_t *r = tud_hid_descriptor_report_cb((uint8_t)inst);
        if (r) hexline("HIDREP", inst, r, (size_t)(cfg[off + 7] | (cfg[off + 8] << 8)));
        inst++;
      }
      off += cfg[off];
    }
  }
  return 0;
}
