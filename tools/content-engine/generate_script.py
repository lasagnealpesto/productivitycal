#!/usr/bin/env python3
"""
Step 1 of the faceless TikTok content engine: generate a voiceover script
for a given topic using Claude.

Usage:
    python generate_script.py "why time-blocking fails for ADHD brains"
    python generate_script.py "3 signs your calendar app is fighting you" --out output/ep03

Writes <out>/script.json with:
    { topic, video_title, hook, script, post_caption }

`script` is the full spoken voiceover text (hook + body + CTA, one flowing
script meant to be read aloud in 20-45s) - this is what step 2
(generate_voiceover.py) turns into audio, and what step 3 derives captions
from. `post_caption` is the TikTok post description (with hashtags), not
spoken.
"""

import argparse
import json
import os
import sys

import anthropic

MODEL = "claude-opus-5"

SCRIPT_SCHEMA = {
    "type": "object",
    "properties": {
        "video_title": {"type": "string", "description": "Internal working title, not shown on screen"},
        "hook": {"type": "string", "description": "The first 1-2 spoken sentences, the scroll-stopper"},
        "script": {
            "type": "string",
            "description": "Full spoken voiceover script: hook + body + CTA as one flowing "
                            "text meant to be read aloud in 20-45 seconds (roughly 60-110 words). "
                            "Plain spoken language, no stage directions, no emoji, no markdown.",
        },
        "post_caption": {
            "type": "string",
            "description": "TikTok post caption/description including 3-6 relevant hashtags. "
                            "Not spoken - this goes in the post text field.",
        },
    },
    "required": ["video_title", "hook", "script", "post_caption"],
    "additionalProperties": False,
}

SYSTEM_PROMPT = """You write scripts for faceless, voiceover-only TikTok videos in the \
productivity/calendar-app niche. Style: direct-to-camera-style spoken text (no visuals \
described, just what's said), a hook in the first sentence that states a specific, \
relatable problem or a surprising claim, a short body that delivers one concrete idea \
(not generic advice), and a soft CTA at the end.

Hard rules:
- 60-110 words total for `script` - it must fit in 20-45 seconds spoken aloud.
- No emoji, no hashtags, no markdown, no stage directions, no "[pause]" markers - just \
  the words to be spoken, plain text.
- Sound like a person talking, not a blog post: short sentences, contractions, no jargon.
- One concrete idea per video, not a listicle unless the topic explicitly asks for a list.
- Never claim a specific research study or statistic you weren't given - use "a lot of \
  people" / "most calendar apps" style claims instead of fabricated numbers."""


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("topic", help="What the video is about.")
    p.add_argument("--out", default=None,
                    help="Output directory (default: output/<slugified topic>).")
    p.add_argument("--product-name", default="Endar",
                    help="App name to reference in the CTA, if relevant.")
    return p.parse_args()


def slugify(text):
    return "-".join(text.lower().split())[:40].strip("-")


def main():
    args = parse_args()
    out_dir = args.out or os.path.join("output", slugify(args.topic))
    os.makedirs(out_dir, exist_ok=True)

    client = anthropic.Anthropic()
    user_prompt = (
        f"Topic: {args.topic}\n"
        f"App to mention in the CTA (only if it fits naturally, don't force it every time): "
        f"{args.product_name}"
    )

    response = client.messages.create(
        model=MODEL,
        max_tokens=2048,
        system=SYSTEM_PROMPT,
        output_config={"effort": "medium", "format": {"type": "json_schema", "schema": SCRIPT_SCHEMA}},
        messages=[{"role": "user", "content": user_prompt}],
    )
    text = next(b.text for b in response.content if b.type == "text")
    data = json.loads(text)
    data["topic"] = args.topic

    out_path = os.path.join(out_dir, "script.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    word_count = len(data["script"].split())
    print(f"Wrote {out_path} ({word_count} words, ~{round(word_count / 2.5)}s spoken)", file=sys.stderr)
    print(data["script"], file=sys.stderr)


if __name__ == "__main__":
    main()
