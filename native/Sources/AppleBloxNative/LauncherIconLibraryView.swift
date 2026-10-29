import SwiftUI
import AppKit
import AppleBloxCore

struct LauncherIconLibraryView: View {
    let model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingIcon: LauncherIconPreview?
    @State private var confirmApply = false
    @State private var confirmRemove = false
    @State private var confirmRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Launcher Icons").font(.title2.bold())
                Spacer()
                Button("Import…", systemImage: "plus") { Task { await model.importLauncherIcon() } }
                Menu {
                    Button("Reload Library", systemImage: "arrow.clockwise") { Task { await model.loadLauncherIcons() } }
                    Button("Show Icon Files", systemImage: "folder") { Task { await model.revealLauncherIcons() } }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Icon library actions")
            }
            Text("Choose a saved Dock icon. Finder customization is unavailable. The default red logo and blue leaf remain available.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    ForEach(model.launcherIconPreviews) { icon in
                        LauncherIconCard(icon: icon, active: model.selectedLauncherIcon == icon.id,
                            apply: { pendingIcon = icon; confirmApply = true },
                            remove: { pendingIcon = icon; confirmRemove = true })
                    }
                }.padding(2)
            }
            Text(model.launcherIconStatus).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityLabel("Icon status: \(model.launcherIconStatus)")
            HStack {
                Button("Restore Native Default") { confirmRestore = true }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 560, height: 450)
        .disabled(model.isBusy)
        .interactiveDismissDisabled(model.isBusy)
        .task { await model.loadLauncherIcons() }
        .confirmationDialog("Apply this launcher icon?", isPresented: $confirmApply, titleVisibility: .visible) {
            Button("Apply Icon") {
                if let pendingIcon { Task { await model.applyLauncherIcon(pendingIcon.id) } }
            }
        } message: {
            Text("Applies \(pendingIcon?.name ?? "this icon") to this launcher’s Dock icon and saves the choice for future launches. The Finder icon stays unchanged. You can restore Native Default at any time.")
        }
        .confirmationDialog("Remove this imported icon?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove from Library") {
                if let pendingIcon { Task { await model.removeLauncherIcon(pendingIcon.id) } }
            }
        } message: { Text("Removes this imported copy from the library. The original file is unchanged, and the copy is kept in the icon folder’s removed subfolder for recovery.") }
        .confirmationDialog("Restore the native launcher icon?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore Native Default") { Task { await model.applyLauncherIcon(.default) } }
        } message: { Text("Restores the original red-body/blue-leaf Native Dock icon. Imported icons remain in the library.") }
    }
}

private struct LauncherIconCard: View {
    let icon: LauncherIconPreview
    let active: Bool
    let apply: () -> Void
    let remove: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            if let image = NSImage(data: icon.png) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 68, height: 68).accessibilityHidden(true)
            }
            Text(icon.name).font(.caption.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 30)
            HStack(spacing: 6) {
                Button(active ? "Reapply" : "Apply", action: apply)
                    .accessibilityLabel("\(active ? "Reapply selected" : "Apply") \(icon.name)")
                if icon.isCustom {
                    Button("Remove", systemImage: "minus.circle", action: remove).labelStyle(.iconOnly)
                        .disabled(active).help(active ? "Apply another icon before removing this one." : "Remove from library")
                        .accessibilityLabel("Remove \(icon.name)")
                }
            }.controlSize(.small)
        }
        .frame(maxWidth: .infinity).padding(10)
        .background(active ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(active ? Color.accentColor.opacity(0.5) : .clear) }
    }
}
