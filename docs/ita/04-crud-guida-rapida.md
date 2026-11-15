# CRUD con mongosh su un cluster MongoDB — Guida rapida

Operazioni CRUD, indici, aggregazione, transazioni, validazione, ricerca testuale, change stream, import/export, eseguiti come utente applicativo sul cluster della guida 03, con in evidenza ciò che cambia su una collezione distribuita. Spiegazioni e motivazioni: `04-crud-guida-completa.md`.

**Prerequisiti:** cluster della guida 03 con TLS, utente `appuser` (`readWrite` su `labdb`), collezioni `ordini` ed `eventi`.

**Stato di verifica:** collaudato su installazione reale (MongoDB 8.0.32, mongosh 2.11.1).

**Segnaposto:** `<utente>`, `<FQDN>`.

> 📖 Comandi e simboli: [legenda dei comandi](legenda-comandi-linux.md).

> ⚠️ Blocchi `js` → dentro `app_shell` (prompt `labdb>`). Blocchi `bash` → sulla VM (prompt `$`). Dopo un errore mongosh non esegue le righe successive dell'incolla. I numeri coincidono solo eseguendo le sezioni **in ordine e una sola volta**.

| Collezione | Documenti | Distribuita |
|---|---|---|
| `clienti` | 50 | No (shard primario) |
| `prodotti` | 30 | No (shard primario) |
| `vendite` | 5.000 | Sì, `{ clienteId: "hashed" }` |

---

## 1. Preparazione

```bash
cd ~/mongo-lab/03-sharding && sudo docker compose start
source ~/mongo-lab/03-sharding/funzioni-lab.sh          # sh_eval (admin)
mkdir -p ~/mongo-lab/04-crud
```

```powershell
scp config\04-crud\funzioni-crud.sh config\04-crud\dati-crud.js config\04-crud\prodotti.csv <utente>@<FQDN>:~/mongo-lab/04-crud/
```

```bash
cd ~/mongo-lab/04-crud && file *                         # mai "CRLF"
source ~/mongo-lab/04-crud/funzioni-crud.sh              # app_shell, app_eval, app_export, app_import
app_eval 'print(db.getName(), db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers[0].user)'   # labdb appuser
```

I due `source` vanno ripetuti a ogni sessione SSH. Nella shell: `show dbs` mostra solo `labdb`; `it` per i risultati successivi; `Ctrl+L` pulisce; `Ctrl+C` interrompe senza uscire; `exit`.

## 2. Dati di esempio

```bash
sh_eval 'printjson(sh.shardCollection("labdb.vendite", { clienteId: "hashed" }))'    # solo admin: appuser → Unauthorized
time app_eval "$(cat dati-crud.js)"                      # prodotti: 30 - clienti: 50 - vendite: 5000 (~20 s)
sh_eval 'db.getSiblingDB("labdb").vendite.getShardDistribution()'
```

Collaudo: 62,5% / 37,5% tra `sh1` e `sh2` (50 soli valori di shard key: pochi valori distinti → distribuzione irregolare). Dati deterministici e rilanciabili.

## 3. Create

```js
db.clienti.insertOne({ _id: 51, nome: "Anna", cognome: "Verdi", email: "anna.verdi51@esempio.it", tipo: "privato", indirizzo: { citta: "Genova", provincia: "GE", cap: "16121" }, interessi: ["musica"], punti: 0, newsletter: true, iscritto: new Date() })
db.prove.insertOne({ testo: "documento senza _id" })                       // crea la collezione; _id = ObjectId (contiene la data)
db.clienti.insertOne({ _id: 51, nome: "Doppione" })                        // E11000
db.prove.insertMany([{ _id: 1 }, { _id: 1 }, { _id: 2 }])                  // ordinato: si ferma, inserito solo 1
db.prove.insertMany([{ _id: 3 }, { _id: 3 }, { _id: 4 }], { ordered: false })   // non ordinato: inseriti 3 e 4
db.prove.insertOne({ _id: "tipi", intero: 42, grande: NumberLong("9007199254740993"), decimale: NumberDecimal("0.1"), doppio: 0.1, data: new Date("2026-10-01T10:00:00Z"), vero: true, nullo: null, lista: [1, "a", { b: 2 }], annidato: { a: { b: 1 } } })
```

Tipi: `int`, `long`, `decimal`, `double`, `date`, `bool`, `null`, `array`, `object`. `0.1 + 0.2` → `0.30000000000000004` in `double`, `Decimal128('0.3')` in decimale: **importi in Decimal128**.

## 4. Read

```js
db.clienti.find({ "indirizzo.citta": "Milano" }, { _id: 0, nome: 1, cognome: 1 })                 // 12
db.clienti.find({ punti: { $gte: 400 } }, { nome: 1, punti: 1 }).sort({ punti: -1 })              // 13
db.clienti.countDocuments({ $or: [ { "indirizzo.citta": "Roma" }, { punti: { $lt: 20 } } ] })     // 6
db.clienti.countDocuments({ telefono: { $exists: false } })                                       // 15
db.clienti.find({ interessi: { $all: ["sport", "viaggi"] } }, { interessi: 1 })                   // 6
db.vendite.countDocuments({ "righe.prodottoId": "P001", "righe.qta": { $gte: 2 } })               // 278
db.vendite.countDocuments({ righe: { $elemMatch: { prodottoId: "P001", qta: { $gte: 2 } } } })    // 208
db.prodotti.find({ _id: { $gt: "P015" } }, { nome: 1 }).sort({ _id: 1 }).limit(5)                 // paginazione per chiave
db.vendite.countDocuments({ data: { $gte: ISODate("2026-03-01"), $lt: ISODate("2026-04-01") } })  // 496
db.clienti.distinct("indirizzo.citta")                                                            // 9
```

- Proiezione: `1` include, `0` esclude; non si mescolano (tranne `_id`).
- Numeri confrontati per valore anche tra tipi diversi (`200` contro `Decimal128`).
- **`$elemMatch`**: senza, le condizioni possono essere soddisfatte da elementi diversi dell'array (278 contro 208).
- `find` restituisce un cursore: `hasNext()`, `next()`, `toArray()`, `forEach()`.

| Query (`explain().queryPlanner.winningPlan.stage`) | Risultato |
|---|---|
| `vendite`, `{ clienteId: 7 }` | `SINGLE_SHARD` |
| `vendite`, `{ stato: "annullata" }` | `SHARD_MERGE` |
| `vendite`, ordinata per `data` | `SHARD_MERGE_SORT` |
| `clienti`, `{ _id: 7 }` | `SINGLE_SHARD` (non distribuita) |

## 5. Update

```js
db.clienti.updateOne({ _id: 51 }, { $set: { telefono: "+39 3331234567", "indirizzo.cap": "16122" } })   // ripetuto: matched 1, modified 0
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
db.prodotti.findOneAndUpdate({ _id: "P002" }, { $inc: { giacenza: -1 } }, { projection: { giacenza: 1 } })                             // 140 (prima)
db.prodotti.findOneAndUpdate({ _id: "P002" }, { $inc: { giacenza: -1 } }, { projection: { giacenza: 1 }, returnDocument: "after" })    // 138
```

- `matchedCount` ≠ `modifiedCount`. Upsert: prima `upsertedCount: 1`, poi `matchedCount: 1, modifiedCount: 0`.
- `$` = prima riga corrispondente; `$[r]` + `arrayFilters` = tutte le righe che soddisfano la condizione.

**Su `vendite` (distribuita):**

```js
db.vendite.updateOne({ stato: "annullata", canale: "telefono" }, { $set: { nota: "verificata" } })      // ok senza shard key (da 7.1)
db.vendite.insertOne({ _id: "prova-sk", clienteId: 99, stato: "prova", totale: NumberDecimal("1.00") })
db.vendite.updateOne({ _id: "prova-sk", clienteId: 99 }, { $set: { clienteId: 98 } })                   // ok: cambia la shard key
db.vendite.updateMany({ clienteId: 98 }, { $set: { clienteId: 97 } })                                   // rifiutato
```

`Multi-update operations are not allowed when updating the shard key field.`

## 6. Delete

```js
db.vendite.deleteOne({ _id: "prova-sk", clienteId: 97 })      // 0
db.vendite.deleteOne({ _id: "prova-sk" })                     // 1, anche senza shard key
db.prove.deleteOne({ _id: 3 })
db.vendite.countDocuments({ stato: "annullata", data: { $lt: ISODate("2026-02-01") } })     // 83: contare prima
db.vendite.deleteMany({ stato: "annullata", data: { $lt: ISODate("2026-02-01") } })         // 83
db.prodotti.findOneAndDelete({ _id: "P099" })
db.prove.deleteMany({})                                       // la collezione resta, con gli indici
db.prove.drop()                                               // sparisce
```

## 7. Indici ed explain

```js
const piano = e => print("restituiti:", e.executionStats.nReturned, "| documenti esaminati:", e.executionStats.totalDocsExamined, "| chiavi esaminate:", e.executionStats.totalKeysExamined, "| stadi:", [...new Set(JSON.stringify(e.queryPlanner.winningPlan).match(/\b(COLLSCAN|IXSCAN|SORT|FETCH)\b/g))].join(" "))
piano(db.vendite.find({ stato: "spedita", canale: "web" }).sort({ data: -1 }).explain("executionStats"))
db.vendite.createIndex({ stato: 1, canale: 1, data: -1 })
piano(db.vendite.find({ stato: "spedita", canale: "web" }).sort({ data: -1 }).explain("executionStats"))
piano(db.vendite.find({ canale: "web" }).sort({ data: -1 }).explain("executionStats"))
```

| | Restituiti | Esaminati | Stadi |
|---|---|---|---|
| Prima | 418 | 4917 | `SORT COLLSCAN` |
| Con l'indice | 418 | 418 | `FETCH IXSCAN` |
| Senza `stato` (prefisso mancante) | 2450 | 4917 | `SORT COLLSCAN` |

Regola **ESR**: uguaglianza, ordinamento, intervallo. `piano` va ridefinita a ogni apertura della shell.

```js
db.clienti.createIndex({ email: 1 }, { unique: true })                       // poi email duplicata → E11000
db.vendite.createIndex({ data: 1 }, { unique: true })                        // CannotCreateIndex: manca la shard key
db.vendite.createIndex({ clienteId: 1, data: 1 }, { unique: true })          // ok, anche con shard key hashed
db.sessioni.createIndex({ creata: 1 }, { expireAfterSeconds: 120 })          // TTL: controllo ogni 60 s
db.prodotti.createIndex({ nome: 1 }, { partialFilterExpression: { giacenza: { $gt: 0 } } })   // usato solo se il filtro garantisce giacenza > 0
```

⚠️ `clienteId_1_data_1` resta fino alla pulizia: niente due vendite dello stesso cliente con la stessa `data` (o entrambe senza).

## 8. Aggregazione

```js
db.vendite.aggregate([ { $group: { _id: "$stato", vendite: { $sum: 1 }, incasso: { $sum: "$totale" } } }, { $sort: { vendite: -1 } } ])
db.vendite.aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$data" } }, incasso: { $sum: "$totale" } } }, { $sort: { _id: 1 } } ])
db.vendite.aggregate([ { $unwind: "$righe" }, { $group: { _id: "$righe.prodottoId", pezzi: { $sum: "$righe.qta" } } }, { $sort: { pezzi: -1, _id: 1 } }, { $limit: 5 }, { $lookup: { from: "prodotti", localField: "_id", foreignField: "_id", as: "prodotto" } }, { $project: { _id: 0, prodotto: { $first: "$prodotto.nome" }, pezzi: 1 } } ])
db.vendite.aggregate([ { $facet: { perCanale: [ { $group: { _id: "$canale", n: { $sum: 1 } } }, { $sort: { n: -1 } } ], perFascia: [ { $bucket: { groupBy: "$totale", boundaries: [0, 50, 100, 250, 500, 1000, 5000], default: "altro", output: { n: { $sum: 1 } } } } ] } } ])
db.vendite.aggregate([ { $match: { stato: "consegnata" } }, { $group: { _id: { $dateToString: { format: "%Y-%m", date: "$data" } }, incasso: { $sum: "$totale" }, vendite: { $sum: 1 } } }, { $merge: { into: "riepilogo_mensile", whenMatched: "replace", whenNotMatched: "insert" } } ])
```

Collaudo: consegnata 2493 (1.195.049,30), spedita 881, in lavorazione 800, annullata 743; prodotti 739 / 714 / 708 / 692 / 692 (pari merito → spareggio su `_id`); canali web 2450, telefono 1241, negozio 1226; `riepilogo_mensile` 11 documenti.

`$lookup` dopo `$limit`: si arricchisce dopo aver ridotto. Su `vendite` il router **divide** la pipeline: `$match` + `$group` parziale su ogni shard, `$mergeCursors` + `$group` finale sul router (`explain().splitPipeline`). Con la shard key nel `$match`: un solo shard, nessuna divisione.

## 9. Transazioni

Contatori prima e dopo (📍 VM):

```bash
sh_eval 'const t = db.serverStatus().transactions; print("avviate:", t.totalStarted, "- confermate:", t.totalCommitted, "- annullate:", t.totalAborted); printjson(Object.fromEntries(Object.entries(t.commitTypes).map(([k, v]) => [k, v.successful])))'
```

Nella shell, **senza uscire** tra un passo e l'altro:

```js
const s = db.getMongo().startSession()
const sp = s.getDatabase("labdb").prodotti, sv = s.getDatabase("labdb").vendite
s.withTransaction(() => { const r = sp.updateOne({ _id: "P003", giacenza: { $gte: 2 } }, { $inc: { giacenza: -2 } }); if (r.modifiedCount !== 1) throw new Error("giacenza insufficiente per P003"); sv.insertOne({ clienteId: 12, data: new Date(), stato: "in lavorazione", canale: "web", righe: [ { prodottoId: "P003", qta: 2, prezzo: NumberDecimal("79.90") } ], totale: NumberDecimal("159.80") }) }, { readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } })
try { s.withTransaction(() => { sv.insertOne({ clienteId: 13, data: new Date(), stato: "in lavorazione", canale: "web", righe: [ { prodottoId: "P007", qta: 1, prezzo: NumberDecimal("59.90") } ], totale: NumberDecimal("59.90") }); const r = sp.updateOne({ _id: "P007", giacenza: { $gte: 1 } }, { $inc: { giacenza: -1 } }); if (r.modifiedCount !== 1) throw new Error("giacenza insufficiente per P007") }) } catch (e) { print("transazione annullata:", e.message) }
s.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } })
sp.updateOne({ _id: "P004" }, { $inc: { giacenza: -1 } })
print("dentro la transazione:", sp.findOne({ _id: "P004" }).giacenza, "- fuori:", db.prodotti.findOne({ _id: "P004" }).giacenza)   // 19 - 20
s.commitTransaction()
s.withTransaction(() => { sv.updateMany({ clienteId: { $in: [1, 2, 3, 4, 5, 6] } }, { $set: { verificata: true } }); sp.updateOne({ _id: "P001" }, { $set: { ultimaVerifica: new Date() } }) })   // 603 vendite, 2 shard
s.endSession()
```

- Solo le operazioni fatte tramite `sp` e `sv` appartengono alla transazione.
- Riuscita: P003 da 35 a 33. Annullata: anche l'inserimento già eseguito sparisce (conteggio invariato).
- Isolamento: fuori dalla transazione il valore vecchio resta visibile fino al commit.
- Collaudo: annullate +2; `twoPhaseCommit` +1 per la transazione su due shard (commit in due fasi, più lento).

Prima delle transazioni: modellare i dati perché ciò che cambia insieme stia nello stesso documento.

## 10. bulkWrite e write concern

```js
db.prodotti.bulkWrite([ { insertOne: { document: { _id: "P100", nome: "Prodotto bulk", categoria: "Prove", prezzo: NumberDecimal("1.00"), giacenza: 10 } } }, { updateOne: { filter: { _id: "P002" }, update: { $inc: { giacenza: 10 } } } }, { updateMany: { filter: { categoria: "Ufficio" }, update: { $set: { reparto: "B" } } } }, { replaceOne: { filter: { _id: "P100" }, replacement: { nome: "Prodotto bulk sostituito", categoria: "Prove", prezzo: NumberDecimal("2.00"), giacenza: 5 } } }, { deleteOne: { filter: { _id: "P100" } } } ])
db.prodotti.insertOne({ _id: "P105" }, { writeConcern: { w: "majority", wtimeout: 5000 } })      // ok
db.prodotti.insertOne({ _id: "P106" }, { writeConcern: { w: 4, wtimeout: 3000 } })               // UnsatisfiableWriteConcern (100)
db.prodotti.deleteMany({ _id: { $in: ["P105", "P106"] } })                                       // 2
```

`bulkWrite`: inserted 1, matched 6, modified 6, deleted 1; non è una transazione; ordinato e non ordinato come `insertMany`.

⚠️ Con `w: 4` l'errore arriva, ma **P106 è stato scritto** (`n: 1`, e il `deleteMany` ne cancella 2): un errore di write concern non annulla la scrittura.

## 11. Validazione dello schema

```js
db.createCollection("recensioni", { validator: { $jsonSchema: { bsonType: "object", required: ["prodottoId", "clienteId", "voto"], properties: { prodottoId: { bsonType: "string", pattern: "^P[0-9]{3}$" }, clienteId: { bsonType: "int" }, voto: { bsonType: "int", minimum: 1, maximum: 5 }, testo: { bsonType: "string", maxLength: 500 } } } }, validationLevel: "strict", validationAction: "error" })
db.recensioni.insertOne({ prodottoId: "P017", clienteId: 3, voto: 5, testo: "Chiaro e pratico" })   // ok
db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 })                              // Document failed validation (maximum)
db.recensioni.insertOne({ prodottoId: "P017", voto: 4 })                                            // (required)
db.recensioni.insertOne({ prodottoId: "X1", clienteId: 5, voto: 4 })                                // (pattern)
db.runCommand({ collMod: "recensioni", validationAction: "warn" })                                  // Unauthorized per appuser
```

```bash
sh_eval 'printjson(db.getSiblingDB("labdb").runCommand({ collMod: "recensioni", validationAction: "warn" }))'
app_eval 'db.recensioni.insertOne({ prodottoId: "P017", clienteId: 4, voto: 6 }); print("documenti non validi:", db.recensioni.countDocuments({ $nor: [ db.getCollectionInfos({ name: "recensioni" })[0].options.validator ] }))'   # 1
sh_eval 'printjson(db.getSiblingDB("labdb").runCommand({ collMod: "recensioni", validationAction: "error" }))'
```

`Additional information` indica la regola violata. `readWrite` crea collezioni con validatore, ma non modifica le opzioni (`collMod`). Con `warn` i documenti non validi entrano; si trovano con `$nor` sul validatore. Su dati esistenti: `warn` → bonifica → `error`.

## 12. Ricerca testuale

```js
db.prodotti.createIndex({ nome: "text", descrizione: "text" }, { default_language: "italian", weights: { nome: 3 }, name: "testo_prodotti" })
db.prodotti.find({ $text: { $search: "montagna" } }, { nome: 1, punteggio: { $meta: "textScore" } }).sort({ punteggio: { $meta: "textScore" } })   // P019, P024
db.prodotti.find({ $text: { $search: "cucinare" } }, { nome: 1 })             // radice comune: P018, P013
db.prodotti.find({ $text: { $search: "\"senza fili\"" } }, { nome: 1 })       // frase esatta: P002
db.prodotti.find({ $text: { $search: "ufficio -sedia" } }, { nome: 1 })       // esclusione: P030
db.prodotti.find({ $text: { $search: "per" } }, { nome: 1 })                  // stop word: nulla
db.prodotti.createIndex({ tags: "text" })                                     // IndexOptionsConflict: uno solo per collezione
```

I campi non indicizzati (`tags`) non vengono cercati. Più parole = OR. Per la ricerca rivolta agli utenti finali: motore dedicato.

## 13. Change stream

Due terminali. **Terminale 2** (osserva):

```js
let ultimo = null; const cs = db.vendite.watch([], { fullDocument: "updateLookup" })
while (true) { const ev = cs.tryNext(); if (ev) { ultimo = ev._id; print(ev.operationType, JSON.stringify(ev.documentKey), ev.updateDescription ? JSON.stringify(ev.updateDescription.updatedFields) : "") } else { sleep(200) } }
```

**Terminale 1** (scrive):

```bash
app_eval 'db.vendite.insertMany([ { clienteId: 1, stato: "prova-cs", totale: NumberDecimal("10.00") }, { clienteId: 2, stato: "prova-cs", totale: NumberDecimal("20.00") } ]); db.vendite.updateOne({ clienteId: 1, stato: "prova-cs" }, { $set: { totale: NumberDecimal("12.00") } }); db.vendite.deleteMany({ stato: "prova-cs" }); print("fatto")'
```

Collaudo: 2 `insert`, 1 `update` (`{"totale":...}`), 2 `delete`; `documentKey` contiene **`clienteId` e `_id`** (shard key inclusa); il router unisce i flussi dei due shard.

**Ripresa**: terminale 2 `Ctrl+C` **una volta** (`Stopping execution...`, shell aperta, `ultimo` conservato); **poi** terminale 1:

```bash
app_eval 'db.vendite.insertOne({ clienteId: 3, stato: "prova-cs2" }); db.vendite.deleteMany({ stato: "prova-cs2" }); print("fatto mentre nessuno guardava")'
```

Terminale 2:

```js
const cs2 = db.vendite.watch([], { resumeAfter: ultimo }); for (let i = 0; i < 30; i++) { const ev = cs2.tryNext(); if (ev) print("recuperato:", ev.operationType, JSON.stringify(ev.documentKey)); else sleep(200) }
```

Collaudo: `recuperato: insert`, `recuperato: delete` (nulla se la scrittura è partita prima del `Ctrl+C`). In produzione: processo dedicato, resume token salvato in modo durevole; la ripresa vale finché l'evento è nell'oplog.

## 14. Import ed export

```bash
cd ~/mongo-lab/04-crud
app_export --collection=prodotti --query='{"categoria":"Libri"}' > libri.json                    # 6; prezzo {"$numberDecimal":"12.60"}
app_export --collection=clienti --type=csv --fields=_id,nome,cognome,indirizzo.citta,punti --sort='{"_id":1}' > clienti.csv   # 51
app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes < prodotti.csv                 # 5 importati, decimal e int
app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes < prodotti.csv                 # 0 importati, 5 falliti (E11000)
app_import --collection=prodotti_import --type=csv --headerline --columnsHaveTypes --mode=upsert < prodotti.csv   # 0 / 0: documenti identici
app_import --collection=libri_copia < libri.json                                                                  # 6, prezzo ancora decimal
```

Extended JSON conserva i tipi. In CSV i campi si elencano (`--fields`) e i tipi si dichiarano nell'intestazione (`prezzo.decimal()`, `giacenza.int32()`) con `--columnsHaveTypes`. Modalità: `insert`, `upsert` (sostituisce), `merge` (aggiunge campi). Non sono strumenti di backup.

## 15. Pulizia

```bash
app_eval '["clienti", "prodotti", "vendite", "recensioni", "riepilogo_mensile", "prodotti_import", "libri_copia"].forEach(n => print(n, db.getCollection(n).drop())); print("restano:", db.getCollectionNames().sort().join(", "))'
sh_eval 'print("vendite ancora distribuita?", db.getSiblingDB("config").collections.findOne({ _id: "labdb.vendite" }) !== null)'    # false
rm ~/mongo-lab/04-crud/libri.json ~/mongo-lab/04-crud/clienti.csv
```

Restano `eventi, ordini`. Il `drop` di `appuser` elimina anche i metadati di distribuzione. Per ripetere: pulizia, poi dalla sezione 2 (il solo ricaricamento conserva gli indici di `vendite`).

## 16. Troubleshooting

| Sintomo | Soluzione |
|---|---|
| `-bash: syntax error near unexpected token` | JavaScript incollato sulla VM: `app_shell` |
| `app_shell` / `sh_eval: command not found` | Ripetere i due `source` |
| Righe non eseguite dopo un errore | Incollarle di nuovo |
| Caratteri ripetuti nella riga incollata | Solo visivo |
| `piano`, `s`, `ultimo is not defined` | Shell riaperta: ridefinire, o ripartire dalla sezione |
| Numeri diversi dai risultati del collaudo | Sezione ripetuta o fuori ordine: pulizia e sezione 2 |
| `E11000 ... clienteId_1_data_1` | Indice unique della sezione 7: documento rimasto da una prova |
| Nessun evento nel change stream | Servono due terminali; avviare prima il ciclo |
| La ripresa non stampa nulla | Fermare il ciclo prima di scrivere |

## 17. Laboratorio vs produzione

| | Laboratorio | Produzione |
|---|---|---|
| Strumento | `mongosh` a mano | Driver; `mongosh` per manutenzione |
| Utente | `appuser` + admin per 3 operazioni | Ruolo minimo per applicazione |
| Shard key | 50 valori → 62% / 38% | Molti valori distinti |
| Indici | Creati al volo | Sulle query reali, verificati con `explain` |
| Cancellazioni | Dirette | Conteggio, backup, spesso cancellazione logica |
| Transazioni | Per vederle | Solo dove il modello dei dati non basta |
| Write concern | Provato a mano | `majority` + `wtimeout`, errore gestito |
| Validazione | Alla creazione | `warn` → bonifica → `error` |
| Ricerca | Indice testuale | Motore dedicato |
| Change stream | Ciclo nella shell | Processo dedicato, token durevole |
