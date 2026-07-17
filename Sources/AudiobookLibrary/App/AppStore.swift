import AVFoundation
import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppStore {
    private(set) var state: AppState
    private(set) var repository: LibraryRepository?
    private(set) var activeGenerationBookID: UUID?
    private(set) var currentTimings: BookTimings?
    var isFocusMode = false
    var isPlaying: Bool
    var playbackRate: Float
    var currentPlaybackSeconds: TimeInterval

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var lastPersistedPlaybackSeconds: TimeInterval

    init() {
        state = .empty
        isPlaying = false
        playbackRate = preferredPlaybackRate()
        currentPlaybackSeconds = 0
        lastPersistedPlaybackSeconds = 0
    }

    func load() {
        do {
            let repository = try LibraryRepository.makeDefault(fileManager: .default)
            self.repository = repository
            // A book can only be legitimately "generating" while this process
            // runs a worker for it, so any generating book found on disk is a
            // job that died with the last app session.
            let books = try repository.load(fileManager: .default).map { book -> Audiobook in
                guard book.status == .generating else { return book }
                var interrupted = book
                interrupted.status = .failed
                interrupted.failureMessage = "Narration was interrupted before it finished. Review the book and generate again."
                return interrupted
            }
            dispatch(.load(books))
        } catch {
            dispatch(.importFailed(error.localizedDescription))
        }
    }

    func dispatch(_ action: AppAction) {
        state = reduce(state: state, action: action)
        persistIfPossible()
    }

    func chooseAndImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .pdf, .epub]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import book"
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        importBook(sourceURL: selectedURL)
    }

    // A same-named source that's already on the shelf gets a confirmation
    // instead of a silent second copy. Held here while the dialog shows.
    var duplicateImportCandidate: URL?

    func duplicateOnShelf(for sourceURL: URL) -> Audiobook? {
        state.books.first { $0.sourceURL.lastPathComponent == sourceURL.lastPathComponent }
    }

    func confirmDuplicateImport() {
        guard let sourceURL = duplicateImportCandidate else { return }
        duplicateImportCandidate = nil
        performImport(sourceURL: sourceURL)
    }

    func importBook(sourceURL: URL) {
        guard duplicateOnShelf(for: sourceURL) == nil else {
            duplicateImportCandidate = sourceURL
            return
        }
        performImport(sourceURL: sourceURL)
    }

    private func performImport(sourceURL: URL) {
        guard let repository else {
            dispatch(.importFailed("The library folder is not ready. Restart the app and try again."))
            return
        }
        dispatch(.importStarted)
        Task {
            let identifier = UUID()
            do {
                let storedSourceURL = try copySource(sourceURL: sourceURL, bookID: identifier, repository: repository, fileManager: .default)
                let imported = try importSource(url: storedSourceURL, fileManager: .default)
                // Optional local text intelligence: classify sections so
                // notes/licenses/front matter are excluded before review.
                var chapters = imported.chapters
                if isSectionClassificationEnabled(), await checkLLMStatus().isReachable,
                   let categories = await classifySections(bookTitle: imported.title, chapters: imported.chapters) {
                    chapters = applySectionClassifications(categories, to: imported.chapters)
                }
                let book = Audiobook(
                    id: identifier,
                    title: imported.title,
                    author: imported.author,
                    sourceURL: storedSourceURL,
                    chapters: chapters,
                    status: .readyForReview,
                    generatedURL: nil,
                    playbackSeconds: 0,
                    lastOpenedAt: nil,
                    createdAt: Date(),
                    failureMessage: nil
                )
                dispatch(.importSucceeded(book))
            } catch {
                dispatch(.importFailed(error.localizedDescription))
            }
        }
    }

    func saveReviewedBook(_ book: Audiobook) {
        var readyBook = book
        readyBook.status = .readyForReview
        readyBook.failureMessage = nil
        dispatch(.updateBook(readyBook))
    }

    func beginGeneration(bookID: UUID) {
        guard let repository, let book = state.books.first(where: { $0.id == bookID }) else {
            dispatch(.importFailed("The selected book is no longer available."))
            return
        }
        guard activeGenerationBookID == nil else {
            let busyTitle = state.books.first(where: { $0.id == activeGenerationBookID })?.title ?? "Another book"
            dispatch(.importFailed("\(busyTitle) is being narrated right now. One book generates at a time — check its progress from the library."))
            return
        }
        activeGenerationBookID = bookID
        var generatingBook = book
        generatingBook.status = .generating
        generatingBook.failureMessage = nil
        dispatch(.updateBook(generatingBook))
        dispatch(.generationStarted(bookID))

        Task { [repository] in
            do {
                // Easier-retelling style: rewrite chapters through the local
                // model first (cached — resuming skips finished rewrites).
                var book = generatingBook
                if book.narrationStyle == .easier {
                    let narrated = book.narratedChapters
                    for (position, chapter) in narrated.enumerated() where chapter.narrationText == nil {
                        dispatch(.generationProgressed(GenerationProgress(
                            bookID: book.id,
                            completedChapters: position,
                            totalChapters: narrated.count,
                            chapterTitle: "Retelling: \(chapter.title)"
                        )))
                        guard let rewritten = await rewriteChapterForEasierListening(bookTitle: book.title, chapter: chapter) else {
                            throw GenerationError.workerFailed(
                                status: 0,
                                diagnostics: "The easier-retelling style needs the local model server, and it did not answer. Start it (LM Studio: lms server start) or switch the book back to Faithful in review."
                            )
                        }
                        book.chapters = book.chapters.map { existing in
                            guard existing.id == chapter.id else { return existing }
                            var updated = existing
                            updated.narrationText = rewritten
                            return updated
                        }
                        dispatch(.updateBook(book))
                    }
                }
                let preparedBook = book
                let generated = try await Task.detached(priority: .userInitiated) { [preparedBook, repository] in
                    try generateKokoroAudio(
                        book: preparedBook,
                        repository: repository,
                        fileManager: .default,
                        progressHandler: { progress in
                            Task { @MainActor [weak self] in
                                self?.dispatch(.generationProgressed(progress))
                            }
                        }
                    )
                }.value
                var packaged = try await Task.detached(priority: .userInitiated) { [generated, repository] in
                    try packageAudiobook(book: generated, repository: repository, fileManager: .default)
                }.value
                packaged.generationRecord = GenerationRecord(
                    provider: "Kokoro (local)",
                    voice: packaged.voice ?? selectedNarrationVoice(),
                    generatedAt: Date(),
                    audioBytes: packaged.generatedURL.flatMap {
                        try? FileManager.default.attributesOfItem(atPath: $0.path(percentEncoded: false))[.size] as? Int
                    }
                )
                activeGenerationBookID = nil
                dispatch(.generationFinished(packaged))
                if case .player(packaged.id) = state.route {
                    preparePlayer(for: packaged)
                    currentTimings = loadBookTimings(bookID: packaged.id, repository: repository, fileManager: .default)
                }
            } catch {
                activeGenerationBookID = nil
                dispatch(.generationFailed(bookID: bookID, message: error.localizedDescription))
            }
        }
    }

    func openGenerationProgress(bookID: UUID) {
        dispatch(.navigate(.generation(bookID)))
    }

    func openPlayer(bookID: UUID) {
        guard let book = state.books.first(where: { $0.id == bookID }), book.generatedURL != nil else {
            dispatch(.importFailed("Generate this audiobook before playing it."))
            return
        }
        preparePlayer(for: book)
        currentTimings = repository.flatMap { loadBookTimings(bookID: bookID, repository: $0, fileManager: .default) }
        isFocusMode = autoFocusOnPlay()
        dispatch(.navigate(.player(bookID)))
    }

    // Removal is two-step: request shows the confirmation dialog; confirm
    // deletes the book's files and library entry.
    var removalCandidateID: UUID?

    func requestRemoval(bookID: UUID) {
        guard activeGenerationBookID != bookID else {
            dispatch(.importFailed("This book is being narrated right now. Wait for it to finish before removing it."))
            return
        }
        removalCandidateID = bookID
    }

    func confirmRemoval() {
        guard let bookID = removalCandidateID else { return }
        removalCandidateID = nil
        if case .player(bookID) = state.route { stopPlayer() }
        if let repository {
            try? FileManager.default.removeItem(at: repository.bookDirectory(bookID: bookID))
        }
        dispatch(.removeBook(bookID))
    }

    func revealBookFiles(bookID: UUID) {
        guard let repository else { return }
        NSWorkspace.shared.activateFileViewerSelecting([repository.bookDirectory(bookID: bookID)])
    }

    func exportAudiobook(bookID: UUID) {
        guard let book = state.books.first(where: { $0.id == bookID }), let sourceURL = book.generatedURL else {
            dispatch(.importFailed("Generate this book before exporting it."))
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            dispatch(.importFailed("Export failed: \(error.localizedDescription)"))
        }
    }

    func resumeGeneration(bookID: UUID) {
        // Completed chapters are fingerprinted on disk (text + voice), so
        // re-running generation only narrates what is missing or changed.
        beginGeneration(bookID: bookID)
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = min(3, max(0.5, rate))
        savePreferredPlaybackRate(playbackRate)
        if isPlaying {
            player?.rate = playbackRate
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentPlaybackSeconds = seconds
        persistPlayback()
    }

    func stopPlayer() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func preparePlayer(for book: Audiobook) {
        stopPlayer()
        guard let url = book.generatedURL else { return }
        let player = AVPlayer(url: url)
        player.seek(to: CMTime(seconds: book.playbackSeconds, preferredTimescale: 600))
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentPlaybackSeconds = time.seconds.isFinite ? time.seconds : 0
                if self.isPlaying,
                   let bookID = self.playerBookID(),
                   let playingBook = self.state.books.first(where: { $0.id == bookID }),
                   let target = skipTargetSeconds(book: playingBook, currentSeconds: self.currentPlaybackSeconds, skips: playbackSkipCategories()) {
                    self.seek(to: target)
                    return
                }
                if abs(self.currentPlaybackSeconds - self.lastPersistedPlaybackSeconds) >= 5 {
                    self.persistPlayback()
                    self.lastPersistedPlaybackSeconds = self.currentPlaybackSeconds
                }
            }
        }
        self.player = player
        currentPlaybackSeconds = book.playbackSeconds
        lastPersistedPlaybackSeconds = book.playbackSeconds
    }

    private func persistPlayback() {
        guard let bookID = playerBookID() else { return }
        dispatch(.updatePlayback(bookID: bookID, seconds: currentPlaybackSeconds))
    }

    private func playerBookID() -> UUID? {
        guard case let .player(bookID) = state.route else { return nil }
        return bookID
    }

    private func persistIfPossible() {
        guard let repository else { return }
        do {
            try repository.save(books: state.books, fileManager: .default)
        } catch {
            state.alertMessage = "Could not save the library: \(error.localizedDescription)"
        }
    }
}

func copySource(sourceURL: URL, bookID: UUID, repository: LibraryRepository, fileManager: FileManager) throws -> URL {
    let didAccess = sourceURL.startAccessingSecurityScopedResource()
    defer {
        if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
    }
    let destinationDirectory = repository.bookDirectory(bookID: bookID).appending(path: "source", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    let destinationURL = destinationDirectory.appending(path: sourceURL.lastPathComponent)
    try fileManager.copyItem(at: sourceURL, to: destinationURL)
    return destinationURL
}
