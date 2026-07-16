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

@Test func navigatingBackToGenerationKeepsProgress() {
    let book = makeBook(status: .generating)
    var state = AppState.empty
    state.books = [book]
    state.route = .generation(book.id)
    state.generationProgress = GenerationProgress(bookID: book.id, completedChapters: 3, totalChapters: 12, chapterTitle: "Three")
    var next = reduce(state: state, action: .navigate(.library))
    #expect(next.generationProgress?.completedChapters == 3)
    next = reduce(state: next, action: .navigate(.generation(book.id)))
    #expect(next.route == .generation(book.id))
    #expect(next.generationProgress?.completedChapters == 3)
}
