import SwiftUI

struct LibrarySidebar: View {
    let books: [Audiobook]
    let selectedBookID: UUID?
    let queuedIDs: Set<UUID>
    let onSelect: (UUID) -> Void
    let onImport: () -> Void
    let actions: BookActions

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.book.closed.fill")
                    .foregroundStyle(AppPalette.accent)
                Text("Audio Shelf")
                    .font(.system(size: 15, weight: .bold))
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(books) { book in
                        SidebarBookRow(
                            book: book,
                            isSelected: selectedBookID == book.id,
                            isQueued: queuedIDs.contains(book.id),
                            onSelect: { onSelect(book.id) },
                            actions: actions
                        )
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Local-only narration")
                .font(.caption2)
                .foregroundStyle(AppPalette.mist.opacity(0.60))
        }
        .padding(18)
        .foregroundStyle(AppPalette.frost)
        .background(AppPalette.sea)
    }
}

// Sidebar row on native proportions: 13pt text, quiet hover, subtle selection;
// the ⋯ stays visible (discoverability beat progressive disclosure here) but
// brightens on hover.
struct SidebarBookRow: View {
    let book: Audiobook
    let isSelected: Bool
    var isQueued: Bool = false
    let onSelect: () -> Void
    let actions: BookActions
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Gap.s1) {
                BookCover(book: book, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(isQueued ? "Queued" : book.status.title)
                        .font(.system(size: 11))
                        .foregroundStyle(isQueued ? AppPalette.river : AppPalette.mist.opacity(0.66))
                }
                Spacer(minLength: 0)
                BookActionsMenu(book: book, actions: actions, isQueued: isQueued)
                    .opacity(isHovering || isSelected ? 1 : 0.45)
            }
            .padding(.horizontal, Gap.s1)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? AppPalette.river.opacity(0.22)
                    : (isHovering ? AppPalette.frost.opacity(0.06) : .clear),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

struct LibraryView: View {
    let books: [Audiobook]
    let selectedBookID: UUID?
    let isImporting: Bool
    let queuedIDs: Set<UUID>
    let onImport: () -> Void
    let onImportFile: (URL) -> Void
    let actions: BookActions

    @State private var environmentChecks: [EnvironmentCheck] = []
    @State private var isDropTargeted = false

    private static let importableExtensions: Set<String> = ["txt", "epub", "pdf"]

    private var selectedBook: Audiobook? {
        selectedBookID.flatMap { book($0, from: books) } ?? books.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gap.s4) {
                ForEach(environmentChecks.filter { !$0.isReady }) { check in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(check.title): \(check.detail)")
                            .font(.system(size: 13, design: .rounded))
                        Spacer()
                    }
                    .padding(12)
                    .foregroundStyle(AppPalette.frost)
                    .background(AppPalette.rose.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppPalette.rose.opacity(0.55), lineWidth: 0.5)
                    }
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The listening desk")
                            .font(.system(size: 26, weight: .bold, design: .serif))
                        Text("Import a book, shape the narration once, then keep listening locally.")
                            .font(.system(size: 13))
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
                    ListeningRail(book: selectedBook, actions: actions)
                } else {
                    EmptyLibraryView(onImport: onImport)
                }

                // D11: the queue as a feature — what narrates next.
                let queuedBooks = queuedIDs.compactMap { id in books.first(where: { $0.id == id }) }
                if !queuedBooks.isEmpty {
                    VStack(alignment: .leading, spacing: Gap.s1) {
                        Text("NEXT UP")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(AppPalette.river)
                        ForEach(queuedBooks) { queuedBook in
                            HStack(spacing: Gap.s1) {
                                BookCover(book: queuedBook, compact: true)
                                Text(queuedBook.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Text("starts when the current book finishes")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.mist.opacity(0.55))
                                Spacer()
                                Button("Remove") { actions.onDequeue(queuedBook.id) }
                                    .buttonStyle(QuietButtonStyle())
                            }
                            .padding(.horizontal, Gap.s2)
                            .padding(.vertical, 6)
                            .background(AppPalette.ink1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                if !books.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("All books")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("\(books.count) total")
                                .font(.caption)
                                .foregroundStyle(AppPalette.mist.opacity(0.7))
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                            ForEach(books) { book in
                                BookCard(book: book, actions: actions)
                            }
                        }
                    }
                }
            }
            .padding(Gap.s4)
        }
        .background(AppPalette.ink)
        .foregroundStyle(AppPalette.frost)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppPalette.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(10)
                    .background(AppPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    let actions: BookActions

    var body: some View {
        AppSurface {
            HStack(spacing: 28) {
                BookCover(book: book, compact: false)
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text(book.status == .readyToListen ? "READY ON YOUR SHELF" : "CURRENTLY IN THE WORKROOM")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(AppPalette.accent)
                        Spacer()
                        BookActionsMenu(book: book, actions: actions)
                    }
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
                    if book.status == .failed || book.status == .paused, let failureMessage = book.failureMessage {
                        Text(failureMessage)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.48))
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        switch book.status {
                        case .readyToListen:
                            Button("Listen now") { actions.onPlay(book.id) }
                                .buttonStyle(PrimaryButtonStyle())
                        case .generating:
                            Button {
                                actions.onProgress(book.id)
                            } label: {
                                Label("View progress", systemImage: "waveform")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        case .readyForReview:
                            Button("Review book") { actions.onReview(book.id) }
                                .buttonStyle(PrimaryButtonStyle())
                        case .paused, .failed:
                            Button {
                                actions.onResume(book.id)
                            } label: {
                                Label("Resume narration", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            Button("Review book") { actions.onReview(book.id) }
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
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 86, height: 110)
                    .background(AppPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    let actions: BookActions
    @State private var isHovering = false

    private var cardActionIcon: String {
        switch book.status {
        case .readyToListen: "play.fill"
        case .generating: "waveform"
        case .paused, .failed: "arrow.clockwise"
        case .readyForReview: "arrow.right"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.s1) {
            HStack(alignment: .top) {
                BookCover(book: book, compact: false)
                Spacer()
                BookActionsMenu(book: book, actions: actions)
                    .opacity(isHovering ? 1 : 0.5)
            }
            Text(book.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
            Text(book.author)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.mist.opacity(0.68))
                .lineLimit(1)
            HStack {
                StatusPill(status: book.status)
                Spacer()
                Button {
                    switch book.status {
                    case .readyToListen: actions.onPlay(book.id)
                    case .generating: actions.onProgress(book.id)
                    case .readyForReview: actions.onReview(book.id)
                    case .paused, .failed: actions.onResume(book.id)
                    }
                } label: {
                    Image(systemName: cardActionIcon)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(AppPalette.frost.opacity(0.10), in: Circle())
            }
        }
        .padding(Gap.s2)
        .background(
            isHovering ? AppPalette.ink2 : AppPalette.ink1,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(isHovering ? 0.28 : 0.14), radius: isHovering ? 6 : 2, y: isHovering ? 3 : 1)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

struct BookCover: View {
    let book: Audiobook
    let compact: Bool
    var width: CGFloat?
    var height: CGFloat?

    var body: some View {
        let width: CGFloat = width ?? (compact ? 34 : 112)
        let height: CGFloat = height ?? (compact ? 44 : 156)
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
            .foregroundStyle(AppPalette.frost)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 7 : 12, style: .continuous)
                .stroke(AppPalette.frost.opacity(0.26), lineWidth: 1)
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
    case .readyToListen: AppPalette.accent
    case .paused: AppPalette.mist
    case .failed: AppPalette.rose
    }
}

func coverColor(for title: String) -> Color {
    let values = [
        Color(red: 0.42, green: 0.32, blue: 0.85),
        Color(red: 0.28, green: 0.32, blue: 0.62),
        Color(red: 0.16, green: 0.45, blue: 0.47),
        Color(red: 0.62, green: 0.24, blue: 0.55)
    ]
    let index = abs(title.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % values.count
    return values[index]
}
