import SwiftUI

struct LibrarySidebar: View {
    let books: [Audiobook]
    let selectedBookID: UUID?
    let onSelect: (UUID) -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.book.closed.fill")
                    .foregroundStyle(AppPalette.copper)
                Text("Audio Shelf")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .padding(.top, 12)

            Button(action: onImport) {
                Label("Import a book", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Text("YOUR LIBRARY")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(AppPalette.mist.opacity(0.72))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(books) { book in
                        Button {
                            onSelect(book.id)
                        } label: {
                            HStack(spacing: 10) {
                                BookCover(book: book, compact: true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(book.title)
                                        .lineLimit(1)
                                    Text(book.status.title)
                                        .font(.caption2)
                                        .foregroundStyle(AppPalette.mist.opacity(0.68))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(
                                selectedBookID == book.id ? AppPalette.river.opacity(0.20) : .clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Local-only narration")
                .font(.caption2)
                .foregroundStyle(AppPalette.mist.opacity(0.60))
        }
        .padding(18)
        .foregroundStyle(AppPalette.paper)
        .background(AppPalette.sea)
    }
}

struct LibraryView: View {
    let books: [Audiobook]
    let selectedBookID: UUID?
    let isImporting: Bool
    let onImport: () -> Void
    let onImportFile: (URL) -> Void
    let onReview: (UUID) -> Void
    let onPlay: (UUID) -> Void
    let onProgress: (UUID) -> Void
    let onResume: (UUID) -> Void

    @State private var environmentChecks: [EnvironmentCheck] = []
    @State private var isDropTargeted = false

    private static let importableExtensions: Set<String> = ["txt", "epub", "pdf"]

    private var selectedBook: Audiobook? {
        selectedBookID.flatMap { book($0, from: books) } ?? books.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(environmentChecks.filter { !$0.isReady }) { check in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(check.title): \(check.detail)")
                            .font(.system(size: 13, design: .rounded))
                        Spacer()
                    }
                    .padding(12)
                    .foregroundStyle(AppPalette.ink)
                    .background(Color(red: 0.96, green: 0.76, blue: 0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The listening desk")
                            .font(.system(size: 36, weight: .bold, design: .serif))
                        Text("Import a book, shape the narration once, then keep listening locally.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(AppPalette.mist.opacity(0.76))
                    }
                    Spacer()
                    Button(action: onImport) {
                        Label(isImporting ? "Reading book" : "Import", systemImage: isImporting ? "book.pages" : "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isImporting)
                }

                if let selectedBook {
                    ListeningRail(book: selectedBook, onReview: onReview, onPlay: onPlay, onProgress: onProgress, onResume: onResume)
                } else {
                    EmptyLibraryView(onImport: onImport)
                }

                if !books.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("All books")
                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("\(books.count) total")
                                .font(.caption)
                                .foregroundStyle(AppPalette.mist.opacity(0.7))
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                            ForEach(books) { book in
                                BookCard(book: book, onReview: onReview, onPlay: onPlay, onProgress: onProgress)
                            }
                        }
                    }
                }
            }
            .padding(34)
        }
        .background(AppPalette.ink)
        .foregroundStyle(AppPalette.paper)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppPalette.copper, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(10)
                    .background(AppPalette.copper.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        Label("Drop books to import", systemImage: "square.and.arrow.down")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .padding(18)
                            .background(AppPalette.ink.opacity(0.9), in: Capsule())
                    }
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let importable = urls.filter { Self.importableExtensions.contains($0.pathExtension.lowercased()) }
            importable.forEach(onImportFile)
            return !importable.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .onAppear {
            environmentChecks = runEnvironmentPreflight(fileManager: .default)
        }
    }
}

struct ListeningRail: View {
    let book: Audiobook
    let onReview: (UUID) -> Void
    let onPlay: (UUID) -> Void
    let onProgress: (UUID) -> Void
    let onResume: (UUID) -> Void

    var body: some View {
        AppSurface {
            HStack(spacing: 28) {
                BookCover(book: book, compact: false)
                VStack(alignment: .leading, spacing: 13) {
                    Text(book.status == .readyToListen ? "READY ON YOUR SHELF" : "CURRENTLY IN THE WORKROOM")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(AppPalette.copper)
                    Text(book.title)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .lineLimit(2)
                    Text(book.author)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(AppPalette.mist.opacity(0.74))
                    HStack(spacing: 10) {
                        StatusPill(status: book.status)
                        Text("\(book.chapters.count) chapters")
                            .font(.caption)
                            .foregroundStyle(AppPalette.mist.opacity(0.68))
                    }
                    Spacer(minLength: 3)
                    if book.status == .failed, let failureMessage = book.failureMessage {
                        Text(failureMessage)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.48))
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        switch book.status {
                        case .readyToListen:
                            Button("Listen now") { onPlay(book.id) }
                                .buttonStyle(PrimaryButtonStyle())
                        case .generating:
                            Button {
                                onProgress(book.id)
                            } label: {
                                Label("View progress", systemImage: "waveform")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        case .readyForReview:
                            Button("Review book") { onReview(book.id) }
                                .buttonStyle(PrimaryButtonStyle())
                        case .failed:
                            Button {
                                onResume(book.id)
                            } label: {
                                Label("Resume narration", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            Button("Review book") { onReview(book.id) }
                                .buttonStyle(QuietButtonStyle())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(26)
        }
    }
}

struct EmptyLibraryView: View {
    let onImport: () -> Void

    var body: some View {
        AppSurface {
            HStack(spacing: 26) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(AppPalette.copper)
                    .frame(width: 86, height: 110)
                    .background(AppPalette.copper.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 9) {
                    Text("Your shelf is empty")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Text("Bring in a text-native EPUB, TXT, or PDF. You will review the chapters before Kokoro starts narrating.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(AppPalette.mist.opacity(0.74))
                    Button("Choose a book", action: onImport)
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 5)
                }
                Spacer()
            }
            .padding(28)
        }
    }
}

struct BookCard: View {
    let book: Audiobook
    let onReview: (UUID) -> Void
    let onPlay: (UUID) -> Void
    let onProgress: (UUID) -> Void

    private var cardActionIcon: String {
        switch book.status {
        case .readyToListen: "play.fill"
        case .generating: "waveform"
        case .readyForReview, .failed: "arrow.right"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            BookCover(book: book, compact: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(book.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Text(book.author)
                .font(.caption)
                .foregroundStyle(AppPalette.mist.opacity(0.68))
                .lineLimit(1)
            HStack {
                StatusPill(status: book.status)
                Spacer()
                Button {
                    switch book.status {
                    case .readyToListen: onPlay(book.id)
                    case .generating: onProgress(book.id)
                    case .readyForReview, .failed: onReview(book.id)
                    }
                } label: {
                    Image(systemName: cardActionIcon)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(AppPalette.paper.opacity(0.10), in: Circle())
            }
        }
        .padding(14)
        .background(AppPalette.paper.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppPalette.mist.opacity(0.16), lineWidth: 1)
        }
    }
}

struct BookCover: View {
    let book: Audiobook
    let compact: Bool

    var body: some View {
        let width: CGFloat = compact ? 34 : 112
        let height: CGFloat = compact ? 44 : 156
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [coverColor(for: book.title), AppPalette.sea],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: compact ? 11 : 18, weight: .medium))
                if !compact {
                    Text(book.title)
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .lineLimit(3)
                }
            }
            .padding(compact ? 6 : 12)
            .foregroundStyle(AppPalette.paper)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 7 : 12, style: .continuous)
                .stroke(AppPalette.paper.opacity(0.26), lineWidth: 1)
        }
    }
}

struct StatusPill: View {
    let status: BookStatus

    var body: some View {
        Text(status.title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(statusColor(status))
            .background(statusColor(status).opacity(0.14), in: Capsule())
            .overlay { Capsule().stroke(statusColor(status).opacity(0.45), lineWidth: 1) }
    }
}

func statusColor(_ status: BookStatus) -> Color {
    switch status {
    case .readyForReview: AppPalette.mist
    case .generating: AppPalette.river
    case .readyToListen: AppPalette.copper
    case .failed: Color(red: 0.95, green: 0.45, blue: 0.40)
    }
}

func coverColor(for title: String) -> Color {
    let values = [
        Color(red: 0.22, green: 0.47, blue: 0.49),
        Color(red: 0.48, green: 0.25, blue: 0.42),
        Color(red: 0.38, green: 0.40, blue: 0.17),
        Color(red: 0.31, green: 0.31, blue: 0.50)
    ]
    let index = abs(title.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % values.count
    return values[index]
}
