#!/usr/bin/env bash
# Nightly database dump. Lives in the app repo as `deploy/backup.sh` and is installed on
# the server as /usr/local/bin/__APP_NAME__-backup.sh.
#
# It belongs in git, not only on the box: the invariant is that the server holds nothing
# that is not in git or in a dump, and that has to include the thing making the dumps.
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
