import Foundation

enum GenerationError: LocalizedError {
    case missingKokoroRuntime
    case missingWorker
    case malformedWorkerEvent(String)
    case workerFailed(status: Int32, diagnostics: String)
    case missingChapterOutput(Int)
    case stopped

    var errorDescription: String? {
        switch self {
        case .missingKokoroRuntime:
            "Kokoro was not found. Set AUDIOBOOK_KOKORO_PYTHON to the Python executable in your Kokoro environment."
        case .missingWorker:
            "The packaged Kokoro worker script is missing. Rebuild the app and try again."
        case let .malformedWorkerEvent(message):
            "Kokoro sent an unreadable progress event: \(message)"
        case let .workerFailed(status, diagnostics):
            "Kokoro stopped with status \(status). \(diagnostics)"
        case let .missingChapterOutput(index):
            "Kokoro did not produce audio for chapter \(index)."
        case .stopped:
            "Narration was stopped."
        }
    }
}

struct KokoroManifest: Codable, Sendable {
    let outputDirectory: String
    let voice: String
    let chapters: [KokoroChapterInput]
}

struct KokoroChapterInput: Codable, Sendable {
    let index: Int
    let title: String
    let text: String
}

struct KokoroWorkerEvent: Codable, Sendable {
    let type: String
    let chapterIndex: Int?
    let chapterTitle: String?
    let path: String?
    let duration: TimeInterval?
    let message: String?
}

// Lets the main actor stop a narration that runs in a detached task: the
// worker handles SIGINT by finishing its current chunk, saving, and exiting,
// so Stop never loses a completed chapter.
final class GenerationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopRequested = false

    func register(_ runningProcess: Process) {
        lock.lock()
        defer { lock.unlock() }
        process = runningProcess
        if stopRequested { runningProcess.interrupt() }
    }

    func requestStop() {
        lock.lock()
        defer { lock.unlock() }
        stopRequested = true
        process?.interrupt()
    }

    var isStopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }
}

func generateKokoroAudio(
    book: Audiobook,
    repository: LibraryRepository,
    fileManager: FileManager,
    control: GenerationControl? = nil,
    progressHandler: @escaping @Sendable (GenerationProgress) -> Void
) throws -> Audiobook {
    let bookDirectory = repository.bookDirectory(bookID: book.id)
    let outputDirectory = bookDirectory.appending(path: "raw-audio", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let textRules = loadTextRules()
    let narrated = book.narratedChapters
    let manifest = KokoroManifest(
        outputDirectory: outputDirectory.path(percentEncoded: false),
        voice: book.voice ?? selectedNarrationVoice(),
        chapters: narrated.enumerated().map { position, chapter in
            var text = applyTextRules(chapter.textForNarration, rules: textRules)
            if book.outputMode == .podcast {
                text = "Episode \(position + 1) of \(narrated.count). \(chapter.title). ... " + text
            }
            return KokoroChapterInput(
                index: chapter.index,
                title: chapter.title,
                text: text
            )
        }
    )
    let manifestURL = bookDirectory.appending(path: "kokoro-manifest.json")
    try JSONEncoder.audiobookLibrary.encode(manifest).write(to: manifestURL, options: .atomic)

    let pythonURL = try kokoroPythonURL(fileManager: fileManager)
    let workerURL = try kokoroWorkerURL()
    let output = try runKokoroProcess(
        pythonURL: pythonURL,
        workerURL: workerURL,
        manifestURL: manifestURL,
        book: book,
        control: control,
        progressHandler: progressHandler
    )

    let completedByIndex = Dictionary(uniqueKeysWithValues: output.compactMap { event -> (Int, KokoroWorkerEvent)? in
        guard event.type == "chapterCompleted", let index = event.chapterIndex else { return nil }
        return (index, event)
    })
    let completedChapters = try book.chapters.map { chapter -> Chapter in
        guard chapter.isExcluded != true else { return chapter }
        guard let event = completedByIndex[chapter.index],
              let path = event.path,
              let duration = event.duration
        else {
            throw GenerationError.missingChapterOutput(chapter.index)
        }
        var completedChapter = chapter
        completedChapter.audioURL = URL(fileURLWithPath: path)
        completedChapter.duration = duration
        return completedChapter
    }
    var completedBook = book
    completedBook.chapters = completedChapters
    completedBook.status = .generating
    completedBook.failureMessage = nil
    return completedBook
}

func kokoroPythonURL(fileManager: FileManager) throws -> URL {
    // Resolution order: user setting → environment variable → the home-folder
    // install this Mac already has → dev-mode search upward from the cwd.
    if let settingsPath = settingsString(SettingsKey.kokoroPython) {
        let url = URL(fileURLWithPath: (settingsPath as NSString).expandingTildeInPath)
        if fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) { return url }
    }
    if let environmentPath = ProcessInfo.processInfo.environment["AUDIOBOOK_KOKORO_PYTHON"] {
        let url = URL(fileURLWithPath: environmentPath)
        if fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) { return url }
    }

    let homeCandidate = fileManager.homeDirectoryForCurrentUser
        .appending(path: "portfolio-flair/kokoro-tts/venv2/bin/python")
    if fileManager.isExecutableFile(atPath: homeCandidate.path(percentEncoded: false)) { return homeCandidate }

    let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    let ancestorDirectories = sequence(first: currentDirectory, next: { $0.deletingLastPathComponent() })
    for directory in ancestorDirectories.prefix(6) {
        let candidate = directory.appending(path: "kokoro-tts/venv2/bin/python")
        if fileManager.isExecutableFile(atPath: candidate.path(percentEncoded: false)) { return candidate }
    }
    throw GenerationError.missingKokoroRuntime
}

func kokoroWorkerURL() throws -> URL {
    guard let url = Bundle.module.url(forResource: "kokoro_worker", withExtension: "py") else {
        throw GenerationError.missingWorker
    }
    return url
}

func runKokoroProcess(
    pythonURL: URL,
    workerURL: URL,
    manifestURL: URL,
    book: Audiobook,
    control: GenerationControl? = nil,
    progressHandler: @escaping @Sendable (GenerationProgress) -> Void
) throws -> [KokoroWorkerEvent] {
    let process = Process()
    process.executableURL = pythonURL
    process.arguments = [workerURL.path(percentEncoded: false), manifestURL.path(percentEncoded: false)]
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    let collector = KokoroEventCollector()
    let totalChapters = book.narratedChapters.count
    standardOutput.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else { return }
        for event in collector.ingest(data) {
            if event.type == "chapterCompleted", let chapterIndex = event.chapterIndex {
                progressHandler(
                    GenerationProgress(
                        bookID: book.id,
                        completedChapters: collector.completedChapterCount(),
                        totalChapters: totalChapters,
                        chapterTitle: event.chapterTitle ?? "Chapter \(chapterIndex)"
                    )
                )
            }
        }
    }

    do {
        try process.run()
    } catch {
        standardOutput.fileHandleForReading.readabilityHandler = nil
        throw error
    }
    control?.register(process)
    process.waitUntilExit()
    standardOutput.fileHandleForReading.readabilityHandler = nil
    let diagnosticsData = standardError.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = String(data: diagnosticsData, encoding: .utf8) ?? "No diagnostic output."
    let (events, failure) = collector.finish()
    if let failure {
        throw GenerationError.malformedWorkerEvent(failure.localizedDescription)
    }
    guard process.terminationStatus == 0 else {
        if control?.isStopRequested == true {
            throw GenerationError.stopped
        }
        throw GenerationError.workerFailed(status: process.terminationStatus, diagnostics: diagnostics)
    }
    return events
}

// Accumulates newline-delimited JSON events from the worker's stdout.
// The readability handler runs on a background queue, so all state stays
// behind the lock and the class is the only value the closure captures.
final class KokoroEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingData = Data()
    private var events: [KokoroWorkerEvent] = []
    private var parsingFailure: Error?

    func completedChapterCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return events.filter { $0.type == "chapterCompleted" }.count
    }

    func ingest(_ data: Data) -> [KokoroWorkerEvent] {
        lock.lock()
        defer { lock.unlock() }
        pendingData.append(data)
        var parsed: [KokoroWorkerEvent] = []
        let newline = Data([0x0A])
        while let range = pendingData.range(of: newline) {
            let lineData = pendingData.subdata(in: pendingData.startIndex ..< range.lowerBound)
            pendingData.removeSubrange(pendingData.startIndex ... range.lowerBound)
            guard !lineData.isEmpty else { continue }
            do {
                let event = try JSONDecoder().decode(KokoroWorkerEvent.self, from: lineData)
                events.append(event)
                parsed.append(event)
            } catch {
                parsingFailure = error
            }
        }
        return parsed
    }

    func finish() -> ([KokoroWorkerEvent], Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (events, parsingFailure)
    }
}
