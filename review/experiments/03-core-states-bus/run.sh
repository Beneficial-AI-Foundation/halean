#!/bin/sh
# Usage: ./run.sh <run-label> <states-seed> <events-seed> [states-count] [events-count]
# Runs the hand-written cases and freshly generated random cases against real HA and HALean
# with the harness copy. Engine: $HALEAN_BIN (default /home/user/halean/.lake/build/bin).
# Logs: logs/<run-label>-*.log. Exit status is not meaningful (divergent cases fail by design).
set -u
cd "$(dirname "$0")"
RUN=$1; SS=$2; ES=$3; SC=${4:-400}; EC=${5:-300}
PY=/opt/havenv/bin/python
PYTEST="$PY -m pytest -p no:cacheprovider -q --tb=short -rfE"
mkdir -p logs gen/out/states_$SS gen/out/events_$ES
$PY gen/make_length_cases.py > /dev/null
$PY gen/gen_states.py $SS $SC gen/out/states_$SS/rand.yaml
$PY gen/gen_events.py $ES $EC gen/out/events_$ES/rand.yaml
sha256sum gen/out/states_$SS/rand.yaml gen/out/events_$ES/rand.yaml > logs/$RUN-generated.sha256
cd harness
$PYTEST test_states.py > ../logs/$RUN-states-hand.log 2>&1
$PYTEST test_events.py > ../logs/$RUN-events-hand.log 2>&1
rm -f ../logs/$RUN-states-record.jsonl
RECORD_OUT=../logs/$RUN-states-record.jsonl $PYTEST test_states_record.py > ../logs/$RUN-states-record.log 2>&1
HALEAN_CASES=../gen/out/states_$SS $PYTEST test_states.py > ../logs/$RUN-states-rand-s$SS.log 2>&1
HALEAN_CASES=../gen/out/events_$ES $PYTEST test_events.py > ../logs/$RUN-events-rand-s$ES.log 2>&1
cd ..
tail -n 1 logs/$RUN-states-hand.log logs/$RUN-events-hand.log logs/$RUN-states-record.log \
  logs/$RUN-states-rand-s$SS.log logs/$RUN-events-rand-s$ES.log
