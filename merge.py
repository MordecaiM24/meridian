import json
from typing import Dict, List


def merge_nearby_diarization(
    diarization: list[dict], gap_threshold: float = 0.5
) -> list[dict]:
    """merge adjacent segments from same speaker if gap < threshold"""
    if not diarization:
        return []

    merged = []
    current = diarization[0].copy()

    for segment in diarization[1:]:
        if (
            segment["speaker"] == current["speaker"]
            and segment["start"] - current["end"] < gap_threshold
        ):
            current["end"] = segment["end"]
        else:
            merged.append(current)
            current = segment.copy()

    merged.append(current)
    return merged


def align_whisper_segments_with_speakers(
    whisper_segments: list[dict], diarization: list[dict]
) -> list[dict]:
    """align existing whisper segments with speaker labels"""
    aligned = []

    for seg in whisper_segments:
        seg_duration = seg["end"] - seg["start"]
        speaker_times = {}

        for d_seg in diarization:
            overlap_start = max(seg["start"], d_seg["start"])
            overlap_end = min(seg["end"], d_seg["end"])
            overlap = max(0, overlap_end - overlap_start)

            if overlap > 0:
                speaker = d_seg["speaker"]
                speaker_times[speaker] = speaker_times.get(speaker, 0) + overlap

        # assign to speaker with most overlap
        if speaker_times:
            best_speaker = max(speaker_times, key=speaker_times.get)
            confidence = speaker_times[best_speaker] / seg_duration
        else:
            best_speaker = "unknown"
            confidence = 0.0

        aligned.append(
            {
                "id": seg["id"],
                "speaker": best_speaker,
                "start": seg["start"],
                "end": seg["end"],
                "text": seg["text"],  # already properly formatted
                "tokens": seg.get("tokens", []),
                "confidence": confidence,
                "avg_logprob": seg.get("avg_logprob", 0),
                "no_speech_prob": seg.get("no_speech_prob", 0),
            }
        )

    return aligned


def merge_consecutive_speaker_segments(segments: list[dict]) -> list[dict]:
    """merge consecutive segments from same speaker for cleaner output"""
    if not segments:
        return []

    merged = []
    current = segments[0].copy()
    current["whisper_ids"] = [current["id"]]

    for seg in segments[1:]:
        if seg["speaker"] == current["speaker"]:
            current["end"] = seg["end"]
            current["text"] += " " + seg["text"]
            current["whisper_ids"].append(seg["id"])
            current["tokens"].extend(seg.get("tokens", []))
            current["confidence"] = (current["confidence"] + seg["confidence"]) / 2
        else:
            merged.append(current)
            current = seg.copy()
            current["whisper_ids"] = [current["id"]]

    merged.append(current)
    return merged


def find_overlaps(diarization: list[dict], min_duration: float = 0.1) -> list[dict]:
    """identify time ranges where multiple speakers overlap"""
    overlaps = []

    for i, seg1 in enumerate(diarization):
        for seg2 in diarization[i + 1 :]:
            overlap_start = max(seg1["start"], seg2["start"])
            overlap_end = min(seg1["end"], seg2["end"])

            if overlap_end - overlap_start > min_duration:
                overlaps.append(
                    {
                        "start": overlap_start,
                        "end": overlap_end,
                        "speakers": sorted(
                            list(set([seg1["speaker"], seg2["speaker"]]))
                        ),
                    }
                )

    return overlaps


def process_transcription(
    transcription: Dict,
    diarization: List[Dict],
    merge_speakers: bool = True,
) -> Dict:
    """main processing function"""

    print(f"merging {len(diarization)} diarization segments...")
    diarization = merge_nearby_diarization(diarization)
    print(f"reduced to {len(diarization)} segments")

    whisper_segments = transcription.get("segments", [])
    print(f"aligning {len(whisper_segments)} whisper segments with speakers...")
    segments = align_whisper_segments_with_speakers(whisper_segments, diarization)

    if merge_speakers:
        print("merging consecutive same-speaker segments...")
        segments = merge_consecutive_speaker_segments(segments)
        print(f"reduced to {len(segments)} speaker segments")

    overlaps = find_overlaps(diarization)
    print(f"found {len(overlaps)} overlap regions")

    speakers = sorted(
        list(set(seg["speaker"] for seg in segments if seg["speaker"] != "unknown"))
    )

    output = {
        "metadata": {
            "duration": transcription.get("duration", 0),
            "language": transcription.get("language", "unknown"),
            "original_text": transcription.get("text", ""),
        },
        "speakers": {
            speaker: {
                "label": speaker.replace("SPEAKER_", "speaker_").lower(),
                "color": None,
            }
            for speaker in speakers
        },
        "segments": segments,
        "overlaps": overlaps,
        "words": transcription.get("words", []),  # keep original words for timeline UI
    }

    # stats
    total_duration = sum(seg["end"] - seg["start"] for seg in segments)
    unknown_duration = sum(
        seg["end"] - seg["start"] for seg in segments if seg["speaker"] == "unknown"
    )

    print(f"\nsummary:")
    print(f"  speakers: {len(speakers)}")
    print(f"  segments: {len(segments)}")
    print(f"  total speaking: {total_duration:.1f}s")
    if unknown_duration > 0:
        print(
            f"  unknown speaker: {unknown_duration:.1f}s ({unknown_duration/total_duration*100:.1f}%)"
        )

    return output
