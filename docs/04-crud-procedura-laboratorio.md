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
