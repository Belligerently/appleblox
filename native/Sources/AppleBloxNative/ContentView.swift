import SwiftUI
import AppKit
import Combine

enum Destination: String, CaseIterable, Identifiable {
    case launcher = "Launcher", games = "My Games", engine = "Engine", mods = "Mods", accounts = "Accounts", integrations = "Integrations", history = "History", installation = "Installation", diagnostics = "Diagnostics", appearance = "Appearance", about = "About"
    static let primaryCases: [Destination] = [.launcher, .games, .engine, .mods]
    var id: Self { self }
    var symbol: String {
        switch self {
        case .launcher: "play.square.stack"
        case .games: "gamecontroller"
        case .engine: "slider.horizontal.3"
        case .mods: "shippingbox"
        case .accounts: "person.crop.circle"
        case .integrations: "puzzlepiece.extension"
        case .history: "clock"
        case .installation: "externaldrive"
        case .diagnostics: "waveform.path.ecg"
        case .about: "info.circle"
        case .appearance: "paintpalette"
        }
    }
}

struct ContentView: View {
    @Bindable var model: LauncherModel
    @State private var destination: Destination = .launcher
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }
    @Environment(\.colorScheme) private var colorScheme
    @State private var refreshCount = 0

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 9) {
                AppleBloxForkLogo().frame(width: 25, height: 27)
                Text("AppleBlox").font(.headline)
                Text("NATIVE").font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                Button {
                    refreshCount += 1
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(reduceMotion ? 0 : Double(refreshCount) * 360))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: refreshCount)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).compactGlass(cornerRadius: 14)
                .help("Refresh installation and running status").accessibilityLabel("Refresh")
                .disabled(model.isBusy)
            }
            NavigationTabs(selection: $destination)
            ZStack(alignment: .topLeading) {
                pageContent
                    .transaction { $0.animation = nil }
                    .id(destination)
                    .transition(reduceMotion ? .identity : .opacity)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: destination)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 18)
        .foregroundStyle(AppleBloxTheme.foreground(for: colorScheme))
        .background { LauncherBackdrop() }
        .nativeWindowMaterial()
        .frame(minWidth: 580, minHeight: 390)
        .task { await model.startServices() }
        .onOpenURL { model.receiveLaunchURL($0) }
        .onReceive(Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
        )) { _ in model.updateRunningStatus() }
        .alert("Something needs attention", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Open this Roblox launch request?", isPresented: Binding(get: { model.pendingLink != nil }, set: { if !$0 { model.pendingLink = nil } }), titleVisibility: .visible) {
            Button("Open in Roblox") {
                if let link = model.pendingLink {
                    model.pendingLink = nil
                    let shortcut = model.configuration.shortcuts.first { $0.placeID == link.placeID }
                    Task { await model.launch(shortcut: shortcut, link: link) }
                }
            }
            .disabled(model.isBusy || model.installation == nil)
        } message: { Text("Your enabled engine profiles, mods, and selected account will be used for a fresh Player session.") }
    }

    private var pageContent: some View {
        Group {
            switch destination {
            case .launcher: LauncherView(model: model, showGames: { destination = .games })
            case .games: GamesView(model: model)
            case .engine: EngineView(model: model)
            case .mods: ModsView(model: model)
            case .accounts: AccountsView(model: model)
            case .integrations: IntegrationsView(model: model)
            case .history: HistoryView(model: model)
            case .installation: InstallationView(model: model)
            case .diagnostics: DiagnosticsView(model: model)
            case .about: AboutView()
            case .appearance: AppearanceView(model: model)
            }
        }
    }
}

private struct NavigationTabs: View {
    @Environment(\.nativePalette) private var palette
    @Binding var selection: Destination
    @Namespace private var selectionAnimation
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Destination.primaryCases) { item in
                Button { selection = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == item ? palette.selectedText(colorScheme) : Color.secondary)
                .background {
                    if selection == item {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(palette.accent.opacity(colorScheme == .dark ? 0.32 : 0.14))
                            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(palette.accent.opacity(0.24)) }
                            .matchedGeometryEffect(id: "selected-tab", in: selectionAnimation)
                    }
                }
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
            Menu {
                ForEach(Destination.allCases.filter { !Destination.primaryCases.contains($0) }) { item in
                    Button(item.rawValue, systemImage: selection == item ? "checkmark" : item.symbol) { selection = item }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .menuStyle(.borderlessButton).accessibilityLabel("More pages")
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 6)
            .background {
                if !Destination.primaryCases.contains(selection) {
                    RoundedRectangle(cornerRadius: 10).fill(palette.accent.opacity(colorScheme == .dark ? 0.32 : 0.14))
                        .matchedGeometryEffect(id: "selected-tab", in: selectionAnimation)
                }
            }
        }
        .padding(4)
        .compactGlass(cornerRadius: 14)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25, extraBounce: 0), value: selection)
    }
}

struct LauncherBackdrop: View {
    @Environment(\.nativePalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.appReduceTransparency) private var appReduceTransparency
    private var reduceTransparency: Bool { systemReduceTransparency || appReduceTransparency }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        palette.background(colorScheme)
            .opacity(reduceTransparency ? 1 : 0.88)
            .ignoresSafeArea().allowsHitTesting(false)
    }
}

private struct CompactGlass: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.appReduceTransparency) private var appReduceTransparency
    private var reduceTransparency: Bool { systemReduceTransparency || appReduceTransparency }

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor),
                               in: .rect(cornerRadius: cornerRadius))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(),
                                in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.thinMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(0.06)) }
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

    func compactGlass(cornerRadius: CGFloat = 12) -> some View {
        modifier(CompactGlass(cornerRadius: cornerRadius))
    }

    @ViewBuilder func launchButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent).buttonBorderShape(.capsule)
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
    @Environment(\.nativePalette) private var palette
    let model: LauncherModel
    let showGames: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }
    @State private var confirmQuit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    AppleBloxForkLogo()
                        .frame(width: 38, height: 41)
                        .frame(width: 56, height: 56)
                        .background(palette.accent.opacity(0.1), in: .rect(cornerRadius: 16)).accessibilityHidden(true)
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
                .background(palette.card(colorScheme).opacity(0.75), in: .rect(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.06)) }
                HStack(spacing: 10) {
                    Button {
                        Task { await model.launch() }
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                if model.isLaunching {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                            }
                            .frame(width: 16, height: 16)
                            Text(model.isLaunching ? "Opening…" : "Launch Roblox")
                                .contentTransition(.opacity)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.isLaunching)
                    }
                    .launchButtonStyle().controlSize(.large)
                    .disabled(model.installation == nil || model.isBusy).keyboardShortcut("r", modifiers: .command)
                    if model.isRunning {
                        Button("Quit Roblox", systemImage: "stop.fill") { confirmQuit = true }
                            .controlSize(.small).disabled(model.isBusy)
                    }
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
                            Image(systemName: "plus.circle").foregroundStyle(palette.accent)
                            Text("Add your favorite games").font(.callout)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(14).contentShape(.rect)
                    }
                    .buttonStyle(.plain).background(palette.card(colorScheme).opacity(0.75), in: .rect(cornerRadius: 14))
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
                                    .disabled(model.installation == nil || model.isBusy)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                    }
                    .background(palette.card(colorScheme).opacity(0.75), in: .rect(cornerRadius: 14))
                }
            }
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("Quit Roblox?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Quit Roblox", role: .destructive, action: model.quitRoblox)
        } message: { Text("This asks all running Roblox Player windows to close.") }
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
                    Button("Open Contents", action: model.openPlayerContents).disabled(model.installation == nil)
                    Spacer()
                    Link("Download Roblox", destination: URL(string: "https://www.roblox.com/download")!)
                }
            }
            Section("Native settings") {
                Text(model.store.directory.path).textSelection(.enabled).font(.caption)
                Text("Stored separately from the original AppleBlox settings.").font(.caption).foregroundStyle(.secondary)
            }
            UpdateControls(model: model)
        }
        .formStyle(.grouped).scrollContentBackground(.hidden).controlSize(.small)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
    }
}

struct DiagnosticsView: View {
    let model: LauncherModel
    @State private var confirmClearCache = false
    @State private var showNativeGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PageHeading(title: "Diagnostics", subtitle: model.isRunning ? "Roblox is running" : "Roblox is not running")
                Button("Roblox Logs", systemImage: "folder", action: model.openRobloxLogs).controlSize(.small)
                Menu {
                    Button("Export Support Bundle…", systemImage: "archivebox") { Task { await model.prepareSupportBundle() } }
                        .disabled(model.isBusy)
                    Button("Open Launcher Logs", systemImage: "folder") { Task { await model.openLauncherLogs() } }
                    Button("Copy Diagnostics", systemImage: "doc.on.doc") { Task { await model.copyDiagnostics() } }
                    Button("Reset AppleBlox Native…", systemImage: "arrow.counterclockwise") { Task { await model.prepareNativeReset() } }
                        .disabled(model.isBusy || !model.canSave)
                    Button("Clear Game Details Cache…", systemImage: "arrow.clockwise") { confirmClearCache = true }
                        .disabled(model.isBusy)
                    Divider()
                    Button("Documentation…", systemImage: "book") { showNativeGuide = true }
                    Button("Open Player Contents", systemImage: "folder", action: model.openPlayerContents)
                        .disabled(model.installation == nil || model.isBusy)
                    Button("Open Native Data Folder", systemImage: "folder", action: model.showNativeData)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Diagnostics actions")
            }
            List(model.activity) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    Text(entry.message).font(.callout).textSelection(.enabled)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            Text(model.maintenanceStatus.isEmpty ? model.launcherLogStatus : model.maintenanceStatus)
                .font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .sheet(isPresented: $showNativeGuide) { NativeGuideView() }
        .sheet(item: Binding(get: { model.supportBundleReview }, set: { model.supportBundleReview = $0 })) { draft in
            SupportBundleReviewView(model: model, draft: draft)
        }
        .sheet(item: Binding(get: { model.resetReview }, set: { model.resetReview = $0 }), onDismiss: { model.finishNativeReset() }) { review in
            NativeResetReviewView(model: model, review: review)
        }
        .confirmationDialog("Clear saved game details?", isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Clear Game Details Cache") { Task { await model.clearGameDetailsCache() } }
        } message: {
            Text("Clears cached game names, creators, and thumbnail links. Saved games, accounts, profiles, mods, backups, and Roblox files stay intact. New lookups can refill the cache; downloaded images in the macOS image cache are unaffected.")
        }
    }
}
