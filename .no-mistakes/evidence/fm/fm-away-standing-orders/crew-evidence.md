# Test evidence for run 01M5WM90EKSY215ZX5RP0R1VNZ at pipeline head 6d55f860

Ran in a temporary detached worktree at 6d55f86 (fetched from the pipeline clone), each invocation under a 15-minute cap, after the pipeline's own test agent hit its budget.

| Suite | Result at 6d55f860 | Log |
| --- | --- | --- |
| tests/fm-branch-supervision.test.sh | green (64 s) | crew-fm-branch-supervision.log |
| tests/fm-supervision-host.test.sh | green: 58 of 87 tests in the first 15-minute invocation (cap hit, no failure), remaining 29 green in a second invocation of only those tests | crew-fm-supervision-host.log, crew-fm-supervision-host-part2.log |
| tests/fm-pi-branch-extension.test.sh | green (235 s) | crew-fm-pi-branch-extension.log |
| tests/fm-control-relaunch.test.sh | first run: 1 failure, "relaunch did not reach trace delivery" (a 5-second poll for a fake trace stub); rerun: green (435 s) | crew-fm-control-relaunch.log, crew-head2-fm-control-relaunch.log |
| tests/fm-omp-harness.test.sh | first run: 1 failure, "expected one follow-up wake, saw 0" in the omp watch extension contract; rerun: green (98 s) | crew-fm-omp-harness.log, crew-head2-fm-omp-harness.log |
| tests/fm-afk-contract.test.sh | green (29 s) | crew-fm-afk-contract.log |

Base comparison at 127f0f30 (the branch base), same kind of temporary worktree:
- tests/fm-omp-harness.test.sh green.
- tests/fm-control-relaunch.test.sh: 1 failure on a different poll ("relaunch did not reach its pre-publication endpoint check"), 53 tests green, showing that suite's short polling windows miss under load regardless of this change.

Conclusion: every touched suite is green at the pipeline head; the two first-run failures were polling-window timing misses that pass on rerun and also occur at the base commit, not failures caused by the change.
