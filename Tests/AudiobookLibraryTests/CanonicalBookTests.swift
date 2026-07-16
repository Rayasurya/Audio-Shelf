import Foundation
import Testing
@testable import AudiobookLibrary

// Runs against the canonical public-domain EPUB when it has been downloaded
// with Scripts/download-canonical-book.sh; skips cleanly when it is absent.
@Test(.enabled(if: FileManager.default.fileExists(atPath: canonicalBookPath)))
func canonicalEPUBImportsWithChapters() throws {
    let source = try importSource(url: URL(fileURLWithPath: canonicalBookPath), fileManager: .default)
    #expect(source.title.localizedCaseInsensitiveContains("Alice"))
    #expect(source.author.localizedCaseInsensitiveContains("Carroll"))
    #expect(source.chapters.count == 12)
    #expect(source.chapters.allSatisfy { $0.text.count > 80 })
    let indexes = source.chapters.map(\.index)
    #expect(indexes == Array(1 ... source.chapters.count))
}

// Chapter titles must come from the EPUB's table of contents, and Project
// Gutenberg boilerplate (header, license, contents page) must not be narrated.
@Test(.enabled(if: FileManager.default.fileExists(atPath: canonicalBookPath)))
func canonicalEPUBUsesTOCTitlesAndSkipsBoilerplate() throws {
    let source = try importSource(url: URL(fileURLWithPath: canonicalBookPath), fileManager: .default)
    #expect(source.chapters.first?.title == "CHAPTER I. Down the Rabbit-Hole")
    #expect(source.chapters.last?.title == "CHAPTER XII. Alice’s Evidence")
    for chapter in source.chapters {
        #expect(!chapter.title.localizedCaseInsensitiveContains("Gutenberg"))
        #expect(!chapter.text.localizedCaseInsensitiveContains("Project Gutenberg"))
    }
}

private let canonicalBookPath = FileManager.default.currentDirectoryPath + "/Fixtures/alice.epub"
