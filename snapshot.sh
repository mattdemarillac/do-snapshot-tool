!/bin/bash
#
# snapshot.sh - Create a timestamped DigitalOcean droplet snapshot and watch it complete.
#
# Usage:
#   ./snapshot.sh <droplet-id> [snapshot-name-prefix]
#
# Example:
#   ./snapshot.sh 123456789 web-server
#   -> creates a snapshot named: web-server-20260723-143022

set -euo pipefail

# ---- Config ----
STATE_FILE="${DO_SNAPSHOT_STATE_FILE:-/tmp/do_snapshots.txt}"

# ---- Args ----
DROPLET_ID="${1:-}"
PREFIX="${2:-backup}"

if [[ -z "$DROPLET_ID" ]]; then
  echo "Usage: $0 <droplet-id> [snapshot-name-prefix]"
  exit 1
fi

if ! command -v doctl >/dev/null 2>&1; then
  echo "Error: doctl is not installed or not on PATH."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required (used to parse doctl JSON output). Install it and retry."
  exit 1
fi

SNAPSHOT_NAME="${PREFIX}-$(date +%Y%m%d-%H%M%S)"

echo "Droplet ID:     $DROPLET_ID"
echo "Snapshot name:  $SNAPSHOT_NAME"
echo

# ---- Kick off snapshot, capture action ID ----
echo "Requesting snapshot..."
ACTION_JSON=$(doctl compute droplet-action snapshot "$DROPLET_ID" \
  --snapshot-name "$SNAPSHOT_NAME" \
  --output json)

ACTION_ID=$(echo "$ACTION_JSON" | jq -r '.[0].id')

if [[ -z "$ACTION_ID" || "$ACTION_ID" == "null" ]]; then
  echo "Error: could not retrieve action ID from doctl output."
  echo "$ACTION_JSON"
  exit 1
fi

echo "Action ID: $ACTION_ID"
echo "Watching progress..."
echo

# ---- Poll until the action is no longer 'in-progress' ----
STATUS="in-progress"
while [[ "$STATUS" == "in-progress" ]]; do
  sleep 5
  STATUS=$(doctl compute droplet-action get "$DROPLET_ID" \
    --action-id "$ACTION_ID" \
    --output json | jq -r '.[0].status')
  echo "$(date '+%H:%M:%S') - status: $STATUS"
done

echo
if [[ "$STATUS" == "completed" ]]; then
  echo "✅ Snapshot '$SNAPSHOT_NAME' completed successfully."
  echo

  # Look up the actual snapshot resource ID (the action ID above is not the same thing)
  SNAPSHOT_ID=$(doctl compute snapshot list --output json | jq -r --arg NAME "$SNAPSHOT_NAME" '.[] | select(.name == $NAME) | .id')

  if [[ -z "$SNAPSHOT_ID" || "$SNAPSHOT_ID" == "null" ]]; then
    echo "⚠️  Could not find snapshot ID for '$SNAPSHOT_NAME' to record it. You may need to clean it up manually."
  else
    echo "Snapshot details:"
    doctl compute snapshot list --format ID,Name,CreatedAt,Size | grep "$SNAPSHOT_ID" || true
    echo
    # Persist: id<TAB>name<TAB>droplet_id<TAB>created_timestamp
    printf "%s\t%s\t%s\t%s\n" "$SNAPSHOT_ID" "$SNAPSHOT_NAME" "$DROPLET_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_FILE"
    echo "Recorded in $STATE_FILE (snapshot ID: $SNAPSHOT_ID)"
  fi
else
  echo "❌ Snapshot ended with status: $STATUS"
  exit 1
fi
