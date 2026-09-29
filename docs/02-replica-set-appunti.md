# 02 — Replica set: appunti di laboratorio

> **Diario del laboratorio.** Questi appunti raccolgono, man mano che il laboratorio procede, le scelte fatte, il loro motivo, le scoperte e gli inconvenienti reali. Da qui verranno ricavate la guida completa `02-replica-set-guida-completa.md` e quella rapida `02-replica-set-guida-rapida.md`. Non è una guida da seguire così com'è.

**Ultimo aggiornamento:** laboratorio **completato** (Passi 0–20). Guide scritte: `02-replica-set-guida-completa.md` e `02-replica-set-guida-rapida.md`; risorse in `config/02-replica-set/`. Questo file resta come diario del laboratorio.

---

## Indice

1. [Ambiente del laboratorio](#1-ambiente-del-laboratorio)
2. [Configurazione attuale](#2-configurazione-attuale)
3. [Cronologia dei passi eseguiti](#3-cronologia-dei-passi-eseguiti)
4. [Decisioni e motivazioni](#4-decisioni-e-motivazioni)
5. [Scoperte e inconvenienti](#5-scoperte-e-inconvenienti)
6. [Laboratorio vs produzione](#6-laboratorio-vs-produzione)
7. [Comandi utili del laboratorio](#7-comandi-utili-del-laboratorio)
8. [Da fare](#8-da-fare)
9. [Note per la stesura delle guide](#9-note-per-la-stesura-delle-guide)

---

## 1. Ambiente del laboratorio

| Voce | Valore |
|---|---|
| VM | La stessa della guida 00/01 (Debian 13, Azure), 2 vCPU, 7,8 GB RAM, **nessuno swap**, 58 GB liberi |
| Convivenza | Sulla stessa VM gira il MongoDB di sviluppo (`~/mongodb`, container `mongo`, porta 27017, TLS attivo) |
| Cartella del laboratorio | `~/mongo-lab/02-replica-set` |
| Progetto Compose | `mongo-lab-rs` (prefisso di rete e volumi) |
| Replica set | `rs0` |
| Versione | MongoDB 8.0.32 (immagine `mongo:8.0`) |

| Container | Porta (dentro e fuori) | Membro registrato come | Ruolo iniziale |
|---|---|---|---|
| `mongo-rs1` | 27101 | `<FQDN>:27101` | Primario preferito (`priority: 2`) |
| `mongo-rs2` | 27102 | `<FQDN>:27102` | Secondario |
| `mongo-rs3` | 27103 | `<FQDN>:27103` | Secondario |

`<FQDN>` è il nome DNS pubblico assegnato all'IP della VM su Azure (formato `<etichetta>.<regione>.cloudapp.azure.com`).

File nella cartella del laboratorio:

| File | Contenuto | Permessi |
|---|---|---|
| `docker-compose.yml` | Definizione dei tre nodi | normali |
| `keyfile` | Chiave condivisa per l'autenticazione interna | `400`, owner 999 |
| `root_password.txt` | Password dell'utente `admin` | `600`, owner 999 |
| `docker-compose.yml.bak` | Copia prima delle modifiche per l'accesso esterno | normali |
| `docker-compose.yml.pre-tls` | Configurazione senza TLS (rollback) | normali |
| `docker-compose.yml.allowtls` | Configurazione in `allowTLS` (fase intermedia) | normali |
| `tls/server.ext` | SAN ed EKU del certificato dei nodi | normali |
| `tls/server.key` | Chiave privata dei nodi | `600` |
| `tls/server.crt` | Certificato dei nodi, firmato dalla CA della guida 01 | `644` |
| `tls/server.pem` | `server.crt` + `server.key` per MongoDB | `600`, owner 999 |
| `tls/ca.pem` | Copia del certificato della CA della guida 01 | `644` |

---

## 2. Configurazione attuale

```yaml
name: mongo-lab-rs

x-mongo-common: &mongo-common
  image: mongo:8.0
  restart: unless-stopped
  stop_grace_period: 1m
  extra_hosts:
    - "<FQDN>:<IP_PRIVATO_VM>"
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
    command: ["--replSet", "rs0", "--port", "27101", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--tlsMode", "requireTLS", "--tlsCertificateKeyFile", "/etc/mongo/tls/server.pem", "--tlsCAFile", "/etc/mongo/tls/ca.pem", "--tlsAllowConnectionsWithoutCertificates", "--tlsDisabledProtocols", "TLS1_0,TLS1_1"]
    ports:
      - "127.0.0.1:27101:27101"
      - "<IP_PRIVATO_VM>:27101:27101"
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD_FILE: /run/secrets/rs_root_password
    secrets:
      - rs_root_password
    volumes:
      - rs1-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro
      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro
      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro

  mongo-rs2:
    <<: *mongo-common
    container_name: mongo-rs2
    hostname: mongo-rs2
    command: ["--replSet", "rs0", "--port", "27102", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--tlsMode", "requireTLS", "--tlsCertificateKeyFile", "/etc/mongo/tls/server.pem", "--tlsCAFile", "/etc/mongo/tls/ca.pem", "--tlsAllowConnectionsWithoutCertificates", "--tlsDisabledProtocols", "TLS1_0,TLS1_1"]
    ports:
      - "127.0.0.1:27102:27102"
      - "<IP_PRIVATO_VM>:27102:27102"
    volumes:
      - rs2-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro
      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro
      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro

  mongo-rs3:
    <<: *mongo-common
    container_name: mongo-rs3
    hostname: mongo-rs3
    command: ["--replSet", "rs0", "--port", "27103", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--tlsMode", "requireTLS", "--tlsCertificateKeyFile", "/etc/mongo/tls/server.pem", "--tlsCAFile", "/etc/mongo/tls/ca.pem", "--tlsAllowConnectionsWithoutCertificates", "--tlsDisabledProtocols", "TLS1_0,TLS1_1"]
    ports:
      - "127.0.0.1:27103:27103"
      - "<IP_PRIVATO_VM>:27103:27103"
    volumes:
      - rs3-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro
      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro
      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro

volumes:
  rs1-data:
  rs2-data:
  rs3-data:

secrets:
  rs_root_password:
    file: ./root_password.txt
```

Configurazione del replica set (eseguita una sola volta sul nodo 1):

```javascript
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "<FQDN>:27101", priority: 2 },
    { _id: 1, host: "<FQDN>:27102" },
    { _id: 2, host: "<FQDN>:27103" }
  ]
})
```

Azure:

- **Etichetta nome DNS** sulla risorsa IP pubblico della VM → `<FQDN>`.
- **Regola NSG** in ingresso: TCP `27101-27103`, origine solo l'IP pubblico del client, nome `mongo-lab-rs`.

Certificato dei nodi (`tls/server.ext`):

```
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=DNS:<FQDN>,DNS:localhost,DNS:mongo-rs1,DNS:mongo-rs2,DNS:mongo-rs3,IP:127.0.0.1,IP:<IP_PRIVATO_VM>
```

Firmato con la CA della guida 01 (`~/mongodb/tls/ca.key`, `-CAserial ~/mongodb/tls/ca.srl`), validità 825 giorni.

---

## 3. Cronologia dei passi eseguiti

| Passo | Cosa | Esito |
|---|---|---|
| 0 | Verifica risorse (`free -h`, `nproc`, `df -h /`, `docker stats`) | OK: RAM sufficiente per il replica set; per lo sharding andrà valutata |
| 1 | Cartella, password admin, keyFile | OK |
| 2 | `docker-compose.yml` con tre nodi | Primo tentativo rovinato dall'incolla (§5.1); ricreato in due parti |
| 3 | Avvio dei tre container | OK: nodo 1 inizializzato, nodi 2–3 in attesa di configurazione |
| 4 | `rs.initiate` | Primo tentativo `Authentication failed` (password errata), secondo OK |
| 5 | Verifica stato e replica dell'utente admin sui secondari | OK |
| 6 | Funzione di comodo `rs_eval` | OK |
| 7 | Scrittura tramite stringa del replica set, lettura da secondario, scrittura su secondario rifiutata (`not primary`) | OK |
| 8 | Failover: stop del primario, nuova elezione, scrittura con la stessa stringa, rientro e ripresa del ruolo per `priority: 2` | OK; scoperto il problema dei 10 s di Docker (§5.4), risolto con `stop_grace_period` |
| 9 | Backup da secondario con `--oplog`, cancellazione, ripristino con `--oplogReplay` | OK |
| 10 | Accesso dal PC: scelta del nome DNS Azure, porte su IP privato, NSG, `extra_hosts`, replica set ricreato con i nuovi nomi | OK: connessione da VS Code e failover dal client funzionanti; `Test-NetConnection` sulle tre porte OK |
| 11 | Manutenzione a rotazione: restart dei secondari uno alla volta, `stepDown`, restart del vecchio primario | OK; lo `stepDown` è stato perso nella prima esecuzione (§5.10) e ripetuto a parte: il nodo 1 è diventato `SECONDARY`, il nodo 2 `PRIMARY`, e dopo 60 s il nodo 1 ha ripreso il ruolo |
| 12 | Certificato dei nodi firmato con la CA della guida 01, EKU `serverAuth,clientAuth`, SAN con `<FQDN>` | OK: `server.crt: OK`, EKU e SAN corretti |
| 13 | Compose con opzioni TLS in `allowTLS`, ricreazione a rotazione (`up -d <servizio>`, `stepDown` prima del primario) | OK: tre nodi in `allowTLS`, `openssl s_client` → `Verify return code: 0 (ok)`, TLS 1.3 |
| 14 | Passaggio a caldo a `preferTLS` (`setParameter`), elezione forzata, verifica `serverStatus().transportSecurity`, `rs_eval` e VS Code in TLS | OK: 18–21 connessioni TLS 1.3 per nodo, zero su versioni vecchie; VS Code collegato con `tls=true&tlsCAFile` |
| 15 | Passaggio a caldo a `requireTLS`, prova del contrario, compose aggiornato a `requireTLS` e ricreazione a rotazione | OK: connessione in chiaro rifiutata (`connection ... closed`), dopo la rotazione `requireTLS` letto dalla configurazione di avvio, replica set sano |
| 16 | Utente `appuser` (`readWrite` su `labdb`) creato attraverso la stringa del replica set, con TLS | OK: letto da un secondario (27102) come `appuser`; connessione da VS Code come `appuser` riuscita, visibile solo `labdb` |
| 17 | Script `/usr/local/bin/mongo-rs-backup.sh`: primo nodo acceso, password via stdin, `secondaryPreferred`, `--oplog`, TLS, retention 7/4/12 in `/var/backups/mongo-lab-rs` | OK con tutti i nodi (eseguito in `mongo-rs1`) e con il nodo 1 spento (eseguito in `mongo-rs2`); file `-rw-------` di root |
| 18 | Timer `mongo-rs-backup.timer` alle 03:00 UTC (dopo quello di sviluppo alle 02:30) | OK: entrambi i timer elencati, esecuzione tramite systemd riuscita |
| 19 | Ripristino con TLS: inserimento, backup, `drop`, `mongorestore --oplogReplay --drop` via stringa del replica set | OK: `1 document(s) restored`, `applied 1 oplog entries`, documento tornato |

---

## 4. Decisioni e motivazioni

Ogni decisione: **cosa**, **perché**, **se non lo fai**, **alternative**, **in produzione**.

### D1 — Laboratorio su una sola VM, con un container per ogni nodo

- **Cosa:** tre container sulla VM già esistente, ciascuno nel ruolo di un server distinto.
- **Perché:** riproduce fedelmente configurazione, comandi, autenticazione tra nodi, elezioni e failover, a costo zero.
- **Limiti:** disco, RAM e macchina sono condivisi: se la VM si ferma, cade tutto. L'alta disponibilità è solo dimostrativa. Mancano latenza di rete reale e guasti di rete parziali.
- **Alternative:** nuova VM dedicata (più isolamento, costo); PC con Docker Desktop (costo zero, ma lontano dallo scenario Azure).
- **In produzione:** un nodo per VM, idealmente in **zone di disponibilità diverse**, con dischi separati.

### D2 — Ogni nodo con porta propria, uguale dentro e fuori dal container

- **Cosa:** porte 27101/27102/27103 sia come porta di ascolto di MongoDB (`--port`) sia come porta pubblicata.
- **Perché:** i client ricevono dal replica set l'elenco dei membri **con gli indirizzi registrati** e poi si collegano a quelli. Se le porte interne ed esterne fossero diverse, gli indirizzi non sarebbero raggiungibili dall'esterno.
- **Se non lo fai:** i client esterni si collegano al primo nodo ma falliscono subito dopo, tentando indirizzi irraggiungibili.
- **In produzione:** tutti i nodi possono usare la porta standard 27017, perché ciascuno ha un proprio indirizzo o nome.

### D3 — Utente admin creato solo sul nodo 1

- **Cosa:** `MONGO_INITDB_ROOT_*` e il secret solo nel servizio `mongo-rs1`.
- **Perché:** i nodi 2 e 3 partono vuoti e, alla formazione del replica set, copiano tutto dal nodo 1 (sincronizzazione iniziale), utente compreso. Verificato: login come admin riuscito sul nodo 2.
- **Se non lo fai:** tre database indipendenti con tre utenti admin, da riconciliare.
- **Conseguenza da ricordare:** il file della password esiste solo nel container del nodo 1 (§5.6).

### D4 — keyFile per l'autenticazione interna

- **Cosa:** file casuale (`openssl rand -base64 756`), identico su tutti i nodi, permessi `400`, owner 999, montato in sola lettura.
- **Perché:** i membri si riconoscono tra loro; un processo senza keyFile non può unirsi al replica set. Attiva anche l'obbligo di autenticazione per i client.
- **Se non lo fai:** con utenti e autenticazione attivi, MongoDB non accetta un replica set senza autenticazione interna.
- **Alternative:** certificati x.509 per l'autenticazione dei membri (da valutare con il TLS).
- **In produzione:** keyFile distribuito in modo sicuro a tutti i server, oppure x.509.

### D5 — Cache ridotta e tetto di memoria per nodo

- **Cosa:** `--wiredTigerCacheSizeGB 0.25` e `mem_limit: 1g`.
- **Perché:** di default ogni nodo userebbe circa metà della RAM per la cache; con tre nodi più l'istanza di sviluppo sulla stessa VM **senza swap**, si rischierebbe che Linux termini dei processi per mancanza di memoria.
- **In produzione:** nessun limite artificiale: ogni nodo ha la sua VM e usa la cache predefinita.

### D6 — `stop_grace_period: 1m`

- **Cosa:** Docker attende fino a un minuto lo spegnimento ordinato.
- **Perché:** un primario che riceve lo spegnimento cede il ruolo ed entra in *quiesce* fino a ~15 s; Docker di default termina il container dopo 10 s.
- **Se non lo fai:** osservato `Stopped 11.0s` e al riavvio `"Startup from clean shutdown?": false` (§5.4).
- **Verificato dopo la correzione:** stop in ~16 s, `clean shutdown: true`.
- **Esteso** anche ai compose delle guide 00 e 01 (istanza singola: rischio minore, nessuna controindicazione).

### D7 — `priority: 2` sul nodo 1

- **Cosa:** il nodo 1 è il primario preferito.
- **Perché:** nel laboratorio rende prevedibile chi è primario e mostra il rientro automatico del ruolo dopo un guasto.
- **Osservato:** dopo il riavvio, il nodo 1 torna prima `SECONDARY`, si rimette in pari, poi riprende il ruolo di primario.
- **In produzione:** si usa per tenere il primario nella zona/data center più vicino all'applicazione. Attenzione: ogni ripresa del ruolo è una breve elezione.

### D8 — Backup da un secondario con oplog

- **Cosa:** `mongodump` con `readPreference=secondary` e `--oplog`; ripristino con `mongorestore --oplogReplay --drop` attraverso la stringa del replica set.
- **Perché:** il backup non pesa sul primario; l'oplog rende la copia coerente a un unico istante anche con scritture in corso.
- **Password:** passata via standard input e scritta in un file di configurazione temporaneo dentro il container, perché il secret esiste solo sul nodo 1 (§5.6) e per non esporla nella lista dei processi.
- **Dimostrato:** il `drop` di una collezione si replica su tutti i nodi → **il replica set non è un backup**.
- **Da fare:** trasformare in script con destinazione protetta (non `/tmp`, §5.7).

### D9 — Accesso dall'esterno con nome DNS di Azure ed `extra_hosts`

- **Problema:** l'IP pubblico da solo non basta, perché il client usa poi i nomi dei membri registrati nel replica set.
- **Alternative valutate:**
  1. `directConnection=true` verso un singolo nodo: semplice, ma niente failover e scritture solo se quel nodo è primario;
  2. file `hosts` sul PC: funziona, ma richiede modifiche su ogni client (scartata su richiesta);
  3. membri registrati con l'IP pubblico: i nodi comunicherebbero passando dall'esterno, fragile (scartata);
  4. **nome DNS di Azure** (scelta).
- **Come funziona la scelta:** membri registrati come `<FQDN>:2710x`. Dal PC, `<FQDN>` si risolve con il DNS pubblico nell'IP pubblico → NSG → IP privato → Docker inoltra al nodo in base alla porta. Dentro i container, `extra_hosts` fa puntare `<FQDN>` all'IP privato, così i nodi si parlano restando nella VM.
- **Requisiti:** porte pubblicate anche su `<IP_PRIVATO_VM>`, regola NSG su 27101–27103 limitata all'IP del client.
- **Verificato:** `rs.initiate` accetta i nomi (ogni nodo riconosce se stesso passando dalla porta pubblicata), `Test-NetConnection` OK sulle tre porte, VS Code collegato con failover funzionante.
- **Rischio attuale:** traffico in chiaro fino all'attivazione del TLS.
- **In produzione:** ogni nodo ha un proprio nome DNS aziendale nella rete privata; i client sono nella stessa rete; se servono client esterni con indirizzi diversi, esistono gli *horizons* (richiedono TLS).

### D10 — Ricreare il replica set invece di rinominare i membri

- **Cosa:** `down -v` e nuovo `rs.initiate` con i nomi DNS.
- **Perché:** cambiare gli host dei membri di un replica set in esercizio è delicato; nel laboratorio c'erano solo dati di prova.
- **In produzione:** i nomi si scelgono **prima** della creazione; un eventuale cambio si fa con `rs.reconfig`, un membro alla volta, con backup.

### D11 — Manutenzione a rotazione

- **Cosa:** secondari uno alla volta (attendendo `SECONDARY` prima del successivo), poi `rs.stepDown(60)` sul primario, verifica della nuova elezione, riavvio del vecchio primario.
- **Perché:** il servizio resta sempre disponibile, tranne i secondi dell'elezione controllata. Riavviare due nodi insieme farebbe perdere la maggioranza.
- **Osservato:** un client collegato con la stringa del replica set (VS Code) ha mantenuto la connessione per tutta la sequenza, seguendo il primario nei suoi spostamenti.
- **Osservato:** anche senza `stepDown` il primario cede il ruolo da solo durante uno spegnimento ordinato (grazie a D6), ma lo `stepDown` esplicito permette di scegliere il momento e verificare l'elezione prima dello spegnimento.
- **In produzione:** stessa sequenza per aggiornamenti di versione, patch del sistema operativo, cambi di configurazione.

### D13 — TLS sul replica set: CA riusata, un certificato, EKU client+server

- **Cosa:** certificato dei nodi firmato con la **CA della guida 01**, un solo certificato per i tre nodi, SAN con `<FQDN>`, nomi dei container, `localhost`, `127.0.0.1`, IP privato; EKU `serverAuth,clientAuth`. Keyfile mantenuto per l'autenticazione interna.
- **Perché la stessa CA:** il `ca.pem` è già distribuito ai client (VS Code funziona senza nuovi file); in produzione è normale un'unica CA per tutti i server.
- **Perché un solo certificato:** nel laboratorio i tre nodi condividono lo stesso nome DNS.
- **Perché `clientAuth`:** quando un nodo si collega a un altro per replicare, presenta lo stesso certificato **come client**; con il solo `serverAuth` l'altro nodo lo rifiuterebbe e la replica si interromperebbe. Tipico motivo di fallimento del TLS sui replica set.
- **Alternative:** autenticazione dei membri con x.509 (`clusterAuthMode x509`) al posto del keyFile, da documentare come opzione di produzione.
- **In produzione:** un certificato per server, con il proprio nome DNS nel SAN; CA aziendale; eventuale x.509 per l'autenticazione dei membri; `tlsClusterFile` separato se si vogliono certificati diversi per client e membri.

### D14 — Migrazione al TLS a rotazione, senza fermo

- **Cosa:** tre fasi: `allowTLS` (con riavvio a rotazione dei nodi), `preferTLS` (a caldo, con `setParameter`), spostamento dei client, `requireTLS` (a caldo), poi compose aggiornato e ultima rotazione per rendere la modalità permanente.
- **Perché:** in ogni momento il replica set ha un primario e i client continuano a funzionare; i client si spostano al TLS uno alla volta durante `preferTLS`.
- **Da ricordare:** i parametri cambiati con `setParameter` **si perdono al riavvio**: la configurazione di avvio (compose) deve essere aggiornata alla fine; un nodo che ripartisse a metà migrazione tornerebbe alla modalità del compose (innocuo nelle fasi intermedie).
- **Ricreazione di un solo nodo:** `docker compose up -d <servizio>` ricrea solo quel servizio con la nuova configurazione.
- **Verifica della cifratura tra nodi:** `db.serverStatus().transportSecurity` conta le connessioni ricevute per versione TLS; le connessioni di replica già aperte vanno rinnovate (elezione con `stepDown`) prima di vedere i contatori salire.
- **In produzione:** stessa procedura, con finestre più lunghe in `preferTLS` per aggiornare tutte le applicazioni.

### D15 — Utente applicativo creato attraverso la stringa del replica set

- **Cosa:** `createUser` inviato con la stringa che elenca tutti i membri, invece che a un nodo specifico.
- **Perché:** la scrittura arriva sicuramente al primario, ovunque si trovi; da lì l'utente si replica.
- **Stringa per le applicazioni:** `authSource=labdb` (l'utente è definito in `labdb`), più `replicaSet`, `tls=true`, `tlsCAFile`.

### D16 — Script di backup dedicato al replica set

- **Cosa:** script separato da quello di sviluppo, con cartella e timer propri (03:00 UTC).
- **Perché le differenze rispetto alla guida 00:** stringa del replica set con `readPreference=secondaryPreferred` (legge da un secondario, ma non fallisce se sono tutti giù); `--oplog` per coerenza; TLS obbligatorio; `mongodump` eseguito nel **primo nodo acceso**, perché qualunque nodo può essere spento e il secret della password esiste solo nel nodo 1 (password passata via standard input).
- **Scritto in due parti:** prima parte con `<< EOF` (inserisce i valori veri di `$HOME` e `$FQDN`), seconda con `<< 'EOF'` (copiata letteralmente).
- **In produzione:** script su un server di amministrazione o su uno dei nodi; stessa logica; copia dei backup fuori dai server del database; eventualmente backup da un secondario "nascosto" (`hidden: true`, `priority: 0`) dedicato.

### D12 — Funzione di comodo `rs_eval` (solo laboratorio)

- **Cosa:** funzione bash che legge la password dal file e lancia `mongosh --eval` sul nodo scelto.
- **Perché:** evita di digitare la password a ogni comando.
- **Limite:** la password è visibile per un istante ai processi del container. Non adatta alla produzione.
- **Con il TLS:** dal Passo 14 la funzione include `--tls --tlsCAFile /etc/mongo/tls/ca.pem`; con `requireTLS` la versione senza TLS non funziona più.

---

## 5. Scoperte e inconvenienti

### 5.1 Blocco lungo rovinato durante l'incolla

- **Sintomo:** riga finale anomala come `EOF file: ./root_password.txtkeyfile:rort...`; il file compose risultava incompleto ma `compose valido` poteva comparire comunque.
- **Soluzione:** incollare in due parti (`cat >` e poi `cat >>`) oppure usare `nano`. Verificare sempre con `docker compose config --services` e `--volumes`.

### 5.2 Primo `rs.initiate` con `Authentication failed`

- **Causa:** password digitata in modo errato. Nessun effetto collaterale.

### 5.3 Messaggi normali all'avvio

- Nodo 1: prima avvio temporaneo su 27017 (creazione admin, `init process complete`), poi avvio definitivo su 27101.
- Nodi 2–3: `Did not find local replica set configuration document at startup` fino a `rs.initiate`.

### 5.4 Docker termina il primario dopo 10 secondi

- **Sintomo:** `Stopped 11.0s`; subito dopo il nodo risultava ancora `SECONDARY` (in *quiesce*); al riavvio `clean shutdown: false`.
- **Soluzione:** `stop_grace_period: 1m` (D6). Dopo: stop ~16 s, `clean shutdown: true`. Anche `down -v` dura ~17 s.

### 5.5 Stringa di connessione del replica set

- Il driver trova da solo il primario partendo dall'elenco dei membri; dopo un failover la stessa stringa continua a funzionare.
- Da MongoDB 5.0 il *write concern* predefinito è `majority`: `acknowledged: true` significa dato già su almeno due nodi.
- Leggere da un secondario richiede `readPreference`/`setReadPref("secondary")`; scrivere su un secondario → `not primary`.

### 5.6 Il secret della password esiste solo sul nodo 1

- **Conseguenza:** comandi lanciati negli altri container non trovano `/run/secrets/...`.
- **Soluzione adottata:** password passata dall'host via standard input (`read -r`).

### 5.7 File di backup in `/tmp` leggibile da altri utenti

- Nato con permessi `664`. Nella versione definitiva: cartella protetta come nella guida 00, `umask 077`.

### 5.8 Messaggi di `mongorestore` con oplog

- `don't know what to do with subdirectory ..., skipping...`: innocui con archivi che contengono l'oplog.
- `applied 0 oplog entries`: corretto se nessuno scriveva durante il backup.

### 5.9 Stringa di connessione incollata nel terminale della VM

- **Sintomo:** il `&` della stringa manda il comando in background (`[1] 12022`, `No such file or directory`).
- **Rischio:** la password resta nella cronologia di bash.
- **Soluzione:** `history | grep "mongodb://"` e `history -d <numero>`. La stringa va nel client (VS Code), non in bash.

### 5.10 Comandi incollati durante un riavvio lungo

- **Sintomo:** output mescolato (`[+] restart 0/1pDown(60)...`), lo `stepDown` non è stato eseguito, il primario è stato riavviato senza cedere prima il ruolo.
- **Perché è andata bene comunque:** spegnimento ordinato + `stop_grace_period` → il primario cede il ruolo da solo.
- **Regola per la guida:** i blocchi con `restart`/`sleep` si eseguono uno alla volta, aspettando il prompt. Il riavvio ora dura ~15 s: l'attesa va contata dalla fine del riavvio.

### 5.11 Funzione e variabili di sessione

- `rs_eval` e `$FQDN` esistono solo nella sessione in cui sono definite: in una nuova sessione vanno ridefinite (`rs_eval: command not found`).
- `rs_eval` senza numero interroga il nodo 1: se il nodo 1 è spento, usare `rs_eval '...' 2` (`container ... is not running`).

### 5.13 Client in chiaro durante `preferTLS`

- Durante `preferTLS` la vecchia connessione di VS Code senza TLS continuava a funzionare: è il comportamento previsto, la finestra per migrare i client. Con `requireTLS` viene rifiutata.
- Una stringa senza `replicaSet=rs0` funziona comunque: i driver scoprono i membri partendo da un solo indirizzo. Il parametro resta consigliato (verifica del nome del replica set). `directConnection=true` invece blocca su un solo nodo.

### 5.14 Contatori TLS

- Dopo `preferTLS` ed elezione forzata: `transportSecurity` con `'1.3'` tra 18 e 21 per nodo, `'1.0'`, `'1.1'`, `'1.2'` a zero (grazie anche a `--tlsDisabledProtocols`).

### 5.15 `applied 1 oplog entries` nel ripristino

- A differenza del Passo 9 (`applied 0`), qui l'oplog catturato durante il backup conteneva un'operazione. Un replica set registra operazioni anche in assenza di scritture dell'applicazione (per esempio scritture periodiche interne del primario), quindi durante un dump non è raro catturarne qualcuna. È la dimostrazione che `--oplog` / `--oplogReplay` funzionano.

### 5.12 Riconoscimento di sé con i nomi DNS

- Con i membri registrati come `<FQDN>:2710x`, `rs.initiate` ha funzionato: ogni nodo riconosce se stesso raggiungendo la propria porta attraverso l'IP privato e il proxy di Docker.

---

## 6. Laboratorio vs produzione

| Aspetto | Laboratorio | Produzione |
|---|---|---|
| Server | 3 container sulla stessa VM | 3 VM, zone di disponibilità diverse |
| Risorse | Cache 256 MB, `mem_limit` 1 GB per nodo | Cache predefinita, risorse dedicate |
| Nomi dei membri | Un nome DNS Azure + porte diverse, `extra_hosts` | Un nome DNS per nodo, DNS aziendale |
| Porte | 27101–27103 | 27017 su ogni nodo |
| Rete dei client | Da internet, NSG limitato a un IP | Rete privata (VNet, peering, VPN) |
| Cifratura | TLS obbligatorio (`requireTLS`), client e tra nodi | Idem |
| Certificati | Uno per tutti i nodi, CA privata della guida 01 | Uno per nodo, CA aziendale o pubblica |
| Autenticazione interna | keyFile | keyFile o x.509 |
| Password | File sulla VM, funzione `rs_eval` | Key Vault / gestore segreti |
| Backup | Manuale da secondario, in `/tmp` | Pianificato, cartella protetta, copia fuori dalla VM |
| Guasto della VM | Cade tutto il replica set | Cade un solo nodo, il servizio continua |

---

## 7. Comandi utili del laboratorio

```bash
cd ~/mongo-lab/02-replica-set

# Funzione di comodo con TLS (da ridefinire in ogni sessione)
rs_eval() {
  local node=${2:-1}
  sudo docker exec -i -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs$node \
    sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 2710'"$node"' -u admin -p "$RS_PWD" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}

# Modalità TLS di ogni nodo e connessioni cifrate ricevute
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
for n in 1 2 3; do rs_eval 'printjson(db.serverStatus().transportSecurity)' $n; done

# Stato dei membri (dal nodo 2, utile se il nodo 1 è spento)
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr, "salute:", m.health))' 2

# Spegnimento ordinato riuscito?
sudo docker compose logs mongo-rs1 | grep -o '"Startup from clean shutdown?":[a-z]*' | tail -1

# Cedere il ruolo di primario
rs_eval 'rs.stepDown(60); print("fatto")'
```

Dal PC (PowerShell):

```powershell
Resolve-DnsName <FQDN>
27101..27103 | ForEach-Object { Test-NetConnection <FQDN> -Port $_ | Select-Object RemotePort, TcpTestSucceeded }
```

Stringa di connessione (client esterno):

```
mongodb://admin:PASSWORD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/?replicaSet=rs0&authSource=admin&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

---

## 8. Da fare

- [x] Confermare il ritorno del nodo 1 a `PRIMARY` dopo lo `stepDown` (fine Passo 11): confermato, dopo il periodo di 60 s il nodo 1 è tornato primario.
- [x] Confermare il comportamento di VS Code durante la manutenzione a rotazione: confermato, la connessione ha retto per tutta la sequenza.
- [x] **TLS tra i nodi e verso i client**, attivato con migrazione a rotazione (`allowTLS` → `preferTLS` → `requireTLS`), riusando la CA della guida 01 e un certificato con `<FQDN>` nel SAN.
- [ ] Valutare (e documentare come opzione) l'autenticazione x.509 dei membri.
- [x] Script di backup per il replica set, con cartella protetta e timer, con TLS: fatto (Passi 17–19).
- [ ] Eliminare da VS Code la vecchia connessione del laboratorio senza TLS.
- [x] ~~Cambiare la password del laboratorio~~: non necessario per il laboratorio (dati di prova, ambiente da smantellare). Nella guida: indicare come si cambia una password su un replica set (`db.changeUserPassword` sul primario, replicato automaticamente) e raccomandarlo in produzione se una password viene esposta.
- [x] Rimuovere `/tmp/rs-backup.archive.gz`: fatto.
- [x] Confermare `stop_grace_period` sul MongoDB di sviluppo: confermato.
- [x] Preparare `config/02-replica-set/`: fatto (compose senza e con TLS, script di backup con controllo dei segnaposto, unità systemd, `server.ext.example`).
- [x] Verificare la prima esecuzione notturna reale del backup di sviluppo con TLS attivo: `Backup completato` alle 02:30 del 29/09.

---

## 9. Note per la stesura delle guide

- Struttura per ogni scelta: cosa / perché / se non lo fai / alternative / in produzione.
- Tabella finale "Laboratorio vs produzione" (§6).
- Sezione concetti iniziale: replica set, primario/secondari, oplog, heartbeat, elezione e maggioranza, numero dispari di nodi, stringa di connessione con `replicaSet`, write concern e read preference, "il replica set non è un backup", legame con lo sharding.
- Avvisi ricorrenti: guardare il prompt prima di ogni `docker compose` (due progetti sulla stessa VM), mai `down -v` nella cartella sbagliata, blocchi lunghi da incollare in parti, comandi con `restart` uno alla volta.
- Nessun dato reale negli esempi (nomi, email, IP, password): solo segnaposto.
