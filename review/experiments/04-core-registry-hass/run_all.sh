#!/bin/bash
# Rerun everything of this experiment: ./run_all.sh <run-number>
# Needs the shipped engines in /home/user/halean/.lake/build/bin (or HALEAN_BIN).
set -u
RUN=${1:?run number}
E=$(cd "$(dirname "$0")" && pwd)
PY=/opt/havenv/bin/python
OUT=$E/gen/out-run$RUN
mkdir -p "$OUT/core" "$OUT/services" "$E/logs"
cd "$E"
# seeds: core 101 and 202, services 11 and 22 (400 cases each)
for s in 101 202; do $PY gen/gen_core.py --seed $s --count 400 --out "$OUT/core" > "logs/run$RUN-gen-core-$s.log" 2>&1; done
for s in 11 22; do $PY gen/gen_services.py --seed $s --count 400 --out "$OUT/services" > "logs/run$RUN-gen-services-$s.log" 2>&1; done
T="-p no:cacheprovider -q --timeout 120 -rf"
$PY -m pytest harness/test_services.py $T > "logs/run$RUN-hand-services.log" 2>&1
$PY -m pytest harness/test_core.py $T > "logs/run$RUN-hand-core.log" 2>&1
HALEAN_CASES=$OUT/services $PY -m pytest harness/test_services.py $T > "logs/run$RUN-random-services.log" 2>&1
HALEAN_CASES=$OUT/core $PY -m pytest harness/test_core.py $T > "logs/run$RUN-random-core.log" 2>&1
(cd harness && $PY -m pytest test_core_ha_only.py -p no:cacheprovider -q -s > "../logs/run$RUN-ha-only-refused.log" 2>&1)
tail -n 1 logs/run$RUN-hand-services.log logs/run$RUN-hand-core.log logs/run$RUN-random-services.log logs/run$RUN-random-core.log
