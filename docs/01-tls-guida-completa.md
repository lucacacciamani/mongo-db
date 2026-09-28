# Cifrare le connessioni a MongoDB con TLS — Guida completa passo passo

**Per chi è questa guida:** per chi ha già MongoDB funzionante secondo la guida `00-guida-completa.md` e vuole cifrare il traffico tra le applicazioni e il database. Come nella guida 00, ogni passaggio spiega **cosa fare**, **cosa fa il comando** e **cosa devi vedere** se è andato bene.

**Cosa otterrai alla fine:**

- tutte le connessioni a MongoDB cifrate, comprese quelle locali, i backup e i ripristini;
- i client che verificano di parlare con il server giusto, non con un impostore;
- una tua autorità di certificazione (CA) con cui rinnovare il certificato senza dover riconfigurare i client;
- una procedura di rinnovo, una di emergenza per tornare indietro e una tabella degli errori più comuni.

**Tempo stimato:** 45–60 minuti.

---

## Indice

- [Parte 0 — Concetti di base](#parte-0--concetti-di-base)
- [Parte 1 — TLS o tunnel SSH?](#parte-1--tls-o-tunnel-ssh)
- [Parte 2 — Preparazione](#parte-2--preparazione)
- [Parte 3 — Creare l'autorità di certificazione (CA)](#parte-3--creare-lautorità-di-certificazione-ca)
- [Parte 4 — Creare il certificato del server](#parte-4--creare-il-certificato-del-server)
- [Parte 5 — Proteggere i file](#parte-5--proteggere-i-file)
- [Parte 6 — Configurare MongoDB](#parte-6--configurare-mongodb)
- [Parte 7 — Verificare che il TLS funzioni](#parte-7--verificare-che-il-tls-funzioni)
- [Parte 8 — Aggiornare backup, ripristino e comandi di test](#parte-8--aggiornare-backup-ripristino-e-comandi-di-test)
- [Parte 9 — Configurare i client](#parte-9--configurare-i-client)
- [Parte 10 — Rinnovare il certificato](#parte-10--rinnovare-il-certificato)
- [Parte 11 — Tornare indietro (disattivare il TLS)](#parte-11--tornare-indietro-disattivare-il-tls)
- [Parte 12 — Quando qualcosa va storto](#parte-12--quando-qualcosa-va-storto)
- [Parte 13 — Verso la produzione](#parte-13--verso-la-produzione)
- [Appendice A — Dove si trova ogni cosa](#appendice-a--dove-si-trova-ogni-cosa)
- [Appendice B — Promemoria dei comandi](#appendice-b--promemoria-dei-comandi)
- [Le 6 regole d'oro del TLS](#le-6-regole-doro-del-tls)

> **Convenzioni:** valgono le stesse della guida 00 (prompt, blocchi `<< 'EOF'` da incollare per intero, segnaposto `<...>` da sostituire togliendo anche `<` e `>`). In questa guida l'utente della VM è `azureuser`, la VM si chiama `mongo-vm` e l'IP privato d'esempio è `10.0.0.4`: sostituiscili con i tuoi.

---

## Parte 0 — Concetti di base

**TLS.** È il protocollo che cifra le comunicazioni su internet: lo stesso che fa comparire il lucchetto nel browser sui siti `https`. Applicato a MongoDB, fa sì che utente, password e dati viaggino in forma illeggibile per chiunque intercetti il traffico.

Il TLS fa **due cose diverse**, ed è importante tenerle distinte:

1. **Cifra** il traffico, così chi ascolta non capisce nulla.
2. **Verifica l'identità** del server, così il client è sicuro di parlare con il vero MongoDB e non con un impostore che si è messo in mezzo (attacco *man in the middle*).

Senza la seconda, la prima vale poco: un impostore potrebbe farsi dare la password e poi leggere tutto. Questa guida configura **entrambe**.

**Certificato.** La "carta d'identità digitale" del server. Contiene i nomi e gli indirizzi del server, la data di scadenza, una *chiave pubblica* e la firma di chi l'ha rilasciato. Non è un segreto: il server lo mostra a chiunque si colleghi.

**Chiave privata.** La controparte segreta del certificato. Chi la possiede può "essere" il server. **Non deve mai uscire dal server** e non va mai condivisa.

**Autorità di certificazione (CA).** Chi firma i certificati. Il client non conosce in anticipo il certificato del server, ma si fida della CA che lo ha firmato: è come un passaporto, di cui ti fidi perché è stato emesso dallo Stato. In questa guida creiamo **una nostra CA** privata.

**SAN (Subject Alternative Name).** L'elenco degli indirizzi e dei nomi per cui il certificato è valido. Se ti colleghi a `20.1.2.3` ma quell'indirizzo non è nel SAN, il client rifiuta la connessione, esattamente come un passaporto intestato a un'altra persona.

**Perché una CA e non un semplice certificato "self-signed"?** Con un certificato self-signed ogni rinnovo produce un certificato nuovo, da ridistribuire a tutti i client. Con una CA, i client ricevono una sola volta il certificato della CA (valido 10 anni) e si fidano automaticamente di ogni certificato del server firmato da lei: i rinnovi diventano invisibili ai client.

### I file che creeremo

| File | Cos'è | Segreto? | Dove va |
|---|---|---|---|
| `ca.key` | Chiave privata della CA | **Sì, il più importante** | In un posto sicuro fuori dalla VM (serve solo per firmare) |
| `ca.pem` | Certificato della CA | No | Ai client e a MongoDB |
| `server.key` | Chiave privata del server | **Sì** | Solo sulla VM |
| `server.crt` | Certificato del server | No | Sulla VM |
| `server.pem` | `server.crt` + `server.key` in un unico file | **Sì** (contiene la chiave) | Solo sulla VM, letto da MongoDB |
| `server.ext` | Impostazioni del certificato (SAN) | No | Sulla VM, serve per i rinnovi |
| `ca.srl` | Contatore dei certificati firmati | No | Insieme a `ca.key` |

---

## Parte 1 — TLS o tunnel SSH?

Anche il tunnel SSH descritto nella guida 00 (Parte 11.1) cifra il traffico e verifica il server. Le due soluzioni sono ugualmente sicure: cambia la gestione.

| | Tunnel SSH | TLS (questa guida) |
|---|---|---|
| Porta 27017 esposta | No | Sì, limitata agli IP autorizzati |
| Cosa serve al client | Chiave SSH e tunnel aperto | Il file `ca.pem` |
| Manutenzione | Nessuna | Rinnovo del certificato del server ogni ~2 anni |
| Più persone o applicazioni | Ognuna con il suo tunnel | Basta distribuire `ca.pem` |
| Servizi che non possono aprire un tunnel | Non adatto | Adatto |

**Regola pratica:** se sei da solo in sviluppo, il tunnel è la scelta più semplice. Il TLS diventa conveniente con più persone, più applicazioni o servizi che devono collegarsi direttamente, ed è comunque indispensabile in produzione quando il database comunica in rete.

Le due soluzioni possono anche convivere: con il TLS attivo il tunnel continua a funzionare, ma anche attraverso il tunnel i client dovranno usare il TLS.

---

## Parte 2 — Preparazione

> 📍 **Dove:** sulla VM, prompt `azureuser@mongo-vm`.

### 2.1 Fare un backup e salvare la configurazione attuale

Prima di ogni modifica importante:

```bash
sudo /usr/local/bin/mongo-backup.sh
cd ~/mongodb
cp docker-compose.yml docker-compose.yml.pre-tls
```

La copia `docker-compose.yml.pre-tls` serve per tornare indietro in un attimo se qualcosa non va (Parte 11).

### 2.2 Recuperare gli indirizzi IP della VM

Il certificato deve contenere tutti gli indirizzi con cui i client raggiungeranno MongoDB.

**IP privato:**

```bash
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1
```

**IP pubblico:** nel portale Azure, pagina *Panoramica* della VM, voce *Indirizzo IP pubblico*. In alternativa, dalla VM:

```bash
curl -s https://ifconfig.me; echo
```

Annotali entrambi.

### 2.3 Verificare che l'IP pubblico sia statico

Se l'IP pubblico cambiasse, il certificato non sarebbe più valido per il nuovo indirizzo. Nel portale Azure apri la risorsa *Indirizzo IP pubblico* collegata alla VM → *Configurazione*: l'assegnazione deve essere **Statico**. Gli IP pubblici di tipo *Standard*, predefiniti per le VM recenti, lo sono già.

> Se usi solo il tunnel SSH e l'accesso dalla VM stessa, l'IP pubblico nel certificato non è strettamente necessario, ma inserirlo non fa danni e ti lascia libero di attivare l'accesso diretto in futuro.

### 2.4 Creare la cartella dei certificati

```bash
mkdir -p ~/mongodb/tls
chmod 700 ~/mongodb/tls
cd ~/mongodb/tls
```

✅ Il prompt diventa `azureuser@mongo-vm:~/mongodb/tls$`.

> **Scorciatoia:** le Parti 3 e 4 sono automatizzate dallo script `config/genera-certificati-tls.sh` del repository. Ti consigliamo di eseguirle a mano almeno la prima volta, per capire cosa succede; lo script è comodo soprattutto per i rinnovi.

---

## Parte 3 — Creare l'autorità di certificazione (CA)

> 📍 **Dove:** sulla VM, nella cartella `~/mongodb/tls`.

```bash
openssl genrsa -out ca.key 4096
openssl req -x509 -new -key ca.key -sha256 -days 3650 -subj "/CN=MongoDB Dev CA" -out ca.pem
chmod 600 ca.key
```

**Cosa fa:**

1. `genrsa` crea la chiave privata della CA (4096 bit, molto robusta);
2. `req -x509` crea il certificato della CA, valido **10 anni** (3650 giorni), con nome `MongoDB Dev CA`;
3. `chmod 600` rende la chiave leggibile solo da te.

**Verifica:**

```bash
openssl x509 -in ca.pem -noout -subject -enddate
```

✅ **Devi vedere:** `subject=CN = MongoDB Dev CA` (gli spazi possono variare) e una data di scadenza fra dieci anni.

---

## Parte 4 — Creare il certificato del server

> 📍 **Dove:** sulla VM, nella cartella `~/mongodb/tls`.

### 4.1 Impostare gli indirizzi

Sostituisci con i tuoi valori (Parte 2.2):

```bash
PUB_IP=<IP_PUBBLICO_VM>
PRIV_IP=10.0.0.4
echo "Pubblico: $PUB_IP - Privato: $PRIV_IP"
```

✅ Controlla che la riga stampata mostri i due indirizzi corretti. Se una delle due parti è vuota, ripeti l'assegnazione.

### 4.2 Descrivere il certificato

```bash
cat > server.ext << EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:mongo,IP:127.0.0.1,IP:$PRIV_IP,IP:$PUB_IP
EOF
cat server.ext
```

> Attenzione: qui la prima riga è `<< EOF` **senza apici**, al contrario del solito. È voluto: così il terminale sostituisce `$PRIV_IP` e `$PUB_IP` con i valori veri.

✅ L'ultima riga stampata deve contenere gli indirizzi veri, per esempio `IP:10.0.0.4,IP:20.1.2.3`, e non le scritte `$PRIV_IP`.

**Cosa significa il SAN:**

| Voce | Serve per |
|---|---|
| `DNS:localhost`, `IP:127.0.0.1` | Connessioni dalla VM stessa, backup, e connessioni tramite tunnel SSH |
| `DNS:mongo` | Applicazioni in altri container dello stesso `docker-compose.yml` |
| `IP:$PRIV_IP` | Client nella stessa rete privata Azure |
| `IP:$PUB_IP` | Accesso diretto da internet (es. il tuo PC) |

Se in futuro assegnerai un nome DNS alla VM (per esempio `miodb.westeurope.cloudapp.azure.com`), aggiungilo come `DNS:...` e rigenera il certificato (Parte 10).

### 4.3 Generare e firmare il certificato

```bash
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=mongo-vm" -out server.csr
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 825 -sha256 -extfile server.ext -out server.crt
rm server.csr
```

**Cosa fa:**

1. crea la chiave privata del server;
2. prepara una "richiesta di certificato" (`server.csr`);
3. la CA firma la richiesta e produce `server.crt`, valido **825 giorni** (circa 2 anni e 3 mesi), con gli indirizzi di `server.ext`;
4. elimina la richiesta, che non serve più.

### 4.4 Controllare il certificato

```bash
openssl verify -CAfile ca.pem server.crt
openssl x509 -in server.crt -noout -ext subjectAltName -enddate
```

✅ **Devi vedere:** `server.crt: OK`, l'elenco degli indirizzi del SAN e la data di scadenza.

### 4.5 Creare il file per MongoDB

MongoDB vuole certificato e chiave del server in un unico file:

```bash
cat server.crt server.key | sudo tee server.pem > /dev/null
```

---

## Parte 5 — Proteggere i file

> 📍 **Dove:** sulla VM, nella cartella `~/mongodb/tls`.

### 5.1 Permessi

```bash
sudo chown 999:999 server.pem
sudo chmod 600 server.pem
chmod 600 server.key
chmod 644 ca.pem server.crt
ls -l
```

✅ **Devi vedere:** `server.pem` con proprietario `999 999` e permessi `-rw-------`; `ca.key` e `server.key` con `-rw-------`; `ca.pem` e `server.crt` con `-rw-r--r--`.

Come per il file della password (guida 00, Parte 6.2), `server.pem` appartiene all'utente con numero 999, cioè all'utente con cui MongoDB gira dentro il container.

### 5.2 Mettere al sicuro la chiave della CA

`ca.key` è il file più delicato: con quello chiunque potrebbe firmare certificati considerati validi dai tuoi client. Sulla VM serve solo nel momento in cui firmi un certificato, quindi è meglio conservarlo altrove.

> 📍 **Dal tuo PC**, in PowerShell:

```powershell
scp -i C:\percorso\della\chiave.pem azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.key C:\percorso\sicuro\ca.key
scp -i C:\percorso\della\chiave.pem azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.srl C:\percorso\sicuro\ca.srl
```

Conserva `ca.key` in un posto protetto: un password manager che supporta allegati, Azure Key Vault o una cartella cifrata. **Non** metterlo nel repository Git e non lasciarlo in una cartella sincronizzata senza protezione.

Solo dopo aver verificato che la copia sul PC esista, eliminalo dalla VM:

> 📍 **Sulla VM:**

```bash
cd ~/mongodb/tls
shred -u ca.key
ls
```

`shred -u` sovrascrive il file prima di cancellarlo, così non è recuperabile.

✅ In `ls` non deve più comparire `ca.key`. Devono restare `ca.pem`, `ca.srl`, `server.crt`, `server.ext`, `server.key`, `server.pem`.

> Per un ambiente di puro laboratorio puoi anche lasciare `ca.key` sulla VM con permessi `600`: è una scelta di comodità, non di sicurezza.

---

## Parte 6 — Configurare MongoDB

> 📍 **Dove:** sulla VM, nella cartella `~/mongodb`.

### 6.1 Il nuovo docker-compose.yml

```bash
cd ~/mongodb
PRIV_IP=10.0.0.4
echo "IP privato: $PRIV_IP"
```

✅ Controlla che l'IP sia quello giusto, poi incolla il blocco **intero**:

```bash
cat > docker-compose.yml << EOF
services:
  mongo:
    image: mongo:8.0
    container_name: mongo
    restart: unless-stopped
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
grep -A2 'ports:' docker-compose.yml
```

✅ Il `grep` deve mostrare `127.0.0.1:27017:27017` e la riga con il tuo IP privato vero.

> **Se non ti serve l'accesso diretto** (usi solo il tunnel SSH o applicazioni sulla VM), elimina la riga con l'IP privato: il TLS funzionerà comunque per tutte le connessioni.

### 6.2 Cosa è cambiato

Rispetto al compose della guida 00 ci sono due novità.

**Il blocco `command`**, cioè le opzioni con cui parte MongoDB:

| Opzione | Significato |
|---|---|
| `--tlsMode=requireTLS` | Accetta **solo** connessioni cifrate; quelle in chiaro vengono rifiutate |
| `--tlsCertificateKeyFile` | Il file con certificato e chiave del server |
| `--tlsCAFile` | Il certificato della CA |
| `--tlsAllowConnectionsWithoutCertificates` | I client si autenticano con utente e password, senza dover presentare un proprio certificato (vedi sotto) |
| `--tlsDisabledProtocols=TLS1_0,TLS1_1` | Disattiva le versioni vecchie e deboli del protocollo; restano TLS 1.2 e 1.3 |

> ⚠️ **La trappola di `tlsCAFile`.** Quando indichi una CA, MongoDB per impostazione predefinita pretende che anche **ogni client** presenti un certificato firmato da quella CA. Senza `--tlsAllowConnectionsWithoutCertificates` nessuno riuscirebbe più a collegarsi con la sola password, nemmeno lo script di backup.

**Due righe in `volumes`**, che rendono visibili al container solo i due file necessari, in sola lettura (`:ro`). La cartella `tls` non viene montata per intero: se anche contenesse altri file sensibili, MongoDB non li vedrebbe.

> Esistono anche le modalità `allowTLS` e `preferTLS`, che accettano sia connessioni cifrate sia in chiaro. Servono per migrare senza interruzioni un sistema con molti client: si parte da `preferTLS`, si aggiornano i client uno alla volta, poi si passa a `requireTLS`. In un ambiente piccolo conviene andare direttamente su `requireTLS`.

### 6.3 Controllare e applicare

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose up -d
```

✅ **Devi vedere:** `compose valido`, poi `Container mongo Recreated` e `Started`. I dati non vengono toccati.

---

## Parte 7 — Verificare che il TLS funzioni

> 📍 **Dove:** sulla VM, nella cartella `~/mongodb`.

### 7.1 Il container è in funzione?

```bash
sudo docker compose ps
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'
```

✅ Lo stato deve essere `Up` (non `Restarting`), e tra avvisi ed errori non devono comparire messaggi su certificati o TLS. Restano gli avvisi innocui già noti dalla guida 00 (`ftdc`, XFS).

❌ **Se il container si riavvia in continuazione**, guarda le ultime righe dei log con `sudo docker compose logs --tail 30 mongo` e consulta la [Parte 12](#parte-12--quando-qualcosa-va-storto). La causa più frequente sono i permessi di `server.pem`.

### 7.2 Il server presenta il certificato giusto?

```bash
openssl s_client -connect 127.0.0.1:27017 -CAfile tls/ca.pem </dev/null 2>/dev/null | grep -E "Verify return code|Protocol"
```

✅ **Devi vedere:** `Verify return code: 0 (ok)` e un protocollo `TLSv1.3` o `TLSv1.2`.

### 7.3 Le versioni vecchie sono rifiutate?

```bash
openssl s_client -connect 127.0.0.1:27017 -tls1_1 </dev/null 2>&1 | grep -iE "alert|error|no protocols" | head -2
```

✅ Deve comparire un errore: la connessione con TLS 1.1 viene rifiutata. (Alcune versioni di OpenSSL non permettono nemmeno di tentarla: anche quello va bene.)

### 7.4 Collegarsi con la shell

Da ora ogni connessione, anche dalla VM, deve usare il TLS:

```bash
sudo docker exec -it mongo mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem \
  -u admin -p --authenticationDatabase admin
```

✅ Dopo la password, compare il prompt `test>`. Esci con `exit`.

### 7.5 La prova del contrario

La stessa connessione **senza** TLS deve fallire:

```bash
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin --eval 'db.runCommand({ping:1})'
```

✅ **Deve fallire** con un errore di connessione (per esempio `connection closed` o `MongoServerSelectionError`). Vuol dire che le connessioni in chiaro sono davvero rifiutate.

---

## Parte 8 — Aggiornare backup, ripristino e comandi di test

> 📍 **Dove:** sulla VM.

Con `requireTLS` anche `mongodump` e `mongorestore` devono usare il TLS: senza questa parte, **i backup notturni fallirebbero**.

### 8.1 Il nuovo script di backup

Questa versione riconosce da sola se il TLS è attivo (controlla se nel container esiste `/etc/mongo/tls/ca.pem`), quindi funziona sia con sia senza TLS. Incolla il blocco **intero**:

```bash
sudo tee /usr/local/bin/mongo-backup.sh > /dev/null << 'EOF'
#!/bin/bash
set -euo pipefail
umask 077

DEST=/var/backups/mongodb
KEEP_DAILY=7      # giorni
KEEP_WEEKLY=4     # settimane
KEEP_MONTHLY=12   # mesi

mkdir -p "$DEST/daily" "$DEST/weekly" "$DEST/monthly"
FILE="$DEST/daily/mongo-$(date +%Y%m%d-%H%M%S).archive.gz"

docker exec -i mongo sh -c '
  umask 077
  printf "password: %s\n" "$(cat /run/secrets/mongo_root_password)" > /tmp/dump.yaml
  TLS=""
  [ -f /etc/mongo/tls/ca.pem ] && TLS="--ssl --sslCAFile=/etc/mongo/tls/ca.pem"
  mongodump $TLS --config=/tmp/dump.yaml -u admin --authenticationDatabase admin --archive --gzip --quiet
  status=$?
  rm -f /tmp/dump.yaml
  exit $status
' > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"

[ "$(date +%u)" = "7" ]  && ln -f "$FILE" "$DEST/weekly/"
[ "$(date +%d)" = "01" ] && ln -f "$FILE" "$DEST/monthly/"

find "$DEST/daily"   -name 'mongo-*.archive.gz' -mtime +$((KEEP_DAILY - 1))        -delete
find "$DEST/weekly"  -name 'mongo-*.archive.gz' -mtime +$((KEEP_WEEKLY * 7 - 1))  -delete
find "$DEST/monthly" -name 'mongo-*.archive.gz' -mtime +$((KEEP_MONTHLY * 31 - 1)) -delete

echo "Backup completato: $FILE ($(du -h "$FILE" | cut -f1))"
EOF
sudo chmod 700 /usr/local/bin/mongo-backup.sh
```

> Gli strumenti di backup di MongoDB usano ancora i nomi storici `--ssl` e `--sslCAFile`, ma il protocollo è il TLS.

### 8.2 Provare il backup

```bash
sudo /usr/local/bin/mongo-backup.sh
sudo systemctl start mongo-backup.service
sudo journalctl -u mongo-backup.service -n 5 --no-pager
```

✅ **Devi vedere** due volte `Backup completato`: una dall'esecuzione manuale, una da quella tramite systemd.

### 8.3 Il comando di ripristino con TLS

```bash
sudo sh -c 'f=$(ls -t /var/backups/mongodb/daily/mongo-*.archive.gz | head -1); echo "Ripristino: $f"; \
  docker exec -i mongo sh -c "mongorestore --ssl --sslCAFile=/etc/mongo/tls/ca.pem -u admin -p \"\$(cat /run/secrets/mongo_root_password)\" --authenticationDatabase admin --archive --gzip --drop" < "$f"'
```

È lo stesso comando della guida 00 (Parte 10.1), con in più `--ssl --sslCAFile=...`. Come allora, `--drop` sostituisce le collezioni presenti nel backup.

### 8.4 I comandi con l'utente applicativo

Ai comandi della guida 00 che usano `mongosh` va aggiunto `--tls --tlsCAFile /etc/mongo/tls/ca.pem`. Per esempio, la verifica di `appuser`:

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.runCommand({ ping: 1 })"'
```

✅ Risposta: `{ ok: 1 }`

---

## Parte 9 — Configurare i client

### 9.1 Portare `ca.pem` sul tuo PC

> 📍 **Dal tuo PC**, in PowerShell:

```powershell
scp -i C:\percorso\della\chiave.pem azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.pem C:\percorso\progetto\ca.pem
```

`ca.pem` **non è un segreto**: contiene solo la parte pubblica della CA. Puoi tenerlo nella cartella del progetto e condividerlo con chi deve collegarsi. Ricorda però che i file da proteggere, `ca.key`, `server.key` e `server.pem`, non devono mai finire nel repository.

### 9.2 Le stringhe di connessione

A tutte le stringhe della guida 00 si aggiungono due parametri: `tls=true` e `tlsCAFile=<percorso di ca.pem>`.

| Dove gira il client | Stringa di connessione |
|---|---|
| Sulla VM | `mongodb://appuser:PWD@127.0.0.1:27017/appdb?authSource=appdb&tls=true&tlsCAFile=/percorso/ca.pem` |
| Container nello stesso compose | `mongodb://appuser:PWD@mongo:27017/appdb?authSource=appdb&tls=true&tlsCAFile=/percorso/ca.pem` |
| PC tramite tunnel SSH | `mongodb://appuser:PWD@127.0.0.1:27017/appdb?authSource=appdb&directConnection=true&tls=true&tlsCAFile=C:/percorso/ca.pem` |
| PC con accesso diretto | `mongodb://appuser:PWD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true&tls=true&tlsCAFile=C:/percorso/ca.pem` |

**Attenzione ai percorsi Windows:**

- usa le barre normali (`C:/progetti/app/ca.pem`), non le rovesciate;
- se il percorso contiene **spazi**, dentro la stringa di connessione vanno scritti come `%20` (es. `C:/Github%20progetti/app/ca.pem`). In alternativa, più comodo, passa il percorso come opzione separata nel codice (vedi 9.3).

**Per un'applicazione in un altro container** dello stesso compose, monta anche nel suo servizio il file `./tls/ca.pem` in sola lettura, come fatto per MongoDB, e usa il percorso interno al container.

### 9.3 Nell'applicazione

Conserva stringa di connessione e percorso della CA nel file `.env` del progetto (escluso da Git con il `.gitignore`):

```
MONGODB_URI=mongodb://appuser:PWD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true&tls=true
MONGODB_CA_FILE=C:/percorso con spazi/ca.pem
```

Esempio con Node.js e il driver ufficiale:

```javascript
const { MongoClient } = require("mongodb");

const client = new MongoClient(process.env.MONGODB_URI, {
  tlsCAFile: process.env.MONGODB_CA_FILE,
});
```

Passando `tlsCAFile` come opzione separata, gli spazi nel percorso non sono un problema. Gli altri driver ufficiali (Python, Java, .NET, Go…) hanno un'opzione equivalente.

> 🚫 **Non usare** `tlsAllowInvalidCertificates=true` o `tlsInsecure=true` per "far funzionare" una connessione: il traffico resterebbe cifrato, ma il client accetterebbe qualunque server, anche un impostore. Se il client rifiuta il certificato, la causa è quasi sempre un indirizzo mancante nel SAN o il file `ca.pem` sbagliato: vedi la Parte 12.

### 9.4 MongoDB Compass

1. Nuova connessione → incolla la stringa di connessione senza `tlsCAFile`.
2. *Advanced Connection Options* → scheda *TLS/SSL*.
3. *SSL/TLS Connection*: **On**.
4. *Certificate Authority (.pem)*: seleziona il file `ca.pem`.
5. Lascia **disattivate** le opzioni *tlsInsecure* e *tlsAllowInvalidCertificates*.

Se ti colleghi tramite il tunnel SSH configurato in Compass, le impostazioni TLS si aggiungono a quelle della scheda *Proxy/SSH*.

### 9.5 Il firewall di Azure

Il TLS protegge il traffico, **non** il database da chi prova a indovinare le password. La regola NSG sulla porta 27017 deve continuare ad avere come origine solo gli IP autorizzati, mai "Any".

---

## Parte 10 — Rinnovare il certificato

Il certificato del server scade dopo 825 giorni. Scaduto quello, **nessun client riesce più a collegarsi**: conviene rinnovarlo con qualche settimana di anticipo.

### 10.1 Controllare la scadenza

> 📍 **Sulla VM:**

```bash
openssl x509 -in ~/mongodb/tls/server.crt -noout -enddate
openssl x509 -in ~/mongodb/tls/server.crt -noout -checkend $((30*86400)) && echo "OK: valido per almeno 30 giorni" || echo "ATTENZIONE: scade entro 30 giorni"
```

Segna la data di scadenza in calendario, con un promemoria un mese prima.

### 10.2 Rinnovare

1. **Riporta sulla VM** la chiave della CA e il contatore. 📍 Dal tuo PC:

   ```powershell
   scp -i C:\percorso\della\chiave.pem C:\percorso\sicuro\ca.key C:\percorso\sicuro\ca.srl azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/
   ```

2. **Rigenera il certificato del server.** 📍 Sulla VM:

   ```bash
   cd ~/mongodb/tls
   chmod 600 ca.key
   openssl genrsa -out server.key 2048
   openssl req -new -key server.key -subj "/CN=mongo-vm" -out server.csr
   openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAserial ca.srl \
     -days 825 -sha256 -extfile server.ext -out server.crt
   rm server.csr
   openssl verify -CAfile ca.pem server.crt
   cat server.crt server.key | sudo tee server.pem > /dev/null
   sudo chown 999:999 server.pem && sudo chmod 600 server.pem
   chmod 600 server.key
   ```

   `server.ext` è quello creato nella Parte 4.2. Se nel frattempo sono cambiati gli indirizzi, modificalo prima (per esempio con `nano server.ext`).

3. **Riavvia MongoDB** per fargli leggere il nuovo certificato:

   ```bash
   cd ~/mongodb && sudo docker compose restart
   ```

4. **Verifica** con i comandi della Parte 7.2 e 7.4, poi controlla la nuova scadenza (10.1).

5. **Rimetti al sicuro la CA:** copia sul PC il `ca.srl` aggiornato (📍 dal PC, come nella Parte 5.2) ed elimina di nuovo `ca.key` dalla VM con `shred -u ~/mongodb/tls/ca.key`.

✅ **I client non devono cambiare nulla:** il nuovo certificato è firmato dalla stessa CA, e il loro `ca.pem` resta valido.

> In alternativa ai passi 2–3, lo script `config/genera-certificati-tls.sh` del repository riutilizza la CA esistente e rigenera solo il certificato del server.

### 10.3 E quando scade la CA?

Fra dieci anni scadrà anche `ca.pem`. A quel punto va creata una nuova CA (Parte 3), firmato un nuovo certificato del server e **distribuito il nuovo `ca.pem` a tutti i client**.

---

## Parte 11 — Tornare indietro (disattivare il TLS)

Se qualcosa non funziona e ti serve rimettere tutto com'era, per esempio per sbloccare un'applicazione:

```bash
cd ~/mongodb
cp docker-compose.yml docker-compose.yml.tls
cp docker-compose.yml.pre-tls docker-compose.yml
sudo docker compose up -d
```

**Cosa fa:** salva la configurazione con TLS (per riattivarla in seguito), ripristina quella precedente e ricrea il container. I dati non vengono toccati.

- Lo script di backup della Parte 8.1 continua a funzionare, perché riconosce da solo l'assenza del TLS.
- Nei client vanno tolti i parametri `tls=true` e `tlsCAFile`.

Per riattivare il TLS: `cp docker-compose.yml.tls docker-compose.yml && sudo docker compose up -d`.

---

## Parte 12 — Quando qualcosa va storto

### Lato server

| Sintomo | Causa probabile | Soluzione |
|---|---|---|
| Container in stato `Restarting`, nei log errori di lettura del certificato o `Permission denied` | `server.pem` non leggibile dall'utente 999 | `sudo chown 999:999 ~/mongodb/tls/server.pem && sudo chmod 600 ~/mongodb/tls/server.pem`, poi `sudo docker compose restart` |
| Container in errore subito dopo l'avvio, log con `No such file` | Percorsi dei file montati sbagliati, o file mancanti in `~/mongodb/tls` | Controlla con `ls -l ~/mongodb/tls` e le righe `volumes` del compose |
| Errore sulla chiave privata che non corrisponde al certificato | `server.pem` costruito con una chiave diversa da quella del certificato | Rigenera `server.pem` con `cat server.crt server.key` (Parte 4.5) |
| `compose valido` non compare | Errore di indentazione nel compose | Ricopia il blocco della Parte 6.1 per intero |
| I backup notturni falliscono dopo l'attivazione del TLS | Script di backup vecchio, senza TLS | Installa lo script della Parte 8.1 |

### Lato client

| Messaggio (o simile) | Causa probabile | Soluzione |
|---|---|---|
| `connection closed`, `ECONNRESET`, `MongoServerSelectionError` subito | Il client non usa il TLS | Aggiungi `tls=true` alla stringa di connessione |
| `certificate verify failed`, `unable to get local issuer certificate`, `self-signed certificate in certificate chain` | Il client non ha il `ca.pem` giusto | Controlla il percorso di `tlsCAFile` e che il file sia il `ca.pem` di questa CA |
| `Hostname/IP does not match certificate's altnames`, `IP address mismatch` | Ti colleghi a un indirizzo non presente nel SAN | Usa uno degli indirizzi del SAN (`openssl x509 -in server.crt -noout -ext subjectAltName`), oppure aggiungi l'indirizzo e rinnova il certificato (Parte 10) |
| `certificate has expired` | Certificato del server scaduto | Rinnovalo (Parte 10) |
| `No SSL certificate provided by peer` (nei log del server) | Manca `--tlsAllowConnectionsWithoutCertificates` | Aggiungi l'opzione al blocco `command` e `sudo docker compose up -d` |
| Errore sul file CA con un percorso Windows | Barre rovesciate o spazi nella stringa di connessione | Usa `/` al posto di `\`, `%20` al posto degli spazi, oppure l'opzione separata (Parte 9.3) |
| `Authentication failed` | Non è un problema TLS: password errata | Vedi guida 00, Parte 15 |

### Diagnosi rapida

Per capire se il problema è nel TLS o altrove, dalla VM:

```bash
openssl s_client -connect 127.0.0.1:27017 -CAfile ~/mongodb/tls/ca.pem </dev/null 2>/dev/null | grep "Verify return code"
```

- `0 (ok)`: lato server il TLS è a posto; il problema è nella configurazione del client.
- Qualunque altro codice: il problema è nel certificato o nella configurazione del server.

---

## Parte 13 — Verso la produzione

Il procedimento di questa guida è corretto anche per la produzione, con alcune differenze:

- **Certificati da una CA riconosciuta.** Una CA aziendale già distribuita sui computer, o una CA pubblica come Let's Encrypt (serve un nome DNS e un rinnovo automatico ogni 90 giorni). In entrambi i casi i client non hanno bisogno di ricevere `ca.pem`.
- **Nomi DNS invece di indirizzi IP** nel SAN: sono più stabili e più facili da gestire.
- **Nessuna esposizione su internet:** applicazione e database comunicano sulla rete privata Azure; il TLS protegge anche quel tratto.
- **Chiave della CA in un sistema dedicato**, come Azure Key Vault, con accessi controllati e registrati.
- **Monitoraggio della scadenza** dei certificati, con avvisi automatici.
- **Replica set e sharding:** oltre alle connessioni dei client, vanno cifrate anche quelle **tra i nodi**. In questo scenario si possono usare certificati x.509 anche per autenticare i membri del cluster tra loro, al posto del keyFile.

---

## Appendice A — Dove si trova ogni cosa

| Cosa | Dove |
|---|---|
| Cartella dei certificati | `~/mongodb/tls` (permessi `700`) |
| Certificato della CA | `~/mongodb/tls/ca.pem` → nel container `/etc/mongo/tls/ca.pem` |
| Certificato + chiave del server | `~/mongodb/tls/server.pem` → nel container `/etc/mongo/tls/server.pem` |
| Impostazioni SAN per i rinnovi | `~/mongodb/tls/server.ext` |
| Chiave della CA | **Fuori dalla VM**, in un posto sicuro (con `ca.srl`) |
| Compose con TLS | `~/mongodb/docker-compose.yml` (copia in `docker-compose.yml.tls` dopo un rollback) |
| Compose senza TLS | `~/mongodb/docker-compose.yml.pre-tls` |
| Script di backup (compatibile TLS) | `/usr/local/bin/mongo-backup.sh` |

---

## Appendice B — Promemoria dei comandi

```bash
# Shell amministrativa con TLS
sudo docker exec -it mongo mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem -u admin -p --authenticationDatabase admin

# Verifica del certificato presentato dal server
openssl s_client -connect 127.0.0.1:27017 -CAfile ~/mongodb/tls/ca.pem </dev/null 2>/dev/null | grep -E "Verify return code|Protocol"

# Indirizzi validi e scadenza del certificato
openssl x509 -in ~/mongodb/tls/server.crt -noout -ext subjectAltName -enddate

# Scade entro 30 giorni?
openssl x509 -in ~/mongodb/tls/server.crt -noout -checkend $((30*86400)) && echo OK || echo "IN SCADENZA"

# Backup (riconosce da solo il TLS)
sudo /usr/local/bin/mongo-backup.sh

# Rollback senza TLS
cd ~/mongodb && cp docker-compose.yml docker-compose.yml.tls && cp docker-compose.yml.pre-tls docker-compose.yml && sudo docker compose up -d
```

**Parametri da aggiungere alle stringhe di connessione:**

```
&tls=true&tlsCAFile=<percorso di ca.pem>
```

---

## Le 6 regole d'oro del TLS

1. **Cifrare non basta, bisogna verificare:** mai `tlsAllowInvalidCertificates` o `tlsInsecure`.
2. **`ca.key` è il file più prezioso:** fuori dalla VM, fuori dal repository, in un posto sicuro.
3. **`ca.pem` è pubblico:** distribuiscilo tranquillamente ai client.
4. **Nel SAN vanno tutti gli indirizzi** con cui ti colleghi; se ne aggiungi uno, rinnova il certificato.
5. **Segna la scadenza in calendario:** un certificato scaduto blocca tutti i client in un colpo.
6. **Il TLS non sostituisce il firewall:** la porta 27017 resta aperta solo agli IP autorizzati.
