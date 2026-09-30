# Runbook: "Deploy - Production" failed (taskflow-api)

**Owner:** on-call engineer · **Goal:** users are served by a healthy color within 5 minutes
**You need:** Jenkins admin login, Docker Desktop on the Jenkins host, this PowerShell helper:

    function k { docker exec -i kind-control-plane kubectl --kubeconfig=/etc/kubernetes/admin.conf @args }

## 0. Triage (1 min)
1. Open the failed build from the Slack ❌ link → Console Output. Search for:
   - `AUTOMATIC ROLLBACK` + `Service now serving: <color>` → the pipeline already rolled back → go to step 2.
   - `HEALTH GATE BLOCKED` → **not an incident**: nothing was deployed. Fix the failing builds, stop here.
   - Aborted at the approval prompt → nothing was deployed, stop here.
   - Anything else (credential error, `Unable to connect to the server`, Jenkins restarted mid-deploy) → the automatic rollback may NOT have run → go to step 3.
2. Note `PREV_COLOR` (was live) and `NEXT_COLOR` (was being deployed) from the log line
   `Live = <prev>. Deploying <image> to idle color <next>`.

## 1. Is the cluster reachable?
    docker ps --filter name=kind-control-plane --format "{{.Status}}"   # must be "Up"
    k get nodes                                                          # Ready
If not: `docker start kind-control-plane kind-registry` and wait for `Ready`.

## 2. Verify what users get right now
    k get svc taskflow -o jsonpath='{.spec.selector.color}'              # which color is live?
    k get deploy taskflow-blue taskflow-green -o wide                    # images + READY per color
    k run rb-check --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- `
      curl -sf http://taskflow:8080/health/live
- Live color = PREV_COLOR, READY 1/1, curl prints `"status":"up"` → **users are fine**. Go to step 4.
- Otherwise → step 3.

## 3. Manual rollback (only if step 2 failed)
3a. Pick the healthy color: the one whose image tag is the last known good commit
    (Jenkins → last green `main` build → `svc-after.yaml` artifact shows its color),
    and whose `k rollout status deployment/taskflow-<color> --timeout=10s` succeeds.
3b. Point traffic at it (set selector = no JSON quoting problems in PowerShell):
    k set selector svc taskflow "app=taskflow,color=<good-color>"
3c. Undo the half-deployed color so the next deploy starts clean:
    k rollout undo deployment/taskflow-<bad-color>
3d. If BOTH colors are broken, redeploy a known-good tag (the registry keeps every sha7 tag):
    curl.exe -s http://localhost:5000/v2/taskflow-api/tags/list
    k set image deployment/taskflow-<color> app=localhost:5000/taskflow-api:<good-sha7>
    k rollout status deployment/taskflow-<color> --timeout=120s
    then 3b.
3e. Repeat step 2 until it passes.

## 4. Stop the bleeding
- Don't approve any other production deploy until step 5 is done (reject pending `input` prompts).
- Post in #taskflow-ci: what failed, which color is live, which commit is live, who is on it.

## 5. Find the cause (with users safe)
    k describe pod -l color=<bad-color>                 # ImagePullBackOff? OOMKilled? probe failures?
    k logs deploy/taskflow-<bad-color> --previous       # crash output; config.ts names missing env vars
    k get events --sort-by=.lastTimestamp | Select-Object -Last 20

| Symptom | Likely cause | Fix |
|---|---|---|
| `ErrImagePull localhost:5000/...` | registry down / mirror lost | `docker start kind-registry`; Lab 07 hosts.toml step |
| `CrashLoopBackOff` | app can't reach postgres/redis, or a bad env var | `k get pods` for deps; check secret `taskflow-env` |
| rollout timeout, pod Running but not Ready | `/health/live` failing | app logs |
| `Unable to connect to the server` in Jenkins | `kind-kubeconfig` credential / kind down | step 1; re-create the credential (Lab 07) |

## 6. Roll forward
Fix on a branch → PR → `develop` (staging + E2E) → `main`. Or `git revert <bad-commit>` on `main`.
The full pipeline runs again: all gates, health gate, approval. **Never** hot-fix the cluster by hand
and leave it: the next pipeline deploy would overwrite it.

## 7. Close
- Step 2 passes, Slack post "resolved: <color> live on <sha7>", link to the failed build.
- Within 2 days: short postmortem (what, why, why the pipeline didn't catch it, one action item).

---

## Dry run log (fill in after §6.3 of the lab guide)

Trigger: *Build with Parameters* on `main` with `BREAK_DEPLOY = true` → approve. The rollout of the
idle color times out after 120 s, `post { failure }` runs, and the console shows `AUTOMATIC ROLLBACK`.

| Step | Time | What actually happened |
|---|---|---|
| 0 Triage | | |
| 1 Cluster reachable | | |
| 2 Verify users | | |
| 3 Manual rollback | | (expected: not needed, the pipeline rolled back) |
| 4–7 | | |

**Total time to "users are fine": ____ min.** Anything in this runbook that was wrong during the dry
run must be corrected here — that correction is the proof the runbook is executable, not generic.
