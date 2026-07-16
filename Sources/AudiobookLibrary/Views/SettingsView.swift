import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.kokoroPython) private var kokoroPythonPath = ""
    @AppStorage(SettingsKey.ffmpeg) private var ffmpegPath = ""
    @AppStorage(SettingsKey.voice) private var narrationVoice = defaultNarrationVoice
    @AppStorage(SettingsKey.llmClassify) private var classifyOnImport = true
    @AppStorage(SettingsKey.llmEndpoint) private var llmEndpointPath = ""
    @AppStorage(SettingsKey.autoFocusOnPlay) private var autoFocus = false
    @State private var checks: [EnvironmentCheck] = []
    @State private var rules: [TextRule] = []
    @State private var llmStatus: LLMStatus?
    @State private var skipRefresh = 0

    private func skipBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: {
                _ = skipRefresh
                return playbackSkipCategories().contains(category)
            },
            set: { isOn in
                var categories = playbackSkipCategories()
                if isOn { categories.insert(category) } else { categories.remove(category) }
                savePlaybackSkipCategories(categories)
                skipRefresh += 1
            }
        )
    }

    private var llmStatusDetail: String {
        guard let llmStatus else { return "Not checked yet" }
        if llmStatus.isReachable {
            return llmStatus.modelName.map { "Reachable · \($0)" } ?? "Reachable"
        }
        return "Not running — start LM Studio's server (lms server start) or Ollama"
    }

    var body: some View {
        Form {
            Section("Narration") {
                LabeledContent("Provider", value: "Kokoro (local)")
                Picker("Voice", selection: $narrationVoice) {
                    ForEach(availableNarrationVoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                Text("The voice applies to books generated from now on. Existing audio is unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Environment") {
                TextField("Kokoro Python path", text: $kokoroPythonPath, prompt: Text("Auto-detect"))
                TextField("ffmpeg path", text: $ffmpegPath, prompt: Text("Auto-detect"))
                Text("Leave a field empty to auto-detect. Paths support ~ for your home folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                ForEach(checks) { check in
                    LabeledContent {
                        Text(check.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    } label: {
                        Label(check.title, systemImage: check.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(check.isReady ? Color.green : Color.orange)
                    }
                }
                Button("Check again") { refreshChecks() }
            }

            Section("Listening") {
                Toggle("Start books in focus mode", isOn: $autoFocus)
                Text("Focus mode fills the window with the narrated sentence — one point of attention, nothing else.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Skip notes while listening", isOn: skipBinding("notes"))
                Toggle("Skip back matter while listening", isOn: skipBinding("back_matter"))
                Text("Applies to sections you chose to narrate anyway — playback jumps past them to the next chapter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Presets") {
                LabeledContent {
                    Button("Apply") {
                        autoFocus = true
                        savePreferredPlaybackRate(0.9)
                        savePlaybackSkipCategories(["notes", "back_matter"])
                        skipRefresh += 1
                    }
                } label: {
                    Text("Calm focus")
                    Text("For ADHD or easily-divided attention: focus mode on play, slightly slower voice, notes and back matter skipped.")
                }
                LabeledContent {
                    Button("Apply") {
                        autoFocus = false
                        savePreferredPlaybackRate(1.5)
                        savePlaybackSkipCategories([])
                        skipRefresh += 1
                    }
                } label: {
                    Text("Quick listener")
                    Text("Faster voice, nothing skipped, standard player.")
                }
                Text("Presets set the toggles above and the default speed. New books start with these; change anything per book while listening.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text intelligence") {
                Toggle("Classify sections on import", isOn: $classifyOnImport)
                Text("Uses a local model server (LM Studio, Ollama, …) to spot licenses, contents pages, and notes, and exclude them from narration. Books never leave this Mac. Review always shows what was excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Server endpoint", text: $llmEndpointPath, prompt: Text(defaultLLMEndpoint))
                LabeledContent {
                    Text(llmStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } label: {
                    Label(
                        "Local model server",
                        systemImage: llmStatus?.isReachable == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(llmStatus?.isReachable == true ? Color.green : Color.orange)
                }
                Button("Check server") {
                    Task { llmStatus = await checkLLMStatus() }
                }
            }

            Section("Narration workflows") {
                if rules.isEmpty {
                    Text("Rules rewrite or remove words before narration — e.g. silence a trigger word, or expand an abbreviation the voice mispronounces. Matching is whole-word and case-insensitive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach($rules) { $rule in
                    HStack(spacing: 8) {
                        TextField("Word or phrase", text: $rule.pattern)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Replacement (empty = remove)", text: $rule.replacement)
                        Button {
                            rules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                Button {
                    rules.append(TextRule(pattern: "", replacement: ""))
                } label: {
                    Label("Add rule", systemImage: "plus")
                }
                if !rules.isEmpty {
                    Text("Rules apply to books generated from now on. Resuming a book re-narrates only the chapters a rule changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Output") {
                LabeledContent("Format", value: "M4B · AAC 64 kbps · chapter markers")
                LabeledContent("Library folder", value: "~/Library/Application Support/AudiobookLibrary")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            refreshChecks()
            rules = loadTextRules()
            Task { llmStatus = await checkLLMStatus() }
        }
        .onChange(of: kokoroPythonPath) { refreshChecks() }
        .onChange(of: ffmpegPath) { refreshChecks() }
        .onChange(of: rules) { saveTextRules(rules) }
    }

    private func refreshChecks() {
        checks = runEnvironmentPreflight(fileManager: .default)
    }
}
