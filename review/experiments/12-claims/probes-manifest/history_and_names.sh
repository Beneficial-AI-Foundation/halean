#!/bin/bash
# git history of the six missing Lean names and of note phrases; existence of theorems, tests and names cited in notes.
# Output: logs-manifest/git-history.log, logs-manifest/names-in-notes.log
L="$(cd "$(dirname "$0")/.." && pwd)/logs-manifest"
cd /home/user/halean
{
for s in "partial def startScript" "partial def finishBranch" "partial def answer" "partial def continueNow" "partial def cancelRun" "partial def releaseQueue"; do
  echo "== git log -S'$s' -- HALean/Automation/Engine.lean"; git log --format='%h %ad %s' --date=short -S"$s" -- HALean/Automation/Engine.lean | cat; done
for s in "templated 'for' rejected" "templated for: rendered when the trigger matches" "static for: only" "templated for: supported" "trigger_variables unsupported" "last_changed/last_updated/context are opaque" "HALean.Automation.startScript" "HALean.Automation.finishBranch"; do
  echo "== git log -m -S'$s' -- manifest.yaml"; git log -m --format='%h %ad %s' --date=short -S"$s" -- manifest.yaml | cat; done
echo "== git log -S'lastChangedUs' -- HALean/"; git log --format='%h %ad %s' --date=short -S"lastChangedUs" -- HALean/ | cat
echo "== git log --grep trigger_variables"; git log --format='%h %ad %s' --date=short --grep="trigger_variables" f638a37 | cat
} > "$L/git-history.log" 2>&1
{
for t in State.new_ok checkRange_ok checkRange_min checkRange_max checkRange_not_number checkIn_ok_iff checkNotIn_ok_iff checkCoerce_int ensureList_is_list ensureList_list checkPort_range quiet fireInternal_first runListener_deliveries slugifyChars_valid slugifyChars_of_valid slugify_fixed_iff; do
  n=${t##*.}; echo "theorem $t: $(grep -rn "^\s*\(protected \)\?theorem \(.*\.\)\?$n\b" HALean | head -1 | cut -c1-110)"; done
echo "test_as_dict_cache_is_stale_after_report: $(grep -n 'def test_as_dict_cache_is_stale_after_report' tests/differential/test_states.py)"
echo "tests/sun/compare.py: $(ls tests/sun/compare.py 2>&1)"
echo "Handle.done / Handle.onc: $(grep -n '^  | done (t : Nat)\|^  | onc (t : Nat)' HALean/Core/Hass.lean | tr '\n' ' ')"
echo "Hass.asyncJobs: $(grep -n 'asyncJobs : List Nat' HALean/Core/Hass.lean)"
echo "Frame.handlerRet: $(grep -n '| handlerRet' HALean/Core/Hass.lean | head -1)"
echo "VErr.raise: $(grep -n '| raise (exception message : String)' HALean/Core/Probatio.lean)"
echo "RunEnd.raises: $(grep -n 'def RunEnd.raises' HALean/Automation/Script.lean)"
echo "Engine.haStart: $(grep -n '^  haStart :' HALean/Automation/Engine.lean)"
echo "Helpers.vIcon: $(grep -n 'def vIcon' HALean/Helpers/Common.lean)"
echo "decodeCv icon: $(grep -n '\"icon\" => pure' HALean/Core/ServicesJson.lean)"
echo "'executor' in HALean/Core/Hass.lean and Exe/Core.lean (case-insensitive): $(grep -ic 'executor' HALean/Core/Hass.lean Exe/Core.lean | tr '\n' ' ')"
echo "theorems about drain: $(grep -n 'theorem.*drain' HALean/Core/*.lean | cut -d: -f1,2,3 | cut -c1-90 | tr '\n' ';')"
echo "entries that carry one of the six missing names (all 402 entries):"
/opt/havenv/bin/python -B -c "
import yaml
d=yaml.safe_load(open('manifest.yaml'))
miss={'HALean.Automation.'+n for n in ('answer','cancelRun','continueNow','finishBranch','releaseQueue','startScript')}
for i,e in enumerate(d['entries'],1):
    m=miss & set(e['lean'])
    if m: print(f'  M-{i}', e['status'], e['python'], sorted(m))"
} > "$L/names-in-notes.log" 2>&1
