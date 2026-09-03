# Faceless TikTok content engine

Generates a voiceover-only, captioned, vertical (1080x1920) video from a
topic in three steps: **script (Claude) → voiceover (ElevenLabs) →
rendered video with animated captions (MoviePy)**. No face, no filming —
this is the "faceless account" content pipeline for the productivity/
calendar-app niche.

## Setup

```bash
cd tools/content-engine
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

Requires:
- `ANTHROPIC_API_KEY` (or `ant auth login`) for script generation.
- `ELEVENLABS_API_KEY` + a voice ID for the voiceover — get a key at
  https://elevenlabs.io, then pick a voice at
  https://elevenlabs.io/app/voice-library and copy its ID (or clone your
  own). Set `ELEVENLABS_VOICE_ID` or pass `--voice-id` each run.
- `ffmpeg` — you don't need to install it separately: `imageio-ffmpeg` (in
  requirements.txt) bundles a static binary that MoviePy uses automatically.
- A bold `.ttf` font for captions. The renderer auto-detects a system font
  (Liberation/DejaVu on Linux, Arial on macOS/Windows) if present; for a
  nicer look, download a free bold font (e.g. Inter or Montserrat Bold from
  Google Fonts) into `assets/` and pass `--font assets/YourFont-Bold.ttf`.

## Run (one topic, end to end)

```bash
export ANTHROPIC_API_KEY=...
export ELEVENLABS_API_KEY=...
export ELEVENLABS_VOICE_ID=...

python create_video.py "why time-blocking fails for ADHD brains"
```

Writes to `output/why-time-blocking-fails-for-adhd-brains/`:
- `script.json` — spoken script + TikTok post caption/hashtags
- `voiceover.mp3` + `alignment.json` — audio + word-level timestamps
- `video.mp4` — the finished 1080x1920 captioned video

## Run step by step

Useful when you want to review/re-roll one stage without redoing (and
repaying for) the others:

```bash
python generate_script.py "3 signs your calendar app is fighting you" --out output/ep03
# review/edit output/ep03/script.json by hand if you want, then:
python generate_voiceover.py output/ep03 --voice-id 21m00Tcm4TlvDq8ikWAM
python render_video.py output/ep03 --background assets/bg_loop.mp4 --font assets/Inter-Bold.ttf
```

## What the caption style looks like

Captions are grouped into short on-screen chunks (~26 characters), shown
word-by-word with the currently-spoken word highlighted (default: white
text, yellow highlight, black outline for legibility over any background),
positioned at ~68% down the frame — the standard bold-caption TikTok style,
synced to speech via ElevenLabs' character-level timestamps. Tunable via
`--caption-color`, `--highlight-color`, `--font-size`.

## Background

Default is a plain dark background (pure voiceover + captions — works fine
on its own, this style is common and doesn't hurt watch time). Pass
`--background path/to/clip.mp4` or `--background path/to/image.png` to use
your own loop/B-roll/screen-recording instead — it's resized to fill the
frame height and looped if shorter than the voiceover.

## Posting

This engine stops at a finished .mp4 + a suggested caption in `script.json`
(`post_caption`). Uploading to TikTok/Reels/Shorts isn't automated here —
TikTok's official Content Posting API exists but requires app review; for a
single faceless account, manual upload (or a scheduler like Metricool/
Later that supports TikTok) is the practical choice. If you want the
Content Posting API wired in once you have more than one account/video a
day to justify it, that's a separate follow-up.

## Cost per video (rough)

- Script: a few cents (one Claude call, short output).
- Voiceover: ElevenLabs charges per character — a 60-110 word script is
  roughly 350-650 characters, well within any paid tier's per-video cost
  (check your plan's per-character rate).
- Render: free (local compute).
