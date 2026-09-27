#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER="${NEXTCLOUD_CONTAINER:-nextcloud-aio-nextcloud}"
USER_ID="${1:-google-102177204541956609188}"
MOUNT_ID="${2:-2}"

echo "============================================================"
echo " FILEJUMPQUOTA - HEALTHCHECK"
echo "============================================================"
echo "Container : $CONTAINER"
echo "User      : $USER_ID"
echo "Mount ID  : $MOUNT_ID"
echo

echo "=== NEXTCLOUD ==="
docker exec --user www-data "$CONTAINER" php occ status

echo
echo "=== APP FILEJUMPQUOTA ==="
docker exec --user www-data "$CONTAINER"   php occ app:list --enabled | grep -E 'filejumpquota:'   || { echo "[ERRORE] filejumpquota non abilitata"; exit 1; }

echo
echo "=== VERSIONE INSTALLATA ==="
docker exec --user www-data "$CONTAINER"   php occ config:app:get filejumpquota installed_version

echo
echo "=== QUOTA CUSTOM ==="
docker exec --user www-data "$CONTAINER"   php occ user:setting "$USER_ID" filejumpquota custom_quota

echo
echo "=== QUOTA NEXTCLOUD ==="
docker exec --user www-data "$CONTAINER"   php occ user:setting "$USER_ID" files quota

echo
echo "=== STORAGE FILEJUMP-PERSONALE ==="
docker exec --user www-data "$CONTAINER"   php occ files_external:verify "$MOUNT_ID"

echo
echo "=== ERRORI RECENTI ==="
if docker logs "$CONTAINER" --since 10m 2>&1   | grep -Ei 'filejumpquota|exception|fatal|typeerror|undefined|error'   | tail -50; then
  true
fi

echo
echo "============================================================"
echo " HEALTHCHECK COMPLETATO"
echo "============================================================"
