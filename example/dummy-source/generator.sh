#!/bin/bash
# Dummy data source using only bash, awk and the influx CLI shipped in the image.
set -u

INTERVAL_SECONDS=${INTERVAL_SECONDS:-2}
JITTER_MILLISECONDS=${JITTER_MILLISECONDS:-20}
HISTORY_MINUTES=${HISTORY_MINUTES:-5}
PERIOD_SECONDS=${PERIOD_SECONDS:-60}
DROP_PROBABILITY=${DROP_PROBABILITY:-0.1}
BUCKET=${INFLUX_BUCKET:-${DOCKER_INFLUXDB_INIT_BUCKET}}
: "${INFLUX_ORG:=${DOCKER_INFLUXDB_INIT_ORG:-}}"
: "${INFLUX_TOKEN:=${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN:-}}"

# The influx CLI picks these up automatically
export INFLUX_HOST=http://localhost:8086 INFLUX_ORG INFLUX_TOKEN

log() { echo "[generator] $*"; }

# Generate new data points for the given time range.
generate() {
  # Seeds above 2^31-1 freeze rand() in the image awk, so every tick would be silent and undropped.
  awk -v start="$1" -v end="$2" -v interval="$INTERVAL_SECONDS" -v jitter="$JITTER_MILLISECONDS" \
      -v period="$PERIOD_SECONDS" -v drop="$DROP_PROBABILITY" \
      -v seed="$(( ${SRANDOM:-$RANDOM} % 2147483646 + 1 ))" '
  # Write one line for sensor at timestamp, unless randomly dropped
  function emit(sensor, value, timestamp) {
    if (rand() >= drop)
      printf "%s value=%.4f %.0f\n", sensor, value, timestamp * 1000
  }
  BEGIN {
    srand(seed); pi = atan2(0, -1)
    for (grid = start; grid <= end; grid += interval) {
      emit("sensor_1", sin(2 * pi * grid / period)^2, grid + rand() * jitter / 1000)
      emit("sensor_2", cos(2 * pi * grid / period)^2, grid + rand() * jitter / 1000)
    }
  }'
}

# Earliest epoch-grid point (k * interval) still inside the history window.
start_timestamp() {
  awk -v now="$1" -v history_minutes="$HISTORY_MINUTES" -v interval="$INTERVAL_SECONDS" 'BEGIN {
    step = int(interval)
    window_start = now - int(history_minutes) * 60
    print int(window_start / step) * step
  }'
}

# Next epoch-grid point after the greatest multiple at or below a forward-jittered timestamp.
next_timestamp() {
  awk -v timestamp="$1" -v interval="$INTERVAL_SECONDS" 'BEGIN {
    step = int(interval)
    grid = int(timestamp / step) * step
    print grid + step
  }'
}

# Smallest epoch-grid point strictly after the argument.
upcoming_timestamp() {
  awk -v timestamp="$1" -v interval="$INTERVAL_SECONDS" 'BEGIN {
    step = int(interval)
    print (int(timestamp / step) + 1) * step
  }'
}

# Newest existing point (unix seconds), empty if none. Used only to find the gap;
# the value itself is jittered and is not a grid origin.
last_timestamp() {
  influx query --raw "
    from(bucket: \"$BUCKET\")
      |> range(start: -${HISTORY_MINUTES}m)
      |> filter(fn: (r) => r._measurement == \"sensor_1\" or r._measurement == \"sensor_2\")
      |> group() |> last()
      |> map(fn: (r) => ({_value: int(v: r._time) / 1000000000}))" 2>/dev/null \
  | tr -d '\r' | awk -F, '$2 == "_result" { print $NF }' | tail -n1
}

write() { influx write --bucket "$BUCKET" --precision ms; }

# Wait for the final server (initial setup runs on a temporary port) and the bucket
log "waiting for InfluxDB..."
until influx ping >/dev/null 2>&1 && influx bucket list -n "$BUCKET" >/dev/null 2>&1; do
  sleep 2
done

now=$(date +%s)
start=$(start_timestamp "$now")
last=$(last_timestamp)
if [[ -n "$last" && "$last" -gt "$start" ]]; then
  start=$(next_timestamp "$last")
  log "existing data found, filling gap since $(date -u -d "@$start")"
fi

log "backfilling $(date -u -d "@$start") -> $(date -u -d "@$now")"
generate "$start" "$now" | write && log "backfill done" || log "backfill failed"

log "live mode: every ${INTERVAL_SECONDS}s, timestamp jitter [0, ${JITTER_MILLISECONDS}]ms"
upcoming=$(upcoming_timestamp "$(date +%s.%N)")
while true; do
  # get current UTC time as seconds since the Unix epoch, with the fractional part in nanoseconds
  now=$(date +%s.%N)
  # In case the previous write ran long, then `now` is already past `upcoming` and the awk condition exits with 0.
  # The schedule then jumps to the next grid point still ahead of now.
  if awk -v now="$now" -v target="$upcoming" 'BEGIN { exit !(now > target) }'; then
    upcoming=$(upcoming_timestamp "$now")
  fi
  # Sleeps the remaining time until next grid timestamp.
  # The delay is 0 when the schedule was just moved forward because `now` had already passed the old target.
  delay=$(awk -v now="$now" -v target="$upcoming" 'BEGIN {
    d = target - now
    print (d > 0 ? d : 0)
  }')
  sleep "$delay"
  # Generates and writes the new data point for the current grid timestamp.
  lines=$(generate "$upcoming" "$upcoming")
  if [[ -n "$lines" ]]; then
    write <<< "$lines" || log "write failed, will retry next tick"
  fi
  # Move the schedule forward to the next grid timestamp.
  upcoming=$(upcoming_timestamp "$upcoming")
done
