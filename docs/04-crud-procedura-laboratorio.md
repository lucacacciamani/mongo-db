# 04 — CRUD con mongosh: procedura di laboratorio (bozza da collaudare)

> **Bozza di lavoro.** Questa procedura serve a collaudare sul cluster della guida 03 tutti i comandi che finiranno nelle guide `04-crud-guida-completa.md` e `04-crud-guida-rapida.md`. Esegui i blocchi in ordine (anche in giorni diversi), confronta con i ✅ e **incolla l'output dei passi segnati con 📋** (togli password, FQDN e IP). Dopo il collaudo questo file viene eliminato.

**Prerequisiti:** cluster della guida 03 completo, **con TLS**, con l'utente `appuser` (Parte 15 della 03) e il database `labdb` con `ordini` ed `eventi`.

**I dati di esempio sono deterministici:** ogni esecuzione di `dati-crud.js` produce gli stessi documenti, quindi i numeri dei ✅ devono coincidere esattamente. Se un numero è diverso, segnalalo: è proprio ciò che il collaudo deve scoprire.

**Due modi di eseguire i comandi:**

- i blocchi `js` vanno incollati **dentro la shell interattiva** aperta con `app_shell` (prompt `labdb>`), come `appuser`; ogni riga è un comando;
- i blocchi `bash` vanno eseguiti **sulla VM**, fuori dalla shell (`app_eval`, `sh_eval`, `app_export`…).

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

