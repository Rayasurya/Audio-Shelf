import Foundation
import Testing
@testable import AudiobookLibrary

private func fixtureURL() throws -> URL {
    try #require(Bundle.module.url(forResource: "test-book", withExtension: "txt"))
}

@Test func importDetectsChaptersAndTitle() throws {
    let source = try importSource(url: fixtureURL(), fileManager: .default)
    #expect(source.title == "The Lighthouse at Quiet Harbor")
    #expect(source.chapters.count == 3)
    #expect(source.chapters.map(\.title) == ["Chapter One", "Chapter Two", "Chapter Three"])
    #expect(source.chapters.allSatisfy { $0.text.count > 80 })
}

// Exercises the real Kokoro worker and ffmpeg, so it needs the local
// kokoro-tts/venv2 environment and takes a couple of minutes.
@Test func generateAndPackageAudiobookEndToEnd() throws {
    let fileManager = FileManager.default
    let libraryRoot = fileManager.temporaryDirectory
        .appending(path: "audiobook-e2e-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: libraryRoot) }
    let repository = LibraryRepository(rootURL: libraryRoot)

    let source = try importSource(url: fixtureURL(), fileManager: fileManager)
    let book = Audiobook(
        id: UUID(),
        title: source.title,
        author: source.author,
        sourceURL: try fixtureURL(),
        chapters: source.chapters,
        status: .readyForReview,
        generatedURL: nil,
        playbackSeconds: 0,
        lastOpenedAt: nil,
        createdAt: Date(),
        failureMessage: nil
    )

    let progressCollector = ProgressCollector()
    let generated = try generateKokoroAudio(
        book: book,
        repository: repository,
        fileManager: fileManager,
        progressHandler: { progressCollector.record($0) }
    )
    #expect(progressCollector.snapshot().count == 3)
    for chapter in generated.chapters {
        let audioURL = try #require(chapter.audioURL)
        #expect(fileManager.fileExists(atPath: audioURL.path(percentEncoded: false)))
        let duration = try #require(chapter.duration)
        #expect(duration > 1)
    }

    let packaged = try packageAudiobook(book: generated, repository: repository, fileManager: fileManager)
    let outputURL = try #require(packaged.generatedURL)
    #expect(outputURL.pathExtension == "m4b")
    #expect(packaged.status == .readyToListen)
    let fileSize = try #require(
        try fileManager.attributesOfItem(atPath: outputURL.path(percentEncoded: false))[.size] as? Int
    )
    #expect(fileSize > 10_000)

    let probe = try probeChapters(outputURL: outputURL)
    #expect(probe.chapterTitles == ["Chapter One", "Chapter Two", "Chapter Three"])
    #expect(probe.durationSeconds > 10)

    // Read-along timing manifest: every chapter narrated from now on carries
    // chunk-level timestamps whose spans cover the chapter audio.
    let bookTimings = try #require(loadBookTimings(bookID: book.id, repository: repository, fileManager: fileManager))
    #expect(bookTimings.chapters.count == 3)
    for chapterTimings in bookTimings.chapters {
        #expect(!chapterTimings.timings.isEmpty)
        let lastEnd = try #require(chapterTimings.timings.last?.end)
        #expect(abs(lastEnd - chapterTimings.duration) < 0.05)
    }

    // Resume: re-running generation must reuse the fingerprinted chapter audio
    // instead of narrating again — verified by unchanged modification dates.
    let audioDirectory = repository.bookDirectory(bookID: book.id).appending(path: "raw-audio", directoryHint: .isDirectory)
    let firstRunDate = try #require(
        try fileManager.attributesOfItem(
            atPath: audioDirectory.appending(path: "chapter-001.wav").path(percentEncoded: false)
        )[.modificationDate] as? Date
    )
    let resumed = try generateKokoroAudio(book: book, repository: repository, fileManager: fileManager, progressHandler: { _ in })
    #expect(resumed.chapters.allSatisfy { $0.audioURL != nil })
    let secondRunDate = try #require(
        try fileManager.attributesOfItem(
            atPath: audioDirectory.appending(path: "chapter-001.wav").path(percentEncoded: false)
        )[.modificationDate] as? Date
    )
    #expect(firstRunDate == secondRunDate)
}

private struct ProbeResult {
    let chapterTitles: [String]
    let durationSeconds: Double
}

private func probeChapters(outputURL: URL) throws -> ProbeResult {
    let ffmpeg = try ffmpegURL(fileManager: .default)
    let ffprobe = ffmpeg.deletingLastPathComponent().appending(path: "ffprobe")
    let process = Process()
    process.executableURL = ffprobe
    process.arguments = [
        "-v", "error",
        "-show_entries", "format=duration:chapter_tags=title",
        "-of", "json",
        outputURL.path(percentEncoded: false)
    ]
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    try process.run()
    process.waitUntilExit()
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let chapters = json["chapters"] as? [[String: Any]] ?? []
    let titles = chapters.compactMap { ($0["tags"] as? [String: Any])?["title"] as? String }
    let format = json["format"] as? [String: Any] ?? [:]
    let duration = Double(format["duration"] as? String ?? "0") ?? 0
    return ProbeResult(chapterTitles: titles, durationSeconds: duration)
}

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: [GenerationProgress] = []

    func record(_ value: GenerationProgress) {
        lock.lock()
        defer { lock.unlock() }
        progress.append(value)
    }

    func snapshot() -> [GenerationProgress] {
        lock.lock()
        defer { lock.unlock() }
        return progress
    }
}
