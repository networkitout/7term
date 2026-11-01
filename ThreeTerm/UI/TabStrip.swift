import SwiftUI

struct TabStrip: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(store.sessions) { session in
                    TabButton(
                        session: session,
                        isSelected: session.id == store.selectedID,
                        select: { store.selectedID = session.id },
                        close: { store.close(session) }
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
        .background(.bar)
    }
}

private struct TabButton: View {
    let session: TerminalSession
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovering = false

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
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("Close tab (⌘W)")
            .accessibilityLabel("Close \(session.title)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isSelected ? 0.10 : (isHovering ? 0.05 : 0)))
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle().fill(Brand.red).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(statusText)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
