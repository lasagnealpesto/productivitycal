#!/usr/bin/env python3
"""
Step 3 of the faceless TikTok content engine: render the final 1080x1920
video from voiceover.mp3 + alignment.json, with animated bold captions
synced to the speech (the standard "faceless TikTok" caption style).

Usage:
    python render_video.py output/why-time-blocking-fails
    python render_video.py output/why-time-blocking-fails \
        --background assets/bg_loop.mp4 --font assets/Inter-Bold.ttf

With no --background, renders on a plain dark background. Captions are
grouped into short on-screen chunks (not full sentences) with a quick
pop-in animation, matching common TikTok caption pacing.
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from moviepy import (
    AudioFileClip,
    ColorClip,
    CompositeVideoClip,
    ImageClip,
    VideoFileClip,
    vfx,
)

WIDTH, HEIGHT = 1080, 1920
CAPTION_MAX_CHARS = 26
POP_DURATION = 0.12

FALLBACK_FONT_PATHS = [
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "C:\\Windows\\Fonts\\arialbd.ttf",
]


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("dir", help="Video output directory (from generate_script.py / "
                                "generate_voiceover.py).")
    p.add_argument("--background", default=None,
                    help="Path to a background video or image to loop under the "
                         "captions. Omit for a plain dark background.")
    p.add_argument("--font", default=None,
                    help="Path to a .ttf/.otf font for captions. Auto-detects a "
                         "system font if omitted.")
    p.add_argument("--caption-color", default="#FFFFFF")
    p.add_argument("--highlight-color", default="#FFD400",
                    help="Color for the currently-spoken word within each caption chunk.")
    p.add_argument("--font-size", type=int, default=72)
    p.add_argument("--output", default=None, help="Output mp4 path (default: <dir>/video.mp4).")
    return p.parse_args()


def resolve_font(font_arg, size):
    candidates = [font_arg] if font_arg else []
    candidates += FALLBACK_FONT_PATHS
    for path in candidates:
        if path and os.path.exists(path):
            return ImageFont.truetype(path, size)
    print("WARNING: no .ttf font found, falling back to PIL's tiny default font. "
          "Pass --font path/to/font.ttf for readable captions.", file=sys.stderr)
    return ImageFont.load_default()


def words_from_alignment(alignment):
    """Turn ElevenLabs character-level alignment into a word list:
    [{"word": str, "start": float, "end": float}, ...]"""
    chars = alignment["characters"]
    starts = alignment["character_start_times_seconds"]
    ends = alignment["character_end_times_seconds"]

    words = []
    current, w_start = "", None
    for ch, s, e in zip(chars, starts, ends):
        if ch.isspace():
            if current:
                words.append({"word": current, "start": w_start, "end": prev_end})
                current, w_start = "", None
            continue
        if w_start is None:
            w_start = s
        current += ch
        prev_end = e
    if current:
        words.append({"word": current, "start": w_start, "end": prev_end})
    return words


def group_into_chunks(words, max_chars=CAPTION_MAX_CHARS):
    """Group consecutive words into caption chunks under a character budget,
    keeping each word's own timing for the pop-in animation."""
    chunks, current = [], []
    length = 0
    for w in words:
        add_len = len(w["word"]) + (1 if current else 0)
        if current and length + add_len > max_chars:
            chunks.append(current)
            current, length = [], 0
            add_len = len(w["word"])
        current.append(w)
        length += add_len
    if current:
        chunks.append(current)
    return chunks


def render_caption_image(chunk, font, active_index, caption_color, highlight_color):
    """Renders one caption chunk as an RGBA PNG (transparent background), with
    the word at active_index in the highlight color - a lightweight karaoke
    effect without re-rendering per character."""
    words = [w["word"] for w in chunk]
    dummy = Image.new("RGBA", (10, 10))
    draw = ImageDraw.Draw(dummy)

    space_w = draw.textlength(" ", font=font)
    widths = [draw.textlength(w, font=font) for w in words]
    total_w = int(sum(widths) + space_w * (len(words) - 1)) + 40
    bbox = font.getbbox("Ay")
    line_h = (bbox[3] - bbox[1]) + 40

    img = Image.new("RGBA", (total_w, line_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    x = 20
    for i, (word, w) in enumerate(zip(words, widths)):
        color = highlight_color if i == active_index else caption_color
        # subtle outline for legibility over any background
        for dx, dy in [(-2, 0), (2, 0), (0, -2), (0, 2)]:
            draw.text((x + dx, 20 + dy), word, font=font, fill=(0, 0, 0, 200))
        draw.text((x, 20), word, font=font, fill=color)
        x += w + space_w

    return np.array(img)


def build_background(args, duration):
    if not args.background:
        return ColorClip((WIDTH, HEIGHT), color=(15, 15, 20), duration=duration)

    ext = os.path.splitext(args.background)[1].lower()
    if ext in (".mp4", ".mov", ".m4v", ".webm"):
        clip = VideoFileClip(args.background)
        if clip.duration < duration:
            clip = clip.with_effects([vfx.Loop(duration=duration)])
        clip = clip.subclipped(0, duration)
    else:
        clip = ImageClip(args.background).with_duration(duration)

    return clip.resized(height=HEIGHT).with_position("center")


def main():
    args = parse_args()

    with open(os.path.join(args.dir, "alignment.json"), encoding="utf-8") as f:
        alignment = json.load(f)

    audio_path = os.path.join(args.dir, "voiceover.mp3")
    audio = AudioFileClip(audio_path)
    duration = audio.duration

    font = resolve_font(args.font, args.font_size)
    words = words_from_alignment(alignment)
    chunks = group_into_chunks(words)

    background = build_background(args, duration)

    caption_clips = []
    for chunk in chunks:
        chunk_start = chunk[0]["start"]
        chunk_end = chunk[-1]["end"]
        for i, word in enumerate(chunk):
            frame = render_caption_image(chunk, font, i, args.caption_color, args.highlight_color)
            word_duration = max(word["end"] - word["start"], 0.05)
            clip = (
                ImageClip(frame)
                .with_start(word["start"])
                .with_duration(word_duration)
                .with_position(("center", int(HEIGHT * 0.68)))
                .with_effects([vfx.FadeIn(min(POP_DURATION, word_duration / 2))])
            )
            caption_clips.append(clip)

    video = CompositeVideoClip([background, *caption_clips], size=(WIDTH, HEIGHT)).with_audio(audio)

    output_path = args.output or os.path.join(args.dir, "video.mp4")
    video.write_videofile(output_path, fps=30, codec="libx264", audio_codec="aac", threads=4)
    print(f"Wrote {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
