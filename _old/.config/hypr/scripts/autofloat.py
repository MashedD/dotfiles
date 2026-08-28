#!/usr/bin/env python3
"""autofloat: float new windows unless tiling exceptions.
Workaround for broken legacy window rules in Hyprland 0.55."""

import json
import os
import socket
import subprocess
import re
import sys
import time

TILING_CLASSES = re.compile(r"^(kitty|firefox)$")
FORCE_FLOAT_CLASSES = re.compile(r"^(q2manager|Q2Manager)$")


def get_socket_path():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    uid = os.getuid()
    base = f"/run/user/{uid}/hypr"
    if sig:
        path = f"{base}/{sig}/.socket2.sock"
        if os.path.exists(path):
            return path
    if os.path.isdir(base):
        for entry in sorted(os.listdir(base), reverse=True):
            path = f"{base}/{entry}/.socket2.sock"
            if os.path.exists(path):
                return path
    return None


def hyprctl(args, timeout=3):
    try:
        subprocess.run(["hyprctl"] + args, timeout=timeout, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def hyprctl_json(args, timeout=3):
    try:
        proc = subprocess.run(["hyprctl", "-j"] + args, timeout=timeout, check=True, capture_output=True, text=True)
        return json.loads(proc.stdout)
    except Exception:
        return None


def get_client(addr):
    clients = hyprctl_json(["clients"])
    if not clients:
        return None
    needle = "0x" + addr.lower().removeprefix("0x")
    for client in clients:
        if client.get("address", "").lower() == needle:
            return client
    return None


def center_client(client):
    monitors = hyprctl_json(["monitors"])
    if not monitors:
        return

    monitor_id = client.get("monitor")
    monitor = next((mon for mon in monitors if mon.get("id") == monitor_id), None)
    if not monitor:
        return

    left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
    work_x = monitor["x"] + left
    work_y = monitor["y"] + top
    work_w = monitor["width"] - left - right
    work_h = monitor["height"] - top - bottom
    win_w, win_h = client.get("size", [0, 0])
    x = work_x + max((work_w - win_w) // 2, 0)
    y = work_y + max((work_h - win_h) // 2, 0)
    hyprctl(["dispatch", "movewindowpixel", f"exact {x} {y},address:{client['address']}"])


def float_and_center(addr):
    for _ in range(10):
        hyprctl(["dispatch", "setfloating", f"address:{addr}"])
        time.sleep(0.1)
        client = get_client(addr)
        if client and client.get("floating"):
            center_client(client)
            return


def enforce_force_float():
    clients = hyprctl_json(["clients"])
    if not clients:
        return
    for client in clients:
        cls = client.get("class", "")
        title = client.get("title", "")
        if not (FORCE_FLOAT_CLASSES.match(cls) or FORCE_FLOAT_CLASSES.match(title)):
            continue
        if client.get("floating"):
            continue
        float_and_center(client["address"])


def main():
    sock_path = get_socket_path()
    if not sock_path:
        sys.exit(1)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(sock_path)
    sock.settimeout(1)

    buf = ""
    while True:
        try:
            data = sock.recv(4096)
        except socket.timeout:
            enforce_force_float()
            continue
        except OSError:
            break
        if not data:
            break
        buf += data.decode()
        while "\n" in buf:
            line, buf = buf.split("\n", 1)
            if not line.startswith("openwindow>>"):
                continue
            parts = line[len("openwindow>>"):].split(",", 3)
            if len(parts) < 3:
                continue
            addr, cls = parts[0], parts[2]
            if TILING_CLASSES.match(cls):
                continue
            float_and_center(addr)


if __name__ == "__main__":
    main()
