#!/usr/bin/env bash
# Usage: ./run.sh <label> [pytest args]   (AUT_CASES / HALEAN_BIN / AUT_DUMP are passed through)
# Runs the harness copy over AUT_CASES (default: cases/) and writes logs/<label>.log
cd "$(dirname "$0")"
L=logs/$1.log; shift
( cd harness && /opt/havenv/bin/python -m pytest . -p no:cacheprovider -q "$@" ) > "$L" 2>&1
echo "exit=$?" >> "$L"
grep -E "passed|failed|error" "$L" | tail -1
