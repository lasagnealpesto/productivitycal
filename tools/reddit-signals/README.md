# Reddit demand-signal discovery

Finds people already expressing a need related to productivity/calendar
apps on Reddit — someone asking for a calendar app recommendation,
complaining they can't stick to a routine, asking for a Notion alternative,
etc. This is fundamentally different from the TikTok creator discovery in
`tools/ugc-discovery/`: there you're looking for influencers to hire; here
you're looking for individual prospects with an explicit, timely need.

Uses the official Reddit API (PRAW) — read-only, no scraping, no ban risk.

## Why this script does not send anything

Reddit bans mass-DM/self-promo accounts fast, and a genuinely-written human
reply converts far better than a canned one anyway. This script only finds
and exports candidate threads/comments. **Review the CSV and reply
manually** — as a real person joining the conversation, only where the app
is an honest fit. Never bulk-DM from this list; even a handful of copy-paste
DMs a day looks and reads like spam.

## Setup

```bash
cd tools/reddit-signals
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

Create a Reddit API app (free) at https://www.reddit.com/prefs/apps →
"create app" → type **script**. Then:

```bash
export REDDIT_CLIENT_ID=the_id_under_the_app_name
export REDDIT_CLIENT_SECRET=the_secret
export REDDIT_USER_AGENT="gtm-signal-finder by u/yourusername"
```

## Run

```bash
python find_reddit_signals.py
```

Defaults: searches subreddits like r/productivity, r/ADHD, r/GetDisciplined,
r/notionso, r/androidapps for phrases like "calendar app", "planner app",
"time blocking", "adhd planner" — both in submissions (via Reddit search)
and in each subreddit's most recent comments (Reddit search doesn't index
comment text, so recent comments are scanned directly instead).

```bash
python find_reddit_signals.py \
  --subreddits productivity ADHD notionso \
  --keywords "calendar app" "planner app" "notion alternative" \
  --time-filter month \
  --output signals_batch1.csv
```

- `--min-account-age-days` (default 7) filters out throwaway/likely-bot
  accounts.
- `--comment-scan-limit` controls how many of each subreddit's newest
  comments get pulled for keyword matching — raise it to look further back,
  at the cost of a slower run.
- Run it periodically (e.g. daily/every few days via cron) rather than once
  — it's a rolling feed of fresh demand signals, not a one-time archive dump.

## Output columns

`author, subreddit, type (submission/comment), matched_keyword, snippet,
permalink, score, created_utc, account_age_days, comment_karma,
link_karma, status`

`status` starts as `new` — same convention as the other discovery tools, so
you can track it through a shared prospect tracker (`new` → `replied` →
`interested` → `installed`/`no fit`).
