#!/usr/bin/env python
"""Real HA / probatio / CPython values for statements in manifest notes (no running hass).
Output: logs-manifest/py-direct.log"""
import sys, datetime as dt
sys.dont_write_bytecode = True
import probatio
from homeassistant.helpers import config_validation as cv
from homeassistant.util import dt as dt_util
out = open(__file__.rsplit("/", 2)[0] + "/logs-manifest/py-direct.log", "w")
def show(mid, what, f):
    try: r = repr(f())
    except BaseException as e: r = f"raises {type(e).__module__}.{type(e).__name__}: {e}"
    s = f"{mid} | {what}\n    -> {r}"; print(s); print(s, file=out)
show("M-281", "cv.time_period_str('0:0:nan') called directly (does a translated cv function raise ValueError?)", lambda: cv.time_period_str("0:0:nan"))
show("M-281", "the same under probatio.Schema({'t': cv.time_period_str})", lambda: probatio.Schema({"t": cv.time_period_str})({"t": "0:0:nan"}))
show("M-281", "cv.positive_timedelta / time_period_dict with NaN: probatio.Schema({'t': cv.time_period_dict})({'t': {'seconds': nan}})", lambda: probatio.Schema({"t": cv.time_period_dict})({"t": {"seconds": float("nan")}}))
show("M-281", "cv.time_period_seconds(nan)", lambda: cv.time_period_seconds(float("nan")))
show("M-316", "cv.entity_ids(5): iterating a scalar", lambda: cv.entity_ids(5))
show("M-316", "cv.entity_ids(timedelta) (SCH-4)", lambda: cv.entity_ids(dt.timedelta(1)))
show("M-107", "dt_util.parse_datetime('2023-11-14') (ciso8601 path)", lambda: dt_util.parse_datetime("2023-11-14"))
show("M-107", "dt_util.parse_datetime('2023-11-14T24:00:00') (TPL-23)", lambda: dt_util.parse_datetime("2023-11-14T24:00:00"))
show("M-107", "the name parse_datetime in util/dt.py: number of definitions and the first one's decorators", lambda: __import__("ast").unparse([n for n in __import__("ast").parse(open(dt_util.__file__).read()).body if getattr(n, "name", "") == "parse_datetime"][0]))
show("M-342", "input_number _cv_input_number message with swapped bounds", lambda: __import__("homeassistant.components.input_number", fromlist=["x"])._cv_input_number({"min": 5.0, "max": 1.0}))
show("M-370", "input_text _cv_input_text message with swapped bounds", lambda: __import__("homeassistant.components.input_text", fromlist=["x"])._cv_input_text({"min": 5, "max": 1}))
show("M-391", "timer _format_timedelta(timedelta(days=1, seconds=3661, microseconds=500000))", lambda: __import__("homeassistant.components.timer", fromlist=["x"])._format_timedelta(dt.timedelta(days=1, seconds=3661, microseconds=500000)))
show("M-331", "f'{0.1 + 0.2:.15}', f'{1e16:.15}', f'{123456789012345678.0:.15}'", lambda: [f"{x:.15}" for x in (0.1 + 0.2, 1e16, 123456789012345678.0)])
show("M-303", "probatio.Lower on non-ASCII text", lambda: probatio.Lower("ÀB"))
show("M-301", "probatio In message ordering: mixed container", lambda: probatio.Schema(probatio.In(["b", 1, "a"]))("z"))
show("M-301", "probatio In message ordering: strings sort", lambda: probatio.Schema(probatio.In(["b", "a"]))("z"))
show("M-301", "probatio In message ordering: None with one other", lambda: probatio.Schema(probatio.In([None, "a"]))("z"))
