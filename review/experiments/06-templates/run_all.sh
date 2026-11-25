#!/bin/sh
# usage: run_all.sh <run-label>            e.g. run_all.sh run1
# Runs (a) the hand-written cases through the harness copy (pytest, shipped assertions),
#      (b) the hand-written cases plus gen/batch_only.yaml through the batch harness,
#      (c) the random cases of every seed in gen/seeds.txt (COUNT each) through the batch harness,
# and writes logs/<label>-*.  HALEAN_BIN selects the engine directory (default: the shipped build).
set -u
cd "$(dirname "$0")" || exit 1
L="$1"; HERE=$(pwd); COUNT=${COUNT:-3000}
( cd harness && /opt/havenv/bin/python -m pytest test_templates.py -p no:cacheprovider -q -rf 2>&1 | grep -v "^ERROR:homeassistant\|^WARNING" ) > logs/$L-hand-pytest.log
tail -1 logs/$L-hand-pytest.log
ALL=$(ls $HERE/cases/*.yaml | tr '\n' ',')$HERE/gen/batch_only.yaml
./run_batch.sh $HERE/logs/$L-hand-batch.jsonl "$ALL" > logs/$L-hand-batch.summary.log 2>&1
python3 classify.py logs/$L-hand-batch.jsonl >> logs/$L-hand-batch.summary.log
grep BATCH logs/$L-hand-batch.summary.log
for seed in $(cat gen/seeds.txt); do
  python3 gen/gen_templates.py $seed $COUNT gen/random-seed$seed.jsonl
  ./run_batch.sh $HERE/logs/$L-random-seed$seed.jsonl $HERE/gen/random-seed$seed.jsonl > logs/$L-random-seed$seed.summary.log 2>&1
  python3 classify.py logs/$L-random-seed$seed.jsonl >> logs/$L-random-seed$seed.summary.log
  grep BATCH logs/$L-random-seed$seed.summary.log
done
