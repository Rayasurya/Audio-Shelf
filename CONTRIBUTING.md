# Contributing to Audio Shelf

Audio Shelf is a local-first macOS app that turns books you own into narrated
audiobooks and podcast episodes — private by default, flexible by design.

## Ground rules

- **Local-first is non-negotiable.** Features must work without network access.
  Anything that sends book text off the machine must be explicit, per-book
  opt-in, and off by default.
- **Fidelity in audiobook mode.** Narration may normalize text for speech, but
  audiobook mode never summarizes or rewrites. Transformations belong to
  workflows (rules, podcast mode) the user chose.
- **Nothing silent.** If the app excludes, rewrites, or skips something, the
  user can see what and why (review badges, generation records, settings).

## Development

- macOS 14+, Swift 6 (Command Line Tools are enough — no Xcode needed).
- `swift build` builds; `zsh Scripts/test.sh` runs the suite (real Kokoro +
  ffmpeg end-to-end tests included).
- `zsh Scripts/build-app.sh --install` assembles the signed .app into
  /Applications.
- Narration runs in `Sources/AudiobookLibrary/Resources/kokoro_worker.py`
  through a JSON-over-stdout protocol; keep stdout reserved for events.

## Layout

- `Domain/` — models and the reducer (pure, tested).
- `Services/` — import, narration, packaging, timings, settings, LLM seam.
- `Views/` — SwiftUI (library, review, generation, player, focus, settings).
- `Tests/` — Swift Testing suite; add a test with every behavior change.
