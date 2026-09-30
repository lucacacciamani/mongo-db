#!/bin/bash
# Backup del cluster con sharding (guida 03): bilanciatore fermo, backup logico via router, TLS
set -euo pipefail
umask 077

# Da impostare:
LAB="/home/<utente>/mongo-lab/03-sharding"
case "$LAB" in *"<"*) echo "ERRORE: impostare LAB in testa allo script" >&2; exit 1;; esac
DB=labdb
DEST=/var/backups/mongo-lab-sh
KEEP_DAILY=7      # giorni
KEEP_WEEKLY=4     # settimane
KEEP_MONTHLY=12   # mesi

# Esegue JavaScript sul router come admin; la password arriva dallo standard input
mongo_admin() {
  cat "$LAB/root_password.txt" | docker exec -i mongo-router sh -c '
    read -r P; export P
    mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 27200 --quiet \
      --eval "db.getSiblingDB(\"admin\").auth(\"admin\", process.env.P); $0"' "$1"
}

mkdir -p "$DEST/daily" "$DEST/weekly" "$DEST/monthly"
FILE="$DEST/daily/$DB-$(date +%Y%m%d-%H%M%S).archive.gz"

# 1. Ferma il bilanciatore; qualunque cosa succeda dopo, all'uscita viene riattivato
mongo_admin 'sh.stopBalancer(); if (sh.getBalancerState()) { quit(1) }' > /dev/null
trap 'rm -f "$FILE.tmp"; mongo_admin "sh.startBalancer()" > /dev/null || echo "ATTENZIONE: riattivare il bilanciatore a mano" >&2' EXIT

# 2. Backup logico attraverso il router, con gli utenti del database
cat "$LAB/root_password.txt" | docker exec -i mongo-router sh -c '
  umask 077
  read -r P
  printf "uri: mongodb://admin:%s@localhost:27200/?authSource=admin\n" "$P" > /tmp/dump.yaml
  mongodump --config=/tmp/dump.yaml --ssl --sslCAFile=/etc/mongo/tls/ca.pem \
    --db '"$DB"' --dumpDbUsersAndRoles --archive --gzip --quiet
  status=$?
  rm -f /tmp/dump.yaml
  exit $status' > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"

# 3. Copie settimanali e mensili, pulizia
[ "$(date +%u)" = "7" ]  && ln -f "$FILE" "$DEST/weekly/"
[ "$(date +%d)" = "01" ] && ln -f "$FILE" "$DEST/monthly/"
find "$DEST/daily"   -name "$DB-*.archive.gz" -mtime +$((KEEP_DAILY - 1))        -delete
find "$DEST/weekly"  -name "$DB-*.archive.gz" -mtime +$((KEEP_WEEKLY * 7 - 1))  -delete
find "$DEST/monthly" -name "$DB-*.archive.gz" -mtime +$((KEEP_MONTHLY * 31 - 1)) -delete

echo "Backup completato: $FILE ($(du -h "$FILE" | cut -f1))"
