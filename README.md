# DigitalOcean Snapshot Scripts

Two scripts for creating and cleaning up timestamped droplet snapshots via `doctl`:

- **`snapshot.sh`** — creates a snapshot, watches it until it completes, and records it to a state file.
- **`snapshot-cleanup.sh`** — deletes snapshots that were recorded by `snapshot.sh`.

Snapshots are operations that allow backing up your server and files before making changes.

## Requirements

- [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install/) — DigitalOcean's official CLI
- [`jq`](https://jqlang.org/) — used to parse `doctl`'s JSON output
- A DigitalOcean API token with **Read and Write** scope

## Setup

**1. Install dependencies**

```bash
# macOS
brew install doctl jq

# Ubuntu/Debian
sudo apt install jq
snap install doctl   # or download the binary from DO's releases page
```

**2. Authenticate `doctl`**

Generate a token in the DigitalOcean control panel: **API → Tokens → Generate New Token**, with **Read and Write** access. Then:

```bash
doctl auth init
```

Paste the token when prompted. Verify it worked:

```bash
doctl account get
```

**3. Make the scripts executable**

```bash
chmod +x snapshot.sh snapshot-cleanup.sh
```

**4. Find your droplet ID**

```bash
doctl compute droplet list
```

## Usage

### Creating a snapshot

```bash
./snapshot.sh <droplet-id> [snapshot-name-prefix]
```

Example:

```bash
./snapshot.sh 221213419 web-server
```

This creates a snapshot named like `web-server-20260723-143022`, polls every 5 seconds until it's done, and prints the result. On success, the snapshot's ID, name, droplet ID, and creation time are appended to a state file (default: `/tmp/do_snapshots.txt`).

If no prefix is given, it defaults to `backup`.

### Cleaning up snapshots

```bash
./snapshot-cleanup.sh              # delete ALL snapshots tracked in the state file
./snapshot-cleanup.sh --last       # delete only the most recently created one
./snapshot-cleanup.sh --id <id>    # delete a specific snapshot by ID
./snapshot-cleanup.sh --dry-run    # preview what would be deleted, without deleting
```

Add `--dry-run` to any of the above to see what would happen first. Otherwise, the script lists what it's about to delete and asks for `y/N` confirmation before doing anything.

Only snapshots that delete successfully are removed from the state file — if a delete fails, that entry stays tracked so you can retry.

## State file

Both scripts share a plain-text, tab-separated file that tracks created snapshots:

```
<snapshot-id>	<snapshot-name>	<droplet-id>	<created-timestamp-UTC>
```

By default this lives at `/tmp/do_snapshots.txt`, which is cleared on most systems at reboot. To use a persistent location instead, set the `DO_SNAPSHOT_STATE_FILE` environment variable before running either script:

```bash
export DO_SNAPSHOT_STATE_FILE="$HOME/.do_snapshots.txt"
./snapshot.sh 221213419 web-server
./snapshot-cleanup.sh --last
```

Set the same value for both scripts so they read/write the same file.

## Notes

- Snapshots can be taken of a running droplet, but for a fully consistent backup it's best to power the droplet off first (`doctl compute droplet-action power-off <droplet-id>`).
- Snapshots are billed monthly based on storage size until deleted.
- 403 errors usually mean your token is read-only, or belongs to the wrong team — check `doctl account get` and your token's scope in the control panel.
- `unknown column` errors from `doctl ... --format` mean a column name doesn't exist for that resource — run `doctl compute snapshot list --format` with no value to see an error listing valid columns.

## Optional: automate with cron

To run a snapshot automatically, e.g. every night at 2am:

```bash
crontab -e
```

Add:

```
0 2 * * * /path/to/snapshot.sh 221213419 nightly >> /var/log/do-snapshot.log 2>&1
```

Pair with a scheduled cleanup (e.g. weekly) if you want to prune old snapshots rather than keeping every one indefinitely.
