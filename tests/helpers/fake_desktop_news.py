#!/usr/bin/env python3
"""Offline stateful desktop-news command stub for private Awesome sessions."""
import hashlib
import json
import os
from pathlib import Path
import sys
import time
from urllib.parse import quote

state_path = Path(os.environ["TEST_NEWS_STATE"])
items = [
    {"id": f"{index:032x}", "category": "cinema" if index == 8 else "general",
     "source": "Cinema fixture" if index == 8 else "Wykop fixture",
     "title": f"Fixture story {index}", "summary": f"Fixture description {index} with useful detail.",
     "url": f"https://example.test/story/{index}", "published": int(time.time()) - index * 60,
     "read": False}
    for index in range(1, 9)
]
now = int(time.time())
state = {"revision": 1, "last_attempt": now, "last_success": now, "items": items}
if state_path.exists():
    state = json.loads(state_path.read_text(encoding="utf-8"))
command = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
item_id = sys.argv[2] if len(sys.argv) > 2 else None
with open(os.environ["TEST_ACTIONS"], "a", encoding="utf-8") as log:
    log.write("desktop-news " + " ".join(sys.argv[1:]) + "\n")
if command == "mark-read":
    for item in state["items"]:
        if item["id"] == item_id: item["read"] = True
elif command == "mark-unread":
    for item in state["items"]:
        if item["id"] == item_id: item["read"] = False
elif command == "remove":
    state["items"] = [item for item in state["items"] if item["id"] != item_id]
elif command == "mark-all-read":
    for item in state["items"]: item["read"] = True
elif command not in {"refresh", "snapshot"}:
    raise SystemExit(2)
state["revision"] += 1
state["last_attempt"] = now
state["last_success"] = now
state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(state), encoding="utf-8")
feed_url = "https://wykop.pl/rss"
feed_id = hashlib.sha256(feed_url.encode()).hexdigest()[:16]
print(f"news-v2\t{state['revision']}\t{state['last_success']}\t{state['last_attempt']}")
for category_id, label in (("general", "General"), ("bydgoszcz", "Bydgoszcz"),
                           ("torun", "Toruń"), ("cinema", "Cinema"),
                           ("community", "Community")):
    print(f"category\t{category_id}\t{quote(label, safe='')}")
print(f"feed\t{feed_id}\tgeneral\tWykop%20fixture\t\t{state['last_success']}")
for item in sorted(state["items"], key=lambda row: row["published"], reverse=True):
    fields = ("item", item["id"], item["category"], quote(item["source"], safe=""),
              str(item["published"]), "1" if item["read"] else "0",
              quote(item["title"], safe=""), quote(item["summary"], safe=""),
              quote(item["url"], safe=""))
    print("\t".join(fields))
