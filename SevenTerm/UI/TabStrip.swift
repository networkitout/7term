import SwiftUI
import SevenTermCore

struct TabStrip: View {
    @Environment(\.chrome) private var chrome
    @Environment(SessionStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            tabs
            if let selected = store.selected {
                LoggingButton(session: selected)
                    .padding(.horizontal, 8)
            }
        }
        .background(chrome.panel)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(store.sessions) { session in
                    TabButton(
                        session: session,
                        isSelected: session.id == store.selectedID,
                        select: { store.selectedID = session.id },
                        close: { store.close(session) },
                        focusTerminal: focusSelectedTerminal
                    )
                }
                Button {
                    store.isQuickConnectPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New connection (⌘T)")
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    /// Hands typing back to the selected terminal after a rename, so the next
    /// keystrokes aren't lost. File browser tabs have no terminal to focus.
    private func focusSelectedTerminal() {
        guard let selected = store.selected, selected.files == nil else { return }
        let terminal = selected.terminalView
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
    }
}

/// Starts or stops logging for the selected tab (⇧⌘L).
private struct LoggingButton: View {
    let session: TerminalSession

    var body: some View {
        Button {
            session.toggleLogging()
        } label: {
            Label(session.isLogging ? "Stop Logging" : "Log",
                  systemImage: session.isLogging ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .disabled(session.state != .running)
        .help(session.isLogging ? "Stop logging this tab (⇧⌘L)" : "Log this tab's output (⇧⌘L)")
    }
}

/// Logging is shown with a shape and a word, never color alone,
/// because red is also 7 Term's accent.
private struct RecordingBadge: View {
    @Environment(\.chrome) private var chrome
    var body: some View {
        Text("REC")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 1.5).fill(chrome.accent))
            .accessibilityHidden(true)
    }
}

private struct TabButton: View {
    @Environment(\.chrome) private var chrome
    let session: TerminalSession
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    let focusTerminal: () -> Void
    @State private var isHovering = false
    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(session.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .leading)
            if session.isLogging {
                RecordingBadge()
            }
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("Close tab (⌘W)")
            .accessibilityLabel("Close \(session.title)")
        }
        .font(Brand.mono(12))
        .padding(.leading, tabColor == nil ? 10 : 12)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(isSelected ? 0.10 : (isHovering ? 0.05 : 0)))
        )
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill((tabColor ?? .clear).opacity(isSelected ? 0.22 : 0.14))
        )
        // The colour is a bar down the leading edge plus a faint tint: a
        // different shape and place from the status dot and the accent
        // underline, so it never reads as a state.
        .overlay(alignment: .leading) {
            if let tabColor {
                Rectangle().fill(tabColor).frame(width: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle().fill(chrome.accent).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        // Alongside the single tap, so selecting stays instant.
        .simultaneousGesture(TapGesture(count: 2).onEnded { isRenaming = true })
        .onHover { isHovering = $0 }
        .help(session.customTitle == nil ? "" : session.defaultTitle)
        .contextMenu { menu }
        .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
            RenameTabPopover(session: session) {
                isRenaming = false
            }
        }
        .onChange(of: isRenaming) { _, renaming in
            if !renaming { focusTerminal() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Rename") { isRenaming = true }
    }

    @ViewBuilder private var menu: some View {
        Button("Rename Tab…") { isRenaming = true }
        Picker("Tab Colour", selection: Binding(
            get: { session.tabColor },
            set: { session.tabColor = $0 }
        )) {
            ForEach(TabColor.allCases, id: \.self) { color in
                Text(color.displayName).tag(color)
            }
        }
        .pickerStyle(.menu)
        if session.customTitle != nil || session.tabColor != .none {
            Button("Reset Name and Colour") {
                session.rename(to: nil)
                session.tabColor = .none
            }
        }
        Divider()
        Button("Close Tab", action: close)
    }

    private var tabColor: Color? {
        session.tabColor.rgb?.swiftUIColor
    }

    private var accessibilityText: String {
        var parts = [session.title, statusText]
        if session.tabColor != .none { parts.append("\(session.tabColor.displayName.lowercased()) tab") }
        if session.isLogging { parts.append("logging") }
        return parts.joined(separator: ", ")
    }

    /// Green while connected. Red is the brand accent, so it never means a state.
    private var statusColor: Color {
        switch session.state {
        case .running: .green
        case .idle, .ended: .gray
        case .failed: .orange
        }
    }

    private var statusText: String {
        switch session.state {
        case .idle: "not started"
        case .running: "connected"
        case .ended: "ended"
        case .failed: "failed to start"
        }
    }
}

/// Rename Tab: Return saves, Esc cancels, an empty name restores the default.
private struct RenameTabPopover: View {
    let session: TerminalSession
    let dismiss: () -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tab name")
                .font(.headline)
            TextField(session.defaultTitle, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($isFocused)
                .onSubmit(save)
            Text("Leave empty to use \u{201C}\(session.defaultTitle)\u{201D}.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: 240, alignment: .leading)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .onAppear {
            text = session.customTitle ?? ""
            isFocused = true
        }
    }

    private func save() {
        session.rename(to: text)
        dismiss()
    }
}
