"""Probes of real HA (hass fixture) for manifest notes that a pure-Python call cannot check.
Output: logs-manifest/probe-ha.log"""
from pathlib import Path
from homeassistant.core import callback
from homeassistant.setup import async_setup_component
LOG = Path(__file__).resolve().parent.parent / "logs-manifest" / "probe-ha.log"

def setup_module(_m):
    LOG.write_text("")

def out(s):
    with LOG.open("a") as f:
        f.write(s + "\n")

async def _run(hass, actions, conditions=None, states=()):
    seen = []
    @callback
    def on(ev):
        seen.append(ev.event_type)
    for t in ("after", "ran"):
        hass.bus.async_listen(t, on)
    for eid, st, attrs in states:
        hass.states.async_set(eid, st, attrs)
    cfg = {"id": "a", "triggers": [{"trigger": "event", "event_type": "go"}], "actions": actions}
    if conditions is not None:
        cfg["conditions"] = conditions
    assert await async_setup_component(hass, "automation", {"automation": [cfg]})
    hass.bus.async_fire("go")
    await hass.async_block_till_done()
    return seen

async def test_m17_service_not_found_continue_on_error(hass):
    """M-17 (`_handle_exception`): ServiceNotFound is one of CONFIGURATION_ERRORS, so
    continue_on_error does not swallow it. bridge.py sends HA's `not_found` as `ha_error`."""
    seen = await _run(hass, [{"action": "nope.nope", "continue_on_error": True}, {"event": "after"}])
    out(f"M-17 | HA: missing service with continue_on_error: true, then event 'after' -> events seen {seen}")

async def test_m8_time_condition_date_only_sensor(hass):
    """M-8: time condition, after: a timestamp sensor whose state is a date only (ciso8601 path)."""
    seen = await _run(hass, [{"event": "ran"}], [{"condition": "time", "after": "sensor.ts"}],
                      [("sensor.ts", "2023-11-14", {"device_class": "timestamp"})])
    out(f"M-8 | HA: time condition after sensor.ts = '2023-11-14' (device_class timestamp) -> events seen {seen}")

async def test_m65_last_changed(hass):
    """M-65: state.last_changed in a template renders in HA (a datetime)."""
    from homeassistant.helpers.template import Template
    hass.states.async_set("sensor.a", "1")
    r = Template("{{ states.sensor.a.last_changed is not none and states.sensor.a.last_changed.year > 2000 }}", hass).async_render()
    out(f"M-65 | HA: states.sensor.a.last_changed renders a datetime -> {r!r}")
