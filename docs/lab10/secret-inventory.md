# Lab 10 Task 2 — Secret inventory

Every secret the two pipelines use, where its **value** lives, and how it is bound.
Nothing in this table appears as a value in any Jenkinsfile — only the **IDs** do.

| Secret | Jenkins credential ID | Kind | Bound with | Used in |
|---|---|---|---|---|
| Registry login | `registry-creds` | Username with password | `withCredentials([usernamePassword(…)])` | API: Push Image |
| Sonar token | `sonar-token` | Secret text | server config, injected by `withSonarQubeEnv('SonarQube')` | API: SonarQube Analysis |
| kubeconfig | `kind-kubeconfig` | Secret file | `withCredentials([file(…)])` | API: deploys + rollback |
| Cosign key | `cosign-key` | Secret file | `withCredentials([file(…)])` | API: SBOM & Sign |
| Cosign key password | `cosign-password` | Secret text | `withCredentials([string(…)])` | API: SBOM & Sign |
| Android keystore | `android-upload-keystore` | Secret file | `withCredentials([file(…)])` | Mobile: Signed AAB |
| Android keystore password | `android-keystore-password` | Secret text | `withCredentials([string(…)])` | Mobile: Signed AAB |
| Slack bot token | `slack-bot-token` | Secret text | Slack plugin global config | both: `post { }` |
| K8s SA token (Lab 09) | `k8s-jenkins-sa-token` | Secret text | Kubernetes cloud config | pod creation |

## Deliberately *not* secrets (and why)

| Value | Where | Why it is public |
|---|---|---|
| `ANDROID_KEY_ALIAS = 'upload'` | `frontend/Jenkinsfile` | Just a name inside the keystore. |
| `UPLOAD_CERT_SHA256` | `frontend/Jenkinsfile` | The certificate fingerprint ships inside every APK/AAB. Publishing it is what lets the pipeline *prove* which key signed the bundle. |
| `AWS_ACCESS_KEY_ID/_SECRET_ACCESS_KEY = 'test'` | `infra/Jenkinsfile` | LocalStack's documented dummy credentials; annotated `// secret-lint:allow` so the reviewer sees the exception on the line. |

## The four rules

1. **IDs in the Jenkinsfile, values in Jenkins.** `withCredentials([...])` for step-scoped
   secrets, `credentials('id')` in `environment {}` for pipeline-wide ones. Both mask the
   value in the log (`****`).
2. **Single-quoted `sh '…$SECRET…'`, never `sh "…${SECRET}…"`.** With double quotes *Groovy*
   substitutes the secret into the command string before the shell runs it, so it can land in
   process listings; Jenkins warns about "insecure interpolation". With single quotes the
   shell expands it at runtime. Check 4 of `ci/check-jenkinsfile-secrets.sh` enforces this.
3. **Files for multi-line secrets** (keystore, kubeconfig, cosign key): Secret file
   credentials, never base64 strings in the Jenkinsfile.
4. **Never `echo` a secret**, not even for debugging. Masking only works on the exact string.

## The gate

`ci/check-jenkinsfile-secrets.sh` runs as the 8th lane of *Static Checks* and scans **every**
tracked `*Jenkinsfile` (API, `frontend/`, `infra/`, `jenkins/`). It prints the lab manual's
reviewer grep, then fails the build on: a literal value assigned to a secret-looking key,
a known token/key format (Slack/GitHub/GitLab/Sonar/AWS/PEM/JWT), or a Groovy-interpolated
secret. Verified both ways — passes on this repo, and flags all four classes on a test file.

## Registry credentials — honest note

`kind-registry` (Lab 07) runs **without authentication**, so `docker login` succeeds with any
password. The pipeline still shows the correct pattern: the secret is bound at runtime, piped
via `--password-stdin` (never on the command line), and `docker logout` follows. Against a
real registry (GHCR, Docker Hub, Harbor) nothing in the Jenkinsfile would change.

## cosign.key — a real finding

`git log --all --oneline -- cosign.key` → **`4a9fb12 help`**. The key *was* committed, so it is
burned. Actions taken:

1. `git rm --cached cosign.key` — removed from the index, kept on disk.
2. `cosign.key`, `*.jks`, `*.keystore`, `key.properties` added to `.gitignore`.
3. **Rotated:** a new key pair was generated and the `cosign-key` / `cosign-password`
   credentials in Jenkins were replaced.
4. Only *after* rotation, `cosign.key` was allowlisted in `.gitleaks.toml`, with the reason
   written next to it. Allowlisting a key that is still in use would be hiding the finding
   instead of fixing it.
