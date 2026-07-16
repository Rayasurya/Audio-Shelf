import Foundation
import Testing
@testable import AudiobookLibrary

private func chapter(_ index: Int, title: String) -> Chapter {
    Chapter(id: UUID(), index: index, title: title, text: "Some chapter body text long enough to matter.", audioURL: nil, duration: nil)
}

@Test func parsesClassificationsFromFencedResponse() {
    let content = """
    Here you go:
    ```json
    [{"index": 1, "category": "license"}, {"index": 2, "category": "body"}, {"index": 3, "category": "bogus"}]
    ```
    """
    let parsed = parseSectionClassifications(content)
    #expect(parsed == [1: "license", 2: "body"])
}

@Test func rejectsResponseWithoutJSON() {
    #expect(parseSectionClassifications("I could not classify these sections.") == nil)
}

@Test func classificationsExcludeNonBodySections() {
    let chapters = [chapter(1, title: "License"), chapter(2, title: "Down the Rabbit-Hole")]
    let classified = applySectionClassifications([1: "license", 2: "body"], to: chapters)
    #expect(classified[0].isExcluded == true)
    #expect(classified[0].sectionCategory == "license")
    #expect(classified[1].isExcluded == nil)

    let book = Audiobook(
        id: UUID(), title: "T", author: "A", sourceURL: URL(fileURLWithPath: "/tmp/t.txt"),
        chapters: classified, status: .readyForReview, generatedURL: nil,
        playbackSeconds: 0, lastOpenedAt: nil, createdAt: Date(), failureMessage: nil
    )
    #expect(book.narratedChapters.map(\.index) == [2])
}

@Test func olderLibraryDecodesWithoutNewFields() throws {
    let legacy = """
    {"id":"\(UUID().uuidString)","index":1,"title":"One","text":"body text"}
    """
    let decoded = try JSONDecoder().decode(Chapter.self, from: Data(legacy.utf8))
    #expect(decoded.isExcluded == nil)
    #expect(decoded.sectionCategory == nil)
}
