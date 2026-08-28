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
- This only does discovery, not outreach. Message drafting/sending is a
  separate step (see the productivity-content automation discussion).
