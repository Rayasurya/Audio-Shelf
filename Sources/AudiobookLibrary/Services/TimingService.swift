import Foundation

// Read-along timing manifest written by the Kokoro worker next to the raw
// chapter audio. Chunk times are chapter-relative seconds.
struct BookTimings: Codable, Equatable, Sendable {
    let version: Int
    let voice: String
    let chapters: [ChapterTimings]
}

struct ChapterTimings: Codable, Equatable, Sendable {
    let index: Int
    let duration: TimeInterval
    let timings: [ChunkTiming]
}

struct ChunkTiming: Codable, Equatable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

func timingsURL(bookID: UUID, repository: LibraryRepository) -> URL {
    repository.bookDirectory(bookID: bookID)
        .appending(path: "raw-audio", directoryHint: .isDirectory)
        .appending(path: "timings.json")
}

func loadBookTimings(bookID: UUID, repository: LibraryRepository, fileManager: FileManager) -> BookTimings? {
    let url = timingsURL(bookID: bookID, repository: repository)
    guard fileManager.fileExists(atPath: url.path(percentEncoded: false)),
          let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(BookTimings.self, from: data)
}
