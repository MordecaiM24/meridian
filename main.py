from openai import OpenAI
import subprocess
import json
import os

subprocess.run(["pkill", "-f", "uvicorn transcribe:app"])
subprocess.Popen(["uvicorn", "transcribe:app", "--host", "0.0.0.0", "--port", "8000"])

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="mordecai",  # openai client requires this even for local
)

client.models.list()

transcript = client.audio.transcriptions.create(
    file=audio_file,
    model="whisper-1",
    response_format="verbose_json",
    timestamp_granularities=["word", "segment"],
)
