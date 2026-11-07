import Foundation

// Command-line check for the core logic. Runs fetch, storage, index.json, auto-select and retention
// against the real Bing API, printing instead of setting the wallpaper. Run: scripts/check-core.sh [folder]

struct PrintApplier: WallpaperApplying {
    func apply(_ url: URL) { print("   → apply: \(url.lastPathComponent)") }
    func applyWhereDifferent(_ url: URL) { print("   → apply where different: \(url.lastPathComponent)") }
}

let directory = URL(filePath: CommandLine.arguments.dropFirst().first!, directoryHint: .isDirectory)
let suite = "kr.pe.corecode.MyTodayWall.corecheck"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)

@MainActor
func report(_ service: WallpaperService) {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
        .filter { $0.hasSuffix(".jpg") }.sorted() ?? []
    print("   current=\(service.index.current ?? "-") lastAutoDate=\(service.index.lastAutoDate ?? "-")"
        + " entries=\(service.index.images.count) files=\(files.count)"
        + " prev=\(service.canGoPrevious) next=\(service.canGoNext)"
        + " searchLinks=\(service.index.images.filter { $0.searchLink != nil }.count)"
        + " currentSearch=\(service.currentEntry?.searchURL?.absoluteString ?? "-")"
        + (service.errorMessage.map { " error=\($0)" } ?? ""))
}

Task { @MainActor in
    print("Folder: \(directory.path) market=\(BingClient.systemMarket)")
    let service = WallpaperService(store: ImageStore(directory: directory), applier: PrintApplier(), defaults: defaults)

    print("1) Launch: download + auto-select newest")
    await service.onLaunchOrRefresh()
    report(service)

    print("2) Refresh again: expect no download or apply")
    await service.onLaunchOrRefresh()
    report(service)

    print("3) Previous → Previous → Next")
    service.previous(); service.previous(); service.next()
    report(service)

    print("4) Refresh keeps the picked image")
    await service.onLaunchOrRefresh()
    report(service)

    print("5) Restart (reload index.json)")
    let restarted = WallpaperService(store: ImageStore(directory: directory), applier: PrintApplier(), defaults: defaults)
    report(restarted)

    print("6) Go to oldest, set retention to 3 days: expect old files deleted, current kept")
    while restarted.canGoPrevious { restarted.previous() }
    restarted.retentionDays = 3
    report(restarted)

    defaults.removePersistentDomain(forName: suite)
    exit(0)
}
dispatchMain()
