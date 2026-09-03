#!/usr/bin/env python3
"""
Step 2 of the faceless TikTok content engine: turn script.json into a
voiceover audio file, with word-level timestamps for caption sync.

Uses the ElevenLabs text-to-speech API (with-timestamps endpoint).

Setup:
    export ELEVENLABS_API_KEY=your_key
    (get a voice_id from https://elevenlabs.io/app/voice-library, or use
     one of your own cloned/library voices)

Usage:
    python generate_voiceover.py output/why-time-blocking-fails
    python generate_voiceover.py output/why-time-blocking-fails --voice-id 21m00Tcm4TlvDq8ikWAM
"""

import argparse
import base64
import json
import os
import sys

import requests

API_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}/with-timestamps"
DEFAULT_MODEL_ID = "eleven_turbo_v2_5"


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("dir", help="Video output directory containing script.json "
                                "(from generate_script.py).")
    p.add_argument("--voice-id", default=os.environ.get("ELEVENLABS_VOICE_ID"),
                    help="ElevenLabs voice ID (or set ELEVENLABS_VOICE_ID).")
    p.add_argument("--model-id", default=DEFAULT_MODEL_ID)
    p.add_argument("--stability", type=float, default=0.5)
    p.add_argument("--similarity-boost", type=float, default=0.75)
    return p.parse_args()


def main():
    args = parse_args()
    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        sys.exit("Set ELEVENLABS_API_KEY.")
    if not args.voice_id:
        sys.exit("Pass --voice-id or set ELEVENLABS_VOICE_ID (pick one at "
                  "https://elevenlabs.io/app/voice-library).")

    script_path = os.path.join(args.dir, "script.json")
    with open(script_path, encoding="utf-8") as f:
        script_data = json.load(f)

    text = script_data["script"]
    response = requests.post(
        API_URL.format(voice_id=args.voice_id),
        headers={"xi-api-key": api_key, "Content-Type": "application/json"},
        json={
            "text": text,
            "model_id": args.model_id,
            "voice_settings": {
                "stability": args.stability,
                "similarity_boost": args.similarity_boost,
            },
        },
        timeout=120,
    )
    if response.status_code != 200:
        sys.exit(f"ElevenLabs API error {response.status_code}: {response.text}")

    payload = response.json()
    audio_bytes = base64.b64decode(payload["audio_base64"])

    audio_path = os.path.join(args.dir, "voiceover.mp3")
    with open(audio_path, "wb") as f:
        f.write(audio_bytes)

    alignment_path = os.path.join(args.dir, "alignment.json")
    with open(alignment_path, "w", encoding="utf-8") as f:
        json.dump(payload["alignment"], f)

    print(f"Wrote {audio_path} and {alignment_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
