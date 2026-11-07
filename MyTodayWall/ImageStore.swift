import Foundation

struct ImageEntry: Codable, Equatable {
    let date: String
    let file: String
    let title: String
    let copyright: String
    let hsh: String
    /// Bing `copyrightlink`. nil for images downloaded before this field was added
    var searchLink: String?

    /// "Bears Ears National Monument... (© Photographer)" → "Bears Ears National Monument..."
    var caption: String {
        copyright.range(of: " (©").map { String(copyright[..<$0.lowerBound]) } ?? copyright
    }

    /// The "(© Photographer)" part
    var credit: String? {
        copyright.range(of: "(©").map { String(copyright[$0.lowerBound...]) }
    }

    /// Search link for the place. Without a Bing link, searches Bing for the caption.
    var searchURL: URL? {
        if let searchLink, let url = URL(string: searchLink), url.scheme == "https" {
            return url
        }
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: caption)]
        return components.url
    }
}

struct ImageIndex: Codable {
    /// Date of the image currently set as wallpaper
    var current: String?
    /// Date of the newest image last selected automatically
    var lastAutoDate: String?
    /// Sorted by date, oldest first
    var images: [ImageEntry] = []

    func image(for date: String) -> ImageEntry? {
        images.first { $0.date == date }
    }

    mutating func add(_ entry: ImageEntry) {
        images.append(entry)
        images.sort { $0.date < $1.date }
    }
}

/// Manages the image files and `index.json` in `~/Pictures/MyTodayWall/`.
final class ImageStore {
    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Pictures/MyTodayWall", directoryHint: .isDirectory)

    let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL = ImageStore.defaultDirectory) {
        self.directory = directory
    }

    private var indexURL: URL { directory.appending(path: "index.json") }

    func fileURL(for entry: ImageEntry) -> URL {
        directory.appending(path: entry.file)
    }

    /// Drops entries whose files are gone. Returns an empty index if the file is missing or corrupt.
    func loadIndex() -> ImageIndex {
        guard let data = try? Data(contentsOf: indexURL) else { return ImageIndex() }
        do {
            var index = try JSONDecoder().decode(ImageIndex.self, from: data)
            index.images = index.images
                .filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
                .sorted { $0.date < $1.date }
            return index
        } catch {
            Log.app.error("Failed to parse index.json: \(error.localizedDescription, privacy: .public)")
            return ImageIndex()
        }
    }

    func save(_ index: ImageIndex) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    /// Moves the downloaded temp file to a temporary name in the same folder, then renames it.
    /// If the app quits midway, no broken file is left under the final name.
    func store(downloaded temp: URL, as fileName: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appending(path: ".\(fileName).partial")
        let final = directory.appending(path: fileName)
        try? fileManager.removeItem(at: partial)
        try fileManager.moveItem(at: temp, to: partial)
        if fileManager.fileExists(atPath: final.path) {
            _ = try fileManager.replaceItemAt(final, withItemAt: partial)
        } else {
            try fileManager.moveItem(at: partial, to: final)
        }
    }

    /// Deletes images older than the retention period, keeping `current`. `retentionDays` of 0 means keep forever.
    func removeExpired(from index: inout ImageIndex, retentionDays: Int, now: Date = .now) {
        guard retentionDays > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now)
        else { return }
        let cutoffDate = cutoff.bingDateString
        let current = index.current
        index.images.removeAll { entry in
            guard entry.date < cutoffDate, entry.date != current else { return false }
            do {
                try fileManager.removeItem(at: fileURL(for: entry))
            } catch {
                Log.app.error("Failed to delete expired file: \(entry.file, privacy: .public)")
            }
            return true
        }
    }
}
