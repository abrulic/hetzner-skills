#!/usr/bin/env bash
set -euo pipefail

APP=__APP_NAME__
BACKUP_DIR=/var/backups/$APP
mkdir -p "$BACKUP_DIR"
FILE="$BACKUP_DIR/$APP-$(date +%F-%H%M).dump"

cd /srv/$APP
docker compose -f docker-compose.prod.yml exec -T postgres \
  pg_dump -U "$APP" -d "$APP" -Fc --no-owner --no-privileges > "$FILE"

test -s "$FILE"

for VOLUME in ${APP}_uploads; do
  docker run --rm -v "$VOLUME":/data -v "$BACKUP_DIR":/backup alpine \
    tar czf "/backup/$VOLUME-$(date +%F-%H%M).tar.gz" -C /data .
done

find "$BACKUP_DIR" -name "$APP-*.dump" -mtime +14 -delete
find "$BACKUP_DIR" -name "${APP}_*.tar.gz" -mtime +14 -delete
