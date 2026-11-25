#!/bin/sh
# usage: run_batch.sh <out.jsonl> <in1.yaml|in1.jsonl>[,<in2>...]   (HALEAN_BIN optional)
cd "$(dirname "$0")/harness" || exit 1
BATCH_OUT="$1" BATCH_IN="$2" /opt/havenv/bin/python -m pytest test_batch.py -p no:cacheprovider -q -s 2>&1 | grep -E "BATCH|passed|failed|Error|error" | tail -5
