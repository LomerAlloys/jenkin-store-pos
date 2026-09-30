# Lab 09 - start (or refresh) Prometheus + Grafana on jenkins-net.
# No bind mounts (Thai characters in the path deadlock Docker Desktop): create -> docker cp -> start.
# Usage (from anywhere):  powershell -ExecutionPolicy Bypass -File monitoring\start-monitoring.ps1
# Re-run after editing prometheus.yml / rules: it copies the files again and hot-reloads Prometheus.

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

function Test-Container($name) {
    return [bool](docker ps -a --filter "name=^$name$" --format '{{.Names}}')
}

# ---------- Prometheus ----------
if (-not (Test-Container 'prometheus')) {
    docker volume create prom-data | Out-Null
    docker create --name prometheus --network jenkins-net --restart unless-stopped `
        -p 127.0.0.1:9090:9090 -v prom-data:/prometheus `
        prom/prometheus:v3.5.0 `
        --config.file=/etc/prometheus/prometheus.yml `
        --storage.tsdb.path=/prometheus `
        --storage.tsdb.retention.time=15d `
        --web.enable-lifecycle | Out-Null
    docker cp "$here\prometheus\." prometheus:/etc/prometheus/
    docker start prometheus | Out-Null
    Write-Host "Prometheus created and started -> http://localhost:9090"
} else {
    docker cp "$here\prometheus\." prometheus:/etc/prometheus/
    docker start prometheus | Out-Null
    Start-Sleep -Seconds 2
    curl.exe -s -X POST http://localhost:9090/-/reload | Out-Null
    Write-Host "Prometheus config copied and reloaded"
}
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml

# ---------- Grafana ----------
if (-not (Test-Container 'grafana')) {
    docker volume create grafana-data | Out-Null
    docker create --name grafana --network jenkins-net --restart unless-stopped `
        -p 127.0.0.1:3001:3000 -v grafana-data:/var/lib/grafana `
        grafana/grafana:12.1.0 | Out-Null
    docker cp "$here\grafana\provisioning\datasources\prometheus.yml" grafana:/etc/grafana/provisioning/datasources/prometheus.yml
    docker start grafana | Out-Null
    Write-Host "Grafana created and started -> http://localhost:3001 (admin/admin on first login)"
} else {
    docker start grafana | Out-Null
    Write-Host "Grafana running -> http://localhost:3001"
}

Write-Host "Next: Prometheus > Status > Target health should show 'jenkins' UP."
Write-Host "Then import monitoring\grafana\jenkins-pipeline-health.json in Grafana."
