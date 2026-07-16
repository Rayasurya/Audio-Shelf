import AppKit
import SwiftUI

// Focus mode: the whole window becomes the narration — one sentence large in
// the center, its neighbors dimmed above and below, nothing else competing
// for attention. Built for listeners who want a single point of focus
// (ADHD-friendly), it doubles as the full-screen read-along.
struct FocusModeView: View {
    let book: Audiobook
    let timings: BookTimings?
    let currentSeconds: TimeInterval
    let isPlaying: Bool
    let onToggle: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onExit: () -> Void

    private struct FocusChunk: Identifiable {
        let id: Int
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    private var chunks: [FocusChunk] {
        guard let timings else { return [] }
        let starts = chapterStartTimes(chapters: book.narratedChapters)
        let startByIndex = Dictionary(uniqueKeysWithValues: zip(book.narratedChapters.map(\.index), starts))
        var flattened: [FocusChunk] = []
        for chapter in timings.chapters {
            guard let chapterStart = startByIndex[chapter.index] else { continue }
            for timing in chapter.timings {
                flattened.append(FocusChunk(
                    id: flattened.count,
                    text: timing.text,
                    start: chapterStart + timing.start,
                    end: chapterStart + timing.end
                ))
            }
        }
        return flattened
    }

    private var currentIndex: Int? {
        let all = chunks
        guard !all.isEmpty else { return nil }
        return all.lastIndex(where: { $0.start <= currentSeconds }) ?? 0
    }

    var body: some View {
        ZStack {
            AppPalette.ink.ignoresSafeArea()
            let all = chunks
            if let index = currentIndex, !all.isEmpty {
                VStack(spacing: 34) {
                    Spacer()
                    if index > 0 {
                        Text(all[index - 1].text)
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(AppPalette.paper.opacity(0.28))
                            .lineLimit(2)
                            .onTapGesture { onSeek(all[index - 1].start) }
                    }
                    Text(all[index].text)
                        .font(.system(size: 30, weight: .medium, design: .serif))
                        .lineSpacing(9)
                        .foregroundStyle(AppPalette.paper)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: index)
                        .contextMenu { WordLookupMenu(text: all[index].text) }
                    if index + 1 < all.count {
                        Text(all[index + 1].text)
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(AppPalette.paper.opacity(0.28))
                            .lineLimit(2)
                            .onTapGesture { onSeek(all[index + 1].start) }
                    }
                    Spacer()
                    focusControls
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)
                .padding(48)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 20) {
                    Text("This book was generated before read-along timings existed.")
                        .foregroundStyle(AppPalette.paper.opacity(0.75))
                    Text("Resume its narration once to gain focus mode.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.paper.opacity(0.5))
                    focusControls
                }
            }
            VStack {
                HStack {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.paper.opacity(0.45))
                    Spacer()
                    Button(action: onExit) {
                        Label("Exit focus", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                .padding(22)
                Spacer()
            }
        }
        .onExitCommand(perform: onExit)
    }

    private var focusControls: some View {
        HStack(spacing: 22) {
            Button { onSeek(max(0, currentSeconds - 15)) } label: {
                Image(systemName: "gobackward.15")
            }
            .buttonStyle(.plain)
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.ink)
            .background(AppPalette.copper, in: Circle())
            Button { onSeek(currentSeconds + 30) } label: {
                Image(systemName: "goforward.30")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(AppPalette.paper.opacity(0.8))
    }
}
