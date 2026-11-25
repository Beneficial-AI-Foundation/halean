"""Direct probes of real HA (no engine) for README claims the scenario harness cannot observe.
Output: logs/probe-ha-misc.log"""
from pathlib import Path
from homeassistant.core import callback
from homeassistant.setup import async_setup_component
LOG = Path(__file__).resolve().parent.parent / "logs" / "probe-ha-misc.log"

def setup_module(_m):
    LOG.write_text("")

def out(s):
    with LOG.open("a") as f:
        f.write(s + "\n")

async def test_repeat_limit(hass):
    """README:270 `repeat` aborts after 10,000 iterations."""
    seen = {"loop": 0, "after_limit": 0}
    @callback
    def on(ev):
        seen[ev.event_type] += 1
    hass.bus.async_listen("loop", on); hass.bus.async_listen("after_limit", on)
    assert await async_setup_component(hass, "automation", {"automation": [{
        "id": "limit", "triggers": [{"trigger": "event", "event_type": "go"}],
        "actions": [{"repeat": {"while": "{{ true }}", "sequence": [{"event": "loop"}]}}, {"event": "after_limit"}]}]})
    hass.bus.async_fire("go")
    await hass.async_block_till_done()
    out(f"repeat_limit: HA fired loop x{seen['loop']}, after_limit x{seen['after_limit']}")
    assert seen == {"loop": 10000, "after_limit": 0}

async def test_max_exceeded_accepted_by_ha(hass, caplog):
    """README:235 lists `max_exceeded` log levels as rejected at load by HALean. HA accepts them."""
    assert await async_setup_component(hass, "automation", {"automation": [{
        "id": "m", "mode": "single", "max_exceeded": "silent",
        "triggers": [{"trigger": "event", "event_type": "go"}], "actions": [{"delay": 5}]}]})
    await hass.async_block_till_done()
    out(f"max_exceeded: HA automation.automation_0 state = {hass.states.get('automation.automation_0').state}")
    assert hass.states.get("automation.automation_0").state == "on"
