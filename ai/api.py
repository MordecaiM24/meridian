from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from typing import Optional
from pathlib import Path
import tempfile
import shutil
import os
import json

# Import pipeline functions from main.py (works whether run from repo root or ai/ dir)
try:  # pragma: no cover - flexible imports for local execution
    from .main import ensure_whisper_server, process_audio  # type: ignore
except Exception:  # pragma: no cover
    from main import ensure_whisper_server, process_audio  # type: ignore

try:  # YouTube helper (optional path resilience)
    from .youtube import download_youtube_video  # type: ignore
except Exception:
    from youtube import download_youtube_video  # type: ignore


class ProcessRequest(BaseModel):
    input: str = Field(..., description="Local path or YouTube URL")
    output: Optional[str] = Field(
        default=None, description="Output directory (default: same as input)"
    )
    speakers: Optional[int] = Field(
        default=None, description="Number of speakers (currently ignored)"
    )
    no_diarize: bool = Field(False, description="Skip diarization")
    keep_temp: bool = Field(False, description="Keep temporary files from conversion")
    whisper_port: int = Field(8000, description="Whisper server port")
    no_server: bool = Field(
        False, description="Do not auto-start the underlying Whisper server"
    )
    return_json: bool = Field(
        False,
        description="If true, return combined JSON content rather than just a file path",
    )


app = FastAPI(title="Meridian CLI API", version="0.1.0")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/ensure_whisper_server")
async def api_ensure_whisper_server(port: int = 8000, host: str = "0.0.0.0"):
    try:
        ensure_whisper_server(port=port, host=host)
        return {"status": "ready", "host": host, "port": port}
    except Exception as exc:  # pragma: no cover
        return JSONResponse(status_code=500, content={"error": str(exc)})


@app.post("/process")
async def api_process(req: ProcessRequest):
    try:
        # Start Whisper server if not suppressed
        if not req.no_server:
            ensure_whisper_server(port=req.whisper_port)

        # Determine whether input is a URL
        input_str = req.input
        if input_str.startswith(("http://", "https://", "youtube.com", "youtu.be")):
            output_dir = Path(req.output) if req.output else Path.cwd()
            output_dir.mkdir(parents=True, exist_ok=True)

            # Derive a base name similar to CLI behavior
            video_id = input_str.split("v=")[-1].split("&")[0].split("/")[-1]
            base_name = f"yt_{video_id}"

            target_wav = output_dir / f"{base_name}.wav"
            download_youtube_video(input_str, str(target_wav.with_suffix("")))
            input_path = str(target_wav)
        else:
            input_path = input_str

        output_file = process_audio(
            input_path=input_path,
            output_dir=req.output,
            skip_diarization=req.no_diarize,
            speaker_count=req.speakers,
            keep_temp=req.keep_temp,
            whisper_port=req.whisper_port,
        )

        output_file = str(output_file)

        if req.return_json:
            try:
                with open(output_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                return JSONResponse(content={"output_file": output_file, "data": data})
            except Exception:
                # If not JSON, just return the path
                pass
        return {"output_file": output_file}

    except Exception as exc:  # pragma: no cover
        return JSONResponse(status_code=400, content={"error": str(exc)})


@app.post("/upload")
async def api_upload(
    file: UploadFile = File(...),
    output: Optional[str] = Form(None),
    speakers: Optional[int] = Form(None),
    no_diarize: bool = Form(False),
    keep_temp: bool = Form(False),
    whisper_port: int = Form(8000),
    no_server: bool = Form(False),
    return_json: bool = Form(False),
):
    tmp_dir = tempfile.mkdtemp(prefix="meridian_")
    tmp_path = None
    try:
        # Start Whisper server if not suppressed
        if not no_server:
            ensure_whisper_server(port=whisper_port)

        # Save the uploaded file to a temporary location, preserve suffix if any
        suffix = ""
        if file.filename and "." in file.filename:
            suffix = "." + file.filename.rsplit(".", 1)[-1]
        if not suffix:
            suffix = ".wav"  # fallback

        with tempfile.NamedTemporaryFile(
            dir=tmp_dir, suffix=suffix, delete=False
        ) as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_path = tmp.name

        # If no output dir specified, default to ./outputs like typical API behavior
        actual_output_dir = output if output else str(Path.cwd() / "outputs")
        Path(actual_output_dir).mkdir(parents=True, exist_ok=True)

        output_file = process_audio(
            input_path=tmp_path,
            output_dir=actual_output_dir,
            skip_diarization=no_diarize,
            speaker_count=speakers,
            keep_temp=keep_temp,
            whisper_port=whisper_port,
        )

        output_file = str(output_file)

        if return_json:
            try:
                with open(output_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                return JSONResponse(content={"output_file": output_file, "data": data})
            except Exception:
                pass

        return {"output_file": output_file}

    except Exception as exc:  # pragma: no cover
        return JSONResponse(status_code=400, content={"error": str(exc)})
    finally:
        # Cleanup temp input file and directory
        try:
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except Exception:
            pass
        try:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        except Exception:
            pass
