#!/usr/bin/env bash
# Structural facts cited from CLAIMS-README.md (library coverage, licenses, pins, names of theorems that the README lists as open).
cd /home/user/halean
echo "## lean files without a built .olean (library coverage of 'lake build')"; n=0; m=0; for f in $(find HALean -name '*.lean'); do n=$((n+1)); o=.lake/build/lib/lean/${f%.lean}.olean; [ -f "$o" ] || { echo "  no olean: $f"; m=$((m+1)); }; done; echo "  $n lean files under HALean/, $m without olean"
echo "## LICENSE / NOTICE / LICENSES"; head -3 LICENSE | sed 's/^ *//'; ls LICENSES; head -40 NOTICE
echo "## manifest entry cited at README:162"; grep -n "helpers/script.py::Script.async_run$" manifest.yaml
echo "## astral pin: HA requirement vs README:76 'astral==2.2'"; grep -n "^astral" /opt/havenv/lib/python3.14/site-packages/homeassistant/package_constraints.txt
echo "## Engine references to Helpers (README:566 not connected)"; grep -rn "Helpers" HALean/Automation HALean/Script Exe/Automation.lean Exe/Script.lean bridge/ || echo "  none"
echo "## theorems whose names contain queued/restart/fifo/arrival (README:781 lists the run-order properties as left)"; grep -rnE "theorem [a-zA-Z_]*(queued|restart|fifo|arrival)[a-zA-Z_]*" HALean --include=*.lean | cut -c1-140
echo "## util/color in manifest (README:776 lists it as left)"; grep -c "util/color" manifest.yaml
echo "## scenario generator among tracked files outside review/ (README:790 lists it as a next step)"; git ls-files | grep -i "gen\|random\|fuzz" | grep -v "^review/" || echo "  none"
echo "## numeric limits in the Lean sources"; grep -n "def REPEAT_TERMINATE_ITERATIONS\|def STEP_FUEL" HALean/Automation/Script.lean; grep -n "opaque ENGINE_FUEL\|opaque LOOP_FUEL\|def TIME_CHANGE_MICROSECOND\|86400 then" HALean/Automation/Engine.lean; grep -n "def MAX_CALL_DEPTH\|def LOOP_FUEL" HALean/Core/Hass.lean; grep -n "def MAX_QUEUED_EVENT_DISPATCHES\|def MAX_LENGTH_EVENT_EVENT_TYPE" HALean/Core/EventBus.lean; grep -n "4300\|> 40 then" HALean/Core/Probatio.lean; grep -n "partial def Validator.run" HALean/Core/Schema.lean
