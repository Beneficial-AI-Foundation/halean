#!/usr/bin/env bash
# README:58-60 "After an upstream pull this shows exactly which translations need revisiting."
# Change a module-level constant that translated code depends on (REPEAT_TERMINATE_ITERATIONS, helpers/script.py)
# in a throwaway copy of upstream, then let drift.py compare the manifest hashes against the copy.
set -e
D=/tmp/claude-0/halean-copies/12-claims-const; rm -rf $D; mkdir -p $D
cp -a /home/user/halean/upstream/ha-core/homeassistant $D/
echo "baseline:"; /opt/havenv/bin/python -B /home/user/halean/tools/drift.py compare --against $D/homeassistant | head -3 || true
sed -i 's/^REPEAT_TERMINATE_ITERATIONS = 10000/REPEAT_TERMINATE_ITERATIONS = 20000/' $D/homeassistant/helpers/script.py
grep -n "^REPEAT_TERMINATE_ITERATIONS" $D/homeassistant/helpers/script.py
echo "after changing the constant:"; /opt/havenv/bin/python -B /home/user/halean/tools/drift.py compare --against $D/homeassistant | head -3 || true
rm -rf $D
