import Foundation

enum BookStatus: String, Codable, CaseIterable, Sendable {
    case readyForReview
    case generating
    case readyToListen
    // Narration was deliberately stopped or interrupted; completed chapters
    // are kept and resume is free. Not an error state.
    case paused
    case failed

    var title: String {
        switch self {
        case .readyForReview: "Ready for review"
        case .generating: "Generating"
        case .readyToListen: "Ready to listen"
        case .paused: "Paused"
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
    // LLM-rewritten text (per the book's narration style). When present, this
    // is what gets narrated; `text` stays the faithful original.
    var narrationText: String?

    var textForNarration: String { narrationText ?? text }

    init(id: UUID, index: Int, title: String, text: String, audioURL: URL?, duration: TimeInterval?, isExcluded: Bool? = nil, sectionCategory: String? = nil, narrationText: String? = nil) {
        self.id = id
        self.index = index
        self.title = title
        self.text = text
        self.audioURL = audioURL
        self.duration = duration
        self.isExcluded = isExcluded
        self.sectionCategory = sectionCategory
        self.narrationText = narrationText
    }
}

// How the text is treated before narration. Faithful never rewrites;
// easier retelling runs each chapter through the local LLM.
enum NarrationStyle: String, Codable, Sendable, CaseIterable {
    case faithful
    case easier

    var title: String {
        switch self {
        case .faithful: "Faithful"
        case .easier: "Easier retelling"
        }
    }

    var blurb: String {
        switch self {
        case .faithful: "Narrates the book exactly as written."
        case .easier: "The local model retells each chapter in plainer language — same story, easier to follow. Needs the model server running."
        }
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
    // Per-book narrator voice; nil = the app-wide Settings voice.
    var voice: String?
    // nil = faithful.
    var narrationStyle: NarrationStyle?
    // Listener's content preferences in their own words ("remove anything
    // outside the story", "skip gore"). A local model removes matching
    // sentences chapter-by-chapter before narration; empty/nil = narrate all.
    var contentPreferences: String?

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

// What is happening to a book right now. Process state lives HERE, not in
// BookStatus — books say what they are; the job says what's being done.
enum GenerationPhase: String, Equatable, Sendable {
    case preparing
    case cleaning
    case retelling
    case narrating
    case packaging

    var title: String {
        switch self {
        case .preparing: "Preparing"
        case .cleaning: "Cleaning"
        case .retelling: "Retelling"
        case .narrating: "Narrating"
        case .packaging: "Packaging"
        }
    }
}

struct GenerationJob: Equatable, Sendable {
    let bookID: UUID
    var phase: GenerationPhase
    var completedChapters: Int
    var totalChapters: Int
    var currentChapterTitle: String
    let startedAt: Date

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
    case models
    case preparation(UUID)
    case generation(UUID)
    case player(UUID)
}

struct AppState: Equatable, Sendable {
    var books: [Audiobook]
    var selectedBookID: UUID?
    var route: AppRoute
    var activeJob: GenerationJob?
    var queue: [UUID]
    var isImporting: Bool
    var alertMessage: String?

    static let empty = AppState(
        books: [],
        selectedBookID: nil,
        route: .library,
        activeJob: nil,
        queue: [],
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
    case generationStarted(GenerationJob)
    case jobUpdated(GenerationJob)
    case generationFinished(Audiobook)
    case generationFailed(bookID: UUID, message: String)
    case generationStopped(bookID: UUID, message: String)
    case enqueueGeneration(UUID)
    case removeFromQueue(UUID)
    case updatePlayback(bookID: UUID, seconds: TimeInterval)
    case removeBook(UUID)
    case dismissAlert
}

func reduce(state: AppState, action: AppAction) -> AppState {
    switch action {
    case let .load(books):
        return AppState(
            books: books,
            selectedBookID: books.first?.id,
            route: .library,
            activeJob: nil,
            queue: [],
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
    case let .generationStarted(job):
        var next = state
        next.route = .generation(job.bookID)
        next.activeJob = job
        next.queue.removeAll { $0 == job.bookID }
        return next
    case let .jobUpdated(job):
        var next = state
        next.activeJob = job
        return next
    case let .generationFinished(book):
        var next = state
        next.books = state.books.map { $0.id == book.id ? book : $0 }
        next.activeJob = nil
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
        next.activeJob = nil
        next.alertMessage = message
        return next
    case let .generationStopped(bookID, message):
        var next = state
        next.books = state.books.map { book in
            guard book.id == bookID else { return book }
            var pausedBook = book
            pausedBook.status = .paused
            pausedBook.failureMessage = message
            return pausedBook
        }
        next.activeJob = nil
        // A stopped job's screen has nothing left to show — land on the hero,
        // which now offers Resume.
        if case .generation(bookID) = state.route {
            next.route = .library
        }
        return next
    case let .enqueueGeneration(bookID):
        var next = state
        if !next.queue.contains(bookID), next.activeJob?.bookID != bookID {
            next.queue.append(bookID)
        }
        return next
    case let .removeFromQueue(bookID):
        var next = state
        next.queue.removeAll { $0 == bookID }
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
    case let .removeBook(bookID):
        var next = state
        next.books = state.books.filter { $0.id != bookID }
        next.queue.removeAll { $0 == bookID }
        if next.selectedBookID == bookID {
            next.selectedBookID = next.books.first?.id
        }
        switch state.route {
        case .player(bookID), .preparation(bookID), .generation(bookID):
            next.route = .library
        default:
            break
        }
        return next
    case .dismissAlert:
        var next = state
        next.alertMessage = nil
        return next
    }
}
