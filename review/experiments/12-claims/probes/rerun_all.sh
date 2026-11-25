#!/usr/bin/env bash
# Reruns every probe of this audit and rewrites logs/. Read-only on the repository (PYTHONDONTWRITEBYTECODE, -p no:cacheprovider).
# Needs the built executables in /home/user/halean/.lake/build/bin and /opt/havenv (review/CONVENTIONS.md). About 3 minutes.
set -u
export PYTHONDONTWRITEBYTECODE=1
R=/home/user/halean; X=$R/review/experiments/12-claims; PY="/opt/havenv/bin/python -B"; L=$X/logs
cd $R
# 1. shipped differential suite, verbose (case names)
(/opt/havenv/bin/python -m pytest tests/differential -p no:cacheprovider -v -rs > $L/differential-verbose.log 2>&1; echo "exit=$?" >> $L/differential-verbose.log)
# 2. structure
$PY tools/drift.py check > $L/drift-check.log 2>&1
$X/probes/sparse_check.sh > $L/sparse-check.log 2>&1; echo "exit=$?" >> $L/sparse-check.log; rm -rf /tmp/claude-0/halean-copies/12-claims-sparse
$PY $X/probes/sparse_history.py > $L/sparse-history.log 2>&1
$PY $X/probes/drift_hash_probe.py > $L/drift-hash-probe.log 2>&1
$X/probes/drift_constant_probe.sh > $L/drift-constant-probe.log 2>&1
$PY $X/probes/names_check.py > $L/names-check.log 2>&1
$PY $X/probes/manifest_counts.py > $L/manifest-counts.log 2>&1
$PY $X/probes/manifest_node_kinds.py > $L/manifest-node-kinds.log 2>&1
$X/probes/structure_checks.sh > $L/structure-checks.log 2>&1
$X/probes/small_checks.sh
# 3. behaviour probes
$PY $X/probes/ha_direct.py > $L/ha-direct.log 2>&1
$PY $X/probes/probe_automation_load.py > $L/probe-automation-load.log 2>&1
$PY $X/probes/probe_script_load.py > $L/probe-script-load.log 2>&1
$PY $X/probes/core_probes.py > $L/core-probes.log 2>&1
$X/probes/float_probe.sh > $L/float-probe.log 2>&1
$PY $X/probes/demo_automations_load.py > $L/demo-automations-load.log 2>&1
$X/probes/core_event_limit.sh > $L/core-event-limit.log 2>&1
for s in scenarios/kept_behaviours scenarios/supported_sample scenarios-engine-only/repeat_limit scenarios-engine-only/known_gaps; do
  $PY $X/probes/engine_scenario.py $X/probes/$s.yaml --logs > $L/engine-$(basename $s).log 2>&1
done
(cd $X/probes && /opt/havenv/bin/python -m pytest test_probe_templates.py -p no:cacheprovider -q 2>&1 | tail -2 > $L/probe-templates.summary)
(cd $X/probes && /opt/havenv/bin/python -m pytest test_probe_ha_misc.py -p no:cacheprovider -q > /dev/null 2>&1)
for r in 1 2; do (cd $X/probes/harness && /opt/havenv/bin/python -m pytest . -p no:cacheprovider -v 2>&1 | grep -E "PASSED|FAILED|passed|failed|^E  " | cut -c1-1500 > $L/harness-own-scenarios-run$r.log); done
# logs/harness-repeat-limit-not-observable.log: copy scenarios-engine-only/repeat_limit.yaml into scenarios/, run the harness once, remove it again.
# 4. the claims table
$PY $X/probes/build_claims.py
