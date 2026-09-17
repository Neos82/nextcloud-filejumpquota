#!/bin/bash

set -u

NC_CONTAINER="nextcloud-aio-nextcloud"
BASE_DIR="/mnt/filejump/Nextcloud-Users"

CONFIG_DIR="/opt/nextcloud-aio/filejumpquota-config"
DEFAULT_QUOTA_FILE="$CONFIG_DIR/default-quota"

echo "============================================================"
echo "Sincronizzazione utenti Nextcloud -> FileJump"
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ============================================================
# Verifica container Nextcloud
# ============================================================

if ! docker ps --format '{{.Names}}' | grep -qx "$NC_CONTAINER"; then
    echo "ERRORE: container $NC_CONTAINER non attivo."
    exit 1
fi

# ============================================================
# Verifica app FileJumpQuota - FAIL CLOSED
# ============================================================

if ! docker exec --user www-data "$NC_CONTAINER" \
    php occ app:list --enabled 2>/dev/null |
    grep -qE '^[[:space:]]*-[[:space:]]+filejumpquota:'; then

    echo "ERRORE CRITICO: app filejumpquota non attiva."
    echo "FAIL-CLOSED: rimozione accesso a FileJump-Personale."

    MEMBERS=$(docker exec --user www-data "$NC_CONTAINER" \
        php occ group:list --output=json 2>/dev/null |
        jq -r '.["filejump-users"][]?' 2>/dev/null)

    if [ -n "$MEMBERS" ]; then
        while IFS= read -r MEMBER; do
            [ -z "$MEMBER" ] && continue

            if docker exec --user www-data "$NC_CONTAINER" \
                php occ group:removeuser filejump-users "$MEMBER"; then
                echo "  Accesso FileJump rimosso: $MEMBER"
            else
                echo "  ERRORE rimozione accesso: $MEMBER"
            fi
        done <<< "$MEMBERS"
    else
        echo "  Gruppo filejump-users gia vuoto."
    fi

    echo "FileJump-Personale bloccato per sicurezza."
    exit 2
fi

echo "OK: app filejumpquota attiva."

# ============================================================
# Verifica mount FileJump
# ============================================================

if ! mountpoint -q /mnt/filejump; then
    echo "ERRORE: /mnt/filejump non risulta montato."
    exit 1
fi

# ============================================================
# Verifica quota DEFAULT
# ============================================================

if [ ! -f "$DEFAULT_QUOTA_FILE" ]; then
    echo "ERRORE: file quota predefinita non trovato:"
    echo "       $DEFAULT_QUOTA_FILE"
    exit 1
fi

DEFAULT_QUOTA=$(tr -d '[:space:]' < "$DEFAULT_QUOTA_FILE")
DEFAULT_QUOTA=$(echo "$DEFAULT_QUOTA" | tr '[:lower:]' '[:upper:]')

if [[ ! "$DEFAULT_QUOTA" =~ ^[1-9][0-9]*(MB|GB|TB)$ ]]; then
    echo "ERRORE: quota DEFAULT non valida: $DEFAULT_QUOTA"
    exit 1
fi

echo "Quota DEFAULT: $DEFAULT_QUOTA"

# ============================================================
# Recupera utenti Nextcloud
# ============================================================

USERS_JSON=$(docker exec --user www-data "$NC_CONTAINER" \
    php occ user:list --limit=0 --info --output=json)

if ! echo "$USERS_JSON" | jq -e . >/dev/null 2>&1; then
    echo "ERRORE: impossibile ottenere la lista utenti Nextcloud."
    exit 1
fi

echo "$USERS_JSON" |
jq -r '
    to_entries[]
    | select(.value.enabled == true)
    | select(.key != "admin")
    | [.key, (.value.quota // "")]
    | @tsv
' |
while IFS=$'\t' read -r NC_UID QUOTA_ATTUALE; do

    if [[ ! "$NC_UID" =~ ^[A-Za-z0-9._@+-]+$ ]]; then
        echo "SKIP: UID non valido per filesystem: $NC_UID"
        continue
    fi

    USER_DIR="$BASE_DIR/$NC_UID"

    echo
    echo "Utente: $NC_UID"

    # ========================================================
    # Gruppo filejump-users
    # ========================================================

    if docker exec --user www-data "$NC_CONTAINER" \
        php occ group:adduser filejump-users "$NC_UID" >/dev/null 2>&1; then

        echo "  Gruppo filejump-users verificato."
    else
        echo "  ERRORE: impossibile associare l'utente a filejump-users."
        continue
    fi

    # ========================================================
    # Directory FileJump
    # ========================================================

    if [ ! -d "$USER_DIR" ]; then
        if mkdir -p "$USER_DIR"; then
            chmod 775 "$USER_DIR" 2>/dev/null || true
            echo "  Directory FileJump creata."
        else
            echo "  ERRORE: impossibile creare $USER_DIR"
            continue
        fi
    else
        echo "  Directory FileJump già presente."
    fi

    # ========================================================
    # Cerca eventuale quota CUSTOM
    # ========================================================

    if CUSTOM_QUOTA=$(docker exec --user www-data "$NC_CONTAINER" \
        php occ user:setting \
        "$NC_UID" \
        filejumpquota \
        custom_quota \
        2>/dev/null); then

        CUSTOM_QUOTA=$(echo "$CUSTOM_QUOTA" | tr -d '[:space:]')
        CUSTOM_QUOTA=$(echo "$CUSTOM_QUOTA" | tr '[:lower:]' '[:upper:]')

    else

        CUSTOM_QUOTA=""

    fi

    if [ -n "$CUSTOM_QUOTA" ]; then

        if [[ ! "$CUSTOM_QUOTA" =~ ^[1-9][0-9]*(MB|GB|TB)$ ]]; then
            echo "  ERRORE: quota CUSTOM non valida: $CUSTOM_QUOTA"
            echo "  Quota attuale lasciata invariata."
            continue
        fi

        TARGET_QUOTA="$CUSTOM_QUOTA"
        QUOTA_TYPE="CUSTOM"
    else
        TARGET_QUOTA="$DEFAULT_QUOTA"
        QUOTA_TYPE="DEFAULT"
    fi

    echo "  Tipo quota: $QUOTA_TYPE"
    echo "  Quota prevista: $TARGET_QUOTA"

    # ========================================================
    # Applica quota Nextcloud
    # ========================================================

    if [ "$QUOTA_ATTUALE" != "$TARGET_QUOTA" ]; then

        if docker exec --user www-data "$NC_CONTAINER" \
            php occ user:setting \
            "$NC_UID" \
            files \
            quota \
            "$TARGET_QUOTA"; then

            echo "  Quota Nextcloud impostata a $TARGET_QUOTA."
        else
            echo "  ERRORE: impossibile impostare la quota."
        fi

    else
        echo "  Quota Nextcloud già impostata a $TARGET_QUOTA."
    fi

done

echo
echo "============================================================"
echo "Sincronizzazione completata."
echo "============================================================"
