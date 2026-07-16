import Foundation

struct LibraryRepository: Sendable {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func makeDefault(fileManager: FileManager) throws -> LibraryRepository {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appending(path: "AudiobookLibrary", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return LibraryRepository(rootURL: rootURL)
    }

    func booksURL() -> URL {
        rootURL.appending(path: "library.json")
    }

    func bookDirectory(bookID: UUID) -> URL {
        rootURL.appending(path: "books", directoryHint: .isDirectory).appending(path: bookID.uuidString, directoryHint: .isDirectory)
    }

    func load(fileManager: FileManager) throws -> [Audiobook] {
        let url = booksURL()
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.audiobookLibrary.decode([Audiobook].self, from: data)
    }

    func save(books: [Audiobook], fileManager: FileManager) throws {
        let data = try JSONEncoder.audiobookLibrary.encode(books)
        let url = booksURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

extension JSONDecoder {
    static var audiobookLibrary: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var audiobookLibrary: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
