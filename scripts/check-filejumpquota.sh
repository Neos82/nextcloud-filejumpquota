#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER="${NEXTCLOUD_CONTAINER:-nextcloud-aio-nextcloud}"
USER_ID="${1:-google-102177204541956609188}"
MOUNT_ID="${2:-2}"
DEFAULT_QUOTA_FILE="/opt/nextcloud-aio/filejumpquota-config/default-quota"
RESOLVED_PATH="/mnt/filejump/Nextcloud-Users/${USER_ID}"

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
echo "=== QUOTA STANDARD ==="
if [[ -f "$DEFAULT_QUOTA_FILE" ]]; then
  DEFAULT_QUOTA="$(tr -d '[:space:]' < "$DEFAULT_QUOTA_FILE")"
  echo "$DEFAULT_QUOTA"
else
  echo "[ERRORE] File quota standard non trovato: $DEFAULT_QUOTA_FILE"
  DEFAULT_QUOTA="N/D"
fi

echo
echo "=== QUOTA CUSTOM UTENTE ==="
CUSTOM_QUOTA="$(
  docker exec --user www-data "$CONTAINER"     php occ user:setting "$USER_ID" filejumpquota custom_quota 2>/dev/null     || true
)"
if [[ -n "$CUSTOM_QUOTA" ]]; then
  echo "$CUSTOM_QUOTA"
else
  echo "Nessuna quota custom -> usa quota standard ($DEFAULT_QUOTA)"
fi

echo
echo "=== QUOTA EFFETTIVA NEXTCLOUD ==="
NC_QUOTA="$(
  docker exec --user www-data "$CONTAINER"     php occ user:setting "$USER_ID" files quota 2>/dev/null     || true
)"
echo "${NC_QUOTA:-N/D}"

echo
echo "=== STORAGE FILEJUMP-PERSONALE ==="
echo "Percorso configurato con variabile: /mnt/filejump/Nextcloud-Users/\$user/"
echo "Percorso risolto per l'utente     : $RESOLVED_PATH"
if docker exec "$CONTAINER" test -d "$RESOLVED_PATH"; then
  echo "[OK] Directory personale presente"
  docker exec "$CONTAINER" ls -ld "$RESOLVED_PATH"
else
  echo "[ERRORE] Directory personale non presente"
  exit 1
fi

echo
echo "=== WRAPPER FILEJUMPQUOTA ==="
docker exec -i --user www-data   -e FJQ_UID="$USER_ID"   "$CONTAINER" php <<'PHP'
<?php
require '/var/www/html/lib/base.php';

$uid = getenv('FJQ_UID');
$root = \\OC::$server->get(\\OCP\\Files\\IRootFolder::class);

try {
    $userFolder = $root->getUserFolder($uid);
    $node = $userFolder->get('FileJump-Personale');
    $storage = $node->getStorage();

    $present = $storage->instanceOfStorage(
        \\OCA\\FileJumpQuota\\Storage\\FileJumpQuota::class
    );

    echo $present
        ? "[OK] FileJumpQuota wrapper PRESENTE\n"
        : "[ERRORE] FileJumpQuota wrapper NON PRESENTE\n";

    exit($present ? 0 : 1);
} catch (\\Throwable $e) {
    echo "[ERRORE] " . $e->getMessage() . "\n";
    exit(1);
}
PHP

echo
echo "=== TIMER PROVISIONING ==="
systemctl is-enabled nextcloud-filejump-users.timer
systemctl is-active nextcloud-filejump-users.timer

echo
echo "=== ERRORI RECENTI FILEJUMPQUOTA ==="
docker logs "$CONTAINER" --since 10m 2>&1   | grep -Ei 'filejumpquota|exception|fatal|typeerror|undefined'   | tail -50 || true

echo
echo "============================================================"
echo " HEALTHCHECK COMPLETATO"
echo "============================================================"
