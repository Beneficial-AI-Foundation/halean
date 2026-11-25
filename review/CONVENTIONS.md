# Conventions for every experiment under `review/`

Reviewed HALean commit: `f638a3779195a42a5162939aa67981b9b501618e` (see `review/logs/halean-commit.txt`).
Reference: Home Assistant `2026.10.4` (commit `357cae5c598dfcd7a0ea7dc5b1facccd4ec6037b`), Jinja2 3.1.6, probatio 0.13.0
(`manifest.yaml` → `upstream:`).

## Environment (already set up; do not reinstall)

| What | Where |
|---|---|
| Lean 4.36.0 + lake | `export PATH=$HOME/.elan/bin:$PATH` |
| Built executables (library and all nine exes, unpatched) | `/home/user/halean/.lake/build/bin/halean-*` |
| Python 3.14 venv with `pytest-homeassistant-custom-component==0.13.375` (HA 2026.10.4, Jinja2 3.1.6, probatio 0.13.0), pyyaml, astral 2.2 | `/opt/havenv/bin/python` (log: `review/logs/ha-install.txt`) |
| Upstream source for reading (sparse checkout of the tag) | `/home/user/halean/upstream/ha-core/homeassistant/...` |
| Installed HA / probatio / jinja2 source (full) | `/opt/havenv/lib/python3.14/site-packages/{homeassistant,probatio,jinja2}` |
| Shipped harness | `tests/differential/*.py`, `tests/run_scenarios.py`, `tests/run_script_scenarios.py` |

Run a harness copy with: `/opt/havenv/bin/python -m pytest <dir-or-file> -p no:cacheprovider -q ...`
(the shipped `pytest.ini` sets `asyncio_mode = auto`; copy it next to your harness copy).

## Hard rules

1. Never modify anything under `HALean/`, `Exe/`, `tests/`, `bridge/`, `tools/`, `manifest.yaml`, `README.md`,
   `PROPERTIES.md` in `/home/user/halean`. Never run `lake build` in `/home/user/halean` (others read those binaries).
2. Write only inside your own directory `review/experiments/<your-area>/` (and your scratch copies, below).
3. Patches and mutations are tested only in a throwaway copy:
   `cp -a /home/user/halean /tmp/claude-0/halean-copies/<your-area>-<n>` (includes `.lake`, so the rebuild is incremental),
   patch there, `lake build <exe>` there, run tests there. Save the patch as `patches/<ID>.patch`
   (`git -C <copy> diff > .../patches/<ID>.patch`) and the test logs under `logs/`. Delete copies you no longer need
   (each is ~1.3 GB). The machine has 4 cores and 16 GB shared with other reviewers: at most one `lake build` at a
   time per reviewer, and do not run pytest with `-n`.
4. The harness copy: copy the shipped differential test file(s) for your area into
   `review/experiments/<your-area>/harness/`, and change only (a) the case directory, so that it reads your
   `cases/` directory, and (b) the engine path, so that it can be overridden with the environment variable
   `HALEAN_BIN` (default `/home/user/halean/.lake/build/bin`). Keep the comparison logic unchanged; if you must
   change it (for example to record both results instead of asserting), say so in your README and keep the
   shipped assertion semantics as the pass/fail verdict.
5. Every divergence is reported only if it reproduced on two or more separate runs. Keep both logs
   (`logs/run1-*.log`, `logs/run2-*.log`). Random generators take a seed; record the seeds; a random case that
   diverges is minimised by hand and added to `cases/` as a named hand-written reproducer.
6. Do not trust `README.md`; verify. But do check for each divergence whether the README (sections "Known gaps",
   the "Rejected / not modelled" table columns, "Known gaps and deviations" at line ~643) lists it. Quote the
   README line (with line number) if it does.

## Divergence kinds

* **Silent**: both sides give an answer, the answers differ, HALean reports no error.
* **Accepts**: HALean accepts (gives a result for) what HA refuses (raises / rejects the config).
* **Refuses**: HALean refuses (error or `unsupported`) what HA accepts. If the README lists the refusal as
  outside the subset, it is a documented gap, not a bug; still list it, flagged `documented`.
* **Order**: same items, different order.
* **Tooling**: the harness, test driver, bridge or drift tool is wrong (not the Lean model).

## Deliverables per area (all under `review/experiments/<your-area>/`)

* `README.md`: what the area is, exactly how to rerun everything (commands), what each file is.
* `cases/`: new hand-written cases (YAML in the shipped format). `gen/`: the random generator script and its seeds.
* `harness/`: the harness copy. `logs/`: every run log (two runs minimum). `patches/`: patches with their test logs.
* `side-by-side.md`: the reading comparison: for each `manifest.yaml` entry of the area (or each group of
  entries), the upstream function (file:line in `upstream/ha-core` or site-packages), the Lean definition
  (file:line), and what differs (or "no difference found"). Be specific; cite lines.
* `FINDINGS.md`: the result, in this exact structure:
  1. `## Counts`: number of new hand-written cases, number of random cases per run, number of runs, number of
     cases that diverge. Each number with the log file it comes from.
  2. `## Divergences`: a table with columns `ID | reproducer (case file::name) | HA result | HALean result | kind |
     README lists it? (line) | patch? (file, shipped tests still pass? log)`. IDs are `<AREA>-<n>`. One row per
     distinct root cause, not per case.
  3. `## Details`: per ID, the minimal reproducer inline, both outputs copied from the logs, root cause with
     Lean file:line and upstream file:line.
  4. `## Reading findings without a reproducer`: differences seen by reading that you could not drive through
     the harness (say why).
  5. `## Notes on the harness`: anything the shipped harness cannot observe in this area (blind spots).

Write plainly: short sentences, no hedging adjectives, no marketing words. Every number must name its log file.
When a patch is tested, "shipped tests still pass" means: in the throwaway copy with the patch, rebuild the
affected executables and run the shipped suites that use them (`tests/differential/run.py -k <area>` equivalents
via `/opt/havenv/bin/python -m pytest <copy>/tests/differential -p no:cacheprovider -q`, plus
`python tests/run_scenarios.py` / `tests/run_script_scenarios.py` where the engine is touched), log saved.
