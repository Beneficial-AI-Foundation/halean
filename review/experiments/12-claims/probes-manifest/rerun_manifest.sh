#!/bin/bash
# Reruns every script behind CLAIMS-MANIFEST-TRANSLATED.md. Probes run twice; the two sets of logs are compared.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; L="$D/../logs-manifest"; PY=/opt/havenv/bin/python
mkdir -p "$L/run1"
cd "$D"
$PY -B structure.py > /dev/null
$PY -B overload_stubs.py > /dev/null
bash history_and_names.sh
(cd /home/user/halean && $PY tools/drift.py check 2>&1 | tail -2) > "$L/drift-check.log"
probes() {
  $PY -B probe_automation.py > /dev/null; $PY -B probe_template.py > /dev/null; $PY -B probe_core.py > /dev/null
  $PY -B probe_helpers.py > /dev/null; $PY -B py_direct.py > /dev/null; bash probe_extra.sh
  $PY -B -m pytest test_probe_ha.py -p no:cacheprovider -q > "$L/probe-ha.pytest.log" 2>&1
}
PL="probe-automation.log probe-template.log probe-core.log probe-helpers.log py-direct.log probe-ha.log probe-m17-engine.log probe-m80-static-target.log"
probes; for f in $PL; do cp "$L/$f" "$L/run1/$f"; done
probes
: > "$L/two-runs.log"
for f in $PL; do
  if cmp -s "$L/$f" "$L/run1/$f"; then echo "$f: run 1 and run 2 identical ($(wc -l < "$L/$f") lines)" >> "$L/two-runs.log"
  else echo "$f: RUNS DIFFER" >> "$L/two-runs.log"; fi
done
cat "$L/two-runs.log"
$PY -B build_manifest_claims.py
