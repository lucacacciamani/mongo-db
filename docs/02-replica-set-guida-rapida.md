# Replica set MongoDB in Docker — Guida rapida

Replica set di 3 nodi in container sulla stessa VM (laboratorio), nomi DNS per l'accesso esterno, TLS attivato a rotazione, utente applicativo, backup con oplog, manutenzione a rotazione. Presuppone le guide 00 e 01 (CA in `~/mongodb/tls`). Motivazioni e scenario di produzione: `02-replica-set-guida-completa.md`.

**Stato di verifica:** tutto collaudato su installazione reale, tranne 🧪 (rollback TLS, cambio password, smantellamento, retention settimanale/mensile nel tempo).

**Segnaposto:** `<FQDN>` (etichetta DNS dell'IP pubblico, `nome.<regione>.cloudapp.azure.com`), `<IP_PRIVATO_VM>`.

> ⚠️ Due progetti Compose sulla VM (`~/mongodb` e `~/mongo-lab/02-replica-set`): **controllare il prompt** prima di ogni `docker compose`, soprattutto `down -v`.

| Container | Porta (dentro = fuori) | Membro |
|---|---|---|
| `mongo-rs1` | 27101 | `<FQDN>:27101` (`priority: 2`) |
| `mongo-rs2` | 27102 | `<FQDN>:27102` |
| `mongo-rs3` | 27103 | `<FQDN>:27103` |

> 📖 **Comandi e simboli** (`sudo`, `chmod`, `|`, `<< EOF`, `docker compose`…): la [legenda dei comandi](legenda-comandi-linux.md) spiega tutto ciò che compare in questa guida.

---

## 1. Preparazione

- Risorse: ~2–3 GB RAM liberi (`free -h`); senza swap, limitare la memoria dei nodi.
- Portale Azure → IP pubblico → Configurazione → **Etichetta nome DNS**. Verifica dal PC: `Resolve-DnsName <FQDN>`.
- Variabili di sessione (da reimpostare a ogni nuova sessione):

```bash
FQDN=<FQDN>; PRIV_IP=<IP_PRIVATO_VM>; echo "$FQDN $PRIV_IP"
```

## 2. Cartella, password, keyFile

```bash
mkdir -p ~/mongo-lab/02-replica-set && cd ~/mongo-lab/02-replica-set
openssl rand -base64 24 | tr -d '/+=' | sudo tee root_password.txt > /dev/null
sudo chown 999:999 root_password.txt && sudo chmod 600 root_password.txt
openssl rand -base64 756 > keyfile
sudo chown 999:999 keyfile && sudo chmod 400 keyfile      # 400 obbligatorio
```

## 3. docker-compose.yml

In due parti (i blocchi lunghi possono rovinarsi all'incolla); `<< EOF` senza apici per espandere le variabili. Versione con segnaposto in `config/02-replica-set/docker-compose.yml` (senza TLS) e `docker-compose-tls.yml` (finale).

```bash
cat > docker-compose.yml << EOF
name: mongo-lab-rs

x-mongo-common: &mongo-common
  image: mongo:8.0
  restart: unless-stopped
  stop_grace_period: 1m
  extra_hosts:
    - "$FQDN:$PRIV_IP"
  mem_limit: 1g
  ulimits:
    nofile:
      soft: 64000
      hard: 64000
  logging:
    driver: json-file
    options:
      max-size: "20m"
      max-file: "3"

services:
  mongo-rs1:
    <<: *mongo-common
    container_name: mongo-rs1
    hostname: mongo-rs1
    command: ["--replSet", "rs0", "--port", "27101", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25"]
    ports:
      - "127.0.0.1:27101:27101"
      - "$PRIV_IP:27101:27101"
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD_FILE: /run/secrets/rs_root_password
    secrets:
      - rs_root_password
    volumes:
      - rs1-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro
EOF
```

```bash
cat >> docker-compose.yml << EOF

  mongo-rs2:
    <<: *mongo-common
    container_name: mongo-rs2
    hostname: mongo-rs2
    command: ["--replSet", "rs0", "--port", "27102", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25"]
    ports:
      - "127.0.0.1:27102:27102"
      - "$PRIV_IP:27102:27102"
    volumes:
      - rs2-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-rs3:
    <<: *mongo-common
    container_name: mongo-rs3
    hostname: mongo-rs3
    command: ["--replSet", "rs0", "--port", "27103", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25"]
    ports:
      - "127.0.0.1:27103:27103"
      - "$PRIV_IP:27103:27103"
    volumes:
      - rs3-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

volumes:
  rs1-data:
  rs2-data:
  rs3-data:

secrets:
  rs_root_password:
    file: ./root_password.txt
EOF
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose config --services; sudo docker compose config --volumes   # 3 + 3
```

Punti chiave:
- porta uguale dentro e fuori: i client usano gli indirizzi registrati nel replica set;
- `extra_hosts`: nei container `<FQDN>` → IP privato (i nodi si parlano dentro la VM); dal PC `<FQDN>` → IP pubblico → NSG → IP privato;
- admin solo sul nodo 1: gli altri lo ricevono per replica (il secret esiste solo nel nodo 1);
- cache 256 MB + `mem_limit` per convivere con l'istanza di sviluppo;
- `stop_grace_period: 1m`: senza, Docker termina il primario dopo 10 s durante il *quiesce* (~15 s) → `clean shutdown: false`.

## 4. Avvio e `rs.initiate`

```bash
sudo docker compose up -d && sleep 15
sudo docker compose logs mongo-rs1 | grep -c "init process complete"    # 1
# nodi 2-3: "Did not find local replica set configuration document" = normale

sudo docker exec -it mongo-rs1 mongosh --port 27101 -u admin -p --authenticationDatabase admin --quiet --eval "
rs.initiate({ _id: 'rs0', members: [
  { _id: 0, host: '$FQDN:27101', priority: 2 },
  { _id: 1, host: '$FQDN:27102' },
  { _id: 2, host: '$FQDN:27103' } ] })"
```

Funzione di laboratorio (non per produzione: password visibile ai processi del container); `rs_eval 'js' [nodo]`:

```bash
rs_eval() {
  local node=${2:-1}
  sudo docker exec -i -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs$node \
    sh -c 'mongosh --port 2710'"$node"' -u admin -p "$RS_PWD" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr, m.health))'
```

## 5. Uso e failover

```bash
# Scrittura via stringa del replica set (il driver trova il primario)
sudo docker exec -i -e FQDN="$FQDN" -e RS_PWD="$(sudo cat root_password.txt)" mongo-rs1 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/labdb?replicaSet=rs0&authSource=admin" --quiet \
    --eval "print(db.hello().primary); printjson(db.prova.insertOne({ msg: \"ciao\" }))"'
rs_eval 'db.getMongo().setReadPref("secondary"); printjson(db.getSiblingDB("labdb").prova.find().toArray())' 3
rs_eval 'db.getSiblingDB("labdb").prova.insertOne({ x: 1 })' 3                 # not primary

# Failover
sudo docker compose stop mongo-rs1                                              # ~16 s
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2         # nuovo PRIMARY
sudo docker compose start mongo-rs1                                             # rientra SECONDARY, poi PRIMARY (priority 2)
sudo docker compose logs mongo-rs1 | grep -o '"Startup from clean shutdown?":[a-z]*' | tail -1   # true
```

Write concern predefinito `majority`: `acknowledged: true` = dato su ≥ 2 nodi. Guasto improvviso: elezione dopo ~10 s senza heartbeat.

## 6. Accesso dal PC

Con i membri registrati con `<FQDN>`, basta aprire le porte (l'IP pubblico da solo non basta: il client usa poi i nomi dei membri). Alternative scartate: `directConnection=true` (niente failover), file `hosts` sui client, membri registrati con IP pubblico.

- NSG: TCP `27101-27103`, origine solo il proprio IP (traffico in chiaro fino al §7).
- Verifica: `27101..27103 | % { Test-NetConnection <FQDN> -Port $_ | Select RemotePort, TcpTestSucceeded }`.
- VS Code: `mongodb://admin:PWD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/?replicaSet=rs0&authSource=admin`.
- La stringa va nel client, non in bash (il `&` la manda in background; togliere dalla cronologia con `history -d`).

## 7. TLS a rotazione

**Certificato** (CA della guida 01; EKU **clientAuth** indispensabile: i nodi si collegano tra loro come client):

```bash
cd ~/mongo-lab/02-replica-set && mkdir -p tls && chmod 700 tls && cd tls
cat > server.ext << EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=DNS:$FQDN,DNS:localhost,DNS:mongo-rs1,DNS:mongo-rs2,DNS:mongo-rs3,IP:127.0.0.1,IP:$PRIV_IP
EOF
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=$FQDN" -out server.csr
openssl x509 -req -in server.csr -CA ~/mongodb/tls/ca.pem -CAkey ~/mongodb/tls/ca.key \
  -CAserial ~/mongodb/tls/ca.srl -days 825 -sha256 -extfile server.ext -out server.crt
rm server.csr && cp ~/mongodb/tls/ca.pem . && openssl verify -CAfile ca.pem server.crt
cat server.crt server.key | sudo tee server.pem > /dev/null
sudo chown 999:999 server.pem && sudo chmod 600 server.pem && chmod 600 server.key && cd ..
```

**Fase 1 — `allowTLS`** (compose + ricreazione a rotazione):

```bash
cp docker-compose.yml docker-compose.yml.pre-tls
sed -i 's|"--wiredTigerCacheSizeGB", "0.25"\]|"--wiredTigerCacheSizeGB", "0.25", "--tlsMode", "allowTLS", "--tlsCertificateKeyFile", "/etc/mongo/tls/server.pem", "--tlsCAFile", "/etc/mongo/tls/ca.pem", "--tlsAllowConnectionsWithoutCertificates", "--tlsDisabledProtocols", "TLS1_0,TLS1_1"]|' docker-compose.yml
sed -i 's|^      - ./keyfile:/etc/mongo/keyfile:ro$|&\n      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro\n      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro|' docker-compose.yml
grep -c allowTLS docker-compose.yml; grep -c "server.pem:ro" docker-compose.yml   # 3 e 3
```

Rotazione, **un comando alla volta**: `up -d mongo-rs3` → attendi `SECONDARY` → `up -d mongo-rs2` → attendi → `rs_eval 'rs.stepDown(60)'` → verifica → `up -d mongo-rs1`. Controlli: `getParameter tlsMode` = `allowTLS` ×3; `openssl s_client -connect 127.0.0.1:27101 -CAfile tls/ca.pem` → `Verify return code: 0 (ok)`.

**Fase 2 — `preferTLS`** (a caldo; si perde al riavvio):

```bash
for n in 1 2 3; do rs_eval 'printjson(db.adminCommand({ setParameter: 1, tlsMode: "preferTLS" }).was)' $n; done
rs_eval 'rs.stepDown(30)'; sleep 45
for n in 1 2 3; do rs_eval 'printjson(db.serverStatus().transportSecurity)' $n; done    # '1.3' > 0
```

Spostare i client: `rs_eval` con `--tls --tlsCAFile /etc/mongo/tls/ca.pem`; VS Code con `&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem`. I client in chiaro funzionano ancora in questa fase.

**Fase 3 — `requireTLS`** (a caldo, poi permanente):

```bash
for n in 1 2 3; do rs_eval 'printjson(db.adminCommand({ setParameter: 1, tlsMode: "requireTLS" }).was)' $n; done
sudo docker exec mongo-rs2 mongosh --port 27102 --quiet --eval 'db.runCommand({ping:1})'   # deve fallire
cp docker-compose.yml docker-compose.yml.allowtls
sed -i 's|"--tlsMode", "allowTLS"|"--tlsMode", "requireTLS"|' docker-compose.yml
```

Poi stessa rotazione della fase 1. Verifica: `requireTLS` ×3 dopo i riavvii. Rollback 🧪: `docker-compose.yml.pre-tls` + rotazione.

## 8. Utente applicativo

Creato via stringa del replica set (arriva al primario):

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee appuser_password.txt > /dev/null; sudo chmod 600 appuser_password.txt
sudo docker exec -i -e FQDN="$FQDN" -e RS_PWD="$(sudo cat root_password.txt)" -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-rs1 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/?replicaSet=rs0&authSource=admin&tls=true&tlsCAFile=/etc/mongo/tls/ca.pem" --quiet \
    --eval "db.getSiblingDB(\"labdb\").createUser({ user: \"appuser\", pwd: process.env.APP_PWD, roles: [ { role: \"readWrite\", db: \"labdb\" } ] })"'
```

URI applicazioni: `mongodb://appuser:PWD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/labdb?replicaSet=rs0&authSource=labdb&tls=true&tlsCAFile=<ca.pem>`. La cifratura la impone il server (`requireTLS`); `replicaSet` consigliato; `directConnection=true` = niente failover.

## 9. Backup e ripristino

Differenze rispetto alla guida 00: stringa del replica set con `readPreference=secondaryPreferred`, `--oplog` (copia coerente), TLS, esecuzione nel primo nodo acceso con password via stdin (secret solo sul nodo 1). Script in `config/02-replica-set/mongo-rs-backup.sh` (impostare `LAB` e `FQDN`) → `/usr/local/bin/mongo-rs-backup.sh` (`700`); backup in `/var/backups/mongo-lab-rs` (`700`), retention 7/4/12.

```bash
sudo /usr/local/bin/mongo-rs-backup.sh                     # "Backup completato (mongo-rs1)"
sudo docker compose stop mongo-rs1 && sudo /usr/local/bin/mongo-rs-backup.sh && sudo docker compose start mongo-rs1   # (mongo-rs2)
```

Timer: `config/02-replica-set/mongo-rs-backup.{service,timer}` → `/etc/systemd/system/`, alle **03:00 UTC** (dopo quello di sviluppo, 02:30); `daemon-reload`, `enable --now mongo-rs-backup.timer`.

Ripristino (ultimo giornaliero, via stringa del replica set):

```bash
F=$(sudo ls -t /var/backups/mongo-lab-rs/daily/ | head -1)
{ sudo cat root_password.txt; sudo cat "/var/backups/mongo-lab-rs/daily/$F"; } | sudo docker exec -i -e FQDN="$FQDN" mongo-rs2 sh -c '
  umask 077; read -r PWD_RS
  printf "uri: mongodb://admin:%s@$FQDN:27101,$FQDN:27102,$FQDN:27103/?replicaSet=rs0&authSource=admin\n" "$PWD_RS" > /tmp/restore.yaml
  mongorestore --config=/tmp/restore.yaml --ssl --sslCAFile=/etc/mongo/tls/ca.pem --oplogReplay --drop --archive --gzip
  status=$?; rm -f /tmp/restore.yaml; exit $status'
```

`don't know what to do with subdirectory` = innocuo; `applied N oplog entries` può essere > 0 anche senza scritture applicative. Il replica set non è un backup: un `drop` si replica ovunque in un istante.

## 10. Manutenzione a rotazione

Un comando alla volta (ogni riavvio ~16 s; comandi incollati durante un riavvio possono andare persi):

```bash
sudo docker compose restart mongo-rs3        # attendere SECONDARY
sudo docker compose restart mongo-rs2        # attendere SECONDARY
rs_eval 'rs.stepDown(60)'                    # verificare nuovo PRIMARY
sudo docker compose restart mongo-rs1        # dopo ~60 s torna PRIMARY
```

Per cambi di configurazione: `up -d <servizio>`; per aggiornare MongoDB: cambiare il tag dell'immagine e stessa sequenza. Client con stringa del replica set: nessuna interruzione osservata.

## 11. Cambio password 🧪

Sul primario (via stringa del replica set) `db.getSiblingDB("labdb").changeUserPassword("appuser", nuova)`; si replica da solo. Per `admin` aggiornare `root_password.txt` solo dopo il cambio riuscito (lo usa lo script di backup).

## 12. Troubleshooting

| Sintomo | Soluzione |
|---|---|
| Compose incompleto dopo l'incolla (`compose valido` ingannevole) | Due parti o `nano`; verificare `--services`/`--volumes` |
| `rs_eval: command not found` / `$FQDN` vuota | Nuova sessione: ridefinire |
| `container ... is not running` | Interrogare un altro nodo: `rs_eval '...' 2` |
| `not primary` | Scrivere via stringa del replica set / attendere il rientro del nodo 1 |
| Stop ~11 s, `clean shutdown: false` | `stop_grace_period: 1m` |
| Client esterno fallisce dopo il primo contatto | Nomi dei membri non risolvibili: FQDN |
| `Test-NetConnection` `False` | NSG 27101–27103, porte su IP privato |
| Replica interrotta dopo il TLS | Certificato senza `clientAuth` |
| Nessun client con password | Manca `--tlsAllowConnectionsWithoutCertificates` |
| `connection ... closed` | Client senza `tls=true` |
| Modalità TLS tornata indietro dopo un riavvio | Cambiata solo a caldo: aggiornare il compose |
| `/run/secrets/...` assente nei nodi 2–3 | Password via stdin |

## 13. Laboratorio vs produzione

| | Laboratorio | Produzione |
|---|---|---|
| Nodi | 3 container, 1 VM | 3 VM, zone diverse |
| Nomi / porte | 1 FQDN, 27101–27103, `extra_hosts` | 1 DNS per nodo, 27017 |
| Rete client | Internet + NSG su un IP | Rete privata |
| Certificati | 1 per tutti, CA privata | 1 per nodo, CA aziendale |
| Auth interna | keyFile | keyFile o x.509 |
| Segreti | File + `rs_eval` | Key Vault |
| Backup | Script locale | Pianificato, copia esterna, secondario nascosto |

Opzioni non collaudate: x.509 per i membri, secondario nascosto, horizons, membri in altra regione con `priority: 0`.

## 14. Smantellamento 🧪

```bash
cd ~/mongo-lab/02-replica-set && pwd && sudo docker compose down -v
sudo systemctl disable --now mongo-rs-backup.timer
sudo rm /etc/systemd/system/mongo-rs-backup.{service,timer} /usr/local/bin/mongo-rs-backup.sh && sudo systemctl daemon-reload
```

Poi: regola NSG `mongo-lab-rs`, etichetta DNS (se non serve), cartelle e backup, connessioni VS Code.
