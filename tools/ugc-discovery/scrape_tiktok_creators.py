#!/usr/bin/env python3
"""
TikTok UGC creator discovery for productivity/calendar-app content.

Searches a set of hashtags via the Apify "clockworks/tiktok-scraper" actor,
aggregates results per author, filters to cheap-to-hire nano/micro creators
with real engagement, and writes a ranked CSV.

Setup:
    pip install -r requirements.txt
    export APIFY_API_TOKEN=your_apify_token   # https://console.apify.com/account/integrations

Usage:
    python scrape_tiktok_creators.py
    python scrape_tiktok_creators.py --hashtags productivitytips plannertok --min-followers 1000 --max-followers 30000
"""

import argparse
import csv
import os
import re
import sys
from collections import defaultdict
from statistics import mean

from apify_client import ApifyClient

ACTOR_ID = "clockworks/tiktok-scraper"

# English-language productivity / planner / calendar-app niche. Creators
# posting in these tags are the most likely to say yes to a calendar-app UGC brief.
DEFAULT_HASHTAGS = [
    "productivitytips",
    "productivityhacks",
    "productivityapp",
    "studytok",
    "plannertok",
    "dailyplanner",
    "digitalplanner",
    "notionapp",
    "timemanagement",
    "organizationtips",
    "studymotivation",
    "lifeorganization",
    "todolist",
    "calendarhacks",
]

EMAIL_RE = re.compile(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+")


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--hashtags", nargs="+", default=DEFAULT_HASHTAGS,
                    help="TikTok hashtags to search (without #).")
    p.add_argument("--results-per-hashtag", type=int, default=100,
                    help="How many videos to pull per hashtag (controls Apify cost).")
    p.add_argument("--min-followers", type=int, default=1000,
                    help="Minimum follower count (nano creator floor).")
    p.add_argument("--max-followers", type=int, default=30000,
                    help="Maximum follower count (stay cheap: micro creator ceiling).")
    p.add_argument("--min-engagement", type=float, default=0.04,
                    help="Minimum avg engagement rate (likes+comments+shares)/views, e.g. 0.04 = 4%%.")
    p.add_argument("--min-videos-matched", type=int, default=1,
                    help="Minimum number of niche videos an author must have to be kept.")
    p.add_argument("--output", default="creators.csv", help="Output CSV path.")
    return p.parse_args()


def fetch_videos(client, hashtags, results_per_hashtag):
    run_input = {
        "hashtags": hashtags,
        "resultsPerPage": results_per_hashtag,
        "shouldDownloadCovers": False,
        "shouldDownloadVideos": False,
        "shouldDownloadSubtitles": False,
        "shouldDownloadSlideshowImages": False,
    }
    print(f"Running Apify actor {ACTOR_ID} for hashtags: {', '.join(hashtags)} ...", file=sys.stderr)
    run = client.actor(ACTOR_ID).call(run_input=run_input)
    dataset_id = run["defaultDatasetId"]
    return list(client.dataset(dataset_id).iterate_items())


def aggregate_by_author(items):
    authors = defaultdict(lambda: {
        "followers": 0, "following": 0, "verified": False, "bio": "",
        "videos": [], "matched_hashtags": set(),
    })

    for item in items:
        meta = item.get("authorMeta") or {}
        username = meta.get("name")
        if not username:
            continue

        plays = item.get("playCount") or 0
        engagement = 0.0
        if plays:
            engagement = (
                (item.get("diggCount") or 0)
                + (item.get("commentCount") or 0)
                + (item.get("shareCount") or 0)
            ) / plays

        a = authors[username]
        a["followers"] = meta.get("fans") or a["followers"]
        a["following"] = meta.get("following") or a["following"]
        a["verified"] = meta.get("verified") or a["verified"]
        a["bio"] = meta.get("signature") or a["bio"]
        a["videos"].append({
            "url": item.get("webVideoUrl"),
            "plays": plays,
            "engagement": engagement,
        })
        for tag in item.get("hashtags") or []:
            name = tag.get("name") if isinstance(tag, dict) else tag
            if name:
                a["matched_hashtags"].add(name)

    return authors


def build_rows(authors, args):
    rows = []
    for username, a in authors.items():
        followers = a["followers"] or 0
        if not (args.min_followers <= followers <= args.max_followers):
            continue
        if len(a["videos"]) < args.min_videos_matched:
            continue

        avg_engagement = mean(v["engagement"] for v in a["videos"])
        if avg_engagement < args.min_engagement:
            continue

        avg_views = mean(v["plays"] for v in a["videos"])
        email_match = EMAIL_RE.search(a["bio"] or "")
        tier = "nano (1k-10k)" if followers < 10000 else "micro (10k-30k)"

        rows.append({
            "username": username,
            "profile_url": f"https://www.tiktok.com/@{username}",
            "tier": tier,
            "followers": followers,
            "following": a["following"],
            "verified": a["verified"],
            "email": email_match.group(0) if email_match else "",
            "bio": (a["bio"] or "").replace("\n", " ").strip(),
            "avg_views": round(avg_views),
            "avg_engagement_rate": round(avg_engagement, 4),
            "videos_matched": len(a["videos"]),
            "matched_hashtags": ", ".join(sorted(a["matched_hashtags"])),
            "sample_video_url": a["videos"][0]["url"],
            "status": "new",
        })

    rows.sort(key=lambda r: r["avg_engagement_rate"], reverse=True)
    return rows


def write_csv(rows, output_path):
    if not rows:
        print("No creators matched the filters. Try widening --min-followers/--max-followers "
              "or lowering --min-engagement.", file=sys.stderr)
        return

    fieldnames = list(rows[0].keys())
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} creators to {output_path}", file=sys.stderr)


def main():
    args = parse_args()
    token = os.environ.get("APIFY_API_TOKEN")
    if not token:
        sys.exit("Set APIFY_API_TOKEN in your environment first "
                  "(https://console.apify.com/account/integrations).")

    client = ApifyClient(token)
    items = fetch_videos(client, args.hashtags, args.results_per_hashtag)
    authors = aggregate_by_author(items)
    rows = build_rows(authors, args)
    write_csv(rows, args.output)


if __name__ == "__main__":
    main()
