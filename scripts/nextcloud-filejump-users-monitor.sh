#!/bin/bash

PROVISIONING="/usr/local/sbin/nextcloud-filejump-users.sh"
ALERT="/usr/local/sbin/nextcloud-filejump-alert.sh"

echo "============================================================"
echo "Monitor FileJumpQuota"
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

if [ ! -x "$PROVISIONING" ]; then
    echo "ERRORE: script provisioning non trovato."
    "$ALERT" ERROR "Script provisioning FileJump non disponibile"
    exit 1
fi

# Esegue il provisioning originale
"$PROVISIONING"
RC=$?

echo
echo "=== RISULTATO PROVISIONING ==="
echo "Exit code: $RC"

# Provisioning completato correttamente
if [ "$RC" -eq 0 ]; then

    "$ALERT" OK "FileJumpQuota operativo"

    ALERT_RC=$?

    if [ "$ALERT_RC" -ne 0 ]; then
        echo "ATTENZIONE: impossibile aggiornare lo stato del monitor."
    fi

    exit 0
fi

# Exit 2 = fail-closed dell'app FileJumpQuota
if [ "$RC" -eq 2 ]; then

    "$ALERT" ERROR \
        "FileJumpQuota non disponibile: provisioning eseguito in modalità fail-closed."

    ALERT_RC=$?

    if [ "$ALERT_RC" -ne 0 ]; then
        echo "ATTENZIONE: impossibile inviare/aggiornare l'allarme."
    fi

    exit 2
fi

# Altri errori del provisioning
"$ALERT" ERROR \
    "Errore nel provisioning FileJump. Exit code: $RC"

ALERT_RC=$?

if [ "$ALERT_RC" -ne 0 ]; then
    echo "ATTENZIONE: impossibile inviare/aggiornare l'allarme."
fi

exit "$RC"
