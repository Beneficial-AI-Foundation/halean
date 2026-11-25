#!/usr/bin/env bash
# Build a copy of upstream holding only the paths of the README sparse-checkout command (lines 138-148),
# then hash every manifest entry against it (drift.py compare). Entries reported "(missing)" are
# manifest paths outside the README sparse set.
set -e
cd /home/user/halean
D=/tmp/claude-0/halean-copies/12-claims-sparse; rm -rf $D; mkdir -p $D/homeassistant
U=upstream/ha-core/homeassistant
for p in components/automation/ helpers/ components/homeassistant/triggers/ const.py core.py \
  components/template/trigger.py util/dt.py util/__init__.py util/location.py components/zone/ \
  components/sun/ components/script/ components/input_boolean/ components/input_number/ \
  components/input_select/ components/input_text/ components/counter/ components/timer/ \
  components/number/ components/select/ components/text/; do
  mkdir -p "$D/homeassistant/$(dirname $p)"; cp -a "$U/$p" "$D/homeassistant/$(dirname $p)/"
done
/opt/havenv/bin/python tools/drift.py compare --against $D/homeassistant
