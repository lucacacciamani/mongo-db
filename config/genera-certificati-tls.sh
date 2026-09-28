#!/bin/bash
# Genera (o rinnova) il certificato TLS del server MongoDB, firmato da una CA privata.
# Vedi docs/01-tls-guida-completa.md
#
# Uso (dalla cartella dei certificati, es. ~/mongodb/tls):
#   ./genera-certificati-tls.sh <IP_PUBBLICO> <IP_PRIVATO> [nome.dns.aggiuntivo]
#
# - Se ca.pem e ca.key non esistono, crea una nuova CA (valida 10 anni).
# - Se ca.pem esiste, riusa la CA: serve ca.key (e ca.srl) nella cartella.
# - Genera sempre un nuovo certificato del server (valido 825 giorni).
#
# STATO: provato in ambiente di test (creazione CA e rinnovo), non ancora
# collaudato su una VM con MongoDB in esecuzione.
set -euo pipefail
umask 077

PUB_IP=${1:?"Uso: $0 <IP_PUBBLICO> <IP_PRIVATO> [dns-aggiuntivo]"}
PRIV_IP=${2:?"Uso: $0 <IP_PUBBLICO> <IP_PRIVATO> [dns-aggiuntivo]"}
EXTRA_DNS=${3:-}
CA_DAYS=3650
SERVER_DAYS=825

# --- CA ---------------------------------------------------------------
if [ ! -f ca.pem ]; then
  echo ">> Creazione di una nuova CA"
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -key ca.key -sha256 -days "$CA_DAYS" -subj "/CN=MongoDB Dev CA" -out ca.pem
elif [ ! -f ca.key ]; then
  echo "ERRORE: ca.pem esiste ma ca.key no. Copia ca.key (e ca.srl) in questa cartella per firmare." >&2
  exit 1
else
  echo ">> Uso della CA esistente"
fi

# --- SAN --------------------------------------------------------------
SAN="DNS:localhost,DNS:mongo,IP:127.0.0.1,IP:$PRIV_IP,IP:$PUB_IP"
[ -n "$EXTRA_DNS" ] && SAN="$SAN,DNS:$EXTRA_DNS"
cat > server.ext << EXT
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=$SAN
EXT

# --- Certificato del server ------------------------------------------
echo ">> Generazione del certificato del server"
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=$(hostname)" -out server.csr
if [ -f ca.srl ]; then SERIAL=(-CAserial ca.srl); else SERIAL=(-CAcreateserial); fi
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key "${SERIAL[@]}" \
  -days "$SERVER_DAYS" -sha256 -extfile server.ext -out server.crt
rm -f server.csr
openssl verify -CAfile ca.pem server.crt

# --- File per MongoDB e permessi ---------------------------------------
cat server.crt server.key | sudo tee server.pem > /dev/null
sudo chown 999:999 server.pem
sudo chmod 600 server.pem
chmod 600 ca.key server.key
chmod 644 ca.pem server.crt server.ext

echo
openssl x509 -in server.crt -noout -ext subjectAltName -enddate
echo
echo "Fatto. Prossimi passi:"
echo "  1. cd ~/mongodb && sudo docker compose restart   (o 'up -d' alla prima attivazione)"
echo "  2. Verifica: openssl s_client -connect 127.0.0.1:27017 -CAfile $(pwd)/ca.pem </dev/null 2>/dev/null | grep 'Verify return code'"
echo "  3. Metti al sicuro ca.key e ca.srl fuori dalla VM, poi: shred -u ca.key"
