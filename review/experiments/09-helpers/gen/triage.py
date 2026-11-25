#!/usr/bin/env python3
"""Summarise a pytest log of harness/test_helpers.py: one block per failed case
(case name, step, HA result, HALean result or the rejection), truncated to WIDTH."""
import re, sys
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 600
name = None
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"_+ test_helpers\[(.*)\] _+$", line)
    if m:
        name = m.group(1); continue
    if line.startswith("E  ") and name:
        t = line[1:].strip()
        if t.startswith(("AssertionError: step", "HA:", "HALean:", "HALean rejected", "HALean should")) or "Error" in t.split(":")[0]:
            if t.startswith("AssertionError: step"): print("==", name)
            print("  ", t[:WIDTH])
    m = re.match(r"=+ (.*(passed|failed).*) =+$", line) or re.match(r"(\d+ (passed|failed).*)$", line)
    if m: print("SUMMARY", m.group(1))
