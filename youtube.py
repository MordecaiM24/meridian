from yt_dlp import YoutubeDL
import unicodedata
import re
import os


def to_kebab_case(name: str) -> str:
    """
    Converts a string to kebab-case.
    This involves lowercasing, replacing spaces and special characters with hyphens,
    and normalizing unicode characters.
    """
    name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode("ascii")
    name = re.sub(r"[^a-zA-Z0-9\s-]", "", name).strip().lower()
    name = re.sub(r"\s+", "-", name)
    name = re.sub(r"-+", "-", name)
    return name


def cleanup_directory_names(directory_path):
    """
    Recursively kebab-cases all filenames in the given directory.
    Renames files and subdirectories to use kebab-case naming.
    """
    if not os.path.exists(directory_path):
        return

    # Get all items in the directory
    items = os.listdir(directory_path)

    for item in items:
        item_path = os.path.join(directory_path, item)

        # Extract filename without extension for videos, keep extension
        if os.path.isfile(item_path):
            name, ext = os.path.splitext(item)
            kebab_name = to_kebab_case(name)
            new_filename = kebab_name + ext
        else:
            # For directories, just kebab case the whole name
            new_filename = to_kebab_case(item)

        new_item_path = os.path.join(directory_path, new_filename)

        # Only rename if the name actually changed
        if item != new_filename:
            # Handle potential conflicts by adding a number suffix
            counter = 1
            original_new_path = new_item_path
            while os.path.exists(new_item_path):
                if os.path.isfile(original_new_path):
                    name_part, ext_part = os.path.splitext(original_new_path)
                    new_item_path = f"{name_part}-{counter}{ext_part}"
                else:
                    new_item_path = f"{original_new_path}-{counter}"
                counter += 1

            os.rename(item_path, new_item_path)

            # If it's a directory, recursively clean it
            if os.path.isdir(new_item_path):
                cleanup_directory_names(new_item_path)


def download_youtube_video(video_url, output_path=None):
    if output_path is None:
        output_path = "temp/%(title)s.%(ext)s"

    ydl_opts = {
        "format": "bestaudio/best",
        "noplaylist": True,  # force single video behavior
        "outtmpl": output_path,
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "wav",  # container
                "preferredquality": "0",
            }
        ],
        # technically should be this by default but i'd rather not deal w/ whisper dying over a quality setting
        "postprocessor_args": ["-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le"],
    }

    # get video info first to extract title for kebab case filename
    if output_path == "temp/%(title)s.%(ext)s":
        with YoutubeDL({"quiet": True}) as ydl_info:
            info = ydl_info.extract_info(video_url, download=False)
            title = info.get("title", "video")
            kebab_title = to_kebab_case(title)
            ydl_opts["outtmpl"] = f"temp/{kebab_title}.%(ext)s"

    with YoutubeDL(ydl_opts) as ydl:
        ydl.download([video_url])


def download_youtube_playlist(
    playlist_url, output_path=None, start_index=None, end_index=None
):
    """
    Downloads a YouTube playlist with optional indexing support.

    Args:
        playlist_url: URL of the playlist
        output_path: Output path template (default uses playlist_title/index - title.ext)
        start_index: First video index to download (1-based, inclusive)
        end_index: Last video index to download (1-based, inclusive)
    """
    # get playlist info first to get the title for kebab case directory
    with YoutubeDL({"quiet": True}) as ydl_info:
        info = ydl_info.extract_info(playlist_url, download=False)
        playlist_title = info.get("title", "playlist")
        kebab_playlist_title = to_kebab_case(playlist_title)

    ydl_opts = {
        "format": "bestaudio/best",
        "outtmpl": output_path
        or f"{kebab_playlist_title}/%(playlist_index)03d - %(title)s.%(ext)s",
        "download_archive": "downloaded.txt",  # skip already-done ids
        "concurrent_fragment_downloads": 4,
        "ignoreerrors": True,  # keep going if one item borks
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "wav",
                "preferredquality": "0",
            }
        ],
        "postprocessor_args": ["-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le"],
    }

    if start_index is not None or end_index is not None:
        if start_index is not None and end_index is not None:
            ydl_opts["playlist_items"] = f"{start_index}-{end_index}"
        elif start_index is not None:
            ydl_opts["playlist_items"] = f"{start_index}-"
        elif end_index is not None:
            ydl_opts["playlist_items"] = f"1-{end_index}"

    with YoutubeDL(ydl_opts) as ydl:
        ydl.download([playlist_url])

    # clean up filenames in the playlist directory after download
    cleanup_directory_names(kebab_playlist_title)
