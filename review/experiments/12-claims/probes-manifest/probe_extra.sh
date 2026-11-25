#!/bin/bash
# Two engine probes with their HA counterparts (M-17 engine side; M-80 static target).
# Output: logs-manifest/probe-m17-engine.log, logs-manifest/probe-m80-static-target.log
L="$(cd "$(dirname "$0")/.." && pwd)/logs-manifest"
B=/home/user/halean/.lake/build/bin/halean-automation
printf '%s\n' '{"type":"init","now":1700000000000,"tz":0,"automations":[{"id":"a","triggers":[{"trigger":"event","event_type":"go"}],"actions":[{"action":"nope.nope","continue_on_error":true},{"event":"after"}]}],"states":[]}' \
  '{"type":"event","event_type":"go","data":{},"now":1700000001000,"tz":0}' \
  '{"type":"service_result","call_id":0,"ok":false,"error_kind":"ha_error","message":"Action nope.nope not found","now":1700000001001,"tz":0}' | $B > "$L/probe-m17-engine.log"
printf '%s\n' '{"type":"init","now":1700000000000,"tz":0,"automations":[{"id":"a","triggers":[{"trigger":"event","event_type":"go"}],"actions":[{"action":"x.y","target":{"entity_id":"Light.A, light.b"}},{"action":"x.z","target":{"entity_id":"not an id"}}]}],"states":[]}' \
  '{"type":"event","event_type":"go","data":{},"now":1700000001000,"tz":0}' \
  '{"type":"service_result","call_id":0,"ok":true,"now":1700000001001,"tz":0}' | $B > "$L/probe-m80-static-target.log"
/opt/havenv/bin/python -B -c "
from homeassistant.helpers import config_validation as cv
print('HA cv.SERVICE_SCHEMA target:', cv.SERVICE_SCHEMA({'action':'x.y','target':{'entity_id':'Light.A, light.b'}})['target'])
try: print(cv.SERVICE_SCHEMA({'action':'x.z','target':{'entity_id':'not an id'}}))
except Exception as e: print('HA cv.SERVICE_SCHEMA invalid id ->', type(e).__name__, str(e)[:120])
" >> "$L/probe-m80-static-target.log" 2>&1
