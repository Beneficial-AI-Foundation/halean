#!/usr/bin/env bash
# Static search of the Lean sources. Usage: review/experiments/01-build-axioms/grep_audit.sh > logs/grep-audit.txt
cd "$(git rev-parse --show-toplevel)"
for w in sorry admit native_decide implemented_by extern unsafe 'decide +native' 'bv_decide' 'opaque'; do
  echo "== word: $w =="; grep -rnw --include='*.lean' -- "$w" HALean HALean.lean Exe | grep -v '^\S*:[0-9]*:\s*--' | head -40
  echo "count(all lines incl. comments)=$(grep -rnw --include='*.lean' -- "$w" HALean HALean.lean Exe | wc -l)"
done
echo "== axiom declarations =="; grep -rnE --include='*.lean' '^\s*(private |protected )?axiom\b' HALean HALean.lean Exe; echo "count=$(grep -rnE --include='*.lean' '^\s*(private |protected )?axiom\b' HALean HALean.lean Exe | wc -l)"
echo "== partial definitions =="; grep -rnE --include='*.lean' '^\s*(@\[[^]]*\]\s*)?(private |protected )?(partial def|partial instance)|^\s*partial\s*$' HALean HALean.lean Exe | tee /tmp/partials.$$ | awk -F: '{print $1}' | sort | uniq -c | sort -rn
echo "count=$(wc -l < /tmp/partials.$$)"; rm -f /tmp/partials.$$
echo "== any other 'partial' token =="; grep -rnw --include='*.lean' 'partial' HALean HALean.lean Exe | grep -vE 'partial def' | head -30
echo "== decreasing_by / termination_by counts =="; grep -rnw --include='*.lean' -E 'termination_by|decreasing_by' HALean Exe | wc -l
echo "== set_option maxHeartbeats / maxRecDepth =="; grep -rn --include='*.lean' -E 'set_option (maxHeartbeats|maxRecDepth)' HALean Exe | wc -l
echo "== generated files (header says generated) =="; grep -rlE --include='*.lean' -i 'generated|auto-generated|do not edit' HALean Exe
