#!/usr/bin/env python3
"""Offline RSS parsing, state, and persistence tests for desktop-news."""
import concurrent.futures
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "dotfiles/.local/bin/desktop-news"
loader = SourceFileLoader("desktop_news", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
news = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = news
loader.exec_module(news)

RSS = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
 <channel><title>Fixture</title>
  <item><title>Zażółć &amp; news</title><link>https://example.test/story#top</link>
   <guid isPermaLink="false">story-1</guid>
   <description><![CDATA[<p>First <b>description</b><br>line.</p><script>ignore()</script> &amp; more]]></description>
   <pubDate>Wed, 15 Oct 2025 07:00:00 GMT</pubDate></item>
  <item><title>Unsafe link</title><link>javascript:alert(1)</link><description>Plain</description></item>
 </channel></rss>'''.encode("utf-8")
ATOM = b'''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:xhtml="http://www.w3.org/1999/xhtml">
 <entry><title>Atom &amp; headline</title><link rel="alternate" href="https://example.test/atom"/>
  <id>tag:example.test,2025:2</id><updated>2025-10-16T12:30:00Z</updated>
  <summary type="xhtml"><xhtml:div>Text <xhtml:em>inside</xhtml:em></xhtml:div></summary></entry>
</feed>'''


class DesktopNewsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="desktop-news-test-")
        self.directory = Path(self.temporary.name)
        self.state_path = self.directory / "state/awesome/news.json"
        self.feeds_path = self.directory / "config/awesome/news-feeds"
        self.feeds_path.parent.mkdir(parents=True)
        self.feeds_path.write_text("general\tFixture\thttps://example.test/rss\n", encoding="utf-8")
        self.feed = news.load_feeds(self.feeds_path)[0]

    def tearDown(self):
        self.temporary.cleanup()

    def item(self, item_id, *, read=False, published=100):
        return {"id": item_id, "category": "general", "source": "Fixture",
                "title": "Story " + item_id, "summary": "Description", "url": "https://example.test/" + item_id,
                "published": published, "read": read}

    def test_rss_atom_html_and_unsafe_links(self):
        items = news.parse_feed(RSS, self.feed, now=1_760_000_000)
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]["title"], "Zażółć & news")
        story = items[0]
        unsafe = next(item for item in items if item["title"] == "Unsafe link")
        self.assertIsNone(unsafe["url"])
        self.assertEqual(story["url"], "https://example.test/story#top")
        self.assertEqual(story["summary"], "First description line. & more")
        self.assertNotIn("ignore", story["summary"])
        atom_feed = dict(self.feed, url="https://example.test/atom")
        atom = news.parse_feed(ATOM, atom_feed, now=1_760_000_000)
        self.assertEqual(atom[0]["title"], "Atom & headline")
        self.assertEqual(atom[0]["summary"], "Text inside")
        self.assertEqual(atom[0]["url"], "https://example.test/atom")
        from datetime import datetime, timezone
        expected = int(datetime(2025, 10, 16, 12, 30, tzinfo=timezone.utc).timestamp())
        self.assertEqual(atom[0]["published"], expected)

    def test_parser_rejects_bad_documents_and_bounds_text(self):
        with self.assertRaises(ValueError):
            news.parse_feed(b"<html>not a feed</html>", self.feed)
        with self.assertRaises(ValueError):
            news.parse_feed(b"<rss><channel><title>Missing items</title></channel></rss>", self.feed)
        with self.assertRaises(ValueError):
            news.parse_feed(b"x" * (news.MAX_BYTES + 1), self.feed)
        with self.assertRaisesRegex(ValueError, "DTD/entity"):
            news.parse_feed(b'<!DOCTYPE rss [<!ENTITY x "expanded">]><rss><channel><item><title>&x;</title></item></channel></rss>', self.feed)
        oversized = b"<rss><channel><item><title>" + b"x" * (news.MAX_TITLE + 20) + b"</title></item></channel></rss>"
        self.assertLessEqual(len(news.parse_feed(oversized, self.feed)[0]["title"]), news.MAX_TITLE)
        self.assertIsNone(news.valid_http_url("file:///etc/passwd"))
        self.assertIsNone(news.valid_http_url("https://user:pass@example.test/rss"))
        self.assertIsNone(news.valid_http_url("javascript:alert(1)"))

    def test_feed_manifest_validation(self):
        feeds = news.load_feeds(self.feeds_path)
        self.assertEqual([(f["category"], f["label"], f["url"]) for f in feeds],
                         [("general", "Fixture", "https://example.test/rss")])
        self.feeds_path.write_text("news\tBad\tftp://example.test/rss\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            news.load_feeds(self.feeds_path)
        self.feeds_path.write_text("general\tA\thttps://example.test/rss\ngeneral\tB\thttps://example.test/rss\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            news.load_feeds(self.feeds_path)
        self.feeds_path.write_text("general\tA\thttps://EXAMPLE.test:443/rss#one\ngeneral\tB\thttps://example.test/rss#two\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            news.load_feeds(self.feeds_path)

    def test_refresh_preserves_state_and_dismissals(self):
        story = self.item("a" * 32)
        with patch.object(news, "_fetch_one", return_value=(self.feed, [story], '"etag"', "Wed, 15 Oct 2025 07:00:00 GMT")):
            first = news.refresh(self.state_path, self.feeds_path, now=1000)
        self.assertTrue(first.startswith("news-v1\t1\t1000\t1000\n"))
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertFalse(state["items"][story["id"]]["read"])
        self.assertEqual(stat.S_IMODE(self.state_path.stat().st_mode), 0o600)

        read_snapshot = news.action(self.state_path, "mark-read", story["id"])
        self.assertIn("\t1\tStory%20", read_snapshot)
        with patch.object(news, "_fetch_one", return_value=(self.feed, [story], '"etag"', None)):
            refreshed = news.refresh(self.state_path, self.feeds_path, now=2000)
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertTrue(state["items"][story["id"]]["read"], "refresh must retain the user's read state")
        self.assertIn("news-v1\t3\t2000\t2000", refreshed)

        unread = news.action(self.state_path, "mark-unread", story["id"])
        self.assertIn("\t0\tStory%20", unread)
        all_read = news.action(self.state_path, "mark-all-read")
        self.assertIn("\t1\tStory%20", all_read)
        removed = news.action(self.state_path, "remove", story["id"])
        self.assertNotIn(story["id"], removed)
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertIn(story["id"], state["dismissed"])
        with patch.object(news, "_fetch_one", return_value=(self.feed, [story], None, None)):
            after_remove = news.refresh(self.state_path, self.feeds_path, now=3000)
        self.assertNotIn(story["id"], after_remove, "dismissed feed entries must not resurrect")

    def test_feed_failure_retains_cached_items_and_reports_status(self):
        story = self.item("b" * 32)
        with patch.object(news, "_fetch_one", return_value=(self.feed, [story], None, None)):
            news.refresh(self.state_path, self.feeds_path, now=1000)
        with patch.object(news, "_fetch_one", side_effect=ValueError("offline")):
            snapshot = news.refresh(self.state_path, self.feeds_path, now=2000)
        self.assertIn(story["id"], snapshot)
        self.assertIn("offline", snapshot)
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertEqual(state["items"][story["id"]]["title"], story["title"])
        self.assertEqual(state["feeds"][self.feed["url"]]["last_success"], 1000)

    def test_full_inbox_does_not_drop_unread_and_reclaims_read(self):
        state = news._new_state()
        state["feeds"][self.feed["url"]] = {"category": "general", "label": "Fixture"}
        for index in range(news.MAX_ITEMS):
            item_id = f"{index:032x}"
            state["items"][item_id] = self.item(item_id, published=index)
        news._write_unlocked(self.state_path, state)
        incoming = self.item("f" * 32, published=10000)
        with patch.object(news, "_fetch_one", return_value=(self.feed, [incoming], None, None)):
            full = news.refresh(self.state_path, self.feeds_path, now=1000)
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertEqual(len(state["items"]), news.MAX_ITEMS)
        self.assertNotIn(incoming["id"], state["items"])
        self.assertIn("Inbox%20full", full)

        oldest = min(state["items"].values(), key=lambda item: item["published"])
        news.action(self.state_path, "mark-read", oldest["id"])
        with patch.object(news, "_fetch_one", return_value=(self.feed, [incoming], None, None)):
            recovered = news.refresh(self.state_path, self.feeds_path, now=2000)
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertEqual(len(state["items"]), news.MAX_ITEMS)
        self.assertIn(incoming["id"], state["items"])
        self.assertNotIn(oldest["id"], state["items"])
        self.assertNotIn("Inbox%20full", recovered)

    def test_snapshot_and_concurrent_actions_keep_valid_json(self):
        one, two = self.item("1" * 32), self.item("2" * 32)
        state = news._new_state()
        state["items"] = {one["id"]: one, two["id"]: two}
        news._write_unlocked(self.state_path, state)
        actions = [("mark-read", one["id"]), ("mark-unread", one["id"]),
                   ("mark-read", two["id"]), ("mark-all-read", None)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            futures = [executor.submit(news.action, self.state_path, name, item_id)
                       for name, item_id in actions]
            for future in futures:
                self.assertTrue(future.result().startswith("news-v1\t"))
        parsed = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertEqual(parsed["revision"], len(actions))
        self.assertTrue(all(isinstance(item["read"], bool) for item in parsed["items"].values()))
        self.assertTrue(news.snapshot(self.state_path).startswith("news-v1\t"))

    def test_corrupt_state_is_not_overwritten(self):
        self.state_path.parent.mkdir(parents=True)
        self.state_path.write_text("{bad json", encoding="utf-8")
        before = self.state_path.read_bytes()
        with self.assertRaises(ValueError):
            news.snapshot(self.state_path)
        self.assertEqual(self.state_path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
