import SwiftUI

// The Models destination: everything AI-shaped in one dense screen — the
// voice model, both text-model servers, and which model owns which role.
struct ModelsView: View {
    @AppStorage(SettingsKey.voice) private var narrationVoice = defaultNarrationVoice
    @AppStorage(SettingsKey.llmModel) private var mainModel = ""
    @AppStorage(SettingsKey.fastLLMModel) private var fastModel = ""
    @AppStorage(SettingsKey.llmEndpoint) private var mainEndpoint = ""
    @AppStorage(SettingsKey.fastLLMEndpoint) private var fastEndpoint = ""

    @State private var mainModels: [String]?
    @State private var fastModels: [String]?
    @State private var kokoroReady = false
    @State private var kokoroDetail = "Checking…"

    var body: some View {
        Form {
            Section("Voice — narration") {
                LabeledContent {
                    Text(kokoroDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } label: {
                    Label("Kokoro-82M", systemImage: kokoroReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(kokoroReady ? Color.green : AppPalette.rose)
                }
                Picker("Default voice", selection: $narrationVoice) {
                    ForEach(availableNarrationVoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                Text("Each book can override the voice in review. Changing a book's voice and regenerating re-narrates it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Understanding — classification & retelling") {
                serverRow(title: "Server", endpoint: currentMainEndpoint, models: mainModels)
                if let models = mainModels, !models.isEmpty {
                    Picker("Model", selection: $mainModel) {
                        Text("Automatic (first available)").tag("")
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                Text("Classifies sections on import and writes easier retellings. The bigger the model, the better the judgment — gemma-4-12b is a good fit on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cleaning — sentence-level passes") {
                serverRow(title: "Server", endpoint: currentFastEndpoint, models: fastModels)
                if let models = fastModels, !models.isEmpty {
                    Picker("Model", selection: $fastModel) {
                        Text("Automatic (\(defaultFastLLMModel))").tag("")
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                Text("Sweeps whole books applying your content preferences — small and fast wins here. Llama 3.2 3B (2 GB) was installed for exactly this. Falls back to the understanding server when this one is off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Refresh servers") { refresh() }
                Text("Endpoints are configurable in Settings (⌘,). Any OpenAI-compatible local server works: LM Studio, Ollama, llama.cpp.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppPalette.ink)
        .onAppear { refresh() }
    }

    private var currentMainEndpoint: String { mainEndpoint.isEmpty ? defaultLLMEndpoint : mainEndpoint }
    private var currentFastEndpoint: String { fastEndpoint.isEmpty ? defaultFastLLMEndpoint : fastEndpoint }

    @ViewBuilder
    private func serverRow(title: String, endpoint: String, models: [String]?) -> some View {
        LabeledContent {
            Text(models == nil ? "Not answering" : "\(models?.count ?? 0) models")
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            Label(endpoint.replacingOccurrences(of: "http://", with: ""), systemImage: models == nil ? "bolt.slash" : "bolt.fill")
                .foregroundStyle(models == nil ? AppPalette.rose : Color.green)
        }
    }

    private func refresh() {
        Task {
            mainModels = await fetchAvailableModels(endpoint: currentMainEndpoint)
            fastModels = await fetchAvailableModels(endpoint: currentFastEndpoint)
            let ready = (try? kokoroPythonURL(fileManager: .default)) != nil
            kokoroReady = ready
            kokoroDetail = ready
                ? "Installed · runs in the local Kokoro environment · 24 kHz"
                : "Kokoro environment not found — set the Python path in Settings (⌘,)"
        }
    }
}
