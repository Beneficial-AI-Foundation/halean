"""Real HA / probatio values for README claims that need no running hass. Run with /opt/havenv/bin/python -B."""
import probatio as vol, homeassistant.helpers.config_validation as cv, homeassistant.const as c, jinja2
from importlib.metadata import version
print("HA", c.__version__, "| jinja2", jinja2.__version__, "| probatio", version("probatio"), "| pytest-homeassistant-custom-component", version("pytest-homeassistant-custom-component"))
def t(label, f):
    try: print(label, "->", repr(f()))
    except Exception as e: print(label, "-> raises", type(e).__name__ + ":", str(e)[:230])
S = lambda v: vol.Schema({"a": v})
t("README:335 Coerce(int) 4300 digits", lambda: len(str(S(vol.Coerce(int))({"a": "1" * 4300})["a"])))
t("README:335 Coerce(int) 4301 digits", lambda: S(vol.Coerce(int))({"a": "1" * 4301}))
t("README:335 In(range(45)) 99", lambda: S(vol.In(list(range(45))))({"a": 99}))
t("README:335 In did you mean", lambda: S(vol.In(["apple", "banana"]))({"a": "appel"}))
print("README:335 hasattr(cv, 'percentage') =", hasattr(cv, "percentage"), "| hasattr(cv, 'icon') =", hasattr(cv, "icon"))
t("README:335 cv.icon('mdi:lamp')", lambda: S(cv.icon)({"a": "mdi:lamp"}))
t("README:335 cv.icon('lamp')", lambda: S(cv.icon)({"a": "lamp"}))
t("README:240 round(2.675, 2)", lambda: round(2.675, 2))
t("README:553 cv.time_period('-0:00:05')", lambda: cv.time_period("-0:00:05"))
from homeassistant.components.timer import _format_timedelta
t("README:553 _format_timedelta(cv.time_period('-0:00:05'))", lambda: _format_timedelta(cv.time_period("-0:00:05")))
t("README:553 back through cv.time_period", lambda: cv.time_period(_format_timedelta(cv.time_period("-0:00:05"))))
import homeassistant.helpers.script as hs, homeassistant.core as core, probatio.schema as ps, probatio._messages as pm, homeassistant.helpers.event as he
print("README:270 REPEAT_TERMINATE_ITERATIONS =", hs.REPEAT_TERMINATE_ITERATIONS, "| README:429 _MAX_QUEUED_EVENT_DISPATCHES =", core._MAX_QUEUED_EVENT_DISPATCHES,
      "| README:648 _AUTO_COMPILE_THRESHOLD =", ps._AUTO_COMPILE_THRESHOLD, "| README:335 _MAX_LISTED_VALUES =", pm._MAX_LISTED_VALUES,
      "| README:666 RANDOM_MICROSECOND_MIN/MAX =", he.RANDOM_MICROSECOND_MIN, he.RANDOM_MICROSECOND_MAX, "| README:429 MAX_LENGTH_EVENT_EVENT_TYPE =", c.MAX_LENGTH_EVENT_EVENT_TYPE)
import sys; print("README:335 sys.get_int_max_str_digits() =", sys.get_int_max_str_digits())
