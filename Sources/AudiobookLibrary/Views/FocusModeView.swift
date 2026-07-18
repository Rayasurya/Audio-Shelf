import AppKit
import SwiftUI

// Focus mode: the whole window becomes the listening room. The cover is the
// centerpiece with minimal transport beneath; "Read along" slides in a
// lyrics panel with the narrated line flowing like Apple Music lyrics.
struct FocusModeView: View {
    let book: Audiobook
    let timings: BookTimings?
    let currentSeconds: TimeInterval
    let isPlaying: Bool
    let onToggle: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onExit: () -> Void
    var onRegenerate: (() -> Void)?

    @State private var showLyrics = true

    private var totalSeconds: TimeInterval {
        max(book.narratedChapters.compactMap(\.duration).reduce(0, +), 1)
    }

    private var currentChapter: Chapter? {
        let narrated = book.narratedChapters
        let starts = chapterStartTimes(chapters: narrated)
        return Array(zip(narrated, starts)).last(where: { _, start in start <= currentSeconds })?.0
    }

    private var hasTimings: Bool {
        !(timings?.chapters.flatMap(\.timings).isEmpty ?? true)
    }

    var body: some View {
        ZStack {
            AppPalette.ink.ignoresSafeArea()
            HStack(spacing: 0) {
                coverColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showLyrics {
                    LyricsFlowView(
                        book: book,
                        timings: timings,
                        currentSeconds: currentSeconds,
                        onSeek: onSeek,
                        onRegenerate: onRegenerate,
                        emphasisSize: 27,
                        baseSize: 18
                    )
                    .padding(.horizontal, 44)
                    .padding(.vertical, 30)
                    .frame(maxWidth: 620)
                    .background(AppPalette.frost.opacity(0.035))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            VStack {
                HStack {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.frost.opacity(0.45))
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
        .animation(.easeInOut(duration: 0.3), value: showLyrics)
        .onExitCommand(perform: onExit)
        .foregroundStyle(AppPalette.frost)
    }

    private var coverColumn: some View {
        VStack(spacing: 26) {
            Spacer()
            BookCover(book: book, compact: false, width: 250, height: 348)
                .shadow(color: .black.opacity(0.45), radius: 32, y: 16)
            VStack(spacing: 6) {
                Text(book.title)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                Text(book.author)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(AppPalette.mist.opacity(0.7))
                if let chapter = currentChapter {
                    Text(chapter.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppPalette.accent)
                        .padding(.top, 8)
                }
            }
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { min(currentSeconds, totalSeconds) },
                        set: onSeek
                    ),
                    in: 0 ... totalSeconds
                )
                .labelsHidden()
                .tint(AppPalette.accent)
                HStack {
                    Text(formatDuration(currentSeconds))
                    Spacer()
                    Text(formatDuration(totalSeconds))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppPalette.mist.opacity(0.6))
            }
            .frame(maxWidth: 380)
            focusControls
            Button {
                showLyrics.toggle()
            } label: {
                Label(
                    showLyrics ? "Hide read along" : "Read along",
                    systemImage: showLyrics ? "text.alignright" : "text.aligncenter"
                )
            }
            .buttonStyle(QuietButtonStyle())
            .help(hasTimings ? "Flowing text beside the narration" : "Regenerate this book once to get synced lyrics")
            Spacer()
        }
        .padding(.horizontal, 46)
    }

    private var focusControls: some View {
        HStack(spacing: 26) {
            Button { onSeek(max(0, currentSeconds - 15)) } label: {
                Image(systemName: "gobackward.15")
            }
            .buttonStyle(.plain)
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 23, weight: .bold))
                    .frame(width: 62, height: 62)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.ink)
            .background(AppPalette.accent, in: Circle())
            Button { onSeek(min(totalSeconds, currentSeconds + 30)) } label: {
                Image(systemName: "goforward.30")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(AppPalette.frost.opacity(0.85))
    }
}
