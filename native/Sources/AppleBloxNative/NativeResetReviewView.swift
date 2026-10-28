import AppKit
import SwiftUI
import AppleBloxCore

extension LauncherModel {
    func finishNativeReset() {
        guard resetCompleted else { return }
        NSApplication.shared.terminate(nil)
    }
    func prepareNativeReset() async {
        guard !isBusy, canSave else { return }
        updateRunningStatus()
        guard !isRunning else { errorMessage = "Quit every Roblox Player before resetting AppleBlox."; return }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        do {
            guard try await !accountVault.hasOriginalLogin() else {
                throw FeatureError.message("Restore the original Player login in Accounts before resetting. Its Keychain recovery copy will not be discarded.")
            }
            resetReview = try await resetService.prepare()
        } catch { report(error) }
    }
    func performNativeReset(_ review: NativeResetPlan) async throws {
        guard !isBusy, canSave else { throw NativeResetError.busy }
        isWorkingFeature = true
        defer { isWorkingFeature = false }
        updateRunningStatus()
        guard !isRunning else { throw FeatureError.message("Roblox started after review. Quit every Player and review reset again.") }
        guard try await !accountVault.hasOriginalLogin() else {
            throw FeatureError.message("Restore the original Player login in Accounts before resetting.")
        }
        guard stopFPSWorkaround() else { throw FeatureError.message("The temporary display could not be restored. Reset has not started.") }
        isResetting = true
        let tasks = [servicesTask, updateTask, gameDetailsTask, presenceArtworkTask, serverActivityTask].compactMap { $0 }
        for task in tasks { task.cancel() }
        gameDetailsLookupID = nil; presenceArtworkLookupID = nil; serverActivityRequestID = nil
        for task in tasks { await task.value }
        servicesTask = nil; servicesTaskID = nil
        await historyWriteTask?.value
        await launcherLogTask?.value
        await discord.disconnect()
        // Recheck after all cancellable writers drain; never reset underneath a fresh Player.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: RobloxInstallation.bundleIdentifier).isEmpty else {
            isResetting = false
            Task { await startServices() }
            throw FeatureError.message("Roblox started while preparing reset. No native files were reset.")
        }
        do {
            let recovery = try await resetService.commit(review) { [accountVault] in try await accountVault.clearForReset() }
            _ = NSWorkspace.shared.open(recovery)
            resetCompleted = true
            resetReview = nil
        } catch {
            if case NativeResetError.rollback = error {
                maintenanceStatus = "Recovery required. Quit the app before moving the archived data folder back."
                // isResetting remains true to gate writes until the user quits.
            } else {
                isResetting = false
                Task { await startServices() }
            }
            throw error
        }
    }
}

struct NativeResetReviewView: View {
    let model: LauncherModel
    let review: NativeResetPlan
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var working = false
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reset AppleBlox Native").font(.title2.bold())
            Text("Archives native data, removes this launcher’s saved Keychain sessions, then quits. The next launch starts fresh.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(review.gameCount) saved games · \(review.profileCount) profiles · \(review.modCount) mods · \(review.accountCount) account records")
                    Text("Native files to archive: \(review.itemNames.joined(separator: ", "))")
                    Text("Recovery folder").font(.headline)
                    Text(review.recoveryDirectory.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Engine/resource backups, settings, themes, imported icons, history and logs stay in that private recovery folder. Account records can be recovered, but saved sessions require signing in again.")
                    Text("Roblox’s installed app, currently applied engine/mod changes and Player login are unchanged. To undo Player changes first, use Engine → Restore Original and Mods → Restore Resources before resetting.")
                    Text("Reset refuses an unrestored original Player login. It only clears AppleBlox’s own credential namespace; other apps’ Keychain items are untouched.")
                }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField("Type RESET to confirm", text: $confirmation).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Type RESET to confirm")
            if let failure { Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Archive, Reset and Quit", role: .destructive) {
                    working = true
                    Task {
                        defer { working = false }
                        do { try await model.performNativeReset(review) }
                        catch { failure = error.localizedDescription }
                    }
                }.disabled(confirmation != "RESET" || model.isBusy)
            }
        }.padding(20).frame(width: 560, height: 450).disabled(working)
        .interactiveDismissDisabled(working)
    }
}
