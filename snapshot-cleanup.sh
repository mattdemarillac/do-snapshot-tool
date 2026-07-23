#!/bin/bash
#
# snapshot-cleanup.sh - Delete DigitalOcean snapshots recorded by snapshot.sh.
#
# Reads /tmp/do_snapshots.txt (or $DO_SNAPSHOT_STATE_FILE) — one snapshot per line:
#   <snapshot-id>\t<snapshot-name>\t<droplet-id>\t<created-timestamp>
#
# Usage:
#   ./snapshot-cleanup.sh                # delete ALL tracked snapshots
#   ./snapshot-cleanup.sh --last         # delete only the most recently created one
#   ./snapshot-cleanup.sh --id <id>      # delete a specific snapshot ID (also untracks it)
#   ./snapshot-cleanup.sh --dry-run      # show what would be deleted, don't delete
#
# Successfully deleted entries are removed from the state file.

set -euo pipefail

STATE_FILE="${DO_SNAPSHOT_STATE_FILE:-/tmp/do_snapshots.txt}"
MODE="all"
TARGET_ID=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --last)
      MODE="last"
      shift
      ;;
    --id)
      MODE="id"
      TARGET_ID="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if ! command -v doctl >/dev/null 2>&1; then
  echo "Error: doctl is not installed or not on PATH."
  exit 1
fi

if [[ ! -f "$STATE_FILE" || ! -s "$STATE_FILE" ]]; then
  echo "No tracked snapshots found in $STATE_FILE. Nothing to do."
  exit 0
fi

# ---- Select lines to act on ----
case "$MODE" in
  all)
    SELECTED=$(cat "$STATE_FILE")
    ;;
  last)
    SELECTED=$(tail -n 1 "$STATE_FILE")
    ;;
  id)
    if [[ -z "$TARGET_ID" ]]; then
      echo "Error: --id requires a snapshot ID."
      exit 1
    fi
    SELECTED=$(grep -P "^${TARGET_ID}\t" "$STATE_FILE" || true)
    if [[ -z "$SELECTED" ]]; then
      echo "Snapshot ID $TARGET_ID not found in $STATE_FILE."
      exit 1
    fi
    ;;
esac

if [[ -z "$SELECTED" ]]; then
  echo "Nothing matched. Nothing to do."
  exit 0
fi

echo "The following snapshot(s) will be deleted:"
echo "$SELECTED" | awk -F'\t' '{printf "  - %s (%s), droplet %s, created %s\n", $1, $2, $3, $4}'
echo

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry run, no changes made)"
  exit 0
fi

read -r -p "Proceed with deletion? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

DELETED_IDS=()
while IFS=$'\t' read -r SNAP_ID SNAP_NAME DROPLET_ID CREATED_AT; do
  [[ -z "$SNAP_ID" ]] && continue
  echo "Deleting $SNAP_ID ($SNAP_NAME)..."
  if doctl compute snapshot delete "$SNAP_ID" --force; then
    DELETED_IDS+=("$SNAP_ID")
    echo "  ✅ Deleted."
  else
    echo "  ❌ Failed to delete $SNAP_ID — leaving it in $STATE_FILE."
  fi
done <<< "$SELECTED"

# ---- Rewrite state file, dropping the successfully deleted entries ----
if [[ ${#DELETED_IDS[@]} -gt 0 ]]; then
  TMP_FILE=$(mktemp)
  while IFS=$'\t' read -r SNAP_ID SNAP_NAME DROPLET_ID CREATED_AT; do
    [[ -z "$SNAP_ID" ]] && continue
    KEEP=true
    for D in "${DELETED_IDS[@]}"; do
      if [[ "$SNAP_ID" == "$D" ]]; then
        KEEP=false
        break
      fi
    done
    if [[ "$KEEP" == true ]]; then
      printf "%s\t%s\t%s\t%s\n" "$SNAP_ID" "$SNAP_NAME" "$DROPLET_ID" "$CREATED_AT" >> "$TMP_FILE"
    fi
  done < "$STATE_FILE"
  mv "$TMP_FILE" "$STATE_FILE"
  echo
  echo "Updated $STATE_FILE (removed ${#DELETED_IDS[@]} entr$([ ${#DELETED_IDS[@]} -eq 1 ] && echo y || echo ies))."
fi
