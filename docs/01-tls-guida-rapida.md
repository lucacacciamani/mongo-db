# TLS per MongoDB in Docker — Guida rapida

Cifratura delle connessioni a MongoDB con una CA privata: traffico cifrato e verifica del server, rinnovi trasparenti per i client. Presuppone il setup della guida `00-guida-rapida.md`.

**Segnaposto:** `<IP_PUBBLICO_VM>`, `<IP_PRIVATO_VM>` (es. `10.0.0.4`). Utente VM d'esempio: `azureuser`.
**Stato di verifica:** §1–6 collaudati su installazione reale; rinnovo (§7) e rollback (§9) non ancora collaudati (🧪).
**Alternativa:** per un singolo sviluppatore il tunnel SSH offre la stessa sicurezza senza certificati (guida 00, §9.1).

---

## 1. Preparazione

```bash
sudo /usr/local/bin/mongo-backup.sh
cd ~/mongodb && cp docker-compose.yml docker-compose.yml.pre-tls   # per il rollback (§9)
mkdir -p ~/mongodb/tls && chmod 700 ~/mongodb/tls && cd ~/mongodb/tls
```

L'IP pubblico deve essere **statico** (portale Azure → IP pubblico → Configurazione), altrimenti il certificato smette di valere quando cambia.

## 2. CA e certificato del server

Automatizzabile con `config/01-tls/genera-certificati-tls.sh <IP_PUBBLICO> <IP_PRIVATO>`. Passi manuali:

```bash
PUB_IP=<IP_PUBBLICO_VM>
PRIV_IP=<IP_PRIVATO_VM>

# CA privata, 10 anni
openssl genrsa -out ca.key 4096
openssl req -x509 -new -key ca.key -sha256 -days 3650 -subj "/CN=MongoDB Dev CA" -out ca.pem

# SAN: tutti gli indirizzi usati dai client (heredoc senza apici: espande le variabili)
cat > server.ext << EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:mongo,IP:127.0.0.1,IP:$PRIV_IP,IP:$PUB_IP
EOF

# Certificato server, 825 giorni
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=mongo-vm" -out server.csr
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 825 -sha256 -extfile server.ext -out server.crt
rm server.csr

openssl verify -CAfile ca.pem server.crt                                  # server.crt: OK
openssl x509 -in server.crt -noout -ext subjectAltName -enddate

# File unico per MongoDB, leggibile dall'UID 999
cat server.crt server.key | sudo tee server.pem > /dev/null
sudo chown 999:999 server.pem && sudo chmod 600 server.pem
chmod 600 ca.key server.key && chmod 644 ca.pem server.crt
```

| File | Segreto | Destinazione |
|---|---|---|
| `ca.key`, `ca.srl` | Sì (critico) | Fuori dalla VM; servono solo per firmare |
| `ca.pem` | No | Client e container |
| `server.key`, `server.pem` | Sì | Solo VM |
| `server.crt`, `server.ext` | No | VM (servono per verifiche e rinnovi) |

**Custodia della CA** — dal PC, in PowerShell (stesso utente e stessa eventuale `-i <chiave>` del comando `ssh`; con accesso a password omettere `-i`):

```powershell
mkdir C:\Users\<tuo-nome>\mongodb-ca -Force            # fuori dal repository Git
scp azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.key C:\Users\<tuo-nome>\mongodb-ca\
scp azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.srl C:\Users\<tuo-nome>\mongodb-ca\
Get-FileHash C:\Users\<tuo-nome>\mongodb-ca\ca.key -Algorithm SHA256   # confrontare con: sha256sum ~/mongodb/tls/ca.key (VM)
```

Poi, a scelta:
- **produzione / consigliato:** `shred -u ~/mongodb/tls/ca.key` sulla VM (la chiave va riportata sulla VM solo per i rinnovi);
- **sviluppo:** tenerla anche sulla VM, verificando `-rw-------` sul file e `drwx------` sulla cartella; non montare mai `./tls` intero nel container; attenzione a snapshot/backup della VM.

`server.pem` risulta del gruppo `systemd-journal`: normale, è il GID 999 dell'host.

## 3. docker-compose.yml con TLS

Heredoc senza apici per espandere `$PRIV_IP`; eliminare quella riga se non serve l'accesso diretto.

```bash
cd ~/mongodb && PRIV_IP=<IP_PRIVATO_VM>
cat > docker-compose.yml << EOF
services:
  mongo:
    image: mongo:8.0
    container_name: mongo
    restart: unless-stopped
    stop_grace_period: 1m
    command:
      - --tlsMode=requireTLS
      - --tlsCertificateKeyFile=/etc/mongo/tls/server.pem
      - --tlsCAFile=/etc/mongo/tls/ca.pem
      - --tlsAllowConnectionsWithoutCertificates
      - --tlsDisabledProtocols=TLS1_0,TLS1_1
    ports:
      - "127.0.0.1:27017:27017"
      - "$PRIV_IP:27017:27017"
    ulimits:
      nofile:
        soft: 64000
        hard: 64000
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD_FILE: /run/secrets/mongo_root_password
    volumes:
      - mongo-data:/data/db
      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro
      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro
    secrets:
      - mongo_root_password

volumes:
  mongo-data:

secrets:
  mongo_root_password:
    file: ./mongo_root_password.txt
EOF
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose up -d
```

- ⚠️ All'`up -d` tutti i client configurati senza TLS (app, Compass, VS Code, script) smettono di collegarsi fino all'aggiornamento (§6).
- `requireTLS`: rifiuta ogni connessione in chiaro (`allowTLS`/`preferTLS` solo per migrazioni graduali).
- `tlsAllowConnectionsWithoutCertificates`: **indispensabile** con `tlsCAFile`, altrimenti MongoDB richiede un certificato client a tutti.
- `tlsDisabledProtocols`: solo TLS 1.2 e 1.3.
- Montati solo i due file necessari, in sola lettura.

## 4. Verifica

```bash
sudo docker compose ps                                              # Up, non Restarting
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'
openssl s_client -connect 127.0.0.1:27017 -CAfile tls/ca.pem </dev/null 2>/dev/null | grep -E "Verify return code|Protocol"   # 0 (ok)

sudo docker exec -it mongo mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem -u admin -p --authenticationDatabase admin
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin --eval 'db.runCommand({ping:1})'   # deve FALLIRE
```

Uscire da `mongosh` (`exit`) prima di lanciare il comando successivo: dentro il prompt `test>` un comando shell dà `SyntaxError: Missing semicolon`.

## 5. Backup e ripristino

Lo script di backup va aggiornato, altrimenti con `requireTLS` i dump falliscono. La versione `config/01-tls/mongo-backup.sh` rileva da sola il TLS (presenza di `/etc/mongo/tls/ca.pem` nel container), quindi funziona anche dopo un rollback; rispetto a `config/00-base/mongo-backup.sh` cambia solo il blocco `docker exec`:

```bash
  TLS=""
  [ -f /etc/mongo/tls/ca.pem ] && TLS="--ssl --sslCAFile=/etc/mongo/tls/ca.pem"
  mongodump $TLS --config=/tmp/dump.yaml -u admin --authenticationDatabase admin --archive --gzip --quiet
```

Installare lo script **intero** (`config/01-tls/mongo-backup.sh`, oppure il blocco da `sudo tee` a `sudo chmod` della guida completa, Parte 8.1): le tre righe sopra eseguite da sole danno `mongodump: command not found`.

```bash
sudo grep -n "TLS" /usr/local/bin/mongo-backup.sh     # 3 righe attese
sudo /usr/local/bin/mongo-backup.sh
sudo systemctl start mongo-backup.service && sudo journalctl -u mongo-backup.service -n 5 --no-pager
sudo sh -c 'rm -f /var/backups/mongodb/mongo-*.archive.gz'   # vecchi dump fuori da daily/weekly/monthly, se presenti
```

**Ripristino con TLS:**

```bash
sudo sh -c 'f=$(ls -t /var/backups/mongodb/daily/mongo-*.archive.gz | head -1); echo "Ripristino: $f"; \
  docker exec -i mongo sh -c "mongorestore --ssl --sslCAFile=/etc/mongo/tls/ca.pem -u admin -p \"\$(cat /run/secrets/mongo_root_password)\" --authenticationDatabase admin --archive --gzip --drop" < "$f"'
```

Nei comandi `mongosh` della guida 00 aggiungere `--tls --tlsCAFile /etc/mongo/tls/ca.pem`.

## 6. Client

Copia di `ca.pem` sul PC (passo distinto dalla custodia di `ca.key`; preferire un percorso senza spazi):

```powershell
scp azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.pem C:\Users\<tuo-nome>\mongodb-ca\ca.pem
```

Parametri da aggiungere alle URI della guida 00: `&tls=true&tlsCAFile=<percorso ca.pem>`.

| Client | Host nella URI |
|---|---|
| VM / tunnel SSH | `127.0.0.1` |
| Container nello stesso compose (montare `ca.pem`) | `mongo` |
| Accesso diretto | `<IP_PUBBLICO_VM>` o `<IP_PRIVATO_VM>` |

- Percorsi Windows nella URI: `/` invece di `\`, spazi come `%20`; in alternativa passare il file come opzione del driver:

  ```javascript
  new MongoClient(process.env.MONGODB_URI, { tlsCAFile: process.env.MONGODB_CA_FILE });
  ```

- **Compass:** Advanced Connection Options → TLS/SSL → On → Certificate Authority = `ca.pem`.
- **MongoDB for VS Code:** tasto destro sulla connessione → Edit Connection, oppure Ctrl+Shift+P → *MongoDB: Connect with Connection String*:
  `mongodb://appuser:PWD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem`; rimuovere la vecchia connessione senza TLS.
- **Senza file sul client:** il server non lo consente né lo impedisce, decide il client. Alternative al file: installare la CA nell'archivio Windows (*Autorità di certificazione radice attendibili*; funziona con i client che leggono l'archivio di sistema, es. strumenti MongoDB recenti e .NET), oppure `tlsAllowInvalidCertificates=true` (solo cifratura, nessuna verifica: da evitare).
- ⛔ Mai `tlsAllowInvalidCertificates` / `tlsInsecure`: annullano la verifica del server.
- NSG sulla 27017 sempre limitato agli IP autorizzati.

## 7. Rinnovo del certificato server

> 🧪 **Non ancora collaudato** su un'installazione reale (lo script `genera-certificati-tls.sh` è stato provato solo in un ambiente di test). Provare prima in sviluppo, con il rollback (§9) a portata di mano.

```bash
openssl x509 -in ~/mongodb/tls/server.crt -noout -enddate
openssl x509 -in ~/mongodb/tls/server.crt -noout -checkend $((30*86400)) && echo OK || echo "IN SCADENZA"
```

Procedura (i client non cambiano nulla, stessa CA):

```bash
# 1. se ca.key non è sulla VM: riportare ca.key e ca.srl in ~/mongodb/tls (scp dal PC)
cd ~/mongodb/tls && chmod 600 ca.key
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=mongo-vm" -out server.csr
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAserial ca.srl \
  -days 825 -sha256 -extfile server.ext -out server.crt
rm server.csr && openssl verify -CAfile ca.pem server.crt
cat server.crt server.key | sudo tee server.pem > /dev/null
sudo chown 999:999 server.pem && sudo chmod 600 server.pem && chmod 600 server.key
cd ~/mongodb && sudo docker compose restart
# 2. verificare (§4), ricopiare ca.srl sul PC; se la CA non deve restare sulla VM: shred -u ~/mongodb/tls/ca.key
```

In alternativa: `config/01-tls/genera-certificati-tls.sh` (riusa la CA esistente). Alla scadenza della CA (10 anni) serve una nuova CA e la ridistribuzione di `ca.pem`.

## 8. Troubleshooting

| Sintomo | Soluzione |
|---|---|
| Container `Restarting`, permission denied sul certificato | `sudo chown 999:999 tls/server.pem && sudo chmod 600 tls/server.pem` |
| Chiave e certificato non corrispondono | Ricostruire `server.pem` da `server.crt` + `server.key` |
| Client: `connection closed` / `ECONNRESET` | Manca `tls=true` |
| `certificate verify failed` / `unable to get local issuer` | `tlsCAFile` errato o CA diversa |
| `does not match certificate's altnames` / `IP address mismatch` | Indirizzo non nel SAN: usarne uno presente o rinnovare con SAN aggiornato |
| `certificate has expired` | Rinnovo (§7) |
| Server: `No SSL certificate provided by peer` | Aggiungere `--tlsAllowConnectionsWithoutCertificates` |
| Backup notturni falliti | Installare lo script compatibile TLS (§5) |
| `SyntaxError: Missing semicolon` | Comando shell lanciato dentro `mongosh`: `exit` |
| `mongodump: command not found` | Incollate solo alcune righe dello script: reinstallarlo intero |
| Cartella `C:Users...` sulla VM | `mkdir` di PowerShell lanciato sulla VM: `rmdir 'C:Users...'` |
| `scp` chiede la password | Accesso a password: normale; per le chiavi vedi guida 00 §11 |
| `ca.pem` assente sul PC | Copiarlo (§6): è un passo distinto dalla copia di `ca.key` |

Diagnosi: `openssl s_client ... | grep "Verify return code"` → `0 (ok)` = server a posto, problema lato client.

## 9. Rollback

> 🧪 **Non ancora collaudato** su un'installazione reale: provarlo una volta in sviluppo prima di contarci in emergenza.

```bash
cd ~/mongodb
cp docker-compose.yml docker-compose.yml.tls
cp docker-compose.yml.pre-tls docker-compose.yml
sudo docker compose up -d
```

Dati intatti; lo script di backup si adatta da solo. Togliere `tls`/`tlsCAFile` dai client. Per riattivare: `cp docker-compose.yml.tls docker-compose.yml && sudo docker compose up -d`.

## 10. Produzione

- CA aziendale o pubblica (Let's Encrypt con nome DNS e rinnovo automatico): nessun `ca.pem` da distribuire.
- Nomi DNS nel SAN invece di IP.
- Nessuna esposizione su internet: rete privata + TLS.
- Chiave della CA in Key Vault o sistema equivalente; alert sulla scadenza dei certificati.
- Replica set / sharding: TLS anche tra i nodi, con possibile autenticazione x.509 dei membri al posto del keyFile.
