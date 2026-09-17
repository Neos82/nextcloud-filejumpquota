#!/bin/bash

set -euo pipefail

CONFIG_DIR="/opt/nextcloud-aio/filejumpquota-config"
DEFAULT_FILE="$CONFIG_DIR/default-quota"
SYNC_SCRIPT="/usr/local/sbin/nextcloud-filejump-users.sh"

if [ $# -ne 1 ]; then
    echo "Uso:"
    echo "  set-filejump-quota.sh <quota>"
    echo
    echo "Esempi:"
    echo "  set-filejump-quota.sh 100GB"
    echo "  set-filejump-quota.sh 200GB"
    echo "  set-filejump-quota.sh 1TB"
    exit 1
fi

NEW_QUOTA=$(echo "$1" | tr '[:lower:]' '[:upper:]')

if [[ ! "$NEW_QUOTA" =~ ^[1-9][0-9]*(MB|GB|TB)$ ]]; then
    echo "ERRORE: quota non valida: $1"
    echo "Formati ammessi: 500MB, 100GB, 1TB"
    exit 1
fi

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

OLD_QUOTA="NON IMPOSTATA"

if [ -f "$DEFAULT_FILE" ]; then
    OLD_QUOTA=$(tr -d '[:space:]' < "$DEFAULT_FILE")
fi

echo "============================================================"
echo " FileJump - modifica quota DEFAULT"
echo "============================================================"
echo
echo "Quota attuale : $OLD_QUOTA"
echo "Nuova quota   : $NEW_QUOTA"
echo

if [ "$OLD_QUOTA" = "$NEW_QUOTA" ]; then
    echo "[INFO] La quota DEFAULT è già $NEW_QUOTA."
    echo "[INFO] Eseguo comunque la sincronizzazione utenti."
else
    TMP_FILE=$(mktemp "$CONFIG_DIR/.default-quota.XXXXXX")

    printf '%s\n' "$NEW_QUOTA" > "$TMP_FILE"
    chmod 600 "$TMP_FILE"

    mv "$TMP_FILE" "$DEFAULT_FILE"

    echo "[OK] Quota DEFAULT aggiornata."
fi

echo
echo "Sincronizzazione utenti..."

"$SYNC_SCRIPT"

echo
echo "============================================================"
echo " COMPLETATO"
echo "============================================================"
echo
echo "Quota DEFAULT: $NEW_QUOTA"
echo "Le quote CUSTOM non sono state modificate."
