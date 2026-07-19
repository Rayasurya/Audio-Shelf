import SwiftUI

struct GenerationView: View {
    let book: Audiobook
    let job: GenerationJob?
    let isStopping: Bool
    let onStop: () -> Void
    let onReturnToLibrary: () -> Void

    private var phases: [GenerationPhase] {
        var list: [GenerationPhase] = []
        if book.contentPreferences?.isEmpty == false, book.narrationStyle != .easier {
            list.append(.cleaning)
        }
        if book.narrationStyle == .easier {
            list.append(.retelling)
        }
        return list + [.narrating, .packaging]
    }

    private var currentPhase: GenerationPhase { job?.phase ?? .preparing }

    // Narration is the only phase with real per-chapter fractions; the
    // others show activity, not a pretend percentage.
    private var isDeterminate: Bool {
        currentPhase == .narrating || currentPhase == .retelling || currentPhase == .cleaning
    }

    var body: some View {
        VStack(spacing: Gap.s4) {
            BookCover(book: book, compact: false)
            VStack(spacing: 6) {
                Text("Making your audiobook")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                Text("Everything runs locally on this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppPalette.mist.opacity(0.74))
            }

            phaseStrip

            AppSurface {
                VStack(alignment: .leading, spacing: Gap.s2) {
                    HStack {
                        Text(job?.currentChapterTitle ?? "Getting ready")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        if let job, job.totalChapters > 0, isDeterminate {
                            Text("\(job.completedChapters) / \(job.totalChapters)")
                                .font(.system(size: 13, weight: .bold).monospacedDigit())
                                .foregroundStyle(AppPalette.accent)
                        }
                    }
                    if let job, isDeterminate {
                        ProgressView(value: job.fraction)
                            .tint(AppPalette.accent)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppPalette.accent)
                    }
                    HStack {
                        Text("Completed chapters are saved immediately — stopping never loses finished work.")
                        Spacer()
                        if let startedAt = job?.startedAt {
                            ElapsedTimeText(since: startedAt)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppPalette.mist.opacity(0.66))
                }
                .padding(Gap.s3)
            }
            .frame(maxWidth: 560)

            HStack(spacing: Gap.s2) {
                Button("Keep browsing", action: onReturnToLibrary)
                    .buttonStyle(QuietButtonStyle())
                Button {
                    onStop()
                } label: {
                    Label(isStopping ? "Stopping…" : "Stop narration", systemImage: "stop.fill")
                        .foregroundStyle(AppPalette.rose)
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isStopping || job == nil)
            }
            Text(isStopping
                ? "Finishing the current passage, then saving — a few seconds."
                : "Stopping keeps the \(job?.completedChapters ?? 0) finished chapters — resume anytime.")
                .font(.caption)
                .foregroundStyle(AppPalette.mist.opacity(0.55))
        }
        .padding(Gap.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.ink)
        .foregroundStyle(AppPalette.frost)
    }

    private var phaseStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(phases.enumerated()), id: \.element) { index, phase in
                if index > 0 {
                    Text("·").foregroundStyle(AppPalette.mist.opacity(0.4))
                }
                phaseLabel(phase)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    @ViewBuilder
    private func phaseLabel(_ phase: GenerationPhase) -> some View {
        let phaseOrder = phases
        let currentIndex = phaseOrder.firstIndex(of: currentPhase) ?? -1
        let phaseIndex = phaseOrder.firstIndex(of: phase) ?? 0
        if phaseIndex < currentIndex {
            Label(phase.title, systemImage: "checkmark")
                .foregroundStyle(AppPalette.mist.opacity(0.75))
        } else if phase == currentPhase {
            Text(phase.title)
                .foregroundStyle(AppPalette.accent)
        } else {
            Text(phase.title)
                .foregroundStyle(AppPalette.mist.opacity(0.4))
        }
    }
}

// Ticks once a second while visible; plain text otherwise.
struct ElapsedTimeText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Text("\(seconds / 60) min \(seconds % 60) s elapsed")
                .monospacedDigit()
        }
    }
}
