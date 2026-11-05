import Darwin

/// Decides whether the process that ran 7 Term as ssh's askpass helper is
/// one 7 Term started itself, before a stored password is released.
///
/// The askpass environment (SEVENTERM_ASKPASS, SEVENTERM_HOST_ID…) can be set
/// by anything, so it isn't proof. The process tree is: ssh forks the helper
/// directly, and 7 Term runs ssh directly (terminal and file browser tabs) or
/// through sftp (sftp tabs). So the helper's ancestors must be exactly
///
///     /usr/bin/ssh → 7 Term
///     /usr/bin/ssh → /usr/bin/sftp → 7 Term
///
/// where "7 Term" is the same executable as the helper. Anything else is
/// refused, including:
/// - another program that runs the 7 Term binary with the askpass variables
///   (its parent isn't ssh), or that runs ssh itself (ssh's parent isn't 7 Term);
/// - a ProxyJump or ProxyCommand hop: that ssh is a child of the outer ssh,
///   not of 7 Term, so a jump host's password prompt never gets the target's
///   stored password.
/// A parent that has exited leaves the helper reparented to launchd, which
/// fails the check too.
///
/// What this doesn't stop: commands the genuine ssh runs itself from
/// ~/.ssh/config (KnownHostsCommand, Match exec, a ProxyCommand that runs
/// $SSH_ASKPASS) are its direct children and pass. Planting one needs write
/// access to ~/.ssh/config, i.e. an already-compromised account.
public enum AskPassCaller {
    public static let ssh = "/usr/bin/ssh"
    public static let sftp = "/usr/bin/sftp"

    /// `ancestors` are executable paths, nearest first (parent, grandparent,
    /// great-grandparent). `app` is the helper's own executable path.
    public static func isTrusted(ancestors: [String], app: String) -> Bool {
        guard !app.isEmpty, ancestors.first == ssh, ancestors.count >= 2 else { return false }
        if ancestors[1] == app { return true }
        return ancestors[1] == sftp && ancestors.count >= 3 && ancestors[2] == app
    }

    /// Whether the helper's real parent is ssh. When it isn't, nothing ssh
    /// would do started the helper, so it shows no dialog at all.
    public static func parentIsSSH() -> Bool {
        ProcessAncestry.executablePath(of: getppid()) == ssh
    }

    /// Checks the running process's real ancestors.
    public static func currentProcessIsTrusted() -> Bool {
        guard let app = ProcessAncestry.executablePath(of: getpid()) else { return false }
        return isTrusted(ancestors: ProcessAncestry.ancestorPaths(of: getpid(), count: 3), app: app)
    }
}

/// Executable paths and parents of running processes, from libproc.
public enum ProcessAncestry {
    /// The executable path the kernel reports for `pid`, or nil if it's gone.
    public static func executablePath(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN; the macro isn't imported.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The parent of `pid`, or nil if it's gone.
    public static func parent(of pid: pid_t) -> pid_t? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// Executable paths of up to `count` ancestors of `pid`, nearest first.
    /// Stops early at launchd (pid 1) or a process that has gone.
    public static func ancestorPaths(of pid: pid_t, count: Int) -> [String] {
        var paths: [String] = []
        var current = pid
        while paths.count < count, let next = parent(of: current), next > 1,
              let path = executablePath(of: next) {
            paths.append(path)
            current = next
        }
        return paths
    }
}
