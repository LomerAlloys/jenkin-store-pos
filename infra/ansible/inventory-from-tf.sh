#!/usr/bin/env bash
# Build an Ansible inventory from Terraform outputs (dynamic inventory).
# Usage: inventory-from-tf.sh <terraform dir> <inventory file>
set -euo pipefail

TF_DIR="${1:-infra/terraform}"
OUT="${2:-infra/ansible/inventory.ini}"

INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw instance_id)
CANDIDATES="$(terraform -chdir="$TF_DIR" output -raw instance_address) $(terraform -chdir="$TF_DIR" output -raw private_ip)"

# LocalStack runs each EC2 instance as a Docker container. If the address AWS
# reports is not routable from this pipeline container, fall back to the
# container's IP on jenkins-net (EC2_DOCKER_FLAGS put it there).
if command -v docker >/dev/null 2>&1; then
  CID=$(docker ps -q --filter "name=${INSTANCE_ID}" | head -n1)
  if [ -n "$CID" ]; then
    NET_IP=$(docker inspect -f '{{with index .NetworkSettings.Networks "jenkins-net"}}{{.IPAddress}}{{end}}' "$CID")
    CANDIDATES="$CANDIDATES $NET_IP"
  fi
fi
echo "Instance ${INSTANCE_ID}; candidate addresses: ${CANDIDATES}"

HOST=""
for attempt in $(seq 1 30); do
  for ip in $CANDIDATES; do
    if timeout 2 bash -c "</dev/tcp/${ip}/22" 2>/dev/null; then
      HOST="$ip"
      break 2
    fi
  done
  echo "SSH not reachable yet (attempt ${attempt}/30)"; sleep 3
done
[ -n "$HOST" ] || { echo "No candidate address answered on port 22"; exit 1; }

cat > "$OUT" <<INV
[taskflow]
${INSTANCE_ID} ansible_host=${HOST}

[taskflow:vars]
ansible_python_interpreter=/usr/bin/python3
INV
echo "Inventory written to ${OUT}:"
cat "$OUT"
