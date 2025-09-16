"""FastAPI application exposing Meridian CLI workflows over HTTP."""
from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Dict, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field, field_validator

from main import ensure_whisper_server, process_audio
from youtube import download_youtube_video

SUPPORTED_EXTENSIONS = {".wav", ".mp3", ".mp4", ".m4a"}

app = FastAPI(
    title="Meridian Workflow API",
    description="Expose Meridian CLI functionality through HTTP endpoints.",
    version="0.1.0",
)


class EnsureWhisperRequest(BaseModel):
    """Request body for starting the whisper server."""

    port: int = Field(8000, ge=1, le=65535, description="Port for the whisper server")
    host: str = Field("0.0.0.0", description="Host interface to bind the whisper server")


class ProcessRequest(BaseModel):
    """Parameters mirroring the CLI flags from main.py."""

    input: str = Field(
        ...,
        description="Path to an audio/video file or YouTube URL.",
    )
    output: Optional[str] = Field(
        None,
        description="Directory for output artifacts. Defaults to the input directory.",
    )
    speakers: Optional[int] = Field(
        None,
        ge=1,
        description="Optional hint for number of speakers.",
    )
    no_diarize: bool = Field(
        False, description="Skip speaker diarization and merging steps."
    )
    keep_temp: bool = Field(
        False,
        description="Preserve intermediate converted audio files.",
    )
    whisper_port: int = Field(
        8000,
        ge=1,
        le=65535,
        description="Port where the whisper server is listening.",
    )
    no_server: bool = Field(
        False, description="Do not attempt to automatically start the whisper server."
    )

    @field_validator("input")
    @classmethod
    def _validate_input(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("input cannot be empty")
        return value


def _base_output_name(path: Path) -> str:
    name = path.name
    for suffix in (".combined.json", ".transcription.json", ".diarization.json"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return path.stem


def _collect_output_paths(result_path: Path) -> Dict[str, str]:
    base_dir = result_path.parent
    base_name = _base_output_name(result_path)

    outputs: Dict[str, str] = {}

    combined = base_dir / f"{base_name}.combined.json"
    if combined.exists():
        outputs["combined"] = str(combined)

    transcription = base_dir / f"{base_name}.transcription.json"
    if transcription.exists():
        outputs["transcription"] = str(transcription)

    diarization = base_dir / f"{base_name}.diarization.json"
    if diarization.exists():
        outputs["diarization"] = str(diarization)

    return outputs


def _should_treat_as_youtube(value: str) -> bool:
    lower = value.lower()
    return lower.startswith(("http://", "https://", "youtube.com", "youtu.be"))


def _extract_video_id(url: str) -> str:
    video_id = url.split("v=")[-1]
    video_id = video_id.split("&")[0]
    video_id = video_id.split("/")[-1]
    return video_id or "video"


async def _download_youtube_input(url: str, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    base_name = f"yt_{_extract_video_id(url)}"
    target_base = output_dir / base_name

    try:
        await run_in_threadpool(download_youtube_video, url, str(target_base))
    except Exception as exc:  # pragma: no cover - delegated to yt_dlp
        raise HTTPException(
            status_code=400, detail=f"Failed to download YouTube audio: {exc}"
        ) from exc

    return target_base.with_suffix(".wav")


async def _run_pipeline(
    *,
    input_path: str,
    output_dir: Optional[str],
    skip_diarization: bool,
    speaker_count: Optional[int],
    keep_temp: bool,
    whisper_port: int,
    auto_start_server: bool,
) -> Path:
    if auto_start_server:
        await run_in_threadpool(ensure_whisper_server, port=whisper_port)

    try:
        result = await run_in_threadpool(
            process_audio,
            input_path=input_path,
            output_dir=output_dir,
            skip_diarization=skip_diarization,
            speaker_count=speaker_count,
            keep_temp=keep_temp,
            whisper_port=whisper_port,
        )
    except Exception as exc:  # pragma: no cover - relies on external binaries
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return Path(result)


@app.get("/health")
def healthcheck() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/ensure-whisper")
async def ensure_whisper_endpoint(request: EnsureWhisperRequest) -> Dict[str, str]:
    await run_in_threadpool(
        ensure_whisper_server, port=request.port, host=request.host
    )
    return {"status": "ready", "port": str(request.port), "host": request.host}


@app.post("/process")
async def process_request(request: ProcessRequest) -> Dict[str, object]:
    input_value = request.input
    input_type = "local"
    resolved_input = input_value

    if _should_treat_as_youtube(input_value):
        input_type = "youtube"
        output_dir = Path(request.output).expanduser() if request.output else Path.cwd()
        resolved_input = str(await _download_youtube_input(input_value, output_dir))
    else:
        path = Path(input_value).expanduser()
        if not path.exists():
            raise HTTPException(status_code=404, detail=f"Input file not found: {path}")
        resolved_input = str(path)

    result_path = await _run_pipeline(
        input_path=resolved_input,
        output_dir=request.output,
        skip_diarization=request.no_diarize,
        speaker_count=request.speakers,
        keep_temp=request.keep_temp,
        whisper_port=request.whisper_port,
        auto_start_server=not request.no_server,
    )

    outputs = _collect_output_paths(result_path)

    return {
        "status": "completed",
        "input_type": input_type,
        "output_directory": str(result_path.parent),
        "generated_files": outputs,
    }


@app.post("/process/upload")
async def process_upload(
    file: UploadFile = File(...),
    output: Optional[str] = Form(None),
    speakers: Optional[int] = Form(None),
    no_diarize: bool = Form(False),
    keep_temp: bool = Form(False),
    whisper_port: int = Form(8000),
    no_server: bool = Form(False),
) -> Dict[str, object]:
    filename = file.filename or "upload.wav"
    suffix = Path(filename).suffix.lower()

    if suffix not in SUPPORTED_EXTENSIONS:
        supported = ", ".join(sorted(SUPPORTED_EXTENSIONS))
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file extension '{suffix}'. Supported types: {supported}",
        )

    output_dir = Path(output).expanduser() if output else Path.cwd()
    output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        data = await file.read()
        tmp.write(data)
        tmp_path = tmp.name

    try:
        result_path = await _run_pipeline(
            input_path=tmp_path,
            output_dir=str(output_dir),
            skip_diarization=no_diarize,
            speaker_count=speakers,
            keep_temp=keep_temp,
            whisper_port=whisper_port,
            auto_start_server=not no_server,
        )
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    outputs = _collect_output_paths(result_path)

    return {
        "status": "completed",
        "input_type": "upload",
        "output_directory": str(result_path.parent),
        "generated_files": outputs,
    }
