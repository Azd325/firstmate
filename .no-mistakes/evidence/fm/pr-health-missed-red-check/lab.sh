#!/usr/bin/env bash
# usage: lab.sh <label> <flag:on|off> <url> <sweeps>
set -u
R={run-worktree}
label=$1 flag=$2 url=$3 sweeps=$4
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
mkdir -p $LAB/state $LAB/data $LAB/config $LAB/projects $LAB/project
repo=$LAB/repo; git init -q $repo; git -C $repo -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
git -C $repo update-ref refs/remotes/origin/main HEAD
cat > $LAB/state/lab-task.meta <<M
window=firstmate:fm-lab-task
endpoint_task_id=lab-task
worktree=$repo
project=$LAB/project
kind=ship
mode=no-mistakes
M
echo "done [at=$(date +%s)]: PR $url checks green" > $LAB/state/lab-task.status
[ "$flag" = on ] && touch $LAB/config/pr-register-scan
for i in $(seq 1 $sweeps); do
  echo "=== sweep $i"
  rm -f $LAB/state/.last-check
  ( cd $R && FM_HOME=$LAB FM_CHECK_INTERVAL=3600 FM_HEARTBEAT=999999 perl -e 'alarm 40; exec @ARGV' bin/fm-watch.sh >$LAB/watch.$i.log 2>&1 ) 
  echo "watcher rc=$?"; tail -5 $LAB/watch.$i.log
  echo "--- wake drain"
  out=$(FM_HOME=$LAB $R/bin/fm-wake-drain.sh 2>&1); echo "$out"
  ack=$(echo "$out" | grep -o -- '--ack-through .*' | head -1)
  [ -n "$ack" ] && FM_HOME=$LAB $R/bin/fm-wake-drain.sh $ack
done
echo "=== meta"; cat $LAB/state/lab-task.meta
echo "=== state"; ls -a $LAB/state
echo "=== poll valid?"; ( cd $R && . bin/fm-pr-lib.sh; fm_pr_poll_artifacts_valid $LAB/state lab-task $R/bin/fm-pr-poll.sh && echo VALID || echo INVALID )
echo "=== pr-register wakes ever queued"; grep -h "pr-register" $LAB/state/.watch-deliveries.log $LAB/state/.wake-queue* 2>/dev/null | head; echo "cursor:"; ls $LAB/state/.pr-check-scan-cursor 2>&1
rm -rf $LAB
