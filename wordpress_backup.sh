#!/bin/bash
# Back up the florentinatilea.ro database (SQL dump) and files (tar.gz, without db/ and .env).
D=$(date +%F)
DEST=/volume1/Media/Wordpress
SRC=/volume1/docker/florentinatilea

echo "Dumping database..."
docker exec FlorentinaTilea-DB sh -c 'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --single-transaction --routines --triggers florentinatilea_db' \
  > $DEST/$D-florentinatilea.wordpress.sql

TOTAL=$(du -sk --exclude=$SRC/db --exclude=$SRC/.env $SRC | cut -f1)
echo "Archiving files (~$((TOTAL / 1024)) MB)..."
tar czf $DEST/$D-florentinatilea.wordpress.tar.gz -C /volume1/docker \
  --exclude=florentinatilea/db --exclude=florentinatilea/.env \
  --record-size=1K --checkpoint=1024 \
  --checkpoint-action=ttyout="  %u / $TOTAL KB (%d s)%*\r" \
  florentinatilea
echo

ls -lh $DEST/$D-florentinatilea.*

