import argparse
import subprocess
import json
import os
import sys
import time
from pathlib import Path
from openai import OpenAI
from diarize import diarize_audio
from merge import process_transcription
from youtube import download_youtube_video


def ensure_whisper_server(port=8000, host="0.0.0.0"):
    """ensure whisper server is running"""
    # check if already running
    result = subprocess.run(["pgrep", "-f", f"uvicorn.*{port}"], capture_output=True)

    if result.returncode == 0:
        print(f"whisper server already running on port {port}")
        client = OpenAI(base_url=f"http://localhost:{port}/v1", api_key="dummy")
        print(client.models.list())
        return

    print(f"starting whisper server on {host}:{port}...")
    subprocess.Popen(
        ["uvicorn", "transcribe:app", "--host", host, "--port", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # wait for server to be ready
    for i in range(10):
        try:
            client = OpenAI(base_url=f"http://localhost:{port}/v1", api_key="dummy")
            client.models.list()
            print("server ready")
            return
        except:
            time.sleep(1)

    print("warning: server might not be ready yet")


def process_audio(
    input_path,
    output_dir=None,
    skip_diarization=False,
    speaker_count=None,
    keep_temp=False,
    whisper_port=8000,
):
    """main processing pipeline"""

    input_path = Path(input_path)

    # setup output directory
    if output_dir:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
    else:
        output_dir = input_path.parent

    # determine audio file
    if input_path.suffix == ".wav":
        audio_file = input_path
        base_name = input_path.stem
    else:
        # attempt conversion for any file type
        base_name = input_path.stem
        audio_file = output_dir / f"{base_name}.wav"
        print(f"converting {input_path} to wav...")
        try:
            result = subprocess.run(
                [
                    "ffmpeg",
                    "-i",
                    str(input_path),
                    "-ar",
                    "16000",
                    "-ac",
                    "1",
                    "-y",  # overwrite output file if it exists
                    str(audio_file),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr if e.stderr else str(e)
            raise ValueError(
                f"failed to convert {input_path.suffix} file to audio: {error_msg}"
            )
        except FileNotFoundError:
            raise ValueError(
                "ffmpeg not found. Please install ffmpeg to convert audio/video files."
            )

    # transcribe
    print(f"transcribing {audio_file}...")
    client = OpenAI(base_url=f"http://localhost:{whisper_port}/v1", api_key="dummy")
    print("client created")

    with open(audio_file, "rb") as f:
        print("opening file")
        transcript = client.audio.transcriptions.create(
            file=f,
            model="whisper-1",
            response_format="verbose_json",
            timestamp_granularities=["word", "segment"],
        )

    # save raw transcription
    transcription_file = output_dir / f"{base_name}.transcription.json"
    with open(transcription_file, "w") as f:
        json.dump(transcript.model_dump(), f, indent=2)
    print(f"saved transcription to {transcription_file}")

    # diarization
    if not skip_diarization:
        print(
            f"diarizing audio{f' with {speaker_count} speakers' if speaker_count else ''}..."
        )
        diarization = diarize_audio(str(audio_file))

        # save raw diarization
        diarization_file = output_dir / f"{base_name}.diarization.json"
        with open(diarization_file, "w") as f:
            json.dump(diarization, f, indent=2)
        print(f"saved diarization to {diarization_file}")

        # merge
        print("merging transcription and diarization...")
        output = process_transcription(
            transcription=transcript.model_dump(),
            diarization=diarization,
        )

        # save combined output
        combined_file = output_dir / f"{base_name}.combined.json"
        with open(combined_file, "w") as f:
            json.dump(output, f, indent=2)
        print(f"saved combined output to {combined_file}")
    else:
        print("skipping diarization")
        combined_file = transcription_file

    # cleanup
    if not keep_temp and audio_file != input_path:
        audio_file.unlink()
        print(f"removed temporary wav file")

    return combined_file


def main():
    parser = argparse.ArgumentParser(
        description="transcribe and diarize audio/video files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  %(prog)s video.mp4
  %(prog)s https://youtube.com/watch?v=... -o transcripts/
  %(prog)s audio.wav --speakers 3
  %(prog)s recording.wav --no-diarize
        """,
    )

    parser.add_argument("input", help="audio/video file or youtube url")
    parser.add_argument(
        "-o", "--output", help="output directory (default: same as input)"
    )
    parser.add_argument(
        "--speakers", type=int, help="number of speakers (auto-detect if not specified)"
    )
    parser.add_argument("--no-diarize", action="store_true", help="skip diarization")
    parser.add_argument("--keep-temp", action="store_true", help="keep temporary files")
    parser.add_argument(
        "--whisper-port", type=int, default=8000, help="whisper server port"
    )
    parser.add_argument(
        "--no-server", action="store_true", help="don't start whisper server"
    )

    args = parser.parse_args()

    try:
        # start whisper server if needed
        if not args.no_server:
            ensure_whisper_server(port=args.whisper_port)

        # handle youtube urls
        if args.input.startswith(("http://", "https://", "youtube.com", "youtu.be")):
            print(f"downloading youtube video: {args.input}")
            output_dir = Path(args.output) if args.output else Path.cwd()
            output_dir.mkdir(parents=True, exist_ok=True)

            # extract video id for filename
            video_id = args.input.split("v=")[-1].split("&")[0].split("/")[-1]
            base_name = f"yt_{video_id}"

            audio_file = output_dir / f"{base_name}.wav"
            download_youtube_video(args.input, str(audio_file.with_suffix("")))
            input_path = audio_file
        else:
            input_path = args.input

        # process
        output_file = process_audio(
            input_path=input_path,
            output_dir=args.output,
            skip_diarization=args.no_diarize,
            speaker_count=args.speakers,
            keep_temp=args.keep_temp,
            whisper_port=args.whisper_port,
        )

        print(f"\nprocessing complete: {output_file}")

    except KeyboardInterrupt:
        print("\n\ninterrupted")
        sys.exit(1)
    except Exception as e:
        print(f"\nerror: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
