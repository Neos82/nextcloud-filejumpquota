#!/bin/bash

set -euo pipefail

NC_CONTAINER="nextcloud-aio-nextcloud"
PROVISION_SCRIPT="/usr/local/sbin/nextcloud-filejump-users.sh"

usage() {
    echo "Uso:"
    echo "  $0 <utente> <quota>"
    echo "  $0 <utente> default"
    echo
    echo "Esempi:"
    echo "  $0 mario 300GB"
    echo "  $0 mario 1TB"
    echo "  $0 mario default"
    exit 1
}

[ $# -eq 2 ] || usage

USER_ID="$1"
VALUE="$2"

# ------------------------------------------------------------
# Verifica container
# ------------------------------------------------------------

if ! docker ps --format '{{.Names}}' | grep -qx "$NC_CONTAINER"; then
    echo "ERRORE: container $NC_CONTAINER non attivo."
    exit 1
fi

# ------------------------------------------------------------
# Verifica utente
# ------------------------------------------------------------

if ! docker exec --user www-data "$NC_CONTAINER" \
    php occ user:info "$USER_ID" >/dev/null 2>&1; then

    echo "ERRORE: utente Nextcloud non trovato:"
    echo "       $USER_ID"
    exit 1
fi

# ------------------------------------------------------------
# Ritorno alla quota DEFAULT
# ------------------------------------------------------------

if [[ "${VALUE,,}" == "default" ]]; then

    echo "============================================================"
    echo " FileJump - rimozione quota CUSTOM"
    echo "============================================================"
    echo
    echo "Utente: $USER_ID"
    echo

    if docker exec --user www-data "$NC_CONTAINER" \
        php occ user:setting \
        "$USER_ID" \
        filejumpquota \
        custom_quota \
        --delete >/dev/null 2>&1; then

        echo "[OK] Quota CUSTOM rimossa."
    else
        echo "[INFO] Nessuna quota CUSTOM presente."
    fi

    echo
    echo "Applicazione quota DEFAULT..."

    "$PROVISION_SCRIPT"

    echo
    echo "[OK] Utente riportato alla quota DEFAULT."
    exit 0
fi

# ------------------------------------------------------------
# Normalizzazione quota CUSTOM
# ------------------------------------------------------------

QUOTA=$(echo "$VALUE" | tr '[:lower:]' '[:upper:]')

if [[ ! "$QUOTA" =~ ^[1-9][0-9]*(MB|GB|TB)$ ]]; then
    echo "ERRORE: formato quota non valido: $VALUE"
    echo
    echo "Esempi validi:"
    echo "  50GB"
    echo "  300GB"
    echo "  1TB"
    exit 1
fi

# ------------------------------------------------------------
# Quota attuale
# ------------------------------------------------------------

CURRENT_CUSTOM=""

if CURRENT_CUSTOM=$(docker exec --user www-data "$NC_CONTAINER" \
    php occ user:setting \
    "$USER_ID" \
    filejumpquota \
    custom_quota \
    2>/dev/null); then

    CURRENT_CUSTOM=$(echo "$CURRENT_CUSTOM" | tr -d '[:space:]')

else

    CURRENT_CUSTOM=""

fi

echo "============================================================"
echo " FileJump - quota CUSTOM"
echo "============================================================"
echo
echo "Utente       : $USER_ID"
echo "Quota attuale: ${CURRENT_CUSTOM:-DEFAULT}"
echo "Nuova quota  : $QUOTA"
echo

if [ "$CURRENT_CUSTOM" = "$QUOTA" ]; then
    echo "[OK] Quota CUSTOM già impostata a $QUOTA."
    exit 0
fi

# ------------------------------------------------------------
# Salvataggio quota CUSTOM
# ------------------------------------------------------------

docker exec --user www-data "$NC_CONTAINER" \
    php occ user:setting \
    "$USER_ID" \
    filejumpquota \
    custom_quota \
    "$QUOTA"

echo
echo "[OK] Quota CUSTOM salvata."

# ------------------------------------------------------------
# Applicazione immediata
# ------------------------------------------------------------

echo
echo "Applicazione quota..."

"$PROVISION_SCRIPT"

echo
echo "============================================================"
echo " COMPLETATO"
echo "============================================================"
echo
echo "Utente: $USER_ID"
echo "Quota : $QUOTA"
echo "Tipo  : CUSTOM"
