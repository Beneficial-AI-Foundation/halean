#!/bin/sh
# show.sh <case-stem>...: run the given cases and print only the verdict and the HA / HALean lines
cd "$(dirname "$0")/.."
for c in "$@"; do
  echo "=== $c"
  /opt/havenv/bin/python -m pytest harness/test_scripts.py -p no:cacheprovider -q --tb=short -k "$c" 2>&1 \
    | grep -E "^E  |passed|failed" | cut -c1-1500
done
