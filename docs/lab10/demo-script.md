# Lab 10 — 10-minute walkthrough script

Every stage you narrate must match what is on screen. The configured thresholds are:
Semgrep `ERROR`, OPA = any critical CVE, Trivy fixable `HIGH,CRITICAL`, Sonar = the Lab 05
Quality Gate (coverage ≥ 70%), health gate **90% over the last 20 finished builds**.
Do not say "Trivy blocks CRITICAL" — it blocks HIGH *and* CRITICAL.

## The change to demo

* **API:** add `version` (the short commit SHA) to the `/health/live` response `data`.
  Pass it as a build arg in *Build Image* (`--build-arg APP_VERSION=$IMAGE_TAG`), set
  `ENV APP_VERSION` in `server/Dockerfile`, read `process.env.APP_VERSION` in the health
  controller, and add `expect(body.data.version).toBeTruthy()` to `e2e/tests/01-health.spec.ts`.
* **Mobile:** show that version on the settings/about screen (`Text('API ${version}')` from a
  call to `/health/live`) + a widget test.

The E2E test on staging then proves the field exists in the **deployed** API, not just in the code.

## Prep checklist (the day before)

- [ ] Both pipelines green on `main` with a **warm cache** (second run is minutes, not half an hour)
- [ ] Health rate ≥ 90% (run `lab10-sim-burst` with `OUTCOME=SUCCESS`, `COUNT=20` if needed)
- [ ] Windows open: Blue Ocean (both jobs), Slack `#taskflow-ci`, Grafana dashboard,
      a PowerShell running `k get pods -n jenkins-agents -w`, the architecture diagram
- [ ] ngrok running, webhook shows `200` in GitHub → Settings → Webhooks
- [ ] **Record a full run as a backup.** A live pipeline takes ~20 min and does not fit in 10.
      Record the waiting parts, speed them up (×4 is fine), and narrate over them.
- [ ] Backup gate in case the health-gate timing slips: the `demo/critical-cve` branch
      (Policy Gate blocks in ~3 min).

## The script

| Min | Show | Say |
|---|---|---|
| 0–1 | Diagram | "One commit, two pipelines, more than a dozen gates. Hexagons stop the build." |
| 1–2 | Diff (API + Flutter) → `git push` → both jobs start | "The webhook triggers both pipelines; each gets a fresh pod." + point at `k get pods -w` |
| 2–4 | API *Static Checks* lanes | Lint · Unit Test · SAST (Semgrep ERROR) · SCA + OPA · gitleaks history · SBOM signed · IaC · Jenkinsfile secret lint. "Parallel and fail fast: one red lane aborts the others." |
| 4–5 | Mobile lanes, APK artifact | "Analyze, tests with coverage and osv-scanner in parallel; every branch gets an installable debug APK." |
| 5–6 | Sonar QG → Build (dind) → Trivy → Push | "Immutable tag = commit SHA; the image is scanned *before* it reaches the registry." |
| 6–7 | `develop`: staging on the idle color + E2E green | "Staging is the idle color: deployed and tested, users still on the old one." |
| 7–8.5 | **Gate blocking live**: `main` hits the Health Gate after the 4-failure burst → BLOCKED, Slack ❌ | "80% of the last 20 builds passed, below 90%: no approval prompt, no deploy. Prometheus down would also block — fail closed." |
| 8.5–9.5 | Recovered run: PASSED → approve → `svc-after.yaml` color flipped; mobile `main` → `SIGNATURE OK` | "Blue/green switch, rollback is automatic on failure; the AAB is verified against our upload key." |
| 9.5–10 | Slack channel, Grafana | "Every result lands in Slack with branch and link; Grafana shows the success rate the gate uses." |

## Health-gate choreography (the timing that makes 7–8.5 work)

The API pipeline takes ~15 min to reach the gate, so start it first.

| Time | Action | What you see |
|---|---|---|
| 0:00 | Trigger `main` of the API job | CI starts |
| 0:30 | `lab10-sim-burst`: `OUTCOME=FAILURE`, `COUNT=4` | 4 red `lab10-sim` builds |
| 1:30 | (optional) Grafana *Build success rate* panel drops (metrics 15 s + scrape 15 s) | |
| ~15:00 | API build reaches **Pipeline Health Gate** | `HEALTH GATE BLOCKED: 16/20 builds succeeded = 80% (threshold 90%)` → build red, **no approval prompt, no deploy**, Slack ❌ |
| then | `lab10-sim-burst`: `OUTCOME=SUCCESS`, `COUNT=20` → rebuild `main` | `HEALTH GATE PASSED: 20/20 = 100%` → approval → switch |

**Why 4 failures, and why 20 successes to recover:** the blocked build itself counts as a failure
next time round, so after a block you have to push the failures out of the 20-build window.
Saying that out loud shows you understand the window, not just the number.

## Answers to the likely "why?" questions

* **Why parallel only for the static checks?** Parallel is safe only when no branch writes what
  another reads and they share no lock. Build → scan → push → deploy is a chain by nature.
* **Why fail fast?** Feedback time is the product. A lint error should cost 30 seconds, not 20 minutes.
* **Why is the health gate right before production?** It protects the one irreversible step (users).
  Feature and develop builds must still run so people can fix what's failing.
* **Why fail closed?** A gate that passes when it cannot measure is decoration.
* **Why dind and not the node's Docker?** kind nodes run containerd — there is no `docker.sock` — and
  no hand-made agents are allowed. dind gives each build a throwaway daemon. The price is
  `privileged`. In production: rootless BuildKit or a dedicated build node pool.
* **Why verify the AAB signer?** "The build succeeded" is not proof of "signed correctly". A missing
  credential silently falls back to the debug key; the fingerprint check turns that into a red build.
* **Why pin tools and verify checksums?** A floating `latest` or `curl | sh` means someone else
  decides what runs in your pipeline. Trivy 0.69.4 (March 2026) is the real example — hence `0.69.3`.
