import json
import os
from pathlib import Path
from typing import Dict, List, Optional
import dotenv

dotenv.load_dotenv()

hf_token = os.getenv("HF_TOKEN")


def _get_device_string() -> str:
    try:
        import torch

        if hasattr(torch, "cuda") and torch.cuda.is_available():
            return "cuda"
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
    except Exception:
        pass
    return "cpu"


def diarize_audio(audio_path: str, hf_token: Optional[str] = None) -> List[Dict]:
    try:
        from pyannote.audio import Pipeline  # type: ignore
    except Exception as exc:  # pragma: no cover - optional dependency
        raise RuntimeError(
            "pyannote.audio is required for diarization. Install with: pip install pyannote.audio torch torchvision torchaudio"
        ) from exc

    token = hf_token or os.getenv("HF_TOKEN")
    if not token:
        raise RuntimeError(
            "HF_TOKEN environment variable is required for pyannote diarization (Hugging Face access token)."
        )

    pipeline = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-3.1", use_auth_token=token
    )

    device = _get_device_string()
    try:
        import torch  # type: ignore

        pipeline.to(torch.device(device))
    except Exception:
        # Fallback silently to CPU if device move fails
        pass

    diarization = pipeline(audio_path)

    segments: List[Dict] = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        segments.append(
            {
                "start": float(getattr(turn, "start", 0.0)),
                "end": float(getattr(turn, "end", 0.0)),
                "speaker": str(speaker),
            }
        )
    # Ensure segments are sorted by start time
    segments.sort(key=lambda s: s["start"])
    return segments


def save_diarization_json(audio_path: str, segments: List[Dict]) -> str:
    audio = Path(audio_path)
    diar_json = audio.with_name(audio.stem + ".diarization.json")
    with open(diar_json, "w", encoding="utf-8") as f:
        json.dump({"segments": segments}, f, ensure_ascii=False, indent=2)
    return str(diar_json)


def diarize_playlist(
    playlist_path: str, hf_token: Optional[str] = None
) -> Dict[str, List[Dict]]:
    playlist_dir = Path(playlist_path)
    print(f"Looking for playlist directory: {playlist_dir}")
    if not playlist_dir.exists():
        raise FileNotFoundError(f"Collection directory not found: {playlist_dir}")

    results: Dict[str, List[Dict]] = {}
    for video_dir in playlist_dir.iterdir():

        wav_files = list(playlist_dir.glob("*.wav"))

        for wav_file in wav_files:
            print(f"Processing audio file: {wav_file}")
            try:
                segments = diarize_audio(str(wav_file), hf_token=hf_token)
                results[str(wav_file)] = segments
                print(f"Successfully processed: {wav_file}")
            except Exception as e:
                print(f"Error processing {wav_file}: {e}")

    print(f"Total files processed: {len(results)}")
    return results


def save_playlist_diarization(results: Dict[str, List[Dict]]) -> List[str]:
    output_files: List[str] = []
    for audio_path, segments in results.items():
        try:
            out = save_diarization_json(audio_path, segments)
            output_files.append(out)
        except Exception as e:
            print(f"Error saving {audio_path}: {e}")
    return output_files


def load_diarization_json(video_dir: str, base_name: str) -> Optional[Dict]:
    path = Path(video_dir) / f"{base_name}.diarization.json"
    if not path.exists():
        return None
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_speakers_map(video_dir: str, base_name: str) -> Dict[str, str]:
    path = Path(video_dir) / f"{base_name}.speakers.json"
    if not path.exists():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
            return {}
    except Exception:
        return {}


def save_speakers_map(video_dir: str, base_name: str, mapping: Dict[str, str]) -> str:
    path = Path(video_dir) / f"{base_name}.speakers.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(mapping, f, ensure_ascii=False, indent=2)
    return str(path)
