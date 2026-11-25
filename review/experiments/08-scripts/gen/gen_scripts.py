#!/opt/havenv/bin/python
"""Seeded random scenario generator for scripts as entities (area 08).

    gen_scripts.py <seed> <count> <outdir>

Writes <count> scenarios `r<seed>_<i>.yaml` in the shipped format
(tests/run_script_scenarios.py). Each has 3-5 scripts from the supported
subset (marker service calls and events, delays, nested script calls by
direct service and by script.turn_on, turn_off / toggle, `stop` with a
response, if / parallel / repeat, every run mode) and a stream of 8-16
steps: outside calls (direct, turn_on, turn_off, toggle), ticks, service
results (ok with or without a response, or an error of each kind) and
reloads.

A `result: n` step needs the n-th service call to exist on both sides. The
generator learns how many calls exist so far by running the prefix through
halean-script (HALEAN_BIN, default the unpatched build). If HA made fewer
calls, the harness fails with an IndexError on the HA side, which is then a
divergence to look at, not hidden.

Calls between scripts: direct calls may target any script (HA bounds the
recursion by mode / max / script_stack); turn_on and toggle only target
scripts with a higher index, so nothing loops forever.
"""

from __future__ import annotations

import copy
import os
import random
import signal
import subprocess
import sys
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "harness"))
from run_script_scenarios import lean_run  # noqa: E402

MODES = ["single", "restart", "queued", "parallel"]


class _Timeout(Exception):
    pass


def _alarm(*_args) -> None:
    raise _Timeout


signal.signal(signal.SIGALRM, _alarm)


class Gen:
    def __init__(self, rng: random.Random) -> None:
        self.rng = rng
        self.n = rng.randint(3, 5)
        self.names = [f"s{i}" for i in range(self.n)]
        self.marker = 0

    def mark(self, name: str) -> str:
        self.marker += 1
        return f"{name}.{self.marker}"

    def action(self, i: int, depth: int) -> list[dict]:
        """One random action (sometimes two that belong together)."""
        rng, name = self.rng, self.names[i]
        k = rng.random()
        if k < 0.20:
            a = {"action": "test.m", "data": {"id": self.mark(name), "v": "{{ v | default(0) }}"}}
            if rng.random() < 0.3:
                a["response_variable"] = "r"
            if rng.random() < 0.3:
                a["continue_on_error"] = True
            return [a]
        if k < 0.36:
            data = {"id": self.mark(name), "v": "{{ v | default(0) }}"}
            pick = rng.random()
            if pick < 0.25:
                other = rng.choice(self.names)
                data["st"] = f"{{{{ states('script.{other}') }}}}"
                data["cur"] = f"{{{{ state_attr('script.{other}', 'current') }}}}"
            elif pick < 0.4:
                data["this"] = "{{ this.state }}/{{ this.attributes.current }}"
            elif pick < 0.55:
                data["r"] = "{{ r | default('undef') }}"
            return [{"event": "mark", "event_data": data}]
        if k < 0.48:
            return [{"delay": rng.choice([1, 1, 2, 3])}]
        if k < 0.66:
            # direct call of any script
            a = {"action": f"script.{rng.choice(self.names)}",
                 "data": {"v": "{{ v | default(0) + 1 }}"}}
            if rng.random() < 0.4:
                a["response_variable"] = "r"
            if rng.random() < 0.3:
                a["continue_on_error"] = True
            return [a]
        if k < 0.74 and i + 1 < self.n:
            targets = rng.sample(self.names[i + 1:], rng.randint(1, min(2, self.n - i - 1)))
            a = {"action": "script.turn_on", "target": {"entity_id": [f"script.{t}" for t in targets]}}
            if rng.random() < 0.5:
                a["data"] = {"variables": {"v": "{{ v | default(0) + 10 }}"}}
            return [a]
        if k < 0.80:
            t = rng.choice(self.names)
            return [{"action": "script.turn_off", "target": {"entity_id": f"script.{t}"}}]
        if k < 0.84 and i + 1 < self.n:
            t = rng.choice(self.names[i:])
            return [{"action": "script.toggle", "target": {"entity_id": f"script.{t}"}}]
        if k < 0.88:
            return [{"variables": {"out": {"id": self.mark(name), "v": "{{ v | default(0) }}"}}},
                    {"stop": "done", "response_variable": "out"}]
        if k < 0.90:
            return [{"stop": "bad", "error": True}]
        if k < 0.92:
            return [{"condition": "template", "value_template": "{{ v | default(0) < 2 }}"}]
        if depth >= 2:
            return [{"event": "mark", "event_data": {"id": self.mark(name)}}]
        if k < 0.95:
            a = {"if": [{"condition": "template", "value_template": "{{ v | default(0) is even }}"}],
                 "then": self.seq(i, depth + 1, 1, 2)}
            if rng.random() < 0.5:
                a["else"] = self.seq(i, depth + 1, 1, 2)
            return [a]
        if k < 0.98:
            return [{"parallel": [{"sequence": self.seq(i, depth + 1, 1, 2)},
                                  {"sequence": self.seq(i, depth + 1, 1, 2)}]}]
        return [{"repeat": {"count": 2, "sequence": self.seq(i, depth + 1, 1, 2)}}]

    def seq(self, i: int, depth: int, lo: int, hi: int) -> list[dict]:
        out: list[dict] = []
        for _ in range(self.rng.randint(lo, hi)):
            out.extend(self.action(i, depth))
        return out

    def script(self, i: int) -> dict:
        rng = self.rng
        cfg: dict = {}
        if rng.random() < 0.3:
            cfg["alias"] = f"Script {i} {rng.choice(['A', 'B'])}"
        if rng.random() < 0.2:
            cfg["icon"] = "mdi:script"
        mode = rng.choice(MODES)
        cfg["mode"] = mode
        if mode in ("queued", "parallel") and rng.random() < 0.6:
            cfg["max"] = rng.choice([2, 2, 3])
        cfg["fields"] = {"v": {}, "r": {}}
        if rng.random() < 0.2:
            cfg["variables"] = {"v": 100}
        cfg["sequence"] = self.seq(i, 0, 1, 4)
        return cfg


def _edges(actions, direct: set, fresh: set) -> None:
    """Call edges of a sequence: direct calls, and turn_on / toggle (which start with a fresh stack)."""
    for a in actions if isinstance(actions, list) else [actions]:
        if not isinstance(a, dict):
            continue
        svc = a.get("action", "")
        if svc in ("script.turn_on", "script.toggle"):
            ids = a["target"]["entity_id"]
            fresh.update(e.split(".")[1] for e in ([ids] if isinstance(ids, str) else ids))
        elif svc.startswith("script.") and svc != "script.turn_off":
            direct.add(svc.split(".")[1])
        for k in ("then", "else", "sequence", "parallel"):
            if k in a:
                _edges(a[k], direct, fresh)
        if "repeat" in a:
            _edges(a["repeat"]["sequence"], direct, fresh)


def loops(scripts: dict) -> bool:
    """Whether a turn_on / toggle edge lies on a cycle of calls. Such scripts
    can start each other forever (each turn_on has a fresh script stack, so
    HA's recursion guard does not apply); both sides then only stop at an
    arbitrary bound, and the scenario compares nothing."""
    direct: dict[str, set] = {}
    fresh: dict[str, set] = {}
    for name, cfg in scripts.items():
        direct[name], fresh[name] = set(), set()
        _edges(cfg["sequence"], direct[name], fresh[name])
    for src, targets in fresh.items():
        for t in targets:
            if t == src:
                return True
            seen, todo = set(), [t]
            while todo:
                n = todo.pop()
                if n == src:
                    return True
                if n in seen or n not in scripts:
                    continue
                seen.add(n)
                todo.extend(direct[n] | fresh[n])
    # a parallel script on a cycle of calls recurses until `max` runs exist;
    # with several calls per run that is exponential in `max` (both in HA
    # and in HALean), so only small `max` values are let through
    for name, cfg in scripts.items():
        if cfg.get("mode") == "parallel" and cfg.get("max", 10) > 3:
            seen, todo = set(), list(direct[name] | fresh[name])
            while todo:
                n = todo.pop()
                if n == name:
                    return True
                if n in seen or n not in scripts:
                    continue
                seen.add(n)
                todo.extend(direct[n] | fresh[n])
    return False


def scenario(seed: int, idx: int) -> dict:
    rng = random.Random(f"{seed}/{idx}")
    while True:
        g = Gen(rng)
        scripts = {name: g.script(i) for i, name in enumerate(g.names)}
        if not loops(scripts):
            break
    sc: dict = {"description": f"random scenario seed={seed} index={idx}", "scripts": scripts, "steps": []}
    at = 0
    resolved: set[int] = set()
    current = scripts
    nsteps = rng.randint(8, 16)
    for _ in range(nsteps):
        at += rng.choice([0, 1, 1, 1, 2, 3])
        if at == 0:
            at = 1
        # how many service calls exist so far (through HALean); a prefix that
        # takes HALean more than 60 s ends the scenario one step earlier
        signal.alarm(60)
        try:
            _, obs = lean_run(sc)
        except _Timeout:
            # only this process's own engine child
            subprocess.run(["pkill", "-P", str(os.getpid()), "-f", "halean-script"], check=False)
            sc["steps"].pop()
            sc["description"] += " (cut: halean-script took more than 60 s on the next step)"
            break
        finally:
            signal.alarm(0)
        made = sum(len(o["call_service"]) for o in obs)
        pending = [n for n in range(made) if n not in resolved]
        st: dict = {"at": at}
        k = rng.random()
        ents = [f"script.{n}" for n in current]
        if pending and k < 0.35:
            n = rng.choice(pending[:2])  # mostly the oldest
            resolved.add(n)
            st["result"] = n
            # an ok result always carries a response: HA refuses `None` for a
            # call that asked for one (ServiceRegistry.async_call), and the
            # generator does not know which calls asked
            if rng.random() < 0.15:
                st["ok"] = False
                st["error_kind"] = rng.choice(["ha_error", "invalid", "other"])
            else:
                st["response"] = {"n": n}
        elif k < 0.65:
            st["call"] = rng.choice(list(current))
            if rng.random() < 0.6:
                st["data"] = {"v": rng.randint(0, 4)}
            if rng.random() < 0.4:
                st["return_response"] = True
        elif k < 0.73:
            st["call"] = "turn_on"
            data: dict = {"entity_id": rng.sample(ents, rng.randint(1, min(2, len(ents))))}
            if rng.random() < 0.5:
                data["variables"] = {"v": rng.randint(0, 4)}
            st["data"] = data
        elif k < 0.82:
            st["call"] = "turn_off"
            st["data"] = {"entity_id": rng.choice([rng.choice(ents), "all", rng.sample(ents, min(2, len(ents)))])}
        elif k < 0.88:
            st["call"] = "toggle"
            st["data"] = {"entity_id": rng.sample(ents, rng.randint(1, min(2, len(ents))))}
        elif k < 0.93:
            new = copy.deepcopy(current)
            name = rng.choice(list(new))
            kk = rng.random()
            if kk < 0.4:
                new[name]["alias"] = f"Reloaded {name}"
            elif kk < 0.7 and len(new) > 2:
                del new[name]
            else:
                i = g.names.index(name)
                new[name]["sequence"] = g.seq(i, 0, 1, 3)
                if loops(new):
                    new[name]["sequence"] = [{"event": "mark", "event_data": {"id": g.mark(name)}}]
            st["reload"] = new
            current = new
        # else: a tick
        sc["steps"].append(st)
    return sc


def main() -> None:
    seed, count, out = int(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    for i in range(count):
        sc = scenario(seed, i)
        (out / f"r{seed}_{i:04d}.yaml").write_text(yaml.safe_dump(sc, sort_keys=False, width=200))


if __name__ == "__main__":
    main()
