import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// How a serial port is configured: speed and framing. The defaults (9600
/// baud, 8 data bits, no parity, 1 stop bit, no flow control) are what
/// Cisco, Juniper, Aruba and most other consoles expect.
public struct SerialSettings: Codable, Hashable, Sendable {
    public enum Parity: String, Codable, CaseIterable, Sendable {
        case none, even, odd

        var letter: String {
            switch self {
            case .none: "N"
            case .even: "E"
            case .odd: "O"
            }
        }
    }

    public enum FlowControl: String, Codable, CaseIterable, Sendable {
        /// Most consoles.
        case none
        /// RTS/CTS lines.
        case hardware
        /// XON/XOFF characters in the data.
        case software
    }

    public var baudRate: Int
    public var dataBits: Int
    public var parity: Parity
    public var stopBits: Int
    public var flowControl: FlowControl

    public init(
        baudRate: Int = 9600,
        dataBits: Int = 8,
        parity: Parity = .none,
        stopBits: Int = 1,
        flowControl: FlowControl = .none
    ) {
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.parity = parity
        self.stopBits = stopBits
        self.flowControl = flowControl
    }

    /// Speeds offered in the picker. Any other positive value can be typed.
    public static let commonRates = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]

    /// "9600 8N1", as consoles are usually described.
    public var summary: String {
        "\(baudRate) \(dataBits)\(parity.letter)\(stopBits)"
            + (flowControl == .none ? "" : flowControl == .hardware ? " RTS/CTS" : " XON/XOFF")
    }

    /// Why these settings can't be used, or nil.
    public var problem: String? {
        if baudRate < 50 || baudRate > 4_000_000 { return "Speed must be between 50 and 4,000,000 baud." }
        if !(5...8).contains(dataBits) { return "Data bits must be 5, 6, 7 or 8." }
        if stopBits != 1, stopBits != 2 { return "Stop bits must be 1 or 2." }
        return nil
    }

    /// Raw mode with this framing and flow control. The speed is set
    /// separately (see `SerialPort`), because macOS sets some speeds with an
    /// ioctl instead of termios.
    public func apply(to attributes: inout termios) {
        cfmakeraw(&attributes)

        var control = attributes.c_cflag
        control |= tcflag_t(CLOCAL | CREAD)
        control &= ~tcflag_t(CSIZE)
        switch dataBits {
        case 5: control |= tcflag_t(CS5)
        case 6: control |= tcflag_t(CS6)
        case 7: control |= tcflag_t(CS7)
        default: control |= tcflag_t(CS8)
        }
        control &= ~tcflag_t(PARENB | PARODD)
        switch parity {
        case .none: break
        case .even: control |= tcflag_t(PARENB)
        case .odd: control |= tcflag_t(PARENB | PARODD)
        }
        if stopBits == 2 { control |= tcflag_t(CSTOPB) } else { control &= ~tcflag_t(CSTOPB) }
        if flowControl == .hardware { control |= Self.hardwareFlow } else { control &= ~Self.hardwareFlow }
        attributes.c_cflag = control

        var input = attributes.c_iflag
        input &= ~tcflag_t(IXON | IXOFF | IXANY)
        if flowControl == .software { input |= tcflag_t(IXON | IXOFF) }
        // Check parity on input only when parity is in use.
        if parity == .none { input &= ~tcflag_t(INPCK) } else { input |= tcflag_t(INPCK) }
        attributes.c_iflag = input

        // Block in read() until at least one byte arrives.
        withUnsafeMutableBytes(of: &attributes.c_cc) { cc in
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
    }

    /// RTS/CTS flow control. macOS spells it as two flags.
    static var hardwareFlow: tcflag_t {
        #if canImport(Darwin)
        tcflag_t(CCTS_OFLOW | CRTS_IFLOW)
        #else
        tcflag_t(CRTSCTS)
        #endif
    }
}
