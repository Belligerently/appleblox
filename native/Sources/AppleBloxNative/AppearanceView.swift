import AppleBloxCore
import AppKit
import SwiftUI

struct AppearanceView: View {
    let model: LauncherModel

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: preference(\.theme)) {
                    ForEach(AppTheme.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Reduce animations", isOn: preference(\.reduceMotion))
                Toggle("Use solid backgrounds", isOn: preference(\.reduceTransparency))
                Text("System accessibility preferences are always respected. The original AppleBlox rose palette is used in every theme.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Appearance") }
            Section {
                Toggle("Show game artwork", isOn: preference(\.showGameArtwork))
                Text("Loads public game details and icons from Roblox in My Games. You can still look up names when artwork is off.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("My Games") }
            Section {
                Button("Reset Appearance") { save(AppearanceSettings()) }
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden).controlSize(.small)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .disabled(!model.canSave)
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<AppearanceSettings, Value>) -> Binding<Value> {
        Binding(get: { model.configuration.appearance[keyPath: keyPath] }, set: { value in
            var next = model.configuration.appearance
            next[keyPath: keyPath] = value
            save(next)
        })
    }

    private func save(_ appearance: AppearanceSettings) {
        do {
            var next = model.configuration
            next.appearance = appearance
            try model.persist(next)
        } catch { model.report(error) }
    }
}

struct AppAppearance: ViewModifier {
    let settings: AppearanceSettings

    func body(content: Content) -> some View {
        content
            .environment(\.appReduceMotion, settings.reduceMotion)
            .environment(\.appReduceTransparency, settings.reduceTransparency)
            .onChange(of: settings.theme, initial: true) { _, theme in
                // preferredColorScheme(nil) can retain a previous window override on macOS.
                switch theme {
                case .system: NSApplication.shared.appearance = nil
                case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
                case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
                }
            }
    }
}

extension EnvironmentValues {
    @Entry var appReduceMotion = false
    @Entry var appReduceTransparency = false
}
