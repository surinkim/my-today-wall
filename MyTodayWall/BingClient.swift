import Foundation

/// One image from the `HPImageArchive.aspx` response
struct BingImage: Decodable {
    let startdate: String
    let urlbase: String
    let url: String
    let title: String
    let copyright: String
    /// Search link for the pictured place (e.g. https://www.bing.com/search?q=Kasilof+River+Alaska)
    let copyrightlink: String?
    let hsh: String
    let wp: Bool?

    var isWallpaperAllowed: Bool { wp ?? true }

    /// urlbase "/th?id=OHR.BearsEars_ROW3487899068" → "BearsEars"
    var name: String {
        if let range = urlbase.range(of: "OHR.") {
            let name = urlbase[range.upperBound...]
                .prefix { $0 != "_" }
                .filter { $0.isLetter || $0.isNumber }
            if !name.isEmpty { return String(name) }
        }
        return String(hsh.prefix(8))
    }
}

enum BingClientError: Error {
    case badStatus(Int)
    case notAnImage(String?)
}

struct BingClient {
    static let host = "https://www.bing.com"

    var market = BingClient.systemMarket
    var session: URLSession = .shared

    /// Bing market from the system language and region, e.g. "en-US" or "ko-KR".
    /// Bing falls back to its worldwide (ROW) image for markets it does not serve.
    static var systemMarket: String {
        let locale = Locale.current
        guard let language = locale.language.languageCode?.identifier,
              let region = locale.region?.identifier
        else { return "en-US" }
        return "\(language)-\(region)"
    }

    /// Fetches metadata for the last 8 days (newest first).
    func fetchArchive() async throws -> [BingImage] {
        var components = URLComponents(string: "\(Self.host)/HPImageArchive.aspx")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: "0"),
            URLQueryItem(name: "n", value: "8"),
            URLQueryItem(name: "mkt", value: market),
        ]
        let (data, response) = try await session.data(from: components.url!)
        try Self.checkStatus(response)

        struct Archive: Decodable { let images: [BingImage] }
        return try JSONDecoder().decode(Archive.self, from: data).images
    }

    /// Downloads the UHD original to a temporary file, falling back to 1920x1080.
    func downloadImage(_ image: BingImage) async throws -> URL {
        do {
            return try await download(URL(string: Self.host + image.urlbase + "_UHD.jpg"))
        } catch {
            Log.app.info("UHD download failed, falling back to 1920x1080: \(image.startdate, privacy: .public) \(error.localizedDescription, privacy: .public)")
            return try await download(URL(string: Self.host + image.url))
        }
    }

    private func download(_ url: URL?) async throws -> URL {
        guard let url else { throw URLError(.badURL) }
        let (file, response) = try await session.download(from: url)
        try Self.checkStatus(response)
        guard response.mimeType?.hasPrefix("image/") == true else {
            throw BingClientError.notAnImage(response.mimeType)
        }
        return file
    }

    private static func checkStatus(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BingClientError.badStatus(http.statusCode)
        }
    }
}
