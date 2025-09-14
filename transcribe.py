# openai_compat.py
from fastapi import FastAPI, UploadFile, Form, File
from fastapi.responses import JSONResponse
from typing import Optional, Literal, List
import tempfile
import subprocess
import json
import os

app = FastAPI()


@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model: str = Form("whisper-1"),
    prompt: Optional[str] = Form(None),
    response_format: Literal["json", "text", "srt", "vtt", "verbose_json"] = Form(
        "json"
    ),
    temperature: float = Form(0.0),
    language: Optional[str] = Form(None),
    timestamp_granularities: Optional[List[str]] = Form(
        None, alias="timestamp_granularities[]"
    ),
):

    print(f"timestamp_granularities: {timestamp_granularities}")
    print(f"type: {type(timestamp_granularities)}")

    # save the wav
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        # run whisper-cli
        cmd = [
            "./build/bin/whisper-cli",
            "-m",
            "models/ggml-medium.en.bin",
            "-fa",  # flash attention
            "-f",
            tmp_path,
            "-ojf",  # output json
        ]

        if language:
            cmd.extend(["-l", language])
        if prompt:
            cmd.extend(["--prompt", prompt])

        result = subprocess.run(cmd, capture_output=True, text=True, check=True)

        # whisper.cpp outputs to {audio.wav}.json (with .wav.json suffix)
        json_output_path = tmp_path + ".json"

        with open(json_output_path, "r") as f:
            whisper_output = json.load(f)

        # extract everything
        full_text = ""
        segments = []
        words = []

        for i, seg in enumerate(whisper_output.get("transcription", [])):
            seg_text = seg["text"]
            full_text += seg_text

            seg_start = seg["offsets"]["from"] / 1000.0
            seg_end = seg["offsets"]["to"] / 1000.0

            # build segment
            segment_entry = {
                "id": i,
                "seek": 0,
                "start": seg_start,
                "end": seg_end,
                "text": seg_text,
                "tokens": [t["id"] for t in seg.get("tokens", [])],
                "temperature": temperature,
                "avg_logprob": -0.3,  # fake bc whisper.cpp doesn't provide
                "compression_ratio": 1.2,  # fake
                "no_speech_prob": 0.01,  # fake
            }
            segments.append(segment_entry)

            # extract words from tokens if requested
            if timestamp_granularities and "word" in timestamp_granularities:
                for token in seg.get("tokens", []):
                    token_text = token["text"]

                    # skip special tokens
                    if token_text.startswith("[") and token_text.endswith("]"):
                        continue

                    # treat each non-special token as a "word" for now
                    # this is imperfect but whisper.cpp doesn't give us real words
                    if token_text.strip():
                        words.append(
                            {
                                "word": token_text.strip(),
                                "start": token["offsets"]["from"] / 1000.0,
                                "end": token["offsets"]["to"] / 1000.0,
                            }
                        )

        # calc duration from last segment
        duration = segments[-1]["end"] if segments else 0.0

        # format response
        if response_format == "text":
            return full_text.strip()

        elif response_format == "verbose_json":
            response = {
                "task": "transcribe",
                "language": language or "english",
                "duration": duration,
                "text": full_text.strip(),
            }

            if timestamp_granularities:
                if "segment" in timestamp_granularities:
                    response["segments"] = segments
                if "word" in timestamp_granularities:
                    response["words"] = words
            else:
                # default to segments if no granularity specified
                response["segments"] = segments

            response["usage"] = {"type": "duration", "seconds": int(duration)}

            return JSONResponse(content=response)

        else:  # regular json
            return JSONResponse(content={"text": full_text.strip()})

    finally:
        os.unlink(tmp_path)
        # also clean up the json output file
        json_output_path = tmp_path + ".json"
        if os.path.exists(json_output_path):
            os.unlink(json_output_path)


@app.get("/v1/models")
async def list_models():
    return {"data": [{"id": "whisper-1", "object": "model", "owned_by": "openai"}]}
