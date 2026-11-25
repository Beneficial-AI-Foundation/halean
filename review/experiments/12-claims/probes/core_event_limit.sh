#!/usr/bin/env bash
# README:429 the 10,000-events limit in halean-core: count deliveries and show the log record.
printf '%s\n' '{"op": "listen", "id": "l", "event_type": "x", "react": [{"fire": {"event_type": "x"}}], "now": 0}' '{"op": "fire", "event_type": "x", "now": 1}' \
 | /home/user/halean/.lake/build/bin/halean-core | tail -1 | /opt/havenv/bin/python -B -c "
import json, sys
r = json.loads(sys.stdin.read()); tr = r['trace']
print('result', r['result'], '| deliveries', sum('delivery' in t for t in tr), '| logs', [t for t in tr if 'log' in t])"
