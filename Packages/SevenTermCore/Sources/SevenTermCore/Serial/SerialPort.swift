import Dispatch
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SerialError: Error, LocalizedError, Equatable {
    case notConnected(String)
    case busy(String)
    case permissionDenied(String)
    case invalidSettings(String)
    case unsupportedSpeed(Int)
    case system(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .notConnected(let path): "\(path) isn't connected. Check the cable, or pick another port."
        case .busy(let path): "\(path) is in use by another app (screen, minicom or another 7 Term tab?)."
        case .permissionDenied(let path): "macOS didn't allow 7 Term to open \(path)."
        case .invalidSettings(let message): message
        case .unsupportedSpeed(let rate): "This adapter or driver doesn't support \(rate) baud."
        case .system(let action, let code): "Couldn't \(action): \(String(cString: strerror(code)))."
        }
    }

    static func from(_ code: Int32, path: String, action: String) -> SerialError {
        switch code {
        case ENOENT, ENXIO, ENODEV: .notConnected(path)
        case EBUSY: .busy(path)
        case EACCES, EPERM: .permissionDenied(path)
        default: .system(action, code)
        }
    }
}

/// An open serial port (a USB console cable, for example).
///
/// Opened in raw mode with the given settings and exclusive access, so no
/// other app can read from it at the same time. Bytes from the device arrive
/// on a dispatch queue; writes are queued so a large paste at 9600 baud never
/// blocks the caller. The original port settings are restored on close.
public final class SerialPort: @unchecked Sendable {
    public let path: String
    public let settings: SerialSettings

    private let fd: Int32
    private var original = termios()
    private let lock = NSLock()
    private var isClosed = false
    private var readSource: DispatchSourceRead?
    private let writeQueue = DispatchQueue(label: "7 Term serial write")

    /// Opens and configures the port. Use the /dev/cu.* path on macOS:
    /// /dev/tty.* waits for a carrier signal that console cables don't send.
    public init(path: String, settings: SerialSettings) throws {
        if let problem = settings.problem { throw SerialError.invalidSettings(problem) }
        self.path = path
        self.settings = settings

        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError.from(errno, path: path, action: "open \(path)") }
        self.fd = fd

        do {
            #if canImport(Darwin)
            // Exclusive access until close.
            guard ioctl(fd, Ioctl.exclusive) == 0 else { throw SerialError.from(errno, path: path, action: "lock \(path)") }
            #endif
            guard tcgetattr(fd, &original) == 0 else { throw SerialError.from(errno, path: path, action: "read settings") }
            var attributes = original
            settings.apply(to: &attributes)
            let customSpeed = try Self.setSpeed(settings.baudRate, in: &attributes)
            guard tcsetattr(fd, TCSANOW, &attributes) == 0 else {
                throw SerialError.from(errno, path: path, action: "apply settings")
            }
            if customSpeed {
                try Self.setCustomSpeed(settings.baudRate, fd: fd)
            }
            tcflush(fd, TCIOFLUSH)
        } catch {
            closeDescriptor(fd)
            throw error
        }
    }

    deinit {
        close()
    }

    /// Starts delivering bytes from the device. `onEnd` is called once when
    /// the port goes away (cable unplugged) or is closed; its error is nil
    /// for a normal close.
    public func startReading(
        on queue: DispatchQueue,
        onData: @escaping @Sendable ([UInt8]) -> Void,
        onEnd: @escaping @Sendable (SerialError?) -> Void
    ) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let fd = self.fd
        let path = self.path
        let ended = Flag()
        source.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count > 0 {
                    onData(Array(buffer[0..<count]))
                    continue
                }
                let code = errno
                if count < 0, code == EAGAIN || code == EINTR { return }
                // 0 bytes or EIO/ENXIO: the device is gone.
                if ended.setOnce() {
                    let error: SerialError? = count == 0 || code == EIO || code == ENXIO
                        ? .notConnected(path)
                        : .system("read from \(path)", code)
                    onEnd(error)
                }
                self?.stopReading()
                return
            }
        }
        lock.withLock { readSource = source }
        source.resume()
    }

    private func stopReading() {
        let source = lock.withLock { () -> DispatchSourceRead? in
            defer { readSource = nil }
            return readSource
        }
        source?.cancel()
    }

    /// Queues bytes to send. Never blocks the caller.
    public func write(_ bytes: [UInt8]) {
        writeQueue.async { [weak self] in
            self?.writeNow(bytes)
        }
    }

    /// Blocks until the bytes are written or the port fails. Waits for room
    /// in the output buffer instead of spinning.
    private func writeNow(_ bytes: [UInt8]) {
        var offset = 0
        while offset < bytes.count {
            if lock.withLock({ isClosed }) { return }
            let written = bytes[offset...].withUnsafeBytes { Foundation.write(fd, $0.baseAddress, $0.count) }
            if written > 0 {
                offset += written
                continue
            }
            let code = errno
            guard written < 0, code == EAGAIN || code == EINTR else { return }
            var waiter = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            _ = poll(&waiter, 1, 1000)
        }
    }

    /// Holds the line in the break state for `milliseconds` (300 by default),
    /// which a Cisco device in ROMMON or password recovery needs at least
    /// 250 of. The length tcsendbreak() picks varies by driver.
    public func sendBreak(milliseconds: Int = 300) throws {
        try writeQueue.sync {
            #if canImport(Darwin)
            guard ioctl(fd, Ioctl.breakOn) == 0 else { throw SerialError.from(errno, path: path, action: "send a break") }
            usleep(useconds_t(milliseconds * 1000))
            guard ioctl(fd, Ioctl.breakOff) == 0 else { throw SerialError.from(errno, path: path, action: "end the break") }
            #else
            guard tcsendbreak(fd, Int32(max(1, milliseconds / 250))) == 0 else {
                throw SerialError.from(errno, path: path, action: "send a break")
            }
            #endif
        }
    }

    /// Restores the port's original settings and closes it. Safe to call twice.
    public func close() {
        let alreadyClosed = lock.withLock { () -> Bool in
            defer { isClosed = true }
            return isClosed
        }
        guard !alreadyClosed else { return }
        stopReading()
        writeQueue.sync {}
        _ = tcsetattr(fd, TCSANOW, &original)
        closeDescriptor(fd)
    }

    // MARK: Speed

    /// Puts a speed termios understands into `attributes`. Returns true when
    /// the real speed has to be set afterwards with an ioctl (macOS only).
    static func setSpeed(_ rate: Int, in attributes: inout termios) throws -> Bool {
        #if canImport(Darwin)
        // On macOS speed_t is the number itself; termios accepts the classic
        // rates, and IOSSIOSPEED sets any other after tcsetattr.
        let classic: Set<Int> = [50, 75, 110, 134, 150, 200, 300, 600, 1200, 1800, 2400, 4800,
                                 9600, 19200, 38400, 57600, 115200, 230400]
        if classic.contains(rate) {
            cfsetspeed(&attributes, speed_t(rate))
            return false
        }
        cfsetspeed(&attributes, speed_t(9600))
        return true
        #else
        guard let code = linuxRates[rate] else { throw SerialError.unsupportedSpeed(rate) }
        cfsetspeed(&attributes, code)
        return false
        #endif
    }

    static func setCustomSpeed(_ rate: Int, fd: Int32) throws {
        #if canImport(Darwin)
        // IOSSIOSPEED = _IOW('T', 2, speed_t) in IOKit/serial/ioss.h
        var speed = speed_t(rate)
        guard ioctl(fd, Ioctl.setSpeed, &speed) == 0 else { throw SerialError.unsupportedSpeed(rate) }
        #endif
    }

    #if !canImport(Darwin)
    static let linuxRates: [Int: speed_t] = [
        50: speed_t(B50), 75: speed_t(B75), 110: speed_t(B110), 134: speed_t(B134), 150: speed_t(B150),
        200: speed_t(B200), 300: speed_t(B300), 600: speed_t(B600), 1200: speed_t(B1200),
        1800: speed_t(B1800), 2400: speed_t(B2400), 4800: speed_t(B4800), 9600: speed_t(B9600),
        19200: speed_t(B19200), 38400: speed_t(B38400), 57600: speed_t(B57600),
        115200: speed_t(B115200), 230400: speed_t(B230400), 460800: speed_t(B460800),
        921600: speed_t(B921600),
    ]
    #endif

    /// The speed termios reports, for tests.
    static func reportedSpeed(_ attributes: termios) -> Int {
        var copy = attributes
        let raw = cfgetospeed(&copy)
        #if canImport(Darwin)
        return Int(raw)
        #else
        return linuxRates.first { $0.value == raw }?.key ?? -1
        #endif
    }
}

#if canImport(Darwin)
/// macOS ioctl numbers. The headers build these with _IO()/_IOW() macros,
/// which Swift can't import. _IO(g, n) = 0x20000000 | g << 8 | n.
private enum Ioctl {
    static let exclusive: UInt = 0x2000_740D   // TIOCEXCL  _IO('t', 13)
    static let breakOff: UInt = 0x2000_747A    // TIOCCBRK  _IO('t', 122)
    static let breakOn: UInt = 0x2000_747B     // TIOCSBRK  _IO('t', 123)
    static let setSpeed: UInt = 0x8008_5402    // IOSSIOSPEED _IOW('T', 2, speed_t), IOKit/serial/ioss.h
}
#endif

/// The C `close`, which SerialPort's own `close()` method would otherwise hide.
private func closeDescriptor(_ fd: Int32) {
    #if canImport(Darwin)
    _ = Darwin.close(fd)
    #else
    _ = Glibc.close(fd)
    #endif
}

/// Set once, from whichever thread gets there first.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    /// True the first time only.
    func setOnce() -> Bool {
        lock.withLock {
            defer { value = true }
            return !value
        }
    }
}
