import Dispatch
import Foundation
import Testing
@testable import SevenTermCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A pseudo-terminal pair stands in for a cable: SerialPort opens the
/// device end by path, and the test plays the console on the other end.
private struct Cable {
    let console: Int32
    let devicePath: String
    private let deviceEnd: Int32

    init() throws {
        var console: Int32 = -1
        var device: Int32 = -1
        guard openpty(&console, &device, nil, nil, nil) == 0 else { throw SerialError.system("openpty", errno) }
        self.console = console
        deviceEnd = device
        devicePath = String(cString: ttyname(device))
    }

    /// The termios SerialPort applied, as seen from the device end.
    func attributes() -> termios {
        var attributes = termios()
        tcgetattr(deviceEnd, &attributes)
        return attributes
    }

    func consoleWrite(_ text: String) {
        _ = text.utf8CString.withUnsafeBufferPointer { write(console, $0.baseAddress, $0.count - 1) }
    }

    func consoleRead(timeout: Int32 = 2000) -> String {
        var waiter = pollfd(fd: console, events: Int16(POLLIN), revents: 0)
        guard poll(&waiter, 1, timeout) > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(console, &buffer, buffer.count)
        return count > 0 ? String(decoding: buffer[0..<count], as: UTF8.self) : ""
    }

    func unplug() {
        close(console)
        close(deviceEnd)
    }
}

private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []
    private var ended: SerialError??
    func add(_ chunk: [UInt8]) { lock.withLock { bytes += chunk } }
    func end(_ error: SerialError?) { lock.withLock { ended = .some(error) } }
    var text: String { lock.withLock { String(decoding: bytes, as: UTF8.self) } }
    var endState: SerialError?? { lock.withLock { ended } }

    func wait(until condition: () -> Bool) {
        for _ in 0..<200 where !condition() { usleep(10_000) }
    }
}

@Suite struct SerialSettingsTests {
    @Test func defaultsAreTheUsualConsole() {
        let settings = SerialSettings()
        #expect(settings.summary == "9600 8N1")
        #expect(settings.problem == nil)
        #expect(SerialSettings(baudRate: 115200, dataBits: 7, parity: .even, stopBits: 2, flowControl: .hardware).summary
            == "115200 7E2 RTS/CTS")
    }

    @Test func rejectsNonsense() {
        #expect(SerialSettings(baudRate: 0).problem != nil)
        #expect(SerialSettings(dataBits: 9).problem != nil)
        #expect(SerialSettings(stopBits: 3).problem != nil)
    }

    @Test(arguments: [
        SerialSettings(),
        SerialSettings(baudRate: 115200, dataBits: 7, parity: .even, stopBits: 2, flowControl: .hardware),
        SerialSettings(baudRate: 19200, dataBits: 8, parity: .odd, stopBits: 1, flowControl: .software),
        SerialSettings(baudRate: 1200, dataBits: 5),
    ])
    func termiosFlags(settings: SerialSettings) {
        var attributes = termios()
        settings.apply(to: &attributes)
        let c = attributes.c_cflag, i = attributes.c_iflag
        let size = c & tcflag_t(CSIZE)
        let expectedSize: tcflag_t = switch settings.dataBits {
        case 5: tcflag_t(CS5)
        case 6: tcflag_t(CS6)
        case 7: tcflag_t(CS7)
        default: tcflag_t(CS8)
        }
        #expect(size == expectedSize)
        #expect((c & tcflag_t(PARENB) != 0) == (settings.parity != .none))
        #expect((c & tcflag_t(PARODD) != 0) == (settings.parity == .odd))
        #expect((c & tcflag_t(CSTOPB) != 0) == (settings.stopBits == 2))
        #expect((c & SerialSettings.hardwareFlow != 0) == (settings.flowControl == .hardware))
        #expect((i & tcflag_t(IXON) != 0) == (settings.flowControl == .software))
        #expect(c & tcflag_t(CLOCAL | CREAD) == tcflag_t(CLOCAL | CREAD))
        // Raw: no echo, no line editing, no CR/LF translation.
        #expect(attributes.c_lflag & tcflag_t(ECHO | ICANON | ISIG) == 0)
        #expect(i & tcflag_t(ICRNL) == 0)
        #expect(attributes.c_oflag & tcflag_t(OPOST) == 0)
    }

    @Test func codableForStorage() throws {
        let settings = SerialSettings(baudRate: 57600, parity: .even, flowControl: .hardware)
        let decoded = try JSONDecoder().decode(SerialSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}

@Suite struct SerialPortTests {
    @Test func appliesSpeedAndFraming() throws {
        let cable = try Cable()
        let port = try SerialPort(path: cable.devicePath, settings: SerialSettings(baudRate: 115200, parity: .even))
        defer { port.close() }
        let attributes = cable.attributes()
        #expect(SerialPort.reportedSpeed(attributes) == 115200)
        // Framing flags are checked in SerialSettingsTests: a pseudo-terminal
        // has no wire, and Linux drops parity bits on it.
    }

    @Test func bytesBothWays() throws {
        let cable = try Cable()
        let port = try SerialPort(path: cable.devicePath, settings: SerialSettings())
        defer { port.close() }
        let inbox = Inbox()
        port.startReading(on: DispatchQueue(label: "test"), onData: inbox.add, onEnd: inbox.end)

        cable.consoleWrite("Router>")
        inbox.wait { inbox.text == "Router>" }
        #expect(inbox.text == "Router>")

        port.write(Array("enable\r".utf8))
        #expect(cable.consoleRead() == "enable\r") // CR stays CR: raw mode
    }

    @Test func largeWriteIsQueuedNotBlocking() throws {
        let cable = try Cable()
        let port = try SerialPort(path: cable.devicePath, settings: SerialSettings())
        defer { port.close() }
        let paste = Array(repeating: UInt8(ascii: "x"), count: 200_000)
        let start = Date()
        port.write(paste) // nobody reads the console yet, so the buffer fills
        #expect(Date().timeIntervalSince(start) < 0.5)

        var received = 0
        while received < paste.count {
            let chunk = cable.consoleRead(timeout: 2000)
            if chunk.isEmpty { break }
            received += chunk.utf8.count
        }
        #expect(received == paste.count)
    }

    @Test func unplugEndsTheSession() throws {
        let cable = try Cable()
        let port = try SerialPort(path: cable.devicePath, settings: SerialSettings())
        defer { port.close() }
        let inbox = Inbox()
        port.startReading(on: DispatchQueue(label: "test"), onData: inbox.add, onEnd: inbox.end)
        cable.unplug()
        inbox.wait { inbox.endState != nil }
        guard case .some(.some(.notConnected)) = inbox.endState else {
            Issue.record("expected notConnected, got \(String(describing: inbox.endState))")
            return
        }
    }

    @Test func missingPortExplainsItself() {
        #expect(throws: SerialError.notConnected("/dev/cu.nothing-here")) {
            try SerialPort(path: "/dev/cu.nothing-here", settings: SerialSettings())
        }
    }

    @Test func badSettingsRefusedBeforeOpening() {
        #expect(throws: SerialError.self) {
            try SerialPort(path: "/dev/null", settings: SerialSettings(dataBits: 4))
        }
    }

    @Test func closeTwiceIsSafe() throws {
        let cable = try Cable()
        let port = try SerialPort(path: cable.devicePath, settings: SerialSettings())
        port.close()
        port.close()
    }
}
