import SwiftUI
import AppleBloxCore

struct SupportBundleReviewView: View {
    let model: LauncherModel
    let draft: SupportBundleDraft
    @Environment(\.dismiss) private var dismiss
    @State private var includeLogs = true
    @State private var selectedFile = "README.txt"
    @State private var errorMessage: String?
    @State private var isSaving = false
    private var files: [SupportBundleFile] { draft.files(includeLogs: includeLogs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Support Bundle").font(.title2.bold())
            Text("Review the exact files below before saving a local ZIP. Account data, names, paths, raw logs and full settings are excluded.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Include saved launcher events", isOn: $includeLogs)
                .disabled(!draft.hasLogs || isSaving)
            if !draft.hasLogs {
                Text("Saved events are unavailable; their existing files were preserved.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Preview", selection: $selectedFile) {
                ForEach(files) { file in Text(file.name).tag(file.name) }
            }
            .disabled(isSaving)
            ScrollView([.horizontal, .vertical]) {
                Text(files.first(where: { $0.name == selectedFile })?.text ?? "")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("Nothing is uploaded automatically.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Button("Save ZIP…") {
                    isSaving = true
                    Task {
                        defer { isSaving = false }
                        do { if try await model.saveSupportBundle(draft, includeLogs: includeLogs) { dismiss() } }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction).disabled(isSaving)
            }
        }
        .padding(20).frame(width: 560, height: 430)
        .interactiveDismissDisabled(isSaving)
        .onChange(of: includeLogs) {
            if !files.contains(where: { $0.name == selectedFile }) { selectedFile = "README.txt" }
        }
    }
}
