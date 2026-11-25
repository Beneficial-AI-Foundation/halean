#!/bin/sh
# run_all.sh <run-number> [<seed> ...]: one full run against the build in HALEAN_BIN (default: the
# unpatched /home/user/halean/.lake/build/bin). Logs go to logs/run<n>-*.log.
#   hand-written cases (cases/*.yaml)          -> logs/run<n>-hand.log
#   config matrix (config/matrix.yaml)         -> logs/run<n>-matrix.log
#   random cases per seed (gen/out/seed<seed>) -> logs/run<n>-random-seed<seed>.log, ...-triage.txt
# The random cases are generated when gen/out/seed<seed> does not exist (300 per seed).
set -u
cd "$(dirname "$0")"
N=$1; shift
PY=/opt/havenv/bin/python
unset HALEAN_CASES
$PY -m pytest harness/test_scripts.py -p no:cacheprovider -q --tb=short > logs/run$N-hand.log 2>&1
tail -1 logs/run$N-hand.log
$PY -m pytest harness/test_config_matrix.py -p no:cacheprovider -q --tb=short -s > logs/run$N-matrix.log 2>&1
tail -1 logs/run$N-matrix.log
for SEED in "$@"; do
  [ -d gen/out/seed$SEED ] || $PY gen/gen_scripts.py $SEED 300 gen/out/seed$SEED
  HALEAN_CASES=gen/out/seed$SEED $PY -m pytest harness/test_scripts.py -p no:cacheprovider -q --tb=short \
    > logs/run$N-random-seed$SEED.log 2>&1
  tail -1 logs/run$N-random-seed$SEED.log
  $PY gen/triage.py logs/run$N-random-seed$SEED.log gen/out/seed$SEED -v > logs/run$N-random-seed$SEED-triage.txt 2>&1
  sed -n '/^signatures/,$p' logs/run$N-random-seed$SEED-triage.txt
done
