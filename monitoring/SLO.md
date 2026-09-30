# Jenkins pipeline SLO (Lab 09)

| | |
|---|---|
| Service | Jenkins CI for taskflow-api |
| SLI | Share of builds that finish in under 6 minutes (360 s) |
| SLO | 95% of builds, rolling 7-day window |
| Error budget | 5% of builds per 7 days may take longer (e.g. 100 builds/week → 5 slow builds) |
| Measured with | `jenkins:build_duration_p95:seconds` (p95 of build duration, Metrics plugin timer). SLO met for the window when `max_over_time(jenkins:build_duration_p95:seconds[7d]) <= 360` |
| Paging alert | `JenkinsQueueBacklog`: p95 queue wait > 2 min for 5 min (symptom: developers wait for CI) |

Limitation: the plugin exports summaries (quantiles), not histogram buckets, so the SLI is
approximated from the p95 over time. An exact "% of builds < 360 s" needs a histogram with a 360 s
bucket.

Why alert on queue wait and not CPU/pods: queue wait is what users *feel* (symptom). "Only 2 pods
allowed" or "node CPU 90%" are *causes*. They might hurt nobody, and many different causes all
show up as the same symptom.
