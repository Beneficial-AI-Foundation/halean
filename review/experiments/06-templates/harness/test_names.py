"""Review helper (not shipped): compare HALean's GLOBALS / FILTERS / TESTS lists
(HALean/Template/Render.lean) with what HA's TemplateEnvironment registers.
Run: /opt/havenv/bin/python -m pytest harness/test_names.py -p no:cacheprovider -q -s"""
import re
from homeassistant.helpers.template import TemplateEnvironment

SRC = open("/home/user/halean/HALean/Template/Render.lean").read()


def lst(name):
    m = re.search(r"def %s : List String :=\s*\[(.*?)\]" % name, SRC, re.S)
    return re.findall(r'"([^"]+)"', m.group(1))


async def test_names(hass):
    env = TemplateEnvironment(hass)
    for role, names, have in (("global", lst("GLOBALS"), env.globals), ("filter", lst("FILTERS"), env.filters),
                              ("test", lst("TESTS"), env.tests)):
        print(f"\nNAMES {role}: in HALean but not in HA: {[n for n in names if n not in have]}")
