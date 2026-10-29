//! @NAME@ (tinyusb-box new zig_usb_cdc): USB CDC-ACM serial port on the Pico with MicroZig's own USB stack (no TinyUSB):
//! every received byte is echoed back upper-cased, like the Rust (embassy-usb) and TinyUSB examples.
//! The USB device is polled from the main loop. The API follows MicroZig 0.17.25's rp2xxx usb_cdc example (MIT).
const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const usb = microzig.core.usb;
const USB_Device = rp2xxx.usb.Polled(.{});
const USB_Serial = usb.drivers.CDC;

var usb_device: USB_Device = undefined;

var usb_controller: usb.DeviceController(.{
    .bcd_usb = USB_Device.max_supported_bcd_usb,
    .device_triple = .unspecified,
    .vendor = USB_Device.default_vendor_id,
    .product = USB_Device.default_product_id,
    .bcd_device = .v1_00,
    .serial = "BOX-ZIG-0001",
    .max_supported_packet_size = USB_Device.max_supported_packet_size,
    .configurations = &.{.{
        .attributes = .{ .self_powered = false },
        .max_current_ma = 100,
        .Drivers = struct { serial: USB_Serial, reset: rp2xxx.usb.ResetDriver(null, 0) },
    }},
}, .{.{
    .serial = .{ .itf_notifi = "@NAME@", .itf_data = "@NAME@ data" },
    .reset = "",
}}) = .init;

pub const std_options = microzig.std_options(.{});

comptime {
    _ = microzig.export_startup();
}

// freestanding: no std.debug panic printer (it pulls in OS I/O)
pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    @breakpoint();
    while (true) {}
}

const pin_config: rp2xxx.pins.GlobalConfiguration = .{
    .GPIO25 = .{ .name = "led", .direction = .out },
};

pub fn main() !void {
    const pins = pin_config.apply();
    pins.led.put(1);
    usb_device = .init();

    var buf: [64]u8 = undefined;
    while (true) {
        usb_device.poll(&usb_controller);
        if (usb_controller.drivers()) |drivers| {
            const n = drivers.serial.read(&buf);
            if (n == 0) continue;
            for (buf[0..n]) |*c| c.* = std.ascii.toUpper(c.*);
            var tx: []const u8 = buf[0..n];
            while (tx.len > 0) {
                tx = tx[drivers.serial.write(tx)..];
                usb_device.poll(&usb_controller);
            }
            while (!drivers.serial.flush()) usb_device.poll(&usb_controller);
            pins.led.toggle();
        }
    }
}
