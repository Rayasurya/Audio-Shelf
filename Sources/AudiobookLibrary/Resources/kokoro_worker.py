import hashlib
import json
import os
import signal
import sys
from pathlib import Path

# The parent process parses stdout as newline-delimited JSON events, but the
# model libraries print warnings with plain print(). Keep the original stdout
# for events only, and send everything else (including sys.stdout) to stderr.
event_stream = os.fdopen(os.dup(sys.stdout.fileno()), "w")
sys.stdout = sys.stderr

import numpy as np
import soundfile as sf
from kokoro import KPipeline


was_cancelled = False
SAMPLE_RATE = 24000


def emit(event):
    event_stream.write(json.dumps(event) + "\n")
    event_stream.flush()


def request_cancellation(signal_number, frame):
    del signal_number
    del frame
    global was_cancelled
    was_cancelled = True


def chapter_fingerprint(chapter, voice):
    payload = voice + "\n" + chapter["text"]
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def completed_chapter_meta(chapter, voice, output_directory):
    """Returns the saved metadata when this chapter's audio already exists for
    the same text and voice, so an interrupted book resumes instead of
    regenerating finished chapters."""
    chapter_index = chapter["index"]
    final_path = output_directory / f"chapter-{chapter_index:03d}.wav"
    meta_path = output_directory / f"chapter-{chapter_index:03d}.meta.json"
    if not final_path.exists() or not meta_path.exists():
        return None
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if meta.get("textHash") != chapter_fingerprint(chapter, voice):
        return None
    return meta


def write_chapter(pipeline, chapter, output_directory, voice):
    chapter_index = chapter["index"]
    chapter_title = chapter["title"]
    emit({"type": "chapterStarted", "chapterIndex": chapter_index, "chapterTitle": chapter_title})

    final_path = output_directory / f"chapter-{chapter_index:03d}.wav"
    reused = completed_chapter_meta(chapter, voice, output_directory)
    if reused is not None:
        emit(
            {
                "type": "chapterCompleted",
                "chapterIndex": chapter_index,
                "chapterTitle": chapter_title,
                "path": str(final_path),
                "duration": reused["duration"],
                "reused": True,
            }
        )
        return reused

    chunks = []
    timings = []
    cursor = 0.0
    for graphemes, _, audio in pipeline(chapter["text"], voice=voice, speed=1):
        if was_cancelled:
            raise InterruptedError("Generation cancelled after a completed chunk")
        duration = len(audio) / SAMPLE_RATE
        timings.append({"text": graphemes, "start": cursor, "end": cursor + duration})
        cursor += duration
        chunks.append(audio)
    if not chunks:
        raise ValueError(f"No audio was generated for chapter {chapter_index}")
    audio = np.concatenate(chunks)
    temporary_path = output_directory / f"chapter-{chapter_index:03d}.tmp.wav"
    sf.write(temporary_path, audio, SAMPLE_RATE)
    temporary_path.replace(final_path)

    meta = {
        "index": chapter_index,
        "title": chapter_title,
        "textHash": chapter_fingerprint(chapter, voice),
        "duration": len(audio) / SAMPLE_RATE,
        "timings": timings,
    }
    meta_path = output_directory / f"chapter-{chapter_index:03d}.meta.json"
    meta_path.write_text(json.dumps(meta), encoding="utf-8")

    emit(
        {
            "type": "chapterCompleted",
            "chapterIndex": chapter_index,
            "chapterTitle": chapter_title,
            "path": str(final_path),
            "duration": meta["duration"],
        }
    )
    return meta


def main(manifest_path):
    signal.signal(signal.SIGINT, request_cancellation)
    signal.signal(signal.SIGTERM, request_cancellation)
    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    output_directory = Path(manifest["outputDirectory"])
    output_directory.mkdir(parents=True, exist_ok=True)
    emit({"type": "workerStarted"})
    pipeline = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")
    chapter_metas = []
    for chapter in manifest["chapters"]:
        if was_cancelled:
            raise InterruptedError("Generation cancelled before the next chapter")
        chapter_metas.append(write_chapter(pipeline, chapter, output_directory, manifest["voice"]))
    # Aggregate read-along timing manifest for the whole book. Chunk times are
    # chapter-relative; the app offsets them by chapter start when playing.
    aggregate = {
        "version": 1,
        "voice": manifest["voice"],
        "chapters": [
            {
                "index": meta["index"],
                "duration": meta["duration"],
                "timings": meta.get("timings", []),
            }
            for meta in chapter_metas
        ],
    }
    (output_directory / "timings.json").write_text(json.dumps(aggregate), encoding="utf-8")
    emit({"type": "workerCompleted"})


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Expected one manifest path argument")
        main(sys.argv[1])
    except InterruptedError as error:
        emit({"type": "cancelled", "message": str(error)})
        sys.exit(130)
    except Exception as error:
        emit({"type": "failed", "message": str(error)})
        raise
