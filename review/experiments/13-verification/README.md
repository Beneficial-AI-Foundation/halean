# 13-verification: the lead reviewer's own re-check of a sample of findings

Purpose: confirm a sample of the area reviewers' divergences a third and fourth time, without their harness copies.

* `cases/cases.yaml` + `harness/test_templates.py`: 19 minimal template reproducers written by the lead reviewer for a
  sample of `TPL-*` IDs, plus one control. The harness is the shipped `tests/differential/test_templates.py` with
  two path lines changed (case directory, engine path). Rerun:
  `/opt/havenv/bin/python -m pytest review/experiments/13-verification/harness/test_templates.py -p no:cacheprovider -q -rf`
  Logs: `logs/templates-run1.log`, `logs/templates-run2.log` (16 failed, 4 passed in both; a failure is a divergence).
  The reproducers written for TPL-19 and TPL-21 did not trigger those findings (other inputs do; see
  `06-templates/FINDINGS.md`); `TPL-12 for-else after full loop` and the control agree, as expected.
* Unmodified shipped harness: a throwaway copy of `tests/`, `bridge/`, `protocol/`, `manifest.yaml` with `.lake`
  symlinked, in which the shipped case directories are emptied and filled with the area reviewers' reproducer files.
  No harness file is changed. Rerun:

  ```bash
  S=/tmp/claude-0/ver-shipped; rm -rf $S; mkdir -p $S; cp -a tests bridge protocol manifest.yaml $S/; ln -s $PWD/.lake $S/.lake
  rm $S/tests/scenarios/*.yaml $S/tests/core/*/*.yaml $S/tests/helpers/*.yaml
  A=review/experiments/07-automation/cases
  cp $A/{act_repeat_count_float,cfg_initial_state_false,coe_string_forms,cfg_duplicate_ids,ev_type_list_and_dup,cond_entity_uppercase,state_to_star}.yaml $S/tests/scenarios/
  R=review/experiments
  cp $R/03-core-states-bus/cases/states/{str_of_state,attributes}.yaml $S/tests/core/states/
  cp $R/03-core-states-bus/cases/events/types_data_filters.yaml $S/tests/core/events/
  cp $R/04-core-registry-hass/cases/services/registry_review.yaml $R/05-service-schemas/cases/divergences.yaml $S/tests/core/services/
  cp $R/09-helpers/cases/{misc,input_number}.yaml $S/tests/helpers/
  (cd $S && /opt/havenv/bin/python -m pytest tests/differential/test_differential.py -p no:cacheprovider -q -rf)
  (cd $S && /opt/havenv/bin/python -m pytest tests/differential/test_{states,events,services,helpers}.py -p no:cacheprovider -q -rf)
  ```
  Logs: `logs/automation-shipped-harness-run{1,2}.log` (7 failed, 1 passed, 2 skipped in both: the 7 scenarios
  fail, the pin test passes, the mqtt/webhook tests have no scenario);
  `logs/core-helpers-shipped-harness-run{1,2}.log` (38 failed, 107 passed in both; same failing ids).
