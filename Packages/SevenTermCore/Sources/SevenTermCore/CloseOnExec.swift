#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Keeps a tab's pseudo-terminal out of every other child process.
///
/// SwiftTerm's `forkpty` hands back the primary descriptor without
/// FD_CLOEXEC, and the child doesn't close what it inherits before exec. So
/// each later ssh, or a local shell and anything run in it, would hold every
/// earlier tab's terminal open: it could read that session's output or type
/// into it, and closing the tab wouldn't hang its shell up. Mark each primary
/// right after its process starts, on the main actor where every fork happens.
public enum CloseOnExec {
    /// Sets FD_CLOEXEC on `fd`. False if the descriptor isn't open.
    @discardableResult
    public static func set(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFD)
        guard flags >= 0 else { return false }
        return fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0
    }
}
