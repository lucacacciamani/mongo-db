# 04 — CRUD con mongosh: procedura di laboratorio (bozza da collaudare)

> **Bozza di lavoro.** Questa procedura serve a collaudare sul cluster della guida 03 tutti i comandi che finiranno nelle guide `04-crud-guida-completa.md` e `04-crud-guida-rapida.md`. Esegui i blocchi in ordine (anche in giorni diversi), confronta con i ✅ e **incolla l'output dei passi segnati con 📋** (togli password, FQDN e IP). Dopo il collaudo questo file viene eliminato.

**Prerequisiti:** cluster della guida 03 completo, **con TLS**, con l'utente `appuser` (Parte 15 della 03) e il database `labdb` con `ordini` ed `eventi`.

**I dati di esempio sono deterministici:** ogni esecuzione di `dati-crud.js` produce gli stessi documenti, quindi i numeri dei ✅ devono coincidere esattamente. Se un numero è diverso, segnalalo: è proprio ciò che il collaudo deve scoprire.

**Due modi di eseguire i comandi:**

- i blocchi `js` vanno incollati **dentro la shell interattiva** aperta con `app_shell` (prompt `labdb>`), come `appuser`; ogni riga è un comando;
- i blocchi `bash` vanno eseguiti **sulla VM**, fuori dalla shell (`app_eval`, `sh_eval`, `app_export`…).

**Errori previsti:** quando un comando incollato dà errore, mongosh **salta le righe successive** del blocco. Nei passi in cui il ✅ prevede un errore, se dopo l'errore il blocco ha altre righe, rieseguile a mano.

| Blocco | Parti | Contenuto |
|---|---|---|
| **A** | 1–3 | Preparazione, dati di esempio, Create |
| **B** | 4 | Read |
| **C** | 5–7 | Update, Delete, indici |
| **D** | 8–10 | Aggregazione, transazioni, bulkWrite |
| **E** | 11–13 | Validazione, ricerca testuale, change stream |
| **F** | 14–15 | Import/export, pulizia |

---

# Blocco A

## Parte 1 — Preparazione

### 1.1 Il cluster è acceso?

📍 VM

```bash
cd ~/mongo-lab/03-sharding
sudo docker compose start        # se era fermo; altrimenti non fa nulla
source ~/mongo-lab/03-sharding/funzioni-lab.sh
sh_eval 'db.adminCommand({ listShards: 1 }).shards.forEach(s => print(s._id, "stato:", s.state)); print("bilanciatore:", sh.getBalancerState()); print("collezioni di labdb:", db.getSiblingDB("labdb").getCollectionNames().sort().join(", "))'
sudo test -f appuser_password.txt && echo "password di appuser presente"
```

✅ `sh1 stato: 1`, `sh2 stato: 1`, `bilanciatore: true`, `collezioni di labdb: eventi, ordini`, `password di appuser presente`.

📋 **Output.**

```bash
azureuserdgs@azmdb01:~$ cd ~/mongo-lab/03-sharding
azureuserdgs@azmdb01:~/mongo-lab/03-sharding$ sudo docker compose start
azureuserdgs@azmdb01:~/mongo-lab/03-sharding$ source ~/mongo-lab/03-sharding/funzioni-lab.sh
azureuserdgs@azmdb01:~/mongo-lab/03-sharding$ sh_eval 'db.adminCommand({ listShards: 1 }).shards.forEach(s => print(s._id, "stato:", s.state)); print("bilanciatore:", sh.getBalancerState()); print("collezioni di labdb:", db.getSiblingDB("labdb").getCollectionNames().sort().join(", "))'
sh1 stato: 1
sh2 stato: 1
bilanciatore: true
collezioni di labdb: eventi, ordini
azureuserdgs@azmdb01:~/mongo-lab/03-sharding$ sudo test -f appuser_password.txt && echo "password di appuser presente"
password di appuser presente
```

### 1.2 Cartella e file del laboratorio

📍 VM

```bash
mkdir -p ~/mongo-lab/04-crud
```

📍 PC (PowerShell), dalla cartella del repository:

```powershell
scp config\04-crud\funzioni-crud.sh config\04-crud\dati-crud.js config\04-crud\prodotti.csv <utente>@<FQDN>:~/mongo-lab/04-crud/
```

📋 **Output.**

```powershell
PS C:\Users\luca.cacciamani\Github lucacacciamani\mongo-db> scp config/04-crud/funzioni-crud.sh config/04-crud/dati-crud.js config/04-crud/prodotti.csv azureuserdgs@azmdb01.italynorth.cloudapp.azure.com:~/mongo-lab/04-crud/
The authenticity of host 'azmdb01.italynorth.cloudapp.azure.com (4.232.72.51)' can't be established.
ED25519 key fingerprint is SHA256:eT0AH9Hzi609poVVZsp6+dXx6PZR99+czrECqqQ0arQ.
This host key is known by the following other names/addresses:
    C:\Users\luca.cacciamani/.ssh/known_hosts:2: 4.232.72.51
Are you sure you want to continue connecting (yes/no/[fingerprint])? 
Warning: Permanently added 'azmdb01.italynorth.cloudapp.azure.com' (ED25519) to the list of known hosts.
azureuserdgs@azmdb01.italynorth.cloudapp.azure.com's password: 
funzioni-crud.sh                                                                                                                                                100% 1864   107.1KB/s   00:00    
dati-crud.js                                                                                                                                                    100% 7635   573.5KB/s   00:00    
prodotti.csv    
```


📍 VM

```bash
cd ~/mongo-lab/04-crud
ls -l
file funzioni-crud.sh dati-crud.js prodotti.csv     # niente "CRLF"
source ~/mongo-lab/04-crud/funzioni-crud.sh
app_eval 'print("database:", db.getName(), "- utente:", db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers[0].user)'
```

✅ Tre file; `file` non deve mai riportare `with CRLF line terminators`; poi `database: labdb - utente: appuser`.

📋 **Output.**

```bash
azureuserdgs@azmdb01:~/mongo-lab/03-sharding$ cd ~/mongo-lab/04-crud
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ ls -l
total 16
-rw-rw-r-- 1 azureuserdgs azureuserdgs 7635 Oct  1 20:24 dati-crud.js
-rw-rw-r-- 1 azureuserdgs azureuserdgs 1864 Oct  1 20:24 funzioni-crud.sh
-rw-rw-r-- 1 azureuserdgs azureuserdgs  273 Oct  1 20:24 prodotti.csv
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ file funzioni-crud.sh dati-crud.js prodotti.csv     # niente "CRLF"
funzioni-crud.sh: ASCII text
dati-crud.js:     Unicode text, UTF-8 text
prodotti.csv:     CSV ASCII text
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ source ~/mongo-lab/04-crud/funzioni-crud.sh
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_eval 'print("database:", db.getName(), "- utente:", db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers[0].user)'
database: labdb - utente: appuser
```

### 1.3 La shell interattiva

```bash
app_shell
```

✅ Si apre mongosh con un prompt simile a `[direct: mongos] labdb>`. Dentro la shell:

📋 **Output.**

```bash
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_shell
Current Mongosh Log ID: 6abec328675bc0da665fb2bc
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/


To help improve our products, pseudo-anonymous usage data is collected from interactive and agentic sessions only, and sent to MongoDB periodically (https://www.mongodb.com/legal/privacy-policy).
You can opt-out by running the disableTelemetry() command.

[direct: mongos] labdb>
```

```js
db
show dbs
show collections
db.ordini.findOne({}, { _id: 0, clienteId: 1, ordine: 1, importo: 1 })
db.ordini.find({}, { _id: 0, ordine: 1 }).sort({ ordine: 1 })
it
exit
```

✅ `db` → `labdb`. `show dbs` → **solo `labdb`** (appuser non vede gli altri database). `show collections` → `eventi`, `ordini`. `find` mostra 20 documenti e poi `Type "it" for more`; `it` mostra i 20 successivi (ordine da 20 a 39).

📋 **Output** (soprattutto il prompt e `show dbs`).

```js
[direct: mongos] labdb> db
labdb
[direct: mongos] labdb> show dbs
labdb  39.15 MiB
[direct: mongos] labdb> show collections
eventi
ordini
[direct: mongos] labdb> db.ordini.findOne({}, { _id: 0, clienteId: 1, ordine: 1, importo: 1 })
{ clienteId: 6, ordine: 6, importo: 408 }
[direct: mongos] labdb> db.ordini.find({}, { _id: 0, ordine: 1 }).sort({ ordine: 1 })
[
  { ordine: -1 }, { ordine: 0 },
  { ordine: 1 },  { ordine: 2 },
  { ordine: 3 },  { ordine: 4 },
  { ordine: 5 },  { ordine: 6 },
  { ordine: 7 },  { ordine: 8 },
  { ordine: 9 },  { ordine: 10 },
  { ordine: 11 }, { ordine: 12 },
  { ordine: 13 }, { ordine: 14 },
  { ordine: 15 }, { ordine: 16 },
  { ordine: 17 }, { ordine: 18 }
]
Type "it" for more
[direct: mongos] labdb> it
[
  { ordine: 19 }, { ordine: 20 },
  { ordine: 21 }, { ordine: 22 },
  { ordine: 23 }, { ordine: 24 },
  { ordine: 25 }, { ordine: 26 },
  { ordine: 27 }, { ordine: 28 },
  { ordine: 29 }, { ordine: 30 },
  { ordine: 31 }, { ordine: 32 },
  { ordine: 33 }, { ordine: 34 },
  { ordine: 35 }, { ordine: 36 },
  { ordine: 37 }, { ordine: 38 }
]
Type "it" for more
[direct: mongos] labdb> exit

```

Prova anche, senza incollare l'output: `.editor` (si apre un editor multiriga: scrivi `db.ordini.countDocuments()`, poi `Ctrl+D` per eseguire) e la freccia ↑ per richiamare i comandi precedenti.

---

## Parte 2 — Dati di esempio

### 2.1 Distribuire `vendite` prima di caricarla (come admin)

`appuser` non può distribuire collezioni: lo fa l'amministratore, con `sh_eval`.

```bash
sh_eval 'printjson(sh.shardCollection("labdb.vendite", { clienteId: "hashed" }))'
```

✅ `collectionsharded: 'labdb.vendite'`, `ok: 1`.

Prova anche la stessa cosa come appuser, per vedere il rifiuto:

```bash
app_eval 'try { sh.shardCollection("labdb.prova", { x: "hashed" }) } catch (e) { print("appuser:", e.codeName) }'
```

✅ `appuser: Unauthorized`.

📋 **Output.**

```bash
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ sh_eval 'printjson(sh.shardCollection("labdb.vendite", { clienteId: "hashed" }))'
{
  collectionsharded: 'labdb.vendite',
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1790887217, i: 2 }),
    signature: {
      hash: Binary.createFromBase64('h0hVGxlr2EuniufpgqSHsjAAMyk=', 0),
      keyId: Long('7691223719082983439')
    }
  },
  operationTime: Timestamp({ t: 1790887217, i: 2 })
}
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_eval 'try { sh.shardCollection("labdb.prova", { x: "hashed" }) } catch (e) { print("appuser:", e.codeName) }'
appuser: Unauthorized

```

### 2.2 Caricamento

```bash
cd ~/mongo-lab/04-crud
time app_eval "$(cat dati-crud.js)"
```

✅ `prodotti: 30 - clienti: 50 - vendite: 5000`, in pochi secondi.

```bash
sh_eval 'db.getSiblingDB("labdb").vendite.getShardDistribution()'
sh_eval 'const d = db.getSiblingDB("config"); ["clienti", "prodotti", "vendite"].forEach(n => print(n, d.collections.findOne({ _id: "labdb." + n }) ? "distribuita" : "non distribuita")); print("shard primario di labdb:", d.databases.findOne({ _id: "labdb" }).primary)'
```

✅ `vendite` divisa più o meno a metà tra `sh1` e `sh2`; `clienti` e `prodotti` **non distribuite**, `vendite` **distribuita**; lo shard primario di `labdb` (dove stanno `clienti` e `prodotti`).

📋 **Output** (con il tempo di `time`).

```bash
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ cd ~/mongo-lab/04-crud
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ time app_eval "$(cat dati-crud.js)"
prodotti: 30 - clienti: 50 - vendite: 5000

real    0m20.200s
user    0m0.011s
sys     0m0.016s
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ sh_eval 'db.getSiblingDB("labdb").vendite.getShardDistribution()'
Shard sh2 at sh2/mongo-sh2a:27221,mongo-sh2b:27222,mongo-sh2c:27223
{
  data: '460KiB',
  docs: 1876,
  chunks: 1,
  'estimated data per chunk': '460KiB',
  'estimated docs per chunk': 1876
}
---
Shard sh1 at sh1/mongo-sh1a:27211,mongo-sh1b:27212,mongo-sh1c:27213
{
  data: '762KiB',
  docs: 3124,
  chunks: 1,
  'estimated data per chunk': '762KiB',
  'estimated docs per chunk': 3124
}
---
Totals
{
  data: '1.19MiB',
  docs: 5000,
  chunks: 2,
  'Shard sh2': [
    '37.65 % data',
    '37.52 % docs in cluster',
    '251B avg obj size on shard'
  ],
  'Shard sh1': [
    '62.34 % data',
    '62.48 % docs in cluster',
    '249B avg obj size on shard'
  ]
}
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ sh_eval 'const d = db.getSiblingDB("config"); ["clienti", "prodotti", "vendite"].forEach(n => print(n, d.collections.findOne({ _id: "labdb." + n }) ? "distribuita" : "non distribuita")); print("shard primario di labdb:", d.databases.findOne({ _id: "labdb" }).primary)'
clienti non distribuita
prodotti non distribuita
vendite distribuita
shard primario di labdb: sh2

```

---

## Parte 3 — Create

```bash
app_shell
```

**Solo se ripeti la Parte 3** (altrimenti gli inserimenti falliscono con `E11000` perché i documenti esistono già), riporta la situazione a prima della parte:

```js
db.clienti.deleteOne({ _id: 51 })
db.prove.drop()
```

### 3.1 `insertOne`, con e senza `_id`

```js
db.clienti.insertOne({ _id: 51, nome: "Anna", cognome: "Verdi", email: "anna.verdi51@esempio.it", tipo: "privato", indirizzo: { citta: "Genova", provincia: "GE", cap: "16121" }, interessi: ["musica"], punti: 0, newsletter: true, iscritto: new Date() })
db.prove.insertOne({ testo: "documento senza _id" })
const doc = db.prove.findOne({ testo: "documento senza _id" })
doc._id
doc._id.getTimestamp()
```

✅ Il primo: `insertedId: 51`. Il secondo: `insertedId: ObjectId('...')`, generato dalla shell; `getTimestamp()` restituisce l'istante di creazione (l'ObjectId contiene la data). La collezione `prove` **non esisteva**: è stata creata dal primo inserimento.

### 3.2 `_id` duplicato

```js
db.clienti.insertOne({ _id: 51, nome: "Doppione" })
```

✅ `MongoServerError: E11000 duplicate key error collection: labdb.clienti index: _id_ dup key: { _id: 51 }`.

### 3.3 `insertMany` ordinato e non ordinato

Incolla i blocchi **uno alla volta**: ogni `insertMany` dà un errore, e dopo un errore mongosh non esegue il resto del blocco.

```js
db.prove.insertMany([{ _id: 1 }, { _id: 1 }, { _id: 2 }])
```

```js
db.prove.find({ _id: { $type: "number" } })
```

```js
db.prove.insertMany([{ _id: 3 }, { _id: 3 }, { _id: 4 }], { ordered: false })
```

```js
db.prove.find({ _id: { $type: "number" } })
```

✅ Primo `insertMany`: errore `E11000` su `index: 1`, `insertedCount: 1` (l'inserimento **ordinato** si ferma al primo errore: `2` non viene inserito); il `find` mostra solo `1`. Secondo: errore su `index: 1`, ma `insertedCount: 2`, inseriti `3` e `4` (il **non ordinato** prosegue). Alla fine: `[ { _id: 1 }, { _id: 3 }, { _id: 4 } ]`.

### 3.4 I tipi

```js
db.prove.insertOne({ _id: "tipi", intero: 42, grande: NumberLong("9007199254740993"), decimale: NumberDecimal("0.1"), doppio: 0.1, data: new Date("2026-10-01T10:00:00Z"), vero: true, nullo: null, lista: [1, "a", { b: 2 }], annidato: { a: { b: 1 } } })
db.prove.aggregate([{ $match: { _id: "tipi" } }, { $project: { _id: 0, intero: { $type: "$intero" }, grande: { $type: "$grande" }, decimale: { $type: "$decimale" }, doppio: { $type: "$doppio" }, data: { $type: "$data" }, vero: { $type: "$vero" }, nullo: { $type: "$nullo" }, lista: { $type: "$lista" }, annidato: { $type: "$annidato" } } }])
db.prove.aggregate([{ $match: { _id: "tipi" } }, { $project: { _id: 0, conDouble: { $add: [0.1, 0.2] }, conDecimal: { $add: [NumberDecimal("0.1"), NumberDecimal("0.2")] } } }])
db.prodotti.findOne({ _id: "P002" })
exit
```

✅ Tipi attesi: `int`, `long`, `decimal`, `double`, `date`, `bool`, `null`, `array`, `object`. Poi `conDouble: 0.30000000000000004` e `conDecimal: Decimal128('0.3')`: per gli importi si usa **Decimal128**. In `P002` il prezzo compare come `Decimal128('24.90')`.

📋 **Output di tutta la Parte 3** (l'intera sessione della shell).

```bash
[direct: mongos] labdb> db.clienti.deleteOne({ _id: 51 })
{ acknowledged: true, deletedCount: 1 }
[direct: mongos] labdb> db.prove.drop()
true
[direct: mongos] labdb> db.clienti.insertOne({ _id: 51, nome: "Anna", cognome: "Verdi", email: "anna.verdi51@esempio.it", tipo: "privato", indirizzo: { citta: "Genova", provincia: "GE", cap: "16121" }, interessi: ["musica"], punti: 0, newsletter: true, iscritto: new Date() })
{ acknowledged: true, insertedId: 51 }
[direct: mongos] labdb> db.prove.insertOne({ testo: "documento senza _id" })
{
  acknowledged: true,
  insertedId: ObjectId('6abecc1756625062b7f55dc9')
}
[direct: mongos] labdb> const doc = db.prove.findOne({ testo: "documento senza _id" })

[direct: mongos] labdb> doc._id
ObjectId('6abecc1756625062b7f55dc9')
[direct: mongos] labdb> doc._id.getTimestamp()
ISODate('2026-10-01T21:09:43.000Z')
[direct: mongos] labdb> db.clienti.insertOne({ _id: 51, nome: "Doppione" })
MongoServerError: E11000 duplicate key error collection: labdb.clienti index: _id_ dup key: { _id: 51 }
[direct: mongos] labdb> db.prove.insertMany([{ _id: 1 }, { _id: 1 }, { _id: 2 }])
Uncaught:
MongoBulkWriteError: E11000 duplicate key error collection: labdb.prove index: _id_ dup key: { _id: 1 }
Result: BulkWriteResult {
  insertedCount: 1,
  matchedCount: 0,
  modifiedCount: 0,
  deletedCount: 0,
  upsertedCount: 0,
  upsertedIds: {},
  insertedIds: { '0': 1 }
}
Write Errors: [
  WriteError {
    err: {
      index: 1,
      code: 11000,
      errmsg: 'E11000 duplicate key error collection: labdb.prove index: _id_ dup key: { _id: 1 }',
      errInfo: undefined,
      op: { _id: 1 }
    }
  }
]
[direct: mongos] labdb> db.prove.find({ _id: { $type: "number" } })
[ { _id: 1 } ]
[direct: mongos] labdb> db.prove.insertMany([{ _id: 3 }, { _id: 3 }, { _id: 4 }], { ordered: false })
Uncaught:
MongoBulkWriteError: E11000 duplicate key error collection: labdb.prove index: _id_ dup key: { _id: 3 }
Result: BulkWriteResult {
  insertedCount: 2,
  matchedCount: 0,
  modifiedCount: 0,
  deletedCount: 0,
  upsertedCount: 0,
  upsertedIds: {},
  insertedIds: { '0': 3, '2': 4 }
}
Write Errors: [
  WriteError {
    err: {
      index: 1,
      code: 11000,
      errmsg: 'E11000 duplicate key error collection: labdb.prove index: _id_ dup key: { _id: 3 }',
      errInfo: undefined,
      op: { _id: 3 }
    }
  }
]
[direct: mongos] labdb> db.prove.find({ _id: { $type: "number" } })
[ { _id: 1 }, { _id: 3 }, { _id: 4 } ]
[direct: mongos] labdb> db.prove.insertOne({ _id: "tipi", intero: 42, grande: NumberLong("9007199254740993"), decimale: NumberDecimal("0.1"), doppio: 0.1, data: new Date("2026-10-01T10:00:00Z"), vero: true, nullo: null, lista: [1, "a", { b: 2 }], annidato: { a: { b: 1 } } })
{ acknowledged: true, insertedId: 'tipi' }
[direct: mongos] labdb> db.prove.aggregate([{ $match: { _id: "tipi" } }, { $project: { _id: 0, intero: { $type: "$intero" }, grande: { $type: "$grande" }, decimale: { $type: "$decimale" }, doppio: { $type: "$doppio" }, data: { $type: "$data" }, vero: { $type: "$vero" }, nullo: { $type: "$nullo" }, lista: { $type: "$lista" }, annidato: { $type: "$annidato" } } }])
[
  {
    intero: 'int',
    grande: 'long',
    decimale: 'decimal',
    doppio: 'double',
    data: 'date',
    vero: 'bool',
    nullo: 'null',
    lista: 'array',
    annidato: 'object'
  }
]
[direct: mongos] labdb> db.prove.aggregate([{ $match: { _id: "tipi" } }, { $project: { _id: 0, conDouble: { $add: [0.1, 0.2] }, conDecimal: { $add: [NumberDecimal("0.1"), NumberDecimal("0.2")] } } }])
[ { conDouble: 0.30000000000000004, conDecimal: Decimal128('0.3') } ]
[direct: mongos] labdb> db.prodotti.findOne({ _id: "P002" })
{
  _id: 'P002',
  nome: 'Mouse senza fili',
  categoria: 'Informatica',
  prezzo: Decimal128('24.90'),
  giacenza: 140,
  tags: [ 'accessori', 'wireless' ],
  descrizione: 'Mouse ergonomico senza fili con batteria ricaricabile'
}
[direct: mongos] labdb> exit
```

**Nota dal collaudo:** rilanciando l'`insertMany` non ordinato della 3.3 con i documenti già presenti si ottengono **tre** `WriteError` (`index` 0, 1 e 2) e `insertedCount: 0`: il non ordinato tenta comunque tutti i documenti.

---


# Blocco B

## Parte 4 — Read

```bash
source ~/mongo-lab/04-crud/funzioni-crud.sh     # se hai riaperto la sessione SSH
app_shell
```

### 4.1 Uguaglianza, dot notation, proiezione

```js
db.clienti.find({ "indirizzo.citta": "Milano" }, { _id: 0, nome: 1, cognome: 1 })
db.clienti.findOne({ _id: 7 })
db.clienti.findOne({ _id: 7 }, { email: 1, "indirizzo.citta": 1 })
db.clienti.findOne({ _id: 7 }, { interessi: 0, indirizzo: 0 })
```

✅ **12** clienti di Milano. La proiezione con `1` include i campi (più `_id`, salvo `_id: 0`); quella con `0` li esclude.

### 4.2 Confronto e operatori logici

```js
db.clienti.find({ punti: { $gte: 400 } }, { nome: 1, punti: 1 }).sort({ punti: -1 })
db.clienti.countDocuments({ tipo: "azienda", newsletter: true })
db.clienti.countDocuments({ $or: [ { "indirizzo.citta": "Roma" }, { punti: { $lt: 20 } } ] })
db.clienti.countDocuments({ "indirizzo.provincia": { $in: ["TO", "VE"] } })
db.clienti.countDocuments({ telefono: { $exists: false } })
db.clienti.countDocuments({ iscritto: { $type: "date" } })
db.clienti.find({ email: { $regex: /^giulia\./ } }, { _id: 0, email: 1 })
db.prodotti.find({ prezzo: { $gt: 200 } }, { nome: 1, prezzo: 1 }).sort({ prezzo: -1 })
db.prodotti.find({ categoria: { $ne: "Libri" }, tags: "ufficio" }, { nome: 1 })
```

✅ Nell'ordine: **13** clienti con almeno 400 punti (il primo `_id: 19` con 490); **7**; **6** (Anna ha 0 punti); **14**; **15** senza telefono (anche Anna); **51** (tutti: anche Anna ha `iscritto` di tipo data); **4** email `giulia.…`; **5** prodotti sopra 200 € (P001, P004, P012, P023, P029: il confronto tra `200`, un numero intero, e i prezzi `Decimal128` funziona, perché MongoDB confronta i numeri per valore anche se di tipo diverso); **5** prodotti con tag `ufficio` (P001, P004, P011, P029, P030).

### 4.3 Array

```js
db.clienti.countDocuments({ interessi: "montagna" })
db.clienti.find({ interessi: { $all: ["sport", "viaggi"] } }, { _id: 1, interessi: 1 })
db.clienti.countDocuments({ interessi: { $size: 3 } })
db.vendite.countDocuments({ "righe.prodottoId": "P001", "righe.qta": { $gte: 2 } })
db.vendite.countDocuments({ righe: { $elemMatch: { prodottoId: "P001", qta: { $gte: 2 } } } })
db.vendite.findOne({ righe: { $elemMatch: { prodottoId: "P001", qta: { $gte: 2 } } } }, { _id: 0, clienteId: 1, righe: 1 })
```

✅ **12**; **6** clienti (9, 11, 16, 17, 42, 44); **29**; **278** contro **208**. Senza `$elemMatch` basta che **una** riga sia P001 e **una qualsiasi** abbia `qta ≥ 2`; con `$elemMatch` le due condizioni devono valere per **la stessa** riga.

### 4.4 Ordinamento, paginazione, conteggi, `distinct`

```js
db.prodotti.find({}, { nome: 1 }).sort({ _id: 1 }).skip(10).limit(5)
db.prodotti.find({ _id: { $gt: "P015" } }, { nome: 1 }).sort({ _id: 1 }).limit(5)
db.vendite.estimatedDocumentCount()
db.vendite.countDocuments()
db.vendite.countDocuments({ data: { $gte: ISODate("2026-03-01"), $lt: ISODate("2026-04-01") } })
db.clienti.distinct("indirizzo.citta")
db.vendite.distinct("stato")
```

✅ P011–P015; P016–P020 (paginazione «per chiave»: riparte dall'ultimo `_id` visto invece di saltare documenti); **5000** e **5000**; **496** vendite a marzo; 9 città (le 8 dei dati più `Genova`); 4 stati.

### 4.5 Cursori

```js
const cur = db.vendite.find({ clienteId: 7 }, { _id: 0, data: 1, totale: 1 }).sort({ data: 1 })
cur.hasNext()
cur.next()
cur.toArray().length
let somma = 0; db.vendite.find({ clienteId: 7 }).forEach(v => { somma += 1 }); somma
```

✅ `true`, la prima vendita del cliente 7, poi **92** (le restanti: in tutto sono **93**), infine **93**.

### 4.6 Query mirate e su tutti gli shard

```js
db.vendite.find({ clienteId: 7 }).explain().queryPlanner.winningPlan.stage
db.vendite.find({ stato: "annullata" }).explain().queryPlanner.winningPlan.stage
db.vendite.find().sort({ data: -1 }).limit(5).explain().queryPlanner.winningPlan.stage
db.clienti.find({ _id: 7 }).explain().queryPlanner.winningPlan.stage
exit
```

✅ `SINGLE_SHARD` (contiene la shard key), `SHARD_MERGE` (tutti gli shard), `SHARD_MERGE_SORT` (tutti gli shard, ordinati e fusi dal router), `SINGLE_SHARD` (collezione non distribuita: vive sullo shard primario).

📋 **Output di tutta la Parte 4.**

```bash
azureuserdgs@azmdb01:~$ source ~/mongo-lab/04-crud/funzioni-crud.sh
azureuserdgs@azmdb01:~$ app_shell
Current Mongosh Log ID: 6af9a7f9427febc77f4f4bf5
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/

[direct: mongos] labdb> db.clienti.find({ "indirizzo.citta": "Milano" }, { _id: 0, nome: 1, cognomcognome: 1 })
[
  { nome: 'Elena', cognome: 'Esposito' },
  { nome: 'Matteo', cognome: 'Gallo' },
  { nome: 'Paolo', cognome: 'Bruno' },
  { nome: 'Matteo', cognome: 'Esposito' },
  { nome: 'Francesca', cognome: 'Marino' },
  { nome: 'Sara', cognome: 'Colombo' },
  { nome: 'Andrea', cognome: 'Ricci' },
  { nome: 'Luca', cognome: 'Colombo' },
  { nome: 'Luca', cognome: 'Bruno' },
  { nome: 'Luca', cognome: 'Ricci' },
  { nome: 'Luca', cognome: 'Bruno' },
  { nome: 'Francesca', cognome: 'Ricci' }
]
[direct: mongos] labdb> db.clienti.findOne({ _id: 7 })
{
  _id: 7,
  nome: 'Matteo',
  cognome: 'Gallo',
  email: 'matteo.gallo7@esempio.it',
  tipo: 'privato',
  indirizzo: { citta: 'Milano', provincia: 'MI', cap: '20121' },
  interessi: [ 'sport', 'cucina', 'lettura' ],
  punti: 108,
  newsletter: false,
  iscritto: ISODate('2025-06-06T00:00:00.000Z')
}
[direct: mongos] labdb> db.clienti.findOne({ _id: 7 }, { email: 1, "indirizzo.citta": 1 })
{
  _id: 7,
  email: 'matteo.gallo7@esempio.it',
  indirizzo: { citta: 'Milano' }
}
[direct: mongos] labdb> db.clienti.findOne({ _id: 7 }, { interessi: 0, indirizzo: 0 })
{
  _id: 7,
  nome: 'Matteo',
  cognome: 'Gallo',
  email: 'matteo.gallo7@esempio.it',
  tipo: 'privato',
  punti: 108,
  newsletter: false,
  iscritto: ISODate('2025-06-06T00:00:00.000Z')
}
[direct: mongos] labdb>

[direct: mongos] labdb> db.clienti.find({ punti: { $gte: 400 } }, { nome: 1, punti: 1 }).sort({ pupunti: -1 })
[
  { _id: 19, nome: 'Chiara', punti: 490 },
  { _id: 12, nome: 'Sara', punti: 486 },
  { _id: 16, nome: 'Matteo', punti: 479 },
  { _id: 48, nome: 'Francesca', punti: 479 },
  { _id: 32, nome: 'Luca', punti: 467 },
  { _id: 45, nome: 'Andrea', punti: 454 },
  { _id: 26, nome: 'Chiara', punti: 442 },
  { _id: 34, nome: 'Chiara', punti: 435 },
  { _id: 43, nome: 'Paolo', punti: 409 },
  { _id: 24, nome: 'Giulia', punti: 406 },
  { _id: 8, nome: 'Paolo', punti: 405 },
  { _id: 13, nome: 'Matteo', punti: 404 },
  { _id: 25, nome: 'Luca', punti: 403 }
]
[direct: mongos] labdb> db.clienti.countDocuments({ tipo: "azienda", newsletter: true })
7
[direct: mongos] labdb> db.clienti.countDocuments({ $or: [ { "indirizzo.citta": "Roma" }, { punti: { $lt: 20 } } ] })
6
[direct: mongos] labdb> db.clienti.countDocuments({ "indirizzo.provincia": { $in: ["TO", "VE"] } })
14
[direct: mongos] labdb> db.clienti.countDocuments({ telefono: { $exists: false } })
15
[direct: mongos] labdb> db.clienti.countDocuments({ iscritto: { $type: "date" } })
51
[direct: mongos] labdb> db.clienti.find({ email: { $regex: /^giulia\./ } }, { _id: 0, email: 1 })
[
  { email: 'giulia.esposito2@esempio.it' },
  { email: 'giulia.bruno20@esempio.it' },
  { email: 'giulia.bianchi24@esempio.it' },
  { email: 'giulia.romano40@esempio.it' }
]
[direct: mongos] labdb> db.prodotti.find({ prezzo: { $gt: 200 } }, { nome: 1, prezzo: 1 }).sort({ prezzo: -1 })
[
  {
    _id: 'P001',
    nome: 'Portatile 14 pollici',
    prezzo: Decimal128('899.00')
  },
  {
    _id: 'P023',
    nome: 'Bicicletta da città',
    prezzo: Decimal128('399.00')
  },
  {
    _id: 'P012',
    nome: 'Aspirapolvere robot',
    prezzo: Decimal128('299.00')
  },
  {
    _id: 'P004',
    nome: 'Monitor 27 pollici',
    prezzo: Decimal128('249.00')
  },
  { _id: 'P029', nome: 'Sedia ergonomica', prezzo: Decimal128('219.00') }
]
[direct: mongos] labdb> db.prodotti.find({ categoria: { $ne: "Libri" }, tags: "ufficio" }, { nome: 1 })
[
  { _id: 'P001', nome: 'Portatile 14 pollici' },
  { _id: 'P004', nome: 'Monitor 27 pollici' },
  { _id: 'P011', nome: 'Lampada da scrivania' },
  { _id: 'P029', nome: 'Sedia ergonomica' },
  { _id: 'P030', nome: 'Stampante laser' }
]
[direct: mongos] labdb> db.clienti.countDocuments({ interessi: "montagna" })
12
[direct: mongos] labdb> db.clienti.find({ interessi: { $all: ["sport", "viaggi"] } }, { _id: 1,intinteressi: 1 })
[
  { _id: 9, interessi: [ 'lettura', 'sport', 'viaggi' ] },
  { _id: 11, interessi: [ 'sport', 'viaggi' ] },
  { _id: 16, interessi: [ 'montagna', 'viaggi', 'sport' ] },
  { _id: 17, interessi: [ 'viaggi', 'sport', 'informatica' ] },
  { _id: 42, interessi: [ 'cucina', 'sport', 'viaggi' ] },
  { _id: 44, interessi: [ 'sport', 'viaggi', 'lettura' ] }
]
[direct: mongos] labdb> db.clienti.countDocuments({ interessi: { $size: 3 } })
29
[direct: mongos] labdb> db.vendite.countDocuments({ "righe.prodottoId": "P001", "righe.qta": { $gt$gte: 2 } })
278
[direct: mongos] labdb> db.vendite.countDocuments({ righe: { $elemMatch: { prodottoId: "P001", qta: { $gte: 2 } } } })
208
[direct: mongos] labdb> db.vendite.findOne({ righe: { $elemMatch: { prodottoId: "P001", qta: { $gt$gte: 2 } } } }, { _id: 0, clienteId: 1, righe: 1 })
{
  clienteId: 4,
  righe: [
    { prodottoId: 'P001', qta: 3, prezzo: Decimal128('899.00') },
    { prodottoId: 'P019', qta: 1, prezzo: Decimal128('19.00') }
  ]
}
[direct: mongos] labdb> db.prodotti.find({}, { nome: 1 }).sort({ _id: 1 }).skip(10).limit(5)
[
  { _id: 'P011', nome: 'Lampada da scrivania' },
  { _id: 'P012', nome: 'Aspirapolvere robot' },
  { _id: 'P013', nome: 'Set di pentole' },
  { _id: 'P014', nome: "Purificatore d'aria" },
  { _id: 'P015', nome: 'Il nome della rosa' }
]
[direct: mongos] labdb> db.prodotti.find({ _id: { $gt: "P015" } }, { nome: 1 }).sort({ _id: 1 }).limit(5)
[
  { _id: 'P016', nome: 'I promessi sposi' },
  { _id: 'P017', nome: 'Imparare MongoDB' },
  { _id: 'P018', nome: 'Cucina regionale' },
  { _id: 'P019', nome: 'Guida alle Dolomiti' },
  { _id: 'P020', nome: 'Atlante del cielo' }
]
[direct: mongos] labdb> db.vendite.estimatedDocumentCount()
5000
[direct: mongos] labdb> db.vendite.countDocuments()
5000
[direct: mongos] labdb> db.vendite.countDocuments({ data: { $gte: ISODate("2026-03-01"), $lt: ISODate("2026-04-01") } })
496
[direct: mongos] labdb> db.clienti.distinct("indirizzo.citta")
[
  'Bari',    'Bologna',
  'Firenze', 'Genova',
  'Milano',  'Napoli',
  'Roma',    'Torino',
  'Venezia'
]
[direct: mongos] labdb> db.vendite.distinct("stato")
[ 'annullata', 'consegnata', 'in lavorazione', 'spedita' ]
[direct: mongos] labdb> const cur = db.vendite.find({ clienteId: 7 }, { _id: 0, data: 1, totale: 1 }).sort({ data: 1 })

[direct: mongos] labdb> cur.hasNext()
true
[direct: mongos] labdb> cur.next()
{
  data: ISODate('2026-01-02T12:00:00.000Z'),
  totale: Decimal128('19.90')
}
[direct: mongos] labdb> cur.toArray().length
92
[direct: mongos] labdb> let somma = 0; db.vendite.find({ clienteId: 7 }).forEach(v => { somma += 1 }); somma
93
[direct: mongos] labdb> db.vendite.find({ clienteId: 7 }).explain().queryPlanner.winningPlan.stage
SINGLE_SHARD
[direct: mongos] labdb> db.vendite.find({ stato: "annullata" }).explain().queryPlanner.winningPlan.stage
SHARD_MERGE
[direct: mongos] labdb> db.vendite.find().sort({ data: -1 }).limit(5).explain().queryPlanner.winningPlan.stage
SHARD_MERGE_SORT
[direct: mongos] labdb> db.clienti.find({ _id: 7 }).explain().queryPlanner.winningPlan.stage
SINGLE_SHARD
[direct: mongos] labdb>

```

---

# Blocco C

## Parte 5 — Update

```bash
source ~/mongo-lab/04-crud/funzioni-crud.sh     # se hai riaperto la sessione SSH
app_shell
```

### 5.1 Operatori di campo

```js
db.clienti.updateOne({ _id: 51 }, { $set: { telefono: "+39 3331234567", "indirizzo.cap": "16122" } })
db.clienti.updateOne({ _id: 51 }, { $set: { telefono: "+39 3331234567", "indirizzo.cap": "16122" } })
db.clienti.updateOne({ _id: 51 }, { $inc: { punti: 50 }, $currentDate: { aggiornato: true } })
db.clienti.updateOne({ _id: 51 }, { $unset: { newsletter: "" }, $rename: { telefono: "cellulare" } })
db.clienti.findOne({ _id: 51 })
```

✅ Primo: `matchedCount: 1, modifiedCount: 1`. Secondo, identico: `matchedCount: 1, modifiedCount: 0` (i valori erano già quelli). Alla fine Anna ha `punti: 50`, `aggiornato` con la data attuale, `cellulare` al posto di `telefono`, nessun `newsletter`, cap `16122`.

### 5.2 Operatori sugli array

```js
db.clienti.updateOne({ _id: 51 }, { $push: { interessi: "viaggi" } })
db.clienti.updateOne({ _id: 51 }, { $addToSet: { interessi: "viaggi" } })
db.clienti.updateOne({ _id: 51 }, { $push: { interessi: { $each: ["cucina", "lettura"] } } })
db.clienti.updateOne({ _id: 51 }, { $pull: { interessi: "musica" } })
db.clienti.findOne({ _id: 51 }, { interessi: 1 })
```

✅ `$addToSet` con un valore già presente: `modifiedCount: 0`. Alla fine: `[ 'viaggi', 'cucina', 'lettura' ]`.

### 5.3 `updateMany`, update con pipeline, `upsert`

```js
db.prodotti.updateMany({ giacenza: 0 }, { $set: { disponibile: false } })
db.prodotti.updateMany({ categoria: "Libri" }, [ { $set: { prezzo: { $round: [ { $multiply: ["$prezzo", NumberDecimal("0.9")] }, 2 ] } } } ])
db.prodotti.find({ categoria: "Libri" }, { prezzo: 1 })
db.prodotti.updateOne({ _id: "P099" }, { $set: { nome: "Prodotto di prova", categoria: "Prove" }, $setOnInsert: { giacenza: 0, creato: new Date() } }, { upsert: true })
db.prodotti.updateOne({ _id: "P099" }, { $set: { nome: "Prodotto di prova", categoria: "Prove" }, $setOnInsert: { giacenza: 0, creato: new Date() } }, { upsert: true })
```

✅ **3** prodotti esauriti (P007, P014, P026). Libri scontati del 10%: 12.60, 10.80, 35.10, 22.50, 17.10, 26.10 (mostrati come `Decimal128('12.60')`: l'arrotondamento a 2 decimali è conservato). Primo upsert: `insertedId: 'P099', matchedCount: 0, upsertedCount: 1`; secondo: `insertedId: null, matchedCount: 1, modifiedCount: 0, upsertedCount: 0`.

### 5.4 Elementi di un array: `$` e `arrayFilters`

```js
db.vendite.countDocuments({ clienteId: 7, "righe.prodottoId": "P002" })
db.vendite.updateMany({ clienteId: 7, "righe.prodottoId": "P002" }, { $set: { "righe.$[r].sconto": NumberDecimal("2.00") } }, { arrayFilters: [ { "r.prodottoId": "P002" } ] })
db.vendite.findOne({ clienteId: 7, "righe.sconto": { $exists: true } }, { _id: 0, righe: 1 })
const v7 = db.vendite.findOne({ clienteId: 7, "righe.prodottoId": "P002" })
db.vendite.updateOne({ _id: v7._id, clienteId: 7, "righe.prodottoId": "P002" }, { $inc: { "righe.$.qta": 1 } })
db.vendite.findOne({ _id: v7._id }, { _id: 0, righe: 1 })
```

✅ **13** vendite; `updateMany`: `matchedCount: 13, modifiedCount: 13`; lo sconto compare solo nelle righe di P002. `$` aggiorna **la prima** riga che corrisponde al filtro: la `qta` di P002 aumenta di 1.

### 5.5 `replaceOne` e `findOneAndUpdate`

```js
db.prove.replaceOne({ _id: 1 }, { testo: "documento sostituito" })
db.prove.findOne({ _id: 1 })
db.prodotti.findOneAndUpdate({ _id: "P002" }, { $inc: { giacenza: -1 } }, { projection: { giacenza: 1 } })
db.prodotti.findOneAndUpdate({ _id: "P002" }, { $inc: { giacenza: -1 } }, { projection: { giacenza: 1 }, returnDocument: "after" })
```

✅ Dopo `replaceOne` il documento ha solo `_id` e `testo`. `findOneAndUpdate` restituisce il documento **prima** della modifica (`giacenza: 140`), oppure **dopo** con `returnDocument: "after"` (`giacenza: 138`).

### 5.6 Update su una collezione distribuita

```js
db.vendite.updateOne({ stato: "annullata", canale: "telefono" }, { $set: { nota: "verificata" } })
db.vendite.insertOne({ _id: "prova-sk", clienteId: 99, stato: "prova", totale: NumberDecimal("1.00") })
db.vendite.updateOne({ _id: "prova-sk", clienteId: 99 }, { $set: { clienteId: 98 } })
db.vendite.findOne({ _id: "prova-sk" })
db.vendite.updateMany({ clienteId: 98 }, { $set: { clienteId: 97 } })
```

✅ Il primo funziona anche senza shard key nel filtro (`matchedCount: 1, modifiedCount: 1`; consentito da MongoDB 7.1). Cambiare il **valore** della shard key con `updateOne` funziona (`matchedCount: 1, modifiedCount: 1`; il documento può cambiare shard) e il `findOne` mostra `clienteId: 98`. Con `updateMany` l'operazione viene rifiutata: `MongoServerError: Multi-update operations are not allowed when updating the shard key field.`

📋 **Output della Parte 5.**

```bash
azureuserdgs@azmdb01:~$ source ~/mongo-lab/04-crud/funzioni-crud.sh
azureuserdgs@azmdb01:~$ app_shell
Current Mongosh Log ID: 6af9ba5cee5a2830d4c48f2f
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/

[direct: mongos] labdb> db.clienti.updateOne({ _id: 51 }, { $set: { telefono: "+39 3331234567", "indirizzo.cap": "16122" } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.clienti.updateOne({ _id: 51 }, { $set: { telefono: "+39 3331234567", "indirizzo.cap": "16122" } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 0,
  upsertedCount: 0
}
[direct: mongos] labdb> db.clienti.updateOne({ _id: 51 }, { $inc: { punti: 50 }, $currentDate: { aaggiornato: true } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.clienti.updateOne({ _id: 51 }, { $unset: { newsletter: "" }, $rename: { telefono: "cellulare" } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.clienti.findOne({ _id: 51 })
{
  _id: 51,
  nome: 'Anna',
  cognome: 'Verdi',
  email: 'anna.verdi51@esempio.it',
  tipo: 'privato',
  indirizzo: { citta: 'Genova', provincia: 'GE', cap: '16122' },
  interessi: [ 'musica' ],
  punti: 50,
  iscritto: ISODate('2026-10-01T21:09:33.693Z'),
  aggiornato: ISODate('2026-11-15T13:58:29.637Z'),
  cellulare: '+39 3331234567'
}
[direct: mongos] labdb> db.clienti.updateOne({ _id: 51 }, { $push: { interessi: "viaggi" } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.clienti.updateOne({ _id: 51 }, { $addToSet: { interessi: "viaggi" } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 0,
  upsertedCount: 0
}
[direct: mongos] labdb> db.clienti.updateOne({ _id: 51 }, { $push: { interessi: { $each: ["cucina", "lettura"] } } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.clienti.updateOne({ _id: 51 }, { $pull: { interessi: "musica" } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.clienti.findOne({ _id: 51 }, { interessi: 1 })
{ _id: 51, interessi: [ 'viaggi', 'cucina', 'lettura' ] }
[direct: mongos] labdb> db.prodotti.updateMany({ giacenza: 0 }, { $set: { disponibile: false } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 3,
  modifiedCount: 3,
  upsertedCount: 0
}
[direct: mongos] labdb> db.prodotti.updateMany({ categoria: "Libri" }, [ { $set: { prezzo: { $roun$round: [ { $multiply: ["$prezzo", NumberDecimal("0.9")] }, 2 ] } } } ])
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 6,
  modifiedCount: 6,
  upsertedCount: 0
}
[direct: mongos] labdb> db.prodotti.find({ categoria: "Libri" }, { prezzo: 1 })
[
  { _id: 'P015', prezzo: Decimal128('12.60') },
  { _id: 'P016', prezzo: Decimal128('10.80') },
  { _id: 'P017', prezzo: Decimal128('35.10') },
  { _id: 'P018', prezzo: Decimal128('22.50') },
  { _id: 'P019', prezzo: Decimal128('17.10') },
  { _id: 'P020', prezzo: Decimal128('26.10') }
]
[direct: mongos] labdb> db.prodotti.updateOne({ _id: "P099" }, { $set: { nome: "Prodotto di prova", categoria: "Prove" }, $setOnInsert: { giacenza: 0, creato: new Date() } }, { upsert: true })
{
  acknowledged: true,
  insertedId: 'P099',
  matchedCount: 0,
  modifiedCount: 0,
  upsertedCount: 1
}
[direct: mongos] labdb> db.prodotti.updateOne({ _id: "P099" }, { $set: { nome: "Prodotto di prova", categoria: "Prove" }, $setOnInsert: { giacenza: 0, creato: new Date() } }, { upsert: true })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 0,
  upsertedCount: 0
}
[direct: mongos] labdb> db.vendite.countDocuments({ clienteId: 7, "righe.prodottoId": "P002" })
13
[direct: mongos] labdb> db.vendite.updateMany({ clienteId: 7, "righe.prodottoId": "P002" }, { $set: { "righe.$[r].sconto": NumberDecimal("2.00") } }, { arrayFilters: [ { "r.prodottoId": "P002" } ] })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 13,
  modifiedCount: 13,
  upsertedCount: 0
}
[direct: mongos] labdb> db.vendite.findOne({ clienteId: 7, "righe.sconto": { $exists: true } }, { _id: 0, righe: 1 })
{
  righe: [
    { prodottoId: 'P005', qta: 2, prezzo: Decimal128('45.90') },
    {
      prodottoId: 'P002',
      qta: 1,
      prezzo: Decimal128('24.90'),
      sconto: Decimal128('2.00')
    },
    { prodottoId: 'P020', qta: 1, prezzo: Decimal128('29.00') }
  ]
}
[direct: mongos] labdb> const v7 = db.vendite.findOne({ clienteId: 7, "righe.prodottoId": "P002" })

[direct: mongos] labdb> db.vendite.updateOne({ _id: v7._id, clienteId: 7, "righe.prodottoId": "P002" }, { $inc: { "righe.$.qta": 1 } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.vendite.findOne({ _id: v7._id }, { _id: 0, righe: 1 })
{
  righe: [
    { prodottoId: 'P005', qta: 2, prezzo: Decimal128('45.90') },
    {
      prodottoId: 'P002',
      qta: 2,
      prezzo: Decimal128('24.90'),
      sconto: Decimal128('2.00')
    },
    { prodottoId: 'P020', qta: 1, prezzo: Decimal128('29.00') }
  ]
}
[direct: mongos] labdb> db.prove.replaceOne({ _id: 1 }, { testo: "documento sostituito" })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.prove.findOne({ _id: 1 })
{ _id: 1, testo: 'documento sostituito' }
[direct: mongos] labdb> db.prodotti.findOneAndUpdate({ _id: "P002" }, { $inc: { giacenza: -1 } }, { projection: { giacenza: 1 } })
{ _id: 'P002', giacenza: 140 }
[direct: mongos] labdb> db.prodotti.findOneAndUpdate({ _id: "P002" }, { $inc: { giacenza: -1 } }, { projection: { giacenza: 1 }, returnDocument: "after" })
{ _id: 'P002', giacenza: 138 }
[direct: mongos] labdb> db.vendite.updateOne({ stato: "annullata", canale: "telefono" }, { $set: { nota: "verificata" } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.vendite.insertOne({ _id: "prova-sk", clienteId: 99, stato: "prova", totale: NumberDecimal("1.00") })
{ acknowledged: true, insertedId: 'prova-sk' }
[direct: mongos] labdb> db.vendite.updateOne({ _id: "prova-sk", clienteId: 99 }, { $set: { clienteId: 98 } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> db.vendite.findOne({ _id: "prova-sk" })
{
  _id: 'prova-sk',
  clienteId: 98,
  stato: 'prova',
  totale: Decimal128('1.00')
}
[direct: mongos] labdb> db.vendite.updateMany({ clienteId: 98 }, { $set: { clienteId: 97 } })
MongoServerError: Multi-update operations are not allowed when updating the shard key field.
[direct: mongos] labdb> db.vendite.updateMany({ clienteId: 98 }, { $set: { clienteId: 97 } })
MongoServerError: Multi-update operations are not allowed when updating the shard key field.
[direct: mongos] labdb>
[direct: mongos] labdb>

```

## Parte 6 — Delete

```js
db.vendite.deleteOne({ _id: "prova-sk", clienteId: 97 })
db.vendite.deleteOne({ _id: "prova-sk" })
db.prove.deleteOne({ _id: 3 })
db.vendite.countDocuments({ stato: "annullata", data: { $lt: ISODate("2026-02-01") } })
db.vendite.deleteMany({ stato: "annullata", data: { $lt: ISODate("2026-02-01") } })
db.prodotti.findOneAndDelete({ _id: "P099" })
db.prove.deleteMany({})
show collections
db.prove.drop()
show collections
```

✅ Il primo `deleteOne` cancella **0** documenti (`prova-sk` ha `clienteId: 98`, non 97: l'`updateMany` di 5.6 era stato rifiutato); il secondo, senza shard key nel filtro, lo cancella (`deletedCount: 1`). `db.prove.deleteOne({ _id: 3 })`: `deletedCount: 1`. Poi: **83** vendite annullate a gennaio, `deletedCount: 83`; `findOneAndDelete` restituisce il documento eliminato. `deleteMany({})` su `prove`: `deletedCount: 4` (nel collaudo `5`, perché il `deleteOne` su `_id: 3` era stato saltato). Dopo `deleteMany({})` la collezione `prove` **esiste ancora** (vuota, con i suoi indici); dopo `drop()` (`true`) non c'è più.

📋 **Output della Parte 6.**

## Parte 7 — Indici ed explain

Una piccola funzione per leggere `explain` (va ridefinita a ogni apertura di `app_shell`):

```js
const piano = e => print("restituiti:", e.executionStats.nReturned, "| documenti esaminati:", e.executionStats.totalDocsExamined, "| chiavi esaminate:", e.executionStats.totalKeysExamined, "| stadi:", [...new Set(JSON.stringify(e.queryPlanner.winningPlan).match(/\b(COLLSCAN|IXSCAN|SORT|FETCH)\b/g))].join(" "))
```

### 7.1 Indice composto (regola ESR)

```js
db.vendite.getIndexes()
piano(db.vendite.find({ stato: "spedita", canale: "web" }).sort({ data: -1 }).explain("executionStats"))
db.vendite.createIndex({ stato: 1, canale: 1, data: -1 })
piano(db.vendite.find({ stato: "spedita", canale: "web" }).sort({ data: -1 }).explain("executionStats"))
piano(db.vendite.find({ canale: "web" }).sort({ data: -1 }).explain("executionStats"))
```

✅ Indici iniziali: `_id_` e `clienteId_hashed`. Prima: **418** restituiti, **4917** documenti esaminati, 0 chiavi, `SORT COLLSCAN`. `createIndex` risponde `stato_1_canale_1_data_-1`. Dopo l'indice: 418 restituiti, **418** esaminati, 418 chiavi, `FETCH IXSCAN`, niente `SORT`. L'ultima query (senza `stato`, il primo campo dell'indice) torna a `SORT COLLSCAN`: 2450 restituiti, 4917 esaminati.

### 7.2 Indice unique

```js
db.clienti.createIndex({ email: 1 }, { unique: true })
db.clienti.insertOne({ _id: 52, nome: "Copia", email: "anna.verdi51@esempio.it" })
db.vendite.createIndex({ data: 1 }, { unique: true })
db.vendite.createIndex({ clienteId: 1, data: 1 }, { unique: true })
```

✅ Su `clienti` l'indice si crea, e l'inserimento con la stessa email fallisce con `E11000`. Su `vendite` (distribuita) `{ data: 1 }` viene rifiutato: `MongoServerError[CannotCreateIndex]: ... cannot create index with 'unique' or 'prepareUnique' option over { data: 1 } with shard key pattern { clienteId: "hashed" }`, perché un indice unique deve contenere la shard key. `{ clienteId: 1, data: 1 }` invece **si crea** (`clienteId_1_data_1`), anche se la shard key è hashed: tutte le vendite di uno stesso cliente stanno sullo stesso shard, che può quindi garantire l'unicità.

> ⚠️ Questo indice resta su `vendite` fino alla pulizia: da qui in poi non possono esistere due vendite con lo stesso `clienteId` e la stessa `data` (o entrambe senza `data`).

### 7.3 Indice TTL

```js
db.sessioni.createIndex({ creata: 1 }, { expireAfterSeconds: 120 })
db.sessioni.insertMany([ { utente: "anna", creata: new Date() }, { utente: "marco", creata: new Date(Date.now() - 3600 * 1000) } ])
db.sessioni.countDocuments()
```

✅ `2`. Prosegui con il 7.4 e ricontrolla tra un paio di minuti (passo 7.5).

### 7.4 Indice parziale

```js
db.prodotti.createIndex({ nome: 1 }, { partialFilterExpression: { giacenza: { $gt: 0 } } })
piano(db.prodotti.find({ nome: "Mouse senza fili", giacenza: { $gt: 0 } }).explain("executionStats"))
piano(db.prodotti.find({ nome: "Mouse senza fili" }).explain("executionStats"))
db.prodotti.getIndexes().map(i => i.name)
```

✅ La prima usa l'indice (`FETCH IXSCAN`, 1 documento esaminato); la seconda no (`COLLSCAN`, 30 documenti esaminati); gli indici sono `[ '_id_', 'nome_1' ]`: l'indice contiene solo i prodotti disponibili, quindi vale solo per le query che lo garantiscono.

### 7.5 Il TTL al lavoro

```js
db.sessioni.find({}, { _id: 0, utente: 1 })
db.sessioni.drop()
exit
```

✅ Dopo uno o due minuti resta solo `anna`: il controllo delle scadenze gira ogni 60 secondi. Dopo altri 2 minuti sparirebbe anche lei.

📋 **Output della Parte 7.**

```bash
azureuserdgs@azmdb01:~$ source ~/mongo-lab/04-crud/funzioni-crud.sh
azureuserdgs@azmdb01:~$ app_shell
Current Mongosh Log ID: 6af9c4027635bba6fb425d2e
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/

[direct: mongos] labdb> db.vendite.deleteOne({ _id: "prova-sk", clienteId: 97 })
{ acknowledged: true, deletedCount: 0 }
[direct: mongos] labdb> db.vendite.deleteOne({ _id: "prova-sk" })
{ acknowledged: true, deletedCount: 1 }
[direct: mongos] labdb> db.vendite.countDocuments({ stato: "annullata", data: { $lt: ISODate("2026-02-01") } })
83
[direct: mongos] labdb> db.vendite.deleteMany({ stato: "annullata", data: { $lt: ISODate("2026-02-01") } })
{ acknowledged: true, deletedCount: 83 }
[direct: mongos] labdb> db.prodotti.findOneAndDelete({ _id: "P099" })
{
  _id: 'P099',
  categoria: 'Prove',
  creato: ISODate('2026-11-15T14:01:47.239Z'),
  giacenza: 0,
  nome: 'Prodotto di prova'
}
[direct: mongos] labdb> db.prove.deleteMany({})
{ acknowledged: true, deletedCount: 5 }
[direct: mongos] labdb> show collections
clienti
eventi
ordini
prodotti
prove
vendite
[direct: mongos] labdb> db.prove.drop()
true
[direct: mongos] labdb> show collections
clienti
eventi
ordini
prodotti
vendite
[direct: mongos] labdb> const piano = e => print("restituiti:", e.executionStats.nReturned, "| documenti esaminati:", e.executionStats.totalDocsExamined, "| chiavi esaminate:", e.executionStats.totalKeysExamined, "| stadi:", [...new Set(JSON.stringify(e.queryPlanner.winningPlan).match(/\b(COLLSCAN|IXSCAN|SORT|FETCH)\b/g))].join([direct: mongos] labdb> const piano = e => print("restituiti:", e.executionStats.nReturned, "| documenti esaminati:", e.executionStats.totalDocsExamined, "| chiavi esaminate:", e.executionStats.totalKeysExamined, "| stadi:", [...new Set(JSON.stringify(e.queryPlanner.winningPlan).match(/\b(COLLSCAN|IXSCAN|SORT|FETCH)\b/g))].join(" "))

[direct: mongos] labdb> db.vendite.getIndexes()
[
  { v: 2, key: { _id: 1 }, name: '_id_' },
  { v: 2, key: { clienteId: 'hashed' }, name: 'clienteId_hashed' }
]
[direct: mongos] labdb> piano(db.vendite.find({ stato: "spedita", canale: "web" }).sort({ data: -1 }).explain("executionStats"))
restituiti: 418 | documenti esaminati: 4917 | chiavi esaminate: 0 | stadi: SORT COLLSCAN

[direct: mongos] labdb> db.vendite.createIndex({ stato: 1, canale: 1, data: -1 })
stato_1_canale_1_data_-1
[direct: mongos] labdb> piano(db.vendite.find({ stato: "spedita", canale: "web" }).sort({ data: -1 }).explain("executionStats"))
restituiti: 418 | documenti esaminati: 418 | chiavi esaminate: 418 | stadi: FETCH IXSCAN

[direct: mongos] labdb> piano(db.vendite.find({ canale: "web" }).sort({ data: -1 }).explain("executionStats"))
restituiti: 2450 | documenti esaminati: 4917 | chiavi esaminate: 0 | stadi: SORT COLLSCAN

[direct: mongos] labdb> db.clienti.createIndex({ email: 1 }, { unique: true })
email_1
[direct: mongos] labdb> db.clienti.insertOne({ _id: 52, nome: "Copia", email: "anna.verdi51@esempio.it" })
MongoServerError: E11000 duplicate key error collection: labdb.clienti index: email_1 dup key: { email: "anna.verdi51@esempio.it" }
[direct: mongos] labdb> db.vendite.createIndex({ data: 1 }, { unique: true })
MongoServerError[CannotCreateIndex]: Index build failed: 99f38597-d502-4ab5-96d3-cbfc65ee71ba: Collection labdb.vendite ( 680c55d1-da4b-408f-b811-dbeaed14193c ) :: caused by :: cannot create index with 'unique' or 'prepareUnique' option over { data: 1 } with shard key pattern { clienteId: "hashed" } and collation {}
[direct: mongos] labdb> db.vendite.createIndex({ clienteId: 1, data: 1 }, { unique: true })
clienteId_1_data_1
[direct: mongos] labdb> db.sessioni.createIndex({ creata: 1 }, { expireAfterSeconds: 120 })
creata_1
[direct: mongos] labdb> db.sessioni.insertMany([ { utente: "anna", creata: new Date() }, { utente: "marco", creata: new Date(Date.now() - 3600 * 1000) } ])
{
  acknowledged: true,
  insertedIds: {
    '0': ObjectId('6af9c49e7635bba6fb425d2f'),
    '1': ObjectId('6af9c49e7635bba6fb425d30')
  }
}
[direct: mongos] labdb> db.sessioni.countDocuments()
2
[direct: mongos] labdb> db.prodotti.createIndex({ nome: 1 }, { partialFilterExpression: { giacenza: { $gt: 0 } } })
nome_1
[direct: mongos] labdb> piano(db.prodotti.find({ nome: "Mouse senza fili", giacenza: { $gt: 0 } }).explain("executionStats"))
restituiti: 1 | documenti esaminati: 1 | chiavi esaminate: 1 | stadi: FETCH IXSCAN

[direct: mongos] labdb> piano(db.prodotti.find({ nome: "Mouse senza fili" }).explain("executionStats"))
restituiti: 1 | documenti esaminati: 30 | chiavi esaminate: 0 | stadi: COLLSCAN

[direct: mongos] labdb> db.prodotti.getIndexes().map(i => i.name)
[ '_id_', 'nome_1' ]
[direct: mongos] labdb> db.sessioni.find({}, { _id: 0, utente: 1 })
[ { utente: 'anna' } ]
[direct: mongos] labdb> db.sessioni.drop()
true
[direct: mongos] labdb>
```

---

# Blocco D

## Parte 8 — Aggregazione

```bash
app_shell
```

### 8.1 Raggruppare

```js
db.vendite.aggregate([ { $group: { _id: "$stato", vendite: { $sum: 1 }, incasso: { $sum: "$totale" } } }, { $sort: { vendite: -1 } } ])
db.vendite.aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$data" } }, incasso: { $sum: "$totale" } } }, { $sort: { _id: 1 } } ])
```

✅ Stati: consegnata **2493** (1.195.049,30), spedita **881**, in lavorazione **800**, annullata **743** (dopo le 83 cancellate). Mesi da `2026-01` (102.826,40) a `2026-11` (34.394,20).

### 8.2 `$unwind` e `$lookup`

```js
db.vendite.aggregate([ { $unwind: "$righe" }, { $group: { _id: "$righe.prodottoId", pezzi: { $sum: "$righe.qta" } } }, { $sort: { pezzi: -1, _id: 1 } }, { $limit: 5 }, { $lookup: { from: "prodotti", localField: "_id", foreignField: "_id", as: "prodotto" } }, { $project: { _id: 0, prodotto: { $first: "$prodotto.nome" }, pezzi: 1 } } ])
db.vendite.aggregate([ { $group: { _id: "$clienteId", speso: { $sum: "$totale" } } }, { $sort: { speso: -1 } }, { $limit: 3 }, { $lookup: { from: "clienti", localField: "_id", foreignField: "_id", as: "c" } }, { $unwind: "$c" }, { $project: { _id: 0, cliente: { $concat: ["$c.nome", " ", "$c.cognome"] }, citta: "$c.indirizzo.citta", speso: 1 } } ])
```

✅ Prodotti: Atlante del cielo (739), Zaino da trekking (714), Bollitore elettrico (708), Aspirapolvere robot (692), Guida alle Dolomiti (692); gli ultimi due sono a pari merito, per questo l'ordinamento usa anche `_id`. Clienti: Andrea Rossi, Napoli (76.399,70); Luca Colombo, Milano (65.122,40); Francesca Marino, Milano (60.443,60).

### 8.3 `$facet` e `$bucket`

```js
db.vendite.aggregate([ { $facet: { perCanale: [ { $group: { _id: "$canale", n: { $sum: 1 } } }, { $sort: { n: -1 } } ], perFascia: [ { $bucket: { groupBy: "$totale", boundaries: [0, 50, 100, 250, 500, 1000, 5000], default: "altro", output: { n: { $sum: 1 } } } } ] } } ])
```

✅ Canali: web 2450, telefono 1241, negozio 1226. Fasce: 0→507, 50→565, 100→1124, 250→1141, 500→976, 1000→604.

### 8.4 `$merge`: salvare il risultato

```js
db.vendite.aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$data" } }, incasso: { $sum: "$totale" }, vendite: { $sum: 1 } } }, { $merge: { into: "riepilogo_mensile", whenMatched: "replace", whenNotMatched: "insert" } } ])
db.riepilogo_mensile.find().sort({ _id: 1 }).limit(3)
```

✅ L'aggregazione non restituisce nulla; `riepilogo_mensile` contiene 11 documenti, uno per mese.

### 8.5 Come il router divide una pipeline

```js
const e = db.vendite.explain().aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: "$canale", n: { $sum: 1 } } } ])
print("fusione:", e.mergeType); print("su ogni shard:", JSON.stringify(e.splitPipeline.shardsPart)); print("fusione finale:", JSON.stringify(e.splitPipeline.mergerPart))
const e2 = db.vendite.explain().aggregate([ { $match: { clienteId: 7 } }, { $group: { _id: "$canale", n: { $sum: 1 } } } ])
print("con la shard key:", e2.splitPipeline === null ? "nessuna divisione" : "divisa", "- shard:", Object.keys(e2.shards).length)
```

✅ Senza shard key: `fusione: mongos`; su ogni shard il `$match` e un `$group` parziale; nella fusione finale un `$mergeCursors` seguito da un `$group` che somma i parziali (`"n":{"$sum":"$$ROOT.n"}`). Con `clienteId: 7`: `con la shard key: nessuna divisione - shard: 1`.

📋 **Output della Parte 8.**

```bash
azureuserdgs@azmdb01:~$ source ~/mongo-lab/04-crud/funzioni-crud.sh
azureuserdgs@azmdb01:~$ app_shell
Current Mongosh Log ID: 6af9c5390b7fb7f6d42b86bb
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/

[direct: mongos] labdb> db.vendite.aggregate([ { $group: { _id: "$stato", vendite: { $sum: 1 }, incasso: { $sum: "$totale" } } }, { $sort: { vendite: -1 } } ])
[
  { _id: 'consegnata', vendite: 2493, incasso: Decimal128('1195049.30') },
  { _id: 'spedita', vendite: 881, incasso: Decimal128('433230.00') },
  {
    _id: 'in lavorazione',
    vendite: 800,
    incasso: Decimal128('392134.10')
  },
  { _id: 'annullata', vendite: 743, incasso: Decimal128('360623.50') }
]
[direct: mongos] labdb> db.vendite.aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$data" } }, incasso: { $sum: "$totale" } } }, { $sort: { _id: 1 } } ])
[
  { _id: '2026-01', incasso: Decimal128('102826.40') },
  { _id: '2026-02', incasso: Decimal128('105804.70') },
  { _id: '2026-03', incasso: Decimal128('134028.90') },
  { _id: '2026-04', incasso: Decimal128('104699.40') },
  { _id: '2026-05', incasso: Decimal128('133419.90') },
  { _id: '2026-06', incasso: Decimal128('105824.60') },
  { _id: '2026-07', incasso: Decimal128('103145.70') },
  { _id: '2026-08', incasso: Decimal128('122446.50') },
  { _id: '2026-09', incasso: Decimal128('126184.00') },
  { _id: '2026-10', incasso: Decimal128('122275.00') },
  { _id: '2026-11', incasso: Decimal128('34394.20') }
]
[direct: mongos] labdb> db.vendite.aggregate([ { $unwind: "$righe" }, { $group: { _id: "$righe.prodottoId", pezzi: { $sum: "$righe.qta" } } }, { $sort: { pezzi: -1 } }, { $limit: 5 }, { $lookup: { from: "prodotti", localField: "_id", foreignField: "_id", as: "prodotto" } }, { $project: { _id: 0, prodotto: { $first: "$prodotto.nome" }, pezzi: 1 } } ])
[
  { pezzi: 739, prodotto: 'Atlante del cielo' },
  { pezzi: 714, prodotto: 'Zaino da trekking' },
  { pezzi: 708, prodotto: 'Bollitore elettrico' },
  { pezzi: 692, prodotto: 'Aspirapolvere robot' },
  { pezzi: 692, prodotto: 'Guida alle Dolomiti' }
]
[direct: mongos] labdb> db.vendite.aggregate([ { $group: { _id: "$clienteId", speso: { $sum: "$totale" } } }, { $sort: { speso: -1 } }, { $limit: 3 }, { $lookup: { ffrom: "clienti", localField: "_id", foreignField: "_id", as: "c" } }, { $unwind: "$c" }, { $project: { _id: 0, cliente: { $concat: ["$c.nome", " ", "$c.cognome"] }, citta: "$c.indirizzo.citta", speso: 1 } } ])
[
  {
    speso: Decimal128('76399.70'),
    cliente: 'Andrea Rossi',
    citta: 'Napoli'
  },
  {
    speso: Decimal128('65122.40'),
    cliente: 'Luca Colombo',
    citta: 'Milano'
  },
  {
    speso: Decimal128('60443.60'),
    cliente: 'Francesca Marino',
    citta: 'Milano'
  }
]
[direct: mongos] labdb> db.vendite.aggregate([ { $facet: { perCanale: [ { $group: { _id: "$canale", n: { $sum: 1 } } }, { $sort: { n: -1 } } ], perFascia: [ { $bucke$bucket: { groupBy: "$totale", boundaries: [0, 50, 100, 250, 500, 1000, 5000], default: "altro", output: { n: { $sum: 1 } } } } ] } } ])
[
  {
    perCanale: [
      { _id: 'web', n: 2450 },
      { _id: 'telefono', n: 1241 },
      { _id: 'negozio', n: 1226 }
    ],
    perFascia: [
      { _id: 0, n: 507 },
      { _id: 50, n: 565 },
      { _id: 100, n: 1124 },
      { _id: 250, n: 1141 },
      { _id: 500, n: 976 },
      { _id: 1000, n: 604 }
    ]
  }
]
[direct: mongos] labdb> db.vendite.aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$data" } }, incasso: { $sum: "$totale" }, vendite: { $sum: 1 } } }, { $merge: { into: "riepilogo_mensile", whenMatched: "replace", whenNotMatched: "insert" } } ])

[direct: mongos] labdb> db.riepilogo_mensile.find().sort({ _id: 1 }).limit(3)
[
  { _id: '2026-01', incasso: Decimal128('102826.40'), vendite: 246 },
  { _id: '2026-02', incasso: Decimal128('105804.70'), vendite: 211 },
  { _id: '2026-03', incasso: Decimal128('134028.90'), vendite: 260 }
]
[direct: mongos] labdb> const e = db.vendite.explain().aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: "$canale", n: { $sum: 1 } } } ])

[direct: mongos] labdb> print("fusione:", e.mergeType); print("su ogni shard:", JSON.stringify(e.splitPipeline.shardsPart)); print("fusione finale:", JSON.stringify(e.splitPipeline.mergerPart))
fusione: mongos
su ogni shard: [{"$match":{"stato":{"$eq":"consegnata"}}},{"$group":{"_id":"$canale","n":{"$sum":{"$const":1}}}}]
fusione finale: [{"$mergeCursors":{"lsid":{"id":"35cc4c40-bd72-4f2d-af97-82528afcb59f","uid":"BRQXuKSknFIiWtLOGANYt+LixwuwH937Ar257mDm79I="},"compareWholeSortKey":false,"tailableMode":"normal","nss":"labdb.vendite","allowPartialResults":false,"recordRemoteOpWaitTime":false,"requestQueryStatsFromRemotes":false}},{"$group":{"_id":"$$ROOT._id","n":{"$sum":"$$ROOT.n"},"$doingMerge":true}}]

[direct: mongos] labdb> const e2 = db.vendite.explain().aggregate([ { $match: { clienteId: 7 } }, { $group: { _id: "$canale", n: { $sum: 1 } } } ])

[direct: mongos] labdb> print("con la shard key:", e2.splitPipeline === null ? "nessuna divisione" : "divisa", "- shard:", Object.keys(e2.shards).length)
con la shard key: nessuna divisione - shard: 1

[direct: mongos] labdb>

```

## Parte 9 — Transazioni

**Contatori delle transazioni del router, prima** (in un altro terminale, o uscendo dalla shell):

```bash
sh_eval 'const t = db.serverStatus().transactions; print("avviate:", t.totalStarted, "- confermate:", t.totalCommitted, "- annullate:", t.totalAborted); printjson(Object.fromEntries(Object.entries(t.commitTypes).map(([k, v]) => [k, v.successful])))'
```

Annota i valori. Poi **rientra nella shell** (i comandi che seguono sono JavaScript, non comandi della VM) e restaci fino alla fine del 9.4: la sessione `s` serve a tutti i passi.

```bash
app_shell
```

### 9.1 Una transazione riuscita

```js
const s = db.getMongo().startSession()
const sp = s.getDatabase("labdb").prodotti, sv = s.getDatabase("labdb").vendite
s.withTransaction(() => { const r = sp.updateOne({ _id: "P003", giacenza: { $gte: 2 } }, { $inc: { giacenza: -2 } }); if (r.modifiedCount !== 1) throw new Error("giacenza insufficiente per P003"); sv.insertOne({ clienteId: 12, data: new Date(), stato: "in lavorazione", canale: "web", righe: [ { prodottoId: "P003", qta: 2, prezzo: NumberDecimal("79.90") } ], totale: NumberDecimal("159.80") }) }, { readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } })
db.prodotti.findOne({ _id: "P003" }, { giacenza: 1 })
db.vendite.countDocuments({ clienteId: 12, stato: "in lavorazione", "righe.prodottoId": "P003", data: { $gte: ISODate("2026-10-01") } })
```

✅ Giacenza di P003 da 35 a **33**; la nuova vendita esiste (**1**).

### 9.2 Una transazione annullata

```js
db.vendite.countDocuments({ clienteId: 13 })
try { s.withTransaction(() => { sv.insertOne({ clienteId: 13, data: new Date(), stato: "in lavorazione", canale: "web", righe: [ { prodottoId: "P007", qta: 1, prezzo: NumberDecimal("59.90") } ], totale: NumberDecimal("59.90") }); const r = sp.updateOne({ _id: "P007", giacenza: { $gte: 1 } }, { $inc: { giacenza: -1 } }); if (r.modifiedCount !== 1) throw new Error("giacenza insufficiente per P007") }) } catch (e) { print("transazione annullata:", e.message) }
db.vendite.countDocuments({ clienteId: 13 })
```

✅ `transazione annullata: giacenza insufficiente per P007` (P007 è esaurito); il conteggio del cliente 13 è **uguale prima e dopo**: anche l'inserimento, eseguito per primo, è stato annullato.

### 9.3 Isolamento: le modifiche si vedono solo dopo il commit

```js
s.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } })
sp.updateOne({ _id: "P004" }, { $inc: { giacenza: -1 } })
print("dentro la transazione:", sp.findOne({ _id: "P004" }).giacenza, "- fuori:", db.prodotti.findOne({ _id: "P004" }).giacenza)
s.commitTransaction()
print("dopo il commit:", db.prodotti.findOne({ _id: "P004" }).giacenza)
s.startTransaction()
sp.updateOne({ _id: "P004" }, { $set: { giacenza: 0 } })
s.abortTransaction()
print("dopo l'abort:", db.prodotti.findOne({ _id: "P004" }).giacenza)
```

✅ `dentro: 19 - fuori: 20`, `dopo il commit: 19`, `dopo l'abort: 19`.

### 9.4 Una transazione su entrambi gli shard

```js
db.vendite.find({ clienteId: { $in: [1, 2, 3, 4, 5, 6] } }).explain().queryPlanner.winningPlan.shards.length
s.withTransaction(() => { sv.updateMany({ clienteId: { $in: [1, 2, 3, 4, 5, 6] } }, { $set: { verificata: true } }); sp.updateOne({ _id: "P001" }, { $set: { ultimaVerifica: new Date() } }) })
db.vendite.countDocuments({ verificata: true })
s.endSession()
exit
```

✅ `2` shard coinvolti; **603** vendite marcate.

**Contatori, dopo:**

```bash
sh_eval 'const t = db.serverStatus().transactions; print("avviate:", t.totalStarted, "- confermate:", t.totalCommitted, "- annullate:", t.totalAborted); printjson(Object.fromEntries(Object.entries(t.commitTypes).map(([k, v]) => [k, v.successful])))'
```

✅ Nel collaudo: avviate da 1298 a **1313**, confermate da 1298 a **1311**, annullate da 0 a **2** (la 9.2 e l'`abortTransaction` della 9.3); `twoPhaseCommit` da 0 a **1**: è la 9.4, il commit coordinato su più shard. Le altre sono `singleShard` (da 1297 a 1309). I valori di partenza dipendono dalla storia del router: conta la differenza.

📋 **Output della Parte 9** (contatori prima e dopo compresi).

```bash

[direct: mongos] labdb> exit
azureuserdgs@azmdb01:~$ sh_eval 'const t = db.serverStatus().transactions; print("avviate:", t.totalStarted, "- confermate:", t.totalCommitted, "- annullate:", t.totalAborted); printjson(Object.fromEntries(Object.entries(t.commitTypes).map(([k, v]) => [k, v.successful])))'
avviate: Long('1298') - confermate: Long('1298') - annullate: Long('0')
{
  noShards: Long('0'),
  singleShard: Long('1297'),
  singleWriteShard: Long('1'),
  readOnly: Long('0'),
  twoPhaseCommit: Long('0'),
  recoverWithToken: Long('0')
}
azureuserdgs@azmdb01:~$ app_shell
Current Mongosh Log ID: 6af9c6d9528711f265cd2750
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/

[direct: mongos] labdb> const s = db.getMongo().startSession()

[direct: mongos] labdb> const sp = s.getDatabase("labdb").prodotti, sv = s.getDatabase("labdb").vendite

[direct: mongos] labdb> s.withTransaction(() => { const r = sp.updateOne({ _id: "P003", giacenza: { $gte: 2 } }, { $inc: { giacenza: -2 } }); if (r.modifiedCount !== 1) throw new Error("giacenza insufficiente per P003"); sv.insertOne({ clienteId: 12, data: new Date(), stato: "in lavorazione", canale: "web", righe: [ {prodottoId: "P003", qta: 2, prezzo: NumberDecimal("79.90") } ], totale: NumberDecimal("159.80") }) }, { readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } })

[direct: mongos] labdb> db.prodotti.findOne({ _id: "P003" }, { giacenza: 1 })
{ _id: 'P003', giacenza: 33 }
[direct: mongos] labdb> db.vendite.countDocuments({ clienteId: 12, stato: "in lavorazione", "righe.prodottoId": "P003", data: { $gte: ISODate("2026-10-01") } })
1
[direct: mongos] labdb> db.vendite.countDocuments({ clienteId: 13 })
90
[direct: mongos] labdb> try { s.withTransaction(() => { sv.insertOne({ clienteId: 13, data: new Date(), stato: "in lavorazione", canale: "web", righe: [ {prodottoId: "P007", qta: 1, prezzo: NumberDecimal("59.90") } ], totale: NumberDecimal("59.90") }); const r = sp.updateOne({ _id: "P007", giacenza: { $gte: 1 } }, { $inc: { giacgiacenza: -1 } }); if (r.modifiedCount !== 1) throw new Error("giacenza insufficiente per P007") }) } catch (e) { print("transazione annullata:", e.message) }
transazione annullata: giacenza insufficiente per P007

[direct: mongos] labdb> db.vendite.countDocuments({ clienteId: 13 })
90
[direct: mongos] labdb> s.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } })

[direct: mongos] labdb> sp.updateOne({ _id: "P004" }, { $inc: { giacenza: -1 } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> print("dentro la transazione:", sp.findOne({ _id: "P004" }).giacenza, "- fuori:", db.prodotti.findOne({ _id: "P004" }).giacenza)
dentro la transazione: 19 - fuori: 20

[direct: mongos] labdb> s.commitTransaction()

[direct: mongos] labdb> print("dopo il commit:", db.prodotti.findOne({ _id: "P004" }).giacenza)
dopo il commit: 19

[direct: mongos] labdb> s.startTransaction()

[direct: mongos] labdb> sp.updateOne({ _id: "P004" }, { $set: { giacenza: 0 } })
{
  acknowledged: true,
  insertedId: null,
  matchedCount: 1,
  modifiedCount: 1,
  upsertedCount: 0
}
[direct: mongos] labdb> s.abortTransaction()

[direct: mongos] labdb> print("dopo l'abort:", db.prodotti.findOne({ _id: "P004" }).giacenza)
dopo l'abort: 19

[direct: mongos] labdb> db.vendite.find({ clienteId: { $in: [1, 2, 3, 4, 5, 6] } }).explain().queryPlanner.winningPlan.shards.length
2
[direct: mongos] labdb> s.withTransaction(() => { sv.updateMany({ clienteId: { $in: [1, 2, 3, 4, 5, 6] } }, { $set: { verificata: true } }); sp.updateOne({ _id: "P001" }, { $set: { ultimaVerifica: new Date() } }) })

[direct: mongos] labdb> db.vendite.countDocuments({ verificata: true })
603
[direct: mongos] labdb> s.endSession()

[direct: mongos] labdb> exit
azureuserdgs@azmdb01:~$ sh_eval 'const t = db.serverStatus().transactions; print("avviate:", t.totalStarted, "- confermate:", t.totalCommitted, "- annullate:", t.totalAborted); printjson(Object.fromEntries(Object.entries(t.commitTypes).map(([k, v]) => [k, v.successful])))'
avviate: Long('1313') - confermate: Long('1311') - annullate: Long('2')
{
  noShards: Long('0'),
  singleShard: Long('1309'),
  singleWriteShard: Long('1'),
  readOnly: Long('0'),
  twoPhaseCommit: Long('1'),
  recoverWithToken: Long('0')
}
azureuserdgs@azmdb01:~$
```

## Parte 10 — bulkWrite e write concern

```bash
app_shell
```

```js
db.prodotti.bulkWrite([ { insertOne: { document: { _id: "P100", nome: "Prodotto bulk", categoria: "Prove", prezzo: NumberDecimal("1.00"), giacenza: 10 } } }, { updateOne: { filter: { _id: "P002" }, update: { $inc: { giacenza: 10 } } } }, { updateMany: { filter: { categoria: "Ufficio" }, update: { $set: { reparto: "B" } } } }, { replaceOne: { filter: { _id: "P100" }, replacement: { nome: "Prodotto bulk sostituito", categoria: "Prove", prezzo: NumberDecimal("2.00"), giacenza: 5 } } }, { deleteOne: { filter: { _id: "P100" } } } ])
db.prodotti.bulkWrite([ { insertOne: { document: { _id: "P101" } } }, { insertOne: { document: { _id: "P101" } } }, { insertOne: { document: { _id: "P102" } } } ])
db.prodotti.bulkWrite([ { insertOne: { document: { _id: "P103" } } }, { insertOne: { document: { _id: "P103" } } }, { insertOne: { document: { _id: "P104" } } } ], { ordered: false })
db.prodotti.find({ _id: { $in: ["P101", "P102", "P103", "P104"] } }, { _id: 1 })
db.prodotti.deleteMany({ _id: { $in: ["P101", "P102", "P103", "P104"] } })
db.prodotti.insertOne({ _id: "P105" }, { writeConcern: { w: "majority", wtimeout: 5000 } })
db.prodotti.insertOne({ _id: "P106" }, { writeConcern: { w: 4, wtimeout: 3000 } })
db.prodotti.deleteMany({ _id: { $in: ["P105", "P106"] } })
exit
```

✅ Primo `bulkWrite`: `insertedCount: 1`, `matchedCount: 6`, `modifiedCount: 6` (P002, i 4 prodotti Ufficio, la sostituzione), `deletedCount: 1`. Ordinato: errore, inserito solo P101. Non ordinato: errore, inseriti P103 e P104. `w: "majority"`: ok. `w: 4` su uno shard di 3 nodi: `MongoWriteConcernError[UnsatisfiableWriteConcern]: Not enough data-bearing nodes` (codice `100`). Attenzione: il risultato contiene `n: 1` e l'ultimo `deleteMany` cancella **2** documenti: P106 **è stato scritto** comunque. L'errore dice che la conferma richiesta non è ottenibile, non che la scrittura è stata annullata.

📋 **Output della Parte 10.**

```bash
azureuserdgs@azmdb01:~$ app_shell
Current Mongosh Log ID: 6af9c8687cefece7b5662ddf
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/

[direct: mongos] labdb> db.prodotti.bulkWrite([ { insertOne: { document: { _id: "P100", nome: "Prodotto bulk", categoria: "Prove", prezzo: NumberDecimal("1.00"), giagiacenza: 10 } } }, { updateOne: { filter: { _id: "P002" }, update: { $inc: { giacenza: 10 } } } }, { updateMany: { filter: { categoria: "Ufficio" }, update: { $set: { reparto: "B" } } } }, { replaceOne: { filter: { _id: "P100" }, replacement: { nome: "Prodotto bulk sostituito", categoria: "Prove", prezzo: NumberDecimal("2.00"), giacenza: 5 } } }, { deleteOne: { filter: { _id: "P100" } } } ])
{
  acknowledged: true,
  insertedCount: 1,
  insertedIds: { '0': 'P100' },
  matchedCount: 6,
  modifiedCount: 6,
  deletedCount: 1,
  upsertedCount: 0,
  upsertedIds: {}
}
[direct: mongos] labdb> db.prodotti.bulkWrite([ { insertOne: { document: { _id: "P101" } } }, { insertOne: { document: { _id: "P101" } } }, { insertOne: { document: { _id: "P102" } } } ])
Uncaught:
MongoBulkWriteError: E11000 duplicate key error collection: labdb.prodotti index: _id_ dup key: { _id: "P101" }
Result: BulkWriteResult {
  insertedCount: 1,
  matchedCount: 0,
  modifiedCount: 0,
  deletedCount: 0,
  upsertedCount: 0,
  upsertedIds: {},
  insertedIds: { '0': 'P101' }
}
Write Errors: [
  WriteError {
    err: {
      index: 1,
      code: 11000,
      errmsg: 'E11000 duplicate key error collection: labdb.prodotti index: _id_ dup key: { _id: "P101" }',
      errInfo: undefined,
      op: { _id: 'P101' }
    }
  }
]
[direct: mongos] labdb> db.prodotti.bulkWrite([ { insertOne: { document: { _id: "P103" } } }, { insertOne: { document: { _id: "P103" } } }, { insertOne: { document: { _id: "P104" } } } ], { ordered: false })
Uncaught:
MongoBulkWriteError: E11000 duplicate key error collection: labdb.prodotti index: _id_ dup key: { _id: "P103" }
Result: BulkWriteResult {
  insertedCount: 2,
  matchedCount: 0,
  modifiedCount: 0,
  deletedCount: 0,
  upsertedCount: 0,
  upsertedIds: {},
  insertedIds: { '0': 'P103', '2': 'P104' }
}
Write Errors: [
  WriteError {
    err: {
      index: 1,
      code: 11000,
      errmsg: 'E11000 duplicate key error collection: labdb.prodotti index: _id_ dup key: { _id: "P103" }',
      errInfo: undefined,
      op: { _id: 'P103' }
    }
  }
]
[direct: mongos] labdb> db.prodotti.find({ _id: { $in: ["P101", "P102", "P103", "P104"] } }, { _id: 1 })
[ { _id: 'P101' }, { _id: 'P103' }, { _id: 'P104' } ]
[direct: mongos] labdb> db.prodotti.deleteMany({ _id: { $in: ["P101", "P102", "P103", "P104"] } })
{ acknowledged: true, deletedCount: 3 }
[direct: mongos] labdb> db.prodotti.insertOne({ _id: "P105" }, { writeConcern: { w: "majority", wtimeout: 5000 } })
{ acknowledged: true, insertedId: 'P105' }
[direct: mongos] labdb> db.prodotti.insertOne({ _id: "P106" }, { writeConcern: { w: 4, wtimeout: 3000 } })
Uncaught:
MongoWriteConcernError[UnsatisfiableWriteConcern]: UnsatisfiableWriteConcern: Not enough data-bearing nodes; Error details: { writeConcern: { w: 4, wtimeout: 3000, provenance: "clientSupplied" } } at sh2
Additional information: {}
Result: {
  n: 1,
  writeConcernError: {
    code: 100,
    codeName: 'UnsatisfiableWriteConcern',
    errmsg: 'UnsatisfiableWriteConcern: Not enough data-bearing nodes; Error details: { writeConcern: { w: 4, wtimeout: 3000, provenance: "clientSupplied" } } at sh2',
    errInfo: {}
  },
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1794754712, i: 1 }),
    signature: {
      hash: Binary.createFromBase64('Ep19SVwiOkkRc48gMJ04TeXyW4Q=', 0),
      keyId: Long('7691223719082983439')
    }
  },
  operationTime: Timestamp({ t: 1794754712, i: 1 })
}
[direct: mongos] labdb> db.prodotti.deleteMany({ _id: { $in: ["P105", "P106"] } })
{ acknowledged: true, deletedCount: 2 }
[direct: mongos] labdb>
```

---

# Blocco E

## Parte 11 — Validazione dello schema

```bash
app_shell
```

```js
db.createCollection("recensioni", { validator: { $jsonSchema: { bsonType: "object", required: ["prodottoId", "clienteId", "voto"], properties: { prodottoId: { bsonType: "string", pattern: "^P[0-9]{3}$" }, clienteId: { bsonType: "int" }, voto: { bsonType: "int", minimum: 1, maximum: 5 }, testo: { bsonType: "string", maxLength: 500 } } } }, validationLevel: "strict", validationAction: "error" })
db.recensioni.insertOne({ prodottoId: "P017", clienteId: 3, voto: 5, testo: "Chiaro e pratico" })
db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 })
db.recensioni.insertOne({ prodottoId: "P017", voto: 4 })
db.recensioni.insertOne({ prodottoId: "X1", clienteId: 5, voto: 4 })
db.runCommand({ collMod: "recensioni", validationAction: "warn" })
exit
```

✅ La collezione si crea; la prima recensione entra; le altre tre vengono rifiutate con `Document failed validation` e un dettaglio (`Additional information`) che indica il campo e la regola violata. `collMod` come appuser: `MongoServerError[Unauthorized]: not authorized on labdb to execute command { collMod: "recensioni", ... }` (confermato: `readWrite` non comprende la modifica delle opzioni di una collezione).

**Come amministratore**, poi di nuovo come appuser:

```bash
sh_eval 'printjson(db.getSiblingDB("labdb").runCommand({ collMod: "recensioni", validationAction: "warn" }))'
app_eval 'db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 }); print("documenti non validi:", db.recensioni.countDocuments({ $nor: [ db.getCollectionInfos({ name: "recensioni" })[0].options.validator ] }))'
sh_eval 'printjson(db.getSiblingDB("labdb").runCommand({ collMod: "recensioni", validationAction: "error" }))'
```

✅ `ok: 1`; con `warn` il documento non valido entra (`documenti non validi: 1`): i documenti che non rispettano lo schema si trovano con `$nor` sul validatore. Poi si torna a `error`.

📋 **Output della Parte 11.**

```bash
azureuserdgs@azmdb01:~$ source ~/mongo-lab/04-crud/funzioni-crud.sh
azureuserdgs@azmdb01:~$ app_shell
Current Mongosh Log ID: 6af9cb3986d1800f098ef806
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/

[direct: mongos] labdb> db.createCollection("recensioni", { validator: { $jsonSchema: { bsonType: "object", required: ["prodottoId", "clienteId", "voto"], properties: { prodottoId: { bsonType: "string", pattern: "^P[0-9]{3}$" }, clienteId: { bsonType: "int" }, voto: { bsonType: "int", minimum: 1, maximum: 5 }, testo: { bsonType: "string", maxLength: 500 } } } }, validationLevel: "strict", validationAction: "error" })
{ ok: 1 }
[direct: mongos] labdb> db.recensioni.insertOne({ prodottoId: "P017", clienteId: 3, voto: 5, testo: "Chiaro e pratico" })
{
  acknowledged: true,
  insertedId: ObjectId('6af9cb6486d1800f098ef807')
}
[direct: mongos] labdb> db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 })
Uncaught:
MongoServerError: Document failed validation
Additional information: {
  failingDocumentId: ObjectId('6af9cb6886d1800f098ef808'),
  details: {
    operatorName: '$jsonSchema',
    schemaRulesNotSatisfied: [
      {
        operatorName: 'properties',
        propertiesNotSatisfied: [
          {
            propertyName: 'voto',
            details: [
              {
                operatorName: 'maximum',
                specifiedAs: { maximum: 5 },
                reason: 'comparison failed',
                consideredValue: 6
              }
            ]
          }
        ]
      }
    ]
  }
}
[direct: mongos] labdb> db.recensioni.insertOne({ prodottoId: "P017", voto: 4 })
Uncaught:
MongoServerError: Document failed validation
Additional information: {
  failingDocumentId: ObjectId('6af9cb6c86d1800f098ef809'),
  details: {
    operatorName: '$jsonSchema',
    schemaRulesNotSatisfied: [
      {
        operatorName: 'required',
        specifiedAs: { required: [ 'prodottoId', 'clienteId', 'voto' ] },
        missingProperties: [ 'clienteId' ]
      }
    ]
  }
}
[direct: mongos] labdb> db.recensioni.insertOne({ prodottoId: "X1", clienteId: 5, voto: 4 })
Uncaught:
MongoServerError: Document failed validation
Additional information: {
  failingDocumentId: ObjectId('6af9cb6f86d1800f098ef80a'),
  details: {
    operatorName: '$jsonSchema',
    schemaRulesNotSatisfied: [
      {
        operatorName: 'properties',
        propertiesNotSatisfied: [
          {
            propertyName: 'prodottoId',
            details: [
              {
                operatorName: 'pattern',
                specifiedAs: { pattern: '^P[0-9]{3}$' },
                reason: 'regular expression did not match',
                consideredValue: 'X1'
              }
            ]
          }
        ]
      }
    ]
  }
}
[direct: mongos] labdb> db.runCommand({ collMod: "recensioni", validationAction: "warn" })
MongoServerError[Unauthorized]: not authorized on labdb to execute command { collMod: "recensioni", validationAction: "warn", lsid: { id: UUID("74ba76e7-39e8-4543-9083-4da7c734c953") }, $clusterTime: { clusterTime: Timestamp(1794755439, 1), signature: { hash: BinData(0, 1414F4710A03078FF9A72CBD119D1C686B076EB3), keyId: 7691223719082983439 } }, $db: "labdb" }
[direct: mongos] labdb> exit
azureuserdgs@azmdb01:~$ sh_eval 'printjson(db.getSiblingDB("labdb").runCommand({ collMod: "recensioni", validationAction: "warn" }))'
{
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1794755452, i: 7 }),
    signature: {
      hash: Binary.createFromBase64('gVvMtBfe8Q3YyVnZGgcINRxaz1Y=', 0),
      keyId: Long('7691223719082983439')
    }
  },
  operationTime: Timestamp({ t: 1794755452, i: 7 })
}
azureuserdgs@azmdb01:~$ app_eval 'db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 }); print("documenti non validi:", db.recensioni.countDocuments({ $nor: [ db.getCollectionInfos({ name: "recensioni" })[0].options.validator ] }))'
documenti non validi: 2
azureuserdgs@azmdb01:~$ sh_eval 'printjson(db.getSiblingDB("labdb").runCommand({ collMod: "recensioni", validationAction: "error" }))'
{
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1794755463, i: 7 }),
    signature: {
      hash: Binary.createFromBase64('sF/ag4G8aGhcFrwGE9bjdpTk69M=', 0),
      keyId: Long('7691223719082983439')
    }
  },
  operationTime: Timestamp({ t: 1794755463, i: 7 })
}
```

> ✔️ **Chiarito (15/11/2026):** il `2` del primo collaudo dipendeva da una doppia esecuzione della Parte 11. Rieseguita una sola volta su `recensioni` ricreata da zero, la parte ha dato `documenti non validi: 1`, e la collezione conteneva esattamente due documenti: la recensione valida (`clienteId: 3, voto: 5`) e quella entrata con `warn` (`clienteId: 4, voto: 6`).
>
> ```bash
> azureuserdgs@azmdb01:~$ app_eval 'db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 }); print("documenti non validi:", db.recensioni.countDocuments({ $nor: [ db.getCollectionInfos({ name: "recensioni" })[0].options.validator ] }))'
> documenti non validi: 1
> ```

## Parte 12 — Ricerca testuale

```bash
app_shell
```

```js
db.prodotti.createIndex({ nome: "text", descrizione: "text" }, { default_language: "italian", weights: { nome: 3 }, name: "testo_prodotti" })
db.prodotti.find({ $text: { $search: "montagna" } }, { nome: 1, punteggio: { $meta: "textScore" } }).sort({ punteggio: { $meta: "textScore" } })
db.prodotti.find({ $text: { $search: "cucinare" } }, { nome: 1 })
db.prodotti.find({ $text: { $search: "\"senza fili\"" } }, { nome: 1 })
db.prodotti.find({ $text: { $search: "ufficio -sedia" } }, { nome: 1 })
db.prodotti.find({ $text: { $search: "per" } }, { nome: 1 })
db.prodotti.createIndex({ tags: "text" })
exit
```

✅ `createIndex` risponde `testo_prodotti`. `montagna`: Guida alle Dolomiti (P019) e Zaino da trekking (P024), entrambi con punteggio `0.6` (Borraccia termica no: «montagna» è solo nei tag, non indicizzati). `cucinare` trova «Cucina regionale» (P018) e «Set di pentole» (P013): radice comune `cucin`. La frase esatta trova solo il Mouse senza fili (P002). `ufficio -sedia` restituisce solo la Stampante laser (P030): la sedia è esclusa. `per` non trova nulla: è una parola vuota (*stop word*) dell'italiano. Il secondo indice testuale viene rifiutato con `MongoServerError[IndexOptionsConflict]: An equivalent index already exists with a different name and options` (seguito dal dettaglio dei due indici): ne è ammesso **uno solo** per collezione.

📋 **Output della Parte 12.**

```bash
azureuserdgs@azmdb01:~$ app_shell
Current Mongosh Log ID: 6af9cbf62b71964c6a036da2
Connecting to:          mongodb://<credentials>@127.0.0.1:27200/labdb?directConnection=true&serverSelectionTimeoutMS=2000&tls=true&tlsCAFile=%2Fetc%2Fmongo%2Ftls%2Fca.pem&authSource=labdb&appName=mongosh+2.11.1
Using MongoDB:          8.0.32
Using Mongosh:          2.11.1

For mongosh info see: https://www.mongodb.com/docs/mongodb-shell/

[direct: mongos] labdb> db.prodotti.createIndex({ nome: "text", descrizione: "text" }, { default_language: "italian", weights: { nome: 3 }, name: "testo_prodotti" })
testo_prodotti
[direct: mongos] labdb> db.prodotti.find({ $text: { $search: "montagna" } }, { nome: 1, punteggio: { $meta: "textScore" } }).sort({ punteggio: { $meta: "textScore" } })
[
  { _id: 'P019', nome: 'Guida alle Dolomiti', punteggio: 0.6 },
  { _id: 'P024', nome: 'Zaino da trekking', punteggio: 0.6 }
]
[direct: mongos] labdb> db.prodotti.find({ $text: { $search: "cucinare" } }, { nome: 1 })
[
  { _id: 'P018', nome: 'Cucina regionale' },
  { _id: 'P013', nome: 'Set di pentole' }
]
[direct: mongos] labdb> db.prodotti.find({ $text: { $search: "\"senza fili\"" } }, { nome: 1 })
[ { _id: 'P002', nome: 'Mouse senza fili' } ]
[direct: mongos] labdb> db.prodotti.find({ $text: { $search: "ufficio -sedia" } }, { nome: 1 })
[ { _id: 'P030', nome: 'Stampante laser' } ]
[direct: mongos] labdb> db.prodotti.find({ $text: { $search: "per" } }, { nome: 1 })

[direct: mongos] labdb> db.prodotti.createIndex({ tags: "text" })
MongoServerError[IndexOptionsConflict]: An equivalent index already exists with a different name and options. Requested index: { v: 2, key: { _fts: "text", _ftsx: 1 }, name: "tags_text", weights: { tags: 1 }, default_language: "english", language_override: "language", textIndexVersion: 3 }, existing index: { v: 2, key: { _fts: "text", _ftsx: 1 }, name: "testo_prodotti", default_language: "italian", weights: { descrizione: 1, nome: 3 }, language_override: "language", textIndexVersion: 3 }
[direct: mongos] labdb> exit
```

## Parte 13 — Change stream

Servono **due terminali SSH** sulla VM.

**Terminale 2**, quello che osserva:

```bash
source ~/mongo-lab/04-crud/funzioni-crud.sh
app_shell
```

```js
let ultimo = null; const cs = db.vendite.watch([], { fullDocument: "updateLookup" })
while (true) { const ev = cs.tryNext(); if (ev) { ultimo = ev._id; print(ev.operationType, JSON.stringify(ev.documentKey), ev.updateDescription ? JSON.stringify(ev.updateDescription.updatedFields) : "") } else { sleep(200) } }
```

**Terminale 1**, quello che scrive:

```bash
source ~/mongo-lab/04-crud/funzioni-crud.sh
app_eval 'db.vendite.insertMany([ { clienteId: 1, stato: "prova-cs", totale: NumberDecimal("10.00") }, { clienteId: 2, stato: "prova-cs", totale: NumberDecimal("20.00") } ]); db.vendite.updateOne({ clienteId: 1, stato: "prova-cs" }, { $set: { totale: NumberDecimal("12.00") } }); db.vendite.deleteMany({ stato: "prova-cs" }); print("fatto")'
```

✅ Nel terminale 2: due `insert`, un `update` (con `{"totale":...}`), due `delete`. In `documentKey` compaiono **`clienteId` e `_id`**: nelle collezioni distribuite l'evento porta con sé la shard key. Gli eventi arrivano da entrambi gli shard, uniti dal router.

**Ripresa dopo un'interruzione.** Nel terminale 2 premi `Ctrl+C` **una sola volta** (la shell resta aperta, con il prompt `labdb>`).

> ⚠️ La variabile `ultimo` esiste solo in questa shell. Se la shell si chiude o la connessione SSH cade, il *resume token* è perso: riparti dall'inizio della Parte 13.

**Solo dopo aver fermato il ciclo**, nel terminale 1 (se il ciclo è ancora attivo, gli eventi vengono visti subito e non resta nulla da recuperare):

```bash
app_eval 'db.vendite.insertOne({ clienteId: 3, stato: "prova-cs2" }); db.vendite.deleteMany({ stato: "prova-cs2" }); print("fatto mentre nessuno guardava")'
```

Nel terminale 2:

```js
const cs2 = db.vendite.watch([], { resumeAfter: ultimo }); for (let i = 0; i < 30; i++) { const ev = cs2.tryNext(); if (ev) print("recuperato:", ev.operationType, JSON.stringify(ev.documentKey)); else sleep(200) }
exit
```

✅ `recuperato: insert` e `recuperato: delete`: con il *resume token* l'osservatore riprende dal punto in cui si era fermato, senza perdere eventi (finché restano nell'oplog).

📋 **Output di entrambi i terminali.**

Terminale 2 (collaudo su `vendite` ricreata vuota e distribuita):

```bash
[direct: mongos] labdb> let ultimo = null; const cs = db.vendite.watch([], { fullDocument: "updateLookup" })

[direct: mongos] labdb> while (true) { const ev = cs.tryNext(); if (ev) { ultimo = ev._id; print(ev.operationType, JSON.stringify(ev.documentKey), ev.updateDescription ? JSON.stringify(ev.updateDescription.updatedFields) : "") } else { sleep(200) } }
insert {"clienteId":1,"_id":"6af9ff04eda4b81dd717402b"}
insert {"clienteId":2,"_id":"6af9ff04eda4b81dd717402c"}
update {"clienteId":1,"_id":"6af9ff04eda4b81dd717402b"} {"totale":{"$numberDecimal":"12.00"}}
delete {"clienteId":2,"_id":"6af9ff04eda4b81dd717402c"}
delete {"clienteId":1,"_id":"6af9ff04eda4b81dd717402b"}
^CStopping execution...
[direct: mongos] labdb> const cs2 = db.vendite.watch([], { resumeAfter: ultimo }); for (let i = 0; i < 30; i++) { const ev = cs2.tryNext(); if (ev) print("recuperato:", ev.operationType, JSON.stringify(ev.documentKey)); else sleep(200) }
recuperato: insert {"clienteId":3,"_id":"6af9ff402ba106dc7207cde5"}
recuperato: delete {"clienteId":3,"_id":"6af9ff402ba106dc7207cde5"}

[direct: mongos] labdb>
```

Terminale 1:

```bash
azureuserdgs@azmdb01:~$ app_eval 'db.vendite.insertMany([ { clienteId: 1, stato: "prova-cs", totale: NumberDecimal("10.00") }, { clienteId: 2, stato: "prova-cs", totale: NumberDecimal("20.00") } ]); db.vendite.updateOne({ clienteId: 1, stato: "prova-cs" }, { $set: { totale: NumberDecimal("12.00") } }); db.vendite.deleteMany({ stato: "prova-cs" }); print("fatto")'

fatto
azureuserdgs@azmdb01:~$ app_eval 'db.vendite.insertOne({ clienteId: 3, stato: "prova-cs2" }); db.vendite.deleteMany({ stato: "prova-cs2" }); print("fatto mentre nessuno guardava")'
fatto mentre nessuno guardava
```

> ✔️ **Collaudato (15/11/2026):** la ripresa con `resumeAfter` recupera l'`insert` e il `delete` avvenuti dopo il `Ctrl+C`, con `clienteId` e `_id` nel `documentKey`. Confermato anche `Ctrl+C`: una pressione stampa `Stopping execution...` e lascia la shell aperta; una seconda chiede conferma per uscire.

---

# Blocco F

## Parte 14 — Import ed export

📍 VM

```bash
cd ~/mongo-lab/04-crud
source ~/mongo-lab/04-crud/funzioni-crud.sh

app_export --collection=prodotti --query='{"categoria":"Libri"}' > libri.json
wc -l libri.json; head -1 libri.json

app_export --collection=clienti --type=csv --fields=_id,nome,cognome,indirizzo.citta,punti --sort='{"_id":1}' > clienti.csv
head -4 clienti.csv

app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes < prodotti.csv
app_eval 'db.prodotti_import.aggregate([ { $project: { nome: 1, prezzo: 1, tipoPrezzo: { $type: "$prezzo" }, tipoGiacenza: { $type: "$giacenza" } } } ]).forEach(p => print(p._id, p.nome, p.prezzo, p.tipoPrezzo, p.tipoGiacenza))'

app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes < prodotti.csv
app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes --mode=upsert < prodotti.csv

app_import --collection=libri_copia < libri.json
app_eval 'print("libri_copia:", db.libri_copia.countDocuments(), "- tipo del prezzo:", db.libri_copia.aggregate([ { $limit: 1 }, { $project: { t: { $type: "$prezzo" } } } ]).next().t)'
```

✅ `exported 6 records`; nel JSON il prezzo compare come `{"$numberDecimal":"12.60"}` (*Extended JSON*: conserva il tipo). Il CSV ha l'intestazione `_id,nome,cognome,indirizzo.citta,punti`. Primo import: `5 document(s) imported successfully`, con tipi `decimal` e `int`. Secondo: cinque righe `continuing through error: E11000 duplicate key error ...`, poi `0 document(s) imported successfully. 5 document(s) failed to import` (`_id` duplicati). Con `--mode=upsert`: nessun errore, ma `0 document(s) imported successfully. 0 document(s) failed to import`: i documenti esistono già e sono identici, quindi non c'è nulla da modificare. `libri_copia: 6`, prezzo `decimal`. Il CSV dei clienti contiene 51 record (i 50 iniziali più Anna).

📋 **Output della Parte 14.**

```bash
azureuserdgs@azmdb01:~$ cd ~/mongo-lab/04-crud
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ source ~/mongo-lab/04-crud/funzioni-crud.sh
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_export --collection=prodotti --query='{"categoria":"Libri"}' > libri.json
2026-11-15T15:18:58.429+0000    connected to: mongodb://[**REDACTED**]@localhost:27200/labdb?authSource=labdb
2026-11-15T15:18:58.433+0000    exported 6 records
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ wc -l libri.json; head -1 libri.json
6 libri.json
{"_id":"P015","nome":"Il nome della rosa","categoria":"Libri","prezzo":{"$numberDecimal":"12.60"},"giacenza":90,"tags":["romanzo","giallo"],"descrizione":"Romanzo giallo ambientato in un'abbazia medievale"}
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_export --collection=clienti --type=csv --fields=_id,nome,cognome,indirizzo.citta,punti --sort='{"_id":1}' > clienti.csv
2026-11-15T15:19:09.440+0000    connected to: mongodb://[**REDACTED**]@localhost:27200/labdb?authSource=labdb
2026-11-15T15:19:09.444+0000    exported 51 records
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ head -4 clienti.csv
_id,nome,cognome,indirizzo.citta,punti
1,Luca,Esposito,Bologna,203
2,Giulia,Esposito,Torino,67
3,Elena,Esposito,Milano,255
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes < prodotti.csv
2026-11-15T15:19:37.581+0000    connected to: mongodb://[**REDACTED**]@localhost:27200/labdb?authSource=labdb
2026-11-15T15:19:37.663+0000    5 document(s) imported successfully. 0 document(s) failed to import.
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_eval 'db.prodotti_import.aggregate([ { $project: { nome: 1, prezzo: 1, tipoPrezzo: { $type: "$prezzo" }, tipoGiacenza: { $type: "$giacenza" } } } ]).forEach(p => print(p._id, p.nome, p.prezzo, p.tipoPrezzo, p.tipoGiacenza))'
P031 Chiavetta USB 64 GB Decimal128('12.90') decimal int
P032 Tostapane Decimal128('34.50') decimal int
P033 Il Gattopardo Decimal128('13.00') decimal int
P034 Pallone da calcio Decimal128('24.99') decimal int
P035 Raccoglitore ad anelli Decimal128('4.20') decimal int
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes < prodotti.csv
2026-11-15T15:19:50.776+0000    connected to: mongodb://[**REDACTED**]@localhost:27200/labdb?authSource=labdb
2026-11-15T15:19:50.781+0000    continuing through error: E11000 duplicate key error collection: labdb.prodotti_import index: _id_ dup key: { _id: "P031" }
2026-11-15T15:19:50.781+0000    continuing through error: E11000 duplicate key error collection: labdb.prodotti_import index: _id_ dup key: { _id: "P032" }
2026-11-15T15:19:50.781+0000    continuing through error: E11000 duplicate key error collection: labdb.prodotti_import index: _id_ dup key: { _id: "P033" }
2026-11-15T15:19:50.781+0000    continuing through error: E11000 duplicate key error collection: labdb.prodotti_import index: _id_ dup key: { _id: "P034" }
2026-11-15T15:19:50.781+0000    continuing through error: E11000 duplicate key error collection: labdb.prodotti_import index: _id_ dup key: { _id: "P035" }
2026-11-15T15:19:50.781+0000    0 document(s) imported successfully. 5 document(s) failed to import.
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes --mode=upsert < prodotti.csv
2026-11-15T15:19:55.543+0000    connected to: mongodb://[**REDACTED**]@localhost:27200/labdb?authSource=labdb
2026-11-15T15:19:55.546+0000    0 document(s) imported successfully. 0 document(s) failed to import.
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_import --collection=libri_copia < libri.json
2026-11-15T15:20:00.265+0000    connected to: mongodb://[**REDACTED**]@localhost:27200/labdb?authSource=labdb
2026-11-15T15:20:00.340+0000    6 document(s) imported successfully. 0 document(s) failed to import.
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_eval 'print("libri_copia:", db.libri_copia.countDocuments(), "- tipo del prezzo:", db.libri_copia.aggregate([ { $limit: 1 }, { $project: { t: { $type: "$prezzo" } } } ]).next().t)'
libri_copia: 6 - tipo del prezzo: decimal
```

## Parte 15 — Pulizia

```bash
app_eval '["clienti", "prodotti", "vendite", "recensioni", "riepilogo_mensile", "prodotti_import", "libri_copia"].forEach(n => print(n, db.getCollection(n).drop())); print("restano:", db.getCollectionNames().sort().join(", "))'
sh_eval 'print("vendite ancora distribuita?", db.getSiblingDB("config").collections.findOne({ _id: "labdb.vendite" }) !== null)'
rm ~/mongo-lab/04-crud/libri.json ~/mongo-lab/04-crud/clienti.csv
```

✅ Sette volte `true`; `restano: eventi, ordini`; `vendite ancora distribuita? false`: il `drop` eseguito da appuser elimina anche i metadati di distribuzione (confermato).

📋 **Output della Parte 15.**

```bash
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ app_eval '["clienti", "prodotti", "vendite", "recensioni", "riepilogo_mensile", "prodotti_import", "libri_copia"].forEach(n => print(n, db.getCollection(n).drop())); print("restano:", db.getCollectionNames().sort().join(", "))'
clienti true
prodotti true
vendite true
recensioni true
riepilogo_mensile true
prodotti_import true
libri_copia true
restano: eventi, ordini
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ sh_eval 'print("vendite ancora distribuita?", db.getSiblingDB("config").collections.findOne({ _id: "labdb.vendite" }) !== null)'
vendite ancora distribuita? false
azureuserdgs@azmdb01:~/mongo-lab/04-crud$ rm ~/mongo-lab/04-crud/libri.json ~/mongo-lab/04-crud/clienti.csv
```

> Per ripetere il laboratorio: Parte 2 (distribuire `vendite`, poi caricare `dati-crud.js`).

---

## Cosa mandare alla fine

Gli output 📋 di ogni blocco, più ogni differenza dai ✅ e ogni errore inatteso. Segnala anche i passaggi poco chiari o i comandi scomodi da incollare nella shell: la guida definitiva ne terrà conto.
