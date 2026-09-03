#!/usr/bin/env python3
"""
Orchestrator: runs the full faceless-TikTok content pipeline for one topic
end to end - script (Claude) -> voiceover (ElevenLabs) -> captioned video.

Usage:
    python create_video.py "why time-blocking fails for ADHD brains"
    python create_video.py "3 signs your calendar app is fighting you" \
        --voice-id 21m00Tcm4TlvDq8ikWAM --background assets/bg_loop.mp4

Equivalent to running generate_script.py, generate_voiceover.py and
render_video.py in sequence on the same output directory. Run the three
scripts individually instead when you want to review/regenerate one step
(e.g. re-roll the script without re-paying for TTS).
"""

import argparse
import subprocess
import sys

from generate_script import slugify


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("topic")
    p.add_argument("--out", default=None)
    p.add_argument("--product-name", default="Endar")
    p.add_argument("--voice-id", default=None)
    p.add_argument("--background", default=None)
    p.add_argument("--font", default=None)
    return p.parse_args()


def run(cmd):
    print(f"$ {' '.join(cmd)}", file=sys.stderr)
    subprocess.run(cmd, check=True)


def main():
    args = parse_args()
    out_dir = args.out or f"output/{slugify(args.topic)}"

    run([sys.executable, "generate_script.py", args.topic,
         "--out", out_dir, "--product-name", args.product_name])

    voiceover_cmd = [sys.executable, "generate_voiceover.py", out_dir]
    if args.voice_id:
        voiceover_cmd += ["--voice-id", args.voice_id]
    run(voiceover_cmd)

    render_cmd = [sys.executable, "render_video.py", out_dir]
    if args.background:
        render_cmd += ["--background", args.background]
    if args.font:
        render_cmd += ["--font", args.font]
    run(render_cmd)

    print(f"Done: {out_dir}/video.mp4", file=sys.stderr)


if __name__ == "__main__":
    main()
