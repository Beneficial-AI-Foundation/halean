"""Batch mode of the template differential harness (review copy, NOT shipped).

Same inputs to both engines as `test_templates.py` (the shipped harness), but
instead of one pytest test per case with assertions it runs every case of the
files named in the environment variable BATCH_IN (comma separated; `.yaml` in
the shipped case format, or `.jsonl` with one case per line) in one Home
Assistant instance and writes one JSON line per case to BATCH_OUT:

    {"name", "template", "ha": {...}, "lean": {...}, "verdict": "pass"|"fail",
     "why": <which shipped assertion failed>, "cat": <category>}

`verdict` is the pass/fail rule of the shipped assertions, unchanged:
  * `unsupported: true`  -> pass iff HALean answers `unsupported`
  * HALean answers `unsupported` otherwise -> fail
  * `render_info: true`  -> HALean's info must equal HA's
  * `expect_error_in_halean_only` -> pass iff HA ok and HALean not ok
  * HA ok   -> HALean's {ok,type,repr} must equal HA's
  * HA raises -> HALean must not be ok
`cat` is an extra classification for the review (it does not change `verdict`):
  same, silent (both ok, differ), accepts (HA raises, HALean ok),
  refuses_render (HA ok, HALean render error), refuses_load (HA ok, HALean
  unsupported), both_refuse_load (HA raises, HALean unsupported), info (render
  info differs), hang (HALean gave no answer within ENGINE_TIMEOUT seconds).

Differences from the shipped harness, all needed for bulk runs:
  * states set by a case are removed after it (the shipped harness gets a
    fresh `hass` per case);
  * the engine is read with a timeout and restarted if it does not answer;
  * HA's render runs under the same exception filter as the shipped harness,
    plus a catch-all that is recorded as `ha_crash` (never counted as pass).
"""

from __future__ import annotations

import json
import os
import queue
import subprocess
import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path

import yaml

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError, TemplateError
from homeassistant.helpers import condition
from homeassistant.helpers.template import Template
from homeassistant.util import dt as dt_util
from freezegun.api import FrozenDateTimeFactory

ENGINE = Path(os.environ.get("HALEAN_BIN", "/home/user/halean/.lake/build/bin")) / "halean-template"
NOW = datetime(2026, 11, 20, 16, 30, 45, 123000, tzinfo=UTC)
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
ENGINE_TIMEOUT = float(os.environ.get("ENGINE_TIMEOUT", "20"))


def _us(d: datetime) -> int:
    return (d - EPOCH) // timedelta(microseconds=1)


def _typename(v) -> str:
    for kls in (bool, int, float, str, type(None), tuple, list, dict, set):
        if isinstance(v, kls):
            return kls.__name__
    return type(v).__name__


class Engine:
    def __init__(self):
        self.start()

    def start(self):
        self.proc = subprocess.Popen([str(ENGINE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.q: queue.Queue = queue.Queue()
        threading.Thread(target=self._reader, args=(self.proc, self.q), daemon=True).start()

    @staticmethod
    def _reader(proc, q):
        for line in proc.stdout:
            q.put(line)
        q.put(None)

    def ask(self, msg: dict) -> dict:
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        try:
            line = self.q.get(timeout=ENGINE_TIMEOUT)
        except queue.Empty:
            self.proc.kill()
            self.start()
            return {"ok": False, "error": "HANG", "hang": True}
        if line is None:
            self.start()
            return {"ok": False, "error": "ENGINE DIED", "hang": True}
        return json.loads(line)

    def close(self):
        self.proc.kill()


def load_cases():
    out = []
    for f in os.environ["BATCH_IN"].split(","):
        p = Path(f)
        if p.suffix == ".jsonl":
            out += [json.loads(line) for line in p.read_text().splitlines() if line.strip()]
        else:
            out += yaml.safe_load(p.read_text()) or []
    return out


def run_case(hass, freezer, engine, case):
    freezer.move_to(datetime.fromisoformat(case["now"]) if "now" in case else NOW)
    states = []
    for s in case.get("states", []):
        hass.states.async_set(s["entity_id"], s["state"], s.get("attributes", {}))
        st = hass.states.get(s["entity_id"])
        states.append({**s, "last_changed_us": _us(st.last_changed),
                       "last_updated_us": _us(st.last_updated)})
    variables = case.get("variables")
    parse = case.get("parse_result", True)
    is_cond = case.get("condition", False)
    rec = {"name": case.get("name"), "template": case["template"]}

    lean = engine.ask({"template": case["template"], "states": states,
                       "variables": variables or {}, "parse_result": parse, "condition": is_cond,
                       "info": bool(case.get("render_info")),
                       "now": _us(dt_util.utcnow()) // 1000,
                       "tz": int(dt_util.now().utcoffset().total_seconds())})
    rec["lean"] = dict(lean)

    ha_crash = None
    tpl = Template(case["template"], hass)
    try:
        if is_cond:
            r = condition.async_template(hass, tpl, variables)
        else:
            r = tpl.async_render(variables, parse_result=parse)
        ha = {"ok": True, "type": _typename(r), "repr": repr(r)}
    except (TemplateError, HomeAssistantError) as err:
        ha = {"ok": False, "error": str(err)}
    except Exception as err:  # the shipped harness would crash here
        ha = {"ok": False, "error": f"{type(err).__name__}: {err}"}
        ha_crash = True
    rec["ha"] = ha

    def verdict():
        lean_ = dict(lean)
        if ha_crash:
            return "fail", "ha_crash", "ha_crash"
        if lean_.get("hang"):
            return "fail", "engine gave no answer", "hang"
        if case.get("unsupported"):
            return ("pass", "", "same") if "unsupported" in lean_ else ("fail", "HALean should reject this template", "accepts_unsupported")
        if "unsupported" in lean_:
            return "fail", "HALean rejected a supported template", ("refuses_load" if ha["ok"] else "both_refuse_load")
        if case.get("render_info"):
            info = tpl.async_render_to_info(variables)
            want = {"entities": sorted(info.entities), "domains": sorted(info.domains),
                    "domains_lifecycle": sorted(info.domains_lifecycle),
                    "all_states": info.all_states, "all_states_lifecycle": info.all_states_lifecycle}
            rec["ha_info"] = want
            if lean_.pop("info", None) != want:
                return "fail", "render info differs", "info"
        lean_.pop("info", None)
        if case.get("expect_error_in_halean_only"):
            ok = ha["ok"] and not lean_["ok"]
            return ("pass", "", "same") if ok else ("fail", "expect_error_in_halean_only", "other")
        if ha["ok"]:
            if lean_ == ha:
                return "pass", "", "same"
            return "fail", "result differs", ("silent" if lean_.get("ok") else "refuses_render")
        if not lean_["ok"]:
            return "pass", "", "same"
        return "fail", "HA raised, HALean returned", "accepts"

    rec["verdict"], rec["why"], rec["cat"] = verdict()
    for s in case.get("states", []):
        hass.states.async_remove(s["entity_id"])
    return rec


async def test_batch(hass: HomeAssistant, freezer: FrozenDateTimeFactory) -> None:
    cases = load_cases()
    engine = Engine()
    counts: dict[str, int] = {}
    with open(os.environ["BATCH_OUT"], "w") as out:
        for case in cases:
            rec = run_case(hass, freezer, engine, case)
            await hass.async_block_till_done()
            counts[rec["cat"]] = counts.get(rec["cat"], 0) + 1
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
    engine.close()
    print(f"\nBATCH cases={len(cases)} " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
