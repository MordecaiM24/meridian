# Meridian

Local‑first speech‑to‑text with optional speaker diarization. This monorepo contains:

- `ai/`: a Python FastAPI service wrapping whisper.cpp (OpenAI‑compatible endpoints and a higher‑level CLI/API).
- `ui/Meridian/`: a SwiftUI macOS app that talks to the local `ai` service to upload/process audio and display labeled transcripts.

If you used this project when it was `ai/` only: the original docs live in `ai/README.md`. This root README adds the macOS app and ties everything together.

---

## Repository structure

- `ai/`
  - FastAPI apps:
    - OpenAI‑compatible: `/v1/audio/transcriptions`, `/v1/models` (served by `transcribe.py`)
    - CLI‑mirror API: `/health`, `/ensure_whisper_server`, `/process`, `/upload` (served by `api.py`)
  - CLI pipeline in `main.py` (downloads from YouTube, transcribes via whisper.cpp, optional diarization with `pyannote.audio`, merges outputs)
  - Prebuilt whisper.cpp binaries under `ai/build/bin/` (e.g., `whisper-cli`, `whisper-server`)
  - Models and helpers in `ai/models/` (includes GGML models and scripts)
- `ui/Meridian/`
  - SwiftUI macOS app (`Meridian.xcodeproj`)
  - Default API base URL: `http://127.0.0.1:8080` (see `Networking/MeridianAPI.swift`)

---

## Quick start (macOS)

### Prerequisites
- macOS 15.1+ (Sequoia) and Xcode 16.1+ for the app
- Python 3.13+ (managed automatically if you use `uv`)
- ffmpeg (`brew install ffmpeg`)
- Optional for diarization: a Hugging Face token with access to `pyannote/speaker-diarization-3.1`

### 1) Start the AI service

```bash
cd ai

# Install Python deps (recommended)
uv sync

# Optional: enable diarization
export HF_TOKEN=hf_XXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Run the higher-level API the app uses
uv run uvicorn api:app --host 127.0.0.1 --port 8080
# Health check:
# curl http://127.0.0.1:8080/health
```

Notes:
- The service will auto‑start the underlying Whisper server on port 8000 when needed.
- OpenAI‑compatible endpoints (for power users): run `uv run uvicorn transcribe:app --host 127.0.0.1 --port 8000`.

### 2) Run the macOS app

1. Open `ui/Meridian/Meridian.xcodeproj` in Xcode.
2. Select the `Meridian` scheme and “My Mac” destination.
3. Build and run.

By default the app talks to `http://127.0.0.1:8080`. To change this, edit `ui/Meridian/Meridian/Networking/MeridianAPI.swift` (`MeridianAPIConfiguration(baseURL:)`).

---

## Using the CLI (optional)

You can also run the end‑to‑end CLI directly (this will auto‑start the Whisper server on port 8000):

```bash
cd ai
uv run python main.py path/to/audio_or_video.(wav|mp4|mp3|m4a)

# Save outputs into a directory
uv run python main.py video.mp4 -o transcripts/

# From YouTube URL
uv run python main.py "https://youtube.com/watch?v=VIDEO_ID" -o transcripts/

# Skip diarization
uv run python main.py audio.wav --no-diarize
```

Outputs (for input base name `sample`):
- `sample.transcription.json` — raw transcription from the server (verbose JSON)
- `sample.diarization.json` — diarization segments (if enabled)
- `sample.combined.json` — merged, speaker‑labeled transcript

See more details in `ai/README.md`.

---

## Models

The default model is `ai/models/ggml-medium.en.bin` (as invoked by `ai/transcribe.py`/whisper.cpp). You can:
- Swap in a different GGML model file at that path, or
- Edit `ai/transcribe.py` to point to a different model, or
- Use helper scripts in `ai/models/` (e.g., `download-ggml-model.sh`) to fetch additional models.

---

## Ports and endpoints

- Whisper (OpenAI‑compatible) server: `http://127.0.0.1:8000/v1`
- App API (CLI‑mirror) server used by the macOS app: `http://127.0.0.1:8080`
  - `POST /ensure_whisper_server` — starts/ensures whisper server (json: `{port, host}`)
  - `POST /process` — process a local path or YouTube URL (json body)
  - `POST /upload` — upload and process a file (multipart/form‑data)
  - `GET /health` — health check

---

## Troubleshooting

- ffmpeg not found: `brew install ffmpeg`
- Python version errors: ensure Python 3.13+ (use `uv sync` to manage automatically)
- Whisper binary missing: ensure `ai/build/bin/whisper-cli` exists; if you rebuild whisper.cpp, update paths in `ai/transcribe.py` if needed
- Diarization issues: set `HF_TOKEN` and ensure a suitable PyTorch is present for your platform; or run with `--no-diarize`

---

## Acknowledgements

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for fast local Whisper inference
- [pyannote.audio](https://github.com/pyannote/pyannote-audio) for diarization
- [yt‑dlp](https://github.com/yt-dlp/yt-dlp) for robust media downloading


