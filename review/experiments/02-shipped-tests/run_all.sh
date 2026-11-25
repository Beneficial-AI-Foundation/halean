#!/usr/bin/env bash
# Run every shipped test once. Usage: review/experiments/02-shipped-tests/run_all.sh <run-label>
# from the repository root, after the executables are built. Logs go to logs/<label>-*.log.
cd "$(git rev-parse --show-toplevel)"
export PATH=$HOME/.elan/bin:$PATH
L=review/experiments/02-shipped-tests/logs; R=${1:-run1}
run() { n=$1; shift; s=$(date +%s); "$@" > $L/$R-$n.log 2>&1; echo "exit=$? seconds=$(( $(date +%s)-s ))" >> $L/$R-$n.log; tail -1 $L/$R-$n.log | sed "s/^/$n: /"; }
run scenarios uv run tests/run_scenarios.py
run script_scenarios uv run tests/run_script_scenarios.py
run bridge_e2e uv run tests/bridge_e2e.py
run sun uv run --with astral==2.2 tests/sun/compare.py
run differential uv run tests/differential/run.py
run live_docker uv run tests/live/docker_e2e.py
