import Foundation

// User-adjustable environment settings, persisted in UserDefaults so the
// bundled app works when launched from Finder (where the working directory
// gives no hint of the repo layout).
enum SettingsKey {
    static let kokoroPython = "kokoroPythonPath"
    static let ffmpeg = "ffmpegPath"
    static let voice = "narrationVoice"
    static let textRules = "narrationTextRules"
    static let llmEndpoint = "llmEndpoint"
    static let llmClassify = "llmClassifySectionsOnImport"
    static let playbackRate = "preferredPlaybackRate"
    static let autoFocusOnPlay = "autoFocusOnPlay"
    static let skipCategories = "playbackSkipCategories"
    static let fastLLMEndpoint = "fastLLMEndpoint"
    static let fastLLMModel = "fastLLMModel"
}

func preferredPlaybackRate() -> Float {
    let stored = UserDefaults.standard.float(forKey: SettingsKey.playbackRate)
    return stored == 0 ? 1 : min(3, max(0.5, stored))
}

func savePreferredPlaybackRate(_ rate: Float) {
    UserDefaults.standard.set(rate, forKey: SettingsKey.playbackRate)
}

func autoFocusOnPlay() -> Bool {
    UserDefaults.standard.bool(forKey: SettingsKey.autoFocusOnPlay)
}

// Section categories the listener wants auto-skipped during playback (for
// sections they chose to narrate but don't always want to hear).
func playbackSkipCategories() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: SettingsKey.skipCategories) ?? [])
}

func savePlaybackSkipCategories(_ categories: Set<String>) {
    UserDefaults.standard.set(Array(categories).sorted(), forKey: SettingsKey.skipCategories)
}

// When playback sits inside a narrated chapter whose category the listener
// skips, returns where to jump: the next non-skipped chapter's start, or the
// end of the book if none remains.
func skipTargetSeconds(book: Audiobook, currentSeconds: TimeInterval, skips: Set<String>) -> TimeInterval? {
    guard !skips.isEmpty else { return nil }
    let narrated = book.narratedChapters
    let starts = chapterStartTimes(chapters: narrated)
    guard let position = Array(zip(narrated, starts)).lastIndex(where: { $0.1 <= currentSeconds }) else { return nil }
    guard let category = narrated[position].sectionCategory, skips.contains(category) else { return nil }
    for next in (position + 1) ..< narrated.count {
        if let nextCategory = narrated[next].sectionCategory, skips.contains(nextCategory) { continue }
        return starts[next]
    }
    return starts.last.map { $0 + (narrated.last?.duration ?? 0) }
}

// A listener-defined narration workflow rule: occurrences of `pattern`
// (matched as whole words, case-insensitively) are replaced before the text
// reaches the narration provider. An empty replacement removes the word —
// e.g. trigger words a listener never wants voiced.
struct TextRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var pattern: String
    var replacement: String

    init(id: UUID = UUID(), pattern: String, replacement: String) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
    }
}

func loadTextRules() -> [TextRule] {
    guard let data = UserDefaults.standard.data(forKey: SettingsKey.textRules),
          let rules = try? JSONDecoder().decode([TextRule].self, from: data)
    else { return [] }
    return rules
}

func saveTextRules(_ rules: [TextRule]) {
    guard let data = try? JSONEncoder().encode(rules) else { return }
    UserDefaults.standard.set(data, forKey: SettingsKey.textRules)
}

func applyTextRules(_ text: String, rules: [TextRule]) -> String {
    guard !rules.isEmpty else { return text }
    var result = text
    for rule in rules {
        let trimmed = rule.pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: trimmed) + "\\b"
        let template = rule.replacement
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
        result = result.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
    }
    return result
        .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        .replacingOccurrences(of: " ([,.;:!?])", with: "$1", options: .regularExpression)
}

let defaultNarrationVoice = "af_sarah"

// Curated Kokoro voices; the worker accepts any voice id the model ships.
let availableNarrationVoices = [
    "af_sarah", "af_bella", "af_heart", "af_nicole",
    "am_adam", "am_michael",
    "bf_emma", "bf_isabella",
    "bm_george", "bm_lewis"
]

func settingsString(_ key: String) -> String? {
    guard let value = UserDefaults.standard.string(forKey: key),
          !value.trimmingCharacters(in: .whitespaces).isEmpty
    else { return nil }
    return value
}

func selectedNarrationVoice() -> String {
    settingsString(SettingsKey.voice) ?? defaultNarrationVoice
}

struct EnvironmentCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let isReady: Bool
}

func runEnvironmentPreflight(fileManager: FileManager) -> [EnvironmentCheck] {
    var checks: [EnvironmentCheck] = []
    do {
        let python = try kokoroPythonURL(fileManager: fileManager)
        checks.append(EnvironmentCheck(id: "kokoro", title: "Kokoro narration", detail: python.path(percentEncoded: false), isReady: true))
    } catch {
        checks.append(EnvironmentCheck(
            id: "kokoro",
            title: "Kokoro narration",
            detail: "Not found. Set the Python path in Settings (⌘,).",
            isReady: false
        ))
    }
    do {
        let ffmpeg = try ffmpegURL(fileManager: fileManager)
        checks.append(EnvironmentCheck(id: "ffmpeg", title: "Audio packaging (ffmpeg)", detail: ffmpeg.path(percentEncoded: false), isReady: true))
    } catch {
        checks.append(EnvironmentCheck(
            id: "ffmpeg",
            title: "Audio packaging (ffmpeg)",
            detail: "Not found. Install ffmpeg or set its path in Settings (⌘,).",
            isReady: false
        ))
    }
    if (try? kokoroWorkerURL()) != nil {
        checks.append(EnvironmentCheck(id: "worker", title: "Narration worker", detail: "Bundled with the app", isReady: true))
    } else {
        checks.append(EnvironmentCheck(id: "worker", title: "Narration worker", detail: "Missing from the app bundle. Reinstall Audio Shelf.", isReady: false))
    }
    return checks
}
