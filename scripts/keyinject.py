#!/usr/bin/env python3
"""Send keys to the running game window (X11 XSendEvent -> SDL2).

    .venv/bin/python scripts/keyinject.py space return
    .venv/bin/python scripts/keyinject.py --window "Tokyo Jungle" --repeat 6 space

Names are X keysym names (space, Return, Up, Down, a, Escape). SDL2's
keyboard state map drives cellPadGetDigitalData in the null/GL backend, so
this is how the title screen gets driven in scripted runs.
"""
import argparse
import time

from Xlib import X, display
from Xlib.ext import xtest
from Xlib import XK

MODS = {"shift": XK.XK_Shift_L, "ctrl": XK.XK_Control_L, "alt": XK.XK_Alt_L}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--window", default="ps3recomp", help="window title substring")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--delay", type=float, default=1.0, help="seconds between keys")
    ap.add_argument("keys", nargs="+", help="keysym names")
    a = ap.parse_args()

    d = display.Display()
    root = d.screen().root
    win = None
    def scan(w):
        nonlocal win
        for c in w.query_tree().children:
            if win:
                return
            try:
                if a.window.lower() in (c.get_wm_name() or "").lower():
                    win = c
                    return
            except Exception:
                continue
            scan(c)
    scan(root)
    if not win:
        raise SystemExit(f"no window matching {a.window!r}")
    win.warp_pointer(640, 400)
    win.set_input_focus(X.RevertToParent, X.CurrentTime)
    d.flush()

    for _ in range(a.repeat):
        for name in a.keys:
            kc = d.keysym_to_keycode(XK.string_to_keysym(name))
            if not kc:
                print(f"no keycode for {name}")
                continue
            xtest.fake_input(d, X.KeyPress, kc, destination=win)
            xtest.fake_input(d, X.KeyRelease, kc, destination=win)
            d.flush()
            print(f"sent {name}")
            time.sleep(a.delay)


if __name__ == "__main__":
    main()
