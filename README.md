
# Meridian

Local-first speech-to-text with speaker diarization. This repo wraps whisper.cpp behind an OpenAI-compatible FastAPI server and provides a CLI that can:

- Transcribe audio/video files using whisper.cpp
- Optionally diarize speakers using pyannote.audio
- Download audio from YouTube and process it end-to-end
- Emit structured JSON files for raw transcription, diarization, and a merged, speaker-labelled transcript

The default model is `models/ggml-medium.en.bin`. You can change the model by editing `transcribe.py`.

> This repo hasn't been merged with the associated RAG application to become a monorepo yet - check that out [here](https://github.com/MordecaiM24/ncsu-sg/) for the current [public version](https://sg.m16b.com/) or [here](https://github.com/MordecaiM24/aletheia) for the more modular, scalable update that'll be out soon.

---

## Contents
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [With uv (recommended)](#with-uv-recommended)
  - [With pip](#with-pip)
- [Diarization setup (HF_TOKEN)](#diarization-setup-hf_token)
- [Running](#running)
  - [CLI (auto-starts server)](#cli-auto-starts-server)
  - [Starting the server manually](#starting-the-server-manually)
  - [Calling the server API](#calling-the-server-api)
- [Outputs](#outputs)
- [YouTube support](#youtube-support)
- [Model selection](#model-selection)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Acknowledgements](#acknowledgements)

---

## Features
- OpenAI-compatible endpoints served by FastAPI (`/v1/audio/transcriptions`, `/v1/models`)
- Whisper inference via whisper.cpp binary (`build/bin/whisper-cli`)
- Optional speaker diarization via `pyannote.audio` (HF Token required)
- YouTube download via `yt-dlp` with automatic 16 kHz mono WAV conversion (ffmpeg required)
- Clean, merged JSON output with per-segment speakers and optional per-word timestamps

## Requirements
- Python 3.13+
- ffmpeg (for audio conversion)
  - macOS (Homebrew): `brew install ffmpeg`
  - Linux: use your distro package manager
- A whisper.cpp binary at `build/bin/whisper-cli`
  - This repo includes a `build/` directory. If you need to rebuild or use a different platform, follow whisper.cpp build instructions.
- For diarization (optional but recommended):
  - A Hugging Face token (`HF_TOKEN`) with access to `pyannote/speaker-diarization-3.1`
  - PyTorch appropriate for your platform (CPU/CUDA/MPS)

## Installation

### With uv (recommended)
```bash
# Install uv if you don't have it
# macOS/Linux: curl -LsSf https://astral.sh/uv/install.sh | sh

uv sync
```

### With pip
```bash
python3.13 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install .
```

## Diarization setup (HF_TOKEN)
`pyannote.audio` requires an HF token. Create a `.env` file or export the variable:
```bash
echo "HF_TOKEN=hf_XXXXXXXXXXXXXXXXXXXXXXXXXXXX" > .env
# or
export HF_TOKEN=hf_XXXXXXXXXXXXXXXXXXXXXXXXXXXX
```
If you do not want diarization, pass `--no-diarize` to the CLI.

Note: You may need to install PyTorch separately according to your platform.

## Running

### CLI (auto-starts server)
The CLI will check for a running server and start one on demand.

```bash
# Basic transcription (auto diarization if HF_TOKEN is set; else pass --no-diarize)
python main.py path/to/audio_or_video.(wav|mp4|mp3|m4a)

# Save outputs to a directory
python main.py path/to/video.mp4 -o transcripts/

# From YouTube URL
python main.py "https://youtube.com/watch?v=VIDEO_ID" -o transcripts/

# Skip diarization
python main.py audio.wav --no-diarize

# Choose a port or skip server auto-start
python main.py audio.wav --whisper-port 8001 --no-server

# Keep the intermediate 16 kHz mono wav (when converting from mp4/mp3/m4a)
python main.py video.mp4 --keep-temp
```

CLI options (from `main.py`):
- `input` (positional): audio/video file path or YouTube URL
- `-o, --output`: output directory (default: same as input)
- `--speakers <int>`: number of speakers (see Known limitations)
- `--no-diarize`: skip diarization
- `--keep-temp`: keep temporary files
- `--whisper-port <int>`: whisper server port (default: 8000)
- `--no-server`: do not auto-start the server

### Starting the server manually
```bash
uvicorn transcribe:app --host 0.0.0.0 --port 8000
```
Endpoints:
- `GET /v1/models`
- `POST /v1/audio/transcriptions`

NOTE:
If you would prefer to use the cloud, the api is fully OpenAI compatible - just
remove the base_url flag in main.py and add your own API key

### Calling the server API
Using curl:
```bash
curl -s -X POST http://localhost:8000/v1/audio/transcriptions \
  -H "Authorization: Bearer dummy" \
  -F file=@audio.wav \
  -F model=whisper-1 \
  -F response_format=verbose_json \
  -F "timestamp_granularities[]=word" \
  -F "timestamp_granularities[]=segment" | jq .
```

Using the OpenAI Python SDK (pointed at the local server):
```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:8000/v1", api_key="dummy")
with open("audio.wav", "rb") as f:
    resp = client.audio.transcriptions.create(
        file=f,
        model="whisper-1",
        response_format="verbose_json",
        timestamp_granularities=["word", "segment"],
    )
print(resp)
```

## Outputs
For an input base name like `sample` and output directory `out/`, the CLI writes:

- `out/sample.transcription.json` — raw transcription (verbose JSON) from the server
- `out/sample.diarization.json` — diarization segments (`[{start, end, speaker}, ...]`)
- `out/sample.combined.json` — merged output with speaker-labelled segments and overlaps

Combined JSON shape (abridged):
```json
{
  "metadata": {"duration": 123.4, "language": "english", "original_text": "..."},
  "speakers": {"SPEAKER_00": {"label": "speaker_00", "color": null}},
  "segments": [
    {
      "id": 0,
      "speaker": "SPEAKER_00",
      "start": 0.0,
      "end": 3.2,
      "text": "Hello and welcome ...",
      "tokens": [123, 456],
      "confidence": 0.98,
      "avg_logprob": -0.3,
      "no_speech_prob": 0.01,
      "whisper_ids": [0]
    }
  ],
  "overlaps": [
    {"start": 12.3, "end": 12.9, "speakers": ["SPEAKER_00", "SPEAKER_01"]}
  ],
  "words": [{"word": "Hello", "start": 0.0, "end": 0.2}]
}
```

## YouTube support
The CLI can accept a YouTube URL. Audio is fetched via `yt-dlp`, converted to 16 kHz mono WAV with `ffmpeg`, and then processed. Filenames are kebab-cased for consistency.

- Single video: pass the URL directly to the CLI.
- Playlists: use `youtube.py:download_youtube_playlist` programmatically if needed.

## Model selection
`transcribe.py` invokes `build/bin/whisper-cli` with:
```bash
-m models/ggml-medium.en.bin
```
To change the model, replace the file at `models/ggml-medium.en.bin` or edit the path in `transcribe.py`.

The repo includes additional models under `models/`. You can also use the helper scripts in `models/` (e.g., `download-ggml-model.sh`) to fetch others.

## Known limitations
- The `--speakers` flag is not wired in `diarize.py`; passing it currently raises an error. Omit it to allow automatic speaker detection, or use `--no-diarize`.
- Word-level timestamps are approximated from whisper.cpp token timings and do not represent linguistically segmented words.
- `build/bin/whisper-cli` must exist for transcription. If you rebuild whisper.cpp yourself, ensure the binary path matches the code or update `transcribe.py`.

## Troubleshooting
- ffmpeg not found: install it (`brew install ffmpeg` on macOS).
- Diarization errors: ensure `HF_TOKEN` is set and PyTorch is installed for your platform. You can skip diarization with `--no-diarize`.
- Server not ready: the CLI waits briefly after starting `uvicorn`. If you see readiness warnings, retry the command or start the server manually.
- Slow performance: use a smaller model (e.g., `models/ggml-small.en.bin`) and update `transcribe.py` accordingly.

## Acknowledgements
- whisper.cpp for blazing-fast local Whisper inference
- pyannote.audio for state-of-the-art speaker diarization
- yt-dlp for robust media downloading


