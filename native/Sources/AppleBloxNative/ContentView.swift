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
    @State private var destination: Destination = .launcher
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.orange).font(.title3)
                Text("AppleBlox").font(.headline)
                Text("NATIVE").font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh)
                    .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 28, height: 28)
                    .compactGlass(cornerRadius: 14).help("Refresh installation and running status")
                    .disabled(model.isLaunching)
            }
            CompactGlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Destination.allCases) { item in
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { destination = item }
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 9).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(destination == item ? Color.orange : Color.secondary)
                        .compactGlass(cornerRadius: 12, active: destination == item)
                        .accessibilityAddTraits(destination == item ? .isSelected : [])
                    }
                }
            }
            Group {
                switch destination {
                case .launcher: LauncherView(model: model, showGames: { destination = .games })
                case .games: GamesView(model: model)
                case .installation: InstallationView(model: model)
                case .diagnostics: DiagnosticsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 18)
        .background { LauncherBackdrop() }
        .nativeWindowMaterial()
        .frame(minWidth: 580, minHeight: 390)
        .alert("Something needs attention", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct LauncherBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if !reduceTransparency {
                LinearGradient(colors: [.orange.opacity(0.13), .clear, .cyan.opacity(0.1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.orange.opacity(0.12), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 330)
            }
        }
        .ignoresSafeArea().allowsHitTesting(false)
    }
}

struct CompactGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else { content() }
    }
}

private struct CompactGlass: ViewModifier {
    let cornerRadius: CGFloat
    let active: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(active ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                               in: .rect(cornerRadius: cornerRadius))
        } else if #available(macOS 26, *) {
            if active {
                content.glassEffect(.regular.tint(.orange.opacity(0.22)).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content.background(.thinMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(active ? 0.2 : 0.06)) }
        }
    }
}

extension View {
    @ViewBuilder func nativeWindowMaterial() -> some View {
        if #available(macOS 15, *) {
            containerBackground(.thinMaterial, for: .window)
        } else {
            background(.regularMaterial)
        }
    }

    func compactGlass(cornerRadius: CGFloat = 12, active: Bool = false) -> some View {
        modifier(CompactGlass(cornerRadius: cornerRadius, active: active))
    }

    @ViewBuilder func launchButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(.orange)
        }
        else { buttonStyle(.borderedProminent) }
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LauncherView: View {
    let model: LauncherModel
    let showGames: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 28, weight: .medium)).foregroundStyle(.orange)
                        .frame(width: 56, height: 56)
                        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 16)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Roblox Player").font(.title2.weight(.semibold))
                        Label(model.status, systemImage: model.installation == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(model.installation == nil ? Color.secondary : .green)
                    }
                    Spacer(minLength: 0)
                    if let installation = model.installation {
                        Text("v" + installation.version).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.035), in: .rect(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.06)) }
                HStack(spacing: 10) {
                    Button {
                        Task { await model.launch() }
                    } label: {
                        Label(model.isLaunching ? "Opening…" : "Launch Roblox", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                    }
                    .launchButtonStyle().controlSize(.large)
                    .disabled(model.installation == nil || model.isLaunching).keyboardShortcut("r", modifiers: .command)
                    Button {
                        if model.installation == nil { model.chooseInstallation() } else { model.revealInstallation() }
                    } label: {
                        Image(systemName: model.installation == nil ? "folder.badge.plus" : "folder").frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain).compactGlass(cornerRadius: 21)
                    .help(model.installation == nil ? "Choose Roblox" : "Show in Finder")
                    .accessibilityLabel(model.installation == nil ? "Choose Roblox" : "Show in Finder")
                }
                HStack {
                    Text("Quick play").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Manage", systemImage: "arrow.up.right", action: showGames)
                        .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if model.configuration.shortcuts.isEmpty {
                    Button(action: showGames) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle").foregroundStyle(.orange)
                            Text("Add your favorite games").font(.callout)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(14).contentShape(.rect)
                    }
                    .buttonStyle(.plain).background(.primary.opacity(0.035), in: .rect(cornerRadius: 14))
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.configuration.shortcuts.prefix(3)) { shortcut in
                            HStack(spacing: 10) {
                                Image(systemName: "gamecontroller").foregroundStyle(.secondary)
                                Text(shortcut.name).font(.callout).lineLimit(1)
                                Spacer()
                                Button("Play", systemImage: "play.fill") { Task { await model.launch(shortcut: shortcut) } }
                                    .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 28, height: 28)
                                    .help("Play " + shortcut.name).accessibilityLabel("Play " + shortcut.name)
                                    .disabled(model.installation == nil || model.isLaunching)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                    }
                    .background(.primary.opacity(0.035), in: .rect(cornerRadius: 14))
                }
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 5) {
                Image(systemName: "swift")
                Text("Native preview · 0.1.1")
                Spacer()
                Text("⌘R to launch")
            }
            .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 8)
        }
    }
}

struct InstallationView: View {
    let model: LauncherModel

    var body: some View {
        Form {
            Section("Roblox Player") {
                LabeledContent("Status", value: model.status)
                LabeledContent("Version", value: model.installation?.version ?? "Not installed")
                LabeledContent("Application") {
                    Text(model.installation?.url.path ?? "No installation selected")
                        .textSelection(.enabled).multilineTextAlignment(.trailing)
                }
                HStack {
                    Button("Choose Roblox…", action: model.chooseInstallation).disabled(!model.canSave)
                    Button("Detect Automatically", action: model.useAutomaticDetection).disabled(!model.canSave)
                    Spacer()
                    Link("Download Roblox", destination: URL(string: "https://www.roblox.com/download")!)
                }
            }
            Section("Native settings") {
                Text(model.store.directory.path).textSelection(.enabled).font(.caption)
                Text("Stored separately from the original AppleBlox settings.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden).controlSize(.small)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
    }
}

struct DiagnosticsView: View {
    let model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PageHeading(title: "Diagnostics", subtitle: model.isRunning ? "Roblox is running" : "Roblox is not running")
                Button("Open Logs", systemImage: "folder", action: model.openRobloxLogs).controlSize(.small)
            }
            List(model.activity) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    Text(entry.message).font(.callout).textSelection(.enabled)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            Text("Session activity · Refresh to update process status").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
