#!/usr/bin/env python3
"""
Draft personalized outreach messages for creators found by
scrape_tiktok_creators.py, using Claude.

Reads creators.csv (or any CSV with the same columns), drafts one message
per creator (email subject+body if an email was found in their bio,
otherwise a short DM-length message you send manually on TikTok), and
writes a new CSV with the drafts attached. Nothing is sent automatically -
review the drafts, then send by hand or via your outreach tool.

Setup:
    pip install -r requirements.txt
    export ANTHROPIC_API_KEY=your_key   # or `ant auth login`

Usage:
    python draft_outreach_messages.py
    python draft_outreach_messages.py --input creators.csv --output creators_with_drafts.csv \
        --product-name "Endar" --offer "3 months free Premium + $75 flat fee" \
        --cta "reply here if you're interested and I'll send the brief"
"""

import argparse
import csv
import json
import sys
import time

import anthropic

MODEL = "claude-opus-5"

DRAFT_SCHEMA = {
    "type": "object",
    "properties": {
        "email_subject": {
            "type": "string",
            "description": "Short subject line, empty string if channel is dm",
        },
        "message": {
            "type": "string",
            "description": "The outreach message body, ready to send as-is",
        },
    },
    "required": ["email_subject", "message"],
    "additionalProperties": False,
}

SYSTEM_PROMPT = """You write short, non-generic creator outreach messages for a UGC \
(user-generated content) sourcing campaign. You will be given one TikTok creator's \
public profile data and a brief for what the brand is offering. Write ONE outreach \
message for that specific creator.

Rules:
- Reference something concrete and specific about their content (their niche, a \
  video topic, their bio) - never a generic "I love your content!" opener.
- Keep it short: 60-100 words for email, 40-70 words for a DM.
- Casual, human, peer-to-peer tone - not corporate, not salesy, no exclamation-point \
  spam, no emoji overload (at most one, only if it fits naturally).
- Be upfront about the offer (product + compensation) in the first two sentences - \
  do not bury it.
- End with the exact call to action given in the brief, adapted naturally into the \
  message.
- If email_subject is requested, make it specific and non-spammy (no ALL CAPS, no \
  "Collab opportunity!!!").
- Do not invent facts about the creator you were not given."""


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", default="creators.csv", help="CSV from scrape_tiktok_creators.py")
    p.add_argument("--output", default="creators_with_drafts.csv")
    p.add_argument("--product-name", default="our productivity calendar app",
                    help="Name of the app/product being pitched.")
    p.add_argument("--offer", default="free lifetime Premium + a $50-100 flat fee "
                                       "depending on your typical views",
                    help="What you're offering the creator, in plain language.")
    p.add_argument("--ask", default="one organic 15-30s TikTok showing how you'd "
                                     "actually use a productivity/calendar app in your "
                                     "daily routine",
                    help="What content you want from them.")
    p.add_argument("--cta", default="reply and I'll send over the full brief",
                    help="The call to action to close the message with.")
    p.add_argument("--only-status", default="new",
                    help="Only draft for rows with this status column value. "
                         "Pass '' to process all rows regardless of status.")
    p.add_argument("--limit", type=int, default=0,
                    help="Max number of creators to draft for (0 = no limit). "
                         "Useful to control API cost on a first run.")
    return p.parse_args()


def build_user_prompt(row, args):
    channel = "email" if row.get("email") else "dm"
    brief = (
        f"Product: {args.product_name}\n"
        f"Offer: {args.offer}\n"
        f"What we want: {args.ask}\n"
        f"Call to action: {args.cta}\n"
        f"Channel: {'email' if channel == 'email' else 'TikTok DM (no subject line)'}"
    )
    profile = (
        f"Username: @{row.get('username')}\n"
        f"Follower tier: {row.get('tier')}\n"
        f"Bio: {row.get('bio')}\n"
        f"Matched hashtags/niche: {row.get('matched_hashtags')}\n"
        f"Avg engagement rate: {row.get('avg_engagement_rate')}\n"
    )
    return f"{brief}\n\nCreator profile:\n{profile}"


def draft_message(client, row, args):
    channel = "email" if row.get("email") else "dm"
    response = client.messages.create(
        model=MODEL,
        max_tokens=1024,
        system=SYSTEM_PROMPT,
        output_config={"effort": "low", "format": {"type": "json_schema", "schema": DRAFT_SCHEMA}},
        messages=[{"role": "user", "content": build_user_prompt(row, args)}],
    )
    text = next(b.text for b in response.content if b.type == "text")
    data = json.loads(text)
    return channel, data["email_subject"], data["message"]


def main():
    args = parse_args()
    client = anthropic.Anthropic()

    with open(args.input, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    if args.only_status:
        targets = [r for r in rows if r.get("status") == args.only_status]
    else:
        targets = rows

    if args.limit:
        targets = targets[: args.limit]

    if not targets:
        sys.exit(f"No rows to draft for (status filter: {args.only_status!r}). Nothing to do.")

    print(f"Drafting outreach for {len(targets)} creator(s)...", file=sys.stderr)

    for i, row in enumerate(targets, 1):
        try:
            channel, subject, message = draft_message(client, row, args)
        except anthropic.APIStatusError as e:
            print(f"[{i}/{len(targets)}] @{row.get('username')}: API error {e.status_code}, skipping", file=sys.stderr)
            continue
        row["channel"] = channel
        row["email_subject"] = subject
        row["message"] = message
        row["status"] = "drafted"
        print(f"[{i}/{len(targets)}] @{row.get('username')} -> {channel} draft ready", file=sys.stderr)
        time.sleep(0.2)

    fieldnames = list(rows[0].keys())
    for extra in ("channel", "email_subject", "message"):
        if extra not in fieldnames:
            fieldnames.append(extra)

    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
