#!/bin/bash
# One full run: hand-written cases, the two crash cases, and the random cases.
#   ./run_all.sh <run-number> <seedA> <seedB> <seedWarm>
# Logs go to logs/run<N>-*.log, recorded differences to logs/run<N>-*.jsonl.
# HALEAN_BIN selects the engine directory (default: the reviewed build).
set -u
N=$1; SA=$2; SB=$3; SW=$4
HERE=$(cd "$(dirname "$0")" && pwd)
PY=/opt/havenv/bin/python
cd "$HERE/harness"
run() {  # run <label> <case dir>
  rm -f "$HERE/logs/run$N-$1.jsonl"
  SCH_CASES="$2" SCH_RECORD="$HERE/logs/run$N-$1.jsonl" $PY -m pytest test_services.py -p no:cacheprovider -q -rf \
    > "$HERE/logs/run$N-$1.log" 2>&1
  echo "run$N-$1: $(tail -1 "$HERE/logs/run$N-$1.log")"
  touch "$HERE/logs/run$N-$1.jsonl"
}
run hand "$HERE/cases"
# shipped assertion mode (no record) on the hand-written cases: the verdict as the shipped harness gives it
SCH_CASES="$HERE/cases" $PY -m pytest test_services.py -p no:cacheprovider -q -rf > "$HERE/logs/run$N-hand-strict.log" 2>&1
echo "run$N-hand-strict: $(tail -1 "$HERE/logs/run$N-hand-strict.log")"
run crash-sch1 "$HERE/cases_crash/sch1"
run crash-sch1b "$HERE/cases_crash/sch1b"
OUT="$HERE/gen/out/run$N"; rm -rf "$OUT"; mkdir -p "$OUT/a" "$OUT/b" "$OUT/warm"
$PY "$HERE/gen/gen_random.py" --seed $SA --schemas 1000 --data 12 --out "$OUT/a/seed-$SA.yaml" | tee "$HERE/logs/run$N-gen.log"
$PY "$HERE/gen/gen_random.py" --seed $SB --schemas 1000 --data 12 --out "$OUT/b/seed-$SB.yaml" | tee -a "$HERE/logs/run$N-gen.log"
$PY "$HERE/gen/gen_random.py" --seed $SW --schemas 60 --data 70 --out "$OUT/warm/seed-$SW.yaml" | tee -a "$HERE/logs/run$N-gen.log"
run random-a "$OUT/a"
run random-b "$OUT/b"
run random-warm "$OUT/warm"
$PY "$HERE/gen/classify.py" "$HERE"/logs/run$N-hand.jsonl "$HERE"/logs/run$N-crash-sch1.jsonl "$HERE"/logs/run$N-crash-sch1b.jsonl \
  "$HERE"/logs/run$N-random-a.jsonl "$HERE"/logs/run$N-random-b.jsonl "$HERE"/logs/run$N-random-warm.jsonl \
  > "$HERE/logs/run$N-classify.log" 2>&1
cat "$HERE/logs/run$N-classify.log" | cut -c1-400
