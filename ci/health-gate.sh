#!/usr/bin/env bash
# Lab 10 Task 4 - Pipeline Health Gate.
# Asks the Lab 09 Prometheus for Jenkins' build counters and blocks the production
# deploy when the success rate over the last $HEALTH_WINDOW finished builds is below
# $HEALTH_THRESHOLD.
#
# How "last 20 builds" is computed from time-series data:
#   jenkins_runs_total_total and jenkins_runs_success_total are counters (Metrics plugin).
#   We fetch both for the last 7 days, take the newest value of "total" (N), find the newest
#   sample where total <= N - 20, and compare the two counters between that point and now:
#       rate = (success_now - success_then) / (total_now - total_then)
#   A Jenkins restart resets the counters, so only samples after the last reset are used.
#
# Fails CLOSED: if Prometheus can't be reached, we can't prove the pipeline is healthy,
# so we don't deploy.
set -euo pipefail

PROM_URL="${PROM_URL:-http://prometheus:9090}"
WINDOW="${HEALTH_WINDOW:-20}"
THRESHOLD="${HEALTH_THRESHOLD:-0.90}"
MIN_BUILDS="${HEALTH_MIN_BUILDS:-5}"       # fewer finished builds than this = not enough data
LOOKBACK_S="${HEALTH_LOOKBACK_S:-604800}"  # 7 days
STEP_S="${HEALTH_STEP_S:-60}"              # 7d / 60s = 10 080 points (< Prometheus' 11 000 limit)

end=$(date +%s)
start=$((end - LOOKBACK_S))

query_range() {
    curl -fsS --max-time 20 --get "${PROM_URL}/api/v1/query_range" \
        --data-urlencode "query=$1" \
        --data-urlencode "start=${start}" \
        --data-urlencode "end=${end}" \
        --data-urlencode "step=${STEP_S}"
}

echo "Health gate: last ${WINDOW} builds must succeed >= ${THRESHOLD} (source: ${PROM_URL})"
if ! query_range 'sum(jenkins_runs_total_total)' > health-total.json ||
   ! query_range 'sum(jenkins_runs_success_total)' > health-success.json; then
    echo "HEALTH GATE: cannot query Prometheus at ${PROM_URL} -> failing closed (deploy blocked)"
    exit 2
fi

jq -n --slurpfile t health-total.json --slurpfile s health-success.json --argjson window "$WINDOW" '
  def series($f): ($f[0].data.result[0].values // []) | map([.[0], (.[1] | tonumber)]);
  series($t) as $tot
  | (series($s) | map({key: (.[0] | tostring), value: .[1]}) | from_entries) as $ok
  | if ($tot | length) == 0 then {error: "no samples for jenkins_runs_total_total"}
    else
      # index of the last counter reset (Jenkins restart); 0 if none
      ([range(1; $tot | length) | select($tot[.][1] < $tot[. - 1][1])] | last // 0) as $r
      | $tot[$r:] as $tv
      | ($tv | last) as $now
      | ([$tv[] | select(.[1] <= ($now[1] - $window))] | last // $tv[0]) as $base
      | ($now[1] - $base[1]) as $builds
      | (($ok[$now[0] | tostring] // 0) - ($ok[$base[0] | tostring] // 0)) as $good
      | { builds: $builds,
          successes: $good,
          failures: ($builds - $good),
          rate: (if $builds > 0 then ($good / $builds) else null end),
          from: ($base[0] | todate),
          to: ($now[0] | todate) }
    end' > health-result.json

cat health-result.json

if jq -e 'has("error")' health-result.json > /dev/null; then
    echo "HEALTH GATE: $(jq -r .error health-result.json) -> failing closed (deploy blocked)"
    exit 2
fi

if jq -e --argjson min "$MIN_BUILDS" '.builds < $min' health-result.json > /dev/null; then
    echo "HEALTH GATE: only $(jq -r .builds health-result.json) finished builds in the window" \
         "(need ${MIN_BUILDS}) -> not enough data, passing with a warning"
    exit 0
fi

summary=$(jq -r '"\(.successes)/\(.builds) builds succeeded = \((.rate * 1000 | round) / 10)%"' health-result.json)
if jq -e --argjson th "$THRESHOLD" '.rate >= $th' health-result.json > /dev/null; then
    echo "HEALTH GATE PASSED: ${summary} (threshold $(jq -n --argjson th "$THRESHOLD" '$th * 100')%)"
else
    echo "HEALTH GATE BLOCKED: ${summary} (threshold $(jq -n --argjson th "$THRESHOLD" '$th * 100')%)."
    echo "The pipeline itself is unhealthy. Fix the failing builds before deploying to production."
    exit 1
fi
