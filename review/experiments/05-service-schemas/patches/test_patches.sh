#!/bin/bash
# Run the hand-written cases and the crash cases on the patched engine
# (SCH-1 + SCH-4 + SCH-6 applied in a throwaway copy, built there).
#   patches/test_patches.sh /tmp/claude-0/halean-copies/05-service-schemas-1
COPY=$1; HERE=$(cd "$(dirname "$0")/.." && pwd); PY=/opt/havenv/bin/python
export HALEAN_BIN=$COPY/.lake/build/bin
cd "$HERE/harness"
for d in cases cases_crash/sch1 cases_crash/sch1b; do
  l=$(echo $d | tr / -)
  rm -f "$HERE/patches/patched-$l.jsonl"
  SCH_CASES="$HERE/$d" SCH_RECORD="$HERE/patches/patched-$l.jsonl" $PY -m pytest test_services.py -p no:cacheprovider -q -rf --tb=line \
     > "$HERE/patches/patched-$l.log" 2>&1
  touch "$HERE/patches/patched-$l.jsonl"
  echo "patched $d: $(tail -1 "$HERE/patches/patched-$l.log")"
  grep "^FAILED" "$HERE/patches/patched-$l.log" | cut -c1-120
done
$PY "$HERE/gen/classify.py" "$HERE"/patches/patched-*.jsonl > "$HERE/patches/patched-classify.log"; cat "$HERE/patches/patched-classify.log" | cut -c1-200
