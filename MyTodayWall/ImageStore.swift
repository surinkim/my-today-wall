import Foundation

struct ImageEntry: Codable, Equatable {
    let date: String
    let file: String
    let title: String
    let copyright: String
    let hsh: String

    /// "Bears Ears 국립공원... (© 작가)" → "Bears Ears 국립공원..."
    var caption: String {
        copyright.range(of: " (©").map { String(copyright[..<$0.lowerBound]) } ?? copyright
    }

    /// "(© 작가)" 부분
    var credit: String? {
        copyright.range(of: "(©").map { String(copyright[$0.lowerBound...]) }
    }
}

struct ImageIndex: Codable {
    /// 지금 걸려 있는 이미지 날짜
    var current: String?
    /// 마지막으로 자동 선택한 최신 이미지 날짜
    var lastAutoDate: String?
    /// 날짜 오름차순
    var images: [ImageEntry] = []

    func image(for date: String) -> ImageEntry? {
        images.first { $0.date == date }
    }

    mutating func add(_ entry: ImageEntry) {
        images.append(entry)
        images.sort { $0.date < $1.date }
    }
}

/// `~/Pictures/MyTodayWall/`의 이미지 파일과 `index.json`을 관리한다.
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

    /// 파일이 사라진 항목은 목록에서 뺀다. 파일이 없거나 깨졌으면 빈 목록.
    func loadIndex() -> ImageIndex {
        guard let data = try? Data(contentsOf: indexURL) else { return ImageIndex() }
        do {
            var index = try JSONDecoder().decode(ImageIndex.self, from: data)
            index.images = index.images
                .filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
                .sorted { $0.date < $1.date }
            return index
        } catch {
            Log.app.error("index.json 파싱 실패: \(error.localizedDescription, privacy: .public)")
            return ImageIndex()
        }
    }

    func save(_ index: ImageIndex) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    /// 받아 둔 임시 파일을 같은 폴더의 임시 이름으로 옮긴 뒤 최종 이름으로 바꾼다.
    /// 중간에 꺼져도 최종 이름으로 깨진 파일이 남지 않는다.
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

    /// 보관 기간이 지난 이미지를 지운다. 걸려 있는 `current`는 남긴다. `retentionDays`가 0이면 무제한.
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
                Log.app.error("보관 기간 지난 파일 삭제 실패: \(entry.file, privacy: .public)")
            }
            return true
        }
    }
}
