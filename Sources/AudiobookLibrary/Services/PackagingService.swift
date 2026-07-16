import Foundation

enum PackagingError: LocalizedError {
    case noChapterAudio
    case missingFFmpeg
    case encoderFailed(status: Int32, diagnostics: String)

    var errorDescription: String? {
        switch self {
        case .noChapterAudio:
            "No chapter audio is available to package. Generate every chapter before creating the audiobook."
        case .missingFFmpeg:
            "ffmpeg was not found. Install it with Homebrew or set AUDIOBOOK_FFMPEG to its executable path."
        case let .encoderFailed(status, diagnostics):
            "Audio packaging failed with status \(status). \(diagnostics)"
        }
    }
}

func packageAudiobook(
    book: Audiobook,
    repository: LibraryRepository,
    fileManager: FileManager
) throws -> Audiobook {
    guard book.narratedChapters.allSatisfy({ $0.audioURL != nil && $0.duration != nil }) else {
        throw PackagingError.noChapterAudio
    }
    let bookDirectory = repository.bookDirectory(bookID: book.id)
    let packageDirectory = bookDirectory.appending(path: "package", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
    let concatURL = packageDirectory.appending(path: "chapters.txt")
    let metadataURL = packageDirectory.appending(path: "chapters.ffmeta")
    let outputURL = bookDirectory.appending(path: "\(safeFileName(book.title)).m4b")
    try makeConcatFile(chapters: book.narratedChapters, destination: concatURL)
    try makeMetadataFile(book: book, destination: metadataURL)

    let process = Process()
    process.executableURL = try ffmpegURL(fileManager: fileManager)
    process.arguments = [
        "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", concatURL.path(percentEncoded: false),
        "-i", metadataURL.path(percentEncoded: false),
        "-map_metadata", "1",
        "-c:a", "aac",
        "-b:a", "64k",
        "-movflags", "+faststart",
        "-f", "ipod",
        outputURL.path(percentEncoded: false)
    ]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    let diagnostics = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "No diagnostic output."
    guard process.terminationStatus == 0 else {
        throw PackagingError.encoderFailed(status: process.terminationStatus, diagnostics: diagnostics)
    }
    var packagedBook = book
    packagedBook.generatedURL = outputURL
    if book.outputMode == .podcast {
        packagedBook.episodesURL = try packagePodcastEpisodes(book: book, bookDirectory: bookDirectory, fileManager: fileManager)
    }
    packagedBook.status = .readyToListen
    packagedBook.failureMessage = nil
    return packagedBook
}

// Podcast mode: alongside the in-app M4B, emit one tagged M4A per chapter so
// the book drops straight into any podcast or music app.
func packagePodcastEpisodes(book: Audiobook, bookDirectory: URL, fileManager: FileManager) throws -> URL {
    let episodesDirectory = bookDirectory.appending(path: "episodes", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: episodesDirectory, withIntermediateDirectories: true)
    let ffmpeg = try ffmpegURL(fileManager: fileManager)
    let narrated = book.narratedChapters
    for (position, chapter) in narrated.enumerated() {
        guard let audioURL = chapter.audioURL else { throw PackagingError.noChapterAudio }
        let episodeURL = episodesDirectory.appending(
            path: String(format: "%02d %@.m4a", position + 1, safeFileName(chapter.title))
        )
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y",
            "-i", audioURL.path(percentEncoded: false),
            "-c:a", "aac",
            "-b:a", "64k",
            "-metadata", "title=\(chapter.title)",
            "-metadata", "artist=\(book.author)",
            "-metadata", "album=\(book.title)",
            "-metadata", "track=\(position + 1)/\(narrated.count)",
            "-movflags", "+faststart",
            episodeURL.path(percentEncoded: false)
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let diagnostics = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PackagingError.encoderFailed(status: process.terminationStatus, diagnostics: diagnostics)
        }
    }
    return episodesDirectory
}

func ffmpegURL(fileManager: FileManager) throws -> URL {
    if let settingsPath = settingsString(SettingsKey.ffmpeg) {
        let url = URL(fileURLWithPath: (settingsPath as NSString).expandingTildeInPath)
        if fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) { return url }
    }
    if let environmentPath = ProcessInfo.processInfo.environment["AUDIOBOOK_FFMPEG"] {
        let url = URL(fileURLWithPath: environmentPath)
        if fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) { return url }
    }
    let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        .map(URL.init(fileURLWithPath:))
    if let available = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path(percentEncoded: false)) }) {
        return available
    }
    throw PackagingError.missingFFmpeg
}

func makeConcatFile(chapters: [Chapter], destination: URL) throws {
    let lines = try chapters.map { chapter -> String in
        guard let url = chapter.audioURL else { throw PackagingError.noChapterAudio }
        let escapedPath = url.path(percentEncoded: false).replacingOccurrences(of: "'", with: "'\\\\''")
        return "file '\(escapedPath)'"
    }
    try lines.joined(separator: "\n").appending("\n").write(to: destination, atomically: true, encoding: .utf8)
}

func makeMetadataFile(book: Audiobook, destination: URL) throws {
    var cursorMilliseconds = 0
    var lines = [
        ";FFMETADATA1",
        "title=\(escapeMetadata(book.title))",
        "artist=\(escapeMetadata(book.author))",
        "album=\(escapeMetadata(book.title))"
    ]
    for chapter in book.narratedChapters {
        guard let duration = chapter.duration else { throw PackagingError.noChapterAudio }
        let durationMilliseconds = max(1, Int((duration * 1_000).rounded()))
        let end = cursorMilliseconds + durationMilliseconds
        lines += [
            "[CHAPTER]",
            "TIMEBASE=1/1000",
            "START=\(cursorMilliseconds)",
            "END=\(end)",
            "title=\(escapeMetadata(chapter.title))"
        ]
        cursorMilliseconds = end
    }
    try lines.joined(separator: "\n").appending("\n").write(to: destination, atomically: true, encoding: .utf8)
}

func safeFileName(_ value: String) -> String {
    let name = value.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
    return name.isEmpty ? "audiobook" : name
}

func escapeMetadata(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "=", with: "\\=")
        .replacingOccurrences(of: ";", with: "\\;")
        .replacingOccurrences(of: "#", with: "\\#")
        .replacingOccurrences(of: "\n", with: " ")
}
