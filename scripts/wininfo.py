#!/usr/bin/env python
"""Find the mapped ps3recomp SDL2 window and print its id + geometry.

  scripts/wininfo.py            -> "0x3800005 1920x1080+960+1440 ps3recomp"
  scripts/wininfo.py --id       -> just the window id (for `import -window`)

python-xlib API notes (this build): get_attributes() (not
get_window_attributes), get_wm_name(), _NET_WM_NAME for UTF-8 titles,
X.IsViewable for map_state.
"""
import sys
from Xlib import display, X

want_id = "--id" in sys.argv
want = "ps3recomp"
for a in sys.argv[1:]:
    if a.startswith("--name="):
        want = a.split("=", 1)[1]

d = display.Display()
net = d.intern_atom("_NET_WM_NAME")


def title(w):
    nm = w.get_wm_name()
    if nm:
        return str(nm)
    p = w.get_property(net, net, 0, 256)
    if p and p.value:
        try:
            return p.value.decode(errors="replace")
        except AttributeError:
            return str(p.value)
    return None


for c in d.screen().root.query_tree().children:
    try:
        wa = c.get_attributes()
        g = c.get_geometry()
    except Exception:
        continue
    if wa.map_state != X.IsViewable:
        continue
    t = title(c)
    if not t or want not in t:
        continue
    if want_id:
        print(hex(c.id))
    else:
        print(f"{hex(c.id)} {g.width}x{g.height}+{g.x}+{g.y} {t!r}")
    sys.exit(0)
sys.exit(1)
