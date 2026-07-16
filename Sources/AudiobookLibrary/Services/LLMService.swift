import Foundation

// Optional local text-intelligence provider: any OpenAI-compatible server on
// this Mac (LM Studio, Ollama, llama.cpp). Book text never leaves the machine
// unless the user points the endpoint elsewhere themselves.
let defaultLLMEndpoint = "http://localhost:1234/v1"

func llmEndpoint() -> String {
    settingsString(SettingsKey.llmEndpoint) ?? defaultLLMEndpoint
}

func isSectionClassificationEnabled() -> Bool {
    if UserDefaults.standard.object(forKey: SettingsKey.llmClassify) == nil { return true }
    return UserDefaults.standard.bool(forKey: SettingsKey.llmClassify)
}

struct LLMStatus: Equatable {
    let isReachable: Bool
    let modelName: String?
}

func checkLLMStatus() async -> LLMStatus {
    guard let url = URL(string: llmEndpoint() + "/models") else {
        return LLMStatus(isReachable: false, modelName: nil)
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 3
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = payload?["data"] as? [[String: Any]] ?? []
        let chatModel = models
            .compactMap { $0["id"] as? String }
            .first { !$0.localizedCaseInsensitiveContains("embed") }
        return LLMStatus(isReachable: true, modelName: chatModel)
    } catch {
        return LLMStatus(isReachable: false, modelName: nil)
    }
}

// Section categories the classifier may assign. Only `body` is narrated by
// default; everything else is excluded with the reason shown in review.
let narratedSectionCategory = "body"
let sectionCategories = ["body", "front_matter", "toc", "license", "notes", "back_matter", "other"]

func classifySections(bookTitle: String, chapters: [Chapter]) async -> [Int: String]? {
    guard let url = URL(string: llmEndpoint() + "/chat/completions") else { return nil }
    // LM Studio JIT-loads a model only when the request names it.
    guard let modelName = await checkLLMStatus().modelName else { return nil }
    let sectionList = chapters.map { chapter in
        let snippet = String(chapter.text.prefix(280)).replacingOccurrences(of: "\n", with: " ")
        return "\(chapter.index). \"\(chapter.title)\" — begins: \(snippet)"
    }.joined(separator: "\n")

    let prompt = """
    You classify sections of the book "\(bookTitle)" for audiobook narration.
    Categories: \(sectionCategories.joined(separator: ", ")).
    "body" = actual book content a listener wants narrated. Publisher boilerplate, \
    licenses, tables of contents, indexes, and editorial notes are not body.
    Sections:
    \(sectionList)

    Reply with ONLY a JSON array, one object per section, no other text:
    [{"index": 1, "category": "body"}, ...]
    """

    let requestBody: [String: Any] = [
        "model": modelName,
        "messages": [["role": "user", "content": prompt]],
        "temperature": 0,
        // Reasoning models spend tokens thinking before the JSON appears, so
        // the budget must cover both. finish_reason=length means it was cut.
        "max_tokens": 6000
    ]
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 180
    request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

    guard let (data, _) = try? await URLSession.shared.data(for: request),
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = payload["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let content = message["content"] as? String
    else { return nil }

    return parseSectionClassifications(content)
}

// Tolerant of models that wrap the JSON in prose or code fences.
func parseSectionClassifications(_ content: String) -> [Int: String]? {
    guard let start = content.firstIndex(of: "["), let end = content.lastIndex(of: "]"), start < end else { return nil }
    let json = String(content[start ... end])
    guard let data = json.data(using: .utf8),
          let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return nil }
    var categories: [Int: String] = [:]
    for entry in entries {
        guard let index = entry["index"] as? Int,
              let category = (entry["category"] as? String)?.lowercased(),
              sectionCategories.contains(category)
        else { continue }
        categories[index] = category
    }
    return categories.isEmpty ? nil : categories
}

// Retells one chapter in plainer language via the local model. Returns nil on
// any failure so callers can stop with a clear message instead of narrating
// half-rewritten books.
func rewriteChapterForEasierListening(bookTitle: String, chapter: Chapter) async -> String? {
    guard let url = URL(string: llmEndpoint() + "/chat/completions"),
          let modelName = await checkLLMStatus().modelName
    else { return nil }

    let prompt = """
    Retell this chapter of "\(bookTitle)" so it is easier to follow when \
    listened to as audio. Keep every plot event, character, and name. Use \
    plain modern language, shorter sentences, and briefly unpack archaic or \
    difficult phrases in place. Remove anything that is not part of the \
    story itself (publisher notes, prices, advertisements). Do not summarize \
    — retell fully. Reply with ONLY the retold chapter text.

    Chapter: \(chapter.title)

    \(chapter.text)
    """
    let requestBody: [String: Any] = [
        "model": modelName,
        "messages": [["role": "user", "content": prompt]],
        "temperature": 0.3,
        "max_tokens": 16_000
    ]
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 600
    request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

    guard let (data, _) = try? await URLSession.shared.data(for: request),
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = payload["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          content.count > 80
    else { return nil }
    return content
}

func applySectionClassifications(_ categories: [Int: String], to chapters: [Chapter]) -> [Chapter] {
    chapters.map { chapter in
        guard let category = categories[chapter.index] else { return chapter }
        var classified = chapter
        classified.sectionCategory = category
        classified.isExcluded = category == narratedSectionCategory ? nil : true
        return classified
    }
}
