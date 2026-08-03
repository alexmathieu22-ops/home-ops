#!/usr/bin/env bash
# Always-Free Ampere A1 capacity is scarce and fluctuates by the minute -- "Out of host
# capacity" on `tofu apply` is expected, not a config error. This is the standard
# community workaround: keep retrying until a slot opens up in this region/AD.
set -uo pipefail
cd "$(dirname "$0")"

interval="${1:-60}"
attempt=0

while true; do
  attempt=$((attempt + 1))
  echo "[$(date +%H:%M:%S)] attempt ${attempt}..."
  output=$(tofu apply -auto-approve 2>&1)
  status=$?
  echo "$output"

  if [ "$status" -eq 0 ]; then
    echo "Instance created."
    exit 0
  fi

  if echo "$output" | grep -q "Out of host capacity"; then
    echo "Out of capacity -- retrying in ${interval}s..."
    sleep "$interval"
    continue
  fi

  echo "Apply failed for a non-capacity reason -- stopping."
  exit "$status"
done
