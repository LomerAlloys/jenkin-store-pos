#!/usr/bin/env bash
# Lab 10 Task 3 - SCA for the Flutter client: osv-scanner against pubspec.lock.
# Binary is pinned (OSV_VER from the Jenkinsfile), checksum-verified and cached on the
# flutter-cache PVC. Exit codes from osv-scanner: 0 = clean, 1 = vulnerable packages found,
# 128 = no packages found (wrong path), anything else = scanner error.
set -euo pipefail
: "${OSV_VER:?set OSV_VER in the Jenkinsfile environment block}"
LOCKFILE=${1:-frontend/pubspec.lock}

BIN="/cache/tools/osv-scanner-${OSV_VER}"
if [ ! -x "$BIN" ]; then
    echo "--> downloading osv-scanner ${OSV_VER}"
    base="https://github.com/google/osv-scanner/releases/download/v${OSV_VER}"
    tmp=$(mktemp -d)
    curl -fsSL --retry 3 -o "$tmp/osv-scanner_linux_amd64" "$base/osv-scanner_linux_amd64"
    curl -fsSL --retry 3 -o "$tmp/SUMS" "$base/osv-scanner_SHA256SUMS"
    (cd "$tmp" && grep -E " osv-scanner_linux_amd64\$" SUMS | sha256sum -c -)
    mkdir -p "$(dirname "$BIN")"
    install -m 0755 "$tmp/osv-scanner_linux_amd64" "${BIN}.tmp"
    mv -f "${BIN}.tmp" "$BIN"
    rm -rf "$tmp"
fi
"$BIN" --version | head -n1

set +e
# Human-readable table in the console...
"$BIN" scan source --lockfile "$LOCKFILE" --format table
rc=$?
# ...and the JSON report as the archived artifact
"$BIN" scan source --lockfile "$LOCKFILE" --format json --output osv-results.json > /dev/null
set -e

case $rc in
    0)   echo "SCA PASSED: no known vulnerabilities in $LOCKFILE" ;;
    1)   echo "SCA FAILED: vulnerable Dart/Flutter packages (see table above / osv-results.json)."
         echo "Upgrade them, or record an accepted risk with a reason in frontend/osv-scanner.toml."
         exit 1 ;;
    128) echo "osv-scanner found no packages in $LOCKFILE (wrong path?)"; exit 1 ;;
    *)   echo "osv-scanner error (exit $rc)"; exit "$rc" ;;
esac
