#!/usr/bin/env bash
# Blind-spot test of tools/drift.py. Works in a throwaway copy of tools/, manifest.yaml and upstream/.
# Each mutation edits the upstream copy with sed, runs `drift.py check`, records exit code and STALE lines, and reverts.
# Usage: review/experiments/11-coverage-drift/drift_blindspots.sh   -> logs/drift-blindspots.log, patches/M*.patch
set -u
REPO=$(cd "$(dirname "$0")/../../.." && pwd); E=$REPO/review/experiments/11-coverage-drift
S=/tmp/claude-0/halean-copies/drift; rm -rf $S; mkdir -p $S/upstream
cp -a $REPO/tools $REPO/manifest.yaml $S/; cp -a $REPO/upstream/ha-core $S/upstream/
U=$S/upstream/ha-core; H=$U/homeassistant; P=/opt/havenv/bin/python
out=$E/logs/drift-blindspots.log; : > $out
mut() { # id, description, file, sed-expression
  id=$1; desc=$2; f=$3; expr=$4
  sed -i -E "$expr" $H/$f
  git -C $U diff > $E/patches/$id.patch
  n=$(grep -c '^[+-][^+-]' $E/patches/$id.patch)
  r=$(cd $S && $P tools/drift.py check 2>&1); code=$?
  stale=$(echo "$r" | grep -E '^(STALE|MISSING)' | tr '\n' ';')
  echo "$id | $desc | changed_lines=$n | drift_exit=$code | ${stale:-no STALE/MISSING}" >> $out
  git -C $U checkout -q -- .
}
mut M01 "control: body of mapped core.py::validate_state (> becomes >=)" core.py 's/if len\(state\) > MAX_LENGTH_STATE_STATE:/if len(state) >= MAX_LENGTH_STATE_STATE:/'
mut M02 "control: comment added inside mapped core.py::validate_state" core.py 's/^(    if len\(state\) > MAX_LENGTH_STATE_STATE:)/    # a comment\n\1/'
mut M03 "constant MAX_LENGTH_STATE_STATE 255 -> 256 (const.py; read by mapped validate_state, async_set_internal)" const.py 's/^MAX_LENGTH_STATE_STATE: Final = 255/MAX_LENGTH_STATE_STATE: Final = 256/'
mut M04 "constant MAX_LENGTH_EVENT_EVENT_TYPE 64 -> 32 (const.py; read by mapped EventBus.async_fire_internal)" const.py 's/^MAX_LENGTH_EVENT_EVENT_TYPE: Final = 64/MAX_LENGTH_EVENT_EVENT_TYPE: Final = 32/'
mut M05 "module constant _MAX_QUEUED_EVENT_DISPATCHES 10_000 -> 5 (core.py; read by mapped async_fire_internal)" core.py 's/^_MAX_QUEUED_EVENT_DISPATCHES: Final = 10_000/_MAX_QUEUED_EVENT_DISPATCHES: Final = 5/'
mut M06 "module regex _OBJECT_ID changed (core.py; VALID_ENTITY_ID used by mapped valid_entity_id, status proven)" core.py 's/^_OBJECT_ID = (.*)$/_OBJECT_ID = r"[a-z]+"/'
mut M07 "constant REPEAT_TERMINATE_ITERATIONS 10000 -> 10 (helpers/script.py; read by mapped _async_do_step_repeat)" helpers/script.py 's/^REPEAT_TERMINATE_ITERATIONS = 10000/REPEAT_TERMINATE_ITERATIONS = 10/'
mut M08 "constant DEFAULT_MAX 10 -> 3 (helpers/script.py; default max runs)" helpers/script.py 's/^DEFAULT_MAX = 10/DEFAULT_MAX = 3/'
mut M09 "module-level schema NUMERIC_STATE_CONDITION_SCHEMA wrapped differently (config_validation.py; not a def)" helpers/config_validation.py 's/^NUMERIC_STATE_CONDITION_SCHEMA = probatio\.All\(/NUMERIC_STATE_CONDITION_SCHEMA = probatio.Any(/'
mut M10 "unmapped helper core.py::is_callback now returns False (called by mapped EventBus.async_listen)" core.py 's/^    return getattr\(func, "_hass_callback", False\) is True/    return False/'
