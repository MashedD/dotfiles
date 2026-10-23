"""Bundled desktop profiles. Mutable choices stay outside the Stow package."""
from __future__ import annotations

import json
from pathlib import Path
import re
import shutil
import subprocess
from typing import Callable

from .settings import atomic_write, apply_settings, restart_xsettingsd, update_gtk_settings_text

PROFILES = (("aero", "Win98 / Aero"), ("night-circuit", "Night Circuit (cyberpunk)"))
BEGIN = "/* BEGIN desktop-control-center theme */"
END = "/* END desktop-control-center theme */"


def validate_profile(profile: str) -> str:
    if profile not in dict(PROFILES):
        raise ValueError(f"Unknown desktop theme: {profile}")
    return profile


def read_profile(state_home: Path) -> str:
    path = Path(state_home) / "awesome/theme"
    return validate_profile(path.read_text().strip()) if path.exists() else "aero"


def profile_settings(profile: str, current: dict[str, object]) -> dict[str, object]:
    validate_profile(profile)
    return {**current, "Net/ThemeName": "Adwaita-dark" if profile == "night-circuit" else "Adwaita",
            "Gtk/EnableAnimations": int(profile == "aero")}


def stylesheet(original: str, asset: Path | None) -> str:
    """Manage only our marked import, leaving custom CSS intact and higher priority."""
    if original.count(BEGIN) != original.count(END) or original.count(BEGIN) > 1:
        raise ValueError("Malformed desktop theme block in gtk.css; refusing to overwrite it")
    if BEGIN in original:
        start, finish = original.index(BEGIN), original.index(END) + len(END)
        if original.index(END) < start:
            raise ValueError("Malformed desktop theme block in gtk.css")
        if original[finish:finish + 1] == "\n":
            finish += 1
        original = original[:start] + original[finish:]
    if asset is None:
        return original
    # Path.as_uri escapes quotes and other CSS-sensitive characters.
    return f'{BEGIN}\n@import url("{asset.absolute().as_uri()}");\n{END}\n' + original


class DesktopPreferences:
    """Optional GNOME/portal dark hint; never start a bus or a desktop daemon."""
    schema = "org.gnome.desktop.interface"

    def __init__(self) -> None:
        self.available = bool(shutil.which("gsettings"))

    def _run(self, *args: str) -> str:
        return subprocess.check_output(["gsettings", *args], text=True, stderr=subprocess.PIPE,
                                       timeout=5).strip()

    def snapshot(self) -> dict[str, str]:
        if not self.available or self.schema not in self._run("list-schemas").splitlines():
            return {}
        keys = set(self._run("list-keys", self.schema).splitlines())
        return {key: self._run("get", self.schema, key)
                for key in ("color-scheme", "gtk-theme", "enable-animations") if key in keys}

    def apply(self, profile: str, settings: dict[str, object], previous: dict[str, str]) -> None:
        values = {"color-scheme": "prefer-dark" if profile == "night-circuit" else "default",
                  "gtk-theme": str(settings["Net/ThemeName"]),
                  "enable-animations": "true" if settings["Gtk/EnableAnimations"] else "false"}
        for key in previous:
            # gsettings accepts a plain string for string keys, with no shell expansion.
            self._run("set", self.schema, key, values[key])

    def restore(self, previous: dict[str, str]) -> None:
        for key, value in previous.items():
            self._run("set", self.schema, key, value)


def apply_profile(profile: str, settings: dict[str, object], *, config_home: Path,
                  data_home: Path, state_home: Path,
                  restart: Callable[[Path], object] = restart_xsettingsd,
                  preferences: DesktopPreferences | None = None) -> None:
    """Apply files/settings transactionally; the UI requests Awesome restart on success.

    Wallpaper changes only when switching profiles. Each profile remembers the last
    wallpaper used while it was active. No sidebar or application state is touched.
    """
    validate_profile(profile)
    config_home, data_home, state_home = map(Path, (config_home, data_home, state_home))
    old_profile = read_profile(state_home)
    xsettings = config_home / "xsettingsd/xsettingsd.conf"
    gtk3 = config_home / "gtk-3.0/settings.ini"
    gtk4 = config_home / "gtk-4.0/settings.ini"
    selection = state_home / "awesome/theme"
    wallpaper = state_home / "awesome/wallpaper"
    history_path = state_home / "awesome/theme-wallpapers.json"
    paths = [xsettings, gtk3, gtk4, selection, wallpaper, history_path,
             *(config_home / f"gtk-{version}.0/gtk.css" for version in (3, 4))]
    previous = {path: path.read_text() if path.exists() else None for path in paths}
    history = json.loads(previous[history_path] or "{}")
    if not isinstance(history, dict) or not all(isinstance(k, str) and isinstance(v, str)
                                               for k, v in history.items()):
        raise ValueError("Invalid theme wallpaper history")
    updates = {}
    for version in (3, 4):
        asset = data_home / f"desktop-themes/night-circuit/gtk-{version}.0.css"
        if profile == "night-circuit" and not asset.is_file():
            raise ValueError(f"Missing theme asset: {asset}; apply the Stow package first")
        path = config_home / f"gtk-{version}.0/gtk.css"
        updates[path] = stylesheet(previous[path] or "", asset if profile == "night-circuit" else None)
    # Respect advanced GTK choices made after choosing the preset.
    gtk4_keys = {"gtk-theme-name", "gtk-icon-theme-name", "gtk-font-name", "gtk-cursor-theme-name",
                 "gtk-cursor-theme-size", "gtk-enable-animations"}
    gtk4_text = update_gtk_settings_text(previous[gtk4] or "", settings, gtk_keys=gtk4_keys)
    prefer_dark = "true" if profile == "night-circuit" else "false"
    # Preserve other sections and do not put removed GTK3 properties into GTK4.
    lines, in_settings, insert_at, found = [], False, None, False
    key = "gtk-application-prefer-dark-theme"
    for line in gtk4_text.splitlines(keepends=True):
        section = re.match(r"\s*\[([^]]+)\]", line)
        if section:
            in_settings = section[1].strip().lower() == "settings"
            if in_settings and insert_at is None:
                insert_at = len(lines) + 1
        if in_settings and re.match(rf"\s*{key}\s*=", line):
            line, found = f"{key}={prefer_dark}\n", True
        lines.append(line)
    if not found:
        assert insert_at is not None
        lines.insert(insert_at, f"{key}={prefer_dark}\n")
    updates[gtk4] = "".join(lines)
    updates[selection] = profile + "\n"
    if profile != old_profile:
        current = (previous[wallpaper] or "").strip()
        if current:
            history[old_profile] = current
        fallback = data_home / "wallpapers" / ("night-circuit.png" if profile == "night-circuit"
                                               else "aurora-cabin.png")
        selected = Path(history.get(profile, str(fallback))).expanduser()
        if not selected.is_file():
            selected = fallback
        if not selected.is_file():
            raise ValueError(f"Missing wallpaper: {selected}")
        updates[wallpaper] = str(selected) + "\n"
        updates[history_path] = json.dumps(history, indent=2) + "\n"
    preferences = preferences if preferences is not None else DesktopPreferences()
    desktop_previous = preferences.snapshot()
    restart_attempted = False
    try:
        for path, text in updates.items():
            # Do not create an empty stylesheet on profiles that never used an overlay.
            if text or previous[path] is not None:
                atomic_write(path, text)
        restart_attempted = True
        apply_settings(xsettings, gtk3, settings, restart=restart)
        preferences.apply(profile, settings, desktop_previous)
    except Exception as exc:
        errors = []
        for path, text in previous.items():
            try:
                if text is None:
                    path.resolve().unlink(missing_ok=True)
                else:
                    atomic_write(path, text)
            except Exception as rollback_error:
                errors.append(f"{path}: {rollback_error}")
        try:
            preferences.restore(desktop_previous)
        except Exception as rollback_error:
            errors.append(f"desktop preferences: {rollback_error}")
        if restart_attempted:
            try:
                restart(xsettings)
            except Exception as rollback_error:
                errors.append(f"xsettingsd: {rollback_error}")
        detail = f"Could not apply desktop theme: {exc}"
        if errors:
            detail += "\nRollback warnings: " + "; ".join(errors)
        raise RuntimeError(detail) from exc
