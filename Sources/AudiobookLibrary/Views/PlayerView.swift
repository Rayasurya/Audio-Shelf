import SwiftUI
import Foundation

enum PlayerPane: String, CaseIterable {
    case chapters = "Chapters"
    case text = "Read along"
}

struct PlayerView: View {
    let book: Audiobook
    let timings: BookTimings?
    let currentSeconds: TimeInterval
    let isPlaying: Bool
    let playbackRate: Float
    let onBack: () -> Void
    let onToggle: () -> Void
    let onSetRate: (Float) -> Void
    let onSeek: (TimeInterval) -> Void
    let onFocus: () -> Void
    let onRegenerate: () -> Void

    @State private var pane: PlayerPane = .chapters

    private var totalSeconds: TimeInterval {
        max(book.narratedChapters.compactMap(\.duration).reduce(0, +), 1)
    }

    private var currentChapter: Chapter? {
        let chapterStarts = chapterStartTimes(chapters: book.narratedChapters)
        return Array(zip(book.narratedChapters, chapterStarts)).last(where: { _, start in start <= currentSeconds })?.0
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button(action: onBack) {
                        Label("Library", systemImage: "chevron.left")
                    }
                    .buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button(action: onFocus) {
                        Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .help("Full-screen flowing text with the narration")
                }
                Spacer()
                BookCover(book: book, compact: false)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Text(book.author)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(AppPalette.mist.opacity(0.70))
                    if let record = book.generationRecord {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Narrated by \(record.provider) · \(record.voice)")
                            Text("\(record.generatedAt.formatted(date: .abbreviated, time: .shortened))\(record.audioBytes.map { " · \(formatBytes($0))" } ?? "")")
                        }
                        .font(.caption2)
                        .foregroundStyle(AppPalette.mist.opacity(0.55))
                        .padding(.top, 6)
                    }
                    if let episodesURL = book.episodesURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([episodesURL])
                        } label: {
                            Label("Show podcast episodes", systemImage: "square.stack")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .padding(.top, 8)
                    }
                }
                Spacer()
            }
            .frame(width: 250)
            .padding(20)
            .background(AppPalette.sea)

            VStack(spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(currentChapter?.title.uppercased() ?? "BEGINNING")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.3)
                            .foregroundStyle(AppPalette.accent)
                            .lineLimit(1)
                        Text("Chapter \(currentChapter?.index ?? 1)")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)
                    }
                    Spacer()
                    Picker("View", selection: $pane) {
                        ForEach(PlayerPane.allCases, id: \.self) { pane in
                            Text(pane.rawValue).tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                VStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { min(currentSeconds, totalSeconds) },
                            set: onSeek
                        ),
                        in: 0 ... totalSeconds
                    )
                    .tint(AppPalette.accent)
                    .controlSize(.large)
                    HStack {
                        Text(formatDuration(currentSeconds))
                        Spacer()
                        Text(formatDuration(totalSeconds))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppPalette.mist.opacity(0.66))
                }

                HStack(spacing: 34) {
                    Button { onSeek(max(0, currentSeconds - 15)) } label: {
                        Image(systemName: "gobackward.15")
                    }
                    .buttonStyle(.plain)
                    Button(action: onToggle) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .frame(width: 64, height: 64)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .foregroundStyle(AppPalette.ink)
                    .background(AppPalette.accent, in: Circle())
                    Button { onSeek(min(totalSeconds, currentSeconds + 30)) } label: {
                        Image(systemName: "goforward.30")
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 22, weight: .medium))
                .frame(maxWidth: .infinity)

                HStack(spacing: 14) {
                    Text("Speed")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppPalette.mist.opacity(0.7))
                    Slider(
                        value: Binding(
                            get: { Double(playbackRate) },
                            set: { onSetRate(Float($0)) }
                        ),
                        in: 0.5 ... 3.0,
                        step: 0.05
                    )
                    .labelsHidden()
                    .tint(AppPalette.accent)
                    Text("\(String(format: "%.2f", playbackRate))×")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppPalette.accent)
                        .frame(width: 46, alignment: .trailing)
                }

                Divider().overlay(AppPalette.mist.opacity(0.14))

                switch pane {
                case .chapters:
                    ChapterTimeline(book: book, currentSeconds: currentSeconds, onSeek: onSeek)
                case .text:
                    LyricsFlowView(book: book, timings: timings, currentSeconds: currentSeconds, onSeek: onSeek, onRegenerate: onRegenerate)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(AppPalette.frost)
        .background(AppPalette.ink)
    }
}

struct ChapterTimeline: View {
    let book: Audiobook
    let currentSeconds: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        let starts = chapterStartTimes(chapters: book.narratedChapters)
        VStack(alignment: .leading, spacing: 9) {
            Text("CHAPTERS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(AppPalette.mist.opacity(0.62))
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(Array(zip(book.narratedChapters, starts)), id: \.0.id) { chapter, start in
                        Button {
                            onSeek(start)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(chapter.index)")
                                    .foregroundStyle(AppPalette.accent)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title).lineLimit(1)
                                    Text(formatDuration(chapter.duration ?? 0))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(AppPalette.mist.opacity(0.62))
                                }
                                Spacer()
                                if start <= currentSeconds, currentSeconds < start + (chapter.duration ?? 0) {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(AppPalette.river)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(AppPalette.frost.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// One narrated line with its absolute position in the book's audio.
struct LyricLine: Identifiable, Equatable {
    let id: Int
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

func lyricLines(book: Audiobook, timings: BookTimings?) -> [LyricLine] {
    guard let timings else { return [] }
    let narrated = book.narratedChapters
    let starts = chapterStartTimes(chapters: narrated)
    let startByIndex = Dictionary(uniqueKeysWithValues: zip(narrated.map(\.index), starts))
    var lines: [LyricLine] = []
    for chapter in timings.chapters {
        guard let chapterStart = startByIndex[chapter.index] else { continue }
        for timing in chapter.timings {
            lines.append(LyricLine(
                id: lines.count,
                text: timing.text.trimmingCharacters(in: .whitespacesAndNewlines),
                start: chapterStart + timing.start,
                end: chapterStart + timing.end
            ))
        }
    }
    return lines
}

func currentLyricIndex(_ lines: [LyricLine], currentSeconds: TimeInterval) -> Int? {
    guard !lines.isEmpty else { return nil }
    return lines.lastIndex(where: { $0.start <= currentSeconds }) ?? 0
}

// Apple Music-style flowing lyrics: the narrated line is large and bright,
// its neighbors recede; the view drifts with the voice; tapping a line seeks.
struct LyricsFlowView: View {
    let book: Audiobook
    let timings: BookTimings?
    let currentSeconds: TimeInterval
    let onSeek: (TimeInterval) -> Void
    var onRegenerate: (() -> Void)?
    var emphasisSize: CGFloat = 24
    var baseSize: CGFloat = 17

    var body: some View {
        let lines = lyricLines(book: book, timings: timings)
        if lines.isEmpty {
            fallbackReader
        } else {
            let current = currentLyricIndex(lines, currentSeconds: currentSeconds)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LyricLinesStack(
                        lines: lines,
                        currentIndex: current,
                        emphasisSize: emphasisSize,
                        baseSize: baseSize,
                        onSeek: onSeek
                    )
                }
                .onChange(of: current) { _, newIndex in
                    if let newIndex {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: .center) }
                }
            }
        }
    }

    // Books generated before timing manifests existed: name the problem, offer
    // the fix, and stay readable meanwhile. Never a silent fallback.
    private var fallbackReader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("This book predates read-along.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("Its audio has no sentence timings, so lyrics can't sync. Regenerating adds them.")
                        .font(.system(size: 12, design: .rounded))
                        .opacity(0.8)
                }
                Spacer()
                if let onRegenerate {
                    Button("Regenerate for read-along", action: onRegenerate)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(12)
            .foregroundStyle(AppPalette.frost)
            .background(AppPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppPalette.accent.opacity(0.5), lineWidth: 1)
            }
            LyricsFallbackReader(book: book, currentSeconds: currentSeconds)
        }
    }
}

// The flowing lines themselves — separate from the ScrollView so they can be
// rendered headlessly for layout verification.
struct LyricLinesStack: View {
    let lines: [LyricLine]
    let currentIndex: Int?
    let emphasisSize: CGFloat
    let baseSize: CGFloat
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Color.clear.frame(height: 60)
            ForEach(lines) { line in
                let isCurrent = line.id == currentIndex
                Text(line.text)
                    .font(.system(size: isCurrent ? emphasisSize : baseSize, weight: isCurrent ? .bold : .medium, design: .serif))
                    .foregroundStyle(isCurrent ? AppPalette.frost : AppPalette.frost.opacity(0.32))
                    .lineSpacing(isCurrent ? 7 : 4)
                    .blur(radius: isCurrent ? 0 : 0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .id(line.id)
                    .onTapGesture { onSeek(line.start) }
                    .contextMenu { WordLookupMenu(text: line.text) }
            }
            Color.clear.frame(height: 120)
        }
        .animation(.easeInOut(duration: 0.3), value: currentIndex)
    }
}

struct LyricsFallbackReader: View {
    let book: Audiobook
    let currentSeconds: TimeInterval

    var body: some View {
        let narrated = book.narratedChapters
        let starts = chapterStartTimes(chapters: narrated)
        let info = Array(zip(narrated, starts)).last(where: { _, start in start <= currentSeconds })
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Generated before read-along existed — regenerate this book to get flowing lyrics.")
                    .font(.caption)
                    .foregroundStyle(AppPalette.mist.opacity(0.55))
                if let info {
                    Text(info.0.title)
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.mist.opacity(0.9))
                    Text(info.0.text)
                        .font(.system(size: 15, design: .serif))
                        .lineSpacing(6)
                        .foregroundStyle(AppPalette.frost.opacity(0.85))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

func chapterStartTimes(chapters: [Chapter]) -> [TimeInterval] {
    var cursor: TimeInterval = 0
    return chapters.map { chapter in
        defer { cursor += chapter.duration ?? 0 }
        return cursor
    }
}

// Right-click "understand this word": every distinct word of the sentence
// opens in the system Dictionary — local, instant, no model required.
struct WordLookupMenu: View {
    let text: String

    var body: some View {
        Menu("Look up a word") {
            ForEach(lookupWords(in: text), id: \.self) { word in
                Button(word) {
                    if let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                       let url = URL(string: "dict://\(encoded)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

func lookupWords(in text: String) -> [String] {
    var seen = Set<String>()
    var words: [String] = []
    for raw in text.split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
        let word = String(raw)
        guard word.count > 3 else { continue }
        if seen.insert(word.lowercased()).inserted {
            words.append(word)
        }
        if words.count == 18 { break }
    }
    return words
}

func formatBytes(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let integerSeconds = max(0, Int(seconds.rounded(.down)))
    let minutes = integerSeconds / 60
    let remainder = integerSeconds % 60
    return String(format: "%d:%02d", minutes, remainder)
}
