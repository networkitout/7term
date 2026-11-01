import Darwin
import Foundation
import ThreeTermCore

/// Reads ~/.ssh/config (and the files it includes) for the import sheet.
enum SSHConfigFile {
    static func aliases() -> [SSHConfigAlias] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let scanner = SSHConfigScanner(
            homeDirectory: home,
            readFile: { path in try? String(contentsOfFile: path, encoding: .utf8) },
            expandGlob: expandGlob
        )
        return scanner.aliases(inFileAt: home + "/.ssh/config")
    }

    /// Paths matching a glob pattern, or none when nothing matches.
    @Sendable static func expandGlob(_ pattern: String) -> [String] {
        var matches = glob_t()
        defer { globfree(&matches) }
        guard glob(pattern, 0, nil, &matches) == 0 else { return [] }
        return (0..<Int(matches.gl_pathc)).compactMap { index in
            matches.gl_pathv[index].map { String(cString: $0) }
        }
    }
}
