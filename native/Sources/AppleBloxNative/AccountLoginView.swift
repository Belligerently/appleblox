import AppleBloxCore
import Observation
import SwiftUI
import WebKit

@MainActor @Observable
private final class LoginSession {
    let store = WKWebsiteDataStore.nonPersistent()
    var host = "www.roblox.com"
    func cookie() async throws -> String {
        let cookies = await store.httpCookieStore.allCookies()
        guard let cookie = cookies.first(where: { $0.name == ".ROBLOSECURITY" && [".roblox.com", "roblox.com", "www.roblox.com"].contains($0.domain.lowercased()) }) else {
            throw FeatureError.message("Complete Roblox sign-in first, then save the signed-in account.")
        }
        return cookie.value
    }
}

struct AccountLoginView: View {
    let model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var session = LoginSession()
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sign in to Roblox").font(.headline)
                Spacer()
                Label(session.host, systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
            Group {
                if #available(macOS 26, *) { ModernLoginBrowser(session: session) }
                else { LegacyLoginBrowser(session: session) }
            }
            .clipShape(.rect(cornerRadius: 12))
            Text("Sign in directly on Roblox’s website. Save stores the validated session in Keychain. This private sign-in window’s web data is discarded when closed.")
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.disabled(saving).keyboardShortcut(.cancelAction)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Save Signed-in Account") {
                    saving = true; message = nil
                    Task {
                        do {
                            let cookie = try await session.cookie()
                            try await model.saveAccount(session: cookie)
                            dismiss()
                        } catch { message = error.localizedDescription }
                        saving = false
                    }
                }
                .launchButtonStyle().disabled(saving).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18).frame(width: 580, height: 640)
        .interactiveDismissDisabled(saving)
    }
}

@available(macOS 26, *)
private struct ModernLoginBrowser: View {
    let session: LoginSession
    @State private var page: WebPage
    init(session: LoginSession) {
        self.session = session
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = session.store
        self.page = WebPage(configuration: configuration, navigationDecider: SecureNavigation())
    }
    var body: some View {
        WebView(page)
            .task { _ = page.load(URL(string: "https://www.roblox.com/login")!) }
            .onChange(of: page.url) { _, url in session.host = url?.host ?? "www.roblox.com" }
    }
    private struct SecureNavigation: WebPage.NavigationDeciding {
        func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
            action.request.url?.scheme == "https" ? .allow : .cancel
        }
    }
}

private struct LegacyLoginBrowser: NSViewRepresentable {
    let session: LoginSession
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = session.store
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "https://www.roblox.com/login")!))
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let session: LoginSession
        init(session: LoginSession) { self.session = session }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { session.host = webView.url?.host ?? "www.roblox.com" }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.scheme == "https" ? .allow : .cancel
        }
    }
}
