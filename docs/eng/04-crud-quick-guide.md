# CRUD with mongosh on a MongoDB cluster — Quick guide

CRUD operations, indexes, aggregation, transactions, validation, text search, change streams, import/export, run as the application user on the cluster from guide 03, highlighting what changes on a sharded collection. Explanations and rationale: `04-crud-complete-guide.md`.

**Prerequisites:** cluster from guide 03 with TLS, user `appuser` (`readWrite` on `labdb`), collections `ordini` and `eventi`.

**Verification status:** tested on a real installation (MongoDB 8.0.32, mongosh 2.11.1).

**Placeholders:** `<utente>`, `<FQDN>`.

> 📖 Commands and symbols: [command legend](linux-commands-legend.md).

> ⚠️ `js` blocks → inside `app_shell` (prompt `labdb>`). `bash` blocks → on the VM (prompt `$`). After an error mongosh does not run the remaining pasted lines. The numbers match only if the sections are run **in order and only once**.

| Collection | Documents | Sharded |
|---|---|---|
| `clienti` | 50 | No (primary shard) |
| `prodotti` | 30 | No (primary shard) |
| `vendite` | 5,000 | Yes, `{ clienteId: "hashed" }` |

---

## 1. Preparation

```bash
cd ~/mongo-lab/03-sharding && sudo docker compose start
source ~/mongo-lab/03-sharding/funzioni-lab.sh          # sh_eval (admin)
mkdir -p ~/mongo-lab/04-crud
```

```powershell
scp config\04-crud\funzioni-crud.sh config\04-crud\dati-crud.js config\04-crud\prodotti.csv <utente>@<FQDN>:~/mongo-lab/04-crud/
```

```bash
cd ~/mongo-lab/04-crud && file *                         # never "CRLF"
source ~/mongo-lab/04-crud/funzioni-crud.sh              # app_shell, app_eval, app_export, app_import
app_eval 'print(db.getName(), db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers[0].user)'   # labdb appuser
```

The two `source` commands must be repeated in every SSH session. In the shell: `show dbs` shows only `labdb`; `it` for the next results; `Ctrl+L` clears; `Ctrl+C` interrupts without exiting; `exit`.

## 2. Sample data

```bash
sh_eval 'printjson(sh.shardCollection("labdb.vendite", { clienteId: "hashed" }))'    # admin only: appuser → Unauthorized
time app_eval "$(cat dati-crud.js)"                      # prodotti: 30 - clienti: 50 - vendite: 5000 (~20 s)
sh_eval 'db.getSiblingDB("labdb").vendite.getShardDistribution()'
```

Test run: 62.5% / 37.5% between `sh1` and `sh2` (only 50 shard key values: few distinct values → uneven distribution). Data is deterministic and can be reloaded.

## 3. Create

```js
db.clienti.insertOne({ _id: 51, nome: "Anna", cognome: "Verdi", email: "anna.verdi51@esempio.it", tipo: "privato", indirizzo: { citta: "Genova", provincia: "GE", cap: "16121" }, interessi: ["musica"], punti: 0, newsletter: true, iscritto: new Date() })
db.prove.insertOne({ testo: "documento senza _id" })                       // creates the collection; _id = ObjectId (contains the date)
db.clienti.insertOne({ _id: 51, nome: "Doppione" })                        // E11000
db.prove.insertMany([{ _id: 1 }, { _id: 1 }, { _id: 2 }])                  // ordered: stops, only 1 inserted
db.prove.insertMany([{ _id: 3 }, { _id: 3 }, { _id: 4 }], { ordered: false })   // unordered: 3 and 4 inserted
db.prove.insertOne({ _id: "tipi", intero: 42, grande: NumberLong("9007199254740993"), decimale: NumberDecimal("0.1"), doppio: 0.1, data: new Date("2026-10-01T10:00:00Z"), vero: true, nullo: null, lista: [1, "a", { b: 2 }], annidato: { a: { b: 1 } } })
```

Types: `int`, `long`, `decimal`, `double`, `date`, `bool`, `null`, `array`, `object`. `0.1 + 0.2` → `0.30000000000000004` as `double`, `Decimal128('0.3')` as decimal: **amounts in Decimal128**.

## 4. Read

```js
db.clienti.find({ "indirizzo.citta": "Milano" }, { _id: 0, nome: 1, cognome: 1 })                 // 12
db.clienti.find({ punti: { $gte: 400 } }, { nome: 1, punti: 1 }).sort({ punti: -1 })              // 13
db.clienti.countDocuments({ $or: [ { "indirizzo.citta": "Roma" }, { punti: { $lt: 20 } } ] })     // 6
db.clienti.countDocuments({ telefono: { $exists: false } })                                       // 15
db.clienti.find({ interessi: { $all: ["sport", "viaggi"] } }, { interessi: 1 })                   // 6
db.vendite.countDocuments({ "righe.prodottoId": "P001", "righe.qta": { $gte: 2 } })               // 278
db.vendite.countDocuments({ righe: { $elemMatch: { prodottoId: "P001", qta: { $gte: 2 } } } })    // 208
db.prodotti.find({ _id: { $gt: "P015" } }, { nome: 1 }).sort({ _id: 1 }).limit(5)                 // keyset pagination
db.vendite.countDocuments({ data: { $gte: ISODate("2026-03-01"), $lt: ISODate("2026-04-01") } })  // 496
db.clienti.distinct("indirizzo.citta")                                                            // 9
```

- Projection: `1` includes, `0` excludes; they cannot be mixed (except `_id`).
- Numbers are compared by value even across different types (`200` against `Decimal128`).
- **`$elemMatch`**: without it, the conditions can be satisfied by different elements of the array (278 against 208).
- `find` returns a cursor: `hasNext()`, `next()`, `toArray()`, `forEach()`.

| Query (`explain().queryPlanner.winningPlan.stage`) | Result |
|---|---|
| `vendite`, `{ clienteId: 7 }` | `SINGLE_SHARD` |
| `vendite`, `{ stato: "annullata" }` | `SHARD_MERGE` |
| `vendite`, sorted by `data` | `SHARD_MERGE_SORT` |
| `clienti`, `{ _id: 7 }` | `SINGLE_SHARD` (not sharded) |

## 5. Update

```js
db.clienti.updateOne({ _id: 51 }, { $set: { telefono: "+39 3331234567", "indirizzo.cap": "16122" } })   // repeated: matched 1, modified 0
db.clienti.updateOne({ _id: 51 }, { $inc: { punti: 50 }, $currentDate: { aggiornato: true } })
db.clienti.updateOne({ _id: 51 }, { $unset: { newsletter: "" }, $rename: { telefono: "cellulare" } })
db.clienti.updateOne({ _id: 51 }, { $push: { interessi: "viaggi" } })
db.clienti.updateOne({ _id: 51 }, { $addToSet: { interessi: "viaggi" } })                               // modified 0
db.clienti.updateOne({ _id: 51 }, { $push: { interessi: { $each: ["cucina", "lettura"] } } })
db.clienti.updateOne({ _id: 51 }, { $pull: { interessi: "musica" } })
db.prodotti.updateMany({ giacenza: 0 }, { $set: { disponibile: false } })                               // 3
db.prodotti.updateMany({ categoria: "Libri" }, [ { $set: { prezzo: { $round: [ { $multiply: ["$prezzo", NumberDecimal("0.9")] }, 2 ] } } } ])   // pipeline
db.prodotti.updateOne({ _id: "P099" }, { $set: { nome: "Prodotto di prova", categoria: "Prove" }, $setOnInsert: { giacenza: 0, creato: new Date() } }, { upsert: true })
db.vendite.updateMany({ clienteId: 7, "righe.prodottoId": "P002" }, { $set: { "righe.$[r].sconto": NumberDecimal("2.00") } }, { arrayFilters: [ { "r.prodottoId": "P002" } ] })   // 13
const v7 = db.vendite.findOne({ clienteId: 7, "righe.prodottoId": "P002" })
db.vendite.updateOne({ _id: v7._id, clienteId: 7, "righe.prodottoId": "P002" }, { $inc: { "righe.$.qta": 1 } })
db.prove.replaceOne({ _id: 1 }, { testo: "documento sostituito" })
db.prodotti.findOneAndUpdate({ _id: "P002" }, { $inc: { giacenza: -1 } }, { projection: { giacenza: 1 } })                             // 140 (before)
db.prodotti.findOneAndUpdate({ _id: "P002" }, { $inc: { giacenza: -1 } }, { projection: { giacenza: 1 }, returnDocument: "after" })    // 138
```

- `matchedCount` ≠ `modifiedCount`. Upsert: first `upsertedCount: 1`, then `matchedCount: 1, modifiedCount: 0`.
- `$` = first matching line item; `$[r]` + `arrayFilters` = all the line items that satisfy the condition.

**On `vendite` (sharded):**

```js
db.vendite.updateOne({ stato: "annullata", canale: "telefono" }, { $set: { nota: "verificata" } })      // ok without the shard key (since 7.1)
db.vendite.insertOne({ _id: "prova-sk", clienteId: 99, stato: "prova", totale: NumberDecimal("1.00") })
db.vendite.updateOne({ _id: "prova-sk", clienteId: 99 }, { $set: { clienteId: 98 } })                   // ok: changes the shard key
db.vendite.updateMany({ clienteId: 98 }, { $set: { clienteId: 97 } })                                   // rejected
```

`Multi-update operations are not allowed when updating the shard key field.`

## 6. Delete

```js
db.vendite.deleteOne({ _id: "prova-sk", clienteId: 97 })      // 0
db.vendite.deleteOne({ _id: "prova-sk" })                     // 1, even without the shard key
db.prove.deleteOne({ _id: 3 })
db.vendite.countDocuments({ stato: "annullata", data: { $lt: ISODate("2026-02-01") } })     // 83: count first
db.vendite.deleteMany({ stato: "annullata", data: { $lt: ISODate("2026-02-01") } })         // 83
db.prodotti.findOneAndDelete({ _id: "P099" })
db.prove.deleteMany({})                                       // the collection remains, with its indexes
db.prove.drop()                                               // it is gone
```

## 7. Indexes and explain

```js
const piano = e => print("restituiti:", e.executionStats.nReturned, "| documenti esaminati:", e.executionStats.totalDocsExamined, "| chiavi esaminate:", e.executionStats.totalKeysExamined, "| stadi:", [...new Set(JSON.stringify(e.queryPlanner.winningPlan).match(/\b(COLLSCAN|IXSCAN|SORT|FETCH)\b/g))].join(" "))
piano(db.vendite.find({ stato: "spedita", canale: "web" }).sort({ data: -1 }).explain("executionStats"))
db.vendite.createIndex({ stato: 1, canale: 1, data: -1 })
piano(db.vendite.find({ stato: "spedita", canale: "web" }).sort({ data: -1 }).explain("executionStats"))
piano(db.vendite.find({ canale: "web" }).sort({ data: -1 }).explain("executionStats"))
```

| | Returned | Examined | Stages |
|---|---|---|---|
| Before | 418 | 4917 | `SORT COLLSCAN` |
| With the index | 418 | 418 | `FETCH IXSCAN` |
| Without `stato` (missing prefix) | 2450 | 4917 | `SORT COLLSCAN` |

**ESR** rule: equality, sort, range. `piano` must be redefined every time the shell is opened.

```js
db.clienti.createIndex({ email: 1 }, { unique: true })                       // then duplicate email → E11000
db.vendite.createIndex({ data: 1 }, { unique: true })                        // CannotCreateIndex: the shard key is missing
db.vendite.createIndex({ clienteId: 1, data: 1 }, { unique: true })          // ok, even with a hashed shard key
db.sessioni.createIndex({ creata: 1 }, { expireAfterSeconds: 120 })          // TTL: check every 60 s
db.prodotti.createIndex({ nome: 1 }, { partialFilterExpression: { giacenza: { $gt: 0 } } })   // used only if the filter guarantees giacenza > 0
```

⚠️ `clienteId_1_data_1` stays until cleanup: no two sales of the same customer with the same `data` (or both without it).

## 8. Aggregation

```js
db.vendite.aggregate([ { $group: { _id: "$stato", vendite: { $sum: 1 }, incasso: { $sum: "$totale" } } }, { $sort: { vendite: -1 } } ])
db.vendite.aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$data" } }, incasso: { $sum: "$totale" } } }, { $sort: { _id: 1 } } ])
db.vendite.aggregate([ { $unwind: "$righe" }, { $group: { _id: "$righe.prodottoId", pezzi: { $sum: "$righe.qta" } } }, { $sort: { pezzi: -1, _id: 1 } }, { $limit: 5 }, { $lookup: { from: "prodotti", localField: "_id", foreignField: "_id", as: "prodotto" } }, { $project: { _id: 0, prodotto: { $first: "$prodotto.nome" }, pezzi: 1 } } ])
db.vendite.aggregate([ { $facet: { perCanale: [ { $group: { _id: "$canale", n: { $sum: 1 } } }, { $sort: { n: -1 } } ], perFascia: [ { $bucket: { groupBy: "$totale", boundaries: [0, 50, 100, 250, 500, 1000, 5000], default: "altro", output: { n: { $sum: 1 } } } } ] } } ])
db.vendite.aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$data" } }, incasso: { $sum: "$totale" }, vendite: { $sum: 1 } } }, { $merge: { into: "riepilogo_mensile", whenMatched: "replace", whenNotMatched: "insert" } } ])
```

Test run: consegnata 2493 (1,195,049.30), spedita 881, in lavorazione 800, annullata 743; products 739 / 714 / 708 / 692 / 692 (tie → broken on `_id`); channels web 2450, telefono 1241, negozio 1226; `riepilogo_mensile` 11 documents.

`$lookup` after `$limit`: enrich after reducing. On `vendite` the router **splits** the pipeline: `$match` + partial `$group` on each shard, `$mergeCursors` + final `$group` on the router (`explain().splitPipeline`). With the shard key in the `$match`: a single shard, no split.

## 9. Transactions

Counters before and after (📍 VM):

```bash
sh_eval 'const t = db.serverStatus().transactions; print("avviate:", t.totalStarted, "- confermate:", t.totalCommitted, "- annullate:", t.totalAborted); printjson(Object.fromEntries(Object.entries(t.commitTypes).map(([k, v]) => [k, v.successful])))'
```

In the shell, **without exiting** between one step and the next:

```js
const s = db.getMongo().startSession()
const sp = s.getDatabase("labdb").prodotti, sv = s.getDatabase("labdb").vendite
s.withTransaction(() => { const r = sp.updateOne({ _id: "P003", giacenza: { $gte: 2 } }, { $inc: { giacenza: -2 } }); if (r.modifiedCount !== 1) throw new Error("giacenza insufficiente per P003"); sv.insertOne({ clienteId: 12, data: new Date(), stato: "in lavorazione", canale: "web", righe: [ { prodottoId: "P003", qta: 2, prezzo: NumberDecimal("79.90") } ], totale: NumberDecimal("159.80") }) }, { readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } })
try { s.withTransaction(() => { sv.insertOne({ clienteId: 13, data: new Date(), stato: "in lavorazione", canale: "web", righe: [ { prodottoId: "P007", qta: 1, prezzo: NumberDecimal("59.90") } ], totale: NumberDecimal("59.90") }); const r = sp.updateOne({ _id: "P007", giacenza: { $gte: 1 } }, { $inc: { giacenza: -1 } }); if (r.modifiedCount !== 1) throw new Error("giacenza insufficiente per P007") }) } catch (e) { print("transazione annullata:", e.message) }
s.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } })
sp.updateOne({ _id: "P004" }, { $inc: { giacenza: -1 } })
print("dentro la transazione:", sp.findOne({ _id: "P004" }).giacenza, "- fuori:", db.prodotti.findOne({ _id: "P004" }).giacenza)   // 19 - 20
s.commitTransaction()
s.withTransaction(() => { sv.updateMany({ clienteId: { $in: [1, 2, 3, 4, 5, 6] } }, { $set: { verificata: true } }); sp.updateOne({ _id: "P001" }, { $set: { ultimaVerifica: new Date() } }) })   // 603 sales, 2 shards
s.endSession()
```

- Only the operations done through `sp` and `sv` belong to the transaction.
- Successful: P003 from 35 to 33. Aborted: even the insert already executed disappears (count unchanged).
- Isolation: outside the transaction the old value stays visible until the commit.
- Test run: aborted +2; `twoPhaseCommit` +1 for the transaction across two shards (two-phase commit, slower).

Before reaching for transactions: model the data so that what changes together lives in the same document.

## 10. bulkWrite and write concern

```js
db.prodotti.bulkWrite([ { insertOne: { document: { _id: "P100", nome: "Prodotto bulk", categoria: "Prove", prezzo: NumberDecimal("1.00"), giacenza: 10 } } }, { updateOne: { filter: { _id: "P002" }, update: { $inc: { giacenza: 10 } } } }, { updateMany: { filter: { categoria: "Ufficio" }, update: { $set: { reparto: "B" } } } }, { replaceOne: { filter: { _id: "P100" }, replacement: { nome: "Prodotto bulk sostituito", categoria: "Prove", prezzo: NumberDecimal("2.00"), giacenza: 5 } } }, { deleteOne: { filter: { _id: "P100" } } } ])
db.prodotti.insertOne({ _id: "P105" }, { writeConcern: { w: "majority", wtimeout: 5000 } })      // ok
db.prodotti.insertOne({ _id: "P106" }, { writeConcern: { w: 4, wtimeout: 3000 } })               // UnsatisfiableWriteConcern (100)
db.prodotti.deleteMany({ _id: { $in: ["P105", "P106"] } })                                       // 2
```

`bulkWrite`: inserted 1, matched 6, modified 6, deleted 1; it is not a transaction; ordered and unordered work as in `insertMany`.

⚠️ With `w: 4` the error is returned, but **P106 has been written** (`n: 1`, and the `deleteMany` deletes 2): a write concern error does not roll back the write.

## 11. Schema validation

```js
db.createCollection("recensioni", { validator: { $jsonSchema: { bsonType: "object", required: ["prodottoId", "clienteId", "voto"], properties: { prodottoId: { bsonType: "string", pattern: "^P[0-9]{3}$" }, clienteId: { bsonType: "int" }, voto: { bsonType: "int", minimum: 1, maximum: 5 }, testo: { bsonType: "string", maxLength: 500 } } } }, validationLevel: "strict", validationAction: "error" })
db.recensioni.insertOne({ prodottoId: "P017", clienteId: 3, voto: 5, testo: "Chiaro e pratico" })   // ok
db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 })                              // Document failed validation (maximum)
db.recensioni.insertOne({ prodottoId: "P017", voto: 4 })                                            // (required)
db.recensioni.insertOne({ prodottoId: "X1", clienteId: 5, voto: 4 })                                // (pattern)
db.runCommand({ collMod: "recensioni", validationAction: "warn" })                                  // Unauthorized for appuser
```

```bash
sh_eval 'printjson(db.getSiblingDB("labdb").runCommand({ collMod: "recensioni", validationAction: "warn" }))'
app_eval 'db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 }); print("documenti non validi:", db.recensioni.countDocuments({ $nor: [ db.getCollectionInfos({ name: "recensioni" })[0].options.validator ] }))'   # 1
sh_eval 'printjson(db.getSiblingDB("labdb").runCommand({ collMod: "recensioni", validationAction: "error" }))'
```

`Additional information` names the violated rule. `readWrite` creates collections with a validator, but cannot change the options (`collMod`). With `warn` invalid documents get in; find them with `$nor` on the validator. On existing data: `warn` → clean-up → `error`.

## 12. Text search

```js
db.prodotti.createIndex({ nome: "text", descrizione: "text" }, { default_language: "italian", weights: { nome: 3 }, name: "testo_prodotti" })
db.prodotti.find({ $text: { $search: "montagna" } }, { nome: 1, punteggio: { $meta: "textScore" } }).sort({ punteggio: { $meta: "textScore" } })   // P019, P024
db.prodotti.find({ $text: { $search: "cucinare" } }, { nome: 1 })             // common stem: P018, P013
db.prodotti.find({ $text: { $search: "\"senza fili\"" } }, { nome: 1 })       // exact phrase: P002
db.prodotti.find({ $text: { $search: "ufficio -sedia" } }, { nome: 1 })       // exclusion: P030
db.prodotti.find({ $text: { $search: "per" } }, { nome: 1 })                  // stop word: nothing
db.prodotti.createIndex({ tags: "text" })                                     // IndexOptionsConflict: only one per collection
```

Fields that are not indexed (`tags`) are not searched. Several words = OR. For search aimed at end users: a dedicated engine.

## 13. Change streams

Two terminals. **Terminal 2** (watches):

```js
let ultimo = null; const cs = db.vendite.watch([], { fullDocument: "updateLookup" })
while (true) { const ev = cs.tryNext(); if (ev) { ultimo = ev._id; print(ev.operationType, JSON.stringify(ev.documentKey), ev.updateDescription ? JSON.stringify(ev.updateDescription.updatedFields) : "") } else { sleep(200) } }
```

**Terminal 1** (writes):

```bash
app_eval 'db.vendite.insertMany([ { clienteId: 1, stato: "prova-cs", totale: NumberDecimal("10.00") }, { clienteId: 2, stato: "prova-cs", totale: NumberDecimal("20.00") } ]); db.vendite.updateOne({ clienteId: 1, stato: "prova-cs" }, { $set: { totale: NumberDecimal("12.00") } }); db.vendite.deleteMany({ stato: "prova-cs" }); print("fatto")'
```

Test run: 2 `insert`, 1 `update` (`{"totale":...}`), 2 `delete`; `documentKey` contains **`clienteId` and `_id`** (shard key included); the router merges the streams of the two shards.

**Resume**: terminal 2 `Ctrl+C` **once** (`Stopping execution...`, shell still open, `ultimo` kept); **then** terminal 1:

```bash
app_eval 'db.vendite.insertOne({ clienteId: 3, stato: "prova-cs2" }); db.vendite.deleteMany({ stato: "prova-cs2" }); print("fatto mentre nessuno guardava")'
```

Terminal 2:

```js
const cs2 = db.vendite.watch([], { resumeAfter: ultimo }); for (let i = 0; i < 30; i++) { const ev = cs2.tryNext(); if (ev) print("recuperato:", ev.operationType, JSON.stringify(ev.documentKey)); else sleep(200) }
```

Test run: `recuperato: insert`, `recuperato: delete` (nothing if the write started before the `Ctrl+C`). In production: a dedicated process, resume token stored durably; resuming works as long as the event is in the oplog.

## 14. Import and export

```bash
cd ~/mongo-lab/04-crud
app_export --collection=prodotti --query='{"categoria":"Libri"}' > libri.json                    # 6; prezzo {"$numberDecimal":"12.60"}
app_export --collection=clienti --type=csv --fields=_id,nome,cognome,indirizzo.citta,punti --sort='{"_id":1}' > clienti.csv   # 51
app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes < prodotti.csv                 # 5 imported, decimal and int
app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes < prodotti.csv                 # 0 imported, 5 failed (E11000)
app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes --mode=upsert < prodotti.csv   # 0 / 0: identical documents
app_import --collection=libri_copia < libri.json                                                                  # 6, prezzo still decimal
```

Extended JSON preserves types. In CSV the fields are listed (`--fields`) and the types are declared in the header (`prezzo.decimal()`, `giacenza.int32()`) with `--columnsHaveTypes`. Modes: `insert`, `upsert` (replaces), `merge` (adds fields). They are not backup tools.

## 15. Cleanup

```bash
app_eval '["clienti", "prodotti", "vendite", "recensioni", "riepilogo_mensile", "prodotti_import", "libri_copia"].forEach(n => print(n, db.getCollection(n).drop())); print("restano:", db.getCollectionNames().sort().join(", "))'
sh_eval 'print("vendite ancora distribuita?", db.getSiblingDB("config").collections.findOne({ _id: "labdb.vendite" }) !== null)'    # false
rm ~/mongo-lab/04-crud/libri.json ~/mongo-lab/04-crud/clienti.csv
```

`eventi, ordini` remain. The `drop` by `appuser` also removes the sharding metadata. To repeat: cleanup, then from section 2 (reloading alone keeps the indexes of `vendite`).

## 16. Troubleshooting

| Symptom | Solution |
|---|---|
| `-bash: syntax error near unexpected token` | JavaScript pasted on the VM: `app_shell` |
| `app_shell` / `sh_eval: command not found` | Repeat the two `source` commands |
| Lines not run after an error | Paste them again |
| Repeated characters in the pasted line | Display only |
| `piano`, `s`, `ultimo is not defined` | Shell reopened: redefine, or restart from the section |
| Numbers differ from the test run results | Section repeated or out of order: cleanup and section 2 |
| `E11000 ... clienteId_1_data_1` | Unique index from section 7: document left over from a trial |
| No events in the change stream | Two terminals are needed; start the loop first |
| The resume prints nothing | Stop the loop before writing |

## 17. Lab vs production

| | Lab | Production |
|---|---|---|
| Tool | `mongosh` by hand | Driver; `mongosh` for maintenance |
| User | `appuser` + admin for 3 operations | Minimal role per application |
| Shard key | 50 values → 62% / 38% | Many distinct values |
| Indexes | Created on the fly | On the real queries, verified with `explain` |
| Deletes | Direct | Count, backup, often soft delete |
| Transactions | To see them | Only where the data model is not enough |
| Write concern | Tried by hand | `majority` + `wtimeout`, error handled |
| Validation | At creation | `warn` → clean-up → `error` |
| Search | Text index | Dedicated engine |
| Change stream | Loop in the shell | Dedicated process, durable token |
