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
sys.path.insert(0, str(ROOT / "dotfiles/.local/lib"))
import desktop_news_config as news_config
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
        self.config_path = self.directory / "config/desktop-news/config.json"
        self.feeds_path = self.config_path
        self.config_path_patch = patch.object(news_config, "config_path", return_value=self.config_path)
        self.config_path_patch.start()
        self.legacy_path = self.directory / "config/awesome/news-feeds"
        self.profile_path = self.directory / "state/awesome/sidebar-sections"
        self.legacy_path.parent.mkdir(parents=True)
        self.legacy_path.write_text("general\tFixture\thttps://example.test/rss\n", encoding="utf-8")
        self.config = news_config.save_config({
            "version": 1,
            "categories": [{"id": "general", "label": "General"}],
            "feeds": [{"id": "0123456789abcdef", "category": "general", "label": "Fixture",
                       "url": "https://example.test/rss", "enabled": True}],
        }, self.config_path)
        self.feed = news.load_feeds(self.config_path)[0]

    def tearDown(self):
        self.config_path_patch.stop()
        self.temporary.cleanup()

    def item(self, item_id, *, read=False, published=100):
        return {"id": item_id, "category": "general", "source": "Fixture",
                "title": "Story " + item_id, "summary": "Description", "url": "https://example.test/" + item_id,
                "published": published, "read": read}

    def test_one_shot_feed_test_does_not_touch_inbox_state(self):
        with patch.object(news, "_fetch_one", return_value=(self.feed, [self.item("d" * 32)], None, None)) as fetch:
            self.assertEqual(news.test_feed(self.feed["url"]), 1)
        fetch.assert_called_once()
        self.assertEqual(fetch.call_args.args[0]["url"], self.feed["url"])
        self.assertFalse(self.state_path.exists())
        with self.assertRaisesRegex(ValueError, "valid HTTP"):
            news.test_feed("file:///etc/passwd")

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

    def test_dynamic_config_validation_and_disabled_sources(self):
        loaded = news_config.load_config(self.config_path)
        self.assertEqual(stat.S_IMODE(self.config_path.stat().st_mode), 0o600)
        self.assertEqual(loaded["categories"], [{"id": "general", "label": "General"}])
        self.assertEqual(len(news.load_feeds(self.config_path)), 1)
        disabled = {**loaded, "feeds": [{**loaded["feeds"][0], "enabled": False}]}
        news_config.save_config(disabled, self.config_path)
        self.assertEqual(news.load_feeds(self.config_path), [])
        for invalid in (
            {**loaded, "categories": [{"id": "Bad ID", "label": "Bad"}]},
            {**loaded, "categories": [{"id": "all", "label": "Everything"}]},
            {**loaded, "categories": [{"id": "everything", "label": "Unread"}]},
            {**loaded, "feeds": [{**loaded["feeds"][0], "url": "ftp://example.test/rss"}]},
            {**loaded, "feeds": [loaded["feeds"][0], {**loaded["feeds"][0], "id": "fedcba9876543210"}]},
            {**loaded, "feeds": [{**loaded["feeds"][0], "category": "missing"}]},
        ):
            with self.assertRaises(ValueError):
                news_config.validate_config(invalid)
        duplicate_urls = {**loaded, "feeds": [
            loaded["feeds"][0], {**loaded["feeds"][0], "id": "fedcba9876543210",
                                  "url": "https://EXAMPLE.test:443/rss#duplicate"}]}
        with self.assertRaisesRegex(ValueError, "Duplicate feed URL"):
            news_config.validate_config(duplicate_urls)

    def test_existing_profile_migrates_once_and_clean_profile_stays_empty(self):
        config_path = self.directory / "migration/config.json"
        legacy_path = self.directory / "migration/awesome/news-feeds"
        profile_path = self.directory / "migration/state/awesome/sidebar-sections"
        legacy_path.parent.mkdir(parents=True)
        profile_path.parent.mkdir(parents=True)
        legacy_path.write_text("general\tWykop\thttps://wykop.pl/rss\n", encoding="utf-8")
        profile_path.write_text("order=calendar,todo\nenabled=calendar,todo\n", encoding="utf-8")
        migrated = news_config.load_config(config_path, legacy_path=legacy_path,
                                           profile_state_path=profile_path)
        self.assertEqual([row["id"] for row in migrated["categories"]],
                         ["general", "bydgoszcz", "torun", "cinema"])
        self.assertEqual(migrated["feeds"][0]["label"], "Wykop")
        self.assertTrue(migrated["feeds"][0]["enabled"])
        legacy_path.write_text("", encoding="utf-8")
        self.assertEqual(news_config.load_config(config_path, legacy_path=legacy_path,
                                                 profile_state_path=profile_path), migrated)

        clean_config = self.directory / "clean/config.json"
        clean_legacy = self.directory / "clean/awesome/news-feeds"
        clean_profile = self.directory / "clean/state/awesome/sidebar-sections"
        clean_legacy.parent.mkdir(parents=True)
        clean_legacy.write_text("general\tWykop\thttps://wykop.pl/rss\n", encoding="utf-8")
        empty = news_config.load_config(clean_config, legacy_path=clean_legacy,
                                        profile_state_path=clean_profile)
        self.assertEqual(empty, {"version": 1, "categories": [], "feeds": []})
        clean_profile.parent.mkdir(parents=True)
        clean_profile.write_text("version=2\n", encoding="utf-8")
        self.assertEqual(news_config.load_config(clean_config, legacy_path=clean_legacy,
                                                 profile_state_path=clean_profile), empty)

    def test_corrupt_config_is_not_overwritten(self):
        self.config_path.write_text("{broken", encoding="utf-8")
        before = self.config_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "Cannot read News settings safely"):
            news_config.load_config(self.config_path)
        self.assertEqual(self.config_path.read_bytes(), before)

    def test_refresh_preserves_state_and_dismissals(self):
        story = self.item("a" * 32)
        with patch.object(news, "_fetch_one", return_value=(self.feed, [story], '"etag"', "Wed, 15 Oct 2025 07:00:00 GMT")):
            first = news.refresh(self.state_path, self.feeds_path, now=1000)
        self.assertTrue(first.startswith("news-v2\t1\t1000\t1000\n"))
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertFalse(state["items"][story["id"]]["read"])
        self.assertEqual(stat.S_IMODE(self.state_path.stat().st_mode), 0o600)

        read_snapshot = news.action(self.state_path, "mark-read", story["id"])
        self.assertIn("\t1\tStory%20", read_snapshot)
        with patch.object(news, "_fetch_one", return_value=(self.feed, [story], '"etag"', None)):
            refreshed = news.refresh(self.state_path, self.feeds_path, now=2000)
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertTrue(state["items"][story["id"]]["read"], "refresh must retain the user's read state")
        self.assertIn("news-v2\t3\t2000\t2000", refreshed)

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

    def test_reassigning_feed_moves_cached_stories_without_dropping_read_state(self):
        story = self.item("c" * 32, read=True)
        story["feed_url"] = self.feed["url"]
        state = news._new_state()
        state["items"][story["id"]] = story
        state["feeds"][self.feed["url"]] = {"category": "general", "label": "Fixture"}
        news._write_unlocked(self.state_path, state)
        changed = {"version": 1,
                   "categories": [{"id": "general", "label": "General"},
                                  {"id": "local", "label": "Local"}],
                   "feeds": [{**self.feed, "category": "local", "enabled": True}]}
        news_config.save_config(changed, self.config_path)
        local_feed = changed["feeds"][0]
        with patch.object(news, "_fetch_one", return_value=(local_feed, [], '"etag"', None)):
            news.refresh(self.state_path, self.config_path, now=1500)
        updated = json.loads(self.state_path.read_text(encoding="utf-8"))["items"][story["id"]]
        self.assertEqual(updated["category"], "local")
        self.assertTrue(updated["read"])
        self.assertEqual(updated["feed_url"], self.feed["url"])

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
                self.assertTrue(future.result().startswith("news-v2\t"))
        parsed = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertEqual(parsed["revision"], len(actions))
        self.assertTrue(all(isinstance(item["read"], bool) for item in parsed["items"].values()))
        self.assertTrue(news.snapshot(self.state_path).startswith("news-v2\t"))

    def test_corrupt_state_is_not_overwritten(self):
        self.state_path.parent.mkdir(parents=True)
        self.state_path.write_text("{bad json", encoding="utf-8")
        before = self.state_path.read_bytes()
        with self.assertRaises(ValueError):
            news.snapshot(self.state_path)
        self.assertEqual(self.state_path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
