#!/usr/bin/env python
"""Probes of halean-core, halean-core-states, halean-core-events, halean-core-services for manifest notes (core area).
Output: logs-manifest/probe-core.log"""
import json, subprocess
B = "/home/user/halean/.lake/build/bin/"
N = 1763656245123456
G = [
 ("M-274", "halean-core", "HassJobType: 'Executor is rejected' - is there a refusal for an executor job? (unknown key 'executor')",
  [{"op": "listen", "id": "l", "event_type": "e", "executor": True, "job_type": "Executor", "now": N},
   {"op": "fire", "event_type": "e", "now": N + 1}]),
 ("M-274/M-275/M-239", "halean-core", "async listener (coroutine function) and @callback listener",
  [{"op": "listen", "id": "a", "event_type": "e", "async": True, "react": [{"sleep": 0}, {"fire": {"event_type": "after_sleep"}}], "now": N},
   {"op": "listen", "id": "c", "event_type": "e", "now": N},
   {"op": "listen", "id": "x", "event_type": "after_sleep", "now": N},
   {"op": "fire", "event_type": "e", "now": N + 1}, {"op": "block_till_done", "now": N + 2}]),
 ("M-182/M-223", "halean-core-states", "fresh context of the state machine is ulid:<n>; a given id is kept",
  [{"op": "set", "entity_id": "light.a", "state": "on", "now": N},
   {"op": "set", "entity_id": "light.b", "state": "on", "context": {"id": "abc", "user_id": "u"}, "now": N}]),
 ("M-223/M-225", "halean-core-events", "event without context: ulid@<ms>#<n>",
  [{"op": "listen", "id": "l", "event_type": "e", "now": N}, {"op": "fire", "event_type": "e", "now": N}]),
 ("M-223", "halean-core-services", "registry: a call without context gets the symbolic id 'new'",
  [{"op": "register", "domain": "d", "service": "s", "handler": {"echo": True}, "now": N},
   {"op": "call", "domain": "d", "service": "s", "data": {}, "blocking": True, "return_response": False, "now": N}]),
 ("M-188", "halean-core-states", "as_dict is the fresh value after a report (last_reported moves)",
  [{"op": "set", "entity_id": "light.a", "state": "on", "now": N}, {"op": "set", "entity_id": "light.a", "state": "on", "now": N + 1000000},
   {"op": "get", "entity_id": "light.a"}]),
 ("M-202", "halean-core-states", "async_set: str() of a non-string state",
  [{"op": "set", "entity_id": "light.a", "state": 5, "now": N}, {"op": "set", "entity_id": "light.b", "state": True, "now": N},
   {"op": "set", "entity_id": "light.c", "state": None, "now": N}, {"op": "set", "entity_id": "light.d", "state": 1.5, "now": N}]),
 ("M-235/M-237", "halean-core-events", "run_immediately raises RuntimeError; listen_once with a filter is TypeError",
  [{"op": "listen", "id": "l", "event_type": "e", "run_immediately": True, "now": N},
   {"op": "listen_once", "id": "m", "event_type": "e", "filter": True, "now": N}]),
 ("M-208/M-210", "halean-core-services", "supports_response: KeyError for a missing domain, then for a missing service (the domain test for services_for_domain is in ../logs/core-probes.log, group V4)",
  [{"op": "register", "domain": "D", "service": "S", "handler": {"return": None}, "now": N},
   {"op": "supports_response", "domain": "nope", "service": "s", "now": N}, {"op": "supports_response", "domain": "d", "service": "nope", "now": N}]),
]
log = open(__file__.rsplit("/", 2)[0] + "/logs-manifest/probe-core.log", "w")
def out(s):
    print(s); print(s, file=log)
for mid, exe, what, lines in G:
    r = subprocess.run([B + exe], input="".join(json.dumps(l) + "\n" for l in lines), capture_output=True, text=True, timeout=60)
    out(f"=== {mid} [{exe}] {what}")
    for l, rep in zip(lines, r.stdout.splitlines()):
        out("  > " + json.dumps(l)[:260]); out("  < " + (rep if len(rep) < 700 else rep[:700] + "…"))
    if r.stderr.strip(): out("  stderr: " + r.stderr.strip()[:300])
