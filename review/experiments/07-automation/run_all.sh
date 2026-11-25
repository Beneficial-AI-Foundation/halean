#!/usr/bin/env bash
# Full run: ./run_all.sh <run-label>      e.g. ./run_all.sh run1
#   1. hand-written cases (cases/)                         -> logs/<label>-cases.log
#   2. random scenarios, seeds below, generated afresh     -> logs/<label>-random-<seed>.log
# Results of both sides are dumped to logs/<label>-dump/<set>/ (JSON per case); a summary of the
# failing cases is written to logs/<label>-summary.txt. HALEAN_BIN selects another engine build.
set -u
cd "$(dirname "$0")"
R=${1:?run label}
PY=/opt/havenv/bin/python
ENGINE=${HALEAN_BIN:-/home/user/halean/.lake/build/bin}/halean-automation
SEEDS="101:300:default 202:300:default 303:200:modes"
: > logs/$R-summary.txt
AUT_CASES=$PWD/cases AUT_DUMP=$PWD/logs/$R-dump/cases ./run.sh $R-cases | tee -a logs/$R-summary.txt
for spec in $SEEDS; do
  IFS=: read seed count profile <<< "$spec"
  out=gen/out/$R-s$seed
  rm -rf $out
  $PY gen/gen_scenarios.py --seed $seed --count $count --profile $profile --out $out --engine $ENGINE >> logs/$R-gen.log 2>&1
  AUT_CASES=$PWD/$out AUT_DUMP=$PWD/logs/$R-dump/s$seed ./run.sh $R-random-$seed | tee -a logs/$R-summary.txt
done
for d in logs/$R-dump/*/; do
  echo "== $d" >> logs/$R-summary.txt
  $PY triage.py $d >> logs/$R-summary.txt
done
grep -hE "^(FAILED|ERROR) " logs/$R-cases.log logs/$R-random-*.log | sed 's/ - .*//' | sort > logs/$R-failing.txt
wc -l logs/$R-failing.txt
