#!/usr/bin/env bash
# Lab 10 Task 2 - prove that no Jenkinsfile in the repo contains a literal secret.
# Turns the code-review checklist item into a pipeline gate.
#
# Accepted risk, with a reason, on the line itself:
#   AWS_SECRET_ACCESS_KEY = 'test'   // secret-lint:allow LocalStack dummy, not a real key
# Same idea as Semgrep's "// nosemgrep: <rule> -- reason" and Lab 08's tfsec ignores:
# the exception is visible in review, next to the code, never hidden in this script.
set -uo pipefail

ALLOW_MARK='secret-lint:allow'

mapfile -t FILES < <(git ls-files | grep -E '(^|/)([^/]+\.)?Jenkinsfile$')
[ "${#FILES[@]}" -gt 0 ] || { echo "no Jenkinsfiles found"; exit 1; }
echo "Checking: ${FILES[*]}"
fail=0

# drop lines that carry an annotated exception
drop_allowed() { grep -v "$ALLOW_MARK" || true; }

echo
echo "== 1. Reviewer grep from the lab manual =="
echo "   (every hit must be a credential ID, a variable NAME, a stage name or a comment)"
grep -nH "password\|secret\|token" "${FILES[@]}" || echo "   (no hits)"

echo
echo "== 2. A literal value assigned to a secret-looking key =="
# e.g.  SONAR_TOKEN = 'sqp_123...'   or   password: "hunter22"
# Lines whose key is credentialsId / *Variable only NAME a secret, so they are allowed.
hits=$(grep -nHEi "(password|passwd|secret|token|apikey|api_key)[a-z0-9_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"'][^\"'\$]{4,}[\"']" "${FILES[@]}" \
       | grep -viE "credentialsid|credentialid|variable[\"']?[[:space:]]*:" | drop_allowed)
if [ -n "$hits" ]; then echo "$hits"; fail=1; else echo "   OK"; fi

echo
echo "== 3. Known token / key formats =="
hits=$(grep -nHE 'xox[abprs]-[0-9A-Za-z-]{10,}|gh[pousr]_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{30,}|glpat-[0-9A-Za-z_-]{20,}|sq[pua]_[0-9a-f]{40}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[0-9A-Za-z_-]{20,}\.[0-9A-Za-z_-]{20,}' "${FILES[@]}" | drop_allowed)
if [ -n "$hits" ]; then echo "$hits"; fail=1; else echo "   OK"; fi

echo
echo "== 4. Secrets interpolated by Groovy (\"...\${PASS}\") instead of by the shell ('...\$PASS') =="
# Groovy interpolation puts the secret into the command line before the shell runs it,
# so it can show up in process listings and in Jenkins' "insecure interpolation" warning.
hits=$(grep -nHE "(^|[^A-Za-z_])sh[[:space:]]*\(?[[:space:]]*(script:[[:space:]]*)?\"[^\"]*\\$\{?(env\.)?[A-Z_]*(PASS|PASSWORD|TOKEN|SECRET)[A-Z_]*" "${FILES[@]}" | drop_allowed)
if [ -n "$hits" ]; then echo "$hits"; fail=1; else echo "   OK"; fi

echo
echo "== 5. Annotated exceptions (a reviewer must agree with every one) =="
allowed=$(grep -nH "$ALLOW_MARK" "${FILES[@]}")
if [ -n "$allowed" ]; then echo "$allowed"; else echo "   (none)"; fi

echo
if [ "$fail" -ne 0 ]; then
    echo "SECRET LINT FAILED: move the value into a Jenkins credential and bind it with withCredentials/credentials()."
    exit 1
fi
echo "SECRET LINT PASSED: no literal secrets in ${#FILES[@]} Jenkinsfile(s)."
