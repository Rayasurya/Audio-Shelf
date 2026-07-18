import AppKit
import SwiftUI
import Testing
@testable import AudiobookLibrary

// Renders the real views to PNGs so layout can be inspected without driving
// the GUI. Files land in /tmp/audioshelf-snapshots/. Opt-in via env var so CI
// and normal runs skip it.
private let snapshotsEnabled = ProcessInfo.processInfo.environment["AUDIOSHELF_SNAPSHOTS"] == "1"

@MainActor
private func renderSnapshot(_ view: some View, size: CGSize, name: String) throws {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    let directory = URL(fileURLWithPath: "/tmp/audioshelf-snapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: directory.appending(path: "\(name).png"))
}

private func sampleBook() -> (Audiobook, BookTimings) {
    let sentences = [
        "The keeper climbed the spiral stairs each evening before dusk, carrying a small brass lamp and a pocketful of matches.",
        "From the top of the tower she could see the whole harbor, the fishing boats returning in a slow line.",
        "She trimmed the wick, polished the great lens, and waited for the sun to touch the water.",
        "Winter came early that year, and with it a fog so thick that the boats rang their bells all through the night.",
        "The keeper kept the light burning and counted the bells from her chair by the window.",
        "One bell was missing.",
        "She wrote the boat's name in her logbook and went down to wake the harbor master."
    ]
    var chapters: [Chapter] = []
    var chapterTimings: [ChapterTimings] = []
    for chapterIndex in 1 ... 3 {
        let texts = sentences.shuffled()
        var cursor: TimeInterval = 0
        var timings: [ChunkTiming] = []
        for text in texts {
            let duration = TimeInterval(text.count) / 18
            timings.append(ChunkTiming(text: text, start: cursor, end: cursor + duration))
            cursor += duration
        }
        chapters.append(Chapter(
            id: UUID(),
            index: chapterIndex,
            title: "Chapter \(chapterIndex). The Lighthouse Waits",
            text: texts.joined(separator: " "),
            audioURL: URL(fileURLWithPath: "/tmp/c\(chapterIndex).wav"),
            duration: cursor
        ))
        chapterTimings.append(ChapterTimings(index: chapterIndex, duration: cursor, timings: timings))
    }
    let book = Audiobook(
        id: UUID(),
        title: "The Lighthouse at Quiet Harbor",
        author: "A. Keeper",
        sourceURL: URL(fileURLWithPath: "/tmp/book.txt"),
        chapters: chapters,
        status: .readyToListen,
        generatedURL: URL(fileURLWithPath: "/tmp/book.m4b"),
        playbackSeconds: 95,
        lastOpenedAt: nil,
        createdAt: Date(),
        failureMessage: nil,
        generationRecord: GenerationRecord(provider: "Kokoro (local)", voice: "af_sarah", generatedAt: Date(), audioBytes: 68_000_000)
    )
    return (book, BookTimings(version: 1, voice: "af_sarah", chapters: chapterTimings))
}

// Audit evidence: the generation flow's states as they exist today.
@Test(.enabled(if: snapshotsEnabled))
@MainActor
func renderGenerationFlowStates() throws {
    let (book, _) = sampleBook()
    var generating = book
    generating.status = .generating
    try renderSnapshot(
        GenerationView(
            book: generating,
            job: GenerationJob(bookID: generating.id, phase: .narrating, completedChapters: 5, totalChapters: 12, currentChapterTitle: "Chapter 6. The Fog Bell", startedAt: Date().addingTimeInterval(-431)),
            isStopping: false,
            onStop: {},
            onReturnToLibrary: {}
        ),
        size: CGSize(width: 900, height: 640),
        name: "audit-generation-progress"
    )
    let actions = BookActions(
        onPlay: { _ in }, onReview: { _ in }, onProgress: { _ in }, onResume: { _ in },
        onRegenerate: { _ in }, onDetails: { _ in }, onExport: { _ in }, onRevealFiles: { _ in }, onRemove: { _ in }
    )
    try renderSnapshot(
        ListeningRail(book: generating, actions: actions).padding(24).background(AppPalette.ink),
        size: CGSize(width: 900, height: 300),
        name: "audit-hero-generating"
    )
    var failed = book
    failed.status = .failed
    failed.failureMessage = "Narration was interrupted before it finished. Review the book and generate again."
    try renderSnapshot(
        ListeningRail(book: failed, actions: actions).padding(24).background(AppPalette.ink),
        size: CGSize(width: 900, height: 320),
        name: "audit-hero-failed"
    )
}

@Test(.enabled(if: snapshotsEnabled))
@MainActor
func renderPlayerSnapshots() throws {
    let (book, timings) = sampleBook()
    try renderSnapshot(
        PlayerView(
            book: book, timings: timings, currentSeconds: 95, isPlaying: true, playbackRate: 1.25,
            onBack: {}, onToggle: {}, onSetRate: { _ in }, onSeek: { _ in }, onFocus: {}, onRegenerate: {}
        ),
        size: CGSize(width: 1_180, height: 740),
        name: "player-chapters"
    )
    try renderSnapshot(
        PlayerView(
            book: book, timings: timings, currentSeconds: 95, isPlaying: true, playbackRate: 1.25,
            onBack: {}, onToggle: {}, onSetRate: { _ in }, onSeek: { _ in }, onFocus: {}, onRegenerate: {}
        ),
        size: CGSize(width: 700, height: 620),
        name: "player-narrow"
    )
    try renderSnapshot(
        PlayerViewTextPane(book: book, timings: timings),
        size: CGSize(width: 1_180, height: 740),
        name: "player-readalong"
    )
    try renderSnapshot(
        FocusModeView(
            book: book, timings: timings, currentSeconds: 95, isPlaying: true,
            onToggle: {}, onSeek: { _ in }, onExit: {}
        ),
        size: CGSize(width: 1_280, height: 800),
        name: "focus-lyrics"
    )
}

// The lyric lines rendered without their ScrollView (which ImageRenderer
// cannot rasterize), cropped to the region around the current line.
private struct PlayerViewTextPane: View {
    let book: Audiobook
    let timings: BookTimings

    var body: some View {
        let lines = lyricLines(book: book, timings: timings)
        let current = currentLyricIndex(lines, currentSeconds: 95) ?? 0
        let window = Array(lines[max(0, current - 3) ... min(lines.count - 1, current + 4)])
        LyricLinesStack(lines: window, currentIndex: current, emphasisSize: 24, baseSize: 17, onSeek: { _ in })
            .padding(46)
            .background(AppPalette.ink)
            .foregroundStyle(AppPalette.paper)
    }
}
