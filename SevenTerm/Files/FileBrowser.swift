import AppKit
import CryptoKit
import Foundation
import Observation
import SevenTermCore

/// One row in either pane.
struct FileRow: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    /// -1 for folders, so they sort together.
    let size: Int64
    let modified: Date
    let mode: String

    var icon: String {
        if isSymlink { return isDirectory ? "folder.badge.questionmark" : "arrow.up.right.square" }
        return isDirectory ? "folder.fill" : "doc"
    }

    var sizeText: String {
        isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// The local or the remote side of a file browser tab.
@MainActor
@Observable
final class FilePane {
    enum Side { case local, remote }

    let side: Side
    var path = ""
    var rows: [FileRow] = []
    var selection: Set<FileRow.ID> = []
    var sortOrder = [KeyPathComparator(\FileRow.name)]
    var isLoading = false
    var error: String?
    var showHidden = false {
        didSet { onShowHiddenChange?() }
    }
    @ObservationIgnored var onShowHiddenChange: (() -> Void)?

    init(side: Side) {
        self.side = side
    }

    /// Folders first, then the chosen column order.
    var sortedRows: [FileRow] {
        let visible = showHidden ? rows : rows.filter { !$0.name.hasPrefix(".") }
        let folders = visible.filter(\.isDirectory).sorted(using: sortOrder)
        let files = visible.filter { !$0.isDirectory }.sorted(using: sortOrder)
        return folders + files
    }

    var selectedRows: [FileRow] {
        rows.filter { selection.contains($0.id) }
    }

    func fullPath(_ row: FileRow) -> String {
        side == .local
            ? URL(fileURLWithPath: path).appendingPathComponent(row.name).path
            : SFTPPath.join(path, row.name)
    }

    var parentPath: String {
        side == .local
            ? URL(fileURLWithPath: path).deletingLastPathComponent().path
            : SFTPPath.parent(path)
    }
}

/// A file transfer, shown in the queue under the panes.
@MainActor
@Observable
final class Transfer: Identifiable {
    enum Direction { case upload, download }
    enum State: Equatable {
        case queued, running, done, skipped, cancelled
        case failed(String)
    }

    let id = UUID()
    let direction: Direction
    let localURL: URL
    let remotePath: String
    let total: UInt64?
    var transferred: UInt64 = 0
    var state: State = .queued
    var sha256: String?
    /// Stops the running transfer; set while it runs.
    @ObservationIgnored var cancelRunning: (() -> Void)?

    init(direction: Direction, localURL: URL, remotePath: String, total: UInt64?) {
        self.direction = direction
        self.localURL = localURL
        self.remotePath = remotePath
        self.total = total
    }

    var name: String { localURL.lastPathComponent }

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(transferred) / Double(total))
    }

    var isFinished: Bool {
        switch state {
        case .queued, .running: false
        default: true
        }
    }

    func cancel() {
        switch state {
        case .queued: state = .cancelled
        case .running: cancelRunning?()
        default: break
        }
    }
}

/// A file browser tab: this Mac on the left, the host on the right, and a
/// transfer queue. ssh makes the connection (`ssh -s host sftp`); 7 Term
/// speaks SFTP over it.
@MainActor
@Observable
final class FileBrowser {
    enum Connection: Equatable {
        case idle, connecting, connected
        case closed(String?)
    }

    let id = UUID()
    let target: SSHTarget
    let keychainHost: (id: String, name: String)?
    let local = FilePane(side: .local)
    let remote = FilePane(side: .remote)
    private(set) var connection: Connection = .idle
    private(set) var transfers: [Transfer] = []
    /// The latest status line ("connecting…", "logging to …", errors).
    var status: String?

    /// Called when the connection ends: nil for a normal close, or why it failed.
    @ObservationIgnored var onEnded: ((String?) -> Void)?
    /// Writes one line to the tab's log while logging is on.
    @ObservationIgnored var log: ((String) -> Void)?

    @ObservationIgnored private var client: SFTPClient?
    @ObservationIgnored private var queueTask: Task<Void, Never>?
    /// "Replace" or "Skip" chosen with "apply to all" for the current batch.
    @ObservationIgnored private var batchConflictChoice: ConflictChoice?

    private static let localPathKey = "fileBrowserLocalPath"

    init(target: SSHTarget, keychainHost: (id: String, name: String)?) {
        self.target = target
        self.keychainHost = keychainHost
        let saved = UserDefaults.standard.string(forKey: Self.localPathKey)
        local.path = saved.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        local.onShowHiddenChange = { [weak self] in self?.refresh(.local) }
        remote.onShowHiddenChange = { [weak self] in self?.refresh(.remote) }
    }

    /// ssh arguments for the sftp subsystem. No terminal, no forwarding:
    /// this connection only ever carries files.
    nonisolated static func sshArguments(for target: SSHTarget) -> [String] {
        ["-x", "-a", "-o", "ClearAllForwardings=yes", "-s"] + target.sshArguments + ["sftp"]
    }

    var hostLabel: String { keychainHost?.name ?? target.displayName }

    func paneFor(_ side: FilePane.Side) -> FilePane { side == .local ? local : remote }

    // MARK: Connection

    func connect() async {
        guard connection != .connecting, connection != .connected else { return }
        connection = .connecting
        status = "connecting to \(target.displayName)…"

        var environment: [String: String] = [:]
        for pair in ChildEnvironment.make(from: ProcessInfo.processInfo.environment)
            + AskPass.environment(hostID: keychainHost?.id ?? "", hostName: hostLabel) {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            environment[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
        }
        var arguments = TerminalSession.Kind.files.arguments(for: target)
        if keychainHost != nil {
            arguments.insert(contentsOf: ["-o", "NumberOfPasswordPrompts=1"], at: 0)
        }

        do {
            let client = try await SFTPClient.launch(
                executable: "/usr/bin/ssh", arguments: arguments, environment: environment)
            self.client = client
            connection = .connected
            status = "connected to \(target.displayName)"
            log?(logStamp() + " connected to \(target.displayName)")
            let home = (try? await client.realPath(".")) ?? "/"
            await load(.remote, path: home)
            await load(.local, path: local.path)
        } catch {
            let message = error.localizedDescription
            connection = .closed(message)
            status = message
            onEnded?(message)
        }
    }

    func disconnect() {
        queueTask?.cancel()
        transfers.filter { !$0.isFinished }.forEach { $0.cancel() }
        client?.close()
        client = nil
        if connection == .connected || connection == .connecting {
            connection = .closed(nil)
        }
    }

    /// An operation failed. If the connection is gone, the tab says so.
    private func report(_ error: Error, in side: FilePane.Side? = nil) {
        let message = error.localizedDescription
        if let client, client.isClosed {
            self.client = nil
            connection = .closed(message)
            status = "disconnected: \(message)"
            onEnded?(message)
            return
        }
        if let side { paneFor(side).error = message } else { status = message }
    }

    // MARK: Browsing

    func refresh(_ side: FilePane.Side) {
        Task { await load(side, path: paneFor(side).path) }
    }

    func go(_ side: FilePane.Side, to path: String) {
        Task { await load(side, path: path) }
    }

    func goUp(_ side: FilePane.Side) {
        go(side, to: paneFor(side).parentPath)
    }

    func load(_ side: FilePane.Side, path: String) async {
        let pane = paneFor(side)
        pane.isLoading = true
        defer { pane.isLoading = false }
        do {
            let rows: [FileRow]
            let resolved: String
            switch side {
            case .local:
                let listing = try await Self.listLocal(path)
                resolved = listing.0
                rows = listing.1
                UserDefaults.standard.set(resolved, forKey: Self.localPathKey)
            case .remote:
                guard let client else { return }
                resolved = try await client.realPath(path)
                rows = try await client.list(resolved).map(Self.row)
            }
            let keep = pane.path == resolved ? pane.selection : []
            pane.path = resolved
            pane.rows = rows
            pane.selection = keep.intersection(rows.map(\.id))
            pane.error = nil
        } catch {
            report(error, in: side)
        }
    }

    nonisolated private static func listLocal(_ path: String) async throws -> (String, [FileRow]) {
        try await Task.detached(priority: .userInitiated) {
            let folder = URL(fileURLWithPath: path).standardizedFileURL
            let keys: [URLResourceKey] = [
                .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [])
            let rows = urls.map { url -> FileRow in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let isLink = values?.isSymbolicLink ?? false
                // A link to a folder opens like a folder.
                let target = isLink ? url.resolvingSymlinksInPath() : url
                let isDirectory = isLink
                    ? (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    : values?.isDirectory ?? false
                return FileRow(
                    name: url.lastPathComponent,
                    isDirectory: isDirectory,
                    isSymlink: isLink,
                    size: isDirectory ? -1 : Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate ?? .distantPast,
                    mode: ""
                )
            }
            return (folder.path, rows)
        }.value
    }

    nonisolated private static func row(_ entry: SFTPEntry) -> FileRow {
        let attributes = entry.attributes
        return FileRow(
            name: entry.name,
            isDirectory: attributes.isDirectory,
            isSymlink: attributes.isSymlink,
            size: attributes.isDirectory ? -1 : Int64(clamping: attributes.size ?? 0),
            modified: attributes.modificationDate ?? .distantPast,
            mode: attributes.modeString
        )
    }

    /// Double-click or Return: folders open in place. A remote file downloads
    /// to the folder shown on the left; a local file opens in its app.
    func open(_ ids: Set<FileRow.ID>, in side: FilePane.Side) {
        let pane = paneFor(side)
        let rows = pane.rows.filter { ids.contains($0.id) }
        if rows.count == 1, let row = rows.first, row.isDirectory || row.isSymlink {
            Task { await openFolderOrLink(row, in: side) }
            return
        }
        switch side {
        case .local:
            rows.forEach { NSWorkspace.shared.open(URL(fileURLWithPath: pane.fullPath($0))) }
        case .remote:
            download(paths: rows.map(pane.fullPath))
        }
    }

    private func openFolderOrLink(_ row: FileRow, in side: FilePane.Side) async {
        let pane = paneFor(side)
        let path = pane.fullPath(row)
        if row.isDirectory {
            await load(side, path: path)
            return
        }
        // A remote symlink: follow it if it points at a folder.
        if side == .remote, let client, let target = try? await client.stat(path), target.isDirectory {
            await load(side, path: path)
        } else if side == .remote {
            download(paths: [path])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    // MARK: Folder and file actions

    func newFolder(in side: FilePane.Side) {
        guard let name = Prompt.text(
            title: "New Folder", message: side == .local ? "In \(local.path)" : "On \(hostLabel) in \(remote.path)",
            initial: "untitled folder", confirm: "Create")
        else { return }
        guard SFTPPath.isSafeName(name) else {
            paneFor(side).error = "“\(name)” can't be used as a folder name."
            return
        }
        let path = side == .local
            ? URL(fileURLWithPath: local.path).appendingPathComponent(name).path
            : SFTPPath.join(remote.path, name)
        Task {
            do {
                if side == .local {
                    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
                } else {
                    try await client?.makeDirectory(path)
                }
                await load(side, path: paneFor(side).path)
                paneFor(side).selection = [name]
            } catch {
                report(error, in: side)
            }
        }
    }

    func rename(_ id: FileRow.ID, in side: FilePane.Side) {
        let pane = paneFor(side)
        guard let row = pane.rows.first(where: { $0.id == id }),
              let name = Prompt.text(title: "Rename", message: row.name, initial: row.name, confirm: "Rename"),
              name != row.name
        else { return }
        guard SFTPPath.isSafeName(name) else {
            pane.error = "“\(name)” can't be used as a name."
            return
        }
        let from = pane.fullPath(row)
        let to = side == .local
            ? URL(fileURLWithPath: pane.path).appendingPathComponent(name).path
            : SFTPPath.join(pane.path, name)
        Task {
            do {
                if side == .local {
                    try FileManager.default.moveItem(atPath: from, toPath: to)
                } else {
                    try await client?.rename(from, to: to)
                }
                await load(side, path: pane.path)
                pane.selection = [name]
            } catch {
                report(error, in: side)
            }
        }
    }

    /// Local items go to the Trash. Remote deletes are permanent, so the
    /// confirmation says so.
    func delete(_ ids: Set<FileRow.ID>, in side: FilePane.Side) {
        let pane = paneFor(side)
        let rows = pane.rows.filter { ids.contains($0.id) }
        guard !rows.isEmpty else { return }
        let what = rows.count == 1 ? "“\(rows[0].name)”" : "\(rows.count) items"
        let confirmed = Prompt.confirm(
            title: side == .local ? "Move \(what) to the Trash?" : "Delete \(what) from \(hostLabel)?",
            message: side == .local
                ? "You can put them back from the Trash."
                : "This can't be undone. Folders are deleted with everything in them.",
            confirm: side == .local ? "Move to Trash" : "Delete",
            destructive: side == .remote)
        guard confirmed else { return }
        Task {
            for row in rows {
                let path = pane.fullPath(row)
                do {
                    if side == .local {
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                    } else if row.isDirectory, !row.isSymlink {
                        try await client?.removeTree(path)
                    } else {
                        try await client?.removeFile(path)
                    }
                    if side == .remote { log?(logStamp() + " deleted \(path)") }
                } catch {
                    report(error, in: side)
                }
            }
            await load(side, path: pane.path)
        }
    }

    // MARK: Transfers

    /// Upload button: the selected local items into the remote folder.
    func uploadSelection() {
        upload(urls: local.selectedRows.map { URL(fileURLWithPath: local.fullPath($0)) })
    }

    /// Download button: the selected remote items into the local folder.
    func downloadSelection() {
        download(paths: remote.selectedRows.map(remote.fullPath))
    }

    /// Local files or folders (from the left pane or from Finder) into the
    /// remote folder that's showing.
    func upload(urls: [URL], into folder: String? = nil) {
        guard let client, !urls.isEmpty else { return }
        let destination = folder ?? remote.path
        Task {
            for url in urls {
                do {
                    try await enqueueUpload(url, into: destination, client: client)
                } catch {
                    report(error, in: .remote)
                }
            }
            startQueue()
        }
    }

    private func enqueueUpload(_ url: URL, into folder: String, client: SFTPClient) async throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        if values.isSymbolicLink == true {
            status = "Skipped \(url.lastPathComponent): symlinks aren't uploaded."
            return
        }
        guard values.isDirectory == true else {
            transfers.append(Transfer(
                direction: .upload, localURL: url,
                remotePath: SFTPPath.join(folder, url.lastPathComponent),
                total: values.fileSize.map(UInt64.init)))
            return
        }
        // A folder: make the folders now, queue the files.
        let top = SFTPPath.join(folder, url.lastPathComponent)
        if try await client.exists(top) == nil { try await client.makeDirectory(top) }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return }
        let base = url.standardizedFileURL.pathComponents.count
        while let item = walker.nextObject() as? URL {
            let itemValues = try item.resourceValues(forKeys: Set(keys))
            if itemValues.isSymbolicLink == true { continue }
            let relative = item.standardizedFileURL.pathComponents.dropFirst(base).joined(separator: "/")
            let remotePath = SFTPPath.join(top, relative)
            if itemValues.isDirectory == true {
                if try await client.exists(remotePath) == nil { try await client.makeDirectory(remotePath) }
            } else {
                transfers.append(Transfer(
                    direction: .upload, localURL: item, remotePath: remotePath,
                    total: itemValues.fileSize.map(UInt64.init)))
            }
        }
    }

    /// Remote files or folders into the local folder that's showing.
    func download(paths: [String], into folder: URL? = nil) {
        guard let client, !paths.isEmpty else { return }
        let destination = folder ?? URL(fileURLWithPath: local.path)
        Task {
            for path in paths {
                do {
                    try await enqueueDownload(path, into: destination, client: client)
                } catch {
                    report(error, in: .local)
                }
            }
            startQueue()
        }
    }

    private func enqueueDownload(_ path: String, into folder: URL, client: SFTPClient) async throws {
        let name = SFTPPath.name(path)
        guard SFTPPath.isSafeName(name) else { throw SFTPError.unsafeName(name) }
        let attributes = try await client.stat(path)
        let local = folder.appendingPathComponent(name)
        guard attributes.isDirectory else {
            transfers.append(Transfer(direction: .download, localURL: local, remotePath: path, total: attributes.size))
            return
        }
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        for item in try await client.walk(path) {
            let target = local.appendingPathComponent(item.relativePath)
            if item.attributes.isDirectory {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else if item.attributes.isRegularFile {
                transfers.append(Transfer(
                    direction: .download, localURL: target, remotePath: item.remotePath,
                    total: item.attributes.size))
            }
            // Symlinks and special files are left out.
        }
    }

    func clearFinished() {
        transfers.removeAll(where: \.isFinished)
    }

    private func startQueue() {
        guard queueTask == nil else { return }
        queueTask = Task {
            while let next = transfers.first(where: { $0.state == .queued }), let client {
                await run(next, client: client)
            }
            batchConflictChoice = nil
            queueTask = nil
        }
    }

    private func run(_ transfer: Transfer, client: SFTPClient) async {
        // Ask before replacing anything.
        let exists: Bool
        switch transfer.direction {
        case .upload: exists = (try? await client.exists(transfer.remotePath)) != nil
        case .download: exists = FileManager.default.fileExists(atPath: transfer.localURL.path)
        }
        var replacing = false
        if exists {
            switch batchConflictChoice ?? askAboutConflict(transfer) {
            case .replace: replacing = true
            case .skip:
                transfer.state = .skipped
                return
            case .stop:
                transfers.filter { $0.state == .queued }.forEach { $0.state = .cancelled }
                return
            }
        }

        transfer.state = .running
        let hasher = StreamingHash()
        let progress = ProgressRelay { [weak transfer] value in transfer?.transferred = value }
        let direction = transfer.direction
        let localURL = transfer.localURL
        let remotePath = transfer.remotePath
        let replace = replacing
        let work = Task.detached { () async throws -> UInt64 in
            switch direction {
            case .upload:
                return try await client.upload(
                    localURL, to: remotePath, replacing: replace,
                    onData: { hasher.update($0) }, progress: { progress.report($0) })
            case .download:
                return try await client.download(
                    remotePath, to: localURL, replacing: replace,
                    onData: { hasher.update($0) }, progress: { progress.report($0) })
            }
        }
        transfer.cancelRunning = { work.cancel() }
        defer { transfer.cancelRunning = nil }
        do {
            let bytes = try await work.value
            transfer.transferred = bytes
            transfer.sha256 = hasher.hexDigest()
            transfer.state = .done
            let arrow = transfer.direction == .upload
                ? "upload \(transfer.localURL.path) -> \(target.displayName):\(transfer.remotePath)"
                : "download \(target.displayName):\(transfer.remotePath) -> \(transfer.localURL.path)"
            log?(logStamp() + " \(arrow) · \(bytes) bytes · sha256 \(transfer.sha256 ?? "")")
            refreshIfShowing(transfer)
        } catch {
            if case SFTPError.cancelled = error {
                transfer.state = .cancelled
            } else if error is CancellationError {
                transfer.state = .cancelled
            } else {
                transfer.state = .failed(error.localizedDescription)
                report(error)
            }
        }
    }

    private func refreshIfShowing(_ transfer: Transfer) {
        switch transfer.direction {
        case .upload where SFTPPath.parent(transfer.remotePath) == remote.path: refresh(.remote)
        case .download where transfer.localURL.deletingLastPathComponent().path == local.path: refresh(.local)
        default: break
        }
    }

    private enum ConflictChoice { case replace, skip, stop }

    private func askAboutConflict(_ transfer: Transfer) -> ConflictChoice {
        let alert = NSAlert()
        let place = transfer.direction == .upload ? "on \(hostLabel)" : "on this Mac"
        alert.messageText = "“\(transfer.name)” already exists \(place)."
        alert.informativeText = transfer.direction == .upload ? transfer.remotePath : transfer.localURL.path
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Stop")
        alert.showsSuppressionButton = transfers.filter { $0.state == .queued }.count > 1
        alert.suppressionButton?.title = "Do this for the rest of these files"
        let choice: ConflictChoice = switch alert.runModal() {
        case .alertFirstButtonReturn: .replace
        case .alertSecondButtonReturn: .skip
        default: .stop
        }
        if alert.suppressionButton?.state == .on, choice != .stop {
            batchConflictChoice = choice
        }
        return choice
    }

    private func logStamp() -> String {
        Date().formatted(.iso8601)
    }

    // MARK: Drag and drop

    /// What a remote row carries when dragged: this browser's id and the path,
    /// so a drop only ever acts on the connection it came from.
    func dragPayload(for row: FileRow) -> String {
        "7term-remote:\(id.uuidString):\(remote.fullPath(row))"
    }

    /// Remote paths dragged from this browser's right pane; anything else is ignored.
    func remotePaths(fromDrop items: [String]) -> [String] {
        let prefix = "7term-remote:\(id.uuidString):"
        return items.compactMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
    }
}

/// SHA-256 of a transfer's bytes, fed in order from the SFTP reader.
private final class StreamingHash: @unchecked Sendable {
    private let lock = NSLock()
    private var hasher = SHA256()

    func update(_ data: Data) {
        lock.withLock { hasher.update(data: data) }
    }

    func hexDigest() -> String {
        lock.withLock { hasher.finalize() }.map { String(format: "%02x", $0) }.joined()
    }
}

/// Passes progress to the main actor at most every 256 KiB, so a fast
/// transfer doesn't flood it with updates.
private final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSent: UInt64 = 0
    private let deliver: @MainActor (UInt64) -> Void

    init(deliver: @escaping @MainActor (UInt64) -> Void) {
        self.deliver = deliver
    }

    func report(_ value: UInt64) {
        let send: Bool = lock.withLock {
            guard value < lastSent || value - lastSent >= 256 * 1024 else { return false }
            lastSent = value
            return true
        }
        guard send else { return }
        let deliver = self.deliver
        Task { @MainActor in deliver(value) }
    }
}

/// Small modal prompts.
@MainActor
enum Prompt {
    static func text(title: String, message: String, initial: String, confirm: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(title: String, message: String, confirm: String, destructive: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .critical : .warning
        let button = alert.addButton(withTitle: confirm)
        button.hasDestructiveAction = destructive
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
