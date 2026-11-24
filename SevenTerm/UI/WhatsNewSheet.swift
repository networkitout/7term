import SwiftUI
import SevenTermCore

/// The release notes after an update (a sheet on the main window), and in
/// Help ▸ What's New (a window of its own, so it never competes with another
/// sheet).
struct WhatsNewSheet: View {
    @Environment(\.chrome) private var chrome
    let presentation: WhatsNewCenter.Presentation
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.title)
                .font(Brand.mono(15, weight: .semibold))
                .padding([.top, .horizontal], 20)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(presentation.entries.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 10) {
                            // With several versions, say which is which.
                            if presentation.entries.count > 1 {
                                Text("Version \(entry.version)")
                                    .font(Brand.mono(11, weight: .bold))
                                    .foregroundStyle(chrome.accent)
                            }
                            ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(size: 13, weight: .semibold))
                                    Text(item.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            Divider()
            HStack {
                Spacer()
                Button("Continue", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 460)
        .frame(minHeight: 220, idealHeight: 440, maxHeight: 560)
    }
}
