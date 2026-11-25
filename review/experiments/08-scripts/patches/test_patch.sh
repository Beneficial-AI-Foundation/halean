#!/bin/sh
# test_patch.sh <ID> [<prerequisite ID>...]: in the throwaway copy, reset the sources to the
# reviewed commit, apply the prerequisite patches and patches/<ID>.patch, rebuild halean-script and
# halean-automation, run the shipped suites there, then the hand-written cases and the config
# matrix of this review against the patched build. Everything goes to patches/<ID>-tests.log.
set -u
ID=$1; shift
HERE=$(cd "$(dirname "$0")" && pwd)
COPY=${COPY:-/tmp/claude-0/halean-copies/08-scripts-1}
BASE=f638a3779195a42a5162939aa67981b9b501618e
LOG=$HERE/$ID-tests.log
export PATH=$HOME/.elan/bin:$PATH
cd "$COPY" || exit 1
{
  echo "== $ID: reset HALean/ Exe/ tests/ to $BASE, apply: $* $ID"
  git checkout -q $BASE -- HALean Exe tests bridge && git status --short HALean Exe tests | head
  for p in "$@" "$ID"; do git apply "$HERE/$p.patch" && echo "applied $p.patch"; done
  echo "== lake build halean-script halean-automation"
  lake build halean-script halean-automation 2>&1 | tail -3
  echo "== tests/run_script_scenarios.py"
  /opt/havenv/bin/python tests/run_script_scenarios.py 2>&1 | tail -3
  echo "== tests/run_scenarios.py"
  /opt/havenv/bin/python tests/run_scenarios.py 2>&1 | tail -3
  echo "== pytest tests/differential/test_scripts.py tests/differential/test_differential.py (in the copy)"
  /opt/havenv/bin/python -m pytest tests/differential/test_scripts.py tests/differential/test_differential.py -p no:cacheprovider -q --tb=line 2>&1 | tail -4
  echo "== hand-written cases of this review against the patched build (failures listed)"
  cd "$HERE/.." && HALEAN_BIN=$COPY/.lake/build/bin /opt/havenv/bin/python -m pytest harness/test_scripts.py -p no:cacheprovider -q --tb=no 2>&1 | grep -E "^FAILED|passed|failed"
  echo "== config matrix against the patched build (entries that are not 'agree')"
  HALEAN_BIN=$COPY/.lake/build/bin /opt/havenv/bin/python -m pytest harness/test_config_matrix.py -p no:cacheprovider -q --tb=no -s 2>&1 | grep -E "^MATRIX" | grep -v ": agree"
} > "$LOG" 2>&1
tail -40 "$LOG"
