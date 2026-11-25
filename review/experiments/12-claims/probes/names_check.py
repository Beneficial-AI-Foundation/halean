"""Existence and location of every Lean name the README cites (lines 54-55, 275, 346, 374-391, 415-425,
451, 483, 530-535, 577-642, 693-696, 793). Prints: name | README file | found as | actual file:line."""
import re, subprocess, pathlib
R = pathlib.Path("/home/user/halean")
THEOREMS = {
 "HALean/Automation/Proofs.lean": "evalAnd_nil evalOr_nil evalCond_disabled evalNot_disabled evalAnd_all_disabled checkAutomationConditions_nil testConditions_nil match_invert match_all single_exclusive restart_never_rejects admit_bounded queued_waits templateCond_static",
 "HALean/Core/StateSpec.lean": "validEntityId_iff validDomain_iff splitEntityId_some",
 "HALean/Template/PyIntSpec.lean": "parseIntChars_iff",
 "HALean/Template/ParseTimeSpec.lean": "parseTimeSeconds_iff",
 "HALean/Template/SyntaxSpec.lean": "isTemplateString_iff",
 "HALean/Template/CvBooleanSpec.lean": "cvBooleanText_iff",
 "HALean/Automation/SlugifySpec.lean": "slugify_fixed_iff slugifyChars_valid",
 "HALean/Template/Proofs.lean": "render_static resultAsBoolean_none cvBoolean_bool iif_none iif_truthy",
 "HALean/Core/Proofs.lean": "set_same_only_reports set_same_state_keeps_last_changed set_frame set_keys remove_keys mem_domainEntityIds remove_then_get_none reserve_then_unavailable",
 "HALean/Core/ServiceRegistryProofs.lean": "has_after_register has_after_remove call_after_remove_not_found call_none_return_response_errors call_only_needs_return_response call_return_response_needs_blocking wf_register wf_remove",
 "HALean/Core/ProbatioProofs.lean": "checkIn_ok_iff checkNotIn_ok_iff checkRange_ok checkRange_min checkRange_max checkRange_not_number ensureList_is_list ensureList_list checkCoerce_int checkPort_range",
 "HALean/Core/EventBusProofs.lean": "once_at_most_once gone_silent reachable_wf unsub_gone_reachable unsub_silent snapshot_match_all snapshot_excluded",
 "HALean/Core/HassProofs.lean": "quiet dispatchLoop_deliveries fireInternal_first set_delivers_first",
 "HALean/Script/Proofs.lean": "callResponse_no_response callResponse_dict entityState_on stopped_nested_cancels supportsMax_iff",
 "HALean/Automation/EngineBound.lean": "runs_bounded",
}
DEFS = {
 "HALean/Automation/Engine.lean": "step startScript callLocal stopRun STEP_FUEL ENGINE_FUEL LOOP_FUEL",
 "HALean/Core/StateMachine.lean": "asyncSet asDict",
 "HALean/Core/ServiceRegistry.lean": "prepareCall finishCall FiredEvent",
 "HALean/Core/Hass.lean": "Hass ready tasks susp Action",
 "HALean/Core/EventBus.lean": "step drain Queued",
 "HALean/Core/State.lean": "Context",
 "HALean/Helpers/Common.lean": "HM",
 "HALean/Helpers/Component.lean": "setup call tick",
}
FILES = "HALean/Core/HassSchedProofs.lean HALean/Script/Entity.lean HALean/Helpers/Pattern.lean HALean/Core/Probatio.lean HALean/Core/ConfigValidation.lean HALean/Core/Schema.lean HALean/Core/ServicesJson.lean HALean/Core/ServiceRegistry.lean HALean/Core/StateMachine.lean HALean/Core/EventBus.lean HALean/Core/Hass.lean HALean/Automation HALean/Template HALean/Script HALean/Helpers Exe/CoreServices.lean Exe/Core.lean Exe/CoreEvents.lean Exe/Helpers.lean tests/differential/schema_spec.py tests/core/services/validators.yaml LICENSE NOTICE LICENSES PROPERTIES.md demo/automations.yaml bridge/protocol.py".split()
def grep(pat, path="HALean"):
    r = subprocess.run(["grep", "-rnE", pat, path], cwd=R, capture_output=True, text=True).stdout.strip().splitlines()
    return r
bad = 0
print("## theorems")
for f, names in THEOREMS.items():
    for n in names.split():
        hits = grep(rf"^\s*(private |protected )?(theorem|lemma)\s+([A-Za-z0-9_.]*\.)?{re.escape(n)}\b")
        here = [h for h in hits if h.startswith(f + ":")]
        status = "OK" if here else ("ELSEWHERE" if hits else "MISSING")
        bad += status != "OK"
        print(f"{n} | {f} | {status} | {'; '.join(':'.join(h.split(':')[:2]) for h in (here or hits))}")
print("## definitions")
for f, names in DEFS.items():
    for n in names.split():
        hits = grep(rf"^\s*(private |protected |partial |@\[[^\]]*\]\s*)*(def|abbrev|structure|inductive|theorem|instance)\s+([A-Za-z0-9_.]*\.)?{re.escape(n)}\b|^\s*\|?\s*{re.escape(n)}\s*[:(]|^\s+{re.escape(n)}\s*:")
        here = [h for h in hits if h.startswith(f + ":")]
        status = "OK" if here else ("ELSEWHERE" if hits else "MISSING")
        bad += status != "OK"
        print(f"{n} | {f} | {status} | {'; '.join(':'.join(h.split(':')[:2]) for h in (here or hits)[:4])}")
print("## files")
for f in FILES:
    ok = (R / f).exists(); bad += not ok
    print(f"{f} | {'OK' if ok else 'MISSING'}")
print("not OK:", bad)
