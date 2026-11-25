#!/bin/bash
# test_patch.sh <ID> <pytest -k expression for the reproducers> [copy]
# In the throwaway copy (already patched and rebuilt with `lake build halean-helpers`):
#   1. run the reproducers of ../cases with the patched engine  -> patches/<ID>.repro.log
#   2. run the shipped tests/differential/test_helpers.py there -> patches/<ID>.shipped.log
ID=$1; K=$2; COPY=${3:-/tmp/claude-0/halean-copies/09-helpers-1}
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
HALEAN_BIN=$COPY/.lake/build/bin /opt/havenv/bin/python -m pytest harness/test_helpers.py -p no:cacheprovider -q -k "$K" > patches/$ID.repro.log 2>&1
echo "repro:   $(tail -1 patches/$ID.repro.log)"
( cd $COPY && /opt/havenv/bin/python -m pytest tests/differential/test_helpers.py -p no:cacheprovider -q > "$HERE/patches/$ID.shipped.log" 2>&1 )
echo "shipped: $(tail -1 patches/$ID.shipped.log)"
