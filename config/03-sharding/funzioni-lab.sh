# Funzioni di comodo del laboratorio 03, versione con TLS (caricare con: source ~/mongo-lab/03-sharding/funzioni-lab.sh)
sh_eval() {
  sudo docker exec -i -e P="$(sudo cat ~/mongo-lab/03-sharding/root_password.txt)" mongo-router \
    sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 27200 -u admin -p "$P" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}
node_eval() {
  sudo docker exec -i -e P="$(sudo cat ~/mongo-lab/03-sharding/root_password.txt)" "$1" \
    sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port '"$2"' -u admin -p "$P" --authenticationDatabase admin --quiet --eval "$0"' "$3"
}
