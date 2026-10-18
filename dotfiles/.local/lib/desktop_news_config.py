"""Validated, user-owned configuration for the Awesome RSS inbox."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import unicodedata
from urllib.parse import urlsplit, urlunsplit

CONFIG_VERSION = 1
MAX_CATEGORIES = 8
MAX_FEEDS = 8
MAX_CATEGORY_LABEL = 32
MAX_FEED_LABEL = 64
CATEGORY_ID = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
FEED_ID = re.compile(r"^[0-9a-f]{16,32}$")
LEGACY_CATEGORIES = (
    ("general", "General"),
    ("bydgoszcz", "Bydgoszcz"),
    ("torun", "Toruń"),
    ("cinema", "Cinema"),
)


class NewsConfigError(ValueError):
    """Invalid or unreadable News configuration."""


def config_path() -> Path:
    home = Path(os.environ.get("HOME", str(Path.home())))
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    return config_home / "desktop-news" / "config.json"


def legacy_feed_path() -> Path:
    home = Path(os.environ.get("HOME", str(Path.home())))
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    return config_home / "awesome" / "news-feeds"


def legacy_profile_path() -> Path:
    home = Path(os.environ.get("HOME", str(Path.home())))
    state_home = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    return state_home / "awesome" / "sidebar-sections"


def valid_http_url(value: str) -> str | None:
    value = value.strip()
    if not value or len(value) > 2048 or any(ord(char) < 32 for char in value):
        return None
    try:
        parsed = urlsplit(value)
        if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
            return None
        if parsed.username is not None or parsed.password is not None:
            return None
        _ = parsed.port
        return urlunsplit((parsed.scheme.lower(), parsed.netloc, parsed.path or "/",
                           parsed.query, parsed.fragment))
    except ValueError:
        return None


def canonical_url(value: str) -> str:
    parsed = urlsplit(value)
    host = (parsed.hostname or "").lower()
    port = parsed.port
    default_port = (parsed.scheme == "http" and port == 80) or (parsed.scheme == "https" and port == 443)
    authority = host if not port or default_port else f"{host}:{port}"
    if ":" in host and not host.startswith("["):
        authority = f"[{host}]" + (f":{port}" if port and not default_port else "")
    return urlunsplit((parsed.scheme.lower(), authority, parsed.path or "/", parsed.query, ""))


def new_category_id(label: str, existing: set[str] | None = None) -> str:
    existing = existing or set()
    normalized = unicodedata.normalize("NFKD", label).encode("ascii", "ignore").decode("ascii").lower()
    base = re.sub(r"[^a-z0-9]+", "-", normalized).strip("-") or "category"
    base = base[:32].rstrip("-_") or "category"
    candidate = base
    suffix = 2
    while candidate in existing:
        ending = f"-{suffix}"
        candidate = base[:32 - len(ending)].rstrip("-_") + ending
        suffix += 1
    return candidate


def new_feed_id() -> str:
    return os.urandom(8).hex()


def _text(value: object, name: str, maximum: int) -> str:
    if not isinstance(value, str):
        raise NewsConfigError(f"{name} must be text")
    value = value.strip()
    if not value or len(value) > maximum or any(ord(char) < 32 for char in value):
        raise NewsConfigError(f"{name} must contain 1–{maximum} printable characters")
    return value


def validate_config(value: object) -> dict:
    if not isinstance(value, dict) or value.get("version") != CONFIG_VERSION:
        raise NewsConfigError("News configuration has an unsupported format")
    categories = value.get("categories")
    feeds = value.get("feeds")
    if not isinstance(categories, list) or not isinstance(feeds, list):
        raise NewsConfigError("News configuration must contain category and feed lists")
    if len(categories) > MAX_CATEGORIES:
        raise NewsConfigError(f"At most {MAX_CATEGORIES} categories are supported")
    if len(feeds) > MAX_FEEDS:
        raise NewsConfigError(f"At most {MAX_FEEDS} feeds are supported")

    clean_categories = []
    category_ids: set[str] = set()
    category_labels: set[str] = set()
    for row in categories:
        if not isinstance(row, dict):
            raise NewsConfigError("Each category must be an object")
        category_id = row.get("id")
        if not isinstance(category_id, str) or not CATEGORY_ID.fullmatch(category_id):
            raise NewsConfigError("Category IDs must use lowercase letters, digits, _ or -")
        label = _text(row.get("label"), "Category name", MAX_CATEGORY_LABEL)
        if category_id == "all":
            raise NewsConfigError("The category ID 'all' is reserved for the All filter")
        if label.casefold() in {"all", "unread"}:
            raise NewsConfigError(f"The category name {label!r} is reserved by the News filters")
        if category_id in category_ids:
            raise NewsConfigError(f"Duplicate category ID: {category_id}")
        if label.casefold() in category_labels:
            raise NewsConfigError(f"Duplicate category name: {label}")
        category_ids.add(category_id)
        category_labels.add(label.casefold())
        clean_categories.append({"id": category_id, "label": label})

    clean_feeds = []
    feed_ids: set[str] = set()
    feed_urls: set[str] = set()
    for row in feeds:
        if not isinstance(row, dict):
            raise NewsConfigError("Each feed must be an object")
        feed_id = row.get("id")
        if not isinstance(feed_id, str) or not FEED_ID.fullmatch(feed_id):
            raise NewsConfigError("Feed IDs must be 16–32 lowercase hexadecimal characters")
        if feed_id in feed_ids:
            raise NewsConfigError(f"Duplicate feed ID: {feed_id}")
        category = row.get("category")
        if not isinstance(category, str) or category not in category_ids:
            raise NewsConfigError("Every feed must use an existing category")
        label = _text(row.get("label"), "Feed name", MAX_FEED_LABEL)
        raw_url = row.get("url")
        if not isinstance(raw_url, str) or not (url := valid_http_url(raw_url)):
            raise NewsConfigError(f"Feed {label!r} must use a valid HTTP(S) URL without credentials")
        url = canonical_url(url)
        if url in feed_urls:
            raise NewsConfigError(f"Duplicate feed URL: {url}")
        enabled = row.get("enabled")
        if not isinstance(enabled, bool):
            raise NewsConfigError(f"Feed {label!r} enabled state must be true or false")
        feed_ids.add(feed_id)
        feed_urls.add(url)
        clean_feeds.append({"id": feed_id, "category": category, "label": label,
                            "url": url, "enabled": enabled})
    return {"version": CONFIG_VERSION, "categories": clean_categories, "feeds": clean_feeds}


def empty_config() -> dict:
    return {"version": CONFIG_VERSION, "categories": [], "feeds": []}


def _legacy_config(path: Path) -> dict:
    categories = [{"id": category_id, "label": label}
                  for category_id, label in LEGACY_CATEGORIES]
    labels = dict(LEGACY_CATEGORIES)
    feeds = []
    seen_urls: set[str] = set()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        lines = []
    except (OSError, UnicodeError) as error:
        raise NewsConfigError(f"Could not read legacy feed list: {error}") from error
    for line_number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != 3:
            raise NewsConfigError(f"{path}:{line_number}: expected category<TAB>label<TAB>URL")
        category, label, raw_url = (field.strip() for field in fields)
        if category not in labels:
            raise NewsConfigError(f"{path}:{line_number}: unknown category {category!r}")
        label = _text(label, "Feed name", MAX_FEED_LABEL)
        normalized = valid_http_url(raw_url)
        if not normalized:
            raise NewsConfigError(f"{path}:{line_number}: invalid HTTP(S) feed URL")
        url = canonical_url(normalized)
        if url in seen_urls:
            raise NewsConfigError(f"{path}:{line_number}: duplicate feed URL")
        seen_urls.add(url)
        source_id = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
        feeds.append({"id": source_id, "category": category, "label": label,
                      "url": url, "enabled": True})
    return validate_config({"version": CONFIG_VERSION, "categories": categories, "feeds": feeds})


def _atomic_json(path: Path, value: dict) -> None:
    destination = path.expanduser().parent.resolve(strict=False) / path.name
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".desktop-news.", suffix=".tmp", dir=destination.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
        directory_fd = os.open(destination.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def save_config(value: object, path: Path | None = None) -> dict:
    clean = validate_config(value)
    _atomic_json(path or config_path(), clean)
    return clean


def load_config(path: Path | None = None, *, legacy_path: Path | None = None,
                profile_state_path: Path | None = None) -> dict:
    """Load user config, migrating an existing profile once or seeding an empty config."""
    destination = path or config_path()
    if destination.exists():
        try:
            raw = json.loads(destination.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise NewsConfigError(f"Cannot read News settings safely: {error}") from error
        return validate_config(raw)

    legacy = legacy_path or legacy_feed_path()
    profile = profile_state_path or legacy_profile_path()
    if profile.is_file():
        initial = _legacy_config(legacy)
    else:
        initial = empty_config()
    # Persist even the empty case: this is the one-time migration marker and keeps
    # a later sidebar state file from accidentally importing the packaged example.
    return save_config(initial, destination)
