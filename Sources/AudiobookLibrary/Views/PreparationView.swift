import SwiftUI

struct PreparationView: View {
    let book: Audiobook
    let onBack: () -> Void
    let onGenerate: (Audiobook) -> Void

    @State private var draftTitle: String
    @State private var draftAuthor: String
    @State private var draftChapters: [Chapter]
    @State private var selectedChapterID: UUID?
    @State private var outputMode: OutputMode

    init(book: Audiobook, onBack: @escaping () -> Void, onGenerate: @escaping (Audiobook) -> Void) {
        self.book = book
        self.onBack = onBack
        self.onGenerate = onGenerate
        _draftTitle = State(initialValue: book.title)
        _draftAuthor = State(initialValue: book.author)
        _draftChapters = State(initialValue: book.chapters)
        _selectedChapterID = State(initialValue: book.chapters.first?.id)
        _outputMode = State(initialValue: book.outputMode ?? .audiobook)
    }

    private var selectedChapterIndex: Int? {
        draftChapters.firstIndex(where: { $0.id == selectedChapterID })
    }

    var body: some View {
        VStack(spacing: 0) {
            PreparationHeader(onBack: onBack, onGenerate: generate)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("PREPARATION REVIEW")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(AppPalette.copper)
                    Text("Make this book ready to speak")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Text("The MVP asks you to review the title, chapters, and narration text once. Later workflows will reduce this to exceptions only.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AppPalette.mist.opacity(0.75))

                    ReviewField(label: "Book title", value: $draftTitle)
                    ReviewField(label: "Author", value: $draftAuthor)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("OUTPUT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(AppPalette.mist.opacity(0.60))
                        Picker("Output", selection: $outputMode) {
                            ForEach(OutputMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Text("CHAPTERS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(AppPalette.mist.opacity(0.60))
                        .padding(.top, 5)
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach($draftChapters) { $chapter in
                                Button {
                                    selectedChapterID = chapter.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Toggle("Narrate", isOn: Binding(
                                            get: { chapter.isExcluded != true },
                                            set: { chapter.isExcluded = $0 ? nil : true }
                                        ))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                        .help(chapter.isExcluded == true ? "Excluded from narration" : "Will be narrated")
                                        Text("\(chapter.index)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(AppPalette.copper)
                                            .frame(width: 20)
                                        Text(chapter.title)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        if let category = chapter.sectionCategory, category != narratedSectionCategory {
                                            Text(category.replacingOccurrences(of: "_", with: " "))
                                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .foregroundStyle(AppPalette.mist)
                                                .background(AppPalette.mist.opacity(0.12), in: Capsule())
                                        }
                                    }
                                    .opacity(chapter.isExcluded == true ? 0.45 : 1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(
                                        selectedChapterID == chapter.id ? AppPalette.river.opacity(0.20) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(width: 310)
                .padding(26)
                .background(AppPalette.sea)

                Divider().overlay(AppPalette.mist.opacity(0.16))

                if let selectedChapterIndex {
                    ChapterEditor(chapter: $draftChapters[selectedChapterIndex])
                        .padding(30)
                } else {
                    ContentUnavailableView("No chapter selected", systemImage: "text.book.closed")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(AppPalette.ink)
        .foregroundStyle(AppPalette.paper)
    }

    private func generate() {
        var reviewedBook = book
        reviewedBook.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewedBook.author = draftAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewedBook.chapters = draftChapters.enumerated().map { index, chapter in
            var revisedChapter = chapter
            revisedChapter.index = index + 1
            return revisedChapter
        }
        reviewedBook.outputMode = outputMode
        onGenerate(reviewedBook)
    }
}

struct PreparationHeader: View {
    let onBack: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label("Library", systemImage: "chevron.left")
            }
            .buttonStyle(QuietButtonStyle())
            Spacer()
            Button(action: onGenerate) {
                Label("Generate locally", systemImage: "waveform.badge.magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
        .background(AppPalette.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppPalette.mist.opacity(0.14)).frame(height: 1)
        }
    }
}

struct ReviewField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(AppPalette.mist.opacity(0.60))
            TextField(label, text: $value)
                .textFieldStyle(.plain)
                .padding(10)
                .foregroundStyle(AppPalette.paper)
                .background(AppPalette.paper.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppPalette.mist.opacity(0.20), lineWidth: 1) }
        }
    }
}

struct ChapterEditor: View {
    @Binding var chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CHAPTER \(chapter.index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(AppPalette.copper)
            TextField("Chapter title", text: $chapter.title)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .padding(.bottom, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.mist.opacity(0.22)).frame(height: 1) }
            HStack {
                Text("Narration text")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(chapter.text.count) characters")
                    .font(.caption)
                    .foregroundStyle(AppPalette.mist.opacity(0.66))
            }
            TextEditor(text: $chapter.text)
                .font(.system(size: 15, design: .serif))
                .scrollContentBackground(.hidden)
                .padding(12)
                .foregroundStyle(AppPalette.paper)
                .background(AppPalette.paper.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(AppPalette.mist.opacity(0.16), lineWidth: 1) }
        }
    }
}
