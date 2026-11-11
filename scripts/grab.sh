#!/bin/sh
# grab.sh <out.png> [WxH+X+Y] - capture the game's OWN rendered frame, not the desktop.
#
# The Vulkan backend can dump the composited offscreen target straight off the
# GPU (libs/video/rsx_vulkan_backend.c: PS3RECOMP_VK_DUMP=<path.ppm>,
# PS3RECOMP_VK_DUMP_EVERY=n).  That is per-window, per-frame, and immune to
# whatever else is on screen, so a run's screenshots are correct even while the
# desktop is in use.  A PPM lands at <out>.ppm; this copies the newest one next
# to <out> and converts it.
#
#   PS3RECOMP_VK_DUMP=logs/vk-frame.ppm PS3RECOMP_VK_DUMP_EVERY=60 ./build-master/tokyojungle &
#   scripts/grab.sh logs/shot-m1.png
#
# With no dump in flight it falls back to a centred desktop crop (spectacle),
# geometry WxH+X+Y or W=/H= (SDL_WINDOWPOS_CENTERED puts the window mid-desktop).
set -u
# This shell often starts with no XAUTHORITY; the X server's own command line
# carries the file it was started with, so read it from there.
if [ -z "${XAUTHORITY:-}" ] || [ ! -r "${XAUTHORITY:-/nonexistent}" ]; then
    XAUTHORITY=$(ps -eo args | sed -n 's/.*-auth \([^ ]*\).*/\1/p' | head -1)
    [ -r "${XAUTHORITY:-/nonexistent}" ] && export XAUTHORITY
fi
out="${1:-logs/grab.png}"
geom="${2:-}"
w="${W:-1280}"; h="${H:-720}"

# 1) GPU dump from the run in flight, if one is running.
ppm=$(ls -t logs/*frame*.ppm logs/vk-frame.ppm 2>/dev/null | head -1)
if [ -n "${PS3RECOMP_VK_DUMP:-}" ] && [ -f "$PS3RECOMP_VK_DUMP" ]; then ppm="$PS3RECOMP_VK_DUMP"; fi
if [ -n "$ppm" ] && [ -f "$ppm" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$ppm") ))
    if [ "$age" -le "${MAX_AGE:-90}" ]; then
        cp "$ppm" "${out%.png}.ppm"
        magick "${out%.png}.ppm" -resize "${MAXW:-900}x" "${out%.png}-s.png" && \
            echo "grab.sh: GPU frame $ppm (${age}s old) -> ${out%.png}-s.png" && exit 0
    fi
fi

# 2) Fallback: composited desktop crop (only good while nothing covers the window).
full="${out%.png}-full.png"
DISPLAY=:0 spectacle -b -n -o "$full" >/dev/null 2>&1 || {
    echo "grab.sh: spectacle failed" >&2; exit 1; }
dsize=$(magick identify -format "%wx%h" "$full" 2>/dev/null)
dw=${dsize%x*}; dh=${dsize#*x}
[ -n "$dw" ] || { echo "grab.sh: cannot read $full" >&2; exit 1; }
if [ -z "$geom" ]; then
    x=$(( (dw - w) / 2 )); y=$(( (dh - h) / 2 )); [ $x -lt 0 ] && x=0; [ $y -lt 0 ] && y=0
    geom="${w}x${h}+${x}+${y}"
fi
magick "$full" -crop "$geom" +repage -resize "${MAXW:-900}x" "${out%.png}-s.png"
echo "grab.sh: desktop $dsize, crop $geom -> ${out%.png}-s.png (full: $full)"
