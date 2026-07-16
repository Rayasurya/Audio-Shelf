import SwiftUI

struct GenerationView: View {
    let book: Audiobook
    let progress: GenerationProgress?
    let onReturnToLibrary: () -> Void

    private var currentProgress: GenerationProgress {
        progress ?? GenerationProgress(bookID: book.id, completedChapters: 0, totalChapters: book.narratedChapters.count, chapterTitle: "Starting Kokoro")
    }

    var body: some View {
        VStack(spacing: 26) {
            BookCover(book: book, compact: false)
            VStack(spacing: 8) {
                Text("Making your audiobook")
                    .font(.system(size: 33, weight: .bold, design: .serif))
                Text("Kokoro is working locally on this Mac.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(AppPalette.mist.opacity(0.74))
            }
            AppSurface {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text(currentProgress.chapterTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(currentProgress.completedChapters) / \(max(currentProgress.totalChapters, book.narratedChapters.count))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.copper)
                    }
                    ProgressView(value: currentProgress.fraction)
                        .tint(AppPalette.copper)
                    Text("Completed chapter audio is saved immediately, so an interrupted job will never be marked complete by mistake.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.mist.opacity(0.68))
                }
                .padding(18)
            }
            Button("Keep browsing", action: onReturnToLibrary)
                .buttonStyle(QuietButtonStyle())
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.ink)
        .foregroundStyle(AppPalette.paper)
    }
}
