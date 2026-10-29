//! @NAME@: USB HID boot keyboard on the Pico with embassy-usb (Rust counterpart of the TinyUSB
//! `device_hid` template). Pull GP15 to GND and the board types "hi" + Enter. The report descriptor is
//! the standard boot-keyboard one written out by hand, so no extra crate is needed.
#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_futures::join::join;
use embassy_rp::bind_interrupts;
use embassy_rp::gpio::{Input, Pull};
use embassy_rp::peripherals::USB;
use embassy_rp::usb::{Driver, InterruptHandler};
use embassy_time::Timer;
use embassy_usb::class::hid::{Config as HidConfig, HidBootProtocol, HidSubclass, HidWriter, State};
use embassy_usb::{Builder, Config};
use {defmt_rtt as _, panic_probe as _};

bind_interrupts!(struct Irqs {
    USBCTRL_IRQ => InterruptHandler<USB>;
});

/// Boot keyboard: modifiers, reserved, 6 key codes (input) + 5 LED bits (output).
const KEYBOARD_REPORT: [u8; 63] = [
    0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01,
    0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01, 0x75, 0x08, 0x81, 0x01, 0x95, 0x05, 0x75, 0x01,
    0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x91, 0x02, 0x95, 0x01, 0x75, 0x03, 0x91, 0x01, 0x95, 0x06,
    0x75, 0x08, 0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00, 0xC0,
];
const KEY_H: u8 = 0x0B;
const KEY_I: u8 = 0x0C;
const KEY_ENTER: u8 = 0x28;

#[embassy_executor::main]
async fn main(_spawner: Spawner) {
    let p = embassy_rp::init(Default::default());
    let driver = Driver::new(p.USB, Irqs);
    let mut button = Input::new(p.PIN_15, Pull::Up);

    // 0xc0de/0xcafe is a test VID/PID: use your own for anything you ship
    let mut config = Config::new(0xc0de, 0xcafe);
    config.manufacturer = Some("Box tinyusb");
    config.product = Some("@NAME@");
    config.serial_number = Some("BOX-0002");
    config.max_power = 100;
    config.max_packet_size_0 = 64;

    let mut config_descriptor = [0; 256];
    let mut bos_descriptor = [0; 256];
    let mut msos_descriptor = [0; 256];
    let mut control_buf = [0; 64];
    let mut state = State::new();
    let mut builder = Builder::new(driver, config, &mut config_descriptor, &mut bos_descriptor, &mut msos_descriptor, &mut control_buf);
    let hid_config = HidConfig {
        report_descriptor: &KEYBOARD_REPORT,
        request_handler: None,
        poll_ms: 10,
        max_packet_size: 8,
        hid_subclass: HidSubclass::Boot,
        hid_boot_protocol: HidBootProtocol::Keyboard,
    };
    let mut writer = HidWriter::<_, 8>::new(&mut builder, &mut state, hid_config);
    let mut usb = builder.build();

    let typing = async {
        loop {
            button.wait_for_low().await;
            info!("button: typing");
            for key in [KEY_H, KEY_I, KEY_ENTER] {
                let _ = writer.write(&[0, 0, key, 0, 0, 0, 0, 0]).await; // press
                let _ = writer.write(&[0; 8]).await; // release
            }
            button.wait_for_high().await;
            Timer::after_millis(20).await; // debounce
        }
    };
    join(usb.run(), typing).await;
}
