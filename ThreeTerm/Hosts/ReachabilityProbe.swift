import Foundation
import Network
import ThreeTermCore

/// "Test reachability" in the host form. It asks ssh where the host really
/// is (`ssh -G`, which applies ~/.ssh/config and never connects), then opens
/// and immediately closes a TCP connection to that address and port.
/// It never sends credentials or starts an SSH handshake. The server may log
/// a closed connection.
enum ReachabilityProbe {
    static let timeoutSeconds = 4.0

    /// A sentence describing the result, for display under the button.
    static func describe(_ target: SSHTarget) async -> String {
        guard let effective = await effectiveConfig(for: target) else {
            return "ssh couldn't work out where \(target.host) points. Check the host and ~/.ssh/config."
        }
        let place = "\(effective.hostname):\(effective.port)"
        switch await connect(host: effective.hostname, port: effective.port) {
        case .open:
            return "\(place) is accepting connections."
        case .unreachable(let reason):
            return "Couldn't reach \(place): \(reason)."
        case .timedOut:
            return "No answer from \(place) within \(Int(timeoutSeconds)) seconds."
        }
    }

    // MARK: ssh -G

    static func effectiveConfig(for target: SSHTarget) async -> SSHEffectiveConfig? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = SSHEffectiveConfig.arguments(for: target)
                process.environment = environmentDictionary()
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: SSHEffectiveConfig.parse(String(decoding: data, as: UTF8.self)))
            }
        }
    }

    private static func environmentDictionary() -> [String: String] {
        var result: [String: String] = [:]
        for pair in ChildEnvironment.make(from: ProcessInfo.processInfo.environment) {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { result[String(parts[0])] = String(parts[1]) }
        }
        return result
    }

    // MARK: TCP

    enum Outcome: Equatable, Sendable {
        case open
        case unreachable(String)
        case timedOut
    }

    static func connect(host: String, port: Int) async -> Outcome {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return .unreachable("invalid port")
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        return await withCheckedContinuation { continuation in
            let attempt = Attempt(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    attempt.finish(.open)
                case .waiting(let error), .failed(let error):
                    attempt.finish(.unreachable(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                attempt.finish(.timedOut)
            }
        }
    }

    /// Resumes the continuation exactly once and closes the connection.
    private final class Attempt: @unchecked Sendable {
        private let connection: NWConnection
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Outcome, Never>?

        init(connection: NWConnection, continuation: CheckedContinuation<Outcome, Never>) {
            self.connection = connection
            self.continuation = continuation
        }

        func finish(_ outcome: Outcome) {
            let pending: CheckedContinuation<Outcome, Never>? = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            guard let pending else { return }
            connection.stateUpdateHandler = nil
            connection.cancel()
            pending.resume(returning: outcome)
        }
    }
}
