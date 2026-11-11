#!/bin/sh
# buildlog.sh <build-log...> - compact build summary: failures, real warnings,
# and the lifter's own WARNING: lines (the memaccess memset/memcpy flood is noise).
for f in "$@"; do
  [ -f "$f" ] || continue
  echo "== $f"
  grep -a "FAILED\|error:" "$f" | sed 's/^\(.\{140\}\).*/\1…/' | sort -u | head -12
  grep -a "warning:" "$f" | grep -av "Wclass-memaccess" |
    sed 's/.*warning: //;s/ \[-W.*//' | sort | uniq -c | sort -rn | head -10
  grep -a "^  WARNING:\|^WARNING:" "$f" | sort | uniq -c | sort -rn | head -10
  tail -1 "$f" | cut -c1-90
done
