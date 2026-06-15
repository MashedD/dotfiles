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
        subprocess.run(["hyprctl"] + args, timeout=timeout)
    except Exception:
        pass


def main():
    sock_path = get_socket_path()
    if not sock_path:
        sys.exit(1)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(sock_path)

    buf = ""
    while True:
        try:
            data = sock.recv(4096)
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
            hyprctl(["dispatch", "togglefloating", f"address:{addr}"])
            time.sleep(0.05)
            hyprctl(["dispatch", "centerwindow", f"address:{addr}"])


if __name__ == "__main__":
    main()
