import Foundation
import ServiceManagement

enum LoginItem {
    private static let initialSetupKey = "didInitialLoginItemSetup"

    /// Always read from `status`, since the user can turn it off in System Settings.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Failed to \(on ? "register" : "unregister", privacy: .public) login item: \(error.localizedDescription, privacy: .public)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// On by default: registers once on first launch, then follows the user's choice.
    /// Registering from a build folder breaks when the path changes, so this only registers from `/Applications`.
    static func registerOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: initialSetupKey) else { return }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            Log.app.info("Running outside /Applications, postponing login item registration")
            return
        }
        setEnabled(true)
        UserDefaults.standard.set(true, forKey: initialSetupKey)
    }
}
