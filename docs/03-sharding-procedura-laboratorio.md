# 03 — Sharding: procedura di laboratorio (bozza usata per il collaudo)

> **Documento storico.** Questa è la bozza con cui è stato eseguito il collaudo; le correzioni emerse sono confluite nelle guide definitive `03-sharding-guida-completa.md` e `03-sharding-guida-rapida.md`, che vanno usate al suo posto (comprendono anche TLS, utente applicativo e backup notturno, assenti qui). Esegui i passi in ordine, confronta l'output con quanto indicato dopo ✅ e segnala ogni differenza. Dal collaudo nasceranno le guide `03-sharding-guida-completa.md` e `03-sharding-guida-rapida.md`.

**Presupposti:** guide 00–02 completate sulla stessa VM. Tempo stimato: 2 ore.

> ⚠️ **Tre progetti Docker Compose sulla VM:** `~/mongodb` (sviluppo), `~/mongo-lab/02-replica-set`, `~/mongo-lab/03-sharding`. **Guarda il prompt prima di ogni `docker compose`.**

> **Scelte di laboratorio.** Tutto ciò che segue gira su una sola VM, con memoria limitata artificialmente e altre istanze spente. Le motivazioni e le scelte di produzione sono in `03-sharding-appunti.md`: non copiare queste impostazioni in produzione.

---

## Il cluster

| Componente | Replica set | Container | Porte |
|---|---|---|---|
| Config server | `cfgrs` | `mongo-cfg1`, `mongo-cfg2`, `mongo-cfg3` | 27201–27203 |
| Shard 1 | `sh1` | `mongo-sh1a`, `mongo-sh1b`, `mongo-sh1c` | 27211–27213 |
| Shard 2 | `sh2` | `mongo-sh2a`, `mongo-sh2b`, `mongo-sh2c` | 27221–27223 |
| Router | — | `mongo-router` | 27200 (unica porta pubblicata) |

---

## Passo 0 — Liberare memoria e aggiungere lo swap

Spegni (senza eliminarli) il MongoDB di sviluppo e il replica set della guida 02, sospendendo i loro backup notturni:

```bash
cd ~/mongodb && sudo docker compose stop
sudo systemctl disable --now mongo-backup.timer
cd ~/mongo-lab/02-replica-set && sudo docker compose stop
sudo systemctl disable --now mongo-rs-backup.timer
sudo docker ps
```

✅ `docker ps` non elenca container in esecuzione.

Aggiungi uno **swap da 4 GB**.

> **Cos'è e perché serve.** Quando la RAM si esaurisce, senza swap Linux attiva l'**OOM killer** (*Out Of Memory*), che termina d'autorità un processo: con dieci nodi MongoDB sarebbe quasi certamente uno di loro, spento di colpo come per un'interruzione di corrente. Con lo swap, Linux sposta su disco le parti di memoria usate meno di recente: il sistema rallenta, ma nessun processo viene ucciso. È una **rete di sicurezza** per i picchi (caricamento dati, bilanciamento dei chunk), **non RAM in più**: se un sistema lo usa di continuo, le prestazioni crollano.
>
> **Scelta di laboratorio:** 4 GB bastano ad assorbire i picchi e occupano 4 dei circa 58 GB liberi sul disco di sistema. Azure suggerirebbe il disco temporaneo della VM (`/mnt`), più veloce, ma il suo contenuto si perde quando la VM viene spostata o deallocata e la configurazione è più articolata: per il laboratorio il file sul disco di sistema è più semplice e prevedibile.
>
> **In produzione** la RAM si dimensiona sul *working set* (dati e indici usati di frequente); lo swap resta piccolo, solo come protezione, e il suo uso si monitora: se cresce, il server è sottodimensionato.

| Comando | Cosa fa |
|---|---|
| `fallocate -l 4G /swapfile` | Crea un file di 4 GB riservando lo spazio sul disco |
| `chmod 600 /swapfile` | Leggibile solo da root: lo swap può contenere dati in memoria, anche password |
| `mkswap /swapfile` | Lo prepara come area di swap |
| `swapon /swapfile` | Lo attiva subito |
| Riga in `/etc/fstab` | Lo riattiva a ogni avvio della VM |

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
sudo swapon --show
```

✅ `free -h`: circa 7 GB disponibili e `Swap: 4.0Gi`; `swapon --show` elenca `/swapfile`.

> `swapon` va lanciato con `sudo` anche solo per consultarlo: su Debian i comandi di amministrazione del sistema stanno in `/usr/sbin`, che non è nel percorso di ricerca degli utenti normali. Senza `sudo` compare `swapon: command not found`.

---

## Passo 1 — Cartella, keyFile e password

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

✅ `keyfile` con `-r--------` dell'utente 999; `root_password.txt` con `-rw-------` di root; l'IP privato stampato correttamente.

---

## Passo 2 — Il docker-compose.yml, in quattro parti

Il file è lungo: lo scriviamo in quattro parti corte (la prima con `>` crea il file, le altre con `>>` lo completano). Le prime tre usano `<< 'EOF'` (copiate alla lettera), l'ultima `<< EOF` (inserisce il valore di `$PRIV_IP`).

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

> Nota: con `--configsvr` MongoDB usa come cartella dati `/data/configdb` invece di `/data/db`, per questo il volume dei config server è montato lì.

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

**Verifica:**

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose config --services | wc -l
sudo docker compose config --volumes | wc -l
sudo docker compose config | grep -c "target: /etc/mongo/keyfile"
grep -A2 "ports:" docker-compose.yml
```

✅ `compose valido`, **10** servizi, **9** volumi, **10** montaggi del keyFile (nove nodi più il router), e sotto `ports` del router le righe con `127.0.0.1` e con il tuo IP privato (non `$PRIV_IP`).

> **Perché il controllo sul keyFile.** Servizi e volumi possono risultare corretti anche se a un nodo manca la sezione `volumes` (i volumi sono dichiarati in fondo al file dalla Parte D). Contare i montaggi del keyFile verifica ogni singolo servizio.
>
> **Se durante l'incolla vedi righe mescolate**, come `EOF   - ./keyfile:...`: nel collaudo è successo alla fine della Parte A, ma era solo un difetto di visualizzazione del terminale, e il file era integro. Non fidarti né dell'aspetto né di `compose valido`: verifica il contenuto (`grep -n -A6 "container_name: mongo-cfg3" docker-compose.yml`) e il conteggio del keyFile, e correggi solo se manca davvero qualcosa. In alternativa all'incolla, `nano` evita il problema.

| Elemento | Significato |
|---|---|
| `--configsvr` | Il nodo è un config server: contiene la mappa del cluster (quali dati stanno su quale shard) |
| `--shardsvr` | Il nodo fa parte di uno shard: contiene una porzione dei dati |
| `mongos --configdb cfgrs/...` | Il router: sa dove trovare i config server e instrada le richieste |
| `mem_limit: 640m` / `384m` | Tetto di memoria per nodo e per il router (scelta di laboratorio) |
| `user: "999:999"` sul router | Il router gira come utente non privilegiato; non ha dati propri |
| Nessuna porta per config server e shard | Solo il router è raggiungibile dall'esterno di Docker |

---

## Passo 3 — Avvio

```bash
cd ~/mongo-lab/03-sharding
sudo docker compose up -d
sleep 20
sudo docker compose ps --format "table {{.Name}}\t{{.Status}}"
sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
```

✅ I nove `mongod` in stato `Up`. Il router potrebbe risultare `Up` ma non ancora operativo, o in `Restarting`: è normale, perché i config server non sono ancora un replica set. La memoria usata da ogni nodo dovrebbe essere ben sotto i 640 MB.

```bash
sudo docker compose logs mongo-router --tail 5
```

Messaggi che parlano di impossibilità a raggiungere `cfgrs` sono attesi in questa fase.

---

## Passo 4 — Inizializzare i tre replica set

Finché non esiste alcun utente, MongoDB accetta comandi di amministrazione collegandosi **dalla stessa macchina** (*localhost exception*): per questo i comandi seguenti non chiedono password.

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

**Verifica dei primari** (dopo circa 20 secondi):

```bash
for c in "mongo-cfg1 27201" "mongo-sh1a 27211" "mongo-sh2a 27221"; do
  set -- $c
  sudo docker exec $1 mongosh --port $2 --quiet --eval 'print(db.hello().setName, "- primario:", db.hello().primary)'
done
```

✅ Per ciascuno dei tre replica set compare il nome e il suo primario (di solito il nodo su cui hai lanciato `rs.initiate`). Annota i primari degli shard: servono al passo successivo.

---

## Passo 5 — Utenti

### 5.1 Amministratori locali degli shard

Ogni shard ha i propri utenti locali, usati solo per la manutenzione diretta dei suoi nodi. Si creano **sul primario** di ciascuno shard, sempre con la localhost exception. Se al Passo 4 il primario di uno shard non era il nodo `a`, sostituisci contenitore e porta.

```bash
cd ~/mongo-lab/03-sharding
for c in "mongo-sh1a 27211" "mongo-sh2a 27221"; do
  set -- $c
  sudo docker exec -i -e P="$(sudo cat root_password.txt)" $1 \
    sh -c 'mongosh --port '"$2"' --quiet --eval "db.getSiblingDB(\"admin\").createUser({ user: \"admin\", pwd: process.env.P, roles: [\"root\"] })"'
done
```

✅ Due volte `{ ok: 1, ... }`.

### 5.2 Amministratore del cluster

Si crea **attraverso il router**, che lo salva nei config server:

```bash
sudo docker compose logs mongo-router --tail 3
sudo docker exec -i -e P="$(sudo cat root_password.txt)" mongo-router \
  sh -c 'mongosh --port 27200 --quiet --eval "db.getSiblingDB(\"admin\").createUser({ user: \"admin\", pwd: process.env.P, roles: [\"root\"] })"'
```

✅ `{ ok: 1, ... }`. Se il router non risponde, controlla che sia `Up` (`sudo docker compose ps mongo-router`) e riprova dopo qualche secondo.

> Nel laboratorio i tre amministratori usano la stessa password, per semplicità. In produzione: password diverse, in un gestore di segreti.

### 5.3 Funzioni di comodo (solo laboratorio)

```bash
# Esegue JavaScript sul router, come admin del cluster
sh_eval() {
  sudo docker exec -i -e P="$(sudo cat ~/mongo-lab/03-sharding/root_password.txt)" mongo-router \
    sh -c 'mongosh --port 27200 -u admin -p "$P" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}

# Esegue JavaScript su un nodo specifico: node_eval <container> <porta> 'js'
node_eval() {
  sudo docker exec -i -e P="$(sudo cat ~/mongo-lab/03-sharding/root_password.txt)" "$1" \
    sh -c 'mongosh --port '"$2"' -u admin -p "$P" --authenticationDatabase admin --quiet --eval "$0"' "$3"
}

sh_eval 'print("Collegato al router, versione", db.version())'
node_eval mongo-sh1a 27211 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

✅ La versione del server e lo stato dei tre membri dello shard 1. Le funzioni vanno ridefinite in ogni nuova sessione.

---

## Passo 6 — Registrare gli shard

```bash
sh_eval 'printjson(sh.addShard("sh1/mongo-sh1a:27211,mongo-sh1b:27212,mongo-sh1c:27213"))'
sh_eval 'printjson(sh.addShard("sh2/mongo-sh2a:27221,mongo-sh2b:27222,mongo-sh2c:27223"))'
sh_eval 'db.adminCommand({ listShards: 1 }).shards.forEach(s => print(s._id, s.host, "stato:", s.state))'
```

✅ Due volte `shardAdded` con `ok: 1`, poi i due shard `sh1` e `sh2` con stato `1`.

**La prova rispetto alla guida 02:** ora `sh.status()` funziona, perché stai parlando con un router:

```bash
sh_eval 'sh.status()'
```

---

## Passo 7 — Dimensione dei chunk (scelta di laboratorio)

I dati di una collezione distribuita sono divisi in **chunk** (intervalli della shard key). Per impostazione predefinita un chunk arriva a 128 MB, e il bilanciatore sposta dati tra gli shard solo quando la differenza supera alcune volte quella dimensione: con i pochi MB di dati di un laboratorio non vedremmo nulla. Riduciamo la dimensione a **1 MB**:

```bash
sh_eval 'db.getSiblingDB("config").settings.updateOne({ _id: "chunksize" }, { $set: { value: 1 } }, { upsert: true }); printjson(db.getSiblingDB("config").settings.findOne({ _id: "chunksize" }))'
```

✅ `{ _id: 'chunksize', value: 1 }`.

> ⚠️ **Solo laboratorio.** In produzione si lascia il valore predefinito: chunk minuscoli significano migliaia di chunk e migrazioni continue.

---

## Passo 8 — Shard key hashed

Collezione `labdb.ordini`, distribuita in base all'**hash** di `clienteId`: i documenti vengono sparsi uniformemente sugli shard.

```bash
sh_eval 'sh.enableSharding("labdb"); printjson(sh.shardCollection("labdb.ordini", { clienteId: "hashed" }))'
```

✅ `collectionsharded: 'labdb.ordini'` con `ok: 1`.

**Carichiamo 200.000 ordini** di prova (circa un minuto):

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

Il caricamento è il momento di massimo uso della memoria: controlla se il sistema ha dovuto ricorrere allo swap.

```bash
free -h
```

✅ Nella riga `Swap:` la colonna `used` dovrebbe essere a zero o quasi. Se è cresciuta molto, annotalo: è un'informazione preziosa per la guida.

**Come si sono distribuiti?**

```bash
sh_eval 'db.getSiblingDB("labdb").ordini.getShardDistribution()'
```

✅ Due blocchi, `Shard sh1` e `Shard sh2`, con percentuali di dati e documenti **vicine al 50%** ciascuno.

---

## Passo 9 — Query mirate e query su tutti gli shard

Una query che include la shard key viene mandata **a un solo shard**; una che non la include deve interrogare **tutti** gli shard (*scatter-gather*).

```bash
sh_eval 'const e = db.getSiblingDB("labdb").ordini.find({ clienteId: 42 }).explain(); print("Con la shard key    ->", e.queryPlanner.winningPlan.stage, "- shard interrogati:", e.queryPlanner.winningPlan.shards.length)'
sh_eval 'const e = db.getSiblingDB("labdb").ordini.find({ importo: { $gt: 990 } }).explain(); print("Senza la shard key  ->", e.queryPlanner.winningPlan.stage, "- shard interrogati:", e.queryPlanner.winningPlan.shards.length)'
```

✅ Con la shard key: `SINGLE_SHARD`, 1 shard. Senza: `SHARD_MERGE`, 2 shard.

> Con una shard key **hashed** si ottiene una query mirata solo con l'uguaglianza (`clienteId: 42`). Un intervallo (`clienteId: { $gt: 100 }`) va comunque a tutti gli shard, perché l'hash disperde valori vicini.

---

## Passo 10 — Shard key a intervalli e il problema della chiave crescente

Collezione `labdb.eventi`, distribuita per **intervalli** di `ts`, un timestamp che cresce sempre.

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

**Dove finiscono i nuovi inserimenti?**

```bash
sh_eval '
const u = db.getSiblingDB("config").collections.findOne({ _id: "labdb.eventi" }).uuid;
const ch = db.getSiblingDB("config").chunks;
ch.aggregate([ { $match: { uuid: u } }, { $group: { _id: "$shard", chunk: { $sum: 1 } } } ]).forEach(printjson);
ch.find({ uuid: u }).sort({ min: -1 }).limit(1).forEach(c => print("Ultimo chunk, che riceve TUTTI i nuovi inserimenti:", c.shard));'
```

✅ Il numero di chunk per shard e l'indicazione dello shard che ospita l'ultimo intervallo. Con una chiave che cresce sempre, **ogni nuovo documento finisce in quell'ultimo chunk**, quindi su un solo shard: è il problema dello *shard caldo*. Il bilanciatore sposta poi i chunk vecchi, ma le scritture restano concentrate.

Ripeti la distribuzione tra un paio di minuti, per vedere il lavoro del bilanciatore:

```bash
sh_eval 'db.getSiblingDB("labdb").eventi.getShardDistribution()'
```

**Una query per intervallo, con la shard key a intervalli, resta mirata:**

```bash
sh_eval 'const t = db.getSiblingDB("labdb").eventi.findOne({}, { ts: 1 }).ts; const e = db.getSiblingDB("labdb").eventi.find({ ts: { $gte: t, $lt: new Date(t.getTime() + 60000) } }).explain(); print(e.queryPlanner.winningPlan.stage, "- shard interrogati:", e.queryPlanner.winningPlan.shards.length)'
```

✅ Probabilmente `SINGLE_SHARD`: un minuto di eventi sta in un solo chunk.

---

## Passo 11 — Il bilanciatore

```bash
sh_eval 'print("Bilanciatore abilitato:", sh.getBalancerState()); printjson(sh.isBalancerRunning())'
sh_eval 'db.getSiblingDB("config").changelog.find({ what: /moveChunk.commit|moveRange/ }).sort({ time: -1 }).limit(5).forEach(e => print(e.time.toISOString(), e.what, e.ns))'
```

✅ Bilanciatore abilitato e, se ha già lavorato, le ultime migrazioni registrate.

---

## Passo 12 — Guasto dentro uno shard

Ogni shard è un replica set: il failover funziona come nella guida 02, e il router se ne accorge da solo.

```bash
node_eval mongo-sh1a 27211 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

Spegni il **primario** dello shard 1 (sostituisci il nome se non è `mongo-sh1a`):

```bash
sudo docker compose stop mongo-sh1a
```

Dopo una ventina di secondi:

```bash
sh_eval 'print("Documenti:", db.getSiblingDB("labdb").ordini.countDocuments()); db.getSiblingDB("labdb").ordini.insertOne({ clienteId: 1, ordine: -1, nota: "durante il guasto" }); print("Scrittura riuscita")'
node_eval mongo-sh1b 27212 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

✅ Il conteggio funziona, la scrittura riesce, e nello shard 1 un altro nodo è diventato `PRIMARY`.

```bash
sudo docker compose start mongo-sh1a
```

---

## Passo 13 — Accesso dal PC attraverso il router

Il router è l'unico punto d'accesso: basta una sola porta, e nessun problema di nomi dei membri come nella guida 02.

1. **NSG di Azure:** regola in ingresso TCP **27200**, origine solo il tuo IP pubblico, nome `mongo-lab-sh`. Il traffico non è cifrato in questo laboratorio.
2. **Verifica dal PC:**

   ```powershell
   Test-NetConnection <FQDN> -Port 27200
   ```

3. **VS Code:**

   ```
   mongodb://admin:PASSWORD@<FQDN>:27200/?authSource=admin
   ```

   Niente `replicaSet=` nella stringa: il router non è un replica set.

✅ VS Code mostra il database `labdb` con le collezioni `ordini` ed `eventi`.

---

## Passo 14 — Backup di un cluster con sharding

Il backup di un cluster è più delicato di quello di un replica set: i dati sono su più shard e i chunk possono spostarsi durante il backup. Nel laboratorio facciamo un **backup logico attraverso il router**, fermando prima il bilanciatore.

```bash
sudo mkdir -p /var/backups/mongo-lab-sh && sudo chmod 700 /var/backups/mongo-lab-sh
sh_eval 'sh.stopBalancer(); print("Bilanciatore abilitato:", sh.getBalancerState())'

F=/var/backups/mongo-lab-sh/labdb-$(date +%Y%m%d-%H%M%S).archive.gz
sudo cat ~/mongo-lab/03-sharding/root_password.txt | sudo docker exec -i mongo-router sh -c '
  umask 077
  read -r P
  printf "uri: mongodb://admin:%s@localhost:27200/?authSource=admin\n" "$P" > /tmp/dump.yaml
  mongodump --config=/tmp/dump.yaml --db labdb --archive --gzip --quiet
  status=$?
  rm -f /tmp/dump.yaml
  exit $status' | sudo tee "$F" > /dev/null
sudo ls -lh /var/backups/mongo-lab-sh

sh_eval 'sh.startBalancer(); print("Bilanciatore abilitato:", sh.getBalancerState())'
```

✅ Bilanciatore `false` durante il backup e `true` dopo; un file di qualche MB.

**Ripristino di prova in un database diverso**, per non toccare l'originale:

```bash
{ sudo cat ~/mongo-lab/03-sharding/root_password.txt; sudo cat "$F"; } | sudo docker exec -i mongo-router sh -c '
  umask 077
  read -r P
  printf "uri: mongodb://admin:%s@localhost:27200/?authSource=admin\n" "$P" > /tmp/restore.yaml
  mongorestore --config=/tmp/restore.yaml --nsFrom "labdb.*" --nsTo "labdb_ripristino.*" --archive --gzip
  status=$?
  rm -f /tmp/restore.yaml
  exit $status'

sh_eval 'const d = db.getSiblingDB("labdb_ripristino"); print("ordini:", d.ordini.countDocuments(), "- eventi:", d.eventi.countDocuments()); print("ordini distribuita?", db.getSiblingDB("config").collections.findOne({ _id: "labdb_ripristino.ordini" }) !== null)'
```

✅ I conteggi coincidono con gli originali (200.001 ordini e 100.000 eventi), e `ordini distribuita? false`: un ripristino logico ricrea le collezioni **non distribuite**. Per ripristinarle come collezioni distribuite bisogna crearle e distribuirle prima del ripristino.

> **In produzione** un backup coerente di un cluster con sharding richiede strumenti dedicati (snapshot coordinati di tutti gli shard e dei config server, con il bilanciatore fermo) o un servizio gestito. Il backup logico attraverso il router va bene per database piccoli o per esportare singole collezioni.

Pulizia del database di prova:

```bash
sh_eval 'db.getSiblingDB("labdb_ripristino").dropDatabase(); print("eliminato")'
```

---

## Passo 15 — Fine laboratorio: riaccendere tutto il resto

Quando hai finito, spegni il cluster e riaccendi le istanze precedenti con i loro backup notturni:

```bash
cd ~/mongo-lab/03-sharding && sudo docker compose stop

cd ~/mongodb && sudo docker compose start
sudo systemctl enable --now mongo-backup.timer

cd ~/mongo-lab/02-replica-set && sudo docker compose start
sudo systemctl enable --now mongo-rs-backup.timer

sudo docker ps --format "table {{.Names}}\t{{.Status}}"
systemctl list-timers 'mongo*'
free -h
```

✅ Il container `mongo` e i tre `mongo-rs*` in esecuzione, i due timer attivi.

**Lo swap** può restare: non costa nulla finché non serve, e protegge anche le istanze di sviluppo. Se invece vuoi toglierlo:

```bash
sudo swapoff /swapfile
sudo sed -i '\|^/swapfile none swap sw 0 0$|d' /etc/fstab
sudo rm /swapfile
free -h
```

✅ Nella riga `Swap:` compare `0B`. I tre comandi disattivano lo swap, tolgono la riga da `/etc/fstab` (così non viene riattivato al riavvio) e cancellano il file.

---

## Cosa non comprende questa bozza

- **TLS** tra router, config server e shard: si applica la stessa logica della guida 02 (certificato con `serverAuth` e `clientAuth`, migrazione `allowTLS` → `preferTLS` → `requireTLS`), estesa a dieci processi. Se vuoi, lo aggiungiamo come passo facoltativo dopo il collaudo.
- **Backup coerenti** di livello produzione (snapshot coordinati): solo descritti.
- **Zone** (*zone sharding*), per legare intervalli di dati a shard specifici, e **resharding**: argomenti avanzati da valutare.

## Da segnalare durante il collaudo

Per ogni passo, incollami l'output. In particolare mi interessano:

- l'uso di memoria reale dei nodi (Passo 3) e l'eventuale uso dello swap durante il caricamento dei dati (`free -h` dopo il Passo 8);
- eventuali errori del router prima e dopo l'inizializzazione dei config server;
- i valori reali di distribuzione e di `explain`;
- i tempi del caricamento dati e del bilanciamento.
