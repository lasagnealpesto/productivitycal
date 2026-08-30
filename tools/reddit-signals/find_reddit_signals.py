#!/usr/bin/env python3
"""
Reddit demand-signal discovery for a productivity/calendar app.

Unlike TikTok creator discovery (which finds influencers to hire), this finds
*people already expressing a need* - posts/comments asking for a calendar or
planner app, complaining about time management, etc - in the subreddits where
that conversation happens. It uses the official Reddit API (PRAW), not
scraping, so there's no ban/ToS risk on the read side.

This is a discovery tool only. Reddit bans mass-DM/spam accounts fast -
the intended use is: review the CSV, then reply genuinely (as a human) on
threads that are a real fit, or occasionally DM only when it's clearly
welcome. Never auto-post or auto-DM from this script.

Setup:
    pip install -r requirements.txt

    Create a Reddit "script" app at https://www.reddit.com/prefs/apps
    (type: script), then:
        export REDDIT_CLIENT_ID=...
        export REDDIT_CLIENT_SECRET=...
        export REDDIT_USER_AGENT="gtm-signal-finder by u/yourusername"

Usage:
    python find_reddit_signals.py
    python find_reddit_signals.py --subreddits productivity ADHD notion \
        --keywords "calendar app" "planner app" --time-filter week
"""

import argparse
import csv
import os
import re
import sys
from datetime import datetime, timezone

import praw

DEFAULT_SUBREDDITS = [
    "productivity",
    "GetDisciplined",
    "ADHD",
    "PKMS",
    "notionso",
    "androidapps",
    "iosapps",
    "timemanagement",
    "digitalplanner",
    "studytips",
]

DEFAULT_KEYWORDS = [
    "calendar app",
    "planner app",
    "productivity app",
    "time blocking",
    "task management app",
    "adhd planner",
    "digital planner recommendation",
    "notion alternative",
    "app to organize my day",
    "app to stay on track",
]


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--subreddits", nargs="+", default=DEFAULT_SUBREDDITS)
    p.add_argument("--keywords", nargs="+", default=DEFAULT_KEYWORDS,
                    help="Phrases to match in submission title/body and recent comments.")
    p.add_argument("--time-filter", default="week",
                    choices=["hour", "day", "week", "month", "year", "all"],
                    help="How far back to search submissions (Reddit search API bucket).")
    p.add_argument("--submission-limit", type=int, default=25,
                    help="Max submissions to fetch per keyword per subreddit.")
    p.add_argument("--comment-scan-limit", type=int, default=200,
                    help="How many of each subreddit's most recent comments to scan for "
                         "keyword matches (Reddit search doesn't index comment text).")
    p.add_argument("--min-account-age-days", type=int, default=7,
                    help="Skip authors newer than this (cuts obvious throwaway/bot noise).")
    p.add_argument("--output", default="reddit_signals.csv")
    return p.parse_args()


def build_keyword_regex(keywords):
    pattern = "|".join(re.escape(k) for k in keywords)
    return re.compile(pattern, re.IGNORECASE)


def account_age_days(created_utc):
    created = datetime.fromtimestamp(created_utc, tz=timezone.utc)
    return (datetime.now(timezone.utc) - created).days


def snippet(text, keyword, width=160):
    text = " ".join((text or "").split())
    idx = text.lower().find(keyword.lower())
    if idx == -1:
        return text[:width]
    start = max(0, idx - width // 2)
    return text[start:start + width]


def author_info(redditor, min_age_days):
    """Returns (account_age_days, comment_karma, link_karma) or None if the
    author should be skipped (deleted/suspended/too new)."""
    try:
        age = account_age_days(redditor.created_utc)
    except Exception:
        return None
    if age < min_age_days:
        return None
    return age, getattr(redditor, "comment_karma", 0), getattr(redditor, "link_karma", 0)


def scan_submissions(reddit, subreddits, keywords, time_filter, limit, min_age_days, rows, seen):
    for sub_name in subreddits:
        subreddit = reddit.subreddit(sub_name)
        for keyword in keywords:
            print(f"Searching r/{sub_name} for '{keyword}'...", file=sys.stderr)
            try:
                results = subreddit.search(f'"{keyword}"', sort="new", time_filter=time_filter, limit=limit)
                for post in results:
                    key = ("submission", post.id)
                    if key in seen or post.author is None:
                        continue
                    seen.add(key)
                    info = author_info(post.author, min_age_days)
                    if info is None:
                        continue
                    age, comment_karma, link_karma = info
                    rows.append({
                        "author": str(post.author),
                        "subreddit": sub_name,
                        "type": "submission",
                        "matched_keyword": keyword,
                        "snippet": snippet(f"{post.title} {post.selftext}", keyword),
                        "permalink": f"https://reddit.com{post.permalink}",
                        "score": post.score,
                        "created_utc": datetime.fromtimestamp(post.created_utc, tz=timezone.utc).isoformat(),
                        "account_age_days": age,
                        "comment_karma": comment_karma,
                        "link_karma": link_karma,
                        "status": "new",
                    })
            except Exception as e:
                print(f"  skipped r/{sub_name} search for {keyword!r}: {e}", file=sys.stderr)


def scan_recent_comments(reddit, subreddits, keyword_re, comment_scan_limit, min_age_days, rows, seen):
    for sub_name in subreddits:
        print(f"Scanning recent comments in r/{sub_name}...", file=sys.stderr)
        subreddit = reddit.subreddit(sub_name)
        try:
            for comment in subreddit.comments(limit=comment_scan_limit):
                if comment.author is None:
                    continue
                match = keyword_re.search(comment.body or "")
                if not match:
                    continue
                key = ("comment", comment.id)
                if key in seen:
                    continue
                seen.add(key)
                info = author_info(comment.author, min_age_days)
                if info is None:
                    continue
                age, comment_karma, link_karma = info
                rows.append({
                    "author": str(comment.author),
                    "subreddit": sub_name,
                    "type": "comment",
                    "matched_keyword": match.group(0),
                    "snippet": snippet(comment.body, match.group(0)),
                    "permalink": f"https://reddit.com{comment.permalink}",
                    "score": comment.score,
                    "created_utc": datetime.fromtimestamp(comment.created_utc, tz=timezone.utc).isoformat(),
                    "account_age_days": age,
                    "comment_karma": comment_karma,
                    "link_karma": link_karma,
                    "status": "new",
                })
        except Exception as e:
            print(f"  skipped r/{sub_name} comment scan: {e}", file=sys.stderr)


def main():
    args = parse_args()

    client_id = os.environ.get("REDDIT_CLIENT_ID")
    client_secret = os.environ.get("REDDIT_CLIENT_SECRET")
    user_agent = os.environ.get("REDDIT_USER_AGENT")
    if not all([client_id, client_secret, user_agent]):
        sys.exit("Set REDDIT_CLIENT_ID, REDDIT_CLIENT_SECRET and REDDIT_USER_AGENT "
                  "(create a 'script' app at https://www.reddit.com/prefs/apps).")

    reddit = praw.Reddit(client_id=client_id, client_secret=client_secret, user_agent=user_agent)
    reddit.read_only = True

    rows = []
    seen = set()
    keyword_re = build_keyword_regex(args.keywords)

    scan_submissions(reddit, args.subreddits, args.keywords, args.time_filter,
                      args.submission_limit, args.min_account_age_days, rows, seen)
    scan_recent_comments(reddit, args.subreddits, keyword_re,
                          args.comment_scan_limit, args.min_account_age_days, rows, seen)

    rows.sort(key=lambda r: r["created_utc"], reverse=True)

    if not rows:
        print("No matches found. Try a broader --time-filter or more subreddits/keywords.", file=sys.stderr)
        return

    fieldnames = list(rows[0].keys())
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} signals to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
