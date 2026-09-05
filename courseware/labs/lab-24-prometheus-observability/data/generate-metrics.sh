#!/bin/sh
# ---------------------------------------------------------------------------
# Meridian Freight Pte Ltd — Depot Portal metrics simulator
# Lab 24 · consumed by the "generator" container in manifests/10-depot-metrics-sim.yaml
#
# WHAT THIS IS
# ------------
# A real application does not write its own exposition text: it registers
# metrics with a Prometheus client library, and the library renders this format
# on demand. This script renders the SAME format by hand so that you can read
# every character of it and know exactly where each line came from.
#
# It rewrites /www/metrics every 10 seconds:
#   * counters only ever increase        (shipments scanned, rejects, HTTP)
#   * the gauge moves up and down        (queue depth, active drivers)
#   * histogram buckets are CUMULATIVE   (le="0.5" <= le="1" <= ... <= le="+Inf")
#
# ATOMIC WRITE
# ------------
# It writes to /www/metrics.tmp and then renames. A scrape that lands mid-write
# would otherwise read a truncated exposition and be recorded as a parse
# failure. Rename is atomic within a filesystem, so a scraper always sees a
# complete document. Real exporters serve from memory and get this for free.
# ---------------------------------------------------------------------------
set -u

OUT_DIR=/www
scanned=0
rejected=0
http_ok=0
http_err=0
i=0

echo "[generator] rendering Prometheus exposition to ${OUT_DIR}/metrics every 10s"

while true; do
  i=$((i + 1))

  # --- counters: monotonically increasing, never reset while the process lives
  scanned=$((scanned + 7 + (i % 5)))
  rejected=$((rejected + (i % 2)))
  http_ok=$((http_ok + 11 + (i % 3)))
  # Errors are rarer than successes: one every fourth cycle. Written as a plain
  # test rather than a ternary so it is portable to BusyBox ash.
  if [ $((i % 4)) -eq 0 ]; then
    http_err=$((http_err + 1))
  fi

  # --- gauge: goes up AND down, which is what makes it a gauge
  depth=$((12 + (i * 7) % 40))
  drivers=$((4 + (i * 3) % 9))

  # --- histogram: cumulative buckets over the same population as _count
  b_05=$((scanned * 62 / 100))
  b_10=$((scanned * 84 / 100))
  b_25=$((scanned * 96 / 100))
  b_50=$((scanned * 99 / 100))
  b_inf=$scanned
  # A crude but monotonic sum, in seconds.
  sum=$((scanned * 41 / 100))

  cat > "${OUT_DIR}/metrics.tmp" <<EOF
# HELP depot_portal_shipments_scanned_total Shipment barcodes scanned at the depot gate since process start.
# TYPE depot_portal_shipments_scanned_total counter
depot_portal_shipments_scanned_total{depot="sg-tuas",lane="inbound"} ${scanned}
# HELP depot_portal_shipments_rejected_total Shipments rejected at the gate since process start.
# TYPE depot_portal_shipments_rejected_total counter
depot_portal_shipments_rejected_total{depot="sg-tuas",lane="inbound",reason="manifest_not_indexed"} ${rejected}
# HELP depot_portal_http_requests_total HTTP requests handled by the depot portal.
# TYPE depot_portal_http_requests_total counter
depot_portal_http_requests_total{depot="sg-tuas",method="GET",status="200"} ${http_ok}
depot_portal_http_requests_total{depot="sg-tuas",method="POST",status="502"} ${http_err}
# HELP depot_portal_queue_depth Shipments currently waiting in the gate queue.
# TYPE depot_portal_queue_depth gauge
depot_portal_queue_depth{depot="sg-tuas",lane="inbound"} ${depth}
# HELP depot_portal_active_drivers Drivers currently checked in at the depot.
# TYPE depot_portal_active_drivers gauge
depot_portal_active_drivers{depot="sg-tuas"} ${drivers}
# HELP depot_portal_scan_latency_seconds Time taken to scan and validate one shipment.
# TYPE depot_portal_scan_latency_seconds histogram
depot_portal_scan_latency_seconds_bucket{depot="sg-tuas",le="0.5"} ${b_05}
depot_portal_scan_latency_seconds_bucket{depot="sg-tuas",le="1"} ${b_10}
depot_portal_scan_latency_seconds_bucket{depot="sg-tuas",le="2.5"} ${b_25}
depot_portal_scan_latency_seconds_bucket{depot="sg-tuas",le="5"} ${b_50}
depot_portal_scan_latency_seconds_bucket{depot="sg-tuas",le="+Inf"} ${b_inf}
depot_portal_scan_latency_seconds_sum{depot="sg-tuas"} ${sum}
depot_portal_scan_latency_seconds_count{depot="sg-tuas"} ${b_inf}
# HELP depot_portal_build_info Build metadata. Always 1; the LABELS carry the information.
# TYPE depot_portal_build_info gauge
depot_portal_build_info{version="6.0.0",revision="a41f9c2",depot="sg-tuas"} 1
EOF

  mv "${OUT_DIR}/metrics.tmp" "${OUT_DIR}/metrics"
  sleep 10
done
