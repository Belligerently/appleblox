import SwiftUI
import AppKit
import AppleBloxCore

struct ModPreviewStrip: View {
    let store: ContentModStore
    let mod: ContentMod
    let revision: Int
    @State private var summary: ModVisualSummary?
    @State private var unavailable = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let summary {
                Text("\(ByteCountFormatter.string(fromByteCount: summary.byteCount, countStyle: .file)) · \(summary.fileCount) files")
                    .font(.caption2).foregroundStyle(.secondary)
                if !summary.thumbnails.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(summary.thumbnails) { thumbnail in
                            if let image = NSImage(data: thumbnail.png) {
                                Image(nsImage: image).resizable().scaledToFit()
                                    .frame(width: 56, height: 42)
                                    .background(.quaternary, in: .rect(cornerRadius: 5)).clipShape(.rect(cornerRadius: 5))
                                    .help(thumbnail.path).accessibilityLabel("Preview of \(thumbnail.path)")
                            }
                        }
                    }
                }
            } else {
                Text(unavailable ? "Preview unavailable. Rescan after fixing the pack." : "Reading local pack details…")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.task(id: revision) {
            summary = nil; unavailable = false
            do {
                let loaded = try await store.visualSummary(mod)
                try Task.checkCancellation()
                summary = loaded
            } catch { if !Task.isCancelled { unavailable = true } }
        }
    }
}
