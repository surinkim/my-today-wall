import AppKit

/// 모니터 연결·해제와 Space 전환을 감지해 현재 이미지를 다시 적용한다.
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
