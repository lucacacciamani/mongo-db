#!/bin/bash
# Backup del replica set rs0 (guida 02): da un secondario, con oplog e TLS
set -euo pipefail
umask 077

# Da impostare:
LAB="/home/<utente>/mongo-lab/02-replica-set"
FQDN="<FQDN>"
case "$LAB$FQDN" in *"<"*) echo "ERRORE: impostare LAB e FQDN in testa allo script" >&2; exit 1;; esac
DEST=/var/backups/mongo-lab-rs
KEEP_DAILY=7      # giorni
KEEP_WEEKLY=4     # settimane
KEEP_MONTHLY=12   # mesi

mkdir -p "$DEST/daily" "$DEST/weekly" "$DEST/monthly"
FILE="$DEST/daily/mongo-rs-$(date +%Y%m%d-%H%M%S).archive.gz"

# Primo nodo in esecuzione, in cui lanciare mongodump
NODE=""
for c in mongo-rs1 mongo-rs2 mongo-rs3; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then NODE=$c; break; fi
done
[ -n "$NODE" ] || { echo "ERRORE: nessun nodo del replica set in esecuzione" >&2; exit 1; }

URI_TPL="mongodb://admin:%s@$FQDN:27101,$FQDN:27102,$FQDN:27103/?replicaSet=rs0&authSource=admin&readPreference=secondaryPreferred"

cat "$LAB/root_password.txt" | docker exec -i -e URI_TPL="$URI_TPL" "$NODE" sh -c '
  umask 077
  read -r PWD_RS
  printf "uri: $URI_TPL\n" "$PWD_RS" > /tmp/dump.yaml
  mongodump --config=/tmp/dump.yaml --ssl --sslCAFile=/etc/mongo/tls/ca.pem --oplog --archive --gzip --quiet
  status=$?
  rm -f /tmp/dump.yaml
  exit $status
' > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"

[ "$(date +%u)" = "7" ]  && ln -f "$FILE" "$DEST/weekly/"
[ "$(date +%d)" = "01" ] && ln -f "$FILE" "$DEST/monthly/"

find "$DEST/daily"   -name 'mongo-rs-*.archive.gz' -mtime +$((KEEP_DAILY - 1))        -delete
find "$DEST/weekly"  -name 'mongo-rs-*.archive.gz' -mtime +$((KEEP_WEEKLY * 7 - 1))  -delete
find "$DEST/monthly" -name 'mongo-rs-*.archive.gz' -mtime +$((KEEP_MONTHLY * 31 - 1)) -delete

echo "Backup completato ($NODE): $FILE ($(du -h "$FILE" | cut -f1))"
