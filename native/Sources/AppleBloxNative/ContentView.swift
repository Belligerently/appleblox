import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case launcher = "Launcher", games = "My Games", installation = "Installation", diagnostics = "Diagnostics"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .launcher: "play.square.stack"
        case .games: "gamecontroller"
        case .installation: "externaldrive"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

struct ContentView: View {
    @Bindable var model: LauncherModel
    @State private var destination: Destination? = .launcher

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("PLAY") {
                    ForEach([Destination.launcher, .games]) { item in
                        Label(item.rawValue, systemImage: item.symbol).tag(item)
                    }
                }
                Section("MANAGE") {
                    ForEach([Destination.installation, .diagnostics]) { item in
                        Label(item.rawValue, systemImage: item.symbol).tag(item)
                    }
                }
            }
            .navigationTitle("AppleBlox")
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("SwiftUI Preview", systemImage: "swift")
                        .font(.caption.weight(.semibold))
                    Text("Version 0.1.0 · Native Mac app")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        } detail: {
            Group {
                switch destination ?? .launcher {
                case .launcher: LauncherView(model: model)
                case .games: GamesView(model: model)
                case .installation: InstallationView(model: model)
                case .diagnostics: DiagnosticsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .navigationTitle((destination ?? .launcher).rawValue)
            .toolbar {
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh)
                        .help("Refresh installation and running status")
                        .disabled(model.isLaunching)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 570)
        .alert("Something needs attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LauncherView: View {
    let model: LauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(eyebrow: "Your next session", title: "Ready when you are.", subtitle: "A familiar launcher. A native Mac experience.")
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 44)).foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Spacer()
                        Label(model.status, systemImage: model.installation == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Roblox Player").font(.title.bold())
                        Text(model.installation.map { "Version \($0.version)" } ?? "Choose your installed Roblox app to get started.")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button {
                            Task { await model.launch() }
                        } label: {
                            Label(model.isLaunching ? "Opening…" : "Launch Roblox", systemImage: "play.fill")
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.installation == nil || model.isLaunching)
                        .keyboardShortcut("r", modifiers: .command)
                        if model.installation == nil {
                            Button("Choose Roblox…", action: model.chooseInstallation)
                        } else {
                            Button("Show in Finder", action: model.revealInstallation).buttonStyle(.bordered)
                        }
                    }
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.07), in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.orange.opacity(0.17)) }

                VStack(alignment: .leading, spacing: 14) {
                    Text("QUICK PLAY").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                    if model.configuration.shortcuts.isEmpty {
                        Label("Save a game in My Games to launch it from here.", systemImage: "bookmark")
                            .foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        ForEach(model.configuration.shortcuts.prefix(3)) { shortcut in
                            HStack {
                                Label(shortcut.name, systemImage: "gamecontroller")
                                Spacer()
                                Button("Play", systemImage: "play.fill") {
                                    Task { await model.launch(shortcut: shortcut) }
                                }
                                .disabled(model.installation == nil || model.isLaunching)
                            }
                            Divider()
                        }
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("The native edition starts here", systemImage: "sparkles").font(.headline)
                        Text("Launching, game shortcuts, and diagnostics are ready to try. FastFlags, mods, updates, and Discord presence will move over in later builds.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            .padding(32).frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
    }
}

struct InstallationView: View {
    let model: LauncherModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: model.status)
                LabeledContent("Version", value: model.installation?.version ?? "Not installed")
                LabeledContent("Application") {
                    Text(model.installation?.url.path ?? "No installation selected")
                        .textSelection(.enabled).multilineTextAlignment(.trailing)
                }
                LabeledContent("Selection", value: model.configuration.customRobloxPath == nil ? "Automatic" : "Custom path preferred")
                HStack {
                    Button("Choose Roblox…", action: model.chooseInstallation).disabled(!model.canSave)
                    Button("Detect Automatically", action: model.useAutomaticDetection).disabled(!model.canSave)
                }
            } header: {
                Text("Roblox Player")
            } footer: {
                Text("Looks in Applications, your personal Applications folder, and macOS’s registered apps. Roblox Studio is excluded.")
            }
            Section("Need Roblox?") {
                Link("Download from Roblox", destination: URL(string: "https://www.roblox.com/download")!)
            }
            Section("Native settings") {
                Text(model.store.directory.path).textSelection(.enabled).font(.callout)
                Text("This preview stores its own settings separately from AppleBlox’s existing configuration.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct DiagnosticsView: View {
    let model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(eyebrow: "A clearer picture", title: "Diagnostics", subtitle: "Installation details and activity from this session.")
            HStack {
                Label(model.isRunning ? "Roblox process detected" : "Roblox is not running", systemImage: "circle.fill")
                    .foregroundStyle(model.isRunning ? .green : .secondary)
                Spacer()
                Button("Open Roblox Logs", systemImage: "folder", action: model.openRobloxLogs)
            }
            List(model.activity) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.message).textSelection(.enabled)
                    Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }
            .listStyle(.inset)
            Text("Activity is kept in memory for this session. Running status updates when you press Refresh.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
