import Foundation
import Testing
@testable import AudiobookLibrary

private func makeBook(categories: [String?]) -> Audiobook {
    let chapters = categories.enumerated().map { index, category in
        Chapter(
            id: UUID(),
            index: index + 1,
            title: "Chapter \(index + 1)",
            text: "text",
            audioURL: URL(fileURLWithPath: "/tmp/c\(index).wav"),
            duration: 100,
            isExcluded: nil,
            sectionCategory: category
        )
    }
    return Audiobook(
        id: UUID(), title: "T", author: "A", sourceURL: URL(fileURLWithPath: "/tmp/t.txt"),
        chapters: chapters, status: .readyToListen, generatedURL: nil,
        playbackSeconds: 0, lastOpenedAt: nil, createdAt: Date(), failureMessage: nil
    )
}

@Test func skipsIntoNextBodyChapter() {
    // body (0-100), notes (100-200), body (200-300)
    let book = makeBook(categories: ["body", "notes", "body"])
    let target = skipTargetSeconds(book: book, currentSeconds: 105, skips: ["notes"])
    #expect(target == 200)
}

@Test func noSkipInsideBodyOrWithoutSkips() {
    let book = makeBook(categories: ["body", "notes", "body"])
    #expect(skipTargetSeconds(book: book, currentSeconds: 50, skips: ["notes"]) == nil)
    #expect(skipTargetSeconds(book: book, currentSeconds: 105, skips: []) == nil)
}

@Test func consecutiveSkippedChaptersJumpTogether() {
    let book = makeBook(categories: ["body", "notes", "back_matter", "body"])
    let target = skipTargetSeconds(book: book, currentSeconds: 110, skips: ["notes", "back_matter"])
    #expect(target == 300)
}

@Test func trailingSkippedChapterJumpsToEnd() {
    let book = makeBook(categories: ["body", "back_matter"])
    let target = skipTargetSeconds(book: book, currentSeconds: 150, skips: ["back_matter"])
    #expect(target == 200)
}
