# Funzioni di comodo del laboratorio 04 (caricare con: source ~/mongo-lab/04-crud/funzioni-crud.sh)
# Usano il cluster della guida 03 (router con TLS) e l'utente applicativo appuser, con permessi solo su labdb.

# Shell interattiva sul router, come appuser, nel database labdb
app_shell() {
  sudo docker exec -it -e P="$(sudo cat ~/mongo-lab/03-sharding/appuser_password.txt)" mongo-router \
    sh -c 'mongosh labdb --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 27200 -u appuser -p "$P" --authenticationDatabase labdb'
}

# Esegue JavaScript come appuser: app_eval 'js'
app_eval() {
  sudo docker exec -i -e P="$(sudo cat ~/mongo-lab/03-sharding/appuser_password.txt)" mongo-router \
    sh -c 'mongosh labdb --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 27200 -u appuser -p "$P" --authenticationDatabase labdb --quiet --eval "$0"' "$1"
}

# mongoexport come appuser; il risultato esce sullo standard output: app_export --collection=prodotti > prodotti.json
app_export() {
  sudo cat ~/mongo-lab/03-sharding/appuser_password.txt | sudo docker exec -i mongo-router sh -c '
    umask 077
    read -r P
    f=$(mktemp)
    printf "uri: mongodb://appuser:%s@localhost:27200/labdb?authSource=labdb\n" "$P" > "$f"
    mongoexport --config="$f" --ssl --sslCAFile=/etc/mongo/tls/ca.pem "$@"
    status=$?
    rm -f "$f"
    exit $status' sh "$@"
}

# mongoimport come appuser; i dati arrivano dallo standard input: app_import --collection=x --type=csv --headerline < file.csv
app_import() {
  { sudo cat ~/mongo-lab/03-sharding/appuser_password.txt; cat; } | sudo docker exec -i mongo-router sh -c '
    umask 077
    read -r P
    f=$(mktemp)
    printf "uri: mongodb://appuser:%s@localhost:27200/labdb?authSource=labdb\n" "$P" > "$f"
    mongoimport --config="$f" --ssl --sslCAFile=/etc/mongo/tls/ca.pem "$@"
    status=$?
    rm -f "$f"
    exit $status' sh "$@"
}
