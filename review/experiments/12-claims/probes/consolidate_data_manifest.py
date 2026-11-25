# Verdicts for manifest.yaml entries. Key: python ref. Value: (verdict, evidence, sources, disagreement or None)
AE, AO, CR, CS, SH, TE = ("automation-engine.md", "automation-other.md", "core-registry-schemas.md",
                          "core-states-bus-hass.md", "scripts-helpers.md", "templates.md")
C, W, O = "correct", "correct for the wrong reason", "overstated"

def cond(extra):
    return (W, extra, [AE, AO],
            "automation-engine: overstated (judged the cited theorems only). automation-other: correct for the wrong reason. "
            "Decided by reading `Automation/ConditionSpec.lean`.")

PROVEN = {
 "helpers/condition.py::AndConditionChecker._async_check": cond(
    "Cited: empty list and all-disabled list. Not cited: `evalAnd_true_iff` (ConditionSpec.lean:665), `evalAnd_false_iff` (:642), `evalAnd_ne_none` (:687) fix true / false / error from `evalCond` of the members. The error text is not fixed."),
 "helpers/condition.py::OrConditionChecker._async_check": cond(
    "Cited: empty list. Not cited: `evalOr_true_iff` (:695), `evalOr_false_iff` (:717), `evalOr_ne_none` (:739) fix true / false / error. The error text is not fixed."),
 "helpers/condition.py::NotConditionChecker._async_check": cond(
    "Cited: `not [disabled]`. Not cited: `evalNot_eq_negate_evalOr` (:752), `evalNot_true_iff` (:779), `evalNot_false_iff` (:768)."),
 "helpers/condition.py::DisabledConditionChecker._async_check": (C,
    "`evalCond env .disabled = .ok none` is the whole upstream function.", [AE, AO], None),
 "helpers/condition.py::ConditionsChecker.async_check": cond(
    "Cited: empty list. Not cited: `checkAutomationConditions_iff` (:830) fixes the Bool result; it is what states \"errors count as False\"."),
 "helpers/script.py::_ScriptRun._test_conditions": cond(
    "Cited: `rfl` on the empty list. Not cited: `testConditions_true_iff` (:846) and `testConditions_false_iff` (:872) fix `some true` and `some false`; `none` is the rest."),
 "helpers/script.py::Script.async_run": (O,
    "All four cited theorems are about `admit`. `triggerAutomation` has branch theorems that stop at `drive`. `HALean.Automation.startScript` is not a declaration (it is `startScriptH`).", [AE], None),
 "helpers/event.py::process_state_match": (W,
    "Cited: two properties. `stateMatch_matches_iff` (EngineSpec.lean:231), not cited, fixes the Bool result.", [AE], None),
 "helpers/template/__init__.py::is_template_string": (C,
    "`isTemplateString_iff` fixes the result. The note text is cut off after `\"{#\" is`.", [TE], None),
 "helpers/config_validation.py::boolean": (C,
    "The note limits the theorem to strings. `cvBooleanText_iff` fixes the string case against `CvBooleanSpec`; `cvBoolean_str` (Template/RenderSpec.lean:116, `rfl`) and `cvBoolean_str_iff` (Core/ConfigValidationSpec.lean:143) link both `cvBoolean` definitions to it. Not fixed by a theorem: the `float` branch, the error text.",
    [CR, TE],
    "core-registry-schemas: overstated (error text, `float` and other types not fixed). templates: correct. Decided `correct`: the note claims the theorem for strings only and calls the other branches \"direct\"; the definitions' non-string branches are one line each (Render.lean:191-197, ConfigValidation.lean:34-47)."),
 "core.py::valid_entity_id": (C, "`validEntityId_iff` (Core/StateSpec.lean:220) fixes the result against `EntityIdRe`. `Template.validEntityId` is an alias (Render.lean:158-161).", [CS, TE], None),
 "core.py::valid_domain": (C, "`validDomain_iff` (StateSpec.lean:281) fixes the result against `DomainRe`.", [CS, TE], None),
 "util/dt.py::parse_time": (O,
    "The theorem exists and states the note. The specification's `int()` has no 4300-digit limit: for `\"0\"*4301 + \"1:00\"` upstream returns `None`, `parseTimeSeconds` returns `some 3600` (re-run here). On non-ASCII digits upstream returns a time, HALean `none`.", [TE], None),
 "core.py::split_entity_id": (C, "`splitEntityId_some` (StateSpec.lean:323) fixes the result.", [CS], None),
 "core.py::States.domain_entity_ids": (O, "`mem_domainEntityIds` is membership only. The order named in the note is not in the theorem.", [CS], None),
 "core.py::StateMachine.async_remove": (O, "Three properties. Return value, event and other entities' states are not fixed. No theorem for `Hass.runAction` / `smQueued`.", [CS], None),
 "core.py::StateMachine.async_reserve": (O, "One property, for ASCII lower-case ids. When it raises is not stated.", [CS], None),
 "core.py::StateMachine.async_set_internal": (O, "The stored state and attributes of the change branch are not fixed. `set_delivers_first` needs a given context.", [CS], None),
 "core.py::ServiceRegistry.has_service": (O, "Two properties. `hasService_eq_asyncServicesForDomain` (not cited) rewrites the result through another model function.", [CR], None),
 "core.py::ServiceRegistry._async_register": (O, "One property of `Registry.register`. Nothing on the fired event, on replacing a service, on other services, on `Hass.runAction` / `firedQueued`.", [CR, CS], None),
 "core.py::ServiceRegistry._async_remove": (O, "Two properties (the second assumes `WF`). Nothing on the event, the warning, other services, the joined core.", [CR, CS], None),
 "core.py::ServiceRegistry.async_call": (O, "Four error paths of `Registry.asyncCall`, each under `WF`. The successful path is not fixed. The cited theorems do not mention `mergeTarget`, `callResponse`, `normalizeTargetIds`, `Hass.callService`.", [AE, CR, CS, SH], None),
 "core.py::_OneTimeListener.__call__": (O, "An upper bound for the stand-alone bus. `Hass.useOnce`, `Hass.runJob`, `Hass.runListener` are not covered by it.", [CS], None),
 "core.py::EventBus._async_dispatch": (O, "For `Hass.dispatchLoop` the delivery list is fixed (under `NoUnsup`); logs and the resulting core are not. For `EventBus.dispatch` only `snapshot` and safety properties.", [CS], None),
 "core.py::EventBus._async_remove_listener": (O, "Properties of the stand-alone bus. The log entry and the re-created list named in the note have no theorem. `Hass.removeListener` is not covered.", [CS], None),
 "core.py::HomeAssistant._async_add_hass_job": (O, "Two properties. Task creation is not characterised.", [CS], None),
 "core.py::HomeAssistant.async_block_till_done": (O, "One conditional property.", [CS], None),
 "helpers/config_validation.py::slug": (O, "`slugify_fixed_iff` is about `slugify?`, under `slugify? s ≠ none`. The only link to `cvSlug` is `cvSlug_ok` (accepted implies fixed point). The converse is not proved.", [CR, AO], None),
 "helpers/entity.py::ToggleEntity.async_toggle": (O, "Involution; state flips. Does not state that `cfg` is kept.", [SH], None),
 "components/input_boolean/__init__.py::InputBoolean.async_turn_on": (O, "Idempotent; state `on`.", [SH], None),
 "components/input_boolean/__init__.py::InputBoolean.async_turn_off": (O, "Idempotent; state `off`.", [SH], None),
 "components/input_number/__init__.py::InputNumber.async_set_native_value": (O, "Success implies bounded and `cfg` kept; out of range gives `Invalid`. Stored value and success condition are not stated.", [SH], None),
 "components/input_number/__init__.py::InputNumber.async_increment": (O, "Success implies bounded. True for any new value.", [SH], None),
 "components/input_number/__init__.py::InputNumber.async_decrement": (O, "Success implies bounded. True for any new value.", [SH], None),
 "components/input_select/__init__.py::InputSelect.__init__": (O, "One invariant under two hypotheses.", [SH], None),
 "components/input_select/__init__.py::InputSelect.async_added_to_hass": (O, "One invariant under two hypotheses.", [SH], None),
 "components/input_select/__init__.py::InputSelect.async_select_option": (O, "Invariant. `current = option` is not stated.", [SH], None),
 "components/input_select/__init__.py::InputSelect.async_set_options": (O, "Invariant for a non-empty list.", [SH], None),
 "components/select/__init__.py::SelectEntity.state": (O, "Result for valid entities only.", [SH], None),
 "components/select/__init__.py::SelectEntity.async_first": (O, "Invariant. Not that the first option is selected.", [SH], None),
 "components/select/__init__.py::SelectEntity.async_last": (O, "Invariant. Not that the last option is selected.", [SH], None),
 "components/select/__init__.py::SelectEntity.async_next": (O, "Invariant. Not which option.", [SH], None),
 "components/select/__init__.py::SelectEntity.async_previous": (O, "Invariant. Not which option.", [SH], None),
 "components/select/__init__.py::SelectEntity._async_offset_index": (O, "Invariant. Not which option.", [SH], None),
 "components/select/__init__.py::SelectEntity._async_select_index": (O, "Invariant. `atMod` is not mentioned.", [SH], None),
 "components/counter/__init__.py::Counter.compute_next_state": (O, "Two bounds. Not the value (for example `clamp v = v` in range).", [SH], None),
 "components/counter/__init__.py::Counter.async_increment": (O, "Bound under `Consistent`. True for any argument of `clamp`.", [SH], None),
 "components/counter/__init__.py::Counter.async_decrement": (O, "Bound under `Consistent`. True for any argument of `clamp`.", [SH], None),
 "components/counter/__init__.py::Counter.async_reset": (O, "Bound under `Consistent`. True for any argument of `clamp`.", [SH], None),
 "components/counter/__init__.py::Counter.async_set_value": (O, "Success result fixed; failure conditions not stated. The note's \"step 0 raises ZeroDivisionError\" has no theorem.", [SH], None),
 "components/timer/__init__.py::Timer.async_cancel": (O, "The theorem is about `toIdle`. `cancel` is not in the statement.", [SH], None),
 "components/timer/__init__.py::Timer.async_finish": (O, "The theorem is about `toIdle`. `finish` is not in the statement.", [SH], None),
 "components/timer/__init__.py::Timer._async_finished": (O, "The theorem is about `toIdle` and `due`. `finished` is not in the statement.", [SH], None),
}

TRANSLATED = {
 "util/__init__.py::slugify": (C, "Each theorem states what the note says. `translated` fits: the output is not fixed.", [AO], None),
 "probatio:validators/comparison.py::Range.__call__": (C, "The four theorems exist and state the note.", [CR], None),
 "probatio:validators/comparison.py::In.__call__": (C, "The theorem exists. It is relative to the opaque `pyEq`.", [CR], None),
 "probatio:validators/comparison.py::NotIn.__call__": (C, "The theorem exists. It is relative to the opaque `pyEq`.", [CR], None),
 "probatio:validators/coerce.py::Coerce.__call__": (C, "The theorem exists.", [CR], None),
 "probatio:validators/structural.py::EnsureList.__call__": (C, "Both theorems exist.", [CR], None),
 "probatio:validators/network.py::Port.__call__": (C, "The theorem exists.", [CR], None),
 "core.py::State.__init__": (C, "`HALean.Core.StateMachine.State.new_ok` exists. The note names it only.", [CS], None),
 "core.py::EventBus.async_fire_internal": (C, "`quiet`, `fireInternal_first` exist. The note says the `drain` bound is not proved; no theorem bounds `drain`.", [CS], None),
 "core.py::HomeAssistant.async_run_hass_job": (C, "`runListener_deliveries` exists. The note names it only.", [CS], None),
}
