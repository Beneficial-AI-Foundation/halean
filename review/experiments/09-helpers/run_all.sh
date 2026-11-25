#!/bin/bash
# run_all.sh <run-number> <seed>
# One full run: the hand-written cases of cases/ and the random cases of seed <seed>
# (generated into gen/seed-<seed>/), real HA against halean-helpers ($HALEAN_BIN,
# default /home/user/halean/.lake/build/bin). Logs: logs/run<N>-handwritten.log,
# logs/run<N>-random-seed<seed>.log and their .classified.txt (gen/classify.py).
set -u
N=$1; SEED=$2
cd "$(dirname "$0")"
PY=/opt/havenv/bin/python
$PY gen/gen_random.py --seed $SEED --out gen/seed-$SEED > logs/run$N-gen-seed$SEED.txt
(cd gen/seed-$SEED && sha256sum *.yaml) >> logs/run$N-gen-seed$SEED.txt
$PY -m pytest harness/test_helpers.py -p no:cacheprovider -q > logs/run$N-handwritten.log 2>&1
python3 gen/classify.py logs/run$N-handwritten.log > logs/run$N-handwritten.classified.txt
HELPERS_CASES=gen/seed-$SEED $PY -m pytest harness/test_helpers.py -p no:cacheprovider -q > logs/run$N-random-seed$SEED.log 2>&1
python3 gen/classify.py logs/run$N-random-seed$SEED.log > logs/run$N-random-seed$SEED.classified.txt
for f in logs/run$N-handwritten logs/run$N-random-seed$SEED; do
  echo "$f.log: $(tail -n 1 $f.log)"; echo "  $(tail -n 1 $f.classified.txt)"
done
