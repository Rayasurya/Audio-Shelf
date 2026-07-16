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
            .frame(width: 290)
            .padding(28)
            .background(AppPalette.sea)

            VStack(spacing: 26) {
                VStack(spacing: 7) {
                    Text(currentChapter?.title ?? "Beginning")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(AppPalette.copper)
                    Text("Chapter \(currentChapter?.index ?? 1)")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { min(currentSeconds, totalSeconds) },
                            set: onSeek
                        ),
                        in: 0 ... totalSeconds
                    )
                    .tint(AppPalette.copper)
                    HStack {
                        Text(formatDuration(currentSeconds))
                        Spacer()
                        Text(formatDuration(totalSeconds))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppPalette.mist.opacity(0.66))
                }

                HStack(spacing: 30) {
                    Button { onSeek(max(0, currentSeconds - 15)) } label: {
                        Image(systemName: "gobackward.15")
                    }
                    .buttonStyle(.plain)
                    Button(action: onToggle) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .frame(width: 70, height: 70)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppPalette.ink)
                    .background(AppPalette.copper, in: Circle())
                    Button { onSeek(min(totalSeconds, currentSeconds + 30)) } label: {
                        Image(systemName: "goforward.30")
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 22, weight: .medium))

                VStack(spacing: 5) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text("\(String(format: "%.2f", playbackRate))×")
                            .monospacedDigit()
                            .foregroundStyle(AppPalette.copper)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Slider(
                        value: Binding(
                            get: { Double(playbackRate) },
                            set: { onSetRate(Float($0)) }
                        ),
                        in: 0.5 ... 3.0,
                        step: 0.05
                    ) {
                        Text("Playback speed")
                    } minimumValueLabel: {
                        Text("0.5×").font(.caption2)
                    } maximumValueLabel: {
                        Text("3×").font(.caption2)
                    }
                    .tint(AppPalette.copper)
                    .controlSize(.small)
                }
                .frame(maxWidth: 340)
                .foregroundStyle(AppPalette.mist.opacity(0.85))
                Divider().overlay(AppPalette.mist.opacity(0.16))
                Picker("View", selection: $pane) {
                    ForEach(PlayerPane.allCases, id: \.self) { pane in
                        Text(pane.rawValue).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                switch pane {
                case .chapters:
                    ChapterTimeline(book: book, currentSeconds: currentSeconds, onSeek: onSeek)
                case .text:
                    ReadAlongView(book: book, timings: timings, currentSeconds: currentSeconds, onSeek: onSeek)
                }
            }
            .padding(42)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(AppPalette.paper)
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
                LazyVStack(spacing: 5) {
                    ForEach(Array(zip(book.narratedChapters, starts)), id: \.0.id) { chapter, start in
                        Button {
                            onSeek(start)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(chapter.index)")
                                    .foregroundStyle(AppPalette.copper)
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
                            .background(AppPalette.paper.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// Shows the current chapter's text while listening. With a timing manifest,
// the chunk being narrated is highlighted and tappable to seek; without one
// (books generated before timings existed) it is plain readable text.
struct ReadAlongView: View {
    let book: Audiobook
    let timings: BookTimings?
    let currentSeconds: TimeInterval
    let onSeek: (TimeInterval) -> Void

    private var currentChapterInfo: (chapter: Chapter, start: TimeInterval)? {
        let starts = chapterStartTimes(chapters: book.narratedChapters)
        return Array(zip(book.narratedChapters, starts)).last(where: { _, start in start <= currentSeconds })
    }

    var body: some View {
        if let info = currentChapterInfo {
            let chunkTimings = timings?.chapters.first(where: { $0.index == info.chapter.index })?.timings ?? []
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(info.chapter.title)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.mist.opacity(0.85))
                        if chunkTimings.isEmpty {
                            Text(info.chapter.text)
                                .font(.system(size: 15, design: .serif))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        } else {
                            ForEach(Array(chunkTimings.enumerated()), id: \.offset) { index, chunk in
                                let isCurrent = isCurrentChunk(chunk, chapterStart: info.start)
                                Text(chunk.text)
                                    .font(.system(size: 15, design: .serif))
                                    .lineSpacing(5)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(isCurrent ? AppPalette.paper : AppPalette.paper.opacity(0.62))
                                    .background(
                                        isCurrent ? AppPalette.copper.opacity(0.22) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .id(index)
                                    .onTapGesture { onSeek(info.start + chunk.start) }
                                    .contextMenu { WordLookupMenu(text: chunk.text) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
                }
                .onChange(of: currentChunkIndex(chunkTimings, chapterStart: info.start)) { _, newIndex in
                    if let newIndex {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        } else {
            Text("Start playing to follow the text.")
                .foregroundStyle(AppPalette.mist.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func isCurrentChunk(_ chunk: ChunkTiming, chapterStart: TimeInterval) -> Bool {
        let absoluteStart = chapterStart + chunk.start
        let absoluteEnd = chapterStart + chunk.end
        return absoluteStart <= currentSeconds && currentSeconds < absoluteEnd
    }

    private func currentChunkIndex(_ chunks: [ChunkTiming], chapterStart: TimeInterval) -> Int? {
        chunks.firstIndex(where: { isCurrentChunk($0, chapterStart: chapterStart) })
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
