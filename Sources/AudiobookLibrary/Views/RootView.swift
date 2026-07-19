import SwiftUI

struct RootView: View {
    @Bindable var store: AppStore
    @State private var detailsBookID: UUID?

    private var actions: BookActions {
        BookActions(
            onPlay: store.openPlayer,
            onReview: { store.dispatch(.navigate(.preparation($0))) },
            onProgress: store.openGenerationProgress,
            onResume: store.resumeGeneration,
            onRegenerate: { store.beginGeneration(bookID: $0) },
            onDetails: { detailsBookID = $0 },
            onExport: store.exportAudiobook,
            onRevealFiles: store.revealBookFiles,
            onRemove: store.requestRemoval,
            onStop: { store.stopGeneration() },
            onDequeue: store.removeFromQueue
        )
    }

    var body: some View {
        @Bindable var store = store
        if store.isFocusMode, case let .player(bookID) = store.state.route, let focusBook = book(bookID, from: store.state.books) {
            FocusModeView(
                book: focusBook,
                timings: store.currentTimings,
                currentSeconds: store.currentPlaybackSeconds,
                isPlaying: store.isPlaying,
                onToggle: store.togglePlayback,
                onSeek: store.seek,
                onExit: { store.isFocusMode = false },
                onRegenerate: {
                    store.isFocusMode = false
                    store.beginGeneration(bookID: bookID)
                }
            )
        } else {
            mainWindow(store: store)
        }
    }

    @ViewBuilder
    private func mainWindow(store: AppStore) -> some View {
        @Bindable var store = store
        NavigationSplitView {
            LibrarySidebar(
                books: store.state.books,
                selection: sidebarSelection(for: store.state.route),
                queuedIDs: Set(store.state.queue),
                onSelect: { item in
                    switch item {
                    case .home:
                        store.dispatch(.navigate(.library))
                    case .models:
                        store.dispatch(.navigate(.models))
                    case let .book(bookID):
                        store.dispatch(.selectBook(bookID))
                        // A book click opens the book itself; Home is the way back.
                        guard let selected = book(bookID, from: store.state.books) else { return }
                        if store.activeGenerationBookID == bookID {
                            store.dispatch(.navigate(.generation(bookID)))
                        } else if selected.status == .readyToListen {
                            store.openPlayer(bookID: bookID)
                        } else {
                            store.dispatch(.navigate(.preparation(bookID)))
                        }
                    }
                },
                onImport: store.chooseAndImport,
                actions: actions
            )
            .navigationSplitViewColumnWidth(min: 226, ideal: 252, max: 286)
        } detail: {
            routeView(store: store)
        }
        .tint(AppPalette.accent)
        .task { store.load() }
        .confirmationDialog(
            "Remove \(store.state.books.first(where: { $0.id == store.removalCandidateID })?.title ?? "this book")?",
            isPresented: Binding(
                get: { store.removalCandidateID != nil },
                set: { isPresented in if !isPresented { store.removalCandidateID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove book and its audio", role: .destructive) { store.confirmRemoval() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the generated audio, podcast episodes, and the imported copy from Audio Shelf. Your original file is not touched.")
        }
        .confirmationDialog(
            "\(store.duplicateImportCandidate?.lastPathComponent ?? "This book") is already on your shelf.",
            isPresented: Binding(
                get: { store.duplicateImportCandidate != nil },
                set: { isPresented in if !isPresented { store.duplicateImportCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Import again as a new book") { store.confirmDuplicateImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Importing again makes a separate copy — useful for trying a different voice or style. The existing book is untouched.")
        }
        .sheet(
            isPresented: Binding(
                get: { detailsBookID != nil },
                set: { isPresented in if !isPresented { detailsBookID = nil } }
            )
        ) {
            if let bookID = detailsBookID, let detailsBook = book(bookID, from: store.state.books) {
                BookDetailsView(book: detailsBook, onClose: { detailsBookID = nil })
            }
        }
        .alert(
            "Audio Shelf",
            isPresented: Binding(
                get: { store.state.alertMessage != nil },
                set: { isPresented in
                    if !isPresented { store.dispatch(.dismissAlert) }
                }
            )
        ) {
            Button("Close") { store.dispatch(.dismissAlert) }
        } message: {
            Text(store.state.alertMessage ?? "")
        }
    }

    private func sidebarSelection(for route: AppRoute) -> SidebarItem? {
        switch route {
        case .library: .home
        case .models: .models
        case let .preparation(bookID), let .generation(bookID), let .player(bookID): .book(bookID)
        }
    }

    @ViewBuilder
    private func routeView(store: AppStore) -> some View {
        switch store.state.route {
        case .models:
            ModelsView()
        case .library:
            LibraryView(
                books: store.state.books,
                selectedBookID: store.state.selectedBookID,
                isImporting: store.state.isImporting,
                queuedIDs: Set(store.state.queue),
                onImport: store.chooseAndImport,
                onImportFile: { store.importBook(sourceURL: $0) },
                actions: actions
            )
        case let .preparation(bookID):
            if let book = book(bookID, from: store.state.books) {
                PreparationView(
                    book: book,
                    onBack: { store.dispatch(.navigate(.library)) },
                    onGenerate: { reviewedBook in
                        store.saveReviewedBook(reviewedBook)
                        store.beginGeneration(bookID: reviewedBook.id)
                    }
                )
            } else {
                MissingBookView(onReturn: { store.dispatch(.navigate(.library)) })
            }
        case let .generation(bookID):
            if let book = book(bookID, from: store.state.books) {
                GenerationView(
                    book: book,
                    job: store.state.activeJob?.bookID == bookID ? store.state.activeJob : nil,
                    isStopping: store.isStoppingJob,
                    onStop: { store.stopGeneration() },
                    onReturnToLibrary: { store.dispatch(.navigate(.library)) }
                )
            } else {
                MissingBookView(onReturn: { store.dispatch(.navigate(.library)) })
            }
        case let .player(bookID):
            if let book = book(bookID, from: store.state.books) {
                PlayerView(
                    book: book,
                    timings: store.currentTimings,
                    currentSeconds: store.currentPlaybackSeconds,
                    isPlaying: store.isPlaying,
                    playbackRate: store.playbackRate,
                    onBack: { store.dispatch(.navigate(.library)) },
                    onToggle: store.togglePlayback,
                    onSetRate: { store.setPlaybackRate($0) },
                    onSeek: store.seek,
                    onFocus: { store.isFocusMode = true },
                    onRegenerate: { store.beginGeneration(bookID: bookID) }
                )
            } else {
                MissingBookView(onReturn: { store.dispatch(.navigate(.library)) })
            }
        }
    }
}

func book(_ id: UUID, from books: [Audiobook]) -> Audiobook? {
    books.first(where: { $0.id == id })
}

// Audio Shelf's palette on macOS background-level rules: hierarchy comes from
// stacked background levels (window → panel → card → hover), not borders.
// Dark surfaces get MORE separation between levels, hairlines stay at 0.5pt.
struct AppPalette {
    // Level 0 — the window.
    static let ink = Color(red: 0.05, green: 0.105, blue: 0.115)
    // Level 1 — panels, cards, grouped sections.
    static let ink1 = Color(red: 0.083, green: 0.16, blue: 0.17)
    // Level 2 — hover, active, inputs.
    static let ink2 = Color(red: 0.115, green: 0.215, blue: 0.225)
    static let sea = Color(red: 0.10, green: 0.26, blue: 0.27)
    static let mist = Color(red: 0.76, green: 0.84, blue: 0.81)
    // Text and light surfaces — frost: a cool, green-cast white. Never beige.
    static let frost = Color(red: 0.92, green: 0.95, blue: 0.94)
    // The identity accent — electric violet. Bold, and unclaimed in audio
    // (orange is Audible's, green is Spotify's). Never orange.
    static let accent = Color(red: 0.49, green: 0.36, blue: 1.0)
    static let river = Color(red: 0.18, green: 0.75, blue: 0.71)
    // Attention/error family — rose, never coral or amber.
    static let rose = Color(red: 0.95, green: 0.34, blue: 0.55)
    // 0.5pt definition line — the macOS hairline, never a visible frame.
    static let hairline = Color(red: 0.76, green: 0.84, blue: 0.81).opacity(0.14)
}

// 8pt base grid.
enum Gap {
    static let s1: CGFloat = 8
    static let s2: CGFloat = 12
    static let s3: CGFloat = 16
    static let s4: CGFloat = 24
}

struct AppSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(AppPalette.ink1, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppPalette.hairline, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}

struct MissingBookView: View {
    let onReturn: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 42, weight: .light))
            Text("This book is no longer in the library")
                .font(.title2.weight(.semibold))
            Button("Return to library", action: onReturn)
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.ink)
        .foregroundStyle(AppPalette.frost)
    }
}

// Native macOS control proportions: 13pt semibold, 6pt radius, ~28pt height,
// hover brightens, press dims — every interaction answers back.
struct PrimaryButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppPalette.frost)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                configuration.isPressed
                    ? AppPalette.accent.opacity(0.72)
                    : (isHovering ? AppPalette.accent.opacity(0.9) : AppPalette.accent),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppPalette.frost)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                configuration.isPressed
                    ? AppPalette.ink2.opacity(1)
                    : (isHovering ? AppPalette.ink2 : AppPalette.ink1),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppPalette.hairline, lineWidth: 0.5)
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
