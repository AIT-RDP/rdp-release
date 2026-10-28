#!/bin/bash
# Start the dummy generator in the background, then hand PID 1 to InfluxDB's own entrypoint
/bin/bash /scripts/generator.sh &
exec /entrypoint.sh "$@"
