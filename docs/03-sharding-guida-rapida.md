# Sharding MongoDB in Docker — Guida rapida

Cluster completo su una VM (laboratorio): 3 config server, 2 shard × 3 nodi, 1 router; shard key hashed e a intervalli, bilanciatore, TLS a freddo, utente applicativo, backup notturno via router. Presuppone le guide 00–01 (CA in `~/mongodb/tls`); la 02 è consigliata. Motivazioni e scenario di produzione: `03-sharding-guida-completa.md`.

**Stato di verifica:** collaudato su installazione reale, tranne 🧪 (ripristino degli utenti, retention settimanale/mensile nel tempo).

**Segnaposto:** `<IP_PRIVATO_VM>`, `<FQDN>`, `<tuo-nome>`.

> 📖 Comandi e simboli: [legenda dei comandi](legenda-comandi-linux.md).

> ⚠️ Più progetti Compose sulla VM: controllare il prompt prima di ogni `docker compose`. Le scelte di laboratorio (memoria, chunk da 1 MB, TLS a freddo, certificato unico) **non** vanno copiate in produzione.

| Componente | RS | Container | Porte |
|---|---|---|---|
| Config server | `cfgrs` | `mongo-cfg1..3` | 27201–27203 |
| Shard 1 | `sh1` | `mongo-sh1a..c` | 27211–27213 |
| Shard 2 | `sh2` | `mongo-sh2a..c` | 27221–27223 |
| Router | — | `mongo-router` | 27200 (unica pubblicata) |

---

## 1. Preparazione della VM

```bash
# Spegnere (non eliminare) sviluppo e replica set 02, sospendere i loro backup
cd ~/mongodb && sudo docker compose stop && sudo systemctl disable --now mongo-backup.timer
cd ~/mongo-lab/02-replica-set && sudo docker compose stop && sudo systemctl disable --now mongo-rs-backup.timer

# Swap 4 GB: rete di sicurezza contro l'OOM killer (non RAM in più)
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h; sudo swapon --show          # senza sudo: command not found (/usr/sbin)
```

## 2. Cartella, keyFile, password

```bash
mkdir -p ~/mongo-lab/03-sharding && cd ~/mongo-lab/03-sharding
openssl rand -base64 756 > keyfile && sudo chown 999:999 keyfile && sudo chmod 400 keyfile
openssl rand -base64 24 | tr -d '/+=' | sudo tee root_password.txt > /dev/null && sudo chmod 600 root_password.txt
PRIV_IP=<IP_PRIVATO_VM>
```

## 3. Compose

Resa in quattro parti (A config server, B shard 1, C shard 2, D router + volumi): vedi guida completa, Parte 3.2, o `config/03-sharding/docker-compose.yml`. Punti chiave:

- config server: `--configsvr`, volume su **`/data/configdb`**;
- shard: `--shardsvr`; tutti: `--replSet`, `--port` propria, `--keyFile`, cache 0.25 GB, `mem_limit: 640m`, `stop_grace_period: 1m`;
- router: `mongos --configdb cfgrs/mongo-cfg1:27201,...`, `user: "999:999"`, `mem_limit: 384m`, porte `127.0.0.1` e `$PRIV_IP` sulla 27200;
- membri registrati con i nomi dei container: i client vedono solo il router.

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose config --services | wc -l                          # 10
sudo docker compose config --volumes | wc -l                           # 9
sudo docker compose config | grep -c "target: /etc/mongo/keyfile"      # 10 (verifica ogni servizio)
```

Righe mescolate a schermo durante l'incolla possono essere solo visive: verificare il contenuto, non l'aspetto.

## 4. Avvio e inizializzazione

```bash
sudo docker compose up -d
# Router in attesa ("Could not find host ... for set cfgrs", "Sleeping for 2 seconds"): normale

sudo docker exec mongo-cfg1 mongosh --port 27201 --quiet --eval 'rs.initiate({ _id: "cfgrs", configsvr: true, members: [
  { _id: 0, host: "mongo-cfg1:27201" }, { _id: 1, host: "mongo-cfg2:27202" }, { _id: 2, host: "mongo-cfg3:27203" } ] })'
sudo docker exec mongo-sh1a mongosh --port 27211 --quiet --eval 'rs.initiate({ _id: "sh1", members: [
  { _id: 0, host: "mongo-sh1a:27211" }, { _id: 1, host: "mongo-sh1b:27212" }, { _id: 2, host: "mongo-sh1c:27213" } ] })'
sudo docker exec mongo-sh2a mongosh --port 27221 --quiet --eval 'rs.initiate({ _id: "sh2", members: [
  { _id: 0, host: "mongo-sh2a:27221" }, { _id: 1, host: "mongo-sh2b:27222" }, { _id: 2, host: "mongo-sh2c:27223" } ] })'
```

(Localhost exception: nessuna password finché non esistono utenti.)

## 5. Utenti e funzioni

```bash
# Admin locali degli shard (sui primari): solo manutenzione diretta
for c in "mongo-sh1a 27211" "mongo-sh2a 27221"; do set -- $c
  sudo docker exec -i -e P="$(sudo cat root_password.txt)" $1 \
    sh -c 'mongosh --port '"$2"' --quiet --eval "db.getSiblingDB(\"admin\").createUser({ user: \"admin\", pwd: process.env.P, roles: [\"root\"] })"'
done
# Admin del cluster, via router (salvato nei config server)
sudo docker exec -i -e P="$(sudo cat root_password.txt)" mongo-router \
  sh -c 'mongosh --port 27200 --quiet --eval "db.getSiblingDB(\"admin\").createUser({ user: \"admin\", pwd: process.env.P, roles: [\"root\"] })"'
```

Funzioni `sh_eval 'js'` (router) e `node_eval <container> <porta> 'js'` in `funzioni-lab.sh` (copia in `config/03-sharding/`), da caricare con `source funzioni-lab.sh` a ogni sessione, o in automatico con una riga in `~/.bashrc`.

## 6. Shard, chunk, collezioni

```bash
sh_eval 'sh.addShard("sh1/mongo-sh1a:27211,mongo-sh1b:27212,mongo-sh1c:27213"); sh.addShard("sh2/mongo-sh2a:27221,mongo-sh2b:27222,mongo-sh2c:27223")'
sh_eval 'sh.status()'
sh_eval 'db.getSiblingDB("config").settings.updateOne({ _id: "chunksize" }, { $set: { value: 1 } }, { upsert: true })'   # SOLO laboratorio
sh_eval 'sh.enableSharding("labdb"); sh.shardCollection("labdb.ordini", { clienteId: "hashed" }); sh.shardCollection("labdb.eventi", { ts: 1 })'
```

Caricamento dati di prova e query: guida completa, Parti 8–10. Risultati del collaudo:

| | `ordini` (hashed) | `eventi` (intervalli, `ts` crescente) |
|---|---|---|
| Distribuzione | 50,5 % / 49,5 % da subito | Tutto su uno shard, poi 5 migrazioni da ~1 MB |
| Nuove scritture | Distribuite | Sempre sull'ultimo chunk (shard caldo) |
| Uguaglianza sulla chiave | `SINGLE_SHARD` | `SINGLE_SHARD` |
| Intervallo sulla chiave | `SHARD_MERGE` (2 shard) | `SINGLE_SHARD` |
| Query senza chiave | `SHARD_MERGE` | `SHARD_MERGE` |

- Chunk = intervallo assegnato a uno shard; nessuna divisione automatica, gli intervalli contigui dello stesso shard si riuniscono da soli.
- **Documenti orfani:** dopo una migrazione lo shard di origine li cancella dopo `orphanCleanupDelaySecs` (900 s); nel frattempo `getShardDistribution` li conta (142.275 su 100.000), il router no. Verifica: `config.rangeDeletions` sullo shard di origine.
- Bilanciatore: si ferma sotto ~3 × chunk size di differenza; in produzione finestra oraria.
- Memoria misurata: 1,2 GB a riposo, 2,5 GB dopo 300.000 documenti, swap 0.

## 7. TLS a freddo

Certificato unico (CA della guida 01), EKU `serverAuth,clientAuth`, SAN con i 10 nomi dei container, `localhost`, `127.0.0.1`, `<FQDN>`, `<IP_PRIVATO_VM>` (esempio: `config/03-sharding/server.ext.example`; comandi: guida completa, Parte 13.1).

```bash
cp docker-compose.yml docker-compose.yml.pre-tls
sed -i 's|"--bind_ip_all"\]|"--bind_ip_all", "--tlsMode", "requireTLS", "--tlsCertificateKeyFile", "/etc/mongo/tls/server.pem", "--tlsCAFile", "/etc/mongo/tls/ca.pem", "--tlsAllowConnectionsWithoutCertificates", "--tlsDisabledProtocols", "TLS1_0,TLS1_1"]|' docker-compose.yml
sed -i 's|^      - ./keyfile:/etc/mongo/keyfile:ro$|&\n      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro\n      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro|' docker-compose.yml
grep -c requireTLS docker-compose.yml; grep -c "server.pem:ro" docker-compose.yml     # 10 e 10
sed -i 's|mongosh --port |mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port |' funzioni-lab.sh && source funzioni-lab.sh
sudo docker compose up -d        # ricrea tutto (~45 s)
```

Verifiche: `requireTLS` su router e shard; `transportSecurity` `'1.3'` > 0; `openssl s_client -connect 127.0.0.1:27200 -CAfile tls/ca.pem` → `0 (ok)`; `mongosh` senza TLS → `connection ... closed`. Il TLS cifra il **transito**, non i dati su disco (cifratura dei dischi Azure).

In produzione: a caldo, come nella guida 02, un certificato per server.

## 8. Accesso dal PC e utente applicativo

NSG: TCP 27200 solo dal proprio IP. VS Code (niente `replicaSet=`):

```
mongodb://admin:PWD@<FQDN>:27200/?authSource=admin&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee appuser_password.txt > /dev/null && sudo chmod 600 appuser_password.txt
sudo docker exec -i -e P="$(sudo cat root_password.txt)" -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-router \
  sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 27200 -u admin -p "$P" --authenticationDatabase admin --quiet \
    --eval "db.getSiblingDB(\"labdb\").createUser({ user: \"appuser\", pwd: process.env.APP_PWD, roles: [ { role: \"readWrite\", db: \"labdb\" } ] })"'
```

URI: `mongodb://appuser:PWD@<FQDN>:27200/labdb?authSource=labdb&tls=true&tlsCAFile=...`. Verificato: `config` → `Unauthorized`; 0 utenti sugli shard (vivono nei config server).

## 9. Backup notturno

`config/03-sharding/mongo-sh-backup.sh` (impostare `LAB`) → `/usr/local/bin/mongo-sh-backup.sh` (`700`); backup in `/var/backups/mongo-lab-sh` (`700`), retention 7/4/12; timer `mongo-sh-backup.{service,timer}` alle **03:30 UTC**.

- Ferma il bilanciatore e lo **riattiva sempre** (`trap ... EXIT`, anche in caso di errore); elimina il file incompleto.
- Password via stdin, anche per `mongosh` (variabile d'ambiente, non argomenti).
- `mongodump` via router con TLS e `--dumpDbUsersAndRoles`; file scritto sull'host con `umask 077` (→ `-rw-------`).

```bash
sudo /usr/local/bin/mongo-sh-backup.sh && sh_eval 'print(sh.getBalancerState())'     # true
```

Ripristino di prova in `labdb_ripristino` con `--nsFrom/--nsTo` (guida completa, Parte 16.5): 300.001 documenti in ~11 s, ma **collezioni non distribuite** (indici della shard key ripristinati: ridistribuibili). Utenti: solo con `--restoreDbUsersAndRoles` nello stesso database 🧪.

Limiti: niente `--oplog` via router → non coerente a un istante con scritture in corso. Produzione: snapshot coordinati o servizio gestito.

## 10. Operatività

- Ripartenza dopo stop completo: router operativo in ~30 s, dati intatti.
- Tornare a sviluppo/replica set 02: `stop` del cluster e del suo timer, `start` delle altre istanze e `enable --now` dei loro timer (collaudato).
- Rimuovere lo swap: `sudo swapoff /swapfile`, `sudo sed -i '\|^/swapfile none swap sw 0 0$|d' /etc/fstab`, `sudo rm /swapfile` (collaudato).
- Smantellamento: `down -v` **nella cartella giusta**, rimozione timer/script, riga in `~/.bashrc`, NSG.

## 11. Troubleshooting

| Sintomo | Soluzione |
|---|---|
| `swapon: command not found` | `sudo` |
| `sh_eval: command not found` | `source funzioni-lab.sh` |
| Totali per shard > documenti reali | Orfani: attendere ~15 min, il router li filtra |
| Un chunk per shard con chunksize 1 MB | Normale: niente divisione automatica |
| Scritture su un solo shard | Chiave crescente a intervalli: hashed o composta |
| Errori TLS tra i processi | `clientAuth` e tutti i nomi dei container nel SAN |
| VS Code senza database | Refresh / riconnessione |
| Bilanciatore fermo dopo un backup | `sh_eval 'sh.startBalancer()'` (lo script lo fa da sé) |

## 12. Laboratorio vs produzione

| | Laboratorio | Produzione |
|---|---|---|
| Server | 10 container, 1 VM | ~10 VM in zone diverse, router sugli app server |
| Memoria | Cache 256 MB, limiti, swap 4 GB | RAM sul working set, swap minimo |
| Chunk size | 1 MB | 128 MB (predefinito) |
| TLS | A freddo, certificato unico | A rotazione, certificato per server |
| Backup | Logico via router, notturno | Snapshot coordinati / servizio gestito |
| Router | 1 | ≥ 2 |
