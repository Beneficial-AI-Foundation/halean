# 02-shipped-tests

Rerun, from the repository root, after the build:

```bash
review/experiments/02-shipped-tests/run_all.sh run1      # every shipped test once; logs/run1-*.log
review/experiments/02-shipped-tests/run_all.sh run2      # second run
/opt/havenv/bin/python -m pytest tests/differential -p no:cacheprovider -q -rs   # same suite from the shared venv, with skip reasons (logs/run3-...)
```

`run_all.sh` runs, as the README's Setup section writes them: `tests/run_scenarios.py`, `tests/run_script_scenarios.py`,
`tests/bridge_e2e.py`, `tests/sun/compare.py` (with astral 2.2), `tests/differential/run.py`, `tests/live/docker_e2e.py`.

Notes:

* `tests/live/docker_e2e.py` pulls `ghcr.io/home-assistant/home-assistant:2026.10.4`. The blob host of ghcr.io is not
  reachable from this environment, so the layers were first pulled from Docker Hub
  (`homeassistant/home-assistant:2026.10.4`); `docker pull` of the ghcr name then completed from the ghcr manifest
  with the layers already present (`logs/live-ghcr-pull.log`, `logs/live-image.txt`: image ids and the
  `io.hass.version` label). The Docker daemon was started by hand (`dockerd`).
* `logs/differential-test-counts.txt`: collected tests per test function.
* Mutation checks of the README's sensitivity claims are in `review/experiments/04-core-registry-hass/mutations/`
  (scheduler, README lines 410-413) and `review/experiments/07-automation/mutations/` (nested condition, lines 115-116).
