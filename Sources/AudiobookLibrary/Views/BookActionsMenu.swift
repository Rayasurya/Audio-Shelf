import SwiftUI

// Every per-book action, one visible menu — identical on sidebar rows, the
// workroom hero, and grid cards. Entries adapt to the book's status and
// capabilities; destructive removal always confirms (dialog lives in RootView).
struct BookActions {
    let onPlay: (UUID) -> Void
    let onReview: (UUID) -> Void
    let onProgress: (UUID) -> Void
    let onResume: (UUID) -> Void
    let onRegenerate: (UUID) -> Void
    let onDetails: (UUID) -> Void
    let onExport: (UUID) -> Void
    let onRevealFiles: (UUID) -> Void
    let onRemove: (UUID) -> Void
    var onStop: () -> Void = {}
    var onDequeue: (UUID) -> Void = { _ in }
}

struct BookActionsMenu: View {
    let book: Audiobook
    let actions: BookActions
    var isQueued: Bool = false

    var body: some View {
        Menu {
            switch book.status {
            case .readyToListen:
                Button("Listen now") { actions.onPlay(book.id) }
            case .generating:
                Button("View progress") { actions.onProgress(book.id) }
                Button("Stop narration", role: .destructive) { actions.onStop() }
            case .readyForReview:
                Button("Review book") { actions.onReview(book.id) }
            case .paused, .failed:
                Button("Resume narration") { actions.onResume(book.id) }
            }
            if isQueued {
                Button("Remove from queue") { actions.onDequeue(book.id) }
            }
            Button("Details…") { actions.onDetails(book.id) }
            Divider()
            if book.status != .generating {
                Button("Review & regenerate") { actions.onReview(book.id) }
            }
            if book.generatedURL != nil {
                Button("Export audiobook…") { actions.onExport(book.id) }
            }
            if let episodesURL = book.episodesURL {
                Button("Show podcast episodes") {
                    NSWorkspace.shared.activateFileViewerSelecting([episodesURL])
                }
            }
            Button("Show files in Finder") { actions.onRevealFiles(book.id) }
            Divider()
            Button("Remove from library…", role: .destructive) { actions.onRemove(book.id) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(AppPalette.mist.opacity(0.8))
    }
}

// D5: everything the app knows about one book, honestly laid out.
struct BookDetailsView: View {
    let book: Audiobook
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                BookCover(book: book, compact: false, width: 72, height: 100)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                    Text(book.author)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AppPalette.mist.opacity(0.75))
                    StatusPill(status: book.status)
                }
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)

            Divider().overlay(AppPalette.mist.opacity(0.15))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    detailsGrid
                    Text("CHAPTERS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(AppPalette.mist.opacity(0.6))
                        .padding(.top, 6)
                    ForEach(book.chapters) { chapter in
                        HStack(spacing: 10) {
                            Text("\(chapter.index)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppPalette.copper)
                                .frame(width: 22, alignment: .trailing)
                            Text(chapter.title)
                                .lineLimit(1)
                                .opacity(chapter.isExcluded == true ? 0.45 : 1)
                            if let category = chapter.sectionCategory, category != narratedSectionCategory {
                                Text(category.replacingOccurrences(of: "_", with: " "))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppPalette.mist.opacity(0.12), in: Capsule())
                            }
                            if chapter.isExcluded == true {
                                Text("not narrated")
                                    .font(.caption2)
                                    .foregroundStyle(AppPalette.mist.opacity(0.5))
                            }
                            Spacer()
                            if let duration = chapter.duration {
                                Text(formatDuration(duration))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(AppPalette.mist.opacity(0.6))
                            }
                        }
                        .font(.system(size: 13))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 560)
        .background(AppPalette.ink)
        .foregroundStyle(AppPalette.paper)
    }

    private var detailsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            detailRow("Output", book.outputMode == .podcast ? "Podcast episodes + M4B" : "Audiobook (M4B)")
            detailRow("Style", (book.narrationStyle ?? .faithful).title)
            if let record = book.generationRecord {
                detailRow("Narrated by", "\(record.provider) · \(record.voice)")
                detailRow("Generated", record.generatedAt.formatted(date: .abbreviated, time: .shortened))
                if let bytes = record.audioBytes {
                    detailRow("Audio size", formatBytes(bytes))
                }
            } else if let voice = book.voice {
                detailRow("Voice", voice)
            }
            detailRow("Source file", book.sourceURL.lastPathComponent)
            detailRow("Read-along", book.hasReadAlongHint)
        }
        .font(.system(size: 13))
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(AppPalette.mist.opacity(0.6))
            Text(value)
        }
    }
}

extension Audiobook {
    // Details can't read timings from disk directly; infer from the record —
    // any book generated after read-along shipped carries a record.
    var hasReadAlongHint: String {
        generationRecord == nil && generatedURL != nil
            ? "Not available — regenerate to enable"
            : (generatedURL == nil ? "After generation" : "Available")
    }
}
