import AppKit

/// `setDesktopImageURL`은 각 화면의 현재 Space에만 적용된다.
struct WallpaperApplier: WallpaperApplying {
    private let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
        .allowClipping: true,
    ]

    func apply(_ url: URL) {
        for screen in NSScreen.screens {
            set(url, on: screen)
        }
    }

    func applyWhereDifferent(_ url: URL) {
        for screen in NSScreen.screens
        where NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL != url.standardizedFileURL {
            set(url, on: screen)
        }
    }

    private func set(_ url: URL, on screen: NSScreen) {
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        } catch {
            Log.app.error("배경화면 적용 실패 (\(screen.localizedName, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }
}
