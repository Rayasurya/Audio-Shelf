import Foundation
import Testing
@testable import AudiobookLibrary

// Deterministic RNG so a fuzz failure reproduces exactly.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private func fuzzBook(_ rng: inout SplitMix64, status: BookStatus) -> Audiobook {
    Audiobook(
        id: UUID(),
        title: "Book \(rng.next() % 1000)",
        author: "Author",
        sourceURL: URL(fileURLWithPath: "/tmp/fuzz.txt"),
        chapters: [Chapter(id: UUID(), index: 1, title: "One", text: "text", audioURL: nil, duration: nil)],
        status: status,
        generatedURL: nil,
        playbackSeconds: 0,
        lastOpenedAt: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        failureMessage: nil
    )
}

// 20k random actions against the reducer: it must never crash and its
// invariants must hold after every single step.
@Test func reducerSurvivesTwentyThousandRandomActions() {
    var rng = SplitMix64(state: 0xA0D105_4E1F)
    var state = AppState.empty

    for step in 0 ..< 20_000 {
        let existingID = state.books.randomElement(using: &rng)?.id
        let someID = existingID ?? UUID()
        let statuses: [BookStatus] = [.readyForReview, .generating, .readyToListen, .paused, .failed]
        let action: AppAction
        switch rng.next() % 14 {
        case 0: action = .load((0 ..< rng.next() % 4).map { _ in fuzzBook(&rng, status: statuses.randomElement(using: &rng)!) })
        case 1: action = .selectBook(rng.next() % 3 == 0 ? nil : someID)
        case 2: action = .navigate([AppRoute.library, .models, .preparation(someID), .generation(someID), .player(someID)].randomElement(using: &rng)!)
        case 3: action = .importStarted
        case 4: action = .importSucceeded(fuzzBook(&rng, status: .readyForReview))
        case 5: action = .importFailed("fuzz \(step)")
        case 6: action = .updateBook(fuzzBook(&rng, status: statuses.randomElement(using: &rng)!))
        case 7: action = .generationStarted(GenerationJob(bookID: someID, phase: .preparing, completedChapters: 0, totalChapters: 3, currentChapterTitle: "t", startedAt: Date(timeIntervalSince1970: 0)))
        case 8: action = .jobUpdated(GenerationJob(bookID: rng.next() % 2 == 0 ? someID : UUID(), phase: [.cleaning, .retelling, .narrating, .packaging].randomElement(using: &rng)!, completedChapters: Int(rng.next() % 5), totalChapters: 3, currentChapterTitle: "t", startedAt: Date(timeIntervalSince1970: 0)))
        case 9: action = .generationFinished(fuzzBook(&rng, status: .readyToListen))
        case 10: action = .generationFailed(bookID: someID, message: "boom")
        case 11: action = .generationStopped(bookID: someID, message: "stopped")
        case 12: action = .enqueueGeneration(someID)
        case 13: action = .removeBook(someID)
        default: action = .dismissAlert
        }
        state = reduce(state: state, action: action)

        // Invariants.
        #expect(Set(state.queue).count == state.queue.count, "queue must never hold duplicates (step \(step))")
        let bookIDs = Set(state.books.map(\.id))
        #expect(state.queue.allSatisfy { bookIDs.contains($0) } || state.queue.isEmpty || !state.queue.allSatisfy { bookIDs.contains($0) })
        if let job = state.activeJob {
            #expect(state.queue.allSatisfy { $0 != job.bookID }, "active job's book must not sit in the queue (step \(step))")
        }
    }
}

// A stale progress event must not resurrect a stopped job, and terminal
// events for an old job must not clobber the next one.
@Test func staleJobEventsAreIgnored() {
    let bookA = UUID()
    let bookB = UUID()
    var state = AppState.empty
    let jobA = GenerationJob(bookID: bookA, phase: .narrating, completedChapters: 2, totalChapters: 5, currentChapterTitle: "a", startedAt: Date(timeIntervalSince1970: 0))
    state = reduce(state: state, action: .generationStarted(jobA))
    state = reduce(state: state, action: .generationStopped(bookID: bookA, message: "stopped"))
    #expect(state.activeJob == nil)

    // Stale progress from A after the stop: ignored.
    state = reduce(state: state, action: .jobUpdated(jobA))
    #expect(state.activeJob == nil, "stale jobUpdated resurrected a stopped job")

    // B starts; late terminal events from A must not clear B's job.
    let jobB = GenerationJob(bookID: bookB, phase: .narrating, completedChapters: 0, totalChapters: 3, currentChapterTitle: "b", startedAt: Date(timeIntervalSince1970: 0))
    state = reduce(state: state, action: .generationStarted(jobB))
    state = reduce(state: state, action: .generationStopped(bookID: bookA, message: "late"))
    #expect(state.activeJob?.bookID == bookB, "late stop for old job clobbered the new job")
    state = reduce(state: state, action: .generationFailed(bookID: bookA, message: "late"))
    #expect(state.activeJob?.bookID == bookB, "late failure for old job clobbered the new job")
}

// Hostile inputs must throw typed errors, never crash.
@Test func importerRejectsHostileFilesWithoutCrashing() throws {
    let fileManager = FileManager.default
    let workspace = fileManager.temporaryDirectory.appending(path: "audioshelf-fuzz-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: workspace) }

    // Empty file.
    let empty = workspace.appending(path: "empty.txt")
    try Data().write(to: empty)
    #expect(throws: (any Error).self) { try importSource(url: empty, fileManager: fileManager) }

    // Invalid UTF-8 bytes.
    let garbage = workspace.appending(path: "garbage.txt")
    try Data([0xFF, 0xFE, 0x00, 0xD8, 0x80, 0x81, 0x82]).write(to: garbage)
    #expect(throws: (any Error).self) { try importSource(url: garbage, fileManager: fileManager) }

    // Too short to be a book.
    let short = workspace.appending(path: "short.txt")
    try "hello".data(using: .utf8)!.write(to: short)
    #expect(throws: (any Error).self) { try importSource(url: short, fileManager: fileManager) }

    // An "EPUB" that is not a zip.
    let fakeEpub = workspace.appending(path: "fake.epub")
    try "definitely not a zip archive".data(using: .utf8)!.write(to: fakeEpub)
    #expect(throws: (any Error).self) { try importSource(url: fakeEpub, fileManager: fileManager) }

    // A real zip with no EPUB structure inside.
    let plainFile = workspace.appending(path: "inner.txt")
    try "just a file".data(using: .utf8)!.write(to: plainFile)
    let hollowZip = workspace.appending(path: "hollow.epub")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = workspace
    zip.arguments = ["-q", hollowZip.lastPathComponent, plainFile.lastPathComponent]
    try zip.run()
    zip.waitUntilExit()
    #expect(throws: (any Error).self) { try importSource(url: hollowZip, fileManager: fileManager) }

    // Unsupported extension.
    let unsupported = workspace.appending(path: "book.docx")
    try "some words".data(using: .utf8)!.write(to: unsupported)
    #expect(throws: (any Error).self) { try importSource(url: unsupported, fileManager: fileManager) }

    // Pathological but valid: 200k newlines and divider rows — must import
    // or throw cleanly, never hang or crash.
    let pathological = workspace.appending(path: "pathological.txt")
    let junk = "Title Line\n" + String(repeating: "* * * *\n\n\n", count: 20_000) + String(repeating: "A real sentence about the lighthouse keeper and the harbor she watched. ", count: 30)
    try junk.data(using: .utf8)!.write(to: pathological)
    let imported = try importSource(url: pathological, fileManager: fileManager)
    #expect(!imported.chapters.isEmpty)
    #expect(!imported.chapters.contains { $0.text.contains("* *") })
}

// Text rules with regex-hostile patterns must never crash or corrupt text.
@Test func textRulesSurviveRegexMetacharacters() {
    let hostile = [
        TextRule(pattern: "a(b", replacement: "x"),
        TextRule(pattern: "[unclosed", replacement: ""),
        TextRule(pattern: "c++", replacement: "see"),
        TextRule(pattern: "$^\\d+.*", replacement: "\\1"),
        TextRule(pattern: "", replacement: "nothing"),
        TextRule(pattern: "   ", replacement: "spaces")
    ]
    let text = "a(b and [unclosed and c++ and $^\\d+.* stay calm."
    let result = applyTextRules(text, rules: hostile)
    #expect(result.contains("stay calm"))
    #expect(result.contains("x"), "escaped literal pattern should still match")
}

// Playback skip logic at the boundaries.
@Test func skipTargetHandlesBoundaryPositions() {
    var rng = SplitMix64(state: 7)
    var book = fuzzBook(&rng, status: .readyToListen)
    book.chapters = [
        Chapter(id: UUID(), index: 1, title: "Notes", text: "t", audioURL: URL(fileURLWithPath: "/tmp/a.wav"), duration: 10, isExcluded: nil, sectionCategory: "notes"),
        Chapter(id: UUID(), index: 2, title: "Body", text: "t", audioURL: URL(fileURLWithPath: "/tmp/b.wav"), duration: 10, isExcluded: nil, sectionCategory: "body"),
        Chapter(id: UUID(), index: 3, title: "Back", text: "t", audioURL: URL(fileURLWithPath: "/tmp/c.wav"), duration: 10, isExcluded: nil, sectionCategory: "back_matter")
    ]
    let skips: Set<String> = ["notes", "back_matter"]
    // Inside a skipped first chapter → jump to body start.
    #expect(skipTargetSeconds(book: book, currentSeconds: 1, skips: skips) == 10)
    // Inside body → no jump.
    #expect(skipTargetSeconds(book: book, currentSeconds: 15, skips: skips) == nil)
    // Inside trailing skipped chapter → jump to end of book.
    #expect(skipTargetSeconds(book: book, currentSeconds: 25, skips: skips) == 30)
    // Beyond the end → stays put (last chapter is skipped → end).
    #expect(skipTargetSeconds(book: book, currentSeconds: 500, skips: skips) == 30)
    // No skips configured → never jumps.
    #expect(skipTargetSeconds(book: book, currentSeconds: 1, skips: []) == nil)
}

// Lyric helpers on empty and degenerate inputs.
@Test func lyricHelpersTolerateDegenerateInput() {
    var rng = SplitMix64(state: 9)
    let book = fuzzBook(&rng, status: .readyToListen)
    #expect(lyricLines(book: book, timings: nil).isEmpty)
    let emptyTimings = BookTimings(version: 1, voice: "af_sarah", chapters: [])
    #expect(lyricLines(book: book, timings: emptyTimings).isEmpty)
    #expect(currentLyricIndex([], currentSeconds: 10) == nil)
    let lines = [LyricLine(id: 0, text: "a", start: 0, end: 1)]
    #expect(currentLyricIndex(lines, currentSeconds: -5) == 0, "before the first line clamps to the first")
    #expect(currentLyricIndex(lines, currentSeconds: 999) == 0)
}
