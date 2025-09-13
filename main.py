from openai import OpenAI
import subprocess

# kill server and restart it
subprocess.run(["pkill", "-f", "uvicorn transcription:app"])
subprocess.Popen(
    ["uvicorn", "transcription:app", "--host", "0.0.0.0", "--port", "8000"]
)

# point to your local server
client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="fake-key",  # openai client requires this even for local
)

client.models.list()

transcript = client.audio.transcriptions.create(
    file=audio_file,
    model="whisper-1",
    response_format="verbose_json",
    timestamp_granularities=["word", "segment"],
)
