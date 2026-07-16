import Foundation
import PDFKit

enum ImportError: LocalizedError {
    case unsupportedFileType(URL)
    case unreadableSource(URL)
    case noReadableText(URL)
    case epubStructureMissing(URL)
    case invalidChapterContent

    var errorDescription: String? {
        switch self {
        case let .unsupportedFileType(url):
            "Unsupported source file: \(url.lastPathComponent). Import a TXT, EPUB, or text-based PDF."
        case let .unreadableSource(url):
            "Could not read \(url.lastPathComponent). Check that the file is available locally and try again."
        case let .noReadableText(url):
            "\(url.lastPathComponent) does not contain selectable text. Scanned PDFs are not part of this MVP."
        case let .epubStructureMissing(url):
            "\(url.lastPathComponent) does not contain a readable EPUB reading order."
        case .invalidChapterContent:
            "The source did not contain enough readable content to create an audiobook."
        }
    }
}

struct ImportedSource: Sendable {
    let title: String
    let author: String
    let chapters: [Chapter]
}

func importSource(url: URL, fileManager: FileManager) throws -> ImportedSource {
    let fileExtension = url.pathExtension.lowercased()
    switch fileExtension {
    case "txt":
        let text = try String(contentsOf: url, encoding: .utf8)
        return try importedTextSource(text: text, fallbackTitle: url.deletingPathExtension().lastPathComponent)
    case "pdf":
        return try importPDF(url: url)
    case "epub":
        return try importEPUB(url: url, fileManager: fileManager)
    default:
        throw ImportError.unsupportedFileType(url)
    }
}

func importedTextSource(text: String, fallbackTitle: String) throws -> ImportedSource {
    let normalized = normalizeSourceText(text)
    guard normalized.count > 120 else { throw ImportError.invalidChapterContent }
    let lines = normalized.components(separatedBy: .newlines)
    let headings = lines.enumerated().filter { isHeading($0.element) }
    let title = firstNonEmptyLine(lines: lines) ?? fallbackTitle
    let chapters = headings.isEmpty
        ? [makeChapter(index: 1, title: "Beginning", text: normalized)]
        : chaptersFromHeadings(lines: lines, headings: headings)
    guard !chapters.isEmpty else { throw ImportError.invalidChapterContent }
    return ImportedSource(title: title, author: "Unknown author", chapters: chapters)
}

func importPDF(url: URL) throws -> ImportedSource {
    guard let document = PDFDocument(url: url) else { throw ImportError.unreadableSource(url) }
    let pageText = (0 ..< document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
    guard !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.noReadableText(url) }
    return try importedTextSource(text: pageText, fallbackTitle: url.deletingPathExtension().lastPathComponent)
}

func importEPUB(url: URL, fileManager: FileManager) throws -> ImportedSource {
    let workspace = fileManager.temporaryDirectory.appending(path: "audiobook-import-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: workspace) }

    try runTool(
        executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
        arguments: ["-qq", "-o", url.path(percentEncoded: false), "-d", workspace.path(percentEncoded: false)]
    )

    let containerURL = workspace.appending(path: "META-INF/container.xml")
    guard let container = try? String(contentsOf: containerURL, encoding: .utf8),
          let packagePath = firstRegexCapture(pattern: "full-path=[\\\"']([^\\\"']+)[\\\"']", in: container)
    else {
        throw ImportError.epubStructureMissing(url)
    }

    let packageURL = workspace.appending(path: packagePath)
    guard let packageText = try? String(contentsOf: packageURL, encoding: .utf8) else {
        throw ImportError.epubStructureMissing(url)
    }

    let title = firstRegexCapture(pattern: "<dc:title[^>]*>(.*?)</dc:title>", in: packageText).map(stripHTML) ?? url.deletingPathExtension().lastPathComponent
    let author = firstRegexCapture(pattern: "<dc:creator[^>]*>(.*?)</dc:creator>", in: packageText).map(stripHTML) ?? "Unknown author"
    let contentDirectory = packageURL.deletingLastPathComponent()
    let manifest = epubManifest(packageText)
    let tocLabels = epubTOCLabels(manifest: manifest, contentDirectory: contentDirectory)
    let spineIDs = allRegexCaptures(pattern: "<itemref[^>]*idref=[\\\"']([^\\\"']+)[\\\"']", in: packageText)
    let chapterURLs = spineIDs.compactMap { manifest[$0]?.href }.map { contentDirectory.appending(path: $0).standardized }
    // Spine items that carry no narratable text (covers, title pages, tables
    // of contents, Project Gutenberg boilerplate) are dropped, so chapters
    // are numbered after filtering to stay contiguous.
    let chapterContent = chapterURLs.compactMap { chapterURL -> (title: String?, text: String)? in
        guard let markup = try? String(contentsOf: chapterURL, encoding: .utf8) else { return nil }
        let labels = tocLabels[chapterURL.standardized.path(percentEncoded: false)] ?? []
        if labels.contains(where: { $0.localizedCaseInsensitiveContains("contents") }) { return nil }
        let text = strippingGutenbergBoilerplate(normalizeSourceText(stripHTML(markup)))
        guard text.count > 80 else { return nil }
        let usableLabels = labels.filter { !isBoilerplateTOCLabel($0) }
        let heading = usableLabels.first
            ?? firstRegexCapture(pattern: "<h1[^>]*>(.*?)</h1>|<h2[^>]*>(.*?)</h2>", in: markup).map(stripHTML)
        return (heading.flatMap { $0.isEmpty ? nil : $0 }, text)
    }
    let chapters = chapterContent.enumerated().map { index, content in
        makeChapter(index: index + 1, title: content.title ?? "Chapter \(index + 1)", text: content.text)
    }
    guard !chapters.isEmpty else { throw ImportError.epubStructureMissing(url) }
    return ImportedSource(title: title, author: author, chapters: chapters)
}

struct EPUBManifestItem {
    let href: String
    let mediaType: String
    let properties: String
}

// Maps each spine document's absolute path to its table-of-contents labels,
// read from the EPUB 2 NCX or the EPUB 3 nav document. Empty when the book
// has no usable TOC — callers then fall back to in-document headings.
func epubTOCLabels(manifest: [String: EPUBManifestItem], contentDirectory: URL) -> [String: [String]] {
    var entries: [(label: String, href: String)] = []
    if let ncx = manifest.values.first(where: { $0.mediaType.contains("dtbncx") }),
       let ncxText = try? String(contentsOf: contentDirectory.appending(path: ncx.href), encoding: .utf8) {
        let baseURL = contentDirectory.appending(path: ncx.href).deletingLastPathComponent()
        entries = allRegexPairCaptures(
            pattern: "<navLabel>\\s*<text>(.*?)</text>[\\s\\S]*?<content[^>]*src=[\\\"']([^\\\"'#]+)",
            in: ncxText
        ).map { (stripHTML($0.0), resolvedPath(href: $0.1, baseURL: baseURL)) }
    } else if let nav = manifest.values.first(where: { $0.properties.contains("nav") }),
              let navText = try? String(contentsOf: contentDirectory.appending(path: nav.href), encoding: .utf8) {
        let baseURL = contentDirectory.appending(path: nav.href).deletingLastPathComponent()
        entries = allRegexPairCaptures(
            pattern: "<a[^>]*href=[\\\"']([^\\\"'#]+)[^>]*>([\\s\\S]*?)</a>",
            in: navText
        ).map { (stripHTML($0.1), resolvedPath(href: $0.0, baseURL: baseURL)) }
    }
    return entries.reduce(into: [:]) { labels, entry in
        let label = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        labels[entry.href, default: []].append(label)
    }
}

func resolvedPath(href: String, baseURL: URL) -> String {
    baseURL.appending(path: href.removingPercentEncoding ?? href).standardized.path(percentEncoded: false)
}

func isBoilerplateTOCLabel(_ label: String) -> Bool {
    label.localizedCaseInsensitiveContains("project gutenberg") || label.localizedCaseInsensitiveContains("license")
}

// Project Gutenberg wraps every book in a header that ends with
// "*** START OF THE PROJECT GUTENBERG EBOOK ... ***" and a license that
// begins with "*** END OF THE PROJECT GUTENBERG EBOOK ... ***". Neither
// belongs in narration, and the end marker can share a file with the last
// chapter, so the text is trimmed around the markers rather than dropped.
func strippingGutenbergBoilerplate(_ text: String) -> String {
    var result = text
    if let range = result.range(
        of: "\\*\\*\\*\\s*START OF THE PROJECT GUTENBERG[^*]*\\*\\*\\*",
        options: [.regularExpression, .caseInsensitive]
    ) {
        result = String(result[range.upperBound...])
    }
    if let range = result.range(
        of: "\\*\\*\\*\\s*END OF THE PROJECT GUTENBERG",
        options: [.regularExpression, .caseInsensitive]
    ) {
        result = String(result[..<range.lowerBound])
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

func epubManifest(_ packageText: String) -> [String: EPUBManifestItem] {
    let itemMatches = allRegexCaptures(pattern: "<item\\s+([^>]+)>", in: packageText)
    return itemMatches.reduce(into: [:]) { manifest, attributes in
        guard let id = firstRegexCapture(pattern: "id=[\\\"']([^\\\"']+)[\\\"']", in: attributes),
              let href = firstRegexCapture(pattern: "href=[\\\"']([^\\\"']+)[\\\"']", in: attributes)
        else { return }
        manifest[id] = EPUBManifestItem(
            href: href,
            mediaType: firstRegexCapture(pattern: "media-type=[\\\"']([^\\\"']+)[\\\"']", in: attributes) ?? "",
            properties: firstRegexCapture(pattern: "properties=[\\\"']([^\\\"']+)[\\\"']", in: attributes) ?? ""
        )
    }
}

func normalizeSourceText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        // Decorative scene-break rows ("* * * *", "----", "· · ·") are visual
        // furniture — a narrator would read them aloud, so they go.
        .replacingOccurrences(of: "(?m)^[ \\t*_\\-•·=~]{2,}$", with: "", options: .regularExpression)
        .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func isHeading(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 2, trimmed.count < 100 else { return false }
    return trimmed.range(of: "^(chapter|part|book|section)\\s+([0-9ivxlcdm]+|[a-z]+)", options: [.regularExpression, .caseInsensitive]) != nil
}

func chaptersFromHeadings(lines: [String], headings: [(offset: Int, element: String)]) -> [Chapter] {
    headings.enumerated().compactMap { index, heading in
        let start = heading.offset
        let end = index + 1 < headings.count ? headings[index + 1].offset : lines.count
        let text = lines[start ..< end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 80 else { return nil }
        return makeChapter(index: index + 1, title: heading.element.trimmingCharacters(in: .whitespacesAndNewlines), text: text)
    }
}

func makeChapter(index: Int, title: String, text: String) -> Chapter {
    Chapter(id: UUID(), index: index, title: title, text: text, audioURL: nil, duration: nil)
}

func firstNonEmptyLine(lines: [String]) -> String? {
    guard let line = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
        return nil
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
}

func stripHTML(_ value: String) -> String {
    let withoutScripts = value.replacingOccurrences(of: "<head[^>]*>[\\s\\S]*?</head>|<script[^>]*>[\\s\\S]*?</script>|<style[^>]*>[\\s\\S]*?</style>", with: " ", options: .regularExpression)
    let withoutTags = withoutScripts.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    return withoutTags
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
}

func firstRegexCapture(pattern: String, in value: String) -> String? {
    allRegexCaptures(pattern: pattern, in: value).first
}

func allRegexPairCaptures(pattern: String, in value: String) -> [(String, String)] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
    let range = NSRange(value.startIndex..., in: value)
    return expression.matches(in: value, range: range).compactMap { match in
        guard match.numberOfRanges >= 3,
              let first = Range(match.range(at: 1), in: value),
              let second = Range(match.range(at: 2), in: value)
        else { return nil }
        return (String(value[first]), String(value[second]))
    }
}

func allRegexCaptures(pattern: String, in value: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
    let range = NSRange(value.startIndex..., in: value)
    return expression.matches(in: value, range: range).compactMap { match in
        (1 ..< match.numberOfRanges).compactMap { group -> String? in
            let groupRange = match.range(at: group)
            guard groupRange.location != NSNotFound, let range = Range(groupRange, in: value) else { return nil }
            return String(value[range])
        }.first
    }
}

func runTool(executableURL: URL, arguments: [String]) throws {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? "No diagnostic output."
        throw NSError(
            domain: "AudiobookLibrary.Tool",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "\(executableURL.lastPathComponent) failed with status \(process.terminationStatus): \(errorText)"]
        )
    }
}
