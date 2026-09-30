#!/usr/bin/env bash
# Lab 10 - install every CI tool the taskflow-api pipeline needs.
#  * Versions come from the Jenkinsfile "environment" block (one source of truth).
#  * Every download is checksum-verified. No "curl | sh" from a moving 'main' branch
#    (that is how the March 2026 Trivy incident reached people).
#  * Binaries are cached on the ci-tools PVC mounted at /tools, so only the first
#    build on a fresh cluster downloads anything. Later builds just create symlinks.
set -euo pipefail

: "${JQ_VER:?}" "${GITLEAKS_VER:?}" "${SYFT_VER:?}" "${COSIGN_VER:?}" "${OPA_VER:?}"
: "${TRIVY_VER:?}" "${TFSEC_VER:?}" "${CHECKOV_VER:?}"

CACHE=/tools
BIN="$CACHE/bin"
mkdir -p "$BIN"

# Two builds can share the PVC at the same time: let only one of them install.
exec 9>"$CACHE/.install.lock"
flock -w 600 9

# fetch_verified NAME VERSION URL SUMS_URL ASSET [TAR_MEMBER]
fetch_verified() {
    local name=$1 ver=$2 url=$3 sums_url=$4 asset=$5 member=${6:-}
    local dest="$BIN/${name}-${ver}"
    if [ ! -x "$dest" ]; then
        echo "--> downloading ${name} ${ver}"
        local tmp
        tmp=$(mktemp -d)
        (
            cd "$tmp"
            curl -fsSL --retry 3 -o "$asset" "$url"
            curl -fsSL --retry 3 -o SUMS "$sums_url"
            # keep only the line for our asset, normalise "hash *file" to "hash  file"
            grep -E "[ *]${asset}\$" SUMS | head -n1 | sed -E "s/[ *]+${asset}\$/  ${asset}/" > CHECK
            [ -s CHECK ] || { echo "no checksum line for ${asset} in ${sums_url}"; exit 1; }
            sha256sum -c CHECK
            if [ -n "$member" ]; then
                tar -xzf "$asset" "$member"
            else
                mv "$asset" "$name"
                member=$name
            fi
            install -m 0755 "$member" "${dest}.tmp"
            mv -f "${dest}.tmp" "$dest"
        )
        rm -rf "$tmp"
    fi
    ln -sf "$dest" "/usr/local/bin/${name}"
}

GH=https://github.com

fetch_verified jq "$JQ_VER" \
    "$GH/jqlang/jq/releases/download/jq-${JQ_VER}/jq-linux-amd64" \
    "$GH/jqlang/jq/releases/download/jq-${JQ_VER}/sha256sum.txt" \
    jq-linux-amd64

fetch_verified gitleaks "$GITLEAKS_VER" \
    "$GH/gitleaks/gitleaks/releases/download/v${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_linux_x64.tar.gz" \
    "$GH/gitleaks/gitleaks/releases/download/v${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_checksums.txt" \
    "gitleaks_${GITLEAKS_VER}_linux_x64.tar.gz" gitleaks

fetch_verified syft "$SYFT_VER" \
    "$GH/anchore/syft/releases/download/v${SYFT_VER}/syft_${SYFT_VER}_linux_amd64.tar.gz" \
    "$GH/anchore/syft/releases/download/v${SYFT_VER}/syft_${SYFT_VER}_checksums.txt" \
    "syft_${SYFT_VER}_linux_amd64.tar.gz" syft

fetch_verified cosign "$COSIGN_VER" \
    "$GH/sigstore/cosign/releases/download/v${COSIGN_VER}/cosign-linux-amd64" \
    "$GH/sigstore/cosign/releases/download/v${COSIGN_VER}/cosign_checksums.txt" \
    cosign-linux-amd64

fetch_verified opa "$OPA_VER" \
    "$GH/open-policy-agent/opa/releases/download/v${OPA_VER}/opa_linux_amd64_static" \
    "$GH/open-policy-agent/opa/releases/download/v${OPA_VER}/opa_linux_amd64_static.sha256" \
    opa_linux_amd64_static

fetch_verified trivy "$TRIVY_VER" \
    "$GH/aquasecurity/trivy/releases/download/v${TRIVY_VER}/trivy_${TRIVY_VER}_Linux-64bit.tar.gz" \
    "$GH/aquasecurity/trivy/releases/download/v${TRIVY_VER}/trivy_${TRIVY_VER}_checksums.txt" \
    "trivy_${TRIVY_VER}_Linux-64bit.tar.gz" trivy

fetch_verified tfsec "$TFSEC_VER" \
    "$GH/aquasecurity/tfsec/releases/download/v${TFSEC_VER}/tfsec_${TFSEC_VER}_linux_amd64.tar.gz" \
    "$GH/aquasecurity/tfsec/releases/download/v${TFSEC_VER}/tfsec_${TFSEC_VER}_checksums.txt" \
    "tfsec_${TFSEC_VER}_linux_amd64.tar.gz" tfsec

# kubectl: current stable (avoids skew with the kind node); its .sha256 file holds only the hash
KUBECTL_VER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
if [ ! -x "$BIN/kubectl-${KUBECTL_VER}" ]; then
    echo "--> downloading kubectl ${KUBECTL_VER}"
    tmp=$(mktemp -d)
    curl -fsSL --retry 3 -o "$tmp/kubectl" "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
    echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl.sha256")  $tmp/kubectl" | sha256sum -c -
    install -m 0755 "$tmp/kubectl" "$BIN/kubectl-${KUBECTL_VER}.tmp"
    mv -f "$BIN/kubectl-${KUBECTL_VER}.tmp" "$BIN/kubectl-${KUBECTL_VER}"
    rm -rf "$tmp"
fi
ln -sf "$BIN/kubectl-${KUBECTL_VER}" /usr/local/bin/kubectl

# Python tools, each in its own venv (semgrep and checkov pin conflicting libraries).
# A cached venv is only reused if its Python still runs (e.g. after node:22 moves to a new Debian).
venv_ok() { [ -x "$1/bin/python" ] && "$1/bin/python" -c 'import sys' 2>/dev/null; }
SEMGREP_VENV="$CACHE/venv-semgrep-${SEMGREP_VER:-latest}"
CHECKOV_VENV="$CACHE/venv-checkov-${CHECKOV_VER}"
if ! venv_ok "$SEMGREP_VENV" || ! venv_ok "$CHECKOV_VENV"; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv >/dev/null
fi
if ! venv_ok "$SEMGREP_VENV" || [ ! -x "$SEMGREP_VENV/bin/semgrep" ]; then
    rm -rf "$SEMGREP_VENV"
    python3 -m venv "$SEMGREP_VENV"
    "$SEMGREP_VENV/bin/pip" install -q --upgrade pip
    "$SEMGREP_VENV/bin/pip" install -q "semgrep${SEMGREP_VER:+==$SEMGREP_VER}"
fi
if ! venv_ok "$CHECKOV_VENV" || [ ! -x "$CHECKOV_VENV/bin/checkov" ]; then
    rm -rf "$CHECKOV_VENV"
    python3 -m venv "$CHECKOV_VENV"
    "$CHECKOV_VENV/bin/pip" install -q --upgrade pip
    "$CHECKOV_VENV/bin/pip" install -q "checkov==${CHECKOV_VER}"
fi
ln -sf "$SEMGREP_VENV/bin/semgrep" /usr/local/bin/semgrep
ln -sf "$CHECKOV_VENV/bin/checkov" /usr/local/bin/checkov

echo "== tool versions =="
jq --version
gitleaks version
syft version | grep -m1 -i '^version'
cosign version 2>&1 | grep -m1 -i 'gitversion'
opa version | head -n1
trivy --version | head -n1
tfsec --version
kubectl version --client | head -n1
semgrep --version
checkov --version