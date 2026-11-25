#!/bin/bash
# For every patch: reset the throwaway copy, apply the patch, rebuild halean-helpers,
# run its reproducers and the shipped test_helpers.py (test_patch.sh). Then all patches together.
COPY=${1:-/tmp/claude-0/halean-copies/09-helpers-1}
HERE=$(cd "$(dirname "$0")" && pwd)
export PATH=$HOME/.elan/bin:$PATH
declare -A K=(
 [HLP-1]="hw_m_all or hw_m_explicit"
 [HLP-2]="hw_in_negative_zero or hw_in_state_format or hw_in_decrement_to"
 [HLP-3]="hw_is_long_option or hw_c_state_too_long"
 [HLP-5]="hw_pat_dollar"
 [HLP-6]="hw_pat_brace_at_start or hw_pat_brace_after_bar or hw_pat_brace_forms or hw_pat_quantifier_forms"
 [HLP-7]="hw_pat_class"
 [HLP-8]="bracket_first or hw_pat_classes"
 [HLP-9]="hw_pat_space_class or hw_pat_escapes"
 [HLP-10]="hw_pat_nonascii"
 [HLP-11]="hw_in_restore"
 [HLP-13]="hw_t_far"
 [HLP-14]="hw_t_restore_idle"
 [HLP-15]="hw_is_config_dup"
 [HLP-16]="hw_ib_slug"
)
for n in 1 2 3 5 6 7 8 9 10 11 13 14 15 16; do
  ID=HLP-$n
  ( cd $COPY && git checkout -q -- HALean Exe && git apply $HERE/$ID.patch && lake build halean-helpers > $HERE/$ID.build.log 2>&1 ) || { echo "$ID: BUILD FAILED"; continue; }
  echo "$ID: $(tail -n 1 $HERE/$ID.build.log)"
  $HERE/test_patch.sh $ID "${K[$ID]}" $COPY
done
( cd $COPY && git checkout -q -- HALean Exe && for n in 1 2 3 5 6 7 8 9 10 11 13 14 15 16; do git apply $HERE/HLP-$n.patch; done
  git diff -- HALean Exe > $HERE/ALL.patch; lake build halean-helpers > $HERE/ALL.build.log 2>&1 )
echo "ALL: $(tail -n 1 $HERE/ALL.build.log)"
cd $HERE/..
HALEAN_BIN=$COPY/.lake/build/bin /opt/havenv/bin/python -m pytest harness/test_helpers.py -p no:cacheprovider -q > patches/ALL.cases.log 2>&1
python3 gen/classify.py patches/ALL.cases.log > patches/ALL.cases.classified.txt
echo "ALL cases:   $(tail -n 1 patches/ALL.cases.log)"; tail -n 1 patches/ALL.cases.classified.txt
( cd $COPY && /opt/havenv/bin/python -m pytest tests/differential/test_helpers.py -p no:cacheprovider -q > $HERE/ALL.shipped.log 2>&1 )
echo "ALL shipped: $(tail -n 1 patches/ALL.shipped.log)"
HALEAN_BIN=$COPY/.lake/build/bin HELPERS_CASES=gen/seed-202 /opt/havenv/bin/python -m pytest harness/test_helpers.py -p no:cacheprovider -q > patches/ALL.random-seed202.log 2>&1
echo "ALL random seed 202: $(tail -n 1 patches/ALL.random-seed202.log)"
