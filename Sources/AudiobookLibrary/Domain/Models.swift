import Foundation

enum BookStatus: String, Codable, CaseIterable, Sendable {
    case readyForReview
    case generating
    case readyToListen
    case failed

    var title: String {
        switch self {
        case .readyForReview: "Ready for review"
        case .generating: "Generating"
        case .readyToListen: "Ready to listen"
        case .failed: "Needs attention"
        }
    }
}

struct Chapter: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var index: Int
    var title: String
    var text: String
    var audioURL: URL?
    var duration: TimeInterval?
    // nil or false = narrated. Set by section classification (license pages,
    // author's notes, …) or by the user in review; excluded chapters keep
    // their text for reading but are skipped by narration and packaging.
    var isExcluded: Bool?
    // Category assigned by section classification (body, front_matter, …),
    // shown in review so an exclusion is never unexplained.
    var sectionCategory: String?

    init(id: UUID, index: Int, title: String, text: String, audioURL: URL?, duration: TimeInterval?, isExcluded: Bool? = nil, sectionCategory: String? = nil) {
        self.id = id
        self.index = index
        self.title = title
        self.text = text
        self.audioURL = audioURL
        self.duration = duration
        self.isExcluded = isExcluded
        self.sectionCategory = sectionCategory
    }
}

struct Audiobook: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var author: String
    var sourceURL: URL
    var chapters: [Chapter]
    var status: BookStatus
    var generatedURL: URL?
    var playbackSeconds: TimeInterval
    var lastOpenedAt: Date?
    var createdAt: Date
    var failureMessage: String?
    var generationRecord: GenerationRecord?
    // nil = audiobook (the default for books from older versions).
    var outputMode: OutputMode?
    // Folder of per-chapter episode files when generated in podcast mode.
    var episodesURL: URL?

    // The chapters narration actually voices — excluded sections keep their
    // text for reading but never reach the narration provider or the player
    // timeline.
    var narratedChapters: [Chapter] {
        chapters.filter { $0.isExcluded != true }
    }

    init(
        id: UUID,
        title: String,
        author: String,
        sourceURL: URL,
        chapters: [Chapter],
        status: BookStatus,
        generatedURL: URL?,
        playbackSeconds: TimeInterval,
        lastOpenedAt: Date?,
        createdAt: Date,
        failureMessage: String?,
        generationRecord: GenerationRecord? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceURL = sourceURL
        self.chapters = chapters
        self.status = status
        self.generatedURL = generatedURL
        self.playbackSeconds = playbackSeconds
        self.lastOpenedAt = lastOpenedAt
        self.createdAt = createdAt
        self.failureMessage = failureMessage
        self.generationRecord = generationRecord
    }
}

struct GenerationProgress: Equatable, Sendable {
    let bookID: UUID
    let completedChapters: Int
    let totalChapters: Int
    let chapterTitle: String

    var fraction: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(completedChapters) / Double(totalChapters)
    }
}

// What the narration produces: one chaptered audiobook file, or a set of
// podcast-style episode files (one per chapter, with a spoken episode intro).
enum OutputMode: String, Codable, Sendable, CaseIterable {
    case audiobook
    case podcast

    var title: String {
        switch self {
        case .audiobook: "Audiobook (M4B)"
        case .podcast: "Podcast episodes"
        }
    }
}

// How an audiobook edition was made — shown to the user so generation is
// never a black box. Optional so libraries from older versions still decode.
struct GenerationRecord: Codable, Equatable, Sendable {
    var provider: String
    var voice: String
    var generatedAt: Date
    var audioBytes: Int?
}

enum AppRoute: Equatable, Sendable {
    case library
    case preparation(UUID)
    case generation(UUID)
    case player(UUID)
}

struct AppState: Equatable, Sendable {
    var books: [Audiobook]
    var selectedBookID: UUID?
    var route: AppRoute
    var generationProgress: GenerationProgress?
    var isImporting: Bool
    var alertMessage: String?

    static let empty = AppState(
        books: [],
        selectedBookID: nil,
        route: .library,
        generationProgress: nil,
        isImporting: false,
        alertMessage: nil
    )
}

enum AppAction: Equatable, Sendable {
    case load([Audiobook])
    case selectBook(UUID?)
    case navigate(AppRoute)
    case importStarted
    case importSucceeded(Audiobook)
    case importFailed(String)
    case updateBook(Audiobook)
    case generationStarted(UUID)
    case generationProgressed(GenerationProgress)
    case generationFinished(Audiobook)
    case generationFailed(bookID: UUID, message: String)
    case updatePlayback(bookID: UUID, seconds: TimeInterval)
    case dismissAlert
}

func reduce(state: AppState, action: AppAction) -> AppState {
    switch action {
    case let .load(books):
        return AppState(
            books: books,
            selectedBookID: books.first?.id,
            route: .library,
            generationProgress: nil,
            isImporting: false,
            alertMessage: nil
        )
    case let .selectBook(bookID):
        var next = state
        next.selectedBookID = bookID
        return next
    case let .navigate(route):
        var next = state
        next.route = route
        return next
    case .importStarted:
        var next = state
        next.isImporting = true
        return next
    case let .importSucceeded(book):
        var next = state
        next.books = [book] + state.books
        next.selectedBookID = book.id
        next.route = .preparation(book.id)
        next.isImporting = false
        return next
    case let .importFailed(message):
        var next = state
        next.isImporting = false
        next.alertMessage = message
        return next
    case let .updateBook(book):
        var next = state
        next.books = state.books.map { $0.id == book.id ? book : $0 }
        return next
    case let .generationStarted(bookID):
        var next = state
        next.route = .generation(bookID)
        next.generationProgress = GenerationProgress(bookID: bookID, completedChapters: 0, totalChapters: 0, chapterTitle: "Preparing narration")
        return next
    case let .generationProgressed(progress):
        var next = state
        next.generationProgress = progress
        return next
    case let .generationFinished(book):
        var next = state
        next.books = state.books.map { $0.id == book.id ? book : $0 }
        next.generationProgress = nil
        // Only steal the screen when the user is watching this book being
        // made; someone browsing another book keeps their place.
        if case .generation(book.id) = state.route {
            next.route = .player(book.id)
        }
        return next
    case let .generationFailed(bookID, message):
        var next = state
        next.books = state.books.map { book in
            guard book.id == bookID else { return book }
            var failedBook = book
            failedBook.status = .failed
            failedBook.failureMessage = message
            return failedBook
        }
        next.generationProgress = nil
        next.alertMessage = message
        return next
    case let .updatePlayback(bookID, seconds):
        var next = state
        next.books = state.books.map { book in
            guard book.id == bookID else { return book }
            var updatedBook = book
            updatedBook.playbackSeconds = seconds
            updatedBook.lastOpenedAt = Date()
            return updatedBook
        }
        return next
    case .dismissAlert:
        var next = state
        next.alertMessage = nil
        return next
    }
}
