import SwiftUI

struct RootView: View {
    @State private var store = AppStore()

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
                onExit: { store.isFocusMode = false }
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
                selectedBookID: store.state.selectedBookID,
                onSelect: { bookID in
                    store.dispatch(.selectBook(bookID))
                    if store.activeGenerationBookID == bookID {
                        store.dispatch(.navigate(.generation(bookID)))
                    } else {
                        store.dispatch(.navigate(.library))
                    }
                },
                onImport: store.chooseAndImport
            )
            .navigationSplitViewColumnWidth(min: 226, ideal: 252, max: 286)
        } detail: {
            routeView(store: store)
        }
        .tint(AppPalette.copper)
        .task { store.load() }
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

    @ViewBuilder
    private func routeView(store: AppStore) -> some View {
        switch store.state.route {
        case .library:
            LibraryView(
                books: store.state.books,
                selectedBookID: store.state.selectedBookID,
                isImporting: store.state.isImporting,
                onImport: store.chooseAndImport,
                onImportFile: { store.importBook(sourceURL: $0) },
                onReview: { store.dispatch(.navigate(.preparation($0))) },
                onPlay: store.openPlayer,
                onProgress: store.openGenerationProgress,
                onResume: store.resumeGeneration
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
                    progress: store.state.generationProgress,
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
                    onFocus: { store.isFocusMode = true }
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

struct AppPalette {
    static let ink = Color(red: 0.06, green: 0.12, blue: 0.13)
    static let sea = Color(red: 0.10, green: 0.26, blue: 0.27)
    static let mist = Color(red: 0.76, green: 0.84, blue: 0.81)
    static let paper = Color(red: 0.95, green: 0.94, blue: 0.88)
    static let copper = Color(red: 0.91, green: 0.31, blue: 0.17)
    static let river = Color(red: 0.23, green: 0.59, blue: 0.60)
}

struct AppSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(AppPalette.paper.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppPalette.mist.opacity(0.18), lineWidth: 1)
            }
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
        .foregroundStyle(AppPalette.paper)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(AppPalette.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? AppPalette.copper.opacity(0.72) : AppPalette.copper, in: Capsule())
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(AppPalette.paper)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(configuration.isPressed ? AppPalette.paper.opacity(0.18) : AppPalette.paper.opacity(0.10), in: Capsule())
            .overlay {
                Capsule().stroke(AppPalette.mist.opacity(0.24), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
