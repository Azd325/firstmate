#!/usr/bin/env bash
set -u
ROOT=$(pwd)
. tests/herdr-test-safety.sh
herdr_forget_inherited_pane
SESSION="fm-lab-unreg-$$"; export HERDR_SESSION="$SESSION"
cleanup(){ herdr_safe_stop_and_delete "$SESSION"; rm -rf "$S"; }
trap cleanup EXIT
fm_herdr_lab_prepare "$SESSION" || { echo prepare failed; exit 1; }
S=$(mktemp -d "${TMPDIR:-/tmp}/fm-unreg.XXXXXX"); mkdir -p "$S/cwd" "$S/bin"
cp /bin/sleep "$S/bin/polytoken"; cp /bin/sleep "$S/bin/lessish"; codesign --force -s - "$S/bin/polytoken" "$S/bin/lessish" 2>/dev/null
. bin/fm-backend.sh; fm_backend_source herdr
lab(){ fm_herdr_lab_cli "$SESSION" "$@"; }
fm_backend_herdr_server_ensure "$SESSION" || exit 1
WS=$(lab workspace create --label unreg --cwd "$S/cwd" 2>&1); P=$(printf %s "$WS"|jq -r '.result.root_pane.pane_id')
sleep 1
echo "baseline (shell only): agent_state=$(fm_backend_herdr_pane_agent_state $SESSION $P) backend=$(fm_backend_agent_state herdr $SESSION:$P)"
lab pane run "$P" "$S/bin/polytoken 600"; sleep 2
echo "agent get: $(herdr agent get $P --session $SESSION 2>&1|tr -d '\n')"
echo "fg: $(herdr pane process-info --pane $P --session $SESSION|jq -c '.result.process_info.foreground_processes|map({name,argv0})')"
echo "S1 unregistered + harness-named fg (polytoken): process_state=$(fm_backend_herdr_pane_process_state $SESSION $P) agent_state=$(fm_backend_herdr_pane_agent_state $SESSION $P) backend=$(fm_backend_agent_state herdr $SESSION:$P)"
lab pane send-keys "$P" C-c >/dev/null; sleep 1
lab pane run "$P" "$S/bin/lessish 600" >/dev/null; sleep 2
echo "agent get: $(herdr agent get $P --session $SESSION 2>&1|tr -d '\n')"
echo "S2 unregistered + non-harness fg: process_state=$(fm_backend_herdr_pane_process_state $SESSION $P) agent_state=$(fm_backend_herdr_pane_agent_state $SESSION $P) backend=$(fm_backend_agent_state herdr $SESSION:$P)"
lab pane send-keys "$P" C-c >/dev/null; sleep 1.5
echo "S3 back to shell: agent_state=$(fm_backend_herdr_pane_agent_state $SESSION $P) backend=$(fm_backend_agent_state herdr $SESSION:$P)"
