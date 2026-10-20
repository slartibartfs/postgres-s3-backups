#!/bin/sh
# Taegliche Sicherung der KLEOX-Datenbank in einen S3-Bucket mit Object Lock.
#
# Der Schluessel (IAM kleox-backup-writer) darf nur ablegen - weder auflisten
# noch lesen noch loeschen. Deshalb legt dieses Skript keinen Bucket an und
# prueft auch nicht, ob es ihn gibt: Fehlt er, scheitert put-object, und der
# Lauf endet mit Fehler.
#
# Tagesdumps:   db/taeglich/   Sperre aus der Vorgabe des Buckets (35 Tage)
# Monatsdumps:  db/monatlich/  am 1. des Monats, 400 Tage gesperrt
#
# Konzept: docs/PLAN-BACKUP.md im Repository kleox-konfigurator.

set -o errexit -o nounset

export AWS_PAGER=""

STEMPEL="$(date -u +%Y-%m-%d_%H%M)"
DATEI="/tmp/kleox-${STEMPEL}.dump"

ablegen() {
    # $1 = Schluessel im Bucket; weitere Argumente gehen an put-object
    schluessel="$1"
    shift
    aws s3api put-object --region "$AWS_REGION" --bucket "$S3_BUCKET_NAME" \
        --key "$schluessel" --body "$DATEI" "$@" > /dev/null
    echo "Abgelegt: s3://$S3_BUCKET_NAME/$schluessel"
}

echo "Sichere Datenbank ..."
pg_dump --format=custom --no-owner --no-privileges --file="$DATEI" "$DATABASE_URL"

# Ist die Datei lesbar? Sonst lieber hier abbrechen als eine kaputte
# Sicherung 35 Tage unloeschbar ablegen.
pg_restore --list "$DATEI" > /dev/null
echo "Dump: $(wc -c < "$DATEI") Bytes"

ablegen "db/taeglich/kleox-${STEMPEL}.dump"

# MONATLICH_ERZWINGEN=1 legt zusaetzlich einen Monatsdump ab - fuer den
# ersten Test, damit niemand bis zum Monatsersten warten muss.
if [ "$(date -u +%d)" = "01" ] || [ "${MONATLICH_ERZWINGEN:-}" = "1" ]; then
    BIS="$(date -u -d '+400 days' +%Y-%m-%dT%H:%M:%SZ)"
    ablegen "db/monatlich/kleox-${STEMPEL}.dump" \
        --object-lock-mode COMPLIANCE --object-lock-retain-until-date "$BIS"
fi

rm -f "$DATEI"

# Lebenszeichen an den Waechter - nur wenn alles davor geklappt hat.
if [ -n "${HEALTHCHECK_URL:-}" ]; then
    curl -fsS -m 10 --retry 3 "$HEALTHCHECK_URL" > /dev/null
    echo "Waechter benachrichtigt."
fi

echo "Fertig."
