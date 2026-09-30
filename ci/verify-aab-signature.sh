#!/usr/bin/env bash
# Lab 10 Task 3 - prove the release AAB is signed with OUR upload key (not the debug key).
# UPLOAD_CERT_SHA256 is the certificate fingerprint. It is public information, so it can
# live in the Jenkinsfile. Only the keystore file and its password are secrets.
set -euo pipefail
AAB=${1:?usage: verify-aab-signature.sh path/to/app-release.aab}
: "${UPLOAD_CERT_SHA256:?set UPLOAD_CERT_SHA256 in the Jenkinsfile environment block}"

keytool -printcert -jarfile "$AAB" | tee aab-signature.txt

actual=$(grep -m1 -E '^[[:space:]]*SHA256:' aab-signature.txt | awk '{print $2}' | tr 'a-f' 'A-F')
expected=$(echo "$UPLOAD_CERT_SHA256" | tr 'a-f' 'A-F')
echo "expected signer: $expected"
echo "actual signer:   $actual"

if grep -q 'CN=Android Debug' aab-signature.txt; then
    echo "FAILED: the AAB is signed with the DEBUG key (ANDROID_KEYSTORE_PATH was not set?)"
    exit 1
fi
if [ -z "$actual" ] || [ "$actual" != "$expected" ]; then
    echo "FAILED: the AAB is not signed with the upload key"
    exit 1
fi

jarsigner -verify "$AAB" | tee -a aab-signature.txt
echo "SIGNATURE OK: $(basename "$AAB") is signed with the upload key"
