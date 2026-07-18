import Foundation
import Testing
@testable import AudiobookLibrary

private func makeBook(status: BookStatus) -> Audiobook {
    Audiobook(
        id: UUID(),
        title: "Test Book",
        author: "Author",
        sourceURL: URL(fileURLWithPath: "/tmp/test.txt"),
        chapters: [Chapter(id: UUID(), index: 1, title: "One", text: "text", audioURL: nil, duration: nil)],
        status: status,
        generatedURL: nil,
        playbackSeconds: 0,
        lastOpenedAt: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        failureMessage: nil
    )
}

@Test func generationFinishedMovesWatcherToPlayer() {
    let book = makeBook(status: .generating)
    var state = AppState.empty
    state.books = [book]
    state.route = .generation(book.id)
    var finished = book
    finished.status = .readyToListen
    let next = reduce(state: state, action: .generationFinished(finished))
    #expect(next.route == .player(book.id))
}

@Test func generationFinishedLeavesBrowserWhereTheyAre() {
    let book = makeBook(status: .generating)
    var state = AppState.empty
    state.books = [book]
    state.route = .library
    var finished = book
    finished.status = .readyToListen
    let next = reduce(state: state, action: .generationFinished(finished))
    #expect(next.route == .library)
    #expect(next.books.first?.status == .readyToListen)
}

private func makeJob(bookID: UUID, phase: GenerationPhase = .narrating, completed: Int = 3, total: Int = 12) -> GenerationJob {
    GenerationJob(
        bookID: bookID,
        phase: phase,
        completedChapters: completed,
        totalChapters: total,
        currentChapterTitle: "Chapter \(completed + 1)",
        startedAt: Date(timeIntervalSince1970: 0)
    )
}

@Test func navigatingBackToGenerationKeepsJobProgress() {
    let book = makeBook(status: .generating)
    var state = AppState.empty
    state.books = [book]
    state.route = .generation(book.id)
    state.activeJob = makeJob(bookID: book.id)
    var next = reduce(state: state, action: .navigate(.library))
    #expect(next.activeJob?.completedChapters == 3)
    next = reduce(state: next, action: .navigate(.generation(book.id)))
    #expect(next.route == .generation(book.id))
    #expect(next.activeJob?.completedChapters == 3)
}

@Test func stoppingPausesTheBookAndClearsTheJob() {
    let book = makeBook(status: .generating)
    var state = AppState.empty
    state.books = [book]
    state.route = .generation(book.id)
    state.activeJob = makeJob(bookID: book.id, completed: 5)
    let next = reduce(state: state, action: .generationStopped(bookID: book.id, message: "Narration stopped — 5 of 12 chapters narrated. Resume anytime."))
    #expect(next.activeJob == nil)
    #expect(next.books.first?.status == .paused)
    #expect(next.books.first?.failureMessage?.contains("5 of 12") == true)
    #expect(next.route == .library)
}

@Test func busyGenerationsQueueAndStartWhenTheSlotFrees() {
    let first = makeBook(status: .generating)
    let second = makeBook(status: .readyForReview)
    var state = AppState.empty
    state.books = [first, second]
    state.activeJob = makeJob(bookID: first.id)

    // Second book queues while the first narrates; enqueueing twice is a no-op.
    var next = reduce(state: state, action: .enqueueGeneration(second.id))
    next = reduce(state: next, action: .enqueueGeneration(second.id))
    #expect(next.queue == [second.id])

    // Starting the queued job removes it from the queue.
    next.activeJob = nil
    next = reduce(state: next, action: .generationStarted(makeJob(bookID: second.id, phase: .preparing, completed: 0)))
    #expect(next.queue.isEmpty)
    #expect(next.activeJob?.bookID == second.id)
}

@Test func removingABookAlsoRemovesItFromTheQueue() {
    let book = makeBook(status: .readyForReview)
    var state = AppState.empty
    state.books = [book]
    state.queue = [book.id]
    let next = reduce(state: state, action: .removeBook(book.id))
    #expect(next.queue.isEmpty)
    #expect(next.books.isEmpty)
}
