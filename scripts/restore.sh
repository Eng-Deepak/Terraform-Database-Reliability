#!/bin/bash

set -euo pipefail

CONTAINER="assessment-postgres"
USER="devops"
RESTORE_DB="bookings_restore"

BACKUP_FILE="${1:-}"

if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
    echo "Usage: ./scripts/restore.sh backups/file.dump"
    exit 1
fi

docker exec "$CONTAINER" \
dropdb --if-exists -U "$USER" "$RESTORE_DB"

docker exec "$CONTAINER" \
createdb -U "$USER" "$RESTORE_DB"

docker exec -i "$CONTAINER" \
pg_restore -U "$USER" -d "$RESTORE_DB" \
--no-owner --no-privileges < "$BACKUP_FILE"

echo "Restore completed successfully"

docker exec "$CONTAINER" \
psql -U "$USER" -d "$RESTORE_DB" \
-c "SELECT COUNT(*) FROM hotel_bookings;"
