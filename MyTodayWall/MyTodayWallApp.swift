import SwiftUI

@main
struct MyTodayWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MyTodayWall", systemImage: "photo.on.rectangle") {
            MenuView(service: appDelegate.service)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = WallpaperService(applier: WallpaperApplier())
    private var screenObserver: ScreenObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.registerOnFirstLaunch()
        screenObserver = ScreenObserver(service: service)
        Task { await service.onLaunchOrRefresh() }
    }
}
