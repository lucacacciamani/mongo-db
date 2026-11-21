# MongoDB su Debian 13 con Docker — Guida completa passo passo

**Per chi è questa guida:** per chi deve installare MongoDB su una macchina virtuale Linux in Azure e non ha molta esperienza con Linux, Docker o MongoDB. Ogni passaggio spiega **cosa fare**, **cosa fa il comando** e **cosa devi vedere** se tutto è andato bene.

**Cosa otterrai alla fine:**

- MongoDB 8.0 funzionante, protetto da password, che si riavvia da solo;
- un utente dedicato per la tua applicazione;
- backup automatici ogni notte, con conservazione di giorni, settimane e mesi;
- la possibilità di collegarti al database dal tuo PC di sviluppo;
- il sistema operativo che si aggiorna da solo con le patch di sicurezza.

**Tempo stimato:** 1–2 ore, andando con calma.

> 📖 **Comandi e simboli** (`sudo`, `chmod`, `|`, `<< EOF`, `docker compose`…): la [legenda dei comandi](legenda-comandi-linux.md) spiega tutto ciò che compare in questa guida.

---

## Indice

- [Parte 0 — Concetti di base (leggila, anche se hai fretta)](#parte-0--concetti-di-base-leggila-anche-se-hai-fretta)
- [Parte 1 — Come usare questa guida](#parte-1--come-usare-questa-guida)
- [Parte 2 — Collegarsi alla macchina virtuale](#parte-2--collegarsi-alla-macchina-virtuale)
- [Parte 3 — Controlli preliminari](#parte-3--controlli-preliminari)
- [Parte 4 — Installare Docker](#parte-4--installare-docker)
- [Parte 5 — Preparare il sistema per MongoDB](#parte-5--preparare-il-sistema-per-mongodb)
- [Parte 6 — Configurare MongoDB](#parte-6--configurare-mongodb)
- [Parte 7 — Avviare MongoDB e verificare che funzioni](#parte-7--avviare-mongodb-e-verificare-che-funzioni)
- [Parte 8 — Creare l'utente per la tua applicazione](#parte-8--creare-lutente-per-la-tua-applicazione)
- [Parte 9 — Backup automatici](#parte-9--backup-automatici)
- [Parte 10 — Ripristinare un backup](#parte-10--ripristinare-un-backup)
- [Parte 11 — Collegarsi dal tuo PC di sviluppo](#parte-11--collegarsi-dal-tuo-pc-di-sviluppo)
- [Parte 12 — Gestire lo spazio occupato dai log](#parte-12--gestire-lo-spazio-occupato-dai-log)
- [Parte 13 — Rendere sicuro il sistema](#parte-13--rendere-sicuro-il-sistema)
- [Parte 14 — Uso quotidiano e manutenzione](#parte-14--uso-quotidiano-e-manutenzione)
- [Parte 15 — Quando qualcosa va storto](#parte-15--quando-qualcosa-va-storto)
- [Parte 16 — Prima di andare in produzione](#parte-16--prima-di-andare-in-produzione)
- [Appendice A — Dove si trova ogni cosa](#appendice-a--dove-si-trova-ogni-cosa)
- [Appendice B — Promemoria dei comandi](#appendice-b--promemoria-dei-comandi)
- [Le 7 regole d'oro](#le-7-regole-doro)

---

## Parte 0 — Concetti di base (leggila, anche se hai fretta)

Capire queste poche parole ti eviterà la maggior parte degli errori.

**Macchina virtuale (VM).** Un computer "finto" che gira nei data center di Microsoft Azure. Si comporta come un vero server Linux: ci entri da remoto e lanci comandi. In questa guida la VM si chiama `mongo-vm`.

**Terminale.** La finestra dove scrivi comandi testuali invece di cliccare. Sul tuo PC Windows è *PowerShell* o *Terminale Windows*; sulla VM è la *shell* Linux (chiamata *bash*).

**SSH.** Il sistema con cui ti colleghi al terminale della VM dal tuo PC. Tutto quello che scrivi dopo esserti collegato viene eseguito **sulla VM**, non sul tuo computer.

**Prompt.** La scritta che compare prima del cursore, per esempio:

```
azureuser@mongo-vm:~/mongodb$
```

Ti dice **chi sei** (`azureuser`), **dove sei** (`mongo-vm`, cioè la VM) e **in quale cartella** (`~/mongodb`, dove `~` significa "la tua cartella personale"). Guardalo sempre: è il modo più semplice per capire se stai lavorando sulla VM o sul tuo PC.

**sudo.** Messo davanti a un comando, lo esegue con i permessi di amministratore (come "Esegui come amministratore" in Windows). La prima volta può chiederti la password del tuo utente.

**apt.** Il "negozio di app" di Debian: installa, aggiorna e rimuove programmi.

**MongoDB.** Il database che vogliamo installare. Salva i dati come *documenti* (simili a JSON), raggruppati in *collezioni*, raggruppate a loro volta in *database*.

**mongosh.** La "shell" di MongoDB: un terminale dove scrivi comandi rivolti al database.

**Docker.** Un programma che fa girare applicazioni dentro scatole isolate, chiamate *container*. È come avere MongoDB "già confezionato" con tutto quello che gli serve, senza doverlo installare pezzo per pezzo nel sistema.

- **Immagine:** la "confezione" scaricata da internet (qui `mongo:8.0`). È un modello, non si modifica.
- **Container:** l'immagine in esecuzione. Il nostro container si chiama `mongo`.
- **Volume:** lo spazio su disco dove il container salva i dati in modo permanente. Se il container viene cancellato e ricreato, **i dati nel volume restano**. Il nostro volume si chiama `mongo-data`.
- **Docker Compose:** un file di testo (`docker-compose.yml`) che descrive come deve essere avviato il container: quale immagine, quali porte, quali impostazioni. Invece di ricordare comandi lunghissimi, scrivi tutto una volta nel file.

**Porta.** Un "numero di sportello" su cui un programma aspetta connessioni. MongoDB usa la porta **27017**, SSH la porta **22**.

**127.0.0.1 (localhost).** Un indirizzo speciale che significa "questo stesso computer". Un servizio in ascolto su `127.0.0.1` è raggiungibile **solo** dalla macchina su cui gira, non dall'esterno.

**NSG (Network Security Group).** Il firewall di Azure: decide quali connessioni da internet possono raggiungere la VM. Si configura dal portale Azure.

**Perché Docker e non l'installazione "classica"?** MongoDB non pubblica ancora pacchetti ufficiali per Debian 13. Con Docker il problema non esiste, perché l'immagine contiene già tutto quello che serve. In più, aggiornare o rimuovere MongoDB diventa molto più semplice.

> **Se hai una vecchia guida** con comandi come `apt-key add`, `buster/mongodb-org/5.0` o `mongodb-org-shell`: non usarla. `apt-key` su Debian 13 non esiste più, MongoDB 5.0 non riceve più aggiornamenti di sicurezza e la vecchia shell `mongo` è stata sostituita da `mongosh`.

---

### Il quadro d'insieme

Ecco come si collegano tra loro i pezzi che installeremo (il diagramma è disegnato direttamente da GitHub):

```mermaid
flowchart LR
    PC["Il tuo PC<br/>PowerShell, VS Code"]
    subgraph AZ["Azure"]
        NSG["NSG<br/>firewall di Azure"]
        subgraph VM["VM Debian 13"]
            DK["Docker"]
            MG["Container mongo<br/>MongoDB 8.0"]
            VOL[("Volume mongo-data<br/>i dati")]
            TM["Timer systemd<br/>02:30 UTC"]
            BK[("/var/backups/mongodb")]
        end
    end
    PC -- "SSH, porta 22" --> NSG
    PC -. "27017: tunnel SSH<br/>o accesso diretto" .-> NSG
    NSG --> VM
    DK --> MG
    MG --- VOL
    TM -- "mongo-backup.sh" --> MG
    MG -- "mongodump" --> BK
```

---

## Parte 1 — Come usare questa guida

### 1.1 I blocchi di comandi

I comandi da eseguire sono in riquadri come questo:

```bash
sudo apt-get update
```

Copia il contenuto del riquadro e incollalo nel terminale, poi premi **Invio**.

**Come incollare nel terminale:**

- in PowerShell / Terminale Windows: **tasto destro del mouse** oppure **Ctrl+V**;
- nei terminali Linux: **Ctrl+Shift+V** (il semplice Ctrl+V di solito non funziona).

Se un riquadro contiene più righe, puoi incollarle tutte insieme: vengono eseguite una dopo l'altra.

### 1.2 I blocchi che creano file (molto importante)

Molti riquadri hanno questa forma:

```bash
sudo tee /percorso/del/file > /dev/null << 'EOF'
...contenuto del file...
EOF
```

Significa: "crea il file con questo contenuto". Il contenuto è tutto ciò che sta tra la prima riga e la parola `EOF` finale.

**Devi incollare il blocco intero, dalla prima all'ultima riga, compreso `EOF`.** Mentre incolli, il terminale mostra un simbolo `>` all'inizio di ogni riga: è normale, significa che sta ricevendo il contenuto del file. Quando arriva alla riga `EOF`, il file viene scritto e torna il prompt normale.

L'errore più comune è copiare solo una parte del blocco: il file non viene creato e i comandi successivi danno errori tipo `No such file or directory`.

### 1.3 I segnaposto

Le parti tra `< >`, come `<IP_PUBBLICO_VM>`, sono **segnaposto**: vanno sostituite con il valore reale, **togliendo anche i simboli `<` e `>`**.

Esempio: `ssh azureuser@<IP_PUBBLICO_VM>` diventa `ssh azureuser@20.123.45.67`.

| Segnaposto | Cosa inserire | Dove trovarlo |
|---|---|---|
| `<IP_PUBBLICO_VM>` | Indirizzo pubblico della VM | Portale Azure → la tua VM → *Panoramica* → *Indirizzo IP pubblico* |
| `<IP_PRIVATO_VM>` | Indirizzo interno della VM (es. `10.0.0.4`) | Comando nella Parte 11.2 |
| `<IL_TUO_IP>` | Indirizzo pubblico del tuo PC/ufficio | Cerca "what is my ip" nel browser del tuo PC |

In questa guida l'utente della VM è `azureuser`: se il tuo è diverso, sostituiscilo.

### 1.4 "Non è successo niente": è normale

In Linux, **un comando che va a buon fine spesso non stampa nulla**. Se premi Invio e ricompare subito il prompt senza messaggi, di solito vuol dire che è andato tutto bene. Gli errori, invece, vengono sempre segnalati con un messaggio.

### 1.5 Tasti utili

| Tasto | Effetto |
|---|---|
| **Ctrl+C** | Interrompe il comando in corso (per esempio per uscire dalla visualizzazione dei log) |
| **Freccia su** | Richiama i comandi precedenti |
| **Tab** | Completa automaticamente nomi di file e cartelle |
| `clear` + Invio | Pulisce lo schermo |

### 1.6 Le password e la chat

Durante la guida verranno generate delle password casuali. **Non copiarle mai in chat, email, ticket o documenti**, e quando chiedi aiuto incollando l'output del terminale controlla che non contenga una password. Se succede per errore, cambiala subito (le istruzioni sono nella guida).

---

## Parte 2 — Collegarsi alla macchina virtuale

> 📍 **Dove:** sul tuo PC.

### 2.1 Aprire il terminale sul PC

Su Windows 10/11 premi il tasto Windows, scrivi **PowerShell** e aprilo. Il comando `ssh` è già incluso in Windows, non serve installare niente.

### 2.2 Collegarsi

Quando hai creato la VM su Azure hai scelto un metodo di accesso: di solito una **chiave SSH** (un file `.pem` scaricato al momento della creazione).

```powershell
ssh -i C:\percorso\della\chiave.pem azureuser@<IP_PUBBLICO_VM>
```

- La prima volta ti chiede di confermare l'identità del server: scrivi `yes` e premi Invio.
- Se tutto va bene, il prompt cambia in `azureuser@mongo-vm:~$`: **ora sei sulla VM**.

Se il collegamento non riesce, vedi la [Parte 15](#parte-15--quando-qualcosa-va-storto), voce "Non riesco a collegarmi con SSH".

### 2.3 Uscire dalla VM

Scrivi `exit` e premi Invio: torni al terminale del tuo PC.

---

## Parte 3 — Controlli preliminari

> 📍 **Dove:** sulla VM (prompt `azureuser@mongo-vm`).

### 3.1 La CPU supporta MongoDB 8.0?

MongoDB 8.0 richiede una funzione del processore chiamata AVX.

```bash
grep -o avx /proc/cpuinfo | head -1
```

✅ **Devi vedere:** `avx`
❌ **Se non compare nulla:** la VM non è adatta a MongoDB 8.0; scegli un'altra taglia di VM su Azure.

### 3.2 Aggiornare l'elenco dei programmi disponibili

```bash
sudo apt-get update
```

**Cosa fa:** scarica l'elenco aggiornato dei programmi installabili. Non installa nulla.

✅ **Devi vedere:** varie righe `Get:` o `Hit:` e alla fine `Reading package lists... Done`.

---

## Parte 4 — Installare Docker

> 📍 **Dove:** sulla VM.

### 4.1 Rimuovere eventuali versioni non ufficiali

Debian offre una sua versione di Docker che può entrare in conflitto con quella ufficiale. Per sicurezza la rimuoviamo:

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y $pkg
done
```

✅ **Messaggi come `Unable to locate package` o `is not installed` sono normali:** significano che non c'era niente da rimuovere.

### 4.2 Aggiungere la "fonte" ufficiale di Docker

Diciamo ad apt di scaricare Docker direttamente dal sito di Docker, verificandone l'autenticità con una chiave di firma.

```bash
sudo apt-get install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

**Cosa fa, riga per riga:**

1. installa due strumenti necessari (certificati e `curl`, per scaricare file);
2. crea la cartella dove tenere le chiavi di firma;
3. scarica la chiave di firma di Docker;
4. la rende leggibile;
5. aggiunge il repository di Docker all'elenco delle fonti di apt (il pezzo `$(...)` inserisce automaticamente il nome della tua versione di Debian, `trixie`).

✅ **Devi vedere:** nessun errore. Gli ultimi comandi non stampano nulla.

### 4.3 Installare Docker

```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

**Cosa fa:** aggiorna l'elenco (ora comprende Docker), installa Docker e il plugin Compose, poi avvia Docker e lo imposta per partire automaticamente a ogni accensione della VM.

L'installazione scarica circa 120 MB e richiede un minuto circa.

### 4.4 Verificare che Docker funzioni

```bash
sudo docker run --rm hello-world
```

✅ **Devi vedere:** tra le varie righe, il messaggio **`Hello from Docker!`**.

> **Una nota su `sudo`:** in questa guida tutti i comandi Docker usano `sudo`. Esiste un modo per evitarlo (`sudo usermod -aG docker $USER`), ma equivale a dare al tuo utente pieni poteri di amministratore: meglio lasciar perdere finché non hai chiaro il motivo.

---

## Parte 5 — Preparare il sistema per MongoDB

> 📍 **Dove:** sulla VM.

MongoDB 8.0 funziona meglio con una particolare configurazione della memoria del sistema (le *Transparent Huge Pages*). Il container usa il sistema della VM, quindi l'impostazione va fatta sulla VM.

```bash
sudo tee /etc/tmpfiles.d/mongodb-thp.conf > /dev/null << 'EOF'
w /sys/kernel/mm/transparent_hugepage/enabled - - - - always
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
w /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 0
EOF
sudo systemd-tmpfiles --create /etc/tmpfiles.d/mongodb-thp.conf
```

**Cosa fa:** crea un file di configurazione che applica le impostazioni a ogni avvio della VM, poi le applica subito senza dover riavviare.

**Verifica:**

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
```

✅ **Devi vedere:** una riga in cui `always` è tra parentesi quadre, così: `[always] madvise never`.

---

## Parte 6 — Configurare MongoDB

> 📍 **Dove:** sulla VM.

### 6.1 Creare la cartella di lavoro

Tutti i file di MongoDB staranno in una cartella dedicata:

```bash
mkdir -p ~/mongodb
cd ~/mongodb
```

✅ Il prompt diventa `azureuser@mongo-vm:~/mongodb$`.

> ⚠️ **Da qui in avanti, i comandi `docker compose` funzionano solo se sei dentro questa cartella.** Se chiudi e riapri la sessione, ricordati di rientrarci con `cd ~/mongodb`.

### 6.2 Creare la password dell'amministratore

Invece di inventare una password, ne generiamo una casuale e robusta, e la salviamo in un file:

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee mongo_root_password.txt > /dev/null
sudo chown 999:999 mongo_root_password.txt
sudo chmod 600 mongo_root_password.txt
```

**Cosa fa:**

1. genera una password casuale di circa 30 caratteri (lettere e numeri) e la scrive nel file `mongo_root_password.txt`;
2. assegna il file all'utente con numero **999**: è l'utente con cui MongoDB gira dentro il container, e deve poter leggere la password;
3. rende il file leggibile **solo** da quell'utente (e dall'amministratore).

**Per leggere la password quando ti serve:**

```bash
sudo cat ~/mongodb/mongo_root_password.txt
```

> 🔐 Salva questa password anche in un password manager. Se perdi sia il file sia la password, perdi l'accesso da amministratore al database.

### 6.3 Creare il file di configurazione di Docker Compose

Incolla il blocco **intero**:

```bash
cat > docker-compose.yml << 'EOF'
services:
  mongo:
    image: mongo:8.0
    container_name: mongo
    restart: unless-stopped
    stop_grace_period: 1m
    ports:
      - "127.0.0.1:27017:27017"
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
    secrets:
      - mongo_root_password

volumes:
  mongo-data:

secrets:
  mongo_root_password:
    file: ./mongo_root_password.txt
EOF
```

**Cosa significa ogni parte:**

| Riga | Significato |
|---|---|
| `image: mongo:8.0` | Usa l'immagine ufficiale di MongoDB, versione 8.0 (con l'ultima correzione disponibile) |
| `container_name: mongo` | Il container si chiamerà `mongo` |
| `restart: unless-stopped` | Se si ferma o la VM si riavvia, riparte da solo (tranne se l'hai fermato tu) |
| `stop_grace_period: 1m` | Allo spegnimento, Docker aspetta fino a un minuto che MongoDB si chiuda da solo in modo ordinato, invece dei 10 secondi predefiniti dopo i quali lo terminerebbe forzatamente |
| `ports: "127.0.0.1:27017:27017"` | MongoDB è raggiungibile sulla porta 27017, **ma solo dalla VM stessa** |
| `ulimits` | Permette a MongoDB di aprire molti file contemporaneamente, come raccomandato |
| `logging` | Limita lo spazio dei log: al massimo 5 file da 50 MB ciascuno |
| `MONGO_INITDB_ROOT_USERNAME` | Crea l'utente amministratore `admin` al primo avvio |
| `MONGO_INITDB_ROOT_PASSWORD_FILE` | Legge la password di `admin` dal file creato prima |
| `volumes: mongo-data:/data/db` | Salva i dati nel volume `mongo-data`, così sopravvivono al container |
| `secrets` | Passa il file della password al container in modo sicuro |

> ⚠️ **Il file YAML è sensibile agli spazi.** L'indentazione (gli spazi a inizio riga) deve essere esatta e fatta con spazi, mai con il tasto Tab. Per questo è meglio incollare il blocco così com'è invece di riscriverlo a mano.

> ⚠️ **Non cambiare mai `127.0.0.1:27017:27017` in `27017:27017` o `0.0.0.0:27017:27017`.** Docker scavalca il firewall di Linux, e il database finirebbe esposto a tutti.

### 6.4 Controllare che il file sia scritto correttamente

```bash
sudo docker compose config --quiet && echo "compose valido"
```

✅ **Devi vedere:** `compose valido`
❌ **Se compare un errore:** probabilmente il blocco non è stato incollato per intero. Ripeti il passo 6.3.

---

## Parte 7 — Avviare MongoDB e verificare che funzioni

> 📍 **Dove:** sulla VM, nella cartella `~/mongodb`.

### 7.1 Avvio

```bash
sudo docker compose up -d
```

**Cosa fa:** scarica l'immagine di MongoDB (solo la prima volta, qualche centinaio di MB) e avvia il container. `-d` significa "in background": il terminale torna libero.

✅ **Devi vedere:** righe con `Created` e `Started`.

### 7.2 Guardare i log di avvio

```bash
sudo docker compose logs -f mongo
```

Scorreranno molte righe tecniche: non spaventarti. Al primo avvio MongoDB si avvia due volte: una prima volta per creare l'utente amministratore, poi definitivamente.

✅ **Devi vedere, verso la fine:** `MongoDB init process complete; ready for start up.` e poi `Waiting for connections`.

Quando le vedi, premi **Ctrl+C** per uscire. Il database continua a funzionare.

### 7.3 Collegarsi al database come amministratore

```bash
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin
```

**Cosa fa:** apre `mongosh` dentro il container, come utente `admin`.

Ti chiederà la password (`Enter password:`). Recuperala con `sudo cat ~/mongodb/mongo_root_password.txt` e incollala: mentre la incolli vedrai solo asterischi.

✅ **Devi vedere:** `Using MongoDB: 8.0.x` e il prompt `test>`.

Prova un comando:

```javascript
db.runCommand({ ping: 1 })
```

✅ Risposta: `{ ok: 1 }`

Per uscire da `mongosh` scrivi `exit` oppure premi **Ctrl+D**.

### 7.4 Controllare gli avvisi

All'accesso, `mongosh` può mostrare un riquadro "The server generated these startup warnings". Con questa configurazione deve comparire **solo** l'avviso sul filesystem XFS, che per ora puoi ignorare (vedi Parte 16).

Per controllare in futuro avvisi ed errori senza leggere tutti i log:

```bash
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'
```

`W` = avviso, `E` = errore, `F` = errore fatale.

> Gli avvisi che contengono `Use of deprecated server parameter` e `"ctx":"ftdc"` sono **innocui**: vengono da un sistema interno di diagnostica di MongoDB e compaiono a ogni avvio.

---

## Parte 8 — Creare l'utente per la tua applicazione

> 📍 **Dove:** sulla VM, nella cartella `~/mongodb`.

**Perché serve:** l'utente `admin` può fare tutto, anche cancellare ogni database. La tua applicazione deve usare un utente che può lavorare **solo sul proprio database**: se un giorno la password dell'applicazione venisse rubata, il danno resterebbe limitato.

In questa guida il database si chiama `appdb` e l'utente `appuser`. Puoi usare nomi diversi: sostituiscili ovunque compaiano.

### 8.1 Generare la password dell'utente

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee ~/mongodb/appuser_password.txt > /dev/null
sudo chmod 600 ~/mongodb/appuser_password.txt
```

### 8.2 Creare l'utente

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("appdb").createUser({ user: "appuser", pwd: process.env.APP_PWD, roles: [ { role: "readWrite", db: "appdb" } ] })'
```

**Cosa fa:** legge la nuova password dal file e la passa a MongoDB, che crea l'utente `appuser` con il permesso di leggere e scrivere (`readWrite`) solo nel database `appdb`. Ti chiede la password di **admin**.

✅ **Devi vedere:** `{ ok: 1 }`

> **Perché non incollare semplicemente la password?** Incollando una password nel prompt interattivo di `mongosh`, alcuni terminali aggiungono caratteri invisibili, e MongoDB risponde con l'errore `U_STRINGPREP_PROHIBITED_ERROR`. Leggendola dal file, il problema non si presenta.

> Il database `appdb` non va creato prima: MongoDB lo crea da solo quando l'applicazione ci scrive la prima volta.

### 8.3 Verificare che l'utente funzioni

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.runCommand({ ping: 1 })"'
```

✅ **Devi vedere:** `{ ok: 1 }`

### 8.4 Cambiare la password dell'utente (quando serve)

Per esempio se è stata copiata per errore da qualche parte:

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee ~/mongodb/appuser_password.txt > /dev/null

sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("appdb").changeUserPassword("appuser", process.env.APP_PWD)'
```

⚠️ **Esegui entrambi i comandi, nell'ordine.** Il primo genera la nuova password, il secondo la comunica a MongoDB. Se esegui solo il secondo, reimposti la password vecchia.

Dopo il cambio, ricordati di aggiornare la password anche nella configurazione della tua applicazione.

### 8.5 La stringa di connessione per l'applicazione

L'applicazione si collega a MongoDB con una "stringa di connessione", che contiene utente, password, indirizzo e database. Scegli quella adatta:

| Dove gira l'applicazione | Stringa di connessione |
|---|---|
| Sulla VM stessa | `mongodb://appuser:PASSWORD@127.0.0.1:27017/appdb?authSource=appdb` |
| In un altro container dello stesso `docker-compose.yml` | `mongodb://appuser:PASSWORD@mongo:27017/appdb?authSource=appdb` |
| Sul tuo PC, tramite tunnel SSH (Parte 11.1) | `mongodb://appuser:PASSWORD@127.0.0.1:27017/appdb?authSource=appdb&directConnection=true` |
| Sul tuo PC, con accesso diretto (Parte 11.2) | `mongodb://appuser:PASSWORD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true` |

Al posto di `PASSWORD` metti quella letta con `sudo cat ~/mongodb/appuser_password.txt`.

> 🔐 Nel progetto dell'applicazione, metti la stringa di connessione in un file `.env` (o nelle variabili d'ambiente) e aggiungi `.env` al file `.gitignore`, così la password non finisce nel repository del codice.

---

## Parte 9 — Backup automatici

> 📍 **Dove:** sulla VM.

**Come funziona:** ogni notte uno script salva una copia compressa di tutti i database. Le copie vengono conservate così:

| Tipo | Quando viene creato | Quante copie restano |
|---|---|---|
| Giornaliero | Ogni notte | Ultimi **7 giorni** |
| Settimanale | Ogni domenica | Ultime **4 settimane** |
| Mensile | Il primo di ogni mese | Ultimi **12 mesi** |

Le copie settimanali e mensili non occupano spazio in più finché esiste anche quella giornaliera dello stesso giorno (sono *hard link*: lo stesso file visto da due cartelle).

Il flusso di un backup notturno:

```mermaid
sequenceDiagram
    participant T as Timer systemd
    participant S as mongo-backup.sh
    participant C as Container mongo
    participant D as Cartella dei backup
    T->>S: ogni notte alle 02:30 UTC
    S->>C: docker exec, mongodump --archive --gzip
    C-->>S: archivio compresso
    S->>D: salva in daily/ con permessi 600
    S->>D: domenica in weekly/, giorno 1 in monthly/ (hard link)
    S->>D: elimina i file oltre la retention
    Note over S: se il dump fallisce, set -e ferma lo script<br/>prima della pulizia: i vecchi backup restano
```

### 9.1 Creare la cartella dei backup

```bash
sudo mkdir -p /var/backups/mongodb
sudo chmod 700 /var/backups/mongodb
```

La cartella è accessibile solo all'amministratore: i backup contengono tutti i dati.

### 9.2 Creare lo script di backup

Incolla il blocco **intero**, fino alla riga `EOF` compresa, poi le due righe successive:

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
  mongodump --config=/tmp/dump.yaml -u admin --authenticationDatabase admin --archive --gzip --quiet
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
sudo head -3 /usr/local/bin/mongo-backup.sh
```

✅ **L'ultimo comando deve mostrare:** `#!/bin/bash`, `set -euo pipefail`, `umask 077`.
❌ **Se dice `No such file or directory`:** il blocco non è stato incollato per intero. Riprova.

**Cosa fa lo script, in parole semplici:**

1. si ferma subito alla prima cosa che va storta (`set -euo pipefail`), così non cancella mai i vecchi backup se il nuovo non è riuscito;
2. fa in modo che i file creati siano leggibili solo dall'amministratore (`umask 077`);
3. chiede a MongoDB, dentro il container, di esportare tutti i dati in un unico file compresso (`mongodump`); la password viene passata tramite un file temporaneo, così non è visibile ad altri programmi;
4. se è domenica, "copia" il backup nella cartella `weekly`; se è il primo del mese, in `monthly`;
5. cancella i backup più vecchi del periodo di conservazione;
6. scrive un messaggio di conferma con la dimensione del file.

**Per cambiare quanto tempo conservare i backup**, modifica le tre righe `KEEP_...` in cima allo script. Per esempio, per 14 giorni di backup giornalieri:

```bash
sudo sed -i 's/^KEEP_DAILY=.*/KEEP_DAILY=14      # giorni/' /usr/local/bin/mongo-backup.sh
sudo grep KEEP_ /usr/local/bin/mongo-backup.sh
```

### 9.3 Provare il backup a mano

```bash
sudo /usr/local/bin/mongo-backup.sh
sudo ls -lhR /var/backups/mongodb
```

✅ **Devi vedere:** `Backup completato: /var/backups/mongodb/daily/mongo-AAAAMMGG-HHMMSS.archive.gz` e, nell'elenco, il file con permessi `-rw-------`.

Con un database quasi vuoto il file pesa solo 1–4 KB: è normale.

> **Se attiverai il TLS** (guida `01-tls-guida-completa.md`), questo script non riuscirà più a collegarsi: andrà sostituito con la versione della guida 01, che funziona sia con sia senza TLS.

### 9.4 Programmare il backup ogni notte

> Collaudati: backup manuale, esecuzione tramite systemd, esecuzione notturna automatica (anche con il TLS della guida 01 attivo) e ripristino. La creazione delle copie settimanali (domenica) e mensili (giorno 1) e la pulizia per scadenza non sono ancora state osservate su un periodo reale 🧪.

Usiamo i *timer* di systemd, il sistema che in Debian gestisce i servizi e le attività programmate. Servono due file: uno che dice **cosa** fare (`.service`) e uno che dice **quando** (`.timer`). Incolla tutto il blocco:

```bash
sudo tee /etc/systemd/system/mongo-backup.service > /dev/null << 'EOF'
[Unit]
Description=Backup MongoDB
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mongo-backup.sh
EOF

sudo tee /etc/systemd/system/mongo-backup.timer > /dev/null << 'EOF'
[Unit]
Description=Backup notturno MongoDB

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mongo-backup.timer
systemctl list-timers mongo-backup.timer
```

✅ **Devi vedere:** una riga con la data della prossima esecuzione alle `02:30:00 UTC`.

**Da sapere:**

- La VM usa l'orario **UTC**. Le 02:30 UTC sono le **04:30 in Italia** con l'ora legale e le **03:30** con l'ora solare.
- `Persistent=true`: se la VM era spenta all'ora prevista, il backup parte appena si riaccende.
- Per cambiare orario, modifica la riga `OnCalendar` nel file `/etc/systemd/system/mongo-backup.timer` (per esempio con `sudo nano`) e poi esegui `sudo systemctl daemon-reload`.

### 9.5 Verificare che funzioni anche in automatico

Lanciamo il backup "come se fosse notte", tramite systemd:

```bash
sudo systemctl start mongo-backup.service
sudo journalctl -u mongo-backup.service -n 10 --no-pager
```

✅ **Devi vedere:** `Backup completato: ...` e `Finished mongo-backup.service`.

<details>
<summary>📋 Output reale del collaudo</summary>

```
Sep 28 13:48:08 mongo-vm systemd[1]: Starting mongo-backup.service - Backup MongoDB...
Sep 28 13:48:09 mongo-vm mongo-backup.sh[2405]: Backup completato: /var/backups/mongodb/daily/mongo-20260928-134809.archive.gz (4.0K)
Sep 28 13:48:09 mongo-vm systemd[1]: mongo-backup.service: Deactivated successfully.
Sep 28 13:48:09 mongo-vm systemd[1]: Finished mongo-backup.service - Backup MongoDB.

# La prima esecuzione notturna automatica:
Sep 29 02:30:00 mongo-vm systemd[1]: Starting mongo-backup.service - Backup MongoDB...
Sep 29 02:30:00 mongo-vm mongo-backup.sh[4682]: Backup completato: /var/backups/mongodb/daily/mongo-20260929-023000.archive.gz (4.0K)
Sep 29 02:30:00 mongo-vm systemd[1]: Finished mongo-backup.service - Backup MongoDB.
```

</details>

In futuro, con lo stesso comando `journalctl` puoi controllare com'è andato il backup di ogni notte.

### 9.6 Quanto spazio occupano i backup

```bash
sudo du -sh /var/backups/mongodb
```

Controllalo di tanto in tanto, soprattutto quando il database comincerà a crescere.

> ⚠️ **Attenzione all'asterisco.** La cartella dei backup è leggibile solo dall'amministratore, quindi un comando come `sudo chmod 600 /var/backups/mongodb/daily/*` fallisce con `No such file or directory`: l'asterisco viene interpretato dal tuo utente prima di `sudo`, e il tuo utente non vede i file. Usa sempre la forma: `sudo sh -c 'comando con /var/backups/mongodb/daily/*'`.

---

## Parte 10 — Ripristinare un backup

> 📍 **Dove:** sulla VM.

"Ripristinare" significa riportare il database allo stato salvato in un backup.

### 10.1 Ripristinare il backup più recente

```bash
sudo sh -c 'f=$(ls -t /var/backups/mongodb/daily/mongo-*.archive.gz | head -1); echo "Ripristino: $f"; \
  docker exec -i mongo sh -c "mongorestore -u admin -p \"\$(cat /run/secrets/mongo_root_password)\" --authenticationDatabase admin --archive --gzip --drop" < "$f"'
```

**Cosa fa:** trova il backup giornaliero più recente, mostra quale sta usando e lo passa a `mongorestore`, che lo ricarica nel database.

⚠️ `--drop` significa che **le collezioni presenti nel backup vengono sostituite** con la versione salvata: le modifiche fatte dopo il backup su quelle collezioni vanno perse.

✅ **Devi vedere, alla fine:** `N document(s) restored successfully. 0 document(s) failed to restore.`

Gli utenti (`admin`, `appuser`) vengono ripristinati anch'essi: compaiono nella riga `restoring users` e non nel conteggio dei documenti.

### 10.2 Ripristinare un backup specifico

Elenca i backup disponibili:

```bash
sudo ls -lh /var/backups/mongodb/daily /var/backups/mongodb/weekly /var/backups/mongodb/monthly
```

Poi usa lo stesso comando del punto 10.1 sostituendo la parte `f=$(...)` con il percorso del file scelto, ad esempio `f=/var/backups/mongodb/weekly/mongo-20260927-023000.archive.gz`.

### 10.3 Esercizio: prova completa di ripristino

Un backup che non hai mai provato a ripristinare non è un backup affidabile. Fai questa prova almeno una volta, **finché il database è ancora di prova**.

**1. Inserisci un documento di prova:**

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.prova.insertOne({ msg: \"ciao\" }); db.prova.countDocuments()"'
```

✅ Risposta: `1`

**2. Fai un backup:**

```bash
sudo /usr/local/bin/mongo-backup.sh
```

**3. Cancella la collezione (simula un incidente):**

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.prova.drop(); db.prova.countDocuments()"'
```

✅ Risposta: `0` (i dati sono "spariti").

**4. Ripristina** con il comando del punto 10.1. Deve dire `1 document(s) restored successfully`.

**5. Controlla che il dato sia tornato:** ripeti il comando del passo 3 sostituendo `db.prova.drop(); db.prova.countDocuments()` con `db.prova.countDocuments()`. Risposta attesa: `1`.

**6. Pulizia:** rilancia il comando del passo 3 (quello con `drop`) per eliminare la collezione di prova.

---

## Parte 11 — Collegarsi dal tuo PC di sviluppo

```mermaid
flowchart LR
    PC["PC di sviluppo"]
    subgraph TUN["Tunnel SSH, consigliato"]
        A1["localhost:27017 sul PC"] -- "cifrato da SSH, porta 22" --> A2["127.0.0.1:27017 sulla VM"]
    end
    subgraph DIR["Accesso diretto, solo sviluppo"]
        B1["IP pubblico:27017"] -- "NSG: solo il tuo IP<br/>in chiaro senza TLS" --> B2["IP privato:27017 sulla VM"]
    end
    PC --> A1
    PC --> B1
```

Per come lo abbiamo configurato, MongoDB accetta connessioni **solo dalla VM stessa**. Per collegarti dal tuo PC ci sono due strade.

| | Tunnel SSH (consigliato) | Accesso diretto |
|---|---|---|
| Sicurezza | Traffico cifrato | Traffico **in chiaro** su internet |
| Modifiche alla VM | Nessuna | Compose e regola NSG |
| Comodità | Devi aprire il tunnel prima di lavorare | Ti colleghi e basta |
| Adatto per | Sviluppo, amministrazione | Solo sviluppo con dati di prova |

### 11.1 Tunnel SSH (consigliato)

> 🧪 **Non ancora collaudato** su un'installazione reale: durante il collaudo è stato usato l'accesso diretto della Parte 11.2. I comandi sono standard, ma segnala eventuali differenze.

**Idea:** usi il collegamento SSH, che già funziona e cifra tutto, come un "tubo" che porta la porta 27017 della VM sul tuo PC. La tua applicazione crede che MongoDB sia sul tuo computer.

> 📍 **Dove:** sul tuo PC (non sulla VM!). Apri un **nuovo** terminale PowerShell.

```powershell
ssh -i C:\percorso\della\chiave.pem -N -L 27017:127.0.0.1:27017 azureuser@<IP_PUBBLICO_VM>
```

**Cosa significano le opzioni:**

- `-N`: non aprire una shell, crea solo il tunnel;
- `-L 27017:127.0.0.1:27017`: "la porta 27017 del mio PC porta alla porta 27017 di `127.0.0.1` sulla VM".

✅ **Cosa vedi:** apparentemente nulla, il terminale resta "fermo". **È normale:** il tunnel è attivo finché quella finestra resta aperta. Lascia la finestra aperta e lavora da un'altra. Per chiudere il tunnel: **Ctrl+C**.

Mentre il tunnel è attivo, la tua applicazione usa questa stringa:

```
mongodb://appuser:PASSWORD@127.0.0.1:27017/appdb?authSource=appdb&directConnection=true
```

**Se sul tuo PC hai già MongoDB installato** (che usa già la porta 27017), usa un'altra porta locale: `-L 27018:127.0.0.1:27017`, e nella stringa di connessione scrivi `27018`.

**Per non dover riscrivere il comando ogni volta**, crea (o modifica) sul tuo PC il file `C:\Users\<tuo-nome>\.ssh\config` con questo contenuto:

```
Host mongo-azure
    HostName <IP_PUBBLICO_VM>
    User azureuser
    IdentityFile C:\percorso\della\chiave.pem
    LocalForward 27017 127.0.0.1:27017
    ServerAliveInterval 60
```

Da quel momento il tunnel si apre con:

```powershell
ssh -N mongo-azure
```

`ServerAliveInterval 60` evita che il tunnel si chiuda da solo quando resta inattivo.

**Con MongoDB Compass** (l'interfaccia grafica ufficiale di MongoDB) non serve nemmeno il comando: nella nuova connessione apri *Advanced Connection Options* → scheda *Proxy/SSH* → *SSH with Identity File*, e inserisci indirizzo della VM, utente `azureuser` e il file della chiave. Come stringa di connessione usa quella qui sopra.

### 11.2 Accesso diretto (solo per sviluppo)

> ⚠️ **Leggi prima:** con questa soluzione utente, password e dati viaggiano su internet **senza cifratura**. Va bene solo per sviluppo con dati di prova, e solo se la regola del firewall Azure è limitata al tuo indirizzo IP. Per cifrare il traffico segui la guida `01-tls-guida-completa.md`.

**Passo 1 — Trova l'IP privato della VM.**

> 📍 Sulla VM.

```bash
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1
```

✅ Vedrai un indirizzo privato, per esempio `10.0.0.4`. Annotalo.

**Passo 2 — Pubblica MongoDB anche su quell'indirizzo.**

Modifica il compose con l'editor `nano`:

```bash
cd ~/mongodb
nano docker-compose.yml
```

Nella sezione `ports`, sotto la riga esistente, aggiungi la seconda riga con il tuo IP privato (qui `10.0.0.4` è un esempio), rispettando gli stessi spazi:

```yaml
    ports:
      - "127.0.0.1:27017:27017"
      - "10.0.0.4:27017:27017"
```

Salva con **Ctrl+O** poi **Invio**, esci con **Ctrl+X**.

> Perché l'IP privato e non `0.0.0.0`? Azure "traduce" il tuo IP pubblico verso quello privato della VM, quindi basta quello. `0.0.0.0` aprirebbe MongoDB su tutte le interfacce di rete, comprese quelle interne di Docker.

Applica e verifica:

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose up -d
sudo ss -ltnp | grep 27017
```

✅ **Devi vedere due righe** in ascolto: una su `127.0.0.1:27017` e una sul tuo IP privato. I dati non vengono toccati.

> **Dove si configura l'indirizzo?** Non in un file di configurazione di MongoDB (in questo setup non esiste un `mongod.conf`): dentro il container MongoDB ascolta su tutte le interfacce, ed è **Docker**, con la sezione `ports` del compose, a decidere su quali indirizzi della VM la porta è raggiungibile. Per controllare: `grep -A3 'ports:' docker-compose.yml` mostra cosa hai configurato, `sudo docker port mongo` cosa è attivo. Se l'IP privato compare nel file ma non in `docker port`, manca `sudo docker compose up -d`. L'IP scritto nel compose deve coincidere con quello della VM (`ip -4 addr show eth0`): se cambiasse, il container non partirebbe.

**Passo 3 — Apri la porta nel firewall di Azure (NSG).**

> 📍 Nel portale Azure, dal browser.

1. Apri la tua VM → menu *Rete* (o *Impostazioni di rete*).
2. Clicca *Crea regola porta* → *Regola porta in ingresso*.
3. Compila così:

| Campo | Valore |
|---|---|
| Origine | *Indirizzi IP* |
| Indirizzi IP di origine | `<IL_TUO_IP>` (cerca "what is my ip" dal browser del tuo PC) |
| Intervalli di porte di destinazione | `27017` |
| Protocollo | TCP |
| Azione | Consenti |
| Nome | `mongodb-dev` |

4. Salva e attendi qualche secondo.

> ⚠️ **Mai "Any" o "Internet" come origine:** chiunque nel mondo potrebbe tentare di entrare nel tuo database.

> In Azure possono esistere due NSG: uno sulla scheda di rete della VM e uno sulla *subnet*. Se la connessione non funziona, controlla che la porta sia consentita in entrambi (nella pagina *Rete* vedi le regole di tutti e due).

**Passo 4 — Prova dal tuo PC.**

> 📍 Sul tuo PC, in PowerShell.

```powershell
Test-NetConnection <IP_PUBBLICO_VM> -Port 27017
```

✅ **Devi vedere:** `TcpTestSucceeded : True`

Stringa di connessione per la tua applicazione:

```
mongodb://appuser:PASSWORD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true
```

> Se un giorno smette di funzionare, quasi sempre è cambiato l'indirizzo IP della tua connessione internet: aggiorna l'origine nella regola NSG.

**Per chiudere l'accesso diretto** (per esempio prima di andare in produzione): togli la seconda riga da `ports`, esegui `sudo docker compose up -d` ed elimina la regola `mongodb-dev` dal portale Azure.

---

## Parte 12 — Gestire lo spazio occupato dai log

> 📍 **Dove:** sulla VM.

MongoDB scrive continuamente messaggi di log. Senza limiti, in qualche mese potrebbero riempire il disco, e **con il disco pieno MongoDB si ferma**.

### 12.1 La configurazione attuale

Nel compose abbiamo già messo:

```yaml
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
```

Significa: quando il file di log arriva a 50 MB se ne comincia uno nuovo, e se ne tengono al massimo 5. Totale massimo: **250 MB**. È un limite di **spazio**, non di tempo: quanti giorni di log ci stanno dipende da quanto "chiacchiera" MongoDB.

**Verifica che sia attiva:**

```bash
sudo docker inspect mongo --format '{{json .HostConfig.LogConfig}}'
```

✅ **Devi vedere:** `{"Type":"json-file","Config":{"max-file":"5","max-size":"50m"}}`

**Quanto spazio occupano ora:**

```bash
sudo sh -c 'du -sh /var/lib/docker/containers/*/*-json.log*'
```

**Per cambiare i limiti:** modifica `max-size` e/o `max-file` nel compose, poi `sudo docker compose up -d`. Nota: ricreando il container, i log accumulati fino a quel momento vengono eliminati (i dati del database no).

### 12.2 Alternativa: conservare i log per un numero di giorni

> 🧪 **Non ancora collaudato** su un'installazione reale: durante il collaudo è stata usata la configurazione predefinita della Parte 12.1.

Se preferisci un limite in giorni (per esempio "tieni 30 giorni"), puoi mandare i log al *journal* di sistema.

Nel compose sostituisci il blocco `logging` con:

```yaml
    logging:
      driver: journald
      options:
        tag: mongo
```

Poi imposta i limiti del journal e applica:

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/retention.conf > /dev/null << 'EOF'
[Journal]
Storage=persistent
MaxRetentionSec=30day
SystemMaxUse=1G
EOF
sudo systemctl restart systemd-journald
cd ~/mongodb && sudo docker compose up -d
```

Vale il primo limite raggiunto tra **30 giorni** e **1 GB**. Questi limiti valgono per tutti i log del sistema, non solo per MongoDB.

Per leggere i log di un certo periodo:

```bash
sudo journalctl CONTAINER_NAME=mongo --since "2 days ago"
```

### 12.3 I dati diagnostici

Dentro il volume dei dati MongoDB tiene anche una cartella `diagnostic.data`, con informazioni tecniche utili in caso di problemi. Si gestisce da sola, con un limite predefinito di circa 250 MB: non serve fare niente.

---

## Parte 13 — Rendere sicuro il sistema

> 📍 **Dove:** sulla VM.

### 13.1 Aggiornamenti di sicurezza automatici

Ogni settimana escono correzioni di sicurezza per Linux. Facciamo in modo che la VM le installi da sola.

```bash
sudo apt-get install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -plow unattended-upgrades
```

Si apre una schermata blu con la domanda *Automatically download and install stable updates?*: seleziona **Sì** (o *Yes*) con le frecce e premi **Invio**.

**Includere anche gli aggiornamenti di Docker.** Per impostazione predefinita vengono aggiornati solo i pacchetti di Debian. Per includere Docker:

```bash
sudo tee /etc/apt/apt.conf.d/51unattended-docker > /dev/null << 'EOF'
Unattended-Upgrade::Origins-Pattern {
        "origin=Docker";
};
EOF
```

Quando Docker si aggiorna, MongoDB si ferma per qualche secondo e riparte da solo. Per un ambiente di sviluppo va bene; in produzione è meglio aggiornare Docker a mano, in un momento scelto.

**Riavvio automatico quando serve (opzionale).** Alcuni aggiornamenti (quelli del *kernel*, il cuore del sistema) hanno effetto solo dopo un riavvio. Puoi lasciare che la VM si riavvii da sola alle 04:00 UTC quando necessario:

```bash
sudo tee /etc/apt/apt.conf.d/52unattended-reboot > /dev/null << 'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF
```

Se preferisci decidere tu quando riavviare, salta questo passaggio e ogni tanto controlla:

```bash
ls /var/run/reboot-required
```

Se il file **esiste**, è ora di riavviare (`sudo reboot`). Se risponde `No such file or directory`, non serve.

**Verifica della configurazione:**

```bash
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -E "Allowed origins|Packages that will be upgraded"
```

✅ **Devi vedere:** una riga `Allowed origins are:` che comprende `Debian-Security` e, se hai aggiunto il file per Docker, `origin=Docker`.

> I messaggi che parlano di *battery* e *metered connection* riguardano i portatili: ignorali.

Per installare subito gli aggiornamenti in attesa, senza aspettare il giro automatico:

```bash
sudo unattended-upgrade -v
```

### 13.2 Proteggere l'accesso SSH

> 🧪 **Non ancora collaudato** su un'installazione reale: la creazione della chiave SSH e la disattivazione dell'accesso con password non sono ancora state eseguite. Segui con particolare attenzione la prova da un secondo terminale, per non restare chiuso fuori.

L'obiettivo è che si possa entrare nella VM **solo con la chiave**, non con una password (le password possono essere indovinate da programmi automatici che provano milioni di combinazioni).

**Controlla la situazione attuale:**

```bash
sudo sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin)'
```

✅ **Situazione ideale:**

```
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
permitrootlogin no
```

Se è già così, **non devi fare niente**.

**Se `passwordauthentication` o `kbdinteractiveauthentication` sono `yes`:**

> ⚠️ Prima di procedere, assicurati di entrare nella VM con una **chiave** e non con una password. Altrimenti, con la modifica seguente, resteresti chiuso fuori.

**Come capire se usi la password:** se `ssh` (o `scp`) ti chiede `azureuser@...'s password:`, stai usando la password. In quel caso crea prima una chiave SSH.

**Creare una chiave SSH e installarla sulla VM** (📍 dal tuo PC, in PowerShell):

```powershell
# 1. Crea la coppia di chiavi: premi Invio per il percorso predefinito; puoi impostare una passphrase
ssh-keygen -t ed25519

# 2. Copia la chiave pubblica sulla VM (ti chiederà la password un'ultima volta)
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh azureuser@<IP_PUBBLICO_VM> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# 3. Prova: deve entrare SENZA chiedere la password
ssh azureuser@<IP_PUBBLICO_VM>
```

La chiave privata (`id_ed25519`, senza estensione) resta sul PC nella cartella `C:\Users\<tuo-nome>\.ssh\` e non va mai condivisa; sulla VM finisce solo la parte pubblica (`.pub`). Essendo nella posizione predefinita, `ssh` e `scp` la usano automaticamente, senza bisogno di `-i`.

Solo quando il passo 3 funziona senza password, procedi:

```bash
sudo tee /etc/ssh/sshd_config.d/50-hardening.conf > /dev/null << 'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo systemctl reload ssh
```

`sshd -t` controlla che la configurazione sia corretta prima di applicarla.

**Prova di sicurezza obbligatoria:** **non chiudere** la sessione in cui sei. Apri un **secondo** terminale sul tuo PC e prova a collegarti di nuovo alla VM. Se funziona, tutto a posto. Se non funziona, dalla prima sessione (ancora aperta) annulla la modifica:

```bash
sudo rm /etc/ssh/sshd_config.d/50-hardening.conf
sudo systemctl reload ssh
```

**Nel portale Azure**, controlla anche la regola dell'NSG per la porta **22** (SSH): l'origine dovrebbe essere `<IL_TUO_IP>`, non "Any". Le VM con la porta 22 aperta a tutto internet ricevono tentativi di accesso continui.

---

## Parte 14 — Uso quotidiano e manutenzione

> 📍 **Dove:** sulla VM, nella cartella `~/mongodb` (`cd ~/mongodb`).

### 14.1 MongoDB parte da solo al riavvio della VM?

Sì, grazie a due cose: il servizio Docker è impostato per partire all'accensione, e il compose contiene `restart: unless-stopped`.

**Verifica:**

```bash
systemctl is-enabled docker
sudo docker inspect mongo --format '{{.HostConfig.RestartPolicy.Name}}'
```

✅ Risposte: `enabled` e `unless-stopped`.

> **L'eccezione di "unless-stopped":** se prima del riavvio avevi fermato tu il container (con `docker compose stop`), dopo il riavvio resta fermo. Lo riavvii con `sudo docker compose start`.

**Prova pratica** (quando nessuno sta usando il database):

```bash
sudo reboot
```

La connessione SSH si chiude. Attendi un paio di minuti, ricollegati e controlla:

```bash
sudo docker ps
cat /sys/kernel/mm/transparent_hugepage/enabled
```

✅ Il container `mongo` deve risultare `Up`, e `always` deve essere tra parentesi quadre.

### 14.2 Comandi di tutti i giorni

| Voglio... | Comando |
|---|---|
| Vedere se MongoDB è acceso | `sudo docker compose ps` |
| Vedere i log in tempo reale (uscita con Ctrl+C) | `sudo docker compose logs -f mongo` |
| Vedere solo avvisi ed errori | `sudo docker compose logs mongo \| grep -E '"s":"(W\|E\|F)"'` |
| Fermare MongoDB | `sudo docker compose stop` |
| Avviare MongoDB | `sudo docker compose start` |
| Riavviare MongoDB | `sudo docker compose restart` |
| Applicare modifiche al `docker-compose.yml` | `sudo docker compose up -d` |
| Aprire la shell del database come admin | `sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin` |
| Vedere su quali indirizzi è raggiungibile MongoDB | `sudo docker port mongo` e `sudo ss -ltnp \| grep 27017` |
| Fare un backup subito | `sudo /usr/local/bin/mongo-backup.sh` |
| Vedere l'esito dei backup notturni | `sudo journalctl -u mongo-backup.service -n 20 --no-pager` |
| Vedere lo spazio libero su disco | `df -h /` |

### 14.3 Aggiornare MongoDB

Per installare l'ultima correzione della versione 8.0 (consigliato ogni tanto):

```bash
cd ~/mongodb
sudo /usr/local/bin/mongo-backup.sh
sudo docker compose pull
sudo docker compose up -d
```

**Cosa fa:** prima un backup di sicurezza, poi scarica l'immagine aggiornata, poi ricrea il container con la nuova versione. I dati restano nel volume. MongoDB resta spento per qualche secondo.

**Verifica la versione:**

```bash
sudo docker exec mongo mongod --version | head -1
```

> **Passare a una nuova versione principale** (per esempio da 8.0 a una futura 9.0) è un'operazione diversa e più delicata: si fa un passo di versione alla volta, con backup, lettura delle note ufficiali di aggiornamento e un passaggio aggiuntivo chiamato *featureCompatibilityVersion*. Non cambiare il numero dopo `mongo:` nel compose senza esserti documentato.

### 14.4 Il comando da non usare mai

```bash
sudo docker compose down -v     # ⛔ NON USARE su un database con dati
```

L'opzione `-v` **cancella il volume**, cioè **tutti i dati** del database, senza chiedere conferma. `sudo docker compose down` senza `-v` è invece sicuro (ferma e rimuove il container, ma i dati restano).

---

## Parte 15 — Quando qualcosa va storto

### Problemi di collegamento

**Non riesco a collegarmi con SSH alla VM.**

- Controlla di aver sostituito `<IP_PUBBLICO_VM>` con l'indirizzo vero, **senza** `<` e `>`. L'errore `Could not resolve hostname` indica proprio questo.
- Assicurati di lanciare il comando **dal tuo PC**, non dalla VM (guarda il prompt).
- Se il comando resta bloccato e poi dà *timeout*: la porta 22 è chiusa. Nel portale Azure controlla che la VM abbia un IP pubblico e che l'NSG consenta la porta 22 dal tuo IP.
- Su Windows, l'errore `UNPROTECTED PRIVATE KEY FILE` significa che il file della chiave ha permessi troppo larghi: dalle proprietà del file (*Sicurezza* → *Avanzate*) disattiva l'ereditarietà e lascia l'accesso solo al tuo utente.

**Dal PC non raggiungo MongoDB sulla porta 27017.**

- Con il tunnel SSH: la finestra del tunnel deve restare aperta, e la stringa di connessione deve usare `127.0.0.1`, non l'IP della VM.
- Con l'accesso diretto: controlla che `sudo ss -ltnp | grep 27017` mostri l'IP privato, che la regola NSG esista, abbia come origine il tuo IP **attuale** e riguardi la porta 27017 in TCP.

### Problemi con i comandi

| Messaggio | Cosa significa | Cosa fare |
|---|---|---|
| `no configuration file provided: not found` | Non sei nella cartella con `docker-compose.yml` | `cd ~/mongodb` e riprova |
| `permission denied while trying to connect to the Docker daemon` | Manca `sudo` | Rilancia il comando con `sudo` davanti |
| `No such file or directory` subito dopo aver creato un file | Il blocco `<< 'EOF'` non è stato incollato per intero | Ricopia il blocco dalla prima riga fino a `EOF` compreso |
| `cannot access '/var/backups/mongodb/...*...'` | L'asterisco viene letto dal tuo utente, che non vede la cartella | Usa `sudo sh -c '...'` (vedi Parte 9.6) |
| `-bash: udo: command not found` o simili | Errore di battitura | Ricontrolla il comando (qui mancava la `s` di `sudo`) |

### Problemi con MongoDB

| Sintomo | Causa probabile | Soluzione |
|---|---|---|
| `MongoServerError: Authentication failed` | Password sbagliata (magari una vecchia) | Rileggi quella attuale con `sudo cat ~/mongodb/mongo_root_password.txt` (o `appuser_password.txt`) |
| Ho cambiato la password nel file `mongo_root_password.txt` ma non funziona | Il file viene letto **solo al primo avvio**, quando il database è vuoto | Cambia la password dentro MongoDB con `db.changeUserPassword()`, come nella Parte 8.4 ma per `admin` nel database `admin` |
| Il container si ferma subito al primo avvio, errore di permessi sulla password | Il file password non è leggibile dall'utente 999 | `sudo chown 999:999 ~/mongodb/mongo_root_password.txt` e riavvia |
| `U_STRINGPREP_PROHIBITED_ERROR` creando un utente | Caratteri invisibili incollati nella password | Usa il metodo della Parte 8.2 (password letta dal file) |
| Avviso `Soft rlimits for open file descriptors too low` | Manca il blocco `ulimits` nel compose | Aggiungilo (Parte 6.3) e `sudo docker compose up -d` |
| Avviso che cita `sysfsFile` o l'allocatore di memoria | Transparent Huge Pages non configurate | Rifai la Parte 5 |
| Avviso `Using the XFS filesystem is strongly recommended` | Il disco non è formattato XFS | Per sviluppo si ignora; per produzione vedi Parte 16 |
| MongoDB si ferma da solo, nei log compaiono errori di spazio | Disco pieno | `df -h /`, controlla backup (`sudo du -sh /var/backups/mongodb`) e log (Parte 12) |

### Ripartire da zero (solo su un database nuovo e vuoto!)

Se la prima configurazione è andata storta e **non ci sono ancora dati importanti**, il modo più semplice per ricominciare:

```bash
cd ~/mongodb
sudo docker compose down -v
sudo docker compose up -d
```

⚠️ Questo cancella **tutto** il contenuto del database, compresi gli utenti. Usalo solo all'inizio, mai dopo aver caricato dati veri.

### Come chiedere aiuto

Quando chiedi aiuto a un collega o in chat, fornisci:

1. il comando esatto che hai lanciato;
2. il messaggio di errore completo;
3. se riguarda MongoDB, solo le righe di avviso/errore: `sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'`.

E **controlla che nel testo non ci siano password.**

---

## Parte 15 bis — Le scelte: laboratorio e produzione

Questa guida è stata collaudata su una VM Azure con Debian 13, 2 vCPU e 7,8 GB di RAM, usata come **ambiente di sviluppo**. Ogni scelta qui sotto è giustificata da quel contesto; l'ultima colonna indica cosa scegliere in produzione.

| Scelta | Nel laboratorio (collaudato) | Perché | In produzione |
|---|---|---|---|
| Installazione | Immagine Docker ufficiale `mongo:8.0` | Nessun pacchetto server ufficiale per Debian 13 | Docker o pacchetti su un sistema supportato, versione fissata e aggiornata in modo controllato |
| Topologia | Una sola istanza | Ambiente di sviluppo | Replica set di tre nodi (guida 02) |
| Porta | Pubblicata su `127.0.0.1` | Docker scavalca il firewall di Linux | Idem, più rete privata |
| Accesso | Tunnel SSH, o accesso diretto con NSG sul proprio IP | Un solo sviluppatore | Solo rete privata, TLS obbligatorio (guida 01) |
| Disco | Disco di sistema ext4 (avviso XFS) | Semplicità | Disco dati dedicato XFS |
| Memoria | Cache predefinita, nessuno swap | VM dedicata all'istanza | RAM sul *working set*, swap piccolo e monitorato |
| Spegnimento | `stop_grace_period: 1m` | Evita chiusure forzate dopo 10 s | Idem |
| Backup | Locale, notturno, 7/4/12 | Protezione da errori e cancellazioni | Copia anche fuori dalla VM, ripristino provato periodicamente |
| Password | File `600` sulla VM | Semplicità | Key Vault o gestore di segreti |
| Aggiornamenti | Automatici, compreso Docker | Nessun servizio critico | Docker e MongoDB in finestre di manutenzione |

---

## Parte 16 — Prima di andare in produzione

La configurazione di questa guida è adatta allo sviluppo. Prima di metterci dati reali, verifica questi punti:

- [ ] **Chiudere l'accesso diretto sulla porta 27017** (rimuovere l'IP privato dal compose ed eliminare la regola NSG), oppure configurare la cifratura **TLS** su MongoDB (guida `01-tls-guida-completa.md`).
- [ ] **Collegare le applicazioni tramite rete privata** Azure (stessa rete virtuale, peering o VPN), non via internet.
- [ ] **Disco dati dedicato formattato XFS** (Premium SSD) per i dati di MongoDB: è la raccomandazione ufficiale per le prestazioni, e tiene i dati separati dal disco di sistema.
- [ ] **Backup fuori dalla VM:** attivare *Azure Backup* sulla VM o copiare i backup su un *Azure Storage Account*. Oggi i backup sono sullo stesso disco del database: se la VM viene persa, si perdono entrambi.
- [ ] **Avvisi automatici** con *Azure Monitor*: spazio disco in esaurimento e backup falliti.
- [ ] **Password conservate** in *Azure Key Vault* o in un password manager aziendale.
- [ ] **Alta disponibilità:** valutare un *replica set* con tre nodi, se l'applicazione non può permettersi interruzioni.
- [ ] **Aggiornamenti di Docker manuali**, in finestre di manutenzione programmate (togliere il file `51unattended-docker`).
- [ ] **Prova di ripristino** periodica, per esempio una volta al mese.

---

## Appendice A — Dove si trova ogni cosa

| Cosa | Dove |
|---|---|
| Cartella di lavoro | `~/mongodb` (cioè `/home/azureuser/mongodb`) |
| Configurazione del container | `~/mongodb/docker-compose.yml` |
| Password di `admin` | `~/mongodb/mongo_root_password.txt` |
| Password di `appuser` | `~/mongodb/appuser_password.txt` |
| Dati del database | Volume Docker `mongodb_mongo-data` (gestito da Docker) |
| Script di backup | `/usr/local/bin/mongo-backup.sh` |
| Backup | `/var/backups/mongodb/daily`, `weekly`, `monthly` |
| Pianificazione backup | `/etc/systemd/system/mongo-backup.timer` e `.service` |
| Impostazioni memoria (THP) | `/etc/tmpfiles.d/mongodb-thp.conf` |
| Aggiornamenti automatici | `/etc/apt/apt.conf.d/51unattended-docker`, `52unattended-reboot` |
| Configurazione SSH aggiuntiva | `/etc/ssh/sshd_config.d/50-hardening.conf` |
| Log del container | `/var/lib/docker/containers/<id>/` (leggili con `docker compose logs`) |

---

## Appendice B — Promemoria dei comandi

```bash
# Entrare nella cartella di lavoro (sempre, prima dei comandi docker compose)
cd ~/mongodb

# Stato, avvio, arresto
sudo docker compose ps
sudo docker compose start
sudo docker compose stop
sudo docker compose restart

# Log
sudo docker compose logs -f mongo
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'

# Shell del database
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin

# Leggere le password
sudo cat ~/mongodb/mongo_root_password.txt
sudo cat ~/mongodb/appuser_password.txt

# Backup
sudo /usr/local/bin/mongo-backup.sh
sudo journalctl -u mongo-backup.service -n 20 --no-pager
systemctl list-timers mongo-backup.timer
sudo du -sh /var/backups/mongodb

# Aggiornare MongoDB (patch della 8.0)
sudo /usr/local/bin/mongo-backup.sh && sudo docker compose pull && sudo docker compose up -d

# Spazio su disco
df -h /

# Serve un riavvio?
ls /var/run/reboot-required
```

**Dal tuo PC:**

```powershell
# Collegarsi alla VM
ssh -i C:\percorso\della\chiave.pem azureuser@<IP_PUBBLICO_VM>

# Aprire il tunnel verso MongoDB (con il file ~/.ssh/config configurato)
ssh -N mongo-azure

# Verificare che la porta sia raggiungibile (accesso diretto)
Test-NetConnection <IP_PUBBLICO_VM> -Port 27017
```

---

## Le 7 regole d'oro

1. **Guarda sempre il prompt** prima di lanciare un comando: sei sul tuo PC o sulla VM?
2. **Non incollare mai password** in chat, email o ticket. Se succede, cambiala subito.
3. **Mai `docker compose down -v`** su un database con dati: cancella tutto.
4. **Mai pubblicare MongoDB su `0.0.0.0`** e mai regole NSG con origine "Any".
5. **Incolla i blocchi `<< 'EOF'` per intero**, fino alla riga `EOF`.
6. **Prima di ogni modifica importante, fai un backup:** `sudo /usr/local/bin/mongo-backup.sh`.
7. **Un backup non provato non è un backup:** esegui la prova di ripristino (Parte 10.3).
