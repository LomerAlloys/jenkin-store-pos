# Lab 10 — steps that cannot be done from the repo

Everything else (Jenkinsfiles, `ci/*.sh`, `k8s/ci-cache.yaml`, docs) is committed on
`lab10-capstone`. These are the Jenkins-UI, keystore, Slack and screenshot steps.
Tick them off as you go.

## A. Prerequisites (Part A)

- [ ] `docker start jenkins sonarqube kind-control-plane kind-registry prometheus grafana`
- [ ] Docker Desktop has ~12 GB (`%UserProfile%\.wslconfig` → `[wsl2]` / `memory=12GB`,
      then `wsl --shutdown` and restart Docker Desktop). Otherwise never run both pipelines at once.
- [ ] Apply the PVCs:
      `Get-Content k8s\ci-cache.yaml -Raw | k apply -f -` then `k get pvc -n jenkins-agents`
      (`Pending` is normal until the first pod mounts them)
- [ ] Preload the big images so the first build doesn't time out:
      `docker pull node:22; docker pull docker:27.3.1-dind; docker pull ghcr.io/cirruslabs/flutter:3.44.3`
      `kind load docker-image node:22 docker:27.3.1-dind ghcr.io/cirruslabs/flutter:3.44.3`
- [ ] Connectivity check from a pod (Part A3) — all four must answer `200`

## B. Task 2 — credentials and the burned cosign key

- [ ] **Manage Jenkins → Credentials → System → Global → Add**
      Kind *Username with password*, username `ci-pusher`, any random password, **ID `registry-creds`**
- [ ] 🔴 **Rotate the cosign key.** `cosign.key` was committed in `4a9fb12`, so it is burned.
      It is now untracked and gitignored, and `.gitleaks.toml` allowlists it — that allowlist is
      only honest **after** you rotate:

          cd D:\File\ComEngineer\ปี4ภาค1\MobileApp\jenkinLab
          docker run --rm -it -v "${PWD}:/w" -w /w gcr.io/projectsigstore/cosign:v2.2.4 generate-key-pair

      Then replace the Jenkins credentials `cosign-key` (Secret file → the new `cosign.key`) and
      `cosign-password` (Secret text → the new password), and commit the new `cosign.pub`.
- [ ] **Screenshot:** the *Jenkinsfile Secret Lint* stage log ending in `SECRET LINT PASSED`

## C. Task 3 — Android keystore and the mobile job

- [ ] Create the upload keystore outside the repo:

          mkdir $HOME\lab10-keys -Force
          docker run -d --name ks eclipse-temurin:21-jdk sleep 600
          docker exec -it ks keytool -genkeypair -v -keystore /tmp/upload-keystore.jks -storetype PKCS12 `
            -alias upload -keyalg RSA -keysize 2048 -validity 10000 `
            -dname "CN=Taskflow Mobile, OU=Lab10, O=ComEngineer, C=TH"
          docker exec -it ks keytool -list -v -keystore /tmp/upload-keystore.jks -alias upload
          docker cp ks:/tmp/upload-keystore.jks "$HOME\lab10-keys\upload-keystore.jks"
          docker rm -f ks

- [ ] Copy the `SHA256: AB:CD:…` line and paste it into `frontend/Jenkinsfile` →
      `UPLOAD_CERT_SHA256` (it still says `PASTE:YOUR:…:HERE`). **The build fails until you do.**
      The fingerprint is public — it ships in every APK — so it belongs in the Jenkinsfile.
- [ ] **Credentials → Global → Add:** Secret file **`android-upload-keystore`** = the `.jks`
- [ ] **Credentials → Global → Add:** Secret text **`android-keystore-password`** = the password
      from the `keytool` prompt (watch for trailing spaces)
- [ ] **New Item → `taskflow-mobile` → Multibranch Pipeline**
      · Branch Sources → same repo + credentials/behaviours as the Lab 04 job
      · **Build Configuration → by Jenkinsfile → Script Path `frontend/Jenkinsfile`**
      The existing GitHub webhook then triggers both jobs.
- [ ] **Screenshots:** the three parallel lanes; on `main` the console lines
      `expected signer` / `actual signer` / `SIGNATURE OK`, plus the archived AAB

## D. Task 4 — no static agents, and the health gate blocking live

- [ ] **New Item → `lab10-sim` → Pipeline → Pipeline script** = `jenkins/lab10-sim.Jenkinsfile`
- [ ] **New Item → `lab10-sim-burst` → Pipeline → Pipeline script** = `jenkins/lab10-sim-burst.Jenkinsfile`
- [ ] *Build with Parameters* once on each so Jenkins registers the parameters. The first
      `build job:` call may need **Manage Jenkins → In-process Script Approval**.
- [ ] **Manage Jenkins → Nodes → `linux-build` → Mark this node temporarily offline**
      (reason: "Lab 10: proving no static agents"), then build `main` of both jobs — both must go
      green with `Created Pod: kind jenkins-agents/…` in the log.
      **Screenshot:** the node list with `linux-build` offline + both green builds.
      Bring it back online afterwards if `taskflow-infra` / `lab08-bootstrap` still need it.
- [ ] Run the health-gate choreography in `demo-script.md`.
      **Screenshots:** the `HEALTH GATE BLOCKED` console + the `health-result.json` artifact,
      the Slack ❌, and the `HEALTH GATE PASSED` run after recovery.

## E. Task 5 — Slack

- [ ] https://api.slack.com/apps → **Create New App → From scratch** → `jenkins-ci`, your workspace
- [ ] **OAuth & Permissions → Bot Token Scopes → add `chat:write`** → **Install to Workspace** →
      copy the **Bot User OAuth Token** (`xoxb-…`)
- [ ] In Slack: create `#taskflow-ci` and run `/invite @jenkins-ci` (otherwise: `not_in_channel`)
- [ ] **Credentials → Global → Add:** Secret text, ID **`slack-bot-token`**, value `xoxb-…`
- [ ] **Manage Jenkins → System → Slack:** workspace = your subdomain, credential = `slack-bot-token`,
      default channel `#taskflow-ci`, ✅ *Custom slack app bot user* → **Test Connection**
- [ ] **Manage Jenkins → System → Jenkins URL** = the URL teammates can open (your ngrok URL).
      `BUILD_URL` in every message is built from this.
- [ ] **Screenshot:** the channel with a ✅ and a ❌ from each pipeline (4 messages)

## F. Task 6 — render the deliverables

- [ ] Paste `docs/lab10/architecture.mmd` into https://mermaid.live → *Actions → PNG/SVG*,
      put it on one A4 page → `docs/lab10/architecture.pdf`
- [ ] Export `docs/lab10/rollback-runbook.md` → `docs/lab10/rollback-runbook.pdf`
- [ ] **Dry run the runbook**: *Build with Parameters* on `main` with `BREAK_DEPLOY = true`,
      approve, watch the rollout time out and `AUTOMATIC ROLLBACK` fire. Time yourself, then fill
      in the dry-run table at the bottom of the runbook and fix anything that was wrong.

## G. Task 1 evidence you still need to capture

- [ ] **Screenshot:** the Blue Ocean graph with the 8 parallel *Static Checks* lanes, and the
      wall-time comparison (old sequential chain vs. new *Static Checks*) for the report
- [ ] Prove the SCA gate can fail:

          git checkout -b demo/critical-cve
          cd server; pnpm add lodash@4.17.4; cd ..
          git commit -am "demo: critical CVE"; git push -u origin demo/critical-cve
          # -> "Policy Gate FAILED: ..." and the sibling lanes are aborted (fail fast)
          git checkout lab10-capstone
