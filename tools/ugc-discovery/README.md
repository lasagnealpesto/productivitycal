# UGC creator discovery (TikTok)

Finds cheap, real-engagement nano/micro TikTok creators (1k-30k followers,
English-language) in the productivity/planner/calendar-app niche, for UGC
outreach on the calendar app.

## Setup

```bash
cd tools/ugc-discovery
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

Get a free Apify account and API token at
https://console.apify.com/account/integrations, then:

```bash
export APIFY_API_TOKEN=your_token_here
```

## Run

```bash
python scrape_tiktok_creators.py
```

Defaults: searches `#productivitytips #plannertok #digitalplanner` etc.
(see `DEFAULT_HASHTAGS` in the script), keeps authors with 1,000-30,000
followers and >=4% average engagement rate, writes `creators.csv` sorted by
engagement (best/cheapest-per-view first).

Useful overrides:

```bash
python scrape_tiktok_creators.py \
  --hashtags productivitytips plannertok notionapp \
  --min-followers 1000 --max-followers 15000 \
  --min-engagement 0.06 \
  --output creators_batch1.csv
```

- `--results-per-hashtag` controls how many videos are pulled per hashtag —
  the main lever on Apify usage cost. Start at 50-100 per hashtag.
- Engagement rate = (likes + comments + shares) / views, averaged across the
  creator's matched videos. It's the main proxy for "real audience, not
  bought followers" and correlates with willingness to do UGC for low pay
  or free-product deals.

## Output columns

`username, profile_url, tier (nano/micro), followers, following, verified,
email (parsed from bio if present), bio, avg_views, avg_engagement_rate,
videos_matched, matched_hashtags, sample_video_url, status`

`status` starts as `new` — use it to track outreach progress
(`new` -> `contacted` -> `negotiating` -> `booked` -> `delivered`) if you
import the CSV into Airtable/Sheets later.

## Notes

- The actor used is `clockworks/tiktok-scraper` on the Apify store. If its
  input/output schema changes, check the actor page on Apify console and
  adjust `run_input` / `authorMeta` field names in the script accordingly.
- No email in bio is normal — most creators expect first contact via TikTok
  DM or a comment, not email. Treat `email` as a bonus fast-path, not the
  primary channel.
- This only does discovery, not sending. Outreach drafting is a separate
  step, below.

## Outreach drafts (`draft_outreach_messages.py`)

Takes the CSV from discovery and drafts one personalized outreach message
per creator with Claude (referencing their actual niche/bio, never a
generic opener). It only writes drafts — nothing is sent automatically.

```bash
export ANTHROPIC_API_KEY=your_key   # or `ant auth login`
python draft_outreach_messages.py \
  --input creators.csv \
  --product-name "Endar" \
  --offer "3 months free Premium + a $50-100 flat fee depending on your views" \
  --ask "one organic 15-30s TikTok showing how you'd actually use a productivity/calendar app in your daily routine" \
  --cta "reply and I'll send over the full brief" \
  --limit 20
```

- Only drafts for rows with `status == new` by default (`--only-status ''`
  to redo everyone). After drafting, `status` becomes `drafted` in the
  output file.
- If a creator has an `email` (parsed from their bio), the draft is an
  email with subject line; otherwise it's a short DM-length message for
  you to paste manually on TikTok (there's no public API for sending
  TikTok DMs, so that step stays manual/semi-manual).
- `--limit` caps how many creators get drafted in one run — use it to
  control API cost while you're tuning the offer/tone, then run without it
  once the drafts read well.
- Writes `creators_with_drafts.csv` (`channel`, `email_subject`, `message`
  columns added) — review every draft before sending, they're a starting
  point, not a guaranteed-good message.
