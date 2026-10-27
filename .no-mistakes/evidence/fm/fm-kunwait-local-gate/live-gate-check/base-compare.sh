#!/usr/bin/env bash
set -u
for v in $(env | sed -n "s/^\(FM_[A-Za-z0-9_]*\|HERDR_[A-Za-z0-9_]*\)=.*/\1/p"); do unset "$v"; done
L=/private/tmp/claude-501/-Users-timkleinschmidt--treehouse-firstmate-b8697d-12-firstmate/bbf1f9eb-903e-4b8b-8942-9fe0a19f570e/scratchpad/live
export HOME=$L/userhome XDG_CONFIG_HOME=$L/userhome/.config XDG_CACHE_HOME=$L/userhome/.cache XDG_DATA_HOME=$L/userhome/.local/share \
  NM_HOME=~/.no-mistakes FM_HOME=$L/home FM_STATE_OVERRIDE=$L/home/state FM_CONFIG_OVERRIDE=$L/home/config PATH=$L/bin:$PATH
echo "## base code 127f0f30 (before this change), same scratch records, same live run"
for t in gate-working otherpr-done; do printf '%s: %s\n' "$t" "$(FM_CREW_STATE_NO_FORGE=1 bash "$L/basecode/bin/fm-crew-state.sh" "$t" 2>&1)"; done
