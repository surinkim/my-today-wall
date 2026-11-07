import AppKit

/// Reapplies the current image when displays are connected or disconnected and when the Space changes.
@MainActor
final class ScreenObserver {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(service: WallpaperService) {
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak service] in
            service?.reapplyCurrent()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { [weak service] in
            service?.reapplyWhereDifferent()
        }
    }

    deinit {
        for (center, token) in tokens {
            center.removeObserver(token)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        tokens.append((center, token))
    }
}
