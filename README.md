# Audio Shelf for macOS

Audio Shelf is a private, local-first book-to-audio companion. Drop in a TXT, EPUB, or text-based PDF you're entitled to use, and it becomes a chaptered audiobook (M4B) or podcast episodes (tagged M4A per chapter) — narrated on your Mac, never in the cloud.

Highlights:

- **Everything local**: Kokoro TTS narration, ffmpeg packaging, and optional LLM section classification (via LM Studio/Ollama) all run on-device.
- **Clean chapters**: titles from the EPUB table of contents; Gutenberg boilerplate, licenses, and contents pages excluded automatically — with a review screen that shows what was excluded and why, and lets you override anything.
- **Read along**: chunk-level timestamps recorded at generation drive live text highlighting, tap-to-seek, and a full-screen focus mode (one sentence at a time — built with ADHD and reading difficulties in mind).
- **Your workflows**: trigger-word removal/replacement rules, per-book voices, playback speed 0.5–3×, skip-notes-while-listening, listening presets, and a per-book record of exactly how each edition was generated.
- **Interruption-proof**: completed chapters are fingerprinted; resuming narrates only what's missing or changed.

MIT-licensed. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the ground rules (local-first, faithful narration, nothing silent).

## Requirements

- macOS 14 or later with a matching Xcode or Command Line Tools installation.
- The local Kokoro environment at `../kokoro-tts/venv2`, or an `AUDIOBOOK_KOKORO_PYTHON` environment variable that points to a Python executable containing `kokoro`, `numpy`, and `soundfile`.
- `ffmpeg` for AAC/M4B packaging. The app detects Homebrew's `/opt/homebrew/bin/ffmpeg`, or use `AUDIOBOOK_FFMPEG` to provide its absolute path.

## Run

From this directory:

```sh
swift run
```

If Kokoro or ffmpeg live elsewhere:

```sh
AUDIOBOOK_KOKORO_PYTHON=/absolute/path/to/python AUDIOBOOK_FFMPEG=/absolute/path/to/ffmpeg swift run
```

The library stores imported sources, generated chapter WAVs, M4B editions, and metadata in `~/Library/Application Support/AudiobookLibrary/`.

## Test

```sh
zsh Scripts/test.sh
```

This runs an import test plus a real end-to-end test that narrates a bundled three-chapter fixture with Kokoro and packages it into a chaptered M4B, so it needs the Kokoro environment and ffmpeg from the requirements above. The script exists because Command Line Tools (without full Xcode) keep Swift Testing in a non-default path; with full Xcode installed, plain `swift test` also works.

## Canonical MVP validation

1. Run [download-canonical-book.sh](./Scripts/download-canonical-book.sh) to download the public-domain EPUB of *Alice's Adventures in Wonderland*.
2. Import `Fixtures/alice.epub` in Audio Shelf.
3. Review the detected chapters and their narration text.
4. Generate the audiobook locally with Kokoro.
5. Confirm the app produces an M4B, reopens it, preserves chapter navigation, changes speed, and resumes playback after reopening.

The app does not support scanned PDFs, cloud inference, voice cloning, or redistribution. Only import books you are entitled to use.
