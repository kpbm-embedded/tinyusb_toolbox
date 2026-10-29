// @NAME@: from `tinyusb-box new zig_usb_cdc @NAME@` (32_21_tinyusb). MicroZig USB CDC echo for the Raspberry Pi Pico, built with the pinned Zig +
// MicroZig of 32_24_microzig (microzig-box). Same build layout as 32_24's pico_blinky example.
const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{ .rp2xxx = true });

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const fw = mb.add_firmware(.{
        .name = "@NAME@",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    mb.install_firmware(fw, .{}); // .uf2
    mb.install_firmware(fw, .{ .format = .elf });
}
