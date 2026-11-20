"""Compare HALean's sunrise/sunset scheduling with astral + HA's
`get_observer_astral_event_next`, to the microsecond, over a grid of
locations, elevations, dates, offsets and time zones (including polar days
and nights). Run: uv run --with astral==2.2 tests/sun/compare.py"""
import datetime, random, subprocess, sys
from pathlib import Path
import astral.sun
from astral import Observer

ROOT = Path(__file__).resolve().parents[1].parent

def ha_next(obs, event, now, tz, offset):
    # helpers/sun.py::get_observer_astral_event_next, with as_local = fixed offset
    local = (now + datetime.timedelta(seconds=tz)).date()
    func = getattr(astral.sun, event)
    for mod in range(-1, 367):
        try:
            t = func(obs, local + datetime.timedelta(days=mod)) + offset
            if t > now:
                return t
        except ValueError:
            pass
    return None

random.seed(7)
cases = []
for _ in range(3000):
    lat = random.choice([random.uniform(-66, 66), random.uniform(-89.9, 89.9), 0.0, 69.65, -77.8])
    lon = random.uniform(-180, 180)
    elev = random.choice([0, 0, 120, 2500.5, -10])
    now = datetime.datetime(2000, 1, 1, tzinfo=datetime.UTC) + datetime.timedelta(
        seconds=random.randrange(0, 40 * 365 * 86400), microseconds=random.randrange(0, 10**6))
    tz = random.choice([0, 3600, -18000, 19800, 46800])
    off = datetime.timedelta(seconds=random.choice([0, 0.5, -3600, 5400.25]))
    ev = random.choice(["sunrise", "sunset"])
    cases.append((lat, lon, elev, ev, now, tz, off))

lines = []
for lat, lon, elev, ev, now, tz, off in cases:
    now_us = int(now.timestamp()) * 10**6 + now.microsecond
    off_us = (off.days * 86400 + off.seconds) * 10**6 + off.microseconds
    lines.append(f"{lat!r} {lon!r} {float(elev)!r} {1 if ev == 'sunrise' else 0} {now_us} {tz} {off_us}")
exe = ROOT / ".lake" / "build" / "bin" / "halean-sun-grid"
out = subprocess.run([str(exe)], input="\n".join(lines) + "\n", capture_output=True, text=True, check=True).stdout.split()
bad = 0
for (lat, lon, elev, ev, now, tz, off), got in zip(cases, out):
    t = ha_next(Observer(lat, lon, elev), ev, now, tz, off)
    want = "none" if t is None else str(int(t.timestamp()) * 10**6 + t.microsecond)
    if want != got:
        bad += 1
        if bad <= 10:
            print("MISMATCH", lat, lon, elev, ev, now, tz, off, "want", want, "got", got)
print(f"{len(cases) - bad}/{len(cases)} match")
sys.exit(1 if bad else 0)
