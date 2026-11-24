#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pytest-homeassistant-custom-component==0.13.375", "pyyaml"]
# ///
"""Run the differential tests (real Home Assistant vs the Lean engine).

Needs the engines built first (`lake build halean-automation halean-script halean-template
halean-core halean-core-states halean-core-services halean-core-events`). Extra args go to pytest, e.g.
  uv run tests/differential/run.py -k mode_queued -vv
"""

import sys
from pathlib import Path

import pytest

here = Path(__file__).resolve().parent
sys.exit(pytest.main([str(here), "-p", "no:cacheprovider", "-q", *sys.argv[1:]]))
