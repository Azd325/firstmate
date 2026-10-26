#!/usr/bin/env bash
# Live check of the done/paused gate wake against a real parked no-mistakes run.
# Everything Firstmate writes lives in a scratch FM_HOME/HOME/XDG; no-mistakes
# is reached read-only through NM_HOME. The pane is a fake tmux surface; the
# crew-state read, the no-mistakes calls and the watcher check path are real.
set -u
for v in $(env | sed -n "s/^\(FM_[A-Za-z0-9_]*\|HERDR_[A-Za-z0-9_]*\)=.*/\1/p"); do unset "$v"; done

LIVE=/private/tmp/claude-501/-Users-timkleinschmidt--treehouse-firstmate-b8697d-12-firstmate/bbf1f9eb-903e-4b8b-8942-9fe0a19f570e/scratchpad/live
GATE_REPO=~/.no-mistakes/repos/0415ddf1f9d0.git
CODE_HEAD=7ccfa30199ae3fc4d6e4c74f7df39cd5fc99f632
RUN=01M5WNSM7YH06MPC4GM5KM0V0M
WT_GATE=~/.treehouse/firstmate-b8697d/12/firstmate
WT_DONE=~/.treehouse/firstmate-b8697d/4/firstmate
OUT=${1:?evidence file}

rm -rf "$LIVE/code" "$LIVE/home" "$LIVE/userhome" "$LIVE/bin" "$LIVE/failbin"
mkdir -p "$LIVE/code" "$LIVE/home/state" "$LIVE/home/config" "$LIVE/home/data" \
  "$LIVE/userhome/.config" "$LIVE/userhome/.cache" "$LIVE/userhome/.local/share" "$LIVE/bin" "$LIVE/failbin"
git --git-dir="$GATE_REPO" archive "$CODE_HEAD" bin | tar -x -C "$LIVE/code"
CODE=$LIVE/code
STATE=$LIVE/home/state

export HOME=$LIVE/userhome XDG_CONFIG_HOME=$LIVE/userhome/.config XDG_CACHE_HOME=$LIVE/userhome/.cache \
  XDG_DATA_HOME=$LIVE/userhome/.local/share NM_HOME=~/.no-mistakes \
  FM_HOME=$LIVE/home FM_STATE_OVERRIDE=$STATE FM_CONFIG_OVERRIDE=$LIVE/home/config

cat > "$LIVE/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  list-windows) printf '%s\n' fm-gate-done fm-gate-paused fm-finished-done; exit 0 ;;
  capture-pane) printf 'idle: worker finished its turn\n'; exit 0 ;;
  display-message) printf 'zsh\n'; exit 0 ;;
esac
exit 1
SH
cat > "$LIVE/failbin/no-mistakes" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$LIVE/bin/tmux" "$LIVE/failbin/no-mistakes"
export PATH=$LIVE/bin:$PATH

write_task() {  # <id> <worktree> <status-line>
  printf 'window=live:%s\nworktree=%s\nkind=ship\nharness=claude\nbackend=tmux\n' "fm-$1" "$2" > "$STATE/$1.meta"
  printf '%s\n' "$3" > "$STATE/$1.status"
  bash -c '. "$1"; fm_wake_status_mark_current "$2" "$3"' _ "$CODE/bin/fm-wake-lib.sh" "$STATE" "$STATE/$1.status"
}
write_task gate-done "$WT_GATE" "done [at=$(date +%s)]: PR checks green"
write_task gate-paused "$WT_GATE" "paused [at=$(date +%s)]: waiting on the maintainer until 2099-01-01T00:00Z"
write_task finished-done "$WT_DONE" "done [at=$(date +%s)]: PR checks green"

watch_once() {  # <label> <seconds> [extra PATH prefix]
  local label=$1 secs=$2 prefix=${3:-} rc
  echo "### watcher run: $label"
  PATH="${prefix:+$prefix:}$PATH" FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
    FM_SECONDMATE_LIVENESS_SECS=99999999 FM_STALE_ESCALATE_SECS=240 \
    timeout "$secs" bash "$CODE/bin/fm-watch.sh" > "$LIVE/watch.out" 2> "$LIVE/watch.err"
  rc=$?
  echo "exit: $rc (124 = still watching when the bound ended, i.e. no wake)"
  echo "printed reasons:"; sed 's/^/  /' "$LIVE/watch.out"
  echo "gate markers:"; for f in "$STATE"/.wait-gate-live_fm-*; do [ -e "$f" ] && printf '  %s: %s\n' "${f##*/}" "$(cat "$f")"; done
  echo "current-state reads taken this run (recheck markers written):"
  for f in "$STATE"/.wait-gate-checked-live_fm-*; do [ -e "$f" ] && printf '  %s\n' "${f##*/}"; done
}

ack_queue() {
  local err="$LIVE/drain.err" seq gen
  FM_STATE_OVERRIDE="$STATE" bash "$CODE/bin/fm-wake-drain.sh" > "$LIVE/drain.out" 2> "$err" || return 0
  echo "queued rows drained:"; grep -E $'\tcheck\t|\tstale\t|\tsignal\t' "$LIVE/drain.out" | sed 's/^/  /'
  seq=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation .*$/\1/p' "$err")
  gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1/p' "$err")
  [ -n "$seq" ] && FM_STATE_OVERRIDE="$STATE" bash "$CODE/bin/fm-wake-drain.sh" --ack-through "$seq" --recovery-generation "$gen" >/dev/null 2>&1
}

force_recheck() { rm -f "$STATE"/.wait-gate-checked-live_fm-*; }

# The incident condition: each idle pane's own stale alarm was already surfaced,
# so only the gate check can still speak for these windows.
mark_panes_surfaced() {
  local f
  for f in "$STATE"/.hash-live_fm-*; do cp "$f" "$STATE/.stale-${f##*/.hash-}"; done
  echo "pane stale alarms marked surfaced: $(ls "$STATE"/.stale-live_fm-* | sed 's|.*/||' | tr '\n' ' ')"
}

{
  echo "# live gate-wake check - $(date -u +%FT%TZ)"
  echo "code under test: $CODE_HEAD (exported from the run's gate repo)"
  echo "run under test: $RUN"
  echo
  echo "## real no-mistakes view of the run"
  ( cd "$WT_GATE" && no-mistakes axi status 2>/dev/null | grep -E '^  (id|status|awaiting_agent|head):|^gate:|^  step:|^  status:' )
  echo
  echo "## real fm-crew-state.sh reads (FM_CREW_STATE_NO_FORGE=1, as the check calls it)"
  for t in gate-done gate-paused finished-done; do
    printf '%s: %s\n' "$t" "$(FM_CREW_STATE_NO_FORGE=1 bash "$CODE/bin/fm-crew-state.sh" "$t" 2>&1)"
  done
  echo
  echo "## 1. first watcher run: one wake naming the gate"
  watch_once first 120; ack_queue
  echo
  echo "## 2. second watcher run: the other parked task's own first wake"
  watch_once second 120; ack_queue
  echo
  mark_panes_surfaced
  echo "## 3. forced recheck: same parked gates, no repeat wake"
  force_recheck; watch_once repeat 20; ack_queue
  echo
  echo "## 4. unknown read (no-mistakes made to fail for this run only)"
  force_recheck; watch_once unknown-read 20 "$LIVE/failbin"; ack_queue
  printf 'crew-state during the failure: %s\n' "$(PATH="$LIVE/failbin:$PATH" FM_CREW_STATE_NO_FORGE=1 bash "$CODE/bin/fm-crew-state.sh" gate-done 2>&1)"
  echo
  echo "## 5. forced recheck after the unknown read: still no repeat wake"
  force_recheck; watch_once after-unknown 20; ack_queue
  echo
  echo "## finished-done task: checked, never woke"
  ls -l "$STATE"/.wait-gate-checked-live_fm-finished-done 2>&1 | sed 's/^/  /'
  [ -e "$STATE/.wait-gate-live_fm-finished-done" ] && echo "  UNEXPECTED gate marker" || echo "  no gate marker (silent)"
} > "$OUT" 2>&1
