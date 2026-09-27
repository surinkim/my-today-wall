import Combine
import CoreGraphics
import Foundation
import ImageIO

protocol WallpaperApplying {
    /// 연결된 모든 화면에 적용
    func apply(_ url: URL)
    /// 현재 배경이 `url`과 다른 화면에만 적용
    func applyWhereDifferent(_ url: URL)
}

/// 트리거(메뉴·앱 시작·화면 변경)를 받아 받아오기 → 저장 → 적용을 조율한다.
@MainActor
final class WallpaperService: ObservableObject {
    /// 0은 무제한
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

    /// 앱 시작·새로 고침: 새 이미지를 받고, 최신 이미지가 마지막 자동 선택분과 다르면 전 화면에 적용한다.
    /// 같은 최신 이미지로 다시 호출되면 사용자가 고른 이미지를 유지한다.
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

    /// 모니터 연결·해제 시
    func reapplyCurrent() {
        guard let entry = currentEntry else { return }
        applier.apply(store.fileURL(for: entry))
    }

    /// Space 전환 시
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

    /// 목록에 없는 이미지만 받는다. 실패하면 기존 이미지를 그대로 둔다.
    private func fetchAndStoreNew() async {
        let archive: [BingImage]
        do {
            archive = try await client.fetchArchive()
        } catch {
            Log.app.error("Bing 목록 받기 실패: \(String(describing: error), privacy: .public)")
            errorMessage = "Bing에서 이미지 목록을 받지 못했습니다."
            return
        }
        errorMessage = nil

        for image in archive {
            guard image.isWallpaperAllowed else {
                Log.app.info("배경화면 사용 불가(wp=false), 건너뜀: \(image.startdate, privacy: .public)")
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
                    hsh: image.hsh
                ))
                save()
            } catch {
                Log.app.error("이미지 받기 실패: \(image.startdate, privacy: .public) \(String(describing: error), privacy: .public)")
                errorMessage = "일부 이미지를 받지 못했습니다."
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
            Log.app.error("index.json 저장 실패: \(error.localizedDescription, privacy: .public)")
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
