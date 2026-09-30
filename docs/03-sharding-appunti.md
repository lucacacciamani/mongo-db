# 03 — Sharding: appunti di laboratorio

> **Diario del laboratorio.** Raccoglie scelte, motivazioni, scoperte e inconvenienti man mano che il laboratorio procede. Da qui verranno ricavate `03-sharding-guida-completa.md` e `03-sharding-guida-rapida.md`.

**Ultimo aggiornamento:** laboratorio **completato e collaudato** (Passi 0–17, TLS a freddo, utente applicativo, backup con TLS). Il cluster resta acceso come ambiente di prova, con backup notturno alle 03:30; sviluppo e replica set 02 spenti. Guide scritte: `03-sharding-guida-completa.md`, `03-sharding-guida-rapida.md`; risorse in `config/03-sharding/`.

---

## 1. Ambiente

| Voce | Valore |
|---|---|
| VM | La stessa delle guide 00–02 (Debian 13, Azure), 2 vCPU, 7,8 GB RAM |
| Swap | Assente all'inizio; aggiunto file di swap da 4 GB (D2) |
| Cartella | `~/mongo-lab/03-sharding` |
| Versione | MongoDB 8.0 (immagine `mongo:8.0`) |
| Altre istanze | MongoDB di sviluppo (`~/mongodb`) e replica set della guida 02 **spenti** durante il laboratorio (D1) |

## 2. Topologia

| Componente | Replica set | Container | Porte |
|---|---|---|---|
| Config server | `cfgrs` | `mongo-cfg1`, `mongo-cfg2`, `mongo-cfg3` | 27201–27203 |
| Shard 1 | `sh1` | `mongo-sh1a`, `mongo-sh1b`, `mongo-sh1c` | 27211–27213 |
| Shard 2 | `sh2` | `mongo-sh2a`, `mongo-sh2b`, `mongo-sh2c` | 27221–27223 |
| Router | — | `mongo-router` | 27200 (unica porta pubblicata) |

## 3. Cronologia

| Passo | Cosa | Esito |
|---|---|---|
| 0 | Spegnimento di sviluppo e replica set, sospensione dei timer di backup, swap da 4 GB | OK: sviluppo fermato in 1,1 s (istanza singola), nodi del replica set in ~16 s (quiesce); 7,3 GB disponibili, `Swap: 4.0Gi` con 0 usati |
| 1 | Cartella, keyFile condiviso, password dell'amministratore | OK: `keyfile` `400` owner 999, `root_password.txt` `600` root, `PRIV_IP` impostato |
| 2 | Compose in quattro parti | OK: file integro nonostante righe mescolate a schermo (§6.3); 10 servizi, 9 volumi, porte del router corrette |
| 3 | Avvio dei 10 container | OK: tutti in esecuzione; memoria a riposo ~108–121 MiB per nodo, 86 MiB il router (~1,2 GB in totale); router in attesa di `cfgrs` con messaggi `FailedToSatisfyReadPreference` e `Sleeping for 2 seconds and retrying` (atteso) |
| 4 | `rs.initiate` di `cfgrs` (con `configsvr: true`), `sh1`, `sh2` con la localhost exception | OK: tre `{ ok: 1 }`; primari `mongo-cfg1`, `mongo-sh1a`, `mongo-sh2a` (il nodo su cui è stato lanciato `rs.initiate`); `db.hello()` funziona senza autenticazione |
| 5 | Admin locali su `sh1`/`sh2` (localhost exception sui primari), admin del cluster via router, funzioni `sh_eval` / `node_eval` | OK: tre `{ ok: 1 }`; router in 8.0.32; `node_eval` sullo shard 1 con l'admin locale: 1 primario e 2 secondari. Il router aveva già registrato `cfgrs` (`Updating the shard registry with confirmed replica set`) |
| 6 | `sh.addShard` di `sh1` e `sh2`, `listShards`, `sh.status()` | OK: `shardAdded` ×2, stato 1; `sh.status()` mostra 2 shard, 1 `mongos` 8.0.32, bilanciatore abilitato e fermo, nessuna collezione distribuita. Verificato anche l'admin del cluster sui config server (salvato lì dal router) |
| 7 | `chunksize` = 1 MB (solo laboratorio) | OK |
| 8 | `labdb.ordini` hashed su `clienteId`, 200.000 documenti | OK: distribuzione 50,5 % / 49,5 % (101.000 / 99.000 documenti, 13,19 / 12,93 MiB); **1 chunk per shard** (§6.8); memoria dopo il caricamento: 2,5 GB usati, 5,3 GB disponibili, **swap 0**; nodi degli shard ~225–239 MiB, config server ~165 MiB, router 117 MiB |
| 9 | `explain` con e senza shard key | OK: `{ clienteId: 42 }` → `SINGLE_SHARD`, 1 shard; `{ importo: { $gt: 990 } }` → `SHARD_MERGE`, 2 shard. Intervallo su chiave hashed `{ $gte: 100, $lt: 110 }` → `SHARD_MERGE`, 2 shard (l'hash disperde valori vicini) |
| 10 | `labdb.eventi` a intervalli su `ts` crescente, 100.000 documenti | Dati nati tutti su `sh2`; il bilanciatore ha già spostato 5 chunk da ~1 MB (1023 KiB) su `sh1`; ultimo chunk (nuovi inserimenti) su `sh2` → shard caldo confermato. `getShardDistribution` somma **142.275** documenti su 100.000 reali: documenti orfani su `sh2` in attesa di cancellazione (§6.10) |
| 10 (verifiche) | Conteggio via router, `rangeDeletions`, query per intervallo su `ts` | Router: 100.000; su `sh2` 5 intervalli in attesa di cancellazione, `orphanCleanupDelaySecs` = 900; intervallo di 1 minuto su `ts` → `SINGLE_SHARD` |
| 11 | Bilanciatore e storico migrazioni | Abilitato, modalità `full`, 91 round; 5 `moveChunk.commit` su `labdb.eventi` in ~6 secondi (07:27:41–47), ~1,4 s ciascuno; poi fermo (§6.11) |
| 12 | Stop del primario di `sh1` (`mongo-sh1a`), conteggio e scrittura via router, stato dello shard | OK: stop in 16,2 s (quiesce, `stop_grace_period`); via router 200.000 documenti e scrittura riuscita; `mongo-sh1b` nuovo primario di `sh1`, `mongo-sh1a` `(not reachable/healthy)`; nodo riacceso |
| 10 (dopo 15 min) | Distribuzione di `eventi` dopo la pulizia degli orfani | Totali tornati a 100.000 (`sh1` 42.275, `sh2` 57.725); i 5 chunk su `sh1` sono diventati **1** (§6.12) |
| — | Riconnessione alla VM: funzioni perse | Salvate in `funzioni-lab.sh`, caricate con `source` (§6.13) |
| 13 | Accesso dal PC attraverso il router: NSG su 27200, `Test-NetConnection`, VS Code con `mongodb://admin:...@<FQDN>:27200/?authSource=admin` (senza `replicaSet`) | OK: porta raggiungibile, VS Code collegato |
| 14 | Backup logico via router con bilanciatore fermo; ripristino in `labdb_ripristino` | OK: archivio da 3,6 MB; ripristinati 300.001 documenti in ~11 s (`ordini` 200.001 compreso quello del Passo 12, `eventi` 100.000); **indici della shard key ripristinati** (`clienteId_hashed`, `ts_1`) ma collezioni **non distribuite**; file di backup nato con permessi `644` (§6.14) |
| 15 | Chiusura: stop del cluster, riaccensione di sviluppo e replica set, timer riattivati, rimozione dello swap | OK: cluster fermato in 17–19 s per container; `mongo` e `mongo-rs1..3` ripartiti; timer 02:30 e 03:00 di nuovo elencati; swap rimosso (`Swap: 0B`), comando `sed` su `/etc/fstab` verificato. La procedura di chiusura e la rimozione dello swap risultano **collaudate** |
| — | Nuova decisione: il cluster diventa l'ambiente di lavoro | Replica set 02 da rispegnere, swap da ricreare, cluster da riaccendere; da decidere il destino dell'istanza di sviluppo (`appdb`) |
| 16 | Ritorno al cluster: stop del replica set 02 e del suo timer, swap ricreato, `docker compose start` del cluster | OK: replica set fermato in ~16 s; swap 4 GB; cluster ripartito dopo uno spegnimento completo, shard con stato 1, dati intatti (200.001 / 100.000) già dopo 30 s; con istanza di sviluppo + cluster: 2,4 GB usati, 5,4 GB disponibili, swap 0 |
| 17 | Spegnimento dell'istanza di sviluppo e del suo timer | OK: `mongo` fermato in 0,8 s; nessun timer MongoDB attivo; sulla VM solo il cluster (5,4 GB disponibili) |
| T1 | Certificato unico per i 10 processi (CA della guida 01), EKU `serverAuth,clientAuth`, SAN con i 10 nomi dei container + `localhost`, `127.0.0.1`, FQDN, IP privato | OK: `server.crt: OK`; firma eseguita due volte per un incolla ripetuto (innocuo: il contatore `ca.srl` avanza di due) |
| T2 | TLS **a freddo**: compose con `requireTLS` su 10 servizi (sed), funzioni con `--tls`, `docker compose up -d` | OK: ricreazione di tutti i container in ~40–47 s; shard con stato 1, dati intatti; router e shard in `requireTLS`; 62 connessioni TLS 1.3 ricevute da `mongo-sh1a`, zero su versioni vecchie; `openssl s_client` sul router → `Verify return code: 0 (ok)`, TLS 1.3; connessione in chiaro rifiutata (`connection ... closed`). Un secondo `up -d` lascia tutto com'è (`Running`) |
| U | Utente applicativo `appuser` via router | OK: `ok: 1`; connessione da VS Code come `appuser` riuscita; come `appuser` `ordini: 200001` e lettura di `config` → `Unauthorized`; sullo shard 1 **0 utenti** in `labdb` (gli utenti creati via router stanno nei config server) |
| B | Backup e ripristino con TLS (`--ssl --sslCAFile`), file scritto con `sudo sh -c "umask 077; cat > ..."` | OK: bilanciatore `false` → `true`; nuovo archivio da 3,6 MB con **`-rw-------`** (correzione di §6.14 verificata); ripristino in `labdb_ripristino`: 200.001 / 100.000, poi eliminato |

## 4. Decisioni e motivazioni

Ogni decisione è descritta con: **nel laboratorio** (cosa facciamo), **perché** (quasi sempre un vincolo del laboratorio: una sola VM, risorse limitate, altre istanze da preservare), **se non lo fai**, **alternative**, **in produzione** (cosa scegliere e cosa valutare in un ambiente reale). Nella guida finale ogni scelta di laboratorio sarà dichiarata come tale, così da non essere copiata in produzione per errore.

### D0 — Topologia completa (10 processi) invece di una ridotta

- **Alternative valutate:** A) cluster ridotto con replica set da un nodo (4 container, ~2 GB); B) cluster completo liberando memoria (scelta); C) cluster completo ingrandendo la VM (costo, riavvio).
- **Perché B:** fedele alla produzione (config server e shard come replica set da tre nodi), senza costi aggiuntivi.
- **Calcolo:** 10 processi con cache 256 MB → ~4–5 GB reali; con sviluppo (fino a ~3,5 GB) e replica set 02 (fino a 3 GB) accesi non ci sarebbe spazio.
- **Vincolo del laboratorio:** tutti i 10 processi sulla stessa VM, con cache e memoria limitate artificialmente.
- **In produzione:** ogni processo `mongod` su un server dedicato. Scelte da fare:
  - **config server:** 3 VM piccole (poca RAM e disco: contengono solo metadati), in zone di disponibilità diverse;
  - **shard:** 3 VM per shard, dimensionate per i dati (RAM sufficiente per il *working set*, disco veloce XFS), in zone diverse;
  - **numero di shard:** partire da 2 solo se i volumi lo giustificano; ogni shard in più aggiunge 3 server. Lo sharding si adotta quando un singolo replica set, verticalmente dimensionato al massimo ragionevole, non basta più;
  - **router `mongos`:** tipicamente uno per ogni server applicativo (stessa macchina o stesso container dell'applicazione), oppure un gruppo dedicato dietro bilanciamento; sono processi senza stato e leggeri;
  - valutare un servizio gestito (MongoDB Atlas) se il costo operativo di ~10 server è eccessivo.

### D1 — Spegnere (non eliminare) il MongoDB di sviluppo e il replica set 02

- **Cosa:** `docker compose stop` nelle due cartelle; `systemctl disable --now` sui timer `mongo-backup.timer` e `mongo-rs-backup.timer`.
- **Perché spegnere e non eliminare:** dati, utenti, certificati e configurazione restano; si riaccende con un comando. Lo sviluppo contiene i dati dell'applicazione ed è l'installazione di riferimento delle guide 00–01.
- **Conseguenze:** applicazione e VS Code non raggiungono il database di sviluppo; i backup notturni fallirebbero senza container → timer sospesi; con `restart: unless-stopped` i container fermati a mano restano spenti anche dopo un riavvio della VM.
- **Ripristino a fine laboratorio:** `sudo docker compose start` nelle due cartelle, `sudo systemctl enable --now` sui due timer.
- **Vincolo del laboratorio:** VM condivisa con altre istanze; si sacrifica temporaneamente lo sviluppo.
- **In produzione:** un cluster con sharding non condivide mai i server con altri database; nessuna istanza va spenta per fargli spazio. Se una VM di prova ospita più ambienti, si pianificano finestre e si documenta chi è impattato.

### D2 — Swap da 4 GB come rete di sicurezza

- **Concetto da spiegare nella guida:** senza swap, a RAM esaurita interviene l'**OOM killer**, che termina d'autorità un processo (probabilmente un nodo MongoDB, come un'interruzione di corrente). Con lo swap Linux sposta su disco le parti di memoria meno usate: il sistema rallenta ma nessun processo viene ucciso.
- **Non è RAM in più:** uso continuativo dello swap = prestazioni crollate. In produzione si dimensiona la RAM per non usarlo; MongoDB raccomanda uno swap piccolo come protezione dall'OOM killer.
- **Come:** `fallocate -l 4G /swapfile` → `chmod 600` (può contenere dati in memoria, anche password) → `mkswap` → `swapon` → riga in `/etc/fstab` per l'avvio. Verifica: `free -h`, `swapon --show`.
- **Perché 4 GB e sul disco di sistema:** sufficienti per i picchi (caricamento dati, bilanciamento dei chunk); 4 dei 58 GB liberi. Alternativa Azure: disco temporaneo (`/mnt`), veloce ma cancellato a spostamento/deallocazione della VM, configurazione più articolata.
- **Rimozione:** `swapoff /swapfile`, togliere la riga da `/etc/fstab`, `rm /swapfile`.
- **Vincolo del laboratorio:** VM sottodimensionata per 10 processi; lo swap evita che un picco faccia terminare un nodo.
- **In produzione:** la RAM di ogni server si dimensiona sul *working set* (dati e indici usati di frequente) più margine; lo swap resta piccolo, solo protezione. Si monitora l'uso dello swap: se cresce, è un segnale di sottodimensionamento, non una soluzione. Su Azure si valuta il disco temporaneo della VM per lo swap, configurato tramite cloud-init.
- **Da aggiungere alla legenda dei comandi:** `fallocate`, `mkswap`, `swapon`, `swapoff`.

### D3 — Membri registrati con i nomi dei container

- **Perché (differenza rispetto alla guida 02):** i client parlano solo con il `mongos`; è il router a contattare config server e shard nella rete Docker. Il problema dei nomi dei membri non raggiungibili dall'esterno non si pone.
- **Vincolo del laboratorio:** tutti i nodi nella stessa rete Docker, dove i nomi dei container sono risolti automaticamente.
- **In produzione:** i nodi hanno comunque **nomi DNS interni** stabili (non IP), scelti prima dell'inizializzazione, perché i config server memorizzano gli indirizzi degli shard e i membri dei replica set si registrano con quei nomi. Le applicazioni vedono solo i router.

### D4 — Una sola porta pubblicata: il router

- **Perché:** config server e shard non devono essere raggiungibili dalle applicazioni.
- **Nel laboratorio:** router pubblicato su `127.0.0.1` e, per l'accesso dal PC, sull'IP privato con regola NSG limitata a un IP (come nelle guide precedenti).
- **In produzione:** config server e shard in una subnet dedicata, raggiungibile solo dai router e dagli strumenti di amministrazione; router raggiungibili solo dagli application server, nella rete privata; nessuna porta su internet.

### D5 — Utenti creati attraverso il `mongos` con la localhost exception

- **Cosa:** nessun `MONGO_INITDB_*`; il primo utente si crea collegandosi al `mongos` dalla stessa macchina finché non esiste alcun utente (*localhost exception*). Gli utenti del cluster sono salvati nei config server.
- **In più:** un amministratore locale su ogni shard (sul suo primario), per la manutenzione diretta dei nodi, come raccomanda la documentazione MongoDB.
- **Password:** non montata nei container; passata al momento della creazione degli utenti.
- **In produzione:** stesso schema (utenti del cluster via router, amministratori locali sugli shard per la manutenzione), con utenti applicativi dedicati e ruoli minimi, password in un gestore di segreti; la localhost exception si usa solo per il primo utente e si chiude da sola.

### D7 — Il cluster resta acceso come ambiente di prova, tutto il resto spento

- **Cosa:** a fine laboratorio il cluster resta acceso come ambiente di prova. L'istanza di sviluppo resta **separata** (i dati di `appdb` non vengono migrati) ma viene **spenta**, con il suo timer di backup sospeso; anche il replica set 02 resta spento.
- **Perché:** separare i dati dell'applicazione dall'ambiente di sperimentazione, e dedicare le risorse della VM al cluster. Con sviluppo e cluster insieme la memoria bastava (2,4 GB usati, 5,4 disponibili, swap 0), ma la scelta è stata di tenere acceso solo il cluster.
- **Conseguenze:** applicazione e connessioni VS Code verso lo sviluppo non disponibili; nessun backup notturno finché le istanze sono spente (e nessun dato nuovo da salvare).
- **Per riaccendere lo sviluppo:** `cd ~/mongodb && sudo docker compose start` e `sudo systemctl enable --now mongo-backup.timer`.
- **In produzione:** ambienti separati su infrastrutture separate; un cluster di prova non condivide la macchina con dati reali.

### D8 — TLS attivato a freddo

- **Nel laboratorio:** cluster fermato e riacceso (`docker compose up -d` dopo aver aggiornato il compose direttamente a `requireTLS`), interruzione di circa un minuto.
- **Perché:** l'unico client è l'autore del laboratorio; la migrazione a caldo richiederebbe due giri di rotazione su 10 processi. Certificato unico perché tutti i processi stanno sulla stessa macchina.
- **In produzione:** migrazione a caldo come nella guida 02 (`allowTLS` → `preferTLS` → `requireTLS`), un replica set alla volta (config server, poi ogni shard) e i router, con più router dietro un bilanciamento per non interrompere le applicazioni; un certificato per server, con il suo nome DNS, `serverAuth` e `clientAuth`.

### D6 — Un keyFile condiviso da tutti i processi

- **Perché:** config server, shard e router devono riconoscersi tra loro (autenticazione interna), esattamente come i membri di un replica set.
- **In produzione:** keyFile distribuito in modo sicuro su tutti i server, oppure (preferibile su cluster grandi) certificati x.509 per l'autenticazione dei membri, gestiti dalla PKI aziendale.

## 5. Laboratorio vs produzione (in costruzione)

| Aspetto | Laboratorio | Produzione |
|---|---|---|
| Server | 10 container su una VM | ~10 VM (3 config server piccoli, 3 per shard) + router sui server applicativi |
| Zone di disponibilità | Nessuna (una VM) | Membri di ogni replica set in zone diverse |
| Memoria | Cache 256 MB, limiti per container, swap 4 GB come rete di sicurezza | RAM sul working set, swap piccolo, monitoraggio |
| Altre istanze | Spente per liberare risorse | Server dedicati, nessuna condivisione |
| Nomi | Nomi dei container Docker | Nomi DNS interni stabili |
| Esposizione | Solo il router, IP limitato via NSG | Solo i router, solo in rete privata |
| Utenti | Localhost exception sul router; admin locali sugli shard | Stesso schema, segreti in un gestore dedicato |
| Autenticazione interna | keyFile condiviso | keyFile o x.509 |
| Cifratura | TLS obbligatorio su tutti i 10 processi, attivato a freddo, certificato unico | TLS obbligatorio, attivato a rotazione, un certificato per server |
| Costo operativo | Nullo | Elevato: valutare se lo sharding serve davvero, o un servizio gestito |

## 6. Scoperte e inconvenienti

### 6.1 `swapon: command not found`

- **Sintomo:** `sudo swapon /swapfile` funziona, ma `swapon --show` senza `sudo` dà `command not found`.
- **Causa:** su Debian i comandi di amministrazione (`swapon`, `mkswap`, …) stanno in `/usr/sbin`, fuori dal `PATH` degli utenti normali; `sudo` usa un percorso che lo include.
- **Soluzione:** `sudo swapon --show`. Da riportare anche nella legenda dei comandi.

### 6.3 Incolla della Parte A: righe mescolate, ma file integro

- **Sintomo:** in tre tentativi, la fine della Parte A appariva come `EOF   - ./keyfile:/etc/mongo/keyfile:ro`, facendo pensare a righe perse (volumi di `mongo-cfg3`).
- **Verifica:** `grep -n -A6 "container_name: mongo-cfg3"` ha mostrato la sezione `volumes` completa: il difetto era solo di **visualizzazione** del terminale.
- **Differenza con la guida 02:** lì il file era davvero incompleto. Quindi né l'aspetto dell'output né `compose valido` sono affidabili: serve un controllo sul contenuto.
- **Controllo aggiunto alla procedura:** `docker compose config | grep -c "target: /etc/mongo/keyfile"` = 10 (verifica ogni servizio). Il conteggio dei volumi non basta, perché i volumi sono dichiarati in fondo al file.

### 6.4 Il router prima dell'inizializzazione dei config server

- Il router parte comunque e **resta in attesa**: nei log `FailedToSatisfyReadPreference ... for set cfgrs` e `Error loading global settings from config server. Sleeping for 2 seconds and retrying`. Non si riavvia e non va in errore: riprova ogni 2 secondi finché `cfgrs` non ha un primario. Nessun bisogno di avviarlo dopo gli altri.

### 6.5 Memoria a riposo

- Nodi appena avviati e vuoti: ~110 MiB ciascuno (limite 640 MiB), router 86 MiB (limite 384 MiB). Totale ~1,2 GB: ampio margine; il dato interessante sarà durante il caricamento (Passo 8).

### 6.6 Due tipi di utenti

- **Utenti del cluster:** creati attraverso il router, salvati nei config server; valgono per router e config server (verificato: login come `admin` su `mongo-cfg1` senza averlo mai creato lì). Le applicazioni usano questi, sempre attraverso il router.
- **Utenti locali degli shard:** creati direttamente sul primario di ogni shard; valgono solo per i nodi di quello shard; servono alla manutenzione diretta.

### 6.7 Lettura di `sh.status()`

- `shards`: shard registrati con i loro membri; `active mongoses`: router attivi e versione; `balancer`: abilitato / in esecuzione / esiti; `shardedDataDistribution`: dati per shard delle collezioni distribuite (vuoto finché non ne creiamo); `databases`: database e shard primario di ciascuno.
- `autosplit: yes` è mostrato per compatibilità: nelle versioni recenti la divisione dei chunk è gestita dal bilanciatore.

### 6.8 Un solo chunk per shard, nonostante `chunksize` = 1 MB

- **Osservato:** dopo 200.000 documenti (~26 MiB), la collezione hashed ha **2 chunk in tutto**, uno per shard, ciascuno di ~13 MiB, cioè molto più grandi di 1 MB.
- **Spiegazione:** nelle versioni recenti (dalla 6.x) MongoDB non divide più i chunk automaticamente man mano che crescono (*auto-split* non più attivo, anche se `sh.status()` mostra `autosplit: yes`). Una collezione hashed vuota nasce già pre-divisa, un intervallo per shard; il bilanciatore ragiona sulla **quantità di dati** per shard, non sul numero di chunk, e divide gli intervalli solo quando deve spostare dati. Qui i dati sono già bilanciati, quindi nessuna divisione né migrazione.
- **Per la guida:** "chunk" ≈ intervallo di valori della shard key assegnato a uno shard; `chunksize` è il riferimento del bilanciatore per decidere quando e quanto spostare, non una dimensione massima imposta ai chunk.

### 6.9 Memoria sotto carico

- Dopo il caricamento: 2,5 GB usati su 7,8, swap mai toccato. Le scelte di laboratorio (cache 256 MB, `mem_limit`) lasciano un margine ampio; lo swap resta una rete di sicurezza non utilizzata.

### 6.10 Documenti orfani dopo le migrazioni (142.275 su 100.000)

- **Osservato:** subito dopo il caricamento di `eventi`, `getShardDistribution` mostra `sh1` con 42.275 documenti in 5 chunk (appena migrati) e `sh2` ancora con **100.000**: totale 142.275, contro i 100.000 reali.
- **Spiegazione:** quando il bilanciatore sposta un intervallo, lo shard di origine **non cancella subito** i documenti copiati: li cancella in modo asincrono, dopo un ritardo di sicurezza (`orphanCleanupDelaySecs`, per impostazione predefinita 900 s = 15 minuti), per non disturbare eventuali letture ancora in corso. Nel frattempo sono documenti **orfani**: presenti fisicamente ma non più di competenza di quello shard.
- **Chi li vede:** le statistiche per shard (`getShardDistribution`) li contano; le query attraverso il router li **filtrano** (`countDocuments` = 100.000).
- **Per la guida:** non allarmarsi per totali che non tornano subito dopo una migrazione; verificare con `countDocuments` via router e con `config.rangeDeletions` sullo shard di origine.

### 6.11 Perché il bilanciatore si è fermato dopo 5 migrazioni

- Dati reali dopo le migrazioni: `sh1` 42.275 documenti, `sh2` 57.725 (al netto degli orfani). La collezione è considerata bilanciata quando la differenza di dati tra gli shard è sotto circa **tre volte la dimensione dei chunk** (qui 3 × 1 MB): raggiunta questa condizione il bilanciatore smette, pur restando attivo (`inBalancerRound: false`, i round continuano a contare).
- Le migrazioni sono veloci (~1,4 s per 1 MB); in produzione, con chunk da 128 MB e carico reale, durano molto di più e consumano risorse: per questo si possono limitare a finestre orarie (*balancing window*).
- **Shard caldo:** lo spostamento riequilibra i dati **già scritti**, ma le nuove scritture su una chiave crescente continuano a finire tutte sull'ultimo chunk.

### 6.12 I chunk si riuniscono da soli

- **Osservato:** dopo la pulizia degli orfani, i 5 chunk migrati su `sh1` risultano **1 solo**, e `sh2` ha 1 chunk: 2 in tutto.
- **Spiegazione:** le versioni recenti di MongoDB (dalla 7.0) **riuniscono automaticamente** gli intervalli contigui che si trovano sullo stesso shard (*automerger*), per tenere basso il numero di chunk. Il bilanciatore li divide quando deve spostare dati, l'automerger li riunisce dopo.
- **Per la guida:** il numero di chunk varia nel tempo e conta poco; ciò che conta è la quantità di dati per shard.
- Le dimensioni in MiB di `getShardDistribution` sono **stime** basate sulle statistiche di archiviazione: possono non corrispondere esattamente a documenti × dimensione media.

### 6.13 Funzioni di comodo e riconnessioni

- Riconnettendosi alla VM, `sh_eval` e `node_eval` spariscono (`command not found`), come `rs_eval` nella guida 02.
- **Soluzione adottata:** salvarle in `~/mongo-lab/03-sharding/funzioni-lab.sh` e ricaricarle con `source` a ogni sessione. Il file non contiene la password (letta ogni volta da `root_password.txt`).
- **Da riportare anche nella guida 02** per `rs_eval`, e nella legenda (`source`).

### 6.14 Backup attraverso il router

- **Collezioni ripristinate non distribuite:** `config.collections` non contiene `labdb_ripristino.ordini`: `mongorestore` attraverso il router ricrea le collezioni tutte sullo shard primario del database. Gli **indici** della shard key vengono però ripristinati: la collezione si può ridistribuire dopo con `sh.shardCollection`, oppure la si crea e distribuisce **prima** del ripristino.
- **Permessi del file:** l'archivio è nato `-rw-r--r--` perché lo scrive `sudo tee` sull'host, con la `umask` predefinita (022): l'`umask 077` dentro il container non vale per il file sull'host. La cartella `700` lo protegge comunque, ma nella guida va scritto con `sudo sh -c 'umask 077; cat > "$F"'` oppure seguito da `sudo chmod 600 "$F"`.
- **Tempi:** 300.001 documenti ripristinati in ~11 s.
- **Limite:** con il bilanciatore fermo non si spostano chunk, ma il backup logico non è comunque una fotografia coerente a un istante se l'applicazione scrive durante il dump (niente `--oplog` attraverso il router). In produzione: snapshot coordinati o servizio gestito.

### 6.15 Funzioni caricate automaticamente

- Per evitare di ridefinirle a ogni riconnessione: `echo 'source ~/mongo-lab/03-sharding/funzioni-lab.sh' >> ~/.bashrc`. Allo smantellamento del laboratorio **togliere la riga**, altrimenti ogni accesso segnala il file mancante.

### 6.2 Tempi di spegnimento

- Istanza singola di sviluppo: 1,1 s. Nodi del replica set: ~16 s (fase di quiesce, coperta da `stop_grace_period`). Conferma pratica della differenza documentata nella guida 02.

## 7. Da fare

- [ ] Completare Passi 0–1 e verificare memoria e swap.
- [ ] Compose del cluster.
- [ ] Inizializzazione dei tre replica set, avvio del router, registrazione degli shard.
- [ ] Utenti (cluster e locali agli shard).
- [ ] Shard key: a intervalli e hashed; dati di prova; distribuzione dei chunk; bilanciatore.
- [ ] Query mirate e scatter-gather (`explain`).
- [ ] Accesso dal PC attraverso il router (porta 27200).
- [ ] Backup di un cluster con sharding (differenze rispetto al replica set).
- [ ] Eventuale TLS.
- [x] Riaccensione di sviluppo e replica set 02 a fine laboratorio: collaudata (Passo 15).
- [x] Decisione sull'istanza di sviluppo: **resta separata** (niente migrazione di `appdb`) e viene **spenta** con il suo timer; il cluster resta l'unico ambiente acceso, come ambiente di prova. Replica set 02 spento, timer sospeso.
- [x] TLS sul cluster: fatto a freddo (T1–T2).
- [x] VS Code collegato al router in TLS (`tls=true&tlsCAFile=...`, FQDN presente nel SAN).
- [x] Utente `appuser` (`readWrite` su `labdb`) creato attraverso il router; connessione da VS Code come `appuser` in TLS riuscita (stringa con `/labdb?authSource=labdb&tls=true&tlsCAFile=...`).
- [x] Backup e ripristino aggiornati con TLS e permessi corretti (Passo B). Backup automatico con timer: **non attivato** (ambiente di prova; backup manuale documentato).
- [x] Backup schedulato: script `mongo-sh-backup.sh` (bilanciatore fermato e **sempre** riattivato con `trap ... EXIT`, verificato anche in simulazione di errore; password via stdin anche per `mongosh`; `--dumpDbUsersAndRoles`), timer alle 03:30 UTC; prova manuale, via systemd e ripristino in `labdb_ripristino` riusciti (300.001 documenti). Output di `sh.stopBalancer()` silenziato. Ripristino degli utenti non collaudato (🧪: richiede `--restoreDbUsersAndRoles` nello stesso database).
- [x] Stesura delle guide 03, risorse in `config/03-sharding/`, aggiornamento della guida 02 e della legenda.
- [ ] Aggiornare la legenda dei comandi (swap).
