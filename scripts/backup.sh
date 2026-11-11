#!/bin/bash

set -euo pipefail

CONTAINER="assessment-postgres"
DB="bookings"
USER="devops"

mkdir -p backups

BACKUP_FILE="backups/bookings_$(date +%Y%m%d_%H%M%S).dump"

docker exec "$CONTAINER" \
pg_dump -U "$USER" -d "$DB" -Fc > "$BACKUP_FILE"

echo "Backup completed successfully"
echo "File: $BACKUP_FILE"
