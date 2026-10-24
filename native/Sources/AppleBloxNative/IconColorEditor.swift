import AppKit
import AppleBloxCore
import SwiftUI

struct IconColorEditor: View {
    let model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var hex: String
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private let presets = [("Rose", "#B12646"), ("Blue", "#0A84FF"), ("Purple", "#BF5AF2"),
                           ("Green", "#30D158"), ("Orange", "#FF9F0A"), ("White", "#FFFFFF")]

    init(model: LauncherModel) {
        self.model = model
        // Seed this sheet's private draft with the last generated color.
        self.hex = model.configuration.features.mods.last(where: { $0.iconColorHex != nil })?.iconColorHex ?? "#B12646"
    }

    private var selected: IconColor? { try? IconColor(hex: hex) }
    private var color: Color {
        guard let selected else { return .secondary }
        return Color(red: Double(selected.red) / 255, green: Double(selected.green) / 255, blue: Double(selected.blue) / 255)
    }
    private var colorBinding: Binding<Color> {
        Binding(get: { color }, set: { value in
            guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
            hex = String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                         Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Roblox Icon Color").font(.title2.bold())
            Text("Recolor supported Roblox interface icons with a generated mod. Enable the pack and apply it from Mods.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                HStack(spacing: 12) {
                    ForEach(["house.fill", "person.fill", "gearshape.fill"], id: \.self) { symbol in
                        Image(systemName: symbol).font(.title2).foregroundStyle(color)
                    }
                }
                .padding(16).background(.quaternary, in: .rect(cornerRadius: 12)).accessibilityLabel("Color sample")
                Spacer(minLength: 0)
                ColorPicker("Icon color", selection: colorBinding, supportsOpacity: false).fixedSize()
            }
            HStack(spacing: 12) {
                ForEach(presets, id: \.0) { name, value in
                    Button { hex = value } label: {
                        let preset = try! IconColor(hex: value)
                        Circle()
                            .fill(Color(red: Double(preset.red) / 255, green: Double(preset.green) / 255, blue: Double(preset.blue) / 255))
                            .frame(width: 26, height: 26)
                            .overlay { Circle().strokeBorder(selected?.hex == value ? Color.primary : .gray.opacity(0.4), lineWidth: selected?.hex == value ? 2 : 1) }
                    }
                    .buttonStyle(.plain).accessibilityLabel("\(name) icon preset").help(name)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text("Hex color").font(.callout)
                TextField("#RRGGBB", text: $hex).font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder).frame(width: 112).accessibilityLabel("Icon hex color")
                if selected == nil { Text("Use six hex digits.").font(.caption).foregroundStyle(.red) }
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if isGenerating { ProgressView().controlSize(.small); Text("Creating color mod…").font(.caption) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isGenerating)
                Button("Create Mod") {
                    guard let selected else { return }
                    isGenerating = true
                    errorMessage = nil
                    Task {
                        do {
                            try await model.createIconColorMod(selected)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                        isGenerating = false
                    }
                }
                .launchButtonStyle().keyboardShortcut(.defaultAction)
                .disabled(selected == nil || isGenerating || model.isBusy || !model.canSave)
            }
        }
        .padding(22).frame(width: 430)
        .disabled(isGenerating)
        .interactiveDismissDisabled(isGenerating)
    }
}
