import Foundation
import Testing
@testable import SevenTermCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite struct CloseOnExecTests {
    /// forkpty's primary descriptor comes back without FD_CLOEXEC, so every
    /// later child (another tab's ssh, a local shell and whatever it runs)
    /// would inherit it and could read or type into that tab.
    @Test func marksAPseudoTerminalDescriptorCloseOnExec() throws {
        var primary: Int32 = -1, secondary: Int32 = -1
        try #require(openpty(&primary, &secondary, nil, nil, nil) == 0)
        defer { close(primary); close(secondary) }
        #expect(fcntl(primary, F_GETFD) & FD_CLOEXEC == 0)

        #expect(CloseOnExec.set(primary))

        #expect(fcntl(primary, F_GETFD) & FD_CLOEXEC != 0)
    }

    @Test func reportsAClosedDescriptor() {
        #expect(!CloseOnExec.set(-1))
    }
}
