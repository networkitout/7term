# Serial console (milestone 11): design

Goal: open a USB-to-serial console cable (switch, router, firewall, Raspberry Pi, server BMC) in a 7 Term tab, with the same tabs, logging, themes and text size as ssh. Native: 7 Term opens the port itself; no `screen`, `cu` or `minicom`.

## What the user sees

- **New Host** gets a type switch at the top: **SSH | Serial**. Serial shows: Name, Port, Speed, Data bits, Parity, Stop bits, Flow control, Tags, "Log every session".
- **Port** is a picker of the serial ports macOS sees right now, refreshed when a cable is plugged in or out. A saved port that isn't connected shows as "not connected" rather than disappearing.
- **Defaults:** 9600 baud, 8 data bits, no parity, 1 stop bit (8N1), no flow control. That's the Cisco, Juniper, Aruba and most other consoles. Speed presets: 9600, 19200, 38400, 57600, 115200 (Pi, many newer devices), plus a custom value.
- The sidebar row shows the port and speed (`usbserial-A10K · 9600 8N1`) where ssh hosts show `user@host:port`. Its button says **Open** instead of SSH/SFTP.
- **Quick Connect** gets a Serial option: pick a port, take the defaults.
- In a serial tab: **Session ▸ Send Break** (⌘B), needed for ROMMON and password recovery. The tab title shows the port, and the status dot goes grey when the cable is pulled. ⇧⌘R reopens it.
- Logging, ⌘F search, themes and ⌘+/⌘- work as in any tab, because the bytes go through the same path.

## How it works

**Finding ports.** IOKit: `IOServiceMatching(kIOSerialBSDServiceValue)`, reading `kIOCalloutDeviceKey` for each device (always the `/dev/cu.*` path, never `/dev/tty.*`: opening tty.* waits for a carrier signal that console cables don't send, so it hangs). `IOServiceAddMatchingNotification` for plug and unplug. Also read the USB vendor, product and serial number so the picker can say "FTDI FT232R (A10K3B7)" and not just a device path. Skip Bluetooth and debug ports (`cu.Bluetooth-Incoming-Port`, `cu.debug-console`).

**Remembering a port.** Save the `/dev/cu.*` path plus the USB serial number when the adapter has one. FTDI adapters have serial numbers, so their path stays the same. CH340 and some PL2303 adapters don't, and their path depends on which USB socket they're in (`cu.usbserial-1410`). If the saved path is missing but exactly one adapter with the same vendor and product is connected, offer that one.

**Opening.**
1. `open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)`, then `ioctl(TIOCEXCL)` so no other app can open the port at the same time.
2. Clear `O_NONBLOCK` with `fcntl`.
3. `tcgetattr` and `cfmakeraw`, then set `CLOCAL | CREAD`, the data bits (`CS5`–`CS8`), parity (`PARENB`, `PARODD`) and stop bits (`CSTOPB`).
4. Flow control: `CRTSCTS` for hardware, `IXON | IXOFF` for XON/XOFF.
5. `cfsetspeed` for standard speeds. Use `ioctl(IOSSIOSPEED)` for other values (for example 250000), applied after `tcsetattr`.
6. `VMIN=1, VTIME=0`, then `tcsetattr(TCSANOW)`, then `tcflush(TCIOFLUSH)`.

**Moving bytes.** A `DispatchSource.makeReadSource` on the file descriptor (fd) reads into the same `received(_:)` path TerminalSession uses for ssh, so logging and the terminal view don't change. Keystrokes from `send(source:data:)` are written to the fd. Return sends CR (the terminal default). Consoles expect that.

**Ending.** A read that returns 0, or fails with `ENXIO` or `EIO`, means the cable was pulled: close the fd, mark the session ended, show `[port disconnected · ⇧⌘R to reopen]`. Closing the tab does the same. Restore the original termios settings before `close()`.

**Send Break.** `ioctl(TIOCSBRK)`, wait about 300 ms, then `ioctl(TIOCCBRK)`. `tcsendbreak(fd, 0)`'s length varies by driver, and Cisco needs at least about 250 ms. Write `[break sent]` to the log as a note.

## Code layout

- **Core** (`SevenTermCore/Serial/`, testable): `SerialSettings` (speed, data bits, parity, stop bits, flow control; validation; `8N1`-style summary), `SerialSettings.apply(to: inout termios)`, and `SerialPort` (open, configure, read and write fd, break, close). The tests run against a pseudo-terminal pair from `openpty()`. That works on macOS and in the Linux test container, and checks that the termios flags match the settings.
- **App:** `SerialPortList` (IOKit enumeration plus hot-plug, `@Observable`), `TerminalSession.Kind.serial` (start or stop opens or closes `SerialPort` instead of `LocalProcess`), and the host form's type switch and serial fields.
- **Storage:** GRDB migration v4 adds `host.kind` (`ssh` default, `serial`), `serialPath`, `serialUSBSerial`, `serialVendorProduct`, `baud`, `dataBits`, `parity`, `stopBits`, `flowControl`. `hostname` stays non-null by storing the port path there, so filtering and search still work. Backups carry the serial fields (format version stays 1; they're new optional keys).
- **Sandbox:** none needed (7 Term isn't sandboxed). If it ever is, it needs `com.apple.security.device.serial`.

## Hardware notes

- macOS includes drivers for **FTDI** (FT232R and others) and **WCH CH340/CH341**. Most Cisco-style USB console cables use one of these, so they need nothing extra.
- **Prolific PL2303** and **Silicon Labs CP210x:** support varies by chip and macOS version. If a cable doesn't show up, check System Information ▸ USB for the chip, then install the vendor driver. 7 Term should say this when the port list is empty.
- Cisco's own mini-USB console port needs Cisco's driver. RJ45 console cables don't.

## Build order

1. Core `SerialSettings` + `SerialPort` with openpty tests.
2. `SerialPortList` (IOKit), with a debug list in Settings to check against real adapters.
3. `TerminalSession.Kind.serial` + Quick Connect serial, then try a real cable.
4. Storage migration, host form type switch, sidebar row.
5. Send Break, unplug handling, backup and README.

## Not in scope

Modem control (DTR/RTS toggles beyond flow control), XMODEM/YMODEM file transfer, scripting, telnet to console servers (a later "Telnet" type could reuse most of the serial UI), multiple tabs sharing one port.
