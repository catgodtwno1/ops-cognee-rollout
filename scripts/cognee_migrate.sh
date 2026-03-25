#!/bin/bash
# Migrate Cognee LanceDB data between servers via rsync.
#
# Usage:
#   # Local Mac → NAS (via SSH)
#   bash cognee_migrate.sh \
#     --src-path /path/to/cognee-data/databases \
#     --dst-host openclaw@10.10.10.66 \
#     --dst-path /share/CACHEDEV1_DATA/Container/openclaw-memory/cognee-data/databases
#
#   # Dry run (show what would transfer)
#   bash cognee_migrate.sh \
#     --src-path /path/to/cognee-data/databases \
#     --dst-host openclaw@10.10.10.66 \
#     --dst-path /share/path/databases \
#     --dry-run
#
#   # Local-to-local (Docker volume → another path)
#   bash cognee_migrate.sh \
#     --src-path /var/lib/docker/volumes/cognee-data/_data/databases \
#     --dst-path /backup/cognee-databases
#
# What it migrates:
#   - LanceDB vector data (*.lance files, manifests, indexes)
#   - SQLite metadata (cognee_db)
#   - Dataset directories per user UUID
#
# What it does NOT migrate:
#   - Graph database (kuzu ↔ neo4j incompatible; needs re-cognify)
#   - User accounts (must pre-exist on destination Cognee)
#
# ⚠️  Known pitfalls:
#   - NAS /tmp is tiny (64MB tmpfs) — don't use it as staging
#   - rsync may warn "failed to set times" on NAS — harmless
#   - Stop Cognee container on destination during transfer to avoid conflicts
#   - After migration, restart Cognee and run smoke test

set -euo pipefail

SRC_PATH=""
DST_HOST=""
DST_PATH=""
DRY_RUN=""
STOP_DST_CONTAINER=""
DST_DOCKER=""
DST_CONTAINER="oc-cognee-api"

usage() {
    echo "Usage: $0 --src-path PATH --dst-path PATH [--dst-host user@host] [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --src-path PATH           Source databases directory"
    echo "  --dst-path PATH           Destination databases directory"
    echo "  --dst-host user@host      SSH destination (omit for local-to-local)"
    echo "  --dst-docker PATH         Docker binary on destination (default: docker)"
    echo "  --dst-container NAME      Cognee container name (default: oc-cognee-api)"
    echo "  --stop-container          Stop destination Cognee during transfer"
    echo "  --dry-run                 Show what would transfer without writing"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --src-path) SRC_PATH="$2"; shift 2 ;;
        --dst-path) DST_PATH="$2"; shift 2 ;;
        --dst-host) DST_HOST="$2"; shift 2 ;;
        --dst-docker) DST_DOCKER="$2"; shift 2 ;;
        --dst-container) DST_CONTAINER="$2"; shift 2 ;;
        --stop-container) STOP_DST_CONTAINER=1; shift ;;
        --dry-run) DRY_RUN="--dry-run"; shift ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[[ -z "$SRC_PATH" ]] && { echo "Error: --src-path required"; usage; }
[[ -z "$DST_PATH" ]] && { echo "Error: --dst-path required"; usage; }

echo "============================================================"
echo "Cognee LanceDB Migration"
echo "============================================================"
echo "  Source:      $SRC_PATH"
if [[ -n "$DST_HOST" ]]; then
    echo "  Destination: $DST_HOST:$DST_PATH"
else
    echo "  Destination: $DST_PATH"
fi
[[ -n "$DRY_RUN" ]] && echo "  Mode: DRY RUN"
echo ""

# Count source files
echo "Counting source files..."
SRC_COUNT=$(find "$SRC_PATH" -type f 2>/dev/null | wc -l | tr -d ' ')
SRC_SIZE=$(du -sh "$SRC_PATH" 2>/dev/null | awk '{print $1}')
echo "  Files: $SRC_COUNT"
echo "  Size:  $SRC_SIZE"
echo ""

# Optionally stop destination container
if [[ -n "$STOP_DST_CONTAINER" && -z "$DRY_RUN" ]]; then
    echo "Stopping destination Cognee container..."
    if [[ -n "$DST_HOST" ]]; then
        DOCKER_CMD="${DST_DOCKER:-docker}"
        ssh "$DST_HOST" "$DOCKER_CMD stop $DST_CONTAINER" 2>/dev/null || true
    else
        docker stop "$DST_CONTAINER" 2>/dev/null || true
    fi
    echo "  Stopped."
    echo ""
fi

# Rsync
echo "Starting rsync..."
if [[ -n "$DST_HOST" ]]; then
    rsync -avz --progress $DRY_RUN \
        "$SRC_PATH/" \
        "$DST_HOST:$DST_PATH/"
else
    rsync -avz --progress $DRY_RUN \
        "$SRC_PATH/" \
        "$DST_PATH/"
fi

echo ""

# Restart destination container
if [[ -n "$STOP_DST_CONTAINER" && -z "$DRY_RUN" ]]; then
    echo "Restarting destination Cognee container..."
    if [[ -n "$DST_HOST" ]]; then
        DOCKER_CMD="${DST_DOCKER:-docker}"
        ssh "$DST_HOST" "$DOCKER_CMD start $DST_CONTAINER"
    else
        docker start "$DST_CONTAINER"
    fi
    echo "  Started."
    echo ""
fi

# Verify
if [[ -z "$DRY_RUN" ]]; then
    echo "Verifying destination..."
    if [[ -n "$DST_HOST" ]]; then
        DST_COUNT=$(ssh "$DST_HOST" "find '$DST_PATH' -type f | wc -l" 2>/dev/null | tr -d ' ')
    else
        DST_COUNT=$(find "$DST_PATH" -type f | wc -l | tr -d ' ')
    fi
    echo "  Source files:      $SRC_COUNT"
    echo "  Destination files: $DST_COUNT"
    
    if [[ "$DST_COUNT" -ge "$SRC_COUNT" ]]; then
        echo "  ✅ Transfer complete"
    else
        echo "  ⚠️  Destination has fewer files — check rsync output above"
    fi
fi

echo ""
echo "============================================================"
echo "Done!"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Restart Cognee: docker restart $DST_CONTAINER"
echo "  2. Run smoke test: python3 scripts/cognee_smoke_test.py --base-url http://DEST:8766"
echo ""
echo "⚠️  If source used kuzu and destination uses neo4j for graph DB,"
echo "   the graph data is NOT migrated (incompatible formats)."
echo "   Only LanceDB vectors are transferred. You may need to re-cognify."
