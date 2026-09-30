# Sharding MongoDB in Docker — Guida completa passo passo

**Per chi è questa guida:** per chi ha seguito le guide 00–02 e vuole imparare a costruire e usare un **cluster con sharding**: router, config server, shard, shard key, bilanciatore, backup. Come nelle guide precedenti, ogni passaggio spiega **cosa fare**, **cosa fa il comando** e **cosa devi vedere**, e ogni scelta è accompagnata da un riquadro 🧭 che distingue ciò che facciamo **nel laboratorio** da ciò che si sceglie **in produzione**.

**Cosa otterrai alla fine:**

- un cluster completo di dieci processi: tre config server, due shard da tre nodi ciascuno, un router;
- due collezioni distribuite, una con shard key hashed e una a intervalli, per vedere con i tuoi occhi pregi e difetti di ciascuna;
- il bilanciatore al lavoro, le query mirate a un solo shard e quelle che li interrogano tutti;
- TLS su tutte le comunicazioni, accesso da VS Code con una sola porta, un utente applicativo;
- backup notturni automatici e una procedura di ripristino collaudata.

**Tempo stimato:** 3 ore.

**Prerequisiti:** guida 00 (Docker, impostazioni del kernel), guida 01 (la CA privata in `~/mongodb/tls`), guida 02 consigliata (i replica set sono il mattone di questo cluster, e lì sono spiegati in dettaglio).

**Stato di verifica:** tutti i passaggi sono stati eseguiti e collaudati su un'installazione reale, tranne quelli segnati con 🧪 (ripristino degli utenti dal backup, retention settimanale/mensile su un periodo reale).

> 📖 **Comandi e simboli** (`sudo`, `chmod`, `|`, `<< EOF`, `docker compose`…): la [legenda dei comandi](legenda-comandi-linux.md) spiega tutto ciò che compare in questa guida.

---

## Indice

- [Parte 0 — Concetti](#parte-0--concetti)
- [Parte 1 — Il laboratorio e lo scenario reale](#parte-1--il-laboratorio-e-lo-scenario-reale)
- [Parte 2 — Preparare la VM](#parte-2--preparare-la-vm)
- [Parte 3 — Costruire il cluster](#parte-3--costruire-il-cluster)
- [Parte 4 — Inizializzare i replica set](#parte-4--inizializzare-i-replica-set)
- [Parte 5 — Utenti e funzioni di comodo](#parte-5--utenti-e-funzioni-di-comodo)
- [Parte 6 — Registrare gli shard](#parte-6--registrare-gli-shard)
- [Parte 7 — La dimensione dei chunk](#parte-7--la-dimensione-dei-chunk)
- [Parte 8 — Shard key hashed](#parte-8--shard-key-hashed)
- [Parte 9 — Query mirate e query su tutti gli shard](#parte-9--query-mirate-e-query-su-tutti-gli-shard)
- [Parte 10 — Shard key a intervalli e lo shard caldo](#parte-10--shard-key-a-intervalli-e-lo-shard-caldo)
- [Parte 11 — Il bilanciatore](#parte-11--il-bilanciatore)
- [Parte 12 — Un guasto dentro uno shard](#parte-12--un-guasto-dentro-uno-shard)
- [Parte 13 — TLS](#parte-13--tls)
- [Parte 14 — Accesso dal tuo PC](#parte-14--accesso-dal-tuo-pc)
- [Parte 15 — Utente applicativo](#parte-15--utente-applicativo)
- [Parte 16 — Backup e ripristino](#parte-16--backup-e-ripristino)
- [Parte 17 — Uso quotidiano](#parte-17--uso-quotidiano)
- [Parte 18 — Riaccendere le altre istanze o smantellare il laboratorio](#parte-18--riaccendere-le-altre-istanze-o-smantellare-il-laboratorio)
- [Parte 19 — Quando qualcosa va storto](#parte-19--quando-qualcosa-va-storto)
- [Parte 20 — Laboratorio e produzione](#parte-20--laboratorio-e-produzione)
- [Appendice A — Dove si trova ogni cosa](#appendice-a--dove-si-trova-ogni-cosa)
- [Appendice B — Promemoria dei comandi](#appendice-b--promemoria-dei-comandi)
- [Le 10 regole d'oro dello sharding](#le-10-regole-doro-dello-sharding)

> **Convenzioni:** come nelle guide precedenti (📍 dove eseguire, ✅ cosa devi vedere, blocchi `<< EOF` da incollare per intero, segnaposto `<...>` da sostituire togliendo anche `<` e `>`). Segnaposto di questa guida: `<IP_PRIVATO_VM>` (es. `10.0.0.4`), `<FQDN>` (nome DNS della VM, guida 02 Parte 2.2), `<tuo-nome>` (utente Windows).

> **I riquadri 🧭** hanno sempre la stessa struttura: **nel laboratorio** (cosa facciamo), **perché** (quasi sempre un vincolo del laboratorio: una sola VM, poca memoria, altre istanze da preservare), **se non lo fai**, **in produzione** (cosa scegliere in un ambiente reale). **Non copiare in produzione le scelte di laboratorio.**

---

## Parte 0 — Concetti

### 0.1 Perché lo sharding

Un replica set (guida 02) **copia** gli stessi dati su più server: protegge dai guasti, ma ogni server deve contenere **tutti** i dati e reggere **tutte** le scritture. Quando i dati o le scritture superano ciò che un singolo server può gestire, lo sharding **divide** i dati di una collezione tra più gruppi di server, detti **shard**. L'applicazione continua a vedere un'unica collezione.

### 0.2 I componenti

| Componente | Cosa fa | Nel nostro cluster |
|---|---|---|
| **Shard** | Contiene una parte dei dati. È sempre un replica set | `sh1` e `sh2`, tre nodi ciascuno |
| **Config server** | Contiene la mappa del cluster: quali dati stanno su quale shard, gli utenti del cluster. È un replica set | `cfgrs`, tre nodi |
| **Router (`mongos`)** | L'unico punto a cui si collegano le applicazioni. Legge la mappa e manda ogni richiesta agli shard giusti. Non contiene dati | `mongo-router` |

**Ogni shard e i config server sono replica set:** tutto ciò che hai visto nella guida 02 (elezioni, failover, keyFile) vale per ciascuno di loro.

### 0.3 Shard key e chunk

Per decidere dove va ogni documento, MongoDB usa un campo scelto per ogni collezione: la **shard key**. I valori della shard key sono divisi in **intervalli**, detti **chunk**, e ogni intervallo è assegnato a uno shard.

Ci sono due strategie:

- **Hashed:** MongoDB applica un hash al valore della chiave, e distribuisce in base all'hash. I documenti si spargono uniformemente, ma valori vicini finiscono su shard diversi.
- **A intervalli (ranged):** i valori vicini stanno sullo stesso shard. Ottima per le query per intervallo, ma rischiosa con chiavi che crescono sempre (date, contatori): tutte le scritture nuove finiscono sull'ultimo intervallo, cioè su un solo shard (*shard caldo*).

Lo vedremo concretamente nelle Parti 8–10.

> **Un chiarimento sui chunk.** È facile immaginarli come "contenitori" di dimensione fissa. Nelle versioni recenti di MongoDB è più corretto pensarli come **intervalli di valori assegnati a uno shard**: non vengono più divisi automaticamente man mano che crescono, il bilanciatore li divide quando deve spostare dati, e un meccanismo automatico riunisce gli intervalli contigui dello stesso shard. Il loro numero varia nel tempo e conta poco: conta **quanti dati** ha ogni shard.

### 0.4 Il bilanciatore

Un processo interno controlla continuamente se gli shard hanno quantità di dati simili. Se la differenza supera una soglia (circa tre volte la dimensione di riferimento dei chunk), sposta intervalli dallo shard più pieno a quello più vuoto: è una **migrazione**. Dopo la migrazione, lo shard di origine non cancella subito i documenti spostati: li tiene per un po' come **documenti orfani** (Parte 10).

### 0.5 Query mirate e query su tutti gli shard

Il router guarda la query: se contiene la shard key, sa su quale shard stanno i dati e interroga **solo quello** (*query mirata*). Se non la contiene, deve interrogare **tutti** gli shard e unire i risultati (*scatter-gather*). Con due shard la differenza è piccola; con cinquanta shard, ogni query senza shard key coinvolge tutto il cluster. **La shard key si sceglie guardando le query più frequenti dell'applicazione.**

### 0.6 Quando serve davvero

Lo sharding ha un costo alto: in produzione servono una decina di server, e backup, monitoraggio e manutenzione diventano più complessi. Si adotta quando un singolo replica set, ben dimensionato, non basta più. Prima di arrivarci conviene valutare un server più grande, indici migliori, o un servizio gestito.

---

## Parte 1 — Il laboratorio e lo scenario reale

### 1.1 La topologia

| Componente | Replica set | Container | Porta |
|---|---|---|---|
| Config server | `cfgrs` | `mongo-cfg1`, `mongo-cfg2`, `mongo-cfg3` | 27201–27203 |
| Shard 1 | `sh1` | `mongo-sh1a`, `mongo-sh1b`, `mongo-sh1c` | 27211–27213 |
| Shard 2 | `sh2` | `mongo-sh2a`, `mongo-sh2b`, `mongo-sh2c` | 27221–27223 |
| Router | — | `mongo-router` | 27200 (unica porta pubblicata) |

> 🧭 **Topologia completa su una sola VM**
>
> **Nel laboratorio:** i dieci processi di un cluster di produzione, in dieci container sulla stessa VM.
>
> **Alternative valutate:** A) cluster ridotto con replica set da un solo nodo (4 container, ~2 GB): economico, ma lontano dalla produzione; B) cluster completo liberando memoria (**scelta**); C) cluster completo ingrandendo la VM (costo e riavvio).
>
> **Perché:** è l'unico modo di vedere la vera struttura senza costi aggiuntivi. Con cache ridotta, dieci processi usano 1,2 GB a riposo e circa 2,5 GB dopo il caricamento dei dati di prova (valori misurati).
>
> **In produzione:** ogni processo su un server dedicato. **Config server:** tre VM piccole (contengono solo metadati), in zone di disponibilità diverse. **Shard:** tre VM per shard, dimensionate sui dati (RAM per il *working set*, dischi veloci XFS), in zone diverse. **Router:** di solito uno per ogni server applicativo, oppure un gruppo dietro bilanciamento: sono leggeri e senza stato. Valutare un servizio gestito se il costo operativo è eccessivo.

### 1.2 Tre progetti sulla stessa VM

Sulla VM ci sono ora tre progetti Docker Compose: `~/mongodb` (sviluppo), `~/mongo-lab/02-replica-set` e `~/mongo-lab/03-sharding`.

> ⚠️ **Guarda il prompt prima di ogni `docker compose`**: agisce sul progetto della cartella corrente, e un `down -v` nella cartella sbagliata cancella i dati di un altro progetto.

---

## Parte 2 — Preparare la VM

> 📍 **Sulla VM.**

### 2.1 Spegnere le altre istanze

Il MongoDB di sviluppo (fino a ~3,5 GB) e il replica set della guida 02 (fino a 3 GB) non lasciano spazio a dieci processi. Li **spegniamo senza eliminarli**, e sospendiamo i loro backup notturni, che altrimenti fallirebbero non trovando i container:

```bash
cd ~/mongodb && sudo docker compose stop
sudo systemctl disable --now mongo-backup.timer
cd ~/mongo-lab/02-replica-set && sudo docker compose stop
sudo systemctl disable --now mongo-rs-backup.timer
sudo docker ps
```

✅ `docker ps` non elenca container in esecuzione. Nel collaudo l'istanza di sviluppo si è fermata in 1 secondo, i nodi del replica set in circa 16 (la fase di *quiesce* della guida 02).

> 🧭 **Spegnere, non eliminare**
>
> **Perché:** dati, utenti, certificati e configurazione restano nei volumi; si riaccende con un comando (Parte 18). L'istanza di sviluppo contiene i dati dell'applicazione.
>
> **Conseguenze:** l'applicazione e le connessioni di VS Code verso lo sviluppo non funzionano finché resta spento. Con `restart: unless-stopped`, un container fermato a mano **resta spento anche dopo un riavvio della VM**.
>
> **In produzione:** un cluster con sharding non condivide mai i server con altri database; nessuna istanza va spenta per fargli spazio.

### 2.2 Lo swap: una rete di sicurezza

**Cos'è.** Quando la RAM si esaurisce, senza swap Linux attiva l'**OOM killer** (*Out Of Memory*), che termina d'autorità un processo: con dieci nodi MongoDB, quasi certamente uno di loro, spento di colpo come per un'interruzione di corrente. Con lo **swap**, Linux sposta su disco le parti di memoria usate meno di recente: il sistema rallenta, ma nessun processo viene ucciso.

**Non è RAM in più.** Il disco è molto più lento della memoria: se un sistema usa lo swap di continuo, le prestazioni crollano. Serve ad assorbire i **picchi**, come il caricamento dei dati o le migrazioni del bilanciatore.

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
sudo swapon --show
```

| Comando | Cosa fa |
|---|---|
| `fallocate -l 4G /swapfile` | Crea un file di 4 GB riservando lo spazio sul disco |
| `chmod 600 /swapfile` | Solo root può leggerlo: lo swap può contenere dati in memoria, anche password |
| `mkswap /swapfile` | Lo prepara come area di swap |
| `swapon /swapfile` | Lo attiva subito |
| Riga in `/etc/fstab` | Lo riattiva a ogni avvio |

✅ In `free -h` la riga `Swap: 4.0Gi`, e `swapon --show` elenca `/swapfile` (la colonna `PRIO -2` è la priorità automatica: ignorala).

> ⚠️ `swapon --show` **senza `sudo`** risponde `command not found`: su Debian i comandi di amministrazione stanno in `/usr/sbin`, fuori dal percorso degli utenti normali. Lo stesso vale per `mkswap` e `swapoff`.

> 🧭 **Swap da 4 GB sul disco di sistema**
>
> **Perché:** 4 GB bastano per i picchi e occupano 4 dei circa 58 GB liberi. Nel collaudo, dopo il caricamento di 300.000 documenti, lo swap è rimasto a **zero**: la rete di sicurezza non è mai servita.
>
> **Alternativa su Azure:** il disco temporaneo della VM (`/mnt`), più veloce, ma cancellato quando la VM viene spostata o deallocata, e più articolato da configurare.
>
> **In produzione:** la RAM si dimensiona sul *working set* (dati e indici usati di frequente); lo swap resta piccolo, solo protezione, e se il suo uso cresce è un segnale di sottodimensionamento da monitorare.

---

## Parte 3 — Costruire il cluster

### 3.1 Cartella, keyFile e password

```bash
mkdir -p ~/mongo-lab/03-sharding
cd ~/mongo-lab/03-sharding

openssl rand -base64 756 > keyfile
sudo chown 999:999 keyfile && sudo chmod 400 keyfile

openssl rand -base64 24 | tr -d '/+=' | sudo tee root_password.txt > /dev/null
sudo chmod 600 root_password.txt

PRIV_IP=<IP_PRIVATO_VM>
echo "IP privato: $PRIV_IP"
ls -l
```

✅ `keyfile` con `-r--------` dell'utente 999; `root_password.txt` con `-rw-------` di root.

> 🧭 **Un keyFile condiviso da tutti i dieci processi**
>
> **Perché:** router, config server e shard devono riconoscersi tra loro, esattamente come i membri di un replica set (guida 02). La password, questa volta, **non** viene montata nei container: la passeremo al momento di creare gli utenti.
>
> **In produzione:** keyFile distribuito in modo sicuro su tutti i server, oppure (preferibile su cluster grandi) certificati x.509 per l'autenticazione dei membri.

### 3.2 Il docker-compose.yml, in quattro parti

Il file è lungo: lo scriviamo in quattro parti corte (la prima con `>` crea il file, le altre con `>>` lo completano). Le prime tre usano `<< 'EOF'` (copiate alla lettera), l'ultima `<< EOF` (inserisce il valore di `$PRIV_IP`, impostato al passo precedente nella stessa sessione).

**Parte A — impostazioni comuni e config server:**

```bash
cat > docker-compose.yml << 'EOF'
name: mongo-lab-sh

x-mongod: &mongod
  image: mongo:8.0
  restart: unless-stopped
  stop_grace_period: 1m
  mem_limit: 640m
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
  mongo-cfg1:
    <<: *mongod
    container_name: mongo-cfg1
    hostname: mongo-cfg1
    command: ["mongod", "--configsvr", "--replSet", "cfgrs", "--port", "27201", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - cfg1-data:/data/configdb
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-cfg2:
    <<: *mongod
    container_name: mongo-cfg2
    hostname: mongo-cfg2
    command: ["mongod", "--configsvr", "--replSet", "cfgrs", "--port", "27202", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - cfg2-data:/data/configdb
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-cfg3:
    <<: *mongod
    container_name: mongo-cfg3
    hostname: mongo-cfg3
    command: ["mongod", "--configsvr", "--replSet", "cfgrs", "--port", "27203", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - cfg3-data:/data/configdb
      - ./keyfile:/etc/mongo/keyfile:ro
EOF
```

> Con `--configsvr` MongoDB salva i dati in `/data/configdb` invece di `/data/db`: per questo i volumi dei config server sono montati lì.

**Parte B — shard 1:**

```bash
cat >> docker-compose.yml << 'EOF'

  mongo-sh1a:
    <<: *mongod
    container_name: mongo-sh1a
    hostname: mongo-sh1a
    command: ["mongod", "--shardsvr", "--replSet", "sh1", "--port", "27211", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - sh1a-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-sh1b:
    <<: *mongod
    container_name: mongo-sh1b
    hostname: mongo-sh1b
    command: ["mongod", "--shardsvr", "--replSet", "sh1", "--port", "27212", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - sh1b-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-sh1c:
    <<: *mongod
    container_name: mongo-sh1c
    hostname: mongo-sh1c
    command: ["mongod", "--shardsvr", "--replSet", "sh1", "--port", "27213", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - sh1c-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro
EOF
```

**Parte C — shard 2:**

```bash
cat >> docker-compose.yml << 'EOF'

  mongo-sh2a:
    <<: *mongod
    container_name: mongo-sh2a
    hostname: mongo-sh2a
    command: ["mongod", "--shardsvr", "--replSet", "sh2", "--port", "27221", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - sh2a-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-sh2b:
    <<: *mongod
    container_name: mongo-sh2b
    hostname: mongo-sh2b
    command: ["mongod", "--shardsvr", "--replSet", "sh2", "--port", "27222", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - sh2b-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-sh2c:
    <<: *mongod
    container_name: mongo-sh2c
    hostname: mongo-sh2c
    command: ["mongod", "--shardsvr", "--replSet", "sh2", "--port", "27223", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25", "--bind_ip_all"]
    volumes:
      - sh2c-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro
EOF
```

**Parte D — router e volumi** (`<< EOF` senza apici):

```bash
cat >> docker-compose.yml << EOF

  mongo-router:
    image: mongo:8.0
    container_name: mongo-router
    hostname: mongo-router
    restart: unless-stopped
    stop_grace_period: 1m
    mem_limit: 384m
    user: "999:999"
    command: ["mongos", "--configdb", "cfgrs/mongo-cfg1:27201,mongo-cfg2:27202,mongo-cfg3:27203", "--port", "27200", "--keyFile", "/etc/mongo/keyfile", "--bind_ip_all"]
    ports:
      - "127.0.0.1:27200:27200"
      - "$PRIV_IP:27200:27200"
    volumes:
      - ./keyfile:/etc/mongo/keyfile:ro
    depends_on:
      - mongo-cfg1
      - mongo-cfg2
      - mongo-cfg3

volumes:
  cfg1-data:
  cfg2-data:
  cfg3-data:
  sh1a-data:
  sh1b-data:
  sh1c-data:
  sh2a-data:
  sh2b-data:
  sh2c-data:
EOF
```

### 3.3 Verificare il file

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose config --services | wc -l
sudo docker compose config --volumes | wc -l
sudo docker compose config | grep -c "target: /etc/mongo/keyfile"
grep -A2 "ports:" docker-compose.yml
```

✅ `compose valido`, **10** servizi, **9** volumi, **10** montaggi del keyFile, e sotto `ports` le righe con `127.0.0.1` e con il tuo IP privato vero.

> ⚠️ **Righe mescolate durante l'incolla.** Nel collaudo, alla fine della Parte A comparivano righe come `EOF   - ./keyfile:/etc/mongo/keyfile:ro`, che facevano pensare a un file rovinato. Era solo un difetto di **visualizzazione** del terminale: il file era integro. Nella guida 02 invece, in un caso simile, il file era davvero incompleto. Quindi non fidarti né dell'aspetto né di `compose valido`: il conteggio dei montaggi del keyFile verifica **ogni** servizio, mentre quello dei volumi no (i volumi sono dichiarati in fondo al file). Per controllare un servizio specifico: `grep -n -A6 "container_name: mongo-cfg3" docker-compose.yml`. In alternativa all'incolla, `nano` evita il problema.

| Elemento | Significato |
|---|---|
| `--configsvr` | Il nodo è un config server |
| `--shardsvr` | Il nodo fa parte di uno shard |
| `mongos --configdb cfgrs/...` | Il router, con l'indirizzo dei config server |
| `mem_limit` 640m / 384m, cache 256 MB | Limiti di laboratorio per stare nella memoria della VM |
| `user: "999:999"` sul router | Il router gira come utente non privilegiato; non ha dati propri |
| Porte solo per il router | Config server e shard non sono raggiungibili dall'esterno di Docker |

> 🧭 **Membri registrati con i nomi dei container, una sola porta pubblicata**
>
> **Perché (differenza rispetto alla guida 02):** i client parlano **solo con il router**, che contatta config server e shard dentro la rete Docker. Il problema dei nomi dei membri non raggiungibili dall'esterno, che nella guida 02 ha richiesto il nome DNS ed `extra_hosts`, qui non esiste.
>
> **In produzione:** i nodi hanno comunque **nomi DNS interni stabili**, scelti prima dell'inizializzazione, perché i config server memorizzano gli indirizzi degli shard. Config server e shard stanno in una subnet raggiungibile solo dai router e dagli strumenti di amministrazione; i router solo dagli application server.

### 3.4 Avvio

```bash
cd ~/mongo-lab/03-sharding
sudo docker compose up -d
sleep 20
sudo docker compose ps --format "table {{.Name}}\t{{.Status}}"
sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
sudo docker compose logs mongo-router --tail 5
```

✅ Dieci container in esecuzione, circa **110 MiB** per nodo e 86 MiB per il router (valori del collaudo).

Nei log del router compaiono messaggi come `Could not find host matching read preference ... for set cfgrs` e `Error loading global settings from config server. Sleeping for 2 seconds and retrying`. **È normale:** il router cerca il primario dei config server, che ancora non esiste, e riprova ogni due secondi. Non va in errore e non si riavvia: si collegherà da solo dopo la Parte 4.

---

## Parte 4 — Inizializzare i replica set

Finché non esiste alcun utente, MongoDB accetta i comandi di amministrazione collegandosi **dalla stessa macchina**: è la *localhost exception*. Per questo i comandi seguenti non chiedono password.

**Config server** (nota `configsvr: true`):

```bash
sudo docker exec mongo-cfg1 mongosh --port 27201 --quiet --eval '
rs.initiate({ _id: "cfgrs", configsvr: true, members: [
  { _id: 0, host: "mongo-cfg1:27201" },
  { _id: 1, host: "mongo-cfg2:27202" },
  { _id: 2, host: "mongo-cfg3:27203" } ] })'
```

**Shard 1:**

```bash
sudo docker exec mongo-sh1a mongosh --port 27211 --quiet --eval '
rs.initiate({ _id: "sh1", members: [
  { _id: 0, host: "mongo-sh1a:27211" },
  { _id: 1, host: "mongo-sh1b:27212" },
  { _id: 2, host: "mongo-sh1c:27213" } ] })'
```

**Shard 2:**

```bash
sudo docker exec mongo-sh2a mongosh --port 27221 --quiet --eval '
rs.initiate({ _id: "sh2", members: [
  { _id: 0, host: "mongo-sh2a:27221" },
  { _id: 1, host: "mongo-sh2b:27222" },
  { _id: 2, host: "mongo-sh2c:27223" } ] })'
```

✅ Tre volte `{ ok: 1 }`.

**Verifica** (dopo una ventina di secondi; `db.hello()` funziona anche senza autenticazione):

```bash
for c in "mongo-cfg1 27201" "mongo-sh1a 27211" "mongo-sh2a 27221"; do
  set -- $c
  sudo docker exec $1 mongosh --port $2 --quiet --eval 'print(db.hello().setName, "- primario:", db.hello().primary)'
done
sudo docker compose logs mongo-router --tail 3
```

✅ Il primario di ciascun replica set, di solito il nodo su cui hai lanciato `rs.initiate`. Nei log del router compare `Updating the shard registry with confirmed replica set ... cfgrs/...`: ha trovato i config server.

---

## Parte 5 — Utenti e funzioni di comodo

### 5.1 Due tipi di utenti

| Tipo | Dove si crea | Dove vive | A cosa serve |
|---|---|---|---|
| **Utenti del cluster** | Attraverso il router | Nei config server | Tutto ciò che passa dal router: amministrazione, applicazioni |
| **Utenti locali degli shard** | Sul primario di ogni shard | Solo nei nodi di quello shard | Manutenzione diretta dei nodi di uno shard |

### 5.2 Amministratori locali degli shard

Sul primario di ciascuno shard, con la localhost exception (se il primario non è il nodo `a`, cambia contenitore e porta):

```bash
cd ~/mongo-lab/03-sharding
for c in "mongo-sh1a 27211" "mongo-sh2a 27221"; do
  set -- $c
  sudo docker exec -i -e P="$(sudo cat root_password.txt)" $1 \
    sh -c 'mongosh --port '"$2"' --quiet --eval "db.getSiblingDB(\"admin\").createUser({ user: \"admin\", pwd: process.env.P, roles: [\"root\"] })"'
done
```

✅ Due volte `{ ok: 1 }`.

### 5.3 Amministratore del cluster

```bash
sudo docker exec -i -e P="$(sudo cat root_password.txt)" mongo-router \
  sh -c 'mongosh --port 27200 --quiet --eval "db.getSiblingDB(\"admin\").createUser({ user: \"admin\", pwd: process.env.P, roles: [\"root\"] })"'
```

✅ `{ ok: 1, ... }`.

> 🧭 **Utenti creati con la localhost exception, niente `MONGO_INITDB_*`**
>
> **Perché:** in un cluster gli utenti si creano attraverso il router; l'inizializzazione automatica dell'immagine Docker vale solo per un `mongod`. La localhost exception si chiude da sola appena esiste un utente.
>
> **Nel laboratorio** i tre amministratori hanno la stessa password, per semplicità. **In produzione:** password diverse, in un gestore di segreti, e utenti applicativi con ruoli minimi.

### 5.4 Funzioni di comodo, salvate in un file

Come `rs_eval` nella guida 02, due funzioni evitano di digitare la password a ogni comando. Questa volta le salviamo in un **file**, perché le funzioni spariscono a ogni riconnessione alla VM:

```bash
cat > ~/mongo-lab/03-sharding/funzioni-lab.sh << 'EOF'
# Funzioni di comodo del laboratorio 03 (caricare con: source ~/mongo-lab/03-sharding/funzioni-lab.sh)
sh_eval() {
  sudo docker exec -i -e P="$(sudo cat ~/mongo-lab/03-sharding/root_password.txt)" mongo-router \
    sh -c 'mongosh --port 27200 -u admin -p "$P" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}
node_eval() {
  sudo docker exec -i -e P="$(sudo cat ~/mongo-lab/03-sharding/root_password.txt)" "$1" \
    sh -c 'mongosh --port '"$2"' -u admin -p "$P" --authenticationDatabase admin --quiet --eval "$0"' "$3"
}
EOF
source ~/mongo-lab/03-sharding/funzioni-lab.sh

sh_eval 'print("Collegato al router, versione", db.version())'
node_eval mongo-sh1a 27211 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
node_eval mongo-cfg1 27201 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

✅ La versione del server (8.0.x), poi un `PRIMARY` e due `SECONDARY` per lo shard 1 e per i config server. L'ultimo comando è istruttivo: sui config server l'utente `admin` non l'abbiamo mai creato direttamente, ma attraverso il router, che l'ha salvato lì.

Uso: `sh_eval 'js'` sul router; `node_eval <container> <porta> 'js'` su un nodo specifico.

**Dopo ogni riconnessione** (altrimenti: `sh_eval: command not found`):

```bash
source ~/mongo-lab/03-sharding/funzioni-lab.sh
```

**Per caricarle in automatico** a ogni accesso, aggiungi la riga a `~/.bashrc`, il file che bash esegue all'apertura di ogni sessione:

```bash
echo 'source ~/mongo-lab/03-sharding/funzioni-lab.sh' >> ~/.bashrc
```

Allo smantellamento del laboratorio va tolta (Parte 18). Il file delle funzioni non contiene la password: la legge ogni volta da `root_password.txt`. **Solo laboratorio:** la password è visibile per un istante ai processi del container.

---

## Parte 6 — Registrare gli shard

```bash
sh_eval 'printjson(sh.addShard("sh1/mongo-sh1a:27211,mongo-sh1b:27212,mongo-sh1c:27213"))'
sh_eval 'printjson(sh.addShard("sh2/mongo-sh2a:27221,mongo-sh2b:27222,mongo-sh2c:27223"))'
sh_eval 'db.adminCommand({ listShards: 1 }).shards.forEach(s => print(s._id, s.host, "stato:", s.state))'
sh_eval 'sh.status()'
```

✅ Due volte `shardAdded` con `ok: 1`, i due shard con `stato: 1`, e `sh.status()` che funziona: nella guida 02 lo stesso comando falliva, perché lì parlavamo con un replica set.

**Come leggere `sh.status()`:**

| Sezione | Contenuto |
|---|---|
| `shards` | Gli shard registrati, con i membri |
| `active mongoses` | I router attivi e la loro versione |
| `autosplit` | Mostrato per compatibilità; nelle versioni recenti la divisione è gestita dal bilanciatore |
| `balancer` | Abilitato, in esecuzione, esiti delle ultime migrazioni |
| `shardedDataDistribution` | Dati per shard delle collezioni distribuite |
| `databases` | Database e loro shard primario |

---

## Parte 7 — La dimensione dei chunk

Il bilanciatore sposta dati quando la differenza tra gli shard supera circa **tre volte** la dimensione di riferimento dei chunk, che per impostazione predefinita è 128 MB. Con i pochi MB del laboratorio non vedremmo mai una migrazione. La riduciamo a 1 MB:

```bash
sh_eval 'db.getSiblingDB("config").settings.updateOne({ _id: "chunksize" }, { $set: { value: 1 } }, { upsert: true }); printjson(db.getSiblingDB("config").settings.findOne({ _id: "chunksize" }))'
```

✅ `{ _id: 'chunksize', value: 1 }`.

> 🧭 **Chunk da 1 MB — solo laboratorio.** In produzione si lascia il valore predefinito: valori piccoli significano migrazioni continue e un carico inutile sul cluster.

---

## Parte 8 — Shard key hashed

```bash
sh_eval 'sh.enableSharding("labdb"); printjson(sh.shardCollection("labdb.ordini", { clienteId: "hashed" }))'
```

✅ `collectionsharded: 'labdb.ordini'`.

**200.000 ordini di prova** (circa un minuto):

```bash
sh_eval '
const c = db.getSiblingDB("labdb").ordini;
for (let b = 0; b < 20; b++) {
  const docs = [];
  for (let i = 0; i < 10000; i++) {
    const n = b * 10000 + i;
    docs.push({ clienteId: n % 5000, ordine: n, importo: Math.round(Math.random() * 1000),
                data: new Date(Date.now() - n * 60000), note: "x".repeat(50) });
  }
  c.insertMany(docs, { ordered: false });
}
print("Documenti:", c.countDocuments());'
```

✅ `Documenti: 200000`.

**Memoria dopo il caricamento**, il momento di massimo uso:

```bash
free -h
sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
```

✅ Nel collaudo: 2,5 GB usati su 7,8, nodi degli shard intorno ai 230 MiB, config server a 165, **swap a zero**.

**Distribuzione:**

```bash
sh_eval 'db.getSiblingDB("labdb").ordini.getShardDistribution()'
```

✅ Nel collaudo **50,5% / 49,5%** (101.000 e 99.000 documenti): l'hash sparge i clienti in modo uniforme.

Noterai **un solo chunk per shard**, da circa 13 MB, nonostante la dimensione di riferimento di 1 MB. Non è un errore: una collezione hashed nasce già divisa in un intervallo per shard, e il bilanciatore non divide ciò che è già bilanciato. Vedi il chiarimento in Parte 0.3.

---

## Parte 9 — Query mirate e query su tutti gli shard

```bash
sh_eval 'const e = db.getSiblingDB("labdb").ordini.find({ clienteId: 42 }).explain(); print("Con la shard key    ->", e.queryPlanner.winningPlan.stage, "- shard interrogati:", e.queryPlanner.winningPlan.shards.length)'
sh_eval 'const e = db.getSiblingDB("labdb").ordini.find({ importo: { $gt: 990 } }).explain(); print("Senza la shard key  ->", e.queryPlanner.winningPlan.stage, "- shard interrogati:", e.queryPlanner.winningPlan.shards.length)'
sh_eval 'const e = db.getSiblingDB("labdb").ordini.find({ clienteId: { $gte: 100, $lt: 110 } }).explain(); print("Intervallo su hashed ->", e.queryPlanner.winningPlan.stage, "- shard interrogati:", e.queryPlanner.winningPlan.shards.length)'
```

✅ Risultati del collaudo:

| Query | Risultato | Perché |
|---|---|---|
| `{ clienteId: 42 }` | `SINGLE_SHARD`, 1 shard | Contiene la shard key |
| `{ importo: { $gt: 990 } }` | `SHARD_MERGE`, 2 shard | Non contiene la shard key |
| `{ clienteId: { $gte: 100, $lt: 110 } }` | `SHARD_MERGE`, 2 shard | Con l'hash, valori vicini stanno su shard diversi |

---

## Parte 10 — Shard key a intervalli e lo shard caldo

Una collezione distribuita per **intervalli** di `ts`, un timestamp che cresce sempre, come una data di creazione:

```bash
sh_eval 'printjson(sh.shardCollection("labdb.eventi", { ts: 1 }))'

sh_eval '
const c = db.getSiblingDB("labdb").eventi;
const base = Date.now();
for (let b = 0; b < 10; b++) {
  const docs = [];
  for (let i = 0; i < 10000; i++) {
    const n = b * 10000 + i;
    docs.push({ ts: new Date(base + n * 1000), tipo: "evento", valore: n, note: "x".repeat(50) });
  }
  c.insertMany(docs, { ordered: true });
}
print("Documenti:", c.countDocuments());'
```

✅ `Documenti: 100000`.

**Dove sono i dati, e dove vanno quelli nuovi:**

```bash
sh_eval 'db.getSiblingDB("labdb").eventi.getShardDistribution()'
sh_eval '
const u = db.getSiblingDB("config").collections.findOne({ _id: "labdb.eventi" }).uuid;
const ch = db.getSiblingDB("config").chunks;
ch.aggregate([ { $match: { uuid: u } }, { $group: { _id: "$shard", chunk: { $sum: 1 } } } ]).forEach(printjson);
ch.find({ uuid: u }).sort({ min: -1 }).limit(1).forEach(c => print("Ultimo chunk, che riceve TUTTI i nuovi inserimenti:", c.shard));'
```

**Cosa è successo nel collaudo:**

1. i dati sono nati **tutti su uno shard** (`sh2`): una collezione a intervalli vuota ha un solo intervallo;
2. il bilanciatore ha subito spostato **5 intervalli da circa 1 MB** (`1023KiB` per chunk) sull'altro shard;
3. l'ultimo intervallo, quello che riceve ogni documento con un timestamp più alto, è rimasto su `sh2`: **tutte le nuove scritture vanno lì**. È lo *shard caldo*: il bilanciatore riequilibra i dati già scritti, ma non può distribuire le scritture nuove.

### 10.1 I conti che non tornano: i documenti orfani

Subito dopo il caricamento, `getShardDistribution` sommava **142.275 documenti** invece di 100.000: `sh1` ne aveva ricevuti 42.275 con le migrazioni, ma `sh2` ne contava ancora tutti e 100.000.

**Perché:** dopo una migrazione, lo shard di origine **non cancella subito** i documenti copiati. Li cancella in modo asincrono, dopo un ritardo di sicurezza (per impostazione predefinita **15 minuti**), per non disturbare eventuali letture ancora in corso. Nel frattempo sono documenti **orfani**: presenti fisicamente, ma non più di competenza di quello shard. Le statistiche per shard li contano; **le query attraverso il router li filtrano**, quindi per l'applicazione i dati sono sempre corretti.

```bash
sh_eval 'print("Documenti visti dal router:", db.getSiblingDB("labdb").eventi.countDocuments())'
node_eval mongo-sh2a 27221 'print("Intervalli in attesa di cancellazione:", db.getSiblingDB("config").rangeDeletions.countDocuments()); print("Ritardo di pulizia (secondi):", db.adminCommand({ getParameter: 1, orphanCleanupDelaySecs: 1 }).orphanCleanupDelaySecs)'
```

✅ Nel collaudo: router `100000`, **5** intervalli in attesa, ritardo **900** secondi. Dopo 15 minuti la distribuzione è tornata a **100.000** (42.275 + 57.725), e i 5 intervalli migrati erano diventati **uno solo**: MongoDB riunisce automaticamente gli intervalli contigui dello stesso shard.

### 10.2 Il rovescio della medaglia

Una query per intervallo sulla shard key a intervalli resta mirata:

```bash
sh_eval 'const t = db.getSiblingDB("labdb").eventi.findOne({}, { ts: 1 }).ts; const e = db.getSiblingDB("labdb").eventi.find({ ts: { $gte: t, $lt: new Date(t.getTime() + 60000) } }).explain(); print(e.queryPlanner.winningPlan.stage, "- shard interrogati:", e.queryPlanner.winningPlan.shards.length)'
```

✅ `SINGLE_SHARD`, 1 shard.

### 10.3 Il confronto

| | `ordini` (hashed) | `eventi` (a intervalli, chiave crescente) |
|---|---|---|
| Distribuzione iniziale | Uniforme da subito | Tutto su uno shard |
| Nuove scritture | Distribuite | Sempre sull'ultimo intervallo: shard caldo |
| Query per uguaglianza sulla chiave | Mirata | Mirata |
| Query per intervallo sulla chiave | Tutti gli shard | Mirata |

> 🧭 **Scegliere la shard key in produzione.** Una buona chiave ha **molti valori diversi**, **distribuisce le scritture** e compare nelle **query più frequenti**. Spesso si usa una chiave composta (per esempio cliente + data) per ottenere scritture distribuite e query mirate. La chiave si può cambiare dopo (*resharding*), ma è un'operazione pesante: va scelta bene fin dall'inizio.

---

## Parte 11 — Il bilanciatore

```bash
sh_eval 'print("Bilanciatore abilitato:", sh.getBalancerState()); printjson(sh.isBalancerRunning())'
sh_eval 'db.getSiblingDB("config").changelog.find({ what: /moveChunk.commit|moveRange/ }).sort({ time: -1 }).limit(5).forEach(e => print(e.time.toISOString(), e.what, e.ns))'
```

✅ Nel collaudo: abilitato, `mode: 'full'`, `inBalancerRound: false`; cinque `moveChunk.commit` su `labdb.eventi` in circa 6 secondi, poco più di un secondo ciascuno.

Dopo quelle cinque migrazioni il bilanciatore si è **fermato pur restando attivo**: al netto degli orfani, la differenza tra gli shard era scesa sotto la soglia.

> 🧭 **In produzione** le migrazioni, con intervalli da 128 MB e carico reale, durano molto di più e consumano disco e rete. Si possono limitare a una **finestra oraria** (*balancing window*), per esempio di notte, e fuori dalla finestra del backup.

---

## Parte 12 — Un guasto dentro uno shard

Ogni shard è un replica set: il failover funziona come nella guida 02, e il router trova da solo il nuovo primario.

```bash
node_eval mongo-sh1a 27211 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
sudo docker compose stop mongo-sh1a
```

Dopo una ventina di secondi:

```bash
sh_eval 'print("Documenti:", db.getSiblingDB("labdb").ordini.countDocuments()); db.getSiblingDB("labdb").ordini.insertOne({ clienteId: 1, ordine: -1, nota: "durante il guasto" }); print("Scrittura riuscita")'
node_eval mongo-sh1b 27212 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
sudo docker compose start mongo-sh1a
```

✅ Nel collaudo: stop in 16 secondi (spegnimento ordinato), conteggio e scrittura riusciti attraverso il router, `mongo-sh1b` nuovo primario dello shard 1.

---

## Parte 13 — TLS

Cifriamo **tutte le comunicazioni**: dal tuo PC al router, e tra router, config server e shard.

> **Cosa cifra, e cosa no.** Il TLS protegge i dati **in transito**. I dati **salvati sui dischi** non sono cifrati da MongoDB Community (la cifratura dei file di dati esiste solo nella versione Enterprise): si proteggono a livello di disco, per esempio con la cifratura dei dischi di Azure, attiva per impostazione predefinita.

### 13.1 Il certificato del cluster

Un certificato per tutti i dieci processi, firmato con la CA della guida 01. Nel SAN i nomi di tutti i container (i processi si collegano tra loro con quei nomi), `localhost`, `127.0.0.1`, e il nome DNS e l'IP privato per il collegamento da VS Code. Uso `serverAuth` **e** `clientAuth`: ogni processo è anche client degli altri (guida 02, Parte 8.2).

```bash
cd ~/mongo-lab/03-sharding
mkdir -p tls && chmod 700 tls && cd tls
FQDN=<FQDN>
PRIV_IP=<IP_PRIVATO_VM>

cat > server.ext << EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=DNS:$FQDN,DNS:localhost,DNS:mongo-router,DNS:mongo-cfg1,DNS:mongo-cfg2,DNS:mongo-cfg3,DNS:mongo-sh1a,DNS:mongo-sh1b,DNS:mongo-sh1c,DNS:mongo-sh2a,DNS:mongo-sh2b,DNS:mongo-sh2c,IP:127.0.0.1,IP:$PRIV_IP
EOF

openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=mongo-lab-sh" -out server.csr
openssl x509 -req -in server.csr -CA ~/mongodb/tls/ca.pem -CAkey ~/mongodb/tls/ca.key \
  -CAserial ~/mongodb/tls/ca.srl -days 825 -sha256 -extfile server.ext -out server.crt
rm server.csr
cp ~/mongodb/tls/ca.pem .
openssl verify -CAfile ca.pem server.crt
openssl x509 -in server.crt -noout -ext subjectAltName,extendedKeyUsage

cat server.crt server.key | sudo tee server.pem > /dev/null
sudo chown 999:999 server.pem && sudo chmod 600 server.pem
chmod 600 server.key && chmod 644 ca.pem server.crt
ls -l
cd ..
```

✅ `server.crt: OK`, nel SAN tutti i quattordici nomi e indirizzi, l'uso `TLS Web Server Authentication, TLS Web Client Authentication`, `server.pem` dell'utente 999 con `-rw-------`.

### 13.2 Attivazione a freddo

```bash
cd ~/mongo-lab/03-sharding
cp docker-compose.yml docker-compose.yml.pre-tls
sed -i 's|"--bind_ip_all"\]|"--bind_ip_all", "--tlsMode", "requireTLS", "--tlsCertificateKeyFile", "/etc/mongo/tls/server.pem", "--tlsCAFile", "/etc/mongo/tls/ca.pem", "--tlsAllowConnectionsWithoutCertificates", "--tlsDisabledProtocols", "TLS1_0,TLS1_1"]|' docker-compose.yml
sed -i 's|^      - ./keyfile:/etc/mongo/keyfile:ro$|&\n      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro\n      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro|' docker-compose.yml
grep -c "requireTLS" docker-compose.yml
grep -c "server.pem:ro" docker-compose.yml
sudo docker compose config --quiet && echo "compose valido"
```

✅ `10`, `10`, `compose valido`: opzioni TLS e file montati su nove nodi e router.

Aggiorna le funzioni di comodo, che da ora si collegano in TLS:

```bash
sed -i 's|mongosh --port |mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port |' funzioni-lab.sh
grep -c "tlsCAFile" funzioni-lab.sh
source funzioni-lab.sh
```

✅ `2`.

Riavvio a freddo: `up -d` ricrea tutti i container, perché la configurazione è cambiata.

```bash
sudo docker compose up -d
sleep 45
sudo docker compose ps --format "table {{.Name}}\t{{.Status}}"
```

✅ Dieci container `Up` (nel collaudo la ricreazione ha richiesto circa 45 secondi). Un secondo `up -d` non fa nulla (`Running`): Docker ricrea solo quando la configurazione cambia.

> 🧭 **TLS a freddo**
>
> **Nel laboratorio:** tutto il cluster fermato e riacceso, circa un minuto di interruzione, direttamente in `requireTLS`.
>
> **Perché:** l'unico client è chi segue il laboratorio; a caldo servirebbero due giri di rotazione su dieci processi. Un certificato unico perché tutti i processi stanno sulla stessa macchina.
>
> **In produzione:** migrazione a caldo come nella guida 02 (`allowTLS` → `preferTLS` → `requireTLS`), un replica set alla volta e i router, con più router dietro un bilanciamento per non interrompere le applicazioni; un certificato per server, con il proprio nome DNS.

### 13.3 Verifiche

```bash
sh_eval 'db.adminCommand({ listShards: 1 }).shards.forEach(s => print(s._id, "stato:", s.state)); print("ordini:", db.getSiblingDB("labdb").ordini.countDocuments(), "- eventi:", db.getSiblingDB("labdb").eventi.countDocuments())'
sh_eval 'print("Router:", db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)'
node_eval mongo-sh1a 27211 'print("Shard 1:", db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode); printjson(db.serverStatus().transportSecurity)'
openssl s_client -connect 127.0.0.1:27200 -CAfile tls/ca.pem </dev/null 2>/dev/null | grep -E "Verify return code|Protocol"
sudo docker exec mongo-router mongosh --port 27200 --quiet --eval 'db.runCommand({ ping: 1 })'
```

✅ Nel collaudo: shard con stato 1 e dati intatti; router e shard in `requireTLS`; **62 connessioni TLS 1.3** ricevute dallo shard 1 e nessuna con versioni più vecchie; `Verify return code: 0 (ok)` con TLS 1.3; l'ultimo comando, senza TLS, **fallisce** con `connection ... closed`.

---

## Parte 14 — Accesso dal tuo PC

Qui si vede un vantaggio pratico del router: **una sola porta**, nessun nome dei singoli nodi, nessun `extra_hosts` come nella guida 02. Per VS Code il cluster è indistinguibile da un'istanza singola.

1. **Regola NSG** nel portale Azure: TCP **27200**, origine solo il tuo IP pubblico, nome `mongo-lab-sh`.
2. **Dal PC:** `Test-NetConnection <FQDN> -Port 27200` → `TcpTestSucceeded : True`.
3. **VS Code** (il `ca.pem` è quello della guida 01):

```
mongodb://admin:PASSWORD@<FQDN>:27200/?authSource=admin&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

Nella stringa **non c'è** `replicaSet=`: il router non è un replica set.

✅ VS Code mostra `labdb` con `ordini` ed `eventi`.

> Se dopo un periodo di inattività VS Code non mostra i database, di solito la connessione è rimasta indietro: tasto destro → *Refresh*, oppure disconnetti e riconnetti.

---

## Parte 15 — Utente applicativo

Creato **attraverso il router**, con permessi solo su `labdb`:

```bash
cd ~/mongo-lab/03-sharding
openssl rand -base64 24 | tr -d '/+=' | sudo tee appuser_password.txt > /dev/null
sudo chmod 600 appuser_password.txt

sudo docker exec -i -e P="$(sudo cat root_password.txt)" -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-router \
  sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 27200 -u admin -p "$P" --authenticationDatabase admin --quiet \
    --eval "db.getSiblingDB(\"labdb\").createUser({ user: \"appuser\", pwd: process.env.APP_PWD, roles: [ { role: \"readWrite\", db: \"labdb\" } ] })"'
```

**Verifiche:**

```bash
sudo docker exec -i -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-router \
  sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 27200 -u appuser -p "$APP_PWD" --authenticationDatabase labdb --quiet \
    --eval "print(\"ordini:\", db.getSiblingDB(\"labdb\").ordini.countDocuments()); try { db.getSiblingDB(\"config\").chunks.findOne(); print(\"config leggibile\") } catch (e) { print(\"config:\", e.codeName) }"'

node_eval mongo-sh1a 27211 'print("Utenti di labdb sullo shard 1:", db.getSiblingDB("labdb").getUsers().users.length)'
```

✅ `ordini: 200001`, `config: Unauthorized` (niente accesso ai metadati del cluster), e **0** utenti sullo shard: gli utenti creati attraverso il router vivono nei config server.

Stringa per le applicazioni e per VS Code:

```
mongodb://appuser:PASSWORD@<FQDN>:27200/labdb?authSource=labdb&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

---

## Parte 16 — Backup e ripristino

### 16.1 Cosa cambia rispetto a un replica set

- I dati sono su più shard, e il bilanciatore può **spostarli durante il backup**: va fermato prima, e **riattivato sempre** dopo.
- Attraverso il router non si può usare `--oplog`: il backup logico **non è una fotografia coerente a un unico istante** se l'applicazione scrive durante il dump.
- Un ripristino attraverso il router ricrea le collezioni **senza distribuirle** (Parte 16.5).

> 🧭 **Backup logico attraverso il router**
>
> **Nel laboratorio:** `mongodump` via router con il bilanciatore fermo, notturno e automatico.
>
> **Perché:** semplice, collaudabile, adatto a database piccoli e a un ambiente di prova.
>
> **In produzione:** backup **coerenti** di tutto il cluster richiedono snapshot coordinati di tutti gli shard e dei config server, con il bilanciatore fermo, oppure gli strumenti di un servizio gestito. Il backup logico via router resta utile per esportare singoli database o collezioni. Il bilanciatore si limita a una finestra oraria che non si sovrapponga al backup.

### 16.2 Lo script

Rispetto agli script delle guide precedenti ci sono tre accorgimenti:

- **il bilanciatore viene sempre riattivato**: un `trap ... EXIT` esegue la riattivazione comunque vada, anche se il backup fallisce (verificato in simulazione), ed elimina l'eventuale file incompleto;
- **la password non compare negli argomenti**: arriva dallo standard input, anche per i comandi `mongosh`, che la leggono da una variabile d'ambiente;
- **gli utenti del database** sono inclusi nel backup (`--dumpDbUsersAndRoles`).

In **tre parti** (la prima inserisce il percorso vero del laboratorio):

```bash
sudo tee /usr/local/bin/mongo-sh-backup.sh > /dev/null << EOF
#!/bin/bash
# Backup del cluster con sharding (guida 03): bilanciatore fermo, backup logico via router, TLS
set -euo pipefail
umask 077

LAB=$HOME/mongo-lab/03-sharding
EOF
```

```bash
sudo tee -a /usr/local/bin/mongo-sh-backup.sh > /dev/null << 'EOF'
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
EOF
```

```bash
sudo tee -a /usr/local/bin/mongo-sh-backup.sh > /dev/null << 'EOF'

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
EOF
```

**Verifica:**

```bash
sudo mkdir -p /var/backups/mongo-lab-sh && sudo chmod 700 /var/backups/mongo-lab-sh
sudo chmod 700 /usr/local/bin/mongo-sh-backup.sh
sudo bash -n /usr/local/bin/mongo-sh-backup.sh && echo "sintassi ok"
sudo grep -n "^LAB=" /usr/local/bin/mongo-sh-backup.sh
sudo tail -1 /usr/local/bin/mongo-sh-backup.sh
```

✅ `sintassi ok`, `LAB=` con il percorso vero, e come ultima riga l'`echo "Backup completato..."` (se manca, l'ultima parte non è stata incollata per intero).

### 16.3 Prova manuale

```bash
sudo /usr/local/bin/mongo-sh-backup.sh
sudo ls -lh /var/backups/mongo-lab-sh/daily
sh_eval 'print("Bilanciatore abilitato:", sh.getBalancerState())'
```

✅ `Backup completato` (nel collaudo 3,6 MB), il file con **`-rw-------`**, e il bilanciatore di nuovo `true`.

> **Permessi del file.** In una versione precedente dei comandi manuali, il backup veniva scritto sull'host con `sudo tee`, e nasceva `-rw-r--r--`: l'`umask 077` dentro il container non vale per i file creati sull'host. Lo script scrive il file dall'host con `umask 077`, quindi nasce protetto.

### 16.4 Il timer

Alle **03:30 UTC**, dopo i backup delle guide 00 (02:30) e 02 (03:00), anche se sospesi:

```bash
sudo tee /etc/systemd/system/mongo-sh-backup.service > /dev/null << 'EOF'
[Unit]
Description=Backup MongoDB cluster con sharding di laboratorio
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mongo-sh-backup.sh
EOF

sudo tee /etc/systemd/system/mongo-sh-backup.timer > /dev/null << 'EOF'
[Unit]
Description=Backup notturno MongoDB cluster con sharding di laboratorio

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mongo-sh-backup.timer
systemctl list-timers 'mongo*'
sudo systemctl start mongo-sh-backup.service && sudo journalctl -u mongo-sh-backup.service -n 3 --no-pager
```

✅ Il timer alle 03:30 e `Backup completato` nel journal.

### 16.5 Ripristino di prova

In un database diverso, per non toccare l'originale:

```bash
cd ~/mongo-lab/03-sharding
F=$(sudo ls -t /var/backups/mongo-lab-sh/daily/ | head -1); echo "Archivio: $F"
{ sudo cat root_password.txt; sudo cat "/var/backups/mongo-lab-sh/daily/$F"; } | sudo docker exec -i mongo-router sh -c '
  umask 077
  read -r P
  printf "uri: mongodb://admin:%s@localhost:27200/?authSource=admin\n" "$P" > /tmp/restore.yaml
  mongorestore --config=/tmp/restore.yaml --ssl --sslCAFile=/etc/mongo/tls/ca.pem --nsFrom "labdb.*" --nsTo "labdb_ripristino.*" --archive --gzip
  status=$?
  rm -f /tmp/restore.yaml
  exit $status'

sh_eval 'const d = db.getSiblingDB("labdb_ripristino"); print("ordini:", d.ordini.countDocuments(), "- eventi:", d.eventi.countDocuments()); print("ordini distribuita?", db.getSiblingDB("config").collections.findOne({ _id: "labdb_ripristino.ordini" }) !== null); d.dropDatabase(); print("database di prova eliminato")'
```

✅ Nel collaudo: **300.001 documenti** ripristinati in circa 11 secondi, conteggi corretti, e **`ordini distribuita? false`**.

**Cosa significa:** un ripristino attraverso il router ricrea le collezioni **non distribuite**, tutte sullo shard primario del database. Gli **indici** della shard key però vengono ripristinati (nell'output di `mongorestore` compaiono `clienteId_hashed` e `ts_1`): la collezione si può ridistribuire dopo con `sh.shardCollection`, oppure la si crea e distribuisce **prima** del ripristino.

**Utenti** 🧪: il backup li contiene (`--dumpDbUsersAndRoles`), ma si ripristinano solo con `--restoreDbUsersAndRoles` e solo nel database con lo **stesso nome**, quindi non in una prova su un database diverso. Questo ripristino non è stato collaudato.

---

## Parte 17 — Uso quotidiano

| Operazione | Comando (da `~/mongo-lab/03-sharding`) |
|---|---|
| Caricare le funzioni | `source funzioni-lab.sh` |
| Stato del cluster | `sh_eval 'sh.status()'` |
| Stato di uno shard | `node_eval mongo-sh1a 27211 'rs.status().members.forEach(m => print(m.name, m.stateStr))'` |
| Distribuzione di una collezione | `sh_eval 'db.getSiblingDB("labdb").ordini.getShardDistribution()'` |
| Bilanciatore | `sh_eval 'print(sh.getBalancerState())'` |
| Memoria dei nodi | `sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"` |
| Fermare / riavviare il cluster | `sudo docker compose stop` / `sudo docker compose start` |
| Backup subito / esiti | `sudo /usr/local/bin/mongo-sh-backup.sh` / `sudo journalctl -u mongo-sh-backup.service -n 5` |

**Ripartenza dopo uno spegnimento completo:** nel collaudo, dopo `docker compose start`, in 30 secondi il router aveva ritrovato config server e shard, con i dati intatti. Con `restart: unless-stopped` il cluster riparte da solo anche dopo un riavvio della VM (se non l'hai fermato tu).

---

## Parte 18 — Riaccendere le altre istanze o smantellare il laboratorio

### 18.1 Tornare al MongoDB di sviluppo e al replica set

```bash
cd ~/mongo-lab/03-sharding && sudo docker compose stop
sudo systemctl disable --now mongo-sh-backup.timer

cd ~/mongodb && sudo docker compose start
sudo systemctl enable --now mongo-backup.timer

cd ~/mongo-lab/02-replica-set && sudo docker compose start
sudo systemctl enable --now mongo-rs-backup.timer

sudo docker ps --format "table {{.Names}}\t{{.Status}}"
systemctl list-timers 'mongo*'
```

✅ Collaudato: il cluster si ferma in circa 18 secondi per container, le altre istanze ripartono e i loro timer tornano in programma.

Per tenere acceso il cluster insieme all'istanza di sviluppo, la memoria basta (nel collaudo: 2,4 GB usati, 5,4 disponibili); il replica set della guida 02 va tenuto spento.

### 18.2 Togliere lo swap (facoltativo)

Collaudato:

```bash
sudo swapoff /swapfile
sudo sed -i '\|^/swapfile none swap sw 0 0$|d' /etc/fstab
sudo rm /swapfile
free -h
```

✅ `Swap: 0B`. Lo swap può anche restare: non costa nulla finché non serve.

### 18.3 Smantellare il cluster

```bash
cd ~/mongo-lab/03-sharding
pwd                                     # deve essere la cartella del cluster!
sudo docker compose down -v
sudo systemctl disable --now mongo-sh-backup.timer
sudo rm /etc/systemd/system/mongo-sh-backup.{service,timer} /usr/local/bin/mongo-sh-backup.sh
sudo systemctl daemon-reload
sed -i '\|source ~/mongo-lab/03-sharding/funzioni-lab.sh|d' ~/.bashrc
```

Poi, a scelta: la cartella `~/mongo-lab/03-sharding`, i backup in `/var/backups/mongo-lab-sh`, la regola NSG `mongo-lab-sh`, le connessioni in VS Code.

---

## Parte 19 — Quando qualcosa va storto

### Preparazione e costruzione

| Sintomo | Causa | Soluzione |
|---|---|---|
| `swapon: command not found` | Comando in `/usr/sbin`, fuori dal percorso utente | `sudo swapon --show` |
| Righe mescolate durante l'incolla (`EOF   - ./keyfile...`) | Difetto di visualizzazione del terminale, oppure file davvero incompleto | Verifica con `config \| grep -c "target: /etc/mongo/keyfile"` (10) e `grep -n -A6` sul servizio sospetto |
| Il router nei log: `Could not find host ... for set cfgrs` | Config server non ancora inizializzati | Normale fino alla Parte 4 |
| Un config server non parte | Volume montato su `/data/db` invece di `/data/configdb`, o keyFile mancante | Controlla il compose del servizio |

### Uso

| Sintomo | Causa | Soluzione |
|---|---|---|
| `sh_eval: command not found` | Nuova sessione | `source funzioni-lab.sh` (o riga in `~/.bashrc`) |
| `sh.status()` fallisce | Collegato a un nodo invece che al router | Usa `sh_eval` |
| Totali di `getShardDistribution` più alti dei documenti reali | Documenti orfani dopo una migrazione | Normale per ~15 minuti; il router li filtra (Parte 10.1) |
| Un solo chunk per shard nonostante `chunksize` piccolo | Nessuna divisione automatica: collezione già bilanciata | Normale (Parte 0.3) |
| Il bilanciatore non sposta nulla | Differenza di dati sotto la soglia (~3 × chunk size) | Normale; controlla `changelog` |
| Scritture concentrate su uno shard | Shard key crescente a intervalli | Scegliere una chiave hashed o composta (Parte 10.3) |
| VS Code non mostra i database | Connessione rimasta indietro | *Refresh* o riconnessione |

### TLS

| Sintomo | Causa | Soluzione |
|---|---|---|
| `connection ... closed` | Client senza TLS | `--tls --tlsCAFile` / `tls=true&tlsCAFile=` |
| Errori sui certificati tra i processi | Certificato senza `clientAuth`, o nome del container mancante nel SAN | Rigenera con tutti i nomi e `serverAuth,clientAuth` |
| `IP address mismatch` / `altnames` da VS Code | FQDN o IP non nel SAN | Usa `<FQDN>`, o rinnova il certificato |

### Backup

| Sintomo | Causa | Soluzione |
|---|---|---|
| Bilanciatore rimasto fermo | Backup interrotto senza riattivazione | Lo script lo riattiva sempre; a mano: `sh_eval 'sh.startBalancer()'` |
| Backup con `-rw-r--r--` | Scritto sull'host senza `umask 077` | Usa lo script; `sudo chmod 600` sui vecchi file |
| Collezioni ripristinate non distribuite | Comportamento normale del ripristino via router | Distribuiscile prima o dopo il ripristino |

---

## Parte 20 — Laboratorio e produzione

### 20.1 Le differenze

| Aspetto | Laboratorio | Produzione |
|---|---|---|
| Server | 10 container su una VM | ~10 VM: 3 config server piccoli, 3 per shard; router sui server applicativi |
| Zone di disponibilità | Nessuna | Membri di ogni replica set in zone diverse |
| Memoria | Cache 256 MB, limiti per container, swap 4 GB di sicurezza | RAM sul working set, swap piccolo, monitoraggio |
| Altre istanze | Spente per liberare risorse | Server dedicati |
| Nomi | Nomi dei container Docker | Nomi DNS interni stabili |
| Esposizione | Solo il router, NSG su un IP | Solo i router, solo in rete privata |
| Chunk size | 1 MB | Predefinito (128 MB) |
| Utenti | Localhost exception; stessa password per gli admin | Stesso schema, segreti in un gestore dedicato |
| Autenticazione interna | keyFile | keyFile o x.509 |
| TLS | A freddo, certificato unico | A rotazione, un certificato per server |
| Backup | Logico via router, notturno, bilanciatore fermo | Snapshot coordinati o servizio gestito; finestra del bilanciatore |
| Router | Uno | Più router, per disponibilità |

### 20.2 Checklist per la produzione

- [ ] Verificato che un singolo replica set ben dimensionato non basti.
- [ ] Shard key scelta sulle query reali: molti valori, scritture distribuite, query mirate.
- [ ] Config server e shard su VM dedicate, in zone di disponibilità diverse.
- [ ] Almeno due router, vicini alle applicazioni.
- [ ] Nomi DNS interni stabili, scelti prima dell'inizializzazione.
- [ ] Nessuna esposizione su internet; subnet dedicata per config server e shard.
- [ ] TLS obbligatorio con certificati per server; keyFile o x.509.
- [ ] Backup coerenti (snapshot coordinati o servizio gestito), ripristino provato.
- [ ] Finestra del bilanciatore fuori dagli orari di punta e dal backup.
- [ ] Monitoraggio: distribuzione dei dati, migrazioni, stato dei replica set, uso della memoria.

### 20.3 Argomenti avanzati (non collaudati nel laboratorio)

- **Zone** (*zone sharding*): legare intervalli di dati a shard specifici, per esempio per paese.
- **Resharding**: cambiare la shard key di una collezione esistente.
- **Aggiungere e rimuovere shard** in un cluster in esercizio.
- **Autenticazione x.509** dei membri al posto del keyFile.

---

## Appendice A — Dove si trova ogni cosa

| Cosa | Dove |
|---|---|
| Cartella del cluster | `~/mongo-lab/03-sharding` |
| Configurazione | `docker-compose.yml` (copia senza TLS: `docker-compose.yml.pre-tls`) |
| keyFile, password | `keyfile` (`400`, 999), `root_password.txt`, `appuser_password.txt` |
| Certificati | `tls/` (`server.pem` 999 `600`, `ca.pem`, `server.crt`, `server.key`, `server.ext`) |
| Funzioni di comodo | `funzioni-lab.sh` (eventuale riga in `~/.bashrc`) |
| Dati | 9 volumi `mongo-lab-sh_*-data` |
| Swap | `/swapfile`, riga in `/etc/fstab` |
| Script di backup | `/usr/local/bin/mongo-sh-backup.sh` |
| Backup | `/var/backups/mongo-lab-sh/daily`, `weekly`, `monthly` |
| Timer | `/etc/systemd/system/mongo-sh-backup.{service,timer}` (03:30 UTC) |
| Azure | Regola NSG `mongo-lab-sh` (27200) |

---

## Appendice B — Promemoria dei comandi

```bash
cd ~/mongo-lab/03-sharding && source funzioni-lab.sh

sh_eval 'sh.status()'
sh_eval 'db.adminCommand({ listShards: 1 }).shards.forEach(s => print(s._id, "stato:", s.state))'
sh_eval 'db.getSiblingDB("labdb").ordini.getShardDistribution()'
sh_eval 'const e = db.getSiblingDB("labdb").ordini.find({ clienteId: 42 }).explain(); print(e.queryPlanner.winningPlan.stage)'
sh_eval 'print(sh.getBalancerState()); printjson(sh.isBalancerRunning())'
node_eval mongo-sh1a 27211 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
node_eval mongo-sh2a 27221 'print(db.getSiblingDB("config").rangeDeletions.countDocuments())'

sudo /usr/local/bin/mongo-sh-backup.sh
sudo journalctl -u mongo-sh-backup.service -n 5 --no-pager
free -h
```

---

## Le 10 regole d'oro dello sharding

1. **Prima di sharding, prova a scalare il replica set**: lo sharding costa caro.
2. **La shard key si sceglie sulle query**, e cambiarla dopo è pesante.
3. **Chiavi crescenti a intervalli = shard caldo**: preferisci hashed o composte.
4. **Le applicazioni parlano solo con i router.**
5. **Ogni shard e i config server sono replica set**: valgono tutte le regole della guida 02.
6. **I totali per shard possono includere orfani**: fidati del router.
7. **Ferma il bilanciatore durante il backup, e riattivalo sempre.**
8. **Un ripristino via router non ridistribuisce le collezioni.**
9. **Il TLS cifra il transito, non il disco.**
10. **Guarda il prompt**: più progetti sulla stessa VM, un solo `down -v` sbagliato.
