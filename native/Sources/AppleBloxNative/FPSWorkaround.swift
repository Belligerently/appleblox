import AppKit
import AppleBloxCore
import DisplayBridge

@MainActor final class NativeDisplayDriver: TemporaryDisplayDriver {
    private let display = ABTemporaryDisplay()
    var active: Bool { display.isActive }
    func start() throws { try display.begin() }
    func stop() throws { try display.stop() }
}

extension LauncherModel {
    var fpsAvailable: Bool { ABTemporaryDisplay.available }
    func setFPSWorkaround(_ enabled: Bool) {
        guard !isBusy, canSave else { return }
        if !enabled, !stopFPSWorkaround() { return }
        setFeature(\.experimentalFPSWorkaround, enabled)
        fpsStatus = enabled ? "Will start before the next fresh Player launch." : "Off"
    }
    @discardableResult func stopFPSWorkaround() -> Bool {
        guard fpsSession.active else { fpsActive = false; return true }
        do {
            try fpsSession.stop()
            fpsActive = fpsSession.active
            fpsStatus = "Temporary display stopped; original display mode restored."
            return true
        } catch {
            fpsActive = fpsSession.active
            fpsStatus = "Display restoration needs attention."
            report(error)
            return false
        }
    }
    func activatePlayer(_ pid: Int32) {
        guard let player = NSRunningApplication(processIdentifier: pid),
              player.bundleIdentifier == RobloxInstallation.bundleIdentifier else { return }
        player.activate(options: [])
    }
    func quitPlayer(_ pid: Int32) {
        guard playerInstances.ids.contains(pid), let player = NSRunningApplication(processIdentifier: pid),
              player.bundleIdentifier == RobloxInstallation.bundleIdentifier else { return }
        if !player.terminate() { errorMessage = "That Player declined to quit." }
    }
}

@MainActor final class LauncherAppDelegate: NSObject, NSApplicationDelegate {
    var prepareToQuit: (() -> Bool)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareToQuit?() == false ? .terminateCancel : .terminateNow
    }
}
