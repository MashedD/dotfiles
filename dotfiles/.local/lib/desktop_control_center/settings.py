"""Safe, comment-preserving settings support for desktop-control-center."""
from __future__ import annotations

import json
import math
import os
import re
import shlex
import signal
import stat
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Callable


DEFAULTS: dict[str, object] = {
    "Net/ThemeName": "Adwaita",
    "Net/IconThemeName": "Breeze",
    "Gtk/ColorScheme": "selected_bg_color:#3584e4\nselected_fg_color:#ffffff",
    "Gtk/FontName": "Microsoft Sans Serif 8",
    "Gtk/CursorThemeName": "Adwaita",
    "Gtk/CursorThemeSize": 0,
    "Gtk/ToolbarStyle": 3,
    "Gtk/ButtonImages": 1,
    "Gtk/MenuImages": 1,
    "Gtk/EnableAnimations": 1,
    "Gtk/EnableEventSounds": 1,
    "Gtk/EnableInputFeedbackSounds": 1,
    "Xft/Antialias": 1,
    "Xft/Hinting": 1,
    "Xft/HintStyle": "hintslight",
    "Xft/RGBA": "rgb",
}

INTEGER_SETTINGS = {
    "Gtk/CursorThemeSize", "Gtk/ToolbarStyle", "Gtk/ButtonImages",
    "Gtk/MenuImages", "Gtk/EnableAnimations", "Gtk/EnableEventSounds",
    "Gtk/EnableInputFeedbackSounds", "Xft/Antialias", "Xft/Hinting",
}
TOOLBAR_STYLES = {
    0: "GTK_TOOLBAR_ICONS",
    1: "GTK_TOOLBAR_TEXT",
    2: "GTK_TOOLBAR_BOTH",
    3: "GTK_TOOLBAR_BOTH_HORIZ",
}
TOOLBAR_STYLE_IDS = {value: key for key, value in TOOLBAR_STYLES.items()}

SIDEBAR_SECTIONS = (
    ("calendar", "Calendar"),
    ("todo", "To-do list"),
    ("news", "News"),
    ("quick-launch", "Quick Launch"),
    ("system-status", "System Status"),
    ("codex", "Codex quotas"),
    ("crypto", "Crypto prices"),
    ("weather", "Weather"),
    ("now-playing", "Now Playing"),
    ("wallpaper", "Wallpaper picker"),
)
SIDEBAR_SECTION_IDS = tuple(section_id for section_id, _ in SIDEBAR_SECTIONS)
DEFAULT_SIDEBAR_ENABLED = frozenset(
    section_id for section_id in SIDEBAR_SECTION_IDS if section_id != "quick-launch"
)
SIDEBAR_PREFERENCE_KEYS = {
    "weather_label", "latitude", "longitude", "todo_path", "calendar_path",
    "wallpaper_dirs", "editor_command", "browser_command",
}


def default_sidebar_preferences(home: Path | None = None,
                               data_home: Path | None = None) -> dict[str, object]:
    home = Path(home or Path.home()).expanduser()
    if data_home is None:
        data_home = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    return {
        "weather_label": "Bydgoszcz, Poland",
        "latitude": 53.1235,
        "longitude": 17.9871,
        "todo_path": str(home / "Documents/todo.md"),
        "calendar_path": str(home / "Documents/calendar.md"),
        "wallpaper_dirs": [str(Path(data_home).expanduser() / "wallpapers"),
                           str(home / "Pictures/Wallpapers")],
        "editor_command": [],
        "browser_command": ["firefox", "--new-tab", "{url}"],
    }


def validate_sidebar_preferences(preferences: dict[str, object]) -> dict[str, object]:
    unknown = set(preferences) - SIDEBAR_PREFERENCE_KEYS
    missing = SIDEBAR_PREFERENCE_KEYS - set(preferences)
    if unknown or missing:
        raise SettingsError("Sidebar preferences have invalid fields")
    result = dict(preferences)
    label = result["weather_label"]
    if not isinstance(label, str) or not label.strip() or len(label) > 100:
        raise SettingsError("Weather location must be 1–100 characters")
    if any(ord(char) < 32 or ord(char) == 127 for char in label):
        raise SettingsError("Weather location contains a control character")
    for key, low, high in (("latitude", -90, 90), ("longitude", -180, 180)):
        try:
            value = float(result[key])
        except (TypeError, ValueError) as exc:
            raise SettingsError(f"{key} must be a number") from exc
        if not math.isfinite(value) or not low <= value <= high:
            raise SettingsError(f"{key} must be between {low} and {high}")
        result[key] = value
    for key in ("todo_path", "calendar_path"):
        path = result[key]
        if not isinstance(path, str) or not path.strip() or len(path) > 4096:
            raise SettingsError(f"{key} must be a non-empty path")
        if any(ord(char) < 32 or ord(char) == 127 for char in path):
            raise SettingsError(f"{key} contains a control character")
    for key in ("editor_command", "browser_command"):
        command = result[key]
        if not isinstance(command, list) or len(command) > 32 or (key == "browser_command" and not command):
            raise SettingsError(f"{key} must contain 1–32 arguments" if key == "browser_command"
                               else "editor_command supports at most 32 arguments")
        for argument in command:
            if not isinstance(argument, str) or not argument or len(argument) > 4096:
                raise SettingsError(f"{key} contains an invalid argument")
            if any(ord(char) < 32 or ord(char) == 127 for char in argument):
                raise SettingsError(f"{key} contains a control character")
    directories = result["wallpaper_dirs"]
    if not isinstance(directories, list) or len(directories) > 32:
        raise SettingsError("Use at most 32 wallpaper folders")
    cleaned: list[str] = []
    seen: set[str] = set()
    for directory in directories:
        if not isinstance(directory, str) or not directory.strip() or len(directory) > 4096:
            raise SettingsError("Wallpaper folders must be non-empty paths")
        if any(ord(char) < 32 or ord(char) == 127 for char in directory):
            raise SettingsError("Wallpaper folder path contains a control character")
        normalized = directory.strip()
        if normalized not in seen:
            cleaned.append(normalized)
            seen.add(normalized)
    result["weather_label"] = label.strip()
    result["todo_path"] = str(result["todo_path"]).strip()
    result["calendar_path"] = str(result["calendar_path"]).strip()
    result["wallpaper_dirs"] = cleaned
    return result


def parse_sidebar_preferences(text: str, defaults: dict[str, object] | None = None) -> dict[str, object]:
    if len(text) > 65536:
        raise SettingsError("Sidebar preferences file is too large")
    preferences = dict(defaults or default_sidebar_preferences())
    preferences["wallpaper_dirs"] = list(preferences.get("wallpaper_dirs", []))
    values: dict[str, str] = {}
    commands: dict[str, list[str]] = {"editor_command": [], "browser_command": []}
    has_commands: set[str] = set()
    wallpaper_dirs: list[str] = []
    has_wallpaper_dirs = False
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped == "version=1":
            continue
        key, separator, value = line.partition("=")
        if not separator or key not in SIDEBAR_PREFERENCE_KEYS:
            raise SettingsError(f"Invalid sidebar preference on line {line_number}")
        if key == "wallpaper_dirs":
            has_wallpaper_dirs = True
            if value.strip(): wallpaper_dirs.append(value.strip())
        elif key in commands:
            has_commands.add(key)
            if value: commands[key].append(value)
        elif key in values:
            raise SettingsError(f"Duplicate sidebar preference: {key}")
        else:
            values[key] = value
    for key in ("weather_label", "todo_path", "calendar_path"):
        if key in values: preferences[key] = values[key]
    for key in ("latitude", "longitude"):
        if key in values:
            try: preferences[key] = float(values[key])
            except ValueError as exc: raise SettingsError(f"{key} must be a number") from exc
    if has_wallpaper_dirs: preferences["wallpaper_dirs"] = wallpaper_dirs
    for key in has_commands: preferences[key] = commands[key]
    return validate_sidebar_preferences(preferences)


def serialize_sidebar_preferences(preferences: dict[str, object]) -> str:
    values = validate_sidebar_preferences(preferences)
    lines = [
        "version=1",
        f"weather_label={values['weather_label']}",
        f"latitude={values['latitude']:.6f}",
        f"longitude={values['longitude']:.6f}",
        f"todo_path={values['todo_path']}",
        f"calendar_path={values['calendar_path']}",
    ]
    lines.extend(f"wallpaper_dirs={directory}" for directory in values["wallpaper_dirs"])
    if not values["wallpaper_dirs"]: lines.append("wallpaper_dirs=")
    for key in ("editor_command", "browser_command"):
        command = values[key]
        lines.extend(f"{key}={argument}" for argument in command)
        if not command: lines.append(f"{key}=")
    return "\n".join(lines) + "\n"


def parse_sidebar_enabled(text: str) -> set[str]:
    """Read enabled section IDs, applying Awesome's one-time News migration."""
    enabled_line: str | None = None
    version = 0
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if separator and key.strip() == "enabled":
            enabled_line = value
        elif separator and key.strip() == "version":
            try:
                version = int(value.strip())
            except ValueError:
                version = 0
    if enabled_line is None:
        return set(DEFAULT_SIDEBAR_ENABLED)
    enabled: set[str] = set()
    for section_id in enabled_line.split(","):
        section_id = section_id.strip()
        if section_id in SIDEBAR_SECTION_IDS:
            enabled.add(section_id)
    if version < 2:
        enabled.add("news")
    return enabled


def update_sidebar_enabled_text(text: str, enabled: set[str]) -> str:
    """Replace the enabled list without disturbing order or collapsed-section state."""
    unknown = set(enabled) - set(SIDEBAR_SECTION_IDS)
    if unknown:
        raise SettingsError(f"Unknown sidebar section(s): {', '.join(sorted(unknown))}")
    line = "enabled=" + ",".join(
        section_id for section_id in SIDEBAR_SECTION_IDS if section_id in enabled
    ) + "\n"
    output: list[str] = []
    replaced = False
    for existing in text.splitlines(keepends=True):
        key, separator, _ = existing.rstrip("\r\n").partition("=")
        if separator and key.strip() == "version":
            continue
        if separator and key.strip() == "enabled":
            if not replaced:
                output.append(line)
                replaced = True
            continue
        output.append(existing)
    if not replaced:
        insertion = next((index + 1 for index, existing in enumerate(output)
                          if existing.rstrip("\r\n").lstrip().startswith("order=")), len(output))
        if insertion == len(output) and output and not output[-1].endswith(("\n", "\r")):
            output[-1] += "\n"
        output.insert(insertion, line)
    return "version=2\n" + "".join(output)


GTK_INI_KEYS = {
    "Net/ThemeName": "gtk-theme-name",
    "Net/IconThemeName": "gtk-icon-theme-name",
    "Gtk/CursorThemeName": "gtk-cursor-theme-name",
    "Gtk/CursorThemeSize": "gtk-cursor-theme-size",
    "Gtk/FontName": "gtk-font-name",
    "Gtk/ToolbarStyle": "gtk-toolbar-style",
    "Gtk/ButtonImages": "gtk-button-images",
    "Gtk/MenuImages": "gtk-menu-images",
    "Gtk/EnableAnimations": "gtk-enable-animations",
    "Gtk/EnableEventSounds": "gtk-enable-event-sounds",
    "Gtk/EnableInputFeedbackSounds": "gtk-enable-input-feedback-sounds",
    "Xft/Antialias": "gtk-xft-antialias",
    "Xft/Hinting": "gtk-xft-hinting",
    "Xft/HintStyle": "gtk-xft-hintstyle",
    "Xft/RGBA": "gtk-xft-rgba",
}

_LINE = re.compile(r"^(\s*)([A-Za-z][A-Za-z0-9/_-]*)(\s+)(.*)$")
_INI_SECTION = re.compile(r"^\s*\[([^]]+)\]")
_INI_KEY = re.compile(r"^(\s*)([A-Za-z0-9_-]+)(\s*=\s*)(.*?)(\s*)$")


class SettingsError(RuntimeError):
    """A settings file or XSETTINGS operation failed."""


QUICK_LAUNCH_VERSION = 1
QUICK_LAUNCH_MAX_ENTRIES = 24
QUICK_LAUNCH_MAX_ARGUMENTS = 32
QUICK_LAUNCH_MAX_TEXT = 65536


def default_quick_launch_entries(home: Path | None = None) -> list[dict[str, object]]:
    home = Path(home or Path.home()).expanduser()
    control_center = str(home / ".local/bin/desktop-control-center")
    quake_one = str(home / "Games/quake-rerelease/vkquake.sh")
    quake_two = str(home / "Games/quake2/q2pro.sh")
    return [
        {"label": "Terminal", "icon": "utilities-terminal", "argv": ["kitty"], "enabled": True},
        {"label": "Files", "icon": "system-file-manager", "argv": ["pcmanfm"], "enabled": True},
        {"label": "Control Panel", "icon": "preferences-system", "argv": [control_center], "enabled": True},
        {"label": "Finder", "icon": "system-run", "argv": ["xfce4-appfinder"], "enabled": True},
        {"label": "Firefox", "icon": "web-browser", "argv": ["firefox"], "enabled": True},
        {"label": "Quake 1", "icon": "applications-games", "argv": [quake_one], "enabled": True},
        {"label": "Quake 2", "icon": "input-gaming", "argv": [quake_two], "enabled": True},
        {"label": "Sleep", "icon": "system-suspend", "argv": ["systemctl", "suspend"], "enabled": True},
    ]


def default_quick_launch_config(home: Path | None = None) -> dict[str, object]:
    return {"version": QUICK_LAUNCH_VERSION, "entries": default_quick_launch_entries(home)}


def parse_quick_launch_command(command: str) -> list[str]:
    if not isinstance(command, str) or not command.strip() or len(command) > 16384:
        raise SettingsError("Enter a command (maximum 16384 characters)")
    if any(ord(char) < 32 or ord(char) == 127 for char in command):
        raise SettingsError("Command contains a control character")
    try:
        argv = shlex.split(command, posix=True)
    except ValueError as exc:
        raise SettingsError(f"Invalid command quoting: {exc}") from exc
    if not argv:
        raise SettingsError("Enter a command")
    return argv


def _validate_quick_launch_entries(entries: object) -> list[dict[str, object]]:
    if not isinstance(entries, list) or len(entries) > QUICK_LAUNCH_MAX_ENTRIES:
        raise SettingsError(f"Quick Launch supports at most {QUICK_LAUNCH_MAX_ENTRIES} entries")
    result: list[dict[str, object]] = []
    labels: set[str] = set()
    for index, raw in enumerate(entries, 1):
        if not isinstance(raw, dict) or set(raw) != {"label", "icon", "argv", "enabled"}:
            raise SettingsError(f"Quick Launch entry {index} has invalid fields")
        label, icon, argv, enabled = raw["label"], raw["icon"], raw["argv"], raw["enabled"]
        if not isinstance(label, str) or not label.strip() or len(label.strip()) > 40:
            raise SettingsError(f"Quick Launch entry {index} needs a label (maximum 40 characters)")
        label = label.strip()
        if any(ord(char) < 32 or ord(char) == 127 for char in label):
            raise SettingsError(f"Quick Launch entry {index} label contains a control character")
        key = label.casefold()
        if key in labels:
            raise SettingsError(f"Quick Launch labels must be unique: {label}")
        labels.add(key)
        if not isinstance(icon, str) or len(icon) > 256 or any(
                ord(char) < 32 or ord(char) == 127 for char in icon):
            raise SettingsError(f"Quick Launch entry {index} has an invalid icon name")
        if not isinstance(argv, list) or not argv or len(argv) > QUICK_LAUNCH_MAX_ARGUMENTS:
            raise SettingsError(f"Quick Launch entry {index} needs 1–{QUICK_LAUNCH_MAX_ARGUMENTS} command arguments")
        cleaned_argv: list[str] = []
        for argument in argv:
            if not isinstance(argument, str) or not argument or len(argument) > 4096:
                raise SettingsError(f"Quick Launch entry {index} has an invalid command argument")
            if any(ord(char) < 32 or ord(char) == 127 for char in argument):
                raise SettingsError(f"Quick Launch entry {index} command contains a control character")
            cleaned_argv.append(argument)
        if not isinstance(enabled, bool):
            raise SettingsError(f"Quick Launch entry {index} enabled flag must be boolean")
        result.append({"label": label, "icon": icon.strip(), "argv": cleaned_argv,
                       "enabled": enabled})
    return result


def parse_quick_launch_config(text: str) -> dict[str, object]:
    if len(text) > QUICK_LAUNCH_MAX_TEXT:
        raise SettingsError("Quick Launch configuration file is too large")
    try:
        value = json.loads(text)
    except (json.JSONDecodeError, TypeError) as exc:
        raise SettingsError(f"Invalid Quick Launch JSON: {exc}") from exc
    if not isinstance(value, dict) or set(value) != {"version", "entries"}:
        raise SettingsError("Quick Launch configuration has invalid fields")
    if type(value["version"]) is not int or value["version"] != QUICK_LAUNCH_VERSION:
        raise SettingsError("Unsupported Quick Launch configuration version")
    return {"version": QUICK_LAUNCH_VERSION,
            "entries": _validate_quick_launch_entries(value["entries"])}


def serialize_quick_launch_config(entries: object) -> str:
    validated = _validate_quick_launch_entries(entries)
    return json.dumps({"version": QUICK_LAUNCH_VERSION, "entries": validated},
                      ensure_ascii=False, indent=2) + "\n"


CRYPTO_PRICES_VERSION = 1
CRYPTO_MAX_TOKENS = 12
CRYPTO_DECIMAL_OPTIONS = (".", ",")
CRYPTO_TOKENS_DEFAULT = (
    {"symbol": "BTC", "id": "bitcoin", "decimals": 0},
    {"symbol": "ETH", "id": "ethereum", "decimals": 0},
    {"symbol": "LTC", "id": "litecoin", "decimals": 2},
)


def default_crypto_prices_config() -> dict[str, object]:
    return {"version": CRYPTO_PRICES_VERSION, "currency": "USD", "currency_symbol": "$",
            "decimal_separator": ",", "thousands_separator": ".",
            "tokens": [dict(token) for token in CRYPTO_TOKENS_DEFAULT]}


def validate_crypto_prices_config(config: dict[str, object]) -> dict[str, object]:
    if set(config) != {"version", "currency", "currency_symbol", "decimal_separator",
                       "thousands_separator", "tokens"}:
        raise SettingsError("Crypto settings have invalid fields")
    version = config["version"]
    if type(version) is not int or version != CRYPTO_PRICES_VERSION:
        raise SettingsError("Unsupported Crypto settings version")
    currency = config["currency"]
    if not isinstance(currency, str) or not re.fullmatch(r"[A-Za-z]{3}", currency):
        raise SettingsError("Currency must be a three-letter currency code")
    currency_symbol = config["currency_symbol"]
    if (not isinstance(currency_symbol, str) or not currency_symbol.strip()
            or currency_symbol[0].isdigit() or len(currency_symbol) > 8
            or any(char.isspace() for char in currency_symbol)
            or any(ord(char) < 32 or ord(char) == 127 for char in currency_symbol)):
        raise SettingsError("Currency symbol must be 1–8 printable characters")
    decimal_separator, thousands_separator = config["decimal_separator"], config["thousands_separator"]
    if decimal_separator not in CRYPTO_DECIMAL_OPTIONS or thousands_separator not in CRYPTO_DECIMAL_OPTIONS:
        raise SettingsError("Number separators must be dots or commas")
    if decimal_separator == thousands_separator:
        raise SettingsError("Decimal and thousands separators must differ")
    tokens = config["tokens"]
    if not isinstance(tokens, list) or len(tokens) > CRYPTO_MAX_TOKENS:
        raise SettingsError(f"Configure at most {CRYPTO_MAX_TOKENS} tokens")
    cleaned, symbols, ids = [], set(), set()
    for index, token in enumerate(tokens, 1):
        if not isinstance(token, dict) or set(token) != {"symbol", "id", "decimals"}:
            raise SettingsError(f"Token {index} has invalid fields")
        symbol, coin_id, decimals = token["symbol"], token["id"], token["decimals"]
        if not isinstance(symbol, str) or not re.fullmatch(r"[A-Z0-9]{1,10}", symbol):
            raise SettingsError(f"Token {index} symbol must use 1–10 uppercase letters or digits")
        if symbol in symbols:
            raise SettingsError(f"Duplicate token symbol: {symbol}")
        if not isinstance(coin_id, str) or not re.fullmatch(r"[a-z0-9-]{1,64}", coin_id):
            raise SettingsError(f"Token {symbol} needs a valid CoinGecko ID")
        if coin_id in ids:
            raise SettingsError(f"Duplicate CoinGecko ID: {coin_id}")
        if type(decimals) is not int or not 0 <= decimals <= 8:
            raise SettingsError(f"Token {symbol} decimals must be between 0 and 8")
        symbols.add(symbol); ids.add(coin_id)
        cleaned.append({"symbol": symbol, "id": coin_id, "decimals": decimals})
    return {"version": CRYPTO_PRICES_VERSION, "currency": currency.upper(),
            "currency_symbol": currency_symbol.strip(),
            "decimal_separator": decimal_separator, "thousands_separator": thousands_separator,
            "tokens": cleaned}


def parse_crypto_prices_config(text: str) -> dict[str, object]:
    if len(text) > 65536:
        raise SettingsError("Crypto settings file is too large")
    try:
        config = json.loads(text)
    except (json.JSONDecodeError, TypeError) as exc:
        raise SettingsError(f"Invalid Crypto settings JSON: {exc}") from exc
    if not isinstance(config, dict):
        raise SettingsError("Crypto settings must be a JSON object")
    return validate_crypto_prices_config(config)


def serialize_crypto_prices_config(config: dict[str, object]) -> str:
    return json.dumps(validate_crypto_prices_config(config), ensure_ascii=False, indent=2) + "\n"


def _split_comment(raw: str) -> tuple[str, str]:
    quoted = False
    escaped = False
    for index, char in enumerate(raw):
        if escaped:
            escaped = False
            continue
        if char == "\\" and quoted:
            escaped = True
            continue
        if char == '"':
            quoted = not quoted
        elif char == "#" and not quoted and (index == 0 or raw[index - 1].isspace()):
            return raw[:index].rstrip(), raw[len(raw[:index].rstrip()):]
    return raw.rstrip(), raw[len(raw.rstrip()):]


def _decode_string(value: str) -> str:
    if len(value) < 2 or value[0] != '"' or value[-1] != '"':
        raise ValueError("invalid quoted XSETTINGS value")
    source = value[1:-1]
    result: list[str] = []
    index = 0
    escapes = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\"}
    while index < len(source):
        char = source[index]
        if char == "\\" and index + 1 < len(source):
            index += 1
            result.append(escapes.get(source[index], source[index]))
        else:
            result.append(char)
        index += 1
    return "".join(result)


def _parse_value(raw: str) -> object:
    raw, _ = _split_comment(raw)
    raw = raw.strip()
    if raw.startswith('"'):
        end = len(raw) - 1
        if end < 1 or raw[end] != '"':
            raise ValueError("unterminated quoted XSETTINGS value")
        return _decode_string(raw[:end + 1])
    try:
        return int(raw, 10)
    except ValueError:
        return raw


def parse_xsettings(text: str) -> dict[str, object]:
    """Parse values while ignoring blank lines and comments."""
    values: dict[str, object] = {}
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = _LINE.match(line)
        if not match:
            raise SettingsError(f"Invalid xsettingsd.conf line {line_number}: {line}")
        _, key, _, raw = match.groups()
        try:
            values[key] = _parse_value(raw)
        except ValueError as exc:
            raise SettingsError(f"Invalid xsettingsd.conf line {line_number}: {exc}") from exc
    return values


def _validate_settings(settings: dict[str, object]) -> None:
    unknown = set(settings) - set(DEFAULTS)
    if unknown:
        raise SettingsError(f"Unsupported setting(s): {', '.join(sorted(unknown))}")
    for key, value in settings.items():
        if key in INTEGER_SETTINGS:
            if isinstance(value, bool):
                value = int(value)
            if not isinstance(value, int):
                raise SettingsError(f"{key} must be an integer")
            if key == "Gtk/CursorThemeSize" and not 0 <= value <= 128:
                raise SettingsError("Gtk/CursorThemeSize must be between 0 and 128")
            if key == "Gtk/ToolbarStyle" and value not in TOOLBAR_STYLES:
                raise SettingsError("Gtk/ToolbarStyle must be between 0 and 3")
            if key in {"Gtk/ButtonImages", "Gtk/MenuImages", "Gtk/EnableAnimations",
                       "Gtk/EnableEventSounds", "Gtk/EnableInputFeedbackSounds",
                       "Xft/Antialias", "Xft/Hinting"} and value not in (0, 1):
                raise SettingsError(f"{key} must be 0 or 1")
        else:
            if not isinstance(value, str) or "\x00" in value:
                raise SettingsError(f"{key} must be a text value")
            if key != "Gtk/ColorScheme" and (not value.strip() or "\n" in value or "\r" in value):
                raise SettingsError(f"{key} must be a non-empty, single-line value")
            if key == "Xft/HintStyle" and value not in {"hintnone", "hintslight", "hintmedium", "hintfull"}:
                raise SettingsError("Xft/HintStyle must be hintnone, hintslight, hintmedium, or hintfull")
            if key == "Xft/RGBA" and value not in {"none", "rgb", "bgr", "vrgb", "vbgr"}:
                raise SettingsError("Xft/RGBA must be none, rgb, bgr, vrgb, or vbgr")
            if key == "Gtk/ColorScheme" and not re.fullmatch(
                    r"selected_bg_color:#[0-9a-fA-F]{6,8}\nselected_fg_color:#[0-9a-fA-F]{6,8}", value):
                raise SettingsError("Gtk/ColorScheme must define selected background and foreground colors")


def _format_value(value: object) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return f'"{escaped}"'


def update_xsettings_text(text: str, settings: dict[str, object]) -> str:
    """Update only managed entries, preserving comments and unknown settings."""
    _validate_settings(settings)
    lines = text.splitlines(keepends=True)
    seen: set[str] = set()
    output: list[str] = []
    for line in lines:
        body = line.rstrip("\r\n")
        ending = line[len(body):]
        match = _LINE.match(body)
        if not match:
            output.append(line)
            continue
        indent, key, separator, raw = match.groups()
        if key not in settings:
            output.append(line)
            continue
        _, suffix = _split_comment(raw)
        output.append(f"{indent}{key}{separator}{_format_value(settings[key])}{suffix}{ending}")
        seen.add(key)
    missing = [key for key in settings if key not in seen]
    if missing:
        if output and not output[-1].endswith(("\n", "\r")):
            output[-1] += "\n"
        for key in missing:
            output.append(f"{key} {_format_value(settings[key])}\n")
    return "".join(output)


def _split_ini_comment(raw: str) -> tuple[str, str]:
    for index, char in enumerate(raw):
        if char in "#;" and index > 0 and raw[index - 1].isspace():
            value = raw[:index].rstrip()
            return value, raw[len(value):]
    return raw.rstrip(), raw[len(raw.rstrip()):]


def parse_gtk_settings(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    section = ""
    for line in text.splitlines():
        section_match = _INI_SECTION.match(line)
        if section_match:
            section = section_match.group(1).strip().lower()
            continue
        if section != "settings":
            continue
        match = _INI_KEY.match(line)
        if match:
            _, key, _, value, _ = match.groups()
            value, _ = _split_ini_comment(value)
            values[key.strip().lower()] = value.strip()
    return values


def settings_from_files(xsettings_text: str, gtk_text: str = "") -> dict[str, object]:
    """Merge xsettingsd values over the GTK3 file, then the documented defaults."""
    settings = dict(DEFAULTS)
    gtk_values = parse_gtk_settings(gtk_text)
    for key, ini_key in GTK_INI_KEYS.items():
        if ini_key not in gtk_values:
            continue
        raw = gtk_values[ini_key]
        try:
            if key == "Gtk/ToolbarStyle":
                value = TOOLBAR_STYLE_IDS.get(raw.upper())
                if value is not None:
                    settings[key] = value
            elif key in INTEGER_SETTINGS:
                settings[key] = int(raw, 10) if raw.lower() not in {"true", "false"} else int(raw.lower() == "true")
            else:
                settings[key] = raw
        except ValueError:
            pass
    parsed = parse_xsettings(xsettings_text)
    for key in DEFAULTS:
        if key in parsed:
            settings[key] = parsed[key]
    _validate_settings(settings)
    return settings


def _gtk_ini_values(settings: dict[str, object]) -> dict[str, str]:
    result: dict[str, str] = {}
    for xsettings_key, ini_key in GTK_INI_KEYS.items():
        value = settings[xsettings_key]
        if xsettings_key == "Gtk/ToolbarStyle":
            result[ini_key] = TOOLBAR_STYLES[int(value)]
        elif xsettings_key in INTEGER_SETTINGS:
            if xsettings_key in {"Gtk/ButtonImages", "Gtk/MenuImages", "Gtk/EnableAnimations",
                                 "Gtk/EnableEventSounds", "Gtk/EnableInputFeedbackSounds"}:
                result[ini_key] = "true" if int(value) else "false"
            else:
                result[ini_key] = str(int(value))
        else:
            result[ini_key] = str(value)
    return result


def update_gtk_settings_text(text: str, settings: dict[str, object]) -> str:
    """Synchronize GTK3 appearance settings without discarding other preferences."""
    _validate_settings(settings)
    desired = _gtk_ini_values(settings)
    lines = text.splitlines(keepends=True)
    section = ""
    found_section = False
    insert_at: int | None = None
    found_keys: set[str] = set()
    output: list[str] = []
    for line in lines:
        body = line.rstrip("\r\n")
        ending = line[len(body):]
        section_match = _INI_SECTION.match(body)
        if section_match:
            if section == "settings" and insert_at is None:
                insert_at = len(output)
            section = section_match.group(1).strip().lower()
            if section == "settings":
                found_section = True
            output.append(line)
            continue
        if section == "settings":
            match = _INI_KEY.match(body)
            if match:
                indent, key, separator, value, trailing = match.groups()
                normalized_key = key.strip().lower()
                if normalized_key in desired:
                    _, comment = _split_ini_comment(value)
                    output.append(f"{indent}{key}{separator}{desired[normalized_key]}{comment}{trailing}{ending}")
                    found_keys.add(normalized_key)
                    continue
        output.append(line)
    if found_section and insert_at is None:
        insert_at = len(output)
    missing = [key for key in desired if key not in found_keys]
    if not found_section:
        if output and not output[-1].endswith(("\n", "\r")):
            output[-1] += "\n"
        output.extend(["[Settings]\n", *[f"{key}={value}\n" for key, value in desired.items()]])
    elif missing:
        assert insert_at is not None
        additions = [f"{key}={desired[key]}\n" for key in missing]
        output[insert_at:insert_at] = additions
    return "".join(output)


def _resolved_write_path(path: Path) -> Path:
    return path.expanduser().resolve(strict=False)


def atomic_write(path: Path, text: str) -> None:
    """Atomically write through Stow symlinks instead of replacing the link."""
    destination = _resolved_write_path(Path(path))
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        mode = stat.S_IMODE(destination.stat().st_mode)
    except FileNotFoundError:
        mode = 0o600
    fd, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, destination)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _default_config_path() -> Path | None:
    candidates = [Path.home() / ".xsettingsd"]
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    candidates.append(config_home / "xsettingsd/xsettingsd.conf")
    config_dirs = os.environ.get("XDG_CONFIG_DIRS", "/etc/xdg").split(":")
    candidates.extend(Path(directory) / "xsettingsd/xsettingsd.conf" for directory in config_dirs)
    return next((path.resolve() for path in candidates if path.is_file() and os.access(path, os.R_OK)), None)


def _process_pids(config_path: Path) -> list[int]:
    proc = Path("/proc")
    pids: list[int] = []
    expected_display = os.environ.get("DISPLAY")
    for entry in proc.iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            if entry.stat().st_uid != os.getuid():
                continue
            if (entry / "comm").read_text(encoding="ascii").strip() != "xsettingsd":
                continue
            argv = [item.decode("utf-8", errors="replace") for item in
                    (entry / "cmdline").read_bytes().split(b"\0") if item]
            configured = None
            for index, argument in enumerate(argv):
                if argument in {"-c", "--config"} and index + 1 < len(argv):
                    configured = Path(argv[index + 1]).expanduser().resolve()
                    break
                if argument.startswith("--config="):
                    configured = Path(argument.split("=", 1)[1]).expanduser().resolve()
                    break
            if configured is not None and configured != config_path:
                continue
            if configured is None and _default_config_path() != config_path:
                continue
            if expected_display:
                environment = (entry / "environ").read_bytes().split(b"\0")
                display = next((item.split(b"=", 1)[1].decode("utf-8", errors="replace")
                                for item in environment if item.startswith(b"DISPLAY=")), None)
                if display and display != expected_display:
                    continue
            pids.append(int(entry.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
    return pids


def restart_xsettingsd(config_path: Path) -> int:
    """Replace this user's xsettingsd process, leaving other desktop services alone."""
    launch_path = Path(config_path).expanduser().absolute()
    config_path = launch_path.resolve(strict=True)
    binary = shutil_which("xsettingsd")
    if binary is None:
        raise SettingsError("xsettingsd is not installed or is not on PATH")
    old_pids = _process_pids(config_path)
    for pid in old_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2.0
    while _process_pids(config_path) and time.monotonic() < deadline:
        time.sleep(0.04)
    remaining = _process_pids(config_path)
    if remaining:
        raise SettingsError(f"xsettingsd did not stop cleanly (PID {remaining[0]})")
    with tempfile.TemporaryFile() as error_log:
        process = subprocess.Popen(
            [binary, "-c", str(launch_path)], stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=error_log, start_new_session=True,
            close_fds=True,
        )
        deadline = time.monotonic() + 0.4
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        if process.poll() is not None:
            error_log.seek(0)
            detail = error_log.read().decode("utf-8", errors="replace").strip()
            raise SettingsError(detail or f"xsettingsd exited with status {process.returncode}")
    return process.pid


def shutil_which(command: str) -> str | None:
    """Small local wrapper to keep subprocess discovery easy to replace in tests."""
    from shutil import which
    return which(command)


def _restore_file(path: Path, previous: str | None) -> None:
    destination = _resolved_write_path(path)
    if previous is None:
        try:
            destination.unlink()
        except FileNotFoundError:
            pass
    else:
        atomic_write(path, previous)


def apply_settings(
    xsettings_path: Path,
    gtk_settings_path: Path,
    settings: dict[str, object],
    restart: Callable[[Path], object] = restart_xsettingsd,
) -> None:
    """Persist both settings files and restart xsettingsd, rolling back on failure."""
    _validate_settings(settings)
    xsettings_path = Path(xsettings_path).expanduser()
    gtk_settings_path = Path(gtk_settings_path).expanduser()
    had_xsettings = xsettings_path.exists()
    had_gtk_settings = gtk_settings_path.exists()
    old_xsettings = xsettings_path.read_text(encoding="utf-8") if had_xsettings else ""
    old_gtk = gtk_settings_path.read_text(encoding="utf-8") if had_gtk_settings else ""
    new_xsettings = update_xsettings_text(old_xsettings, settings)
    new_gtk = update_gtk_settings_text(old_gtk, settings)
    restart_attempted = False
    try:
        atomic_write(xsettings_path, new_xsettings)
        atomic_write(gtk_settings_path, new_gtk)
        restart_attempted = True
        restart(xsettings_path)
    except Exception as exc:
        rollback_errors: list[str] = []
        try:
            _restore_file(xsettings_path, old_xsettings if had_xsettings else None)
        except Exception as rollback_exc:
            rollback_errors.append(f"xsettingsd.conf: {rollback_exc}")
        try:
            _restore_file(gtk_settings_path, old_gtk if had_gtk_settings else None)
        except Exception as rollback_exc:
            rollback_errors.append(f"GTK settings.ini: {rollback_exc}")
        if restart_attempted:
            try:
                restart(xsettings_path)
            except Exception as rollback_exc:
                rollback_errors.append(f"could not restart with restored settings: {rollback_exc}")
        detail = f"Could not apply settings: {exc}"
        if rollback_errors:
            detail += "\nRollback warning: " + "; ".join(rollback_errors)
        raise SettingsError(detail) from exc
