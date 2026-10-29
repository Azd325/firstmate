#!/usr/bin/env bash
# Live driver: real fm-midtask-fallback.sh consider + real fm-control relaunch on a Herdr lab session.
set -u
ROOT=$1
. "$ROOT/tests/lib.sh"
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
SESSION="fm-lab-midtask-$$"; export HERDR_SESSION="$SESSION"
fm_herdr_lab_prepare "$SESSION" || { echo "prepare failed"; exit 1; }
S=$(mktemp -d "${TMPDIR:-/tmp}/fm-mt-live.XXXXXX"); S=$(cd "$S" && pwd)
cleanup(){ chmod -R u+w "$S" 2>/dev/null; herdr_safe_stop_and_delete "$SESSION"; rm -rf "$S"; fm_test_cleanup; }
trap cleanup EXIT
H=$S/home; mkdir -p $H/state $H/data/t7016 $H/config
printf '# Task\n## Captain'"'"'s intent\nlifecycle proof\n\n## Firstmate spec\nstop\n' > $H/data/t7016/brief.md
PROJ=$S/proj; WT=$S/wt; mkdir -p $PROJ; git -C $PROJ init -q; echo x>$PROJ/README.md; git -C $PROJ add README.md
git -C $PROJ -c user.name=t -c user.email=t@e.invalid commit -qm i; git -C $PROJ worktree add -q -b t7016 $WT
printf 'unlanded\n' > $WT/note.txt
. "$ROOT/bin/fm-backend.sh"; fm_backend_source herdr
CR=$(fm_backend_herdr_container_ensure "$WT"); CONT=${CR%%$'\t'*}; SEED=${CR#*$'\t'}; WS=${CONT#*:}
read -r TAB PANE <<<"$(fm_backend_herdr_create_task "$CONT" fm-t7016 "$WT" "$SEED")"
{ echo window=$SESSION:$PANE; echo endpoint_task_id=t7016; echo worktree=$WT; echo project=$PROJ; echo harness=claude; echo kind=ship
  echo mode=no-mistakes; echo yolo=off; echo model=claude-sonnet-5; echo effort=high; echo backend=herdr; echo herdr_session=$SESSION
  echo herdr_workspace_id=$WS; echo herdr_tab_id=$TAB; echo herdr_pane_id=$PANE; } > $H/state/t7016.meta
FB=$S/fb; mkdir $FB; AB=$S/ab; mkdir $AB
SB=$(fm_agent_standin "$S/standin") || { echo "no standin"; exit 1; }
ln -s "$SB" "$AB/codex"
cat > $FB/codex <<EOS
#!/usr/bin/env bash
: > $S/codex-launched
herdr pane report-agent "$PANE" --source midtask-live --agent codex --state idle --session "$SESSION" >/dev/null 2>&1
exec $AB/codex 900
EOS
chmod +x $FB/codex
fm_backend_herdr_send_text_line "$SESSION:$PANE" "export PATH=$FB:\$PATH"
jq -n '{mid_task_fallback:true, rules:[{when:"work", use:[
 {harness:"claude",model:"claude-sonnet-5",effort:"high"},
 {harness:"grok",model:"grok-4",effort:"high"},
 {harness:"codex",model:"gpt-5.5",effort:"high"}]}]}' > $H/config/crew-dispatch.json
Q=$S/q.json
jq -n '{schemaVersion:5,providers:[
 {provider:"claude",quotaSemantics:{status:"known",effectiveAvailability:[{scope:"all_models",status:"known",effectivePercentRemaining:0,runway:{status:"exhausted_now"}}]}},
 {provider:"grok",quotaSemantics:{status:"known",effectiveAvailability:[{scope:"all_models",status:"known",effectivePercentRemaining:0,runway:{status:"exhausted_now"}}]}},
 {provider:"codex",quotaSemantics:{status:"known",effectiveAvailability:[{scope:"all_models",status:"known",effectivePercentRemaining:80,runway:{status:"through_reset"}}]}}]}' > $Q
E="env FM_HOME=$H HERDR_SESSION=$SESSION FM_SPAWN_NO_GUARD=1 FM_CONTROL_POLL=0.2 FM_CONTROL_EXIT_WAIT=2"
echo "== bind"; $E $ROOT/bin/fm-midtask-fallback.sh bind t7016 --rule 0; echo rc=$?
echo "== consider"; $E $ROOT/bin/fm-midtask-fallback.sh consider t7016 --snapshot $Q; echo rc=$?
for _ in $(seq 1 30); do [ -e $S/codex-launched ] && break; sleep 0.2; done
echo "codex-launched=$([ -e $S/codex-launched ] && echo yes || echo no)"
echo "note=$(cat $WT/note.txt)"; git -C $WT status --porcelain
echo "== meta"; grep -E '^(harness|model|effort|worktree|midtask)' $H/state/t7016.meta
echo "== status"; cat $H/state/t7016.status
echo "== repeat consider (must be no-op)"; $E $ROOT/bin/fm-midtask-fallback.sh consider t7016 --snapshot $Q; echo rc=$?
grep -c '^switched' $H/state/t7016.status
echo "== setting off => no-op"
jq 'del(.mid_task_fallback)' $H/config/crew-dispatch.json > $H/c && mv $H/c $H/config/crew-dispatch.json
$E $ROOT/bin/fm-midtask-fallback.sh consider t7016 --snapshot $Q; echo rc=$?
