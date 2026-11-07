import Combine
import CoreGraphics
import Foundation
import ImageIO

protocol WallpaperApplying {
    /// Applies to every connected screen
    func apply(_ url: URL)
    /// Applies only to screens whose wallpaper differs from `url`
    func applyWhereDifferent(_ url: URL)
}

/// Takes triggers (menu, app launch, screen changes) and coordinates fetch → store → apply.
@MainActor
final class WallpaperService: ObservableObject {
    /// 0 means keep forever
    static let retentionChoices = [30, 90, 180, 0]
    private static let retentionKey = "retentionDays"

    @Published private(set) var index: ImageIndex
    @Published private(set) var thumbnail: CGImage?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var retentionDays: Int {
        didSet {
            defaults.set(retentionDays, forKey: Self.retentionKey)
            removeExpired()
            save()
        }
    }

    let store: ImageStore
    private let client: BingClient
    private let applier: WallpaperApplying
    private let defaults: UserDefaults

    init(
        client: BingClient = BingClient(),
        store: ImageStore = ImageStore(),
        applier: WallpaperApplying,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.store = store
        self.applier = applier
        self.defaults = defaults

        var index = store.loadIndex()
        if let current = index.current, index.image(for: current) == nil {
            index.current = nil
        }
        self.index = index
        self.retentionDays = defaults.object(forKey: Self.retentionKey) as? Int ?? 90
        updateThumbnail()
    }

    var currentEntry: ImageEntry? {
        index.current.flatMap { index.image(for: $0) }
    }

    private var currentPosition: Int? {
        index.images.firstIndex { $0.date == index.current }
    }

    var canGoPrevious: Bool { currentPosition.map { $0 > 0 } ?? !index.images.isEmpty }
    var canGoNext: Bool { currentPosition.map { $0 < index.images.count - 1 } ?? false }

    /// Launch or refresh: downloads new images and, if the newest differs from the last automatic pick, applies it to all screens.
    /// Called again with the same newest image, it keeps the image the user picked.
    func onLaunchOrRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await fetchAndStoreNew()
        if let latest = index.images.last, index.lastAutoDate != latest.date {
            select(latest)
            index.lastAutoDate = latest.date
        }
        removeExpired()
        save()
    }

    func previous() { move(by: -1) }
    func next() { move(by: 1) }

    /// On display connect or disconnect
    func reapplyCurrent() {
        guard let entry = currentEntry else { return }
        applier.apply(store.fileURL(for: entry))
    }

    /// On Space change
    func reapplyWhereDifferent() {
        guard let entry = currentEntry else { return }
        applier.applyWhereDifferent(store.fileURL(for: entry))
    }

    private func move(by offset: Int) {
        let target = currentPosition.map { $0 + offset } ?? index.images.count - 1
        guard index.images.indices.contains(target) else { return }
        select(index.images[target])
        save()
    }

    private func select(_ entry: ImageEntry) {
        applier.apply(store.fileURL(for: entry))
        index.current = entry.date
        updateThumbnail()
    }

    /// Downloads only images not in the index. On failure, keeps the existing images.
    private func fetchAndStoreNew() async {
        let archive: [BingImage]
        do {
            archive = try await client.fetchArchive()
        } catch {
            Log.app.error("Failed to fetch Bing archive: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "Couldn’t get the image list from Bing.")
            return
        }
        errorMessage = nil

        for image in archive {
            if let position = index.images.firstIndex(where: { $0.date == image.startdate }),
               index.images[position].searchLink == nil {
                index.images[position].searchLink = image.copyrightlink
            }
            guard image.isWallpaperAllowed else {
                Log.app.info("Not allowed as wallpaper (wp=false), skipping: \(image.startdate, privacy: .public)")
                continue
            }
            guard !index.images.contains(where: { $0.date == image.startdate || $0.hsh == image.hsh }) else {
                continue
            }
            do {
                let temp = try await client.downloadImage(image)
                let file = "\(image.startdate)_\(image.name).jpg"
                try store.store(downloaded: temp, as: file)
                index.add(ImageEntry(
                    date: image.startdate,
                    file: file,
                    title: image.title,
                    copyright: image.copyright,
                    hsh: image.hsh,
                    searchLink: image.copyrightlink
                ))
                save()
            } catch {
                Log.app.error("Failed to download image: \(image.startdate, privacy: .public) \(String(describing: error), privacy: .public)")
                errorMessage = String(localized: "Some images couldn’t be downloaded.")
            }
        }
    }

    private func removeExpired() {
        store.removeExpired(from: &index, retentionDays: retentionDays)
    }

    private func save() {
        do {
            try store.save(index)
        } catch {
            Log.app.error("Failed to save index.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateThumbnail() {
        thumbnail = currentEntry.flatMap { Self.makeThumbnail(self.store.fileURL(for: $0)) }
    }

    private static func makeThumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
