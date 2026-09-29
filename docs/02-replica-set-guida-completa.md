# Replica set MongoDB in Docker — Guida completa passo passo

**Per chi è questa guida:** per chi ha seguito le guide 00 e 01 e vuole imparare a costruire, usare, proteggere e mantenere un **replica set** MongoDB. Come nelle guide precedenti, ogni passaggio spiega **cosa fare**, **cosa fa il comando** e **cosa devi vedere**. In più, ogni scelta tecnica è accompagnata da un riquadro 🧭 che ne spiega il motivo e come si traduce in produzione.

**Cosa otterrai alla fine:**

- un replica set di tre nodi, con elezione automatica del primario e failover;
- nodi raggiungibili dal tuo PC con un nome DNS, e il driver che segue il primario anche durante i guasti;
- connessioni cifrate con TLS, sia dai client ai nodi sia tra i nodi stessi, attivate senza mai fermare il servizio;
- un utente applicativo, backup automatici coerenti presi da un secondario, e una procedura di ripristino collaudata;
- la procedura di manutenzione a rotazione, per riavviare o aggiornare i nodi senza interruzioni.

**Tempo stimato:** 2–3 ore.

**Prerequisiti:** guida 00 completata (Docker, impostazioni del kernel) e guida 01 completata (la CA privata in `~/mongodb/tls`, riusata qui per il TLS).

**Stato di verifica:** tutti i passaggi sono stati eseguiti e collaudati su un'installazione reale, tranne quelli segnati con 🧪 (cambio password, smantellamento del laboratorio, retention settimanale/mensile su un periodo reale).

> 📖 **Comandi e simboli** (`sudo`, `chmod`, `|`, `<< EOF`, `docker compose`…): la [legenda dei comandi](legenda-comandi-linux.md) spiega tutto ciò che compare in questa guida.

---

## Indice

- [Parte 0 — Concetti](#parte-0--concetti)
- [Parte 1 — Il laboratorio e lo scenario reale](#parte-1--il-laboratorio-e-lo-scenario-reale)
- [Parte 2 — Preparazione](#parte-2--preparazione)
- [Parte 3 — Costruire i tre nodi](#parte-3--costruire-i-tre-nodi)
- [Parte 4 — Formare il replica set](#parte-4--formare-il-replica-set)
- [Parte 5 — Usare il replica set](#parte-5--usare-il-replica-set)
- [Parte 6 — Il failover](#parte-6--il-failover)
- [Parte 7 — Accesso dal tuo PC](#parte-7--accesso-dal-tuo-pc)
- [Parte 8 — TLS senza fermare il servizio](#parte-8--tls-senza-fermare-il-servizio)
- [Parte 9 — Utente applicativo](#parte-9--utente-applicativo)
- [Parte 10 — Backup e ripristino](#parte-10--backup-e-ripristino)
- [Parte 11 — Manutenzione a rotazione](#parte-11--manutenzione-a-rotazione)
- [Parte 12 — Cambiare una password](#parte-12--cambiare-una-password)
- [Parte 13 — Quando qualcosa va storto](#parte-13--quando-qualcosa-va-storto)
- [Parte 14 — Laboratorio e produzione](#parte-14--laboratorio-e-produzione)
- [Parte 15 — Smantellare il laboratorio](#parte-15--smantellare-il-laboratorio)
- [Appendice A — Dove si trova ogni cosa](#appendice-a--dove-si-trova-ogni-cosa)
- [Appendice B — Promemoria dei comandi](#appendice-b--promemoria-dei-comandi)
- [Le 8 regole d'oro del replica set](#le-8-regole-doro-del-replica-set)

> **Convenzioni:** valgono quelle delle guide 00 e 01 (📍 dove eseguire, ✅ cosa devi vedere, blocchi `<< EOF` da incollare per intero, segnaposto `<...>` da sostituire togliendo anche `<` e `>`). Utente della VM d'esempio: `azureuser`. Segnaposto specifici di questa guida: `<FQDN>` (nome DNS della VM, Parte 2.2), `<IP_PRIVATO_VM>` (es. `10.0.0.4`).

> **I riquadri 🧭** spiegano ogni scelta con la stessa struttura: **perché** la facciamo, **se non lo fai** cosa succede (spesso con quello che è successo davvero durante il collaudo), **alternative**, **in produzione**.

---

## Parte 0 — Concetti

### 0.1 Cos'è un replica set

Un **replica set** è un gruppo di server MongoDB, di solito tre, che contengono **gli stessi dati**.

- Uno solo di loro è il **primario**: riceve tutte le scritture.
- Gli altri sono **secondari**: copiano continuamente dal primario ogni modifica, leggendola da un registro delle operazioni chiamato **oplog**.
- I nodi si scambiano di continuo un segnale di vita, l'**heartbeat**.

Se il primario si guasta, gli altri se ne accorgono ed **eleggono un nuovo primario** tra i secondari, di solito in pochi secondi: è il **failover** automatico. Quando il vecchio primario torna, rientra come secondario e si rimette in pari.

### 0.2 Maggioranza e numero dispari

Per eleggere un primario serve la **maggioranza** dei membri con diritto di voto. Con tre nodi ne bastano due: il sistema sopravvive alla perdita di uno qualunque.

Per questo si usa un numero **dispari** di nodi. Con due, se uno cade l'altro da solo non ha la maggioranza: nessun primario, niente scritture. Con quattro si sopravvive comunque alla perdita di uno solo, come con tre, pagando un server in più.

> Esiste anche l'*arbitro*, un membro che vota ma non contiene dati, per raggiungere un numero dispari risparmiando. È sconsigliato nelle configurazioni moderne perché indebolisce le garanzie sulle scritture: meglio tre nodi completi.

### 0.3 Come si collega un'applicazione

L'applicazione non si collega a un nodo preciso, ma all'intero replica set: nella stringa di connessione elenca i nodi e il nome del replica set.

```
mongodb://utente:password@nodo1:27017,nodo2:27017,nodo3:27017/?replicaSet=rs0
```

Il driver si collega a uno qualunque di quegli indirizzi, chiede com'è fatto il gruppo, riceve l'elenco dei membri **con i nomi con cui sono registrati**, individua il primario e ci manda le scritture. Se il primario cambia, il driver lo segue da solo: l'applicazione non cambia nulla.

Due concetti legati alla stringa di connessione:

- **Write concern:** quando considerare confermata una scrittura. Da MongoDB 5.0 il valore predefinito è `majority`: la conferma arriva quando la **maggioranza** dei nodi ha ricevuto il dato. Una scrittura confermata sopravvive quindi alla perdita del primario.
- **Read preference:** da quale nodo leggere. Il predefinito è `primary`. Con `secondary` o `secondaryPreferred` si legge dai secondari, alleggerendo il primario, accettando che i dati possano essere leggermente indietro.

### 0.4 A cosa serve

- **Alta disponibilità:** il database resta in piedi anche se un server si guasta o va riavviato.
- **Manutenzione senza interruzioni:** aggiornamenti e riavvii un nodo alla volta.
- **Più copie dei dati** su server diversi.
- **Funzionalità in più:** le transazioni su più documenti e i *change streams* (notifiche in tempo reale delle modifiche) richiedono un replica set; con un'istanza singola come quella della guida 00 non sono disponibili.

### 0.5 Cosa NON è

**Il replica set non è un backup.** Se qualcuno cancella una collezione, la cancellazione viene replicata in un istante su tutti i nodi. Lo vedremo con i nostri occhi nella Parte 10. I backup restano indispensabili.

### 0.6 Replica set e sharding

| | Replica set | Sharding |
|---|---|---|
| Cosa fa | **Copia** gli stessi dati su più server | **Divide** dati diversi tra più server |
| Risolve | Guasti, manutenzione, disponibilità | Troppi dati o troppe scritture per un server |
| Server minimi in produzione | 3 | Circa 10 (2 shard × 3, 3 config server, router) |
| Quando serve | Quasi sempre, in produzione | Solo con volumi molto grandi |

In un cluster con sharding, **ogni shard è a sua volta un replica set**, e lo sono anche i config server: questa guida è il prerequisito della guida 03 sullo sharding.

---

## Parte 1 — Il laboratorio e lo scenario reale

### 1.1 Cosa costruiremo

Tre container sulla stessa VM, ciascuno nel ruolo di un server distinto:

| Container | Porta (dentro e fuori) | Membro registrato come | Ruolo |
|---|---|---|---|
| `mongo-rs1` | 27101 | `<FQDN>:27101` | Primario preferito |
| `mongo-rs2` | 27102 | `<FQDN>:27102` | Secondario |
| `mongo-rs3` | 27103 | `<FQDN>:27103` | Secondario |

> 🧭 **Scelta — Un laboratorio su una sola VM, con un container per nodo**
>
> **Perché:** riproduce fedelmente configurazione, comandi, autenticazione tra i nodi, elezioni, failover e TLS, a costo zero e riusando la VM delle guide precedenti.
>
> **Cosa non simula:** tutti i nodi condividono disco, RAM e macchina. Se la VM si ferma, cade l'intero replica set: l'alta disponibilità è solo dimostrativa. Mancano anche la latenza di rete reale e i guasti di rete parziali.
>
> **Alternative:** una nuova VM dedicata al laboratorio (più isolamento, un costo in più); il PC con Docker Desktop (costo zero, ma lontano dallo scenario Azure).
>
> **In produzione:** tre VM distinte, idealmente in **zone di disponibilità diverse**, ciascuna con il proprio disco. Ogni nodo usa la porta standard 27017 e ha un proprio nome DNS.

### 1.2 Convivere con il MongoDB di sviluppo

Sulla stessa VM gira il MongoDB delle guide 00 e 01, in `~/mongodb`. Regole per non disturbarlo:

- una cartella separata, `~/mongo-lab/02-replica-set`;
- porte diverse (27101–27103);
- un progetto Docker Compose con nome proprio, quindi rete e volumi separati;
- memoria limitata per ogni nodo del laboratorio.

> ⚠️ **La regola più importante di questa guida.** I comandi `docker compose` agiscono sul progetto **della cartella in cui ti trovi**. Da ora sulla VM ce ne sono due: `~/mongodb` (il tuo database di sviluppo) e `~/mongo-lab/02-replica-set` (il laboratorio). **Guarda il prompt prima di ogni comando `docker compose`**: un `down -v` nella cartella sbagliata cancellerebbe i dati di sviluppo.

---

## Parte 2 — Preparazione

### 2.1 Controllare le risorse

> 📍 **Sulla VM.**

```bash
free -h
nproc
df -h /
sudo docker stats --no-stream
```

Per il replica set di questa guida servono circa 2–3 GB di RAM liberi. Durante il collaudo la VM aveva 7,8 GB di RAM, 2 CPU e **nessuno swap**: quest'ultimo dettaglio è importante, perché senza swap, se la memoria finisce, Linux termina d'autorità qualche processo. Per questo limiteremo la memoria di ogni nodo (Parte 3.4).

### 2.2 Assegnare un nome DNS alla VM

Nella Parte 7 ci collegheremo al replica set dal PC. Come vedremo, per farlo i membri devono essere registrati con un **nome risolvibile anche dal PC**, e conviene sceglierlo **prima** di creare il replica set.

> 📍 **Nel portale Azure.**

Apri la risorsa **Indirizzo IP pubblico** collegata alla VM (dalla *Panoramica* della VM, clic sull'indirizzo IP) → *Configurazione* → **Etichetta nome DNS**. Scegli un nome univoco (per esempio il nome della VM) e salva. Sotto compare il nome completo, del tipo `nome.<regione>.cloudapp.azure.com`: è il tuo `<FQDN>`.

> 📍 **Dal PC**, in PowerShell:

```powershell
Resolve-DnsName <FQDN>
```

✅ Deve rispondere con l'IP pubblico della VM. La propagazione può richiedere qualche minuto.

### 2.3 Le variabili della sessione

Molti comandi di questa guida usano il nome DNS e l'IP privato. Per non riscriverli, li mettiamo in due variabili.

> 📍 **Sulla VM:**

```bash
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1      # mostra l'IP privato
FQDN=<FQDN>
PRIV_IP=<IP_PRIVATO_VM>
echo "Nome DNS: $FQDN - IP privato: $PRIV_IP"
```

✅ La riga stampata deve mostrare i valori veri.

> ⚠️ **Le variabili vivono solo nella sessione corrente.** Se chiudi il terminale o ti ricolleghi alla VM, ripeti questi comandi prima di proseguire. Lo stesso varrà per la funzione `rs_eval` (Parte 4.3).

---

## Parte 3 — Costruire i tre nodi

> 📍 **Sulla VM.**

### 3.1 Cartella, password e keyFile

```bash
mkdir -p ~/mongo-lab/02-replica-set
cd ~/mongo-lab/02-replica-set

# Password dell'amministratore
openssl rand -base64 24 | tr -d '/+=' | sudo tee root_password.txt > /dev/null
sudo chown 999:999 root_password.txt && sudo chmod 600 root_password.txt

# keyFile: la "parola d'ordine" condivisa tra i nodi
openssl rand -base64 756 > keyfile
sudo chown 999:999 keyfile && sudo chmod 400 keyfile
ls -l
```

✅ `keyfile` con `-r--------` e `root_password.txt` con `-rw-------`, entrambi di proprietà `999` (il gruppo `systemd-journal` che compare accanto è una coincidenza di numerazione, innocua).

> 🧭 **Scelta — Il keyFile per l'autenticazione interna**
>
> **Cos'è:** un file segreto identico su tutti i nodi, con cui i membri si riconoscono tra loro. Un processo che non lo possiede non può unirsi al replica set né ricevere i dati replicati. Attiva anche l'obbligo di autenticazione per i client.
>
> **Perché i permessi `400`:** MongoDB si rifiuta di partire se il keyFile è leggibile da altri utenti. L'owner 999 è l'utente con cui MongoDB gira nei container.
>
> **Se non lo fai:** con l'autenticazione degli utenti attiva, MongoDB non accetta un replica set senza autenticazione interna.
>
> **Alternative:** certificati x.509 per autenticare i membri (Parte 14.3).
>
> **In produzione:** lo stesso keyFile, distribuito in modo sicuro su ogni server, oppure x.509.

### 3.2 Il docker-compose.yml

Il file è lungo: per evitare che si rovini durante l'incolla (è successo durante il collaudo), lo scriviamo in **due parti**. La prima (`cat >`) crea il file, la seconda (`cat >>`) lo completa. Entrambe usano `<< EOF` **senza apici**, così `$FQDN` e `$PRIV_IP` vengono sostituiti con i valori veri: controlla prima che le variabili siano impostate (Parte 2.3).

**Parte A** — impostazioni comuni e nodo 1:

```bash
cat > docker-compose.yml << EOF
name: mongo-lab-rs

x-mongo-common: &mongo-common
  image: mongo:8.0
  restart: unless-stopped
  stop_grace_period: 1m
  extra_hosts:
    - "$FQDN:$PRIV_IP"
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
    command: ["--replSet", "rs0", "--port", "27101", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25"]
    ports:
      - "127.0.0.1:27101:27101"
      - "$PRIV_IP:27101:27101"
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD_FILE: /run/secrets/rs_root_password
    secrets:
      - rs_root_password
    volumes:
      - rs1-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro
EOF
```

**Parte B** — nodi 2 e 3, volumi e secret (nota il `>>`, che **accoda**):

```bash
cat >> docker-compose.yml << EOF

  mongo-rs2:
    <<: *mongo-common
    container_name: mongo-rs2
    hostname: mongo-rs2
    command: ["--replSet", "rs0", "--port", "27102", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25"]
    ports:
      - "127.0.0.1:27102:27102"
      - "$PRIV_IP:27102:27102"
    volumes:
      - rs2-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

  mongo-rs3:
    <<: *mongo-common
    container_name: mongo-rs3
    hostname: mongo-rs3
    command: ["--replSet", "rs0", "--port", "27103", "--keyFile", "/etc/mongo/keyfile", "--wiredTigerCacheSizeGB", "0.25"]
    ports:
      - "127.0.0.1:27103:27103"
      - "$PRIV_IP:27103:27103"
    volumes:
      - rs3-data:/data/db
      - ./keyfile:/etc/mongo/keyfile:ro

volumes:
  rs1-data:
  rs2-data:
  rs3-data:

secrets:
  rs_root_password:
    file: ./root_password.txt
EOF
```

**Verifica:**

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose config --services
sudo docker compose config --volumes
grep -A1 "extra_hosts" docker-compose.yml
```

✅ `compose valido`, i tre servizi `mongo-rs1`, `mongo-rs2`, `mongo-rs3`, i tre volumi, e sotto `extra_hosts` il tuo nome DNS con l'IP privato (valori veri, non `$FQDN`).

> ⚠️ `compose valido` da solo non basta: durante il collaudo un file rovinato dall'incolla ha superato quel controllo pur essendo incompleto. I controlli su servizi e volumi sono quelli che contano. In alternativa all'incolla, puoi sempre usare l'editor: `nano docker-compose.yml`, incolli, **Ctrl+O** e Invio, **Ctrl+X**.

### 3.3 Cosa significa ogni parte

| Elemento | Significato |
|---|---|
| `name: mongo-lab-rs` | Nome del progetto: rete e volumi hanno questo prefisso, separati da quelli di sviluppo |
| `x-mongo-common` / `<<: *mongo-common` | Impostazioni comuni scritte una volta e applicate ai tre nodi |
| `stop_grace_period: 1m` | Tempo concesso a MongoDB per spegnersi in modo ordinato (Parte 6.3) |
| `extra_hosts` | Dentro i container, il nome DNS punta all'IP privato della VM (Parte 7.2) |
| `mem_limit: 1g` | Tetto di memoria per nodo |
| `--replSet rs0` | Il nodo fa parte del replica set `rs0` |
| `--port 2710x` | Porta propria di ogni nodo, uguale dentro e fuori dal container |
| `--keyFile` | Autenticazione interna (Parte 3.1) |
| `--wiredTigerCacheSizeGB 0.25` | Cache di 256 MB per nodo, invece di metà della RAM |
| Porte su `127.0.0.1` e `$PRIV_IP` | Raggiungibili dalla VM e, attraverso l'IP privato, dall'esterno (Parte 7) |
| `MONGO_INITDB_*` solo sul nodo 1 | L'utente `admin` viene creato solo lì |

> 🧭 **Scelta — Porta propria per ogni nodo, uguale dentro e fuori**
>
> **Perché:** i client ricevono dal replica set l'elenco dei membri **con gli indirizzi registrati**, e poi si collegano a quelli. Se tutti i nodi ascoltassero su 27017 dentro il container e su porte diverse solo all'esterno, gli indirizzi registrati non sarebbero raggiungibili da fuori.
>
> **Se non lo fai:** il client esterno si collega al primo nodo ma fallisce subito dopo, quando tenta gli indirizzi ricevuti.
>
> **In produzione:** ogni nodo è un server diverso con il proprio nome, quindi tutti possono usare la porta standard 27017.

> 🧭 **Scelta — Utente admin creato solo sul nodo 1**
>
> **Perché:** i nodi 2 e 3 partono vuoti; quando formeremo il replica set, copieranno tutto dal nodo 1 (*sincronizzazione iniziale*), utente compreso.
>
> **Se non lo fai:** tre database indipendenti, ciascuno con il proprio admin, da riconciliare.
>
> **Conseguenza da ricordare:** il file della password è montato solo nel container del nodo 1. Quando servirà la password negli altri container, la passeremo dall'esterno (Parte 10).

> 🧭 **Scelta — Cache ridotta e tetto di memoria**
>
> **Perché:** di default ogni nodo userebbe circa metà della RAM per la cache. Tre nodi più l'istanza di sviluppo, su una VM senza swap, rischierebbero di esaurire la memoria.
>
> **In produzione:** nessun limite artificiale: ogni nodo ha la sua VM e usa la cache predefinita.

### 3.4 Avvio

Controlla che il prompt mostri `~/mongo-lab/02-replica-set`, poi:

```bash
sudo docker compose up -d
sudo docker compose ps
sleep 15
sudo docker compose logs mongo-rs1 | grep -E "init process complete|Waiting for connections" | head -3
sudo docker compose logs mongo-rs2 | grep -iE "replica set config|Waiting for connections" | head -3
```

✅ **Cosa aspettarsi:**

- tre container `Up`;
- sul nodo 1: un primo `Waiting for connections` sulla porta **27017**, poi `MongoDB init process complete`, poi `Waiting for connections` sulla porta **27101**. Il nodo si è avviato prima in modalità temporanea per creare l'utente `admin`, poi in modo definitivo sulla sua porta;
- sul nodo 2: `Did not find local replica set configuration document at startup`. **È normale:** il nodo sa di far parte di `rs0`, ma nessuno gli ha ancora detto chi sono gli altri membri.

---

## Parte 4 — Formare il replica set

> 📍 **Sulla VM**, nella cartella del laboratorio.

### 4.1 `rs.initiate`

Il comando si lancia **una sola volta, su un solo nodo**: la configurazione viene propagata agli altri. Ti chiederà la password di `admin` (`sudo cat root_password.txt`):

```bash
sudo docker exec -it mongo-rs1 mongosh --port 27101 -u admin -p --authenticationDatabase admin --quiet --eval "
rs.initiate({
  _id: 'rs0',
  members: [
    { _id: 0, host: '$FQDN:27101', priority: 2 },
    { _id: 1, host: '$FQDN:27102' },
    { _id: 2, host: '$FQDN:27103' }
  ]
})"
```

Il JavaScript è tra virgolette doppie, così la shell sostituisce `$FQDN` con il nome vero.

✅ **Risposta attesa:** `{ ok: 1 }`. Un `Authentication failed` significa solo password errata: riprova.

**Cosa succede ora:** i nodi 2 e 3 copiano tutti i dati dal nodo 1 (sincronizzazione iniziale). Con un database vuoto bastano pochi secondi.

> 🧭 **Scelta — I membri registrati con il nome DNS**
>
> **Perché:** i client esterni potranno risolvere e raggiungere gli stessi nomi (Parte 7). Ogni nodo riconosce se stesso raggiungendo la propria porta attraverso l'IP privato e il proxy di Docker, grazie a `extra_hosts`: durante il collaudo `rs.initiate` ha funzionato senza problemi.
>
> **Se non lo fai:** registrando i membri con i nomi dei container (`mongo-rs1:27101`…), tutto funziona dall'interno della VM, ma dal PC il driver riceverebbe nomi che non sa risolvere.
>
> **In produzione:** i nomi si scelgono **prima** di creare il replica set. Cambiarli dopo è possibile (`rs.reconfig`, un membro alla volta), ma delicato.

> 🧭 **Scelta — `priority: 2` sul nodo 1**
>
> **Perché:** rende prevedibile chi è primario e permette di osservare il "rientro" del ruolo dopo un guasto (Parte 6).
>
> **In produzione:** serve a tenere il primario nella zona o nel data center più vicino all'applicazione. Ricorda che ogni ripresa del ruolo è una breve elezione.

### 4.2 Verificare lo stato

Aspetta una decina di secondi:

```bash
sudo docker exec -it mongo-rs1 mongosh --port 27101 -u admin -p --authenticationDatabase admin --quiet \
  --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr, "salute:", m.health))'
```

✅ **Atteso:** `<FQDN>:27101 PRIMARY`, `<FQDN>:27102 SECONDARY`, `<FQDN>:27103 SECONDARY`, tutti con salute `1`. Se vedi `STARTUP2`, la sincronizzazione è in corso: riprova dopo qualche secondo.

**La prova della replica:** l'utente `admin` era stato creato solo sul nodo 1. Collegati al nodo 2:

```bash
sudo docker exec -it mongo-rs2 mongosh --port 27102 -u admin -p --authenticationDatabase admin --quiet \
  --eval 'print("Sono il primario?", db.hello().isWritablePrimary)'
```

✅ Se il login riesce e la risposta è `Sono il primario? false`, l'utente è arrivato per replica e il nodo 2 è un secondario.

### 4.3 Una scorciatoia per il laboratorio

Per non digitare la password a ogni comando, definiamo una funzione che la legge dal file:

```bash
rs_eval() {
  local node=${2:-1}
  sudo docker exec -i -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs$node \
    sh -c 'mongosh --port 2710'"$node"' -u admin -p "$RS_PWD" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

Uso: `rs_eval 'comando'` esegue sul nodo 1, `rs_eval 'comando' 3` sul nodo 3.

> 🧭 **Scelta — La funzione `rs_eval` (solo laboratorio)**
>
> **Perché:** comodità. **Limite:** passa la password in un modo che la rende visibile per un istante ai processi del container: non usarla in produzione.
>
> **Da ricordare:** esiste solo nella sessione corrente (in una nuova sessione: `rs_eval: command not found`, va ridefinita). Senza numero interroga il nodo 1: se il nodo 1 è spento risponde `container ... is not running`, e bisogna usare `rs_eval '...' 2`. Dopo l'attivazione del TLS andrà aggiornata (Parte 8.4).

---

## Parte 5 — Usare il replica set

### 5.1 Scrivere attraverso il replica set

Ci colleghiamo come farebbe un'applicazione: con una stringa che elenca tutti i membri e il nome del replica set.

```bash
sudo docker exec -i -e FQDN="$FQDN" -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs1 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/labdb?replicaSet=rs0&authSource=admin" --quiet --eval "
    print(\"Primario trovato dal driver:\", db.hello().primary);
    printjson(db.prova.insertOne({ msg: \"ciao dal replica set\", quando: new Date() }));
  "'
```

✅ **Atteso:** `Primario trovato dal driver: <FQDN>:27101` e `acknowledged: true`. Il driver ha interrogato i membri, ha trovato da solo il primario e ha scritto lì. Con il write concern predefinito `majority`, quando arriva `acknowledged: true` il dato esiste già su almeno due nodi.

### 5.2 Leggere da un secondario

```bash
rs_eval 'db.getMongo().setReadPref("secondary"); printjson(db.getSiblingDB("labdb").prova.find().toArray())' 3
```

✅ Compare il documento appena scritto: la replica funziona. `setReadPref("secondary")` serve perché, di default, si legge dal primario.

### 5.3 Scrivere su un secondario

```bash
rs_eval 'db.getSiblingDB("labdb").prova.insertOne({ msg: "scrittura sul secondario" })' 3
```

✅ **Deve fallire** con `MongoServerError: not primary`: solo il primario accetta scritture.

---

## Parte 6 — Il failover

> ⚠️ Controlla che il prompt mostri `~/mongo-lab/02-replica-set`: il comando seguente, in `~/mongodb`, fermerebbe il database di sviluppo.

### 6.1 Spegnere il primario

```bash
sudo docker compose stop mongo-rs1
```

Dopo una decina di secondi, interroga il nodo 2 (il nodo 1 è spento):

```bash
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ **Atteso:** `<FQDN>:27101 (not reachable/healthy)` e uno tra i nodi 2 e 3 diventato **PRIMARY**. I due nodi rimasti sono la maggioranza, quindi hanno potuto eleggerne uno.

**L'applicazione se ne accorge?** Stessa stringa di prima, lanciata dal nodo 2:

```bash
sudo docker exec -i -e FQDN="$FQDN" -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs2 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/labdb?replicaSet=rs0&authSource=admin" --quiet --eval "
    print(\"Primario trovato dal driver:\", db.hello().primary);
    printjson(db.prova.insertOne({ msg: \"scritto durante il guasto\", quando: new Date() }));
  "'
```

✅ Il driver trova il **nuovo** primario e la scrittura riesce, senza cambiare nulla nella stringa di connessione.

### 6.2 Il rientro

```bash
sudo docker compose start mongo-rs1
```

Lancia due volte, subito e dopo circa 30 secondi:

```bash
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ Alla prima lettura il nodo 1 è **SECONDARY**: rientra e recupera le scritture perse. Alla seconda è di nuovo **PRIMARY**, grazie alla `priority: 2`.

**Nessun dato perso:**

```bash
rs_eval 'printjson(db.getSiblingDB("labdb").prova.find({}, { _id: 0, msg: 1 }).toArray())'
```

✅ Entrambi i documenti: `ciao dal replica set` e `scritto durante il guasto`.

### 6.3 Lo spegnimento ordinato e `stop_grace_period`

Quando un primario riceve la richiesta di spegnersi, cede subito il ruolo ed entra in una fase di **quiesce**: resta acceso come secondario per un po', fino a circa **15 secondi**, per dare ai client il tempo di spostarsi sul nuovo primario. Poi si chiude in modo ordinato.

Verifica che lo spegnimento sia stato pulito:

```bash
sudo docker compose logs mongo-rs1 | grep -o '"Startup from clean shutdown?":[a-z]*' | tail -1
```

✅ `"Startup from clean shutdown?":true`. Lo stop del primario dura circa 16 secondi.

> 🧭 **Scelta — `stop_grace_period: 1m`**
>
> **Perché:** Docker, per impostazione predefinita, aspetta solo **10 secondi** e poi termina il container d'autorità.
>
> **Se non lo fai — cosa è successo nel collaudo:** senza questa opzione lo stop del primario è durato **11 secondi** (i 10 di attesa più la terminazione forzata); subito dopo il nodo risultava ancora `SECONDARY`, perché era in quiesce; e al riavvio i log riportavano `"Startup from clean shutdown?":false`. Per MongoDB è come un'interruzione di corrente: nessun dato perso grazie al journal, ma un recupero all'avvio. Con l'opzione: stop in circa 16 secondi e `true`.
>
> **In produzione:** vale per qualunque MongoDB in container. Per questo `stop_grace_period` è stato aggiunto anche ai compose delle guide 00 e 01.

> **Guasto improvviso vs spegnimento ordinato.** Con `docker compose stop` il primario avvisa gli altri e l'elezione è quasi istantanea. Con un guasto vero (crash, VM bloccata) i secondari se ne accorgono solo quando smettono di ricevere l'heartbeat, per impostazione predefinita dopo circa 10 secondi: in quell'intervallo le scritture restano in attesa.

---

## Parte 7 — Accesso dal tuo PC

### 7.1 Il problema

Potrebbe sembrare che basti mettere l'IP pubblico della VM nella stringa di connessione. Non è così:

1. il client si collega all'indirizzo che gli dai;
2. il server gli risponde con l'elenco dei membri **come sono registrati**;
3. da quel momento il client usa **quei nomi**, non l'indirizzo iniziale.

Il PC deve quindi saper risolvere e raggiungere i nomi dei membri.

| Alternativa | Come | Pro | Contro |
|---|---|---|---|
| Connessione diretta a un nodo | `directConnection=true` e IP pubblico | Nessuna configurazione | Niente failover; scritture solo se quel nodo è primario |
| File `hosts` sul PC | I nomi dei membri puntati all'IP della VM | Semplice | Da modificare su ogni client |
| Membri registrati con l'IP pubblico | IP pubblico in `rs.initiate` | Nessun DNS | Anche i nodi si parlerebbero passando dall'esterno: fragile |
| **Nome DNS** (scelta) | Nome DNS Azure + `extra_hosts` | Nessuna modifica ai client, come in produzione | Richiede un nome DNS pubblico |

### 7.2 Come funziona la soluzione scelta

Il nome `<FQDN>` è lo stesso per tutti, ma si risolve in modo diverso a seconda di chi lo cerca:

- **dal PC:** il DNS pubblico lo risolve nell'**IP pubblico** → l'NSG di Azure lascia passare → la connessione arriva all'**IP privato** della VM → Docker la inoltra al nodo giusto in base alla **porta**;
- **dentro i container:** `extra_hosts` lo fa puntare direttamente all'**IP privato**, così i nodi si parlano restando dentro la VM.

Client e nodi usano gli stessi nomi, esattamente come in produzione con un DNS aziendale. Per questo, nella Parte 3, abbiamo pubblicato le porte anche sull'IP privato.

### 7.3 La regola NSG

> 📍 **Nel portale Azure:** VM → *Rete* → *Crea regola porta* → *Regola porta in ingresso*.

| Campo | Valore |
|---|---|
| Origine | *Indirizzi IP* |
| Indirizzi IP di origine | il tuo IP pubblico (cerca "what is my ip" dal browser del PC) |
| Intervalli di porte di destinazione | `27101-27103` |
| Protocollo | TCP |
| Azione | Consenti |
| Nome | `mongo-lab-rs` |

> ⚠️ **Mai "Any" come origine.** Fino alla Parte 8 il traffico del laboratorio viaggia in chiaro, password compresa.

### 7.4 Verifica dal PC

> 📍 **Dal PC**, in PowerShell:

```powershell
27101..27103 | ForEach-Object { Test-NetConnection <FQDN> -Port $_ | Select-Object RemotePort, TcpTestSucceeded }
```

✅ Tre volte `True`. Se qualcuna è `False`: controlla la regola NSG e che `sudo ss -ltnp | grep 2710` sulla VM mostri le porte anche sull'IP privato.

### 7.5 Collegarsi da VS Code

Estensione MongoDB for VS Code → **Ctrl+Shift+P** → *MongoDB: Connect with Connection String*:

```
mongodb://admin:PASSWORD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/?replicaSet=rs0&authSource=admin
```

✅ Si collega e mostra `labdb`.

> ⚠️ **La stringa di connessione si incolla nel client, non nel terminale della VM.** Durante il collaudo è finita per errore in bash: il carattere `&` ha mandato il comando in background (`[1] 12022`, poi `No such file or directory`). Nessun danno, ma la riga, password compresa, resta nella cronologia. Per toglierla: `history | grep "mongodb://"` e poi `history -d <numero>`.

**La prova più bella:** con VS Code collegato, spegni il primario dalla VM (`sudo docker compose stop mongo-rs1`), aspetta una ventina di secondi e inserisci un documento da VS Code: funziona, perché il driver è passato al nuovo primario. Poi `sudo docker compose start mongo-rs1`.

> 🧭 **In produzione**, file `hosts` e nome DNS pubblico non servono: ogni nodo ha un nome DNS aziendale nella rete privata, e i client sono nella stessa rete. Se client esterni e interni devono vedere indirizzi diversi, MongoDB offre gli **horizons**, che richiedono il TLS.

---

## Parte 8 — TLS senza fermare il servizio

### 8.1 Cosa proteggere

Su un replica set ci sono **due tratti** da cifrare:

- **dai client ai nodi**, come nella guida 01;
- **tra i nodi**: replica dei dati e heartbeat.

Lo faremo **senza mai fermare il replica set**, passando per tre modalità:

| Modalità | Accetta in ingresso | Usa verso gli altri nodi |
|---|---|---|
| `allowTLS` | cifrato e in chiaro | in chiaro |
| `preferTLS` | cifrato e in chiaro | cifrato |
| `requireTLS` | solo cifrato | cifrato |

Le fasi: certificato → riavvio a rotazione in `allowTLS` → passaggio a caldo a `preferTLS` e spostamento dei client → passaggio a caldo a `requireTLS` → configurazione resa permanente.

### 8.2 Il certificato dei nodi

> 📍 **Sulla VM** (con `$FQDN` e `$PRIV_IP` impostati).

```bash
cd ~/mongo-lab/02-replica-set
mkdir -p tls && chmod 700 tls && cd tls

cat > server.ext << EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=DNS:$FQDN,DNS:localhost,DNS:mongo-rs1,DNS:mongo-rs2,DNS:mongo-rs3,IP:127.0.0.1,IP:$PRIV_IP
EOF
cat server.ext
```

✅ L'ultima riga contiene i valori veri.

Genera e firma il certificato con la **CA della guida 01**:

```bash
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=$FQDN" -out server.csr
openssl x509 -req -in server.csr -CA ~/mongodb/tls/ca.pem -CAkey ~/mongodb/tls/ca.key \
  -CAserial ~/mongodb/tls/ca.srl -days 825 -sha256 -extfile server.ext -out server.crt
rm server.csr
cp ~/mongodb/tls/ca.pem .
openssl verify -CAfile ca.pem server.crt
openssl x509 -in server.crt -noout -ext subjectAltName,extendedKeyUsage
```

✅ `server.crt: OK`, i nomi del SAN e la riga `TLS Web Server Authentication, TLS Web Client Authentication`.

> Se hai scelto di non tenere `ca.key` sulla VM (guida 01, Parte 5.2), riportala temporaneamente in `~/mongodb/tls` per questa firma, poi rimuovila di nuovo. Il contatore `ca.srl` avanza: aggiorna anche la copia sul PC.

File e permessi per MongoDB:

```bash
cat server.crt server.key | sudo tee server.pem > /dev/null
sudo chown 999:999 server.pem && sudo chmod 600 server.pem
chmod 600 server.key && chmod 644 ca.pem server.crt
ls -l
cd ..
```

> 🧭 **Scelta — CA riusata, un certificato, uso client e server**
>
> **Perché la stessa CA della guida 01:** il `ca.pem` è già sul PC e i client sanno già usarlo; in produzione è normale un'unica CA per tutti i server.
>
> **Perché un solo certificato:** nel laboratorio i tre nodi condividono lo stesso nome DNS.
>
> **Perché `clientAuth` — il dettaglio più importante:** quando un nodo si collega a un altro per replicare, si comporta da **client** e presenta lo stesso certificato. Con il solo `serverAuth` l'altro nodo lo rifiuterebbe e la replica si interromperebbe. È la causa più frequente di problemi con il TLS sui replica set.
>
> **In produzione:** un certificato per server, con il suo nome nel SAN, dalla CA aziendale.

### 8.3 Fase 1 — `allowTLS`, con riavvio a rotazione

Aggiorniamo il compose (con una copia di sicurezza per il rollback) aggiungendo a ogni nodo le opzioni TLS e i due file:

```bash
cd ~/mongo-lab/02-replica-set
cp docker-compose.yml docker-compose.yml.pre-tls
sed -i 's|"--wiredTigerCacheSizeGB", "0.25"\]|"--wiredTigerCacheSizeGB", "0.25", "--tlsMode", "allowTLS", "--tlsCertificateKeyFile", "/etc/mongo/tls/server.pem", "--tlsCAFile", "/etc/mongo/tls/ca.pem", "--tlsAllowConnectionsWithoutCertificates", "--tlsDisabledProtocols", "TLS1_0,TLS1_1"]|' docker-compose.yml
sed -i 's|^      - ./keyfile:/etc/mongo/keyfile:ro$|&\n      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro\n      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro|' docker-compose.yml
grep -c "allowTLS" docker-compose.yml
grep -c "server.pem:ro" docker-compose.yml
sudo docker compose config --quiet && echo "compose valido"
```

✅ `3`, `3`, `compose valido`. Le opzioni sono quelle della guida 01; `--tlsAllowConnectionsWithoutCertificates` resta indispensabile, altrimenti con una CA indicata MongoDB pretenderebbe un certificato da ogni client.

**Riavvio a rotazione.** `docker compose up -d <servizio>` ricrea **solo quel nodo** con la nuova configurazione. Prima i secondari, poi il primario dopo avergli fatto cedere il ruolo. **Un comando alla volta**, aspettando il prompt:

```bash
sudo docker compose up -d mongo-rs3
```

```bash
sleep 15; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

Quando il nodo 3 è `SECONDARY`:

```bash
sudo docker compose up -d mongo-rs2
```

```bash
sleep 15; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 3
```

Quando il nodo 2 è `SECONDARY`:

```bash
rs_eval 'rs.stepDown(60); print("fatto")'
```

```bash
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

Con il nodo 1 `SECONDARY`:

```bash
sudo docker compose up -d mongo-rs1
```

**Verifica** (dopo circa un minuto):

```bash
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
openssl s_client -connect 127.0.0.1:27101 -CAfile tls/ca.pem </dev/null 2>/dev/null | grep -E "Verify return code|Protocol"
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ Tre volte `allowTLS`, `Verify return code: 0 (ok)` con TLS 1.3, i tre membri sani. `rs_eval` e i client continuano a funzionare in chiaro: in questa fase è giusto così.

### 8.4 Fase 2 — `preferTLS` e spostamento dei client

Il cambio di modalità si fa **a caldo**, senza riavvii:

```bash
for n in 1 2 3; do rs_eval 'printjson(db.adminCommand({ setParameter: 1, tlsMode: "preferTLS" }).was)' $n; done
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
```

✅ Tre volte `allowTLS` (la modalità precedente), poi tre volte `preferTLS`.

> ⚠️ **Un parametro cambiato a caldo si perde al riavvio.** Un nodo che ripartisse ora tornerebbe alla modalità del compose (`allowTLS`): innocuo in questa fase, ma per questo alla fine aggiorneremo il compose.

**I nodi parlano tra loro in TLS?** Le connessioni di replica già aperte restano in chiaro finché non vengono rinnovate: forziamo un'elezione, poi leggiamo i contatori delle connessioni cifrate ricevute da ogni nodo.

```bash
rs_eval 'rs.stepDown(30); print("fatto")'
sleep 45
for n in 1 2 3; do rs_eval 'printjson(db.serverStatus().transportSecurity)' $n; done
```

✅ Su ogni nodo `'1.3'` maggiore di zero (nel collaudo: 18–21) e zero per le versioni più vecchie.

**Aggiorna `rs_eval`** perché usi il TLS:

```bash
rs_eval() {
  local node=${2:-1}
  sudo docker exec -i -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs$node \
    sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 2710'"$node"' -u admin -p "$RS_PWD" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

**Aggiorna VS Code** (il `ca.pem` è lo stesso della guida 01, già sul PC):

```
mongodb://admin:PASSWORD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/?replicaSet=rs0&authSource=admin&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

✅ Si collega. In questa fase **anche la vecchia connessione in chiaro funziona ancora**: è la finestra prevista per spostare i client uno alla volta.

> **Prima di proseguire**, assicurati che **tutti** i client usino il TLS: dal passo successivo le connessioni in chiaro saranno rifiutate.

### 8.5 Fase 3 — `requireTLS` e configurazione permanente

**Passaggio a caldo:**

```bash
for n in 1 2 3; do rs_eval 'printjson(db.adminCommand({ setParameter: 1, tlsMode: "requireTLS" }).was)' $n; done
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
```

✅ Tre volte `preferTLS`, poi tre volte `requireTLS`.

**La prova del contrario:**

```bash
sudo docker exec mongo-rs2 mongosh --port 27102 --quiet --eval 'db.runCommand({ ping: 1 })'
```

✅ **Deve fallire** con `MongoServerSelectionError: connection ... closed`. Anche la vecchia connessione di VS Code senza TLS smette di funzionare: puoi eliminarla.

**Rendere la modalità permanente** con un'ultima rotazione:

```bash
cp docker-compose.yml docker-compose.yml.allowtls
sed -i 's|"--tlsMode", "allowTLS"|"--tlsMode", "requireTLS"|' docker-compose.yml
grep -c "requireTLS" docker-compose.yml
sudo docker compose config --quiet && echo "compose valido"
```

Poi, un comando alla volta, la stessa rotazione della fase 1: `up -d mongo-rs3` → verifica → `up -d mongo-rs2` → verifica → `rs.stepDown(60)` → `up -d mongo-rs1`.

**Verifica finale** (dopo circa un minuto):

```bash
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ Tre volte `requireTLS`, ora letto dalla configurazione di avvio, e i tre membri sani. Il laboratorio è cifrato in ogni sua parte.

> 🧭 **Scelta — Migrazione in tre fasi**
>
> **Perché:** in ogni momento c'è un primario e i client continuano a lavorare; si spostano sul TLS uno alla volta durante `preferTLS`.
>
> **Se non lo fai:** passando direttamente a `requireTLS` con un riavvio, tutti i client non ancora aggiornati si bloccherebbero nello stesso istante.
>
> **In produzione:** stessa procedura, con una finestra `preferTLS` lunga quanto serve per aggiornare tutte le applicazioni.

**Tornare indietro**, se servisse: `cp docker-compose.yml.pre-tls docker-compose.yml` e rotazione dei tre nodi. 🧪 Questa procedura non è stata collaudata.

---

## Parte 9 — Utente applicativo

Come nella guida 00, le applicazioni non usano `admin` ma un utente limitato al proprio database. Lo creiamo **attraverso la stringa del replica set**, così il comando arriva sicuramente al primario.

```bash
cd ~/mongo-lab/02-replica-set
openssl rand -base64 24 | tr -d '/+=' | sudo tee appuser_password.txt > /dev/null
sudo chmod 600 appuser_password.txt

sudo docker exec -i -e FQDN="$FQDN" \
  -e RS_PWD="$(sudo cat root_password.txt)" -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-rs1 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/?replicaSet=rs0&authSource=admin&tls=true&tlsCAFile=/etc/mongo/tls/ca.pem" --quiet \
    --eval "db.getSiblingDB(\"labdb\").createUser({ user: \"appuser\", pwd: process.env.APP_PWD, roles: [ { role: \"readWrite\", db: \"labdb\" } ] })"'
```

✅ `ok: 1`.

**Verifica**, leggendo da un secondario come `appuser`:

```bash
sudo docker exec -i -e FQDN="$FQDN" -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-rs3 \
  sh -c 'mongosh "mongodb://appuser:$APP_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/labdb?replicaSet=rs0&authSource=labdb&tls=true&tlsCAFile=/etc/mongo/tls/ca.pem&readPreference=secondary" --quiet \
    --eval "print(\"Letto da:\", db.hello().me); print(\"Documenti in prova:\", db.prova.countDocuments())"'
```

✅ `Letto da:` con la porta di un secondario: l'utente è stato replicato e funziona anche lì.

**La stringa per le applicazioni:**

```
mongodb://appuser:PASSWORD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/labdb?replicaSet=rs0&authSource=labdb&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

| Parametro | Significato |
|---|---|
| i tre `host:porta` | punti di partenza per scoprire il replica set |
| `/labdb` | database predefinito |
| `replicaSet=rs0` | verifica di essere sul replica set giusto |
| `authSource=labdb` | l'utente è definito in `labdb`, non in `admin` |
| `tls=true` | obbligatorio: senza, il server chiude la connessione |
| `tlsCAFile` | la CA con cui verificare i nodi |

> A imporre la cifratura **è il server** (`requireTLS`), non la stringa: la stringa serve solo a far collegare il client nel modo accettato. Una stringa senza `replicaSet=rs0` funziona comunque (i driver scoprono i membri da soli), ma il parametro resta consigliato; `directConnection=true`, invece, bloccherebbe il client su un solo nodo, senza failover.

Da VS Code, collegato come `appuser`, vedrai solo il database `labdb`.

---

## Parte 10 — Backup e ripristino

### 10.1 Il replica set non è un backup: la prova

```bash
rs_eval 'db.getSiblingDB("labdb").prova.insertOne({ msg: "documento importante" }); print("Documenti:", db.getSiblingDB("labdb").prova.countDocuments())'
rs_eval 'db.getSiblingDB("labdb").prova.drop(); print("Documenti:", db.getSiblingDB("labdb").prova.countDocuments())'
rs_eval 'db.getMongo().setReadPref("secondary"); print("Sul nodo 3:", db.getSiblingDB("labdb").prova.countDocuments())' 3
```

La cancellazione è arrivata anche sul secondario in un istante. Se `rs_eval` risponde `not primary`, il nodo 1 non è il primario in quel momento: aspetta che riprenda il ruolo e riprova.

### 10.2 Cosa cambia rispetto al backup della guida 00

> 🧭 **Scelta — Uno script di backup dedicato al replica set**
>
> - **Si collega al replica set** e legge preferibilmente da un secondario (`readPreference=secondaryPreferred`), così non pesa sul primario; se i secondari non sono disponibili, ripiega sul primario invece di fallire.
> - **Usa `--oplog`:** un dump richiede tempo e intanto l'applicazione scrive; con l'oplog, `mongodump` registra anche le operazioni avvenute durante il backup e il ripristino (`--oplogReplay`) le riapplica, per una copia **coerente a un unico istante**. Funziona solo sui replica set.
> - **Usa il TLS**, ormai obbligatorio.
> - **Si esegue nel primo nodo acceso:** qualunque nodo può essere spento, e il file della password esiste solo nel nodo 1. La password viene quindi letta sulla VM e passata al container attraverso lo **standard input**, che non compare nella lista dei processi.
>
> **In produzione:** stessa logica, da un server di amministrazione o da un nodo; copia dei backup fuori dai server del database; spesso da un secondario dedicato e nascosto (`hidden: true`, `priority: 0`).

### 10.3 Lo script

Lo script è scritto in **due parti**: la prima (`<< EOF` senza apici) inserisce i valori veri di `$HOME` e `$FQDN`, la seconda (`<< 'EOF'`) viene copiata letteralmente.

```bash
sudo mkdir -p /var/backups/mongo-lab-rs && sudo chmod 700 /var/backups/mongo-lab-rs

sudo tee /usr/local/bin/mongo-rs-backup.sh > /dev/null << EOF
#!/bin/bash
# Backup del replica set rs0 (guida 02): da un secondario, con oplog e TLS
set -euo pipefail
umask 077

LAB=$HOME/mongo-lab/02-replica-set
FQDN=$FQDN
EOF

sudo tee -a /usr/local/bin/mongo-rs-backup.sh > /dev/null << 'EOF'
DEST=/var/backups/mongo-lab-rs
KEEP_DAILY=7      # giorni
KEEP_WEEKLY=4     # settimane
KEEP_MONTHLY=12   # mesi

mkdir -p "$DEST/daily" "$DEST/weekly" "$DEST/monthly"
FILE="$DEST/daily/mongo-rs-$(date +%Y%m%d-%H%M%S).archive.gz"

# Primo nodo in esecuzione, in cui lanciare mongodump
NODE=""
for c in mongo-rs1 mongo-rs2 mongo-rs3; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then NODE=$c; break; fi
done
[ -n "$NODE" ] || { echo "ERRORE: nessun nodo del replica set in esecuzione" >&2; exit 1; }

URI_TPL="mongodb://admin:%s@$FQDN:27101,$FQDN:27102,$FQDN:27103/?replicaSet=rs0&authSource=admin&readPreference=secondaryPreferred"

cat "$LAB/root_password.txt" | docker exec -i -e URI_TPL="$URI_TPL" "$NODE" sh -c '
  umask 077
  read -r PWD_RS
  printf "uri: $URI_TPL\n" "$PWD_RS" > /tmp/dump.yaml
  mongodump --config=/tmp/dump.yaml --ssl --sslCAFile=/etc/mongo/tls/ca.pem --oplog --archive --gzip --quiet
  status=$?
  rm -f /tmp/dump.yaml
  exit $status
' > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"

[ "$(date +%u)" = "7" ]  && ln -f "$FILE" "$DEST/weekly/"
[ "$(date +%d)" = "01" ] && ln -f "$FILE" "$DEST/monthly/"

find "$DEST/daily"   -name 'mongo-rs-*.archive.gz' -mtime +$((KEEP_DAILY - 1))        -delete
find "$DEST/weekly"  -name 'mongo-rs-*.archive.gz' -mtime +$((KEEP_WEEKLY * 7 - 1))  -delete
find "$DEST/monthly" -name 'mongo-rs-*.archive.gz' -mtime +$((KEEP_MONTHLY * 31 - 1)) -delete

echo "Backup completato ($NODE): $FILE ($(du -h "$FILE" | cut -f1))"
EOF

sudo chmod 700 /usr/local/bin/mongo-rs-backup.sh
sudo head -8 /usr/local/bin/mongo-rs-backup.sh
```

✅ Le righe `LAB=` e `FQDN=` contengono i valori veri. La retention è la stessa della guida 00: 7 giornalieri, 4 settimanali (🧪 non ancora osservata su un periodo reale), 12 mensili.

### 10.4 Prove

```bash
sudo /usr/local/bin/mongo-rs-backup.sh
sudo ls -lh /var/backups/mongo-lab-rs/daily
```

✅ `Backup completato (mongo-rs1): ...` e il file con permessi `-rw-------` di root.

**Con il nodo 1 spento**, un comando alla volta:

```bash
sudo docker compose stop mongo-rs1
```

```bash
sudo /usr/local/bin/mongo-rs-backup.sh
```

```bash
sudo docker compose start mongo-rs1
```

✅ Il backup riesce indicando `(mongo-rs2)`.

### 10.5 Il timer notturno

A un orario diverso da quello della guida 00 (02:30), per non sovrapporsi:

```bash
sudo tee /etc/systemd/system/mongo-rs-backup.service > /dev/null << 'EOF'
[Unit]
Description=Backup MongoDB replica set di laboratorio
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mongo-rs-backup.sh
EOF

sudo tee /etc/systemd/system/mongo-rs-backup.timer > /dev/null << 'EOF'
[Unit]
Description=Backup notturno MongoDB replica set di laboratorio

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mongo-rs-backup.timer
systemctl list-timers 'mongo*'
sudo systemctl start mongo-rs-backup.service && sudo journalctl -u mongo-rs-backup.service -n 3 --no-pager
```

✅ Entrambi i timer elencati (02:30 e 03:00 UTC) e `Backup completato` nel journal.

### 10.6 Ripristino

Prova completa: un documento, un backup, un incidente, il ripristino.

```bash
rs_eval 'db.getSiblingDB("labdb").prova.insertOne({ msg: "prova ripristino" }); print("Documenti:", db.getSiblingDB("labdb").prova.countDocuments())'
sudo /usr/local/bin/mongo-rs-backup.sh
rs_eval 'db.getSiblingDB("labdb").prova.drop(); print("Documenti:", db.getSiblingDB("labdb").prova.countDocuments())'
```

Il ripristino dal backup più recente, attraverso la stringa del replica set (così `mongorestore` scrive sul primario ovunque sia) e con il TLS. Lo standard input trasporta prima la password (una riga, letta da `read`) e poi il file di backup:

```bash
cd ~/mongo-lab/02-replica-set
F=$(sudo ls -t /var/backups/mongo-lab-rs/daily/ | head -1); echo "Ripristino: $F"
{ sudo cat root_password.txt; sudo cat "/var/backups/mongo-lab-rs/daily/$F"; } | sudo docker exec -i -e FQDN="$FQDN" mongo-rs2 sh -c '
  umask 077
  read -r PWD_RS
  printf "uri: mongodb://admin:%s@$FQDN:27101,$FQDN:27102,$FQDN:27103/?replicaSet=rs0&authSource=admin\n" "$PWD_RS" > /tmp/restore.yaml
  mongorestore --config=/tmp/restore.yaml --ssl --sslCAFile=/etc/mongo/tls/ca.pem --oplogReplay --drop --archive --gzip
  status=$?
  rm -f /tmp/restore.yaml
  exit $status'
```

```bash
rs_eval 'printjson(db.getSiblingDB("labdb").prova.find({}, { _id: 0, msg: 1 }).toArray())'
```

✅ `document(s) restored successfully` e il documento di nuovo al suo posto.

**Due tipi di messaggi da conoscere:**

- `don't know what to do with subdirectory ..., skipping...`: **innocui**, compaiono ripristinando un archivio che contiene l'oplog;
- `applied N oplog entries`: le operazioni catturate durante il backup e riapplicate. Può essere zero, oppure maggiore di zero anche se l'applicazione non scriveva: un replica set registra anche operazioni interne. Nel collaudo si sono visti entrambi i casi.

---

## Parte 11 — Manutenzione a rotazione

È l'operazione più comune su un replica set in produzione: aggiornamenti di MongoDB, patch del sistema operativo, cambi di configurazione. La regola: **prima i secondari, uno alla volta; il primario per ultimo, dopo avergli fatto cedere il ruolo.**

> ⚠️ **Un comando alla volta.** Ogni riavvio dura circa 16 secondi (lo spegnimento ordinato). Durante il collaudo, incollando i comandi successivi mentre un riavvio era in corso, il terminale ha mescolato le righe e lo `stepDown` non è stato eseguito. Aspetta sempre il prompt, e conta i tempi di attesa dalla fine del riavvio.

```bash
sudo docker compose restart mongo-rs3
```

```bash
sleep 20; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

Solo quando il nodo 3 è tornato `SECONDARY` (riavviarne due insieme farebbe perdere la maggioranza):

```bash
sudo docker compose restart mongo-rs2
```

```bash
sleep 20; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 3
```

Il primario cede il ruolo:

```bash
rs_eval 'rs.stepDown(60); print("fatto")'
```

```bash
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ Il nodo 1 è `SECONDARY`, un altro è `PRIMARY`. Il `60` impedisce al nodo 1 di ricandidarsi per 60 secondi. Se il comando risponde con una connessione chiusa invece di `fatto`, è normale: il nodo chiude le connessioni quando cambia ruolo.

```bash
sudo docker compose restart mongo-rs1
```

```bash
sleep 60; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ Il nodo 1 è tornato `PRIMARY`. Un client collegato (per esempio VS Code) non perde la connessione durante tutta la sequenza: nel collaudo ha retto senza interruzioni.

> 🧭 **Perché lo `stepDown` esplicito**, se un primario che si spegne in modo ordinato cede comunque il ruolo da solo (lo si è visto proprio quando lo `stepDown` è andato perso)? Perché permette di **scegliere il momento** dell'elezione e di **verificare** che un altro nodo sia primario **prima** di spegnere quello vecchio.
>
> **Per cambiare configurazione** si usa `docker compose up -d <servizio>` invece di `restart`: ricrea il nodo con il compose aggiornato (come nella Parte 8). **Per aggiornare MongoDB**, stessa sequenza cambiando il tag dell'immagine.

---

## Parte 12 — Cambiare una password

🧪 *Non collaudato nel laboratorio.*

Su un replica set basta eseguire il cambio sul primario: la modifica viene replicata da sola sugli altri nodi. Per `appuser`, attraverso la stringa del replica set:

```bash
cd ~/mongo-lab/02-replica-set
openssl rand -base64 24 | tr -d '/+=' | sudo tee appuser_password.txt > /dev/null
sudo docker exec -i -e FQDN="$FQDN" \
  -e RS_PWD="$(sudo cat root_password.txt)" -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-rs1 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/?replicaSet=rs0&authSource=admin&tls=true&tlsCAFile=/etc/mongo/tls/ca.pem" --quiet \
    --eval "db.getSiblingDB(\"labdb\").changeUserPassword(\"appuser\", process.env.APP_PWD)"'
```

Per `admin`: stesso procedimento con `db.getSiblingDB("admin").changeUserPassword("admin", ...)`, aggiornando `root_password.txt` (owner 999, `600`) **solo dopo** il cambio riuscito, perché lo script di backup lo legge.

In produzione va fatto sempre se una password viene esposta (in una chat, in un ticket, nella cronologia di un terminale).

---

## Parte 13 — Quando qualcosa va storto

### Durante la costruzione

| Sintomo | Causa | Soluzione |
|---|---|---|
| Riga anomala tipo `EOF file: ./root_password...` durante l'incolla | Blocco lungo rovinato dal terminale | Ricrea il compose in due parti o con `nano`; verifica con `config --services` e `--volumes` |
| `compose valido` ma mancano servizi o volumi | File incompleto | Come sopra |
| Nodo 2 o 3: `Did not find local replica set configuration document` | Normale prima di `rs.initiate` | Esegui la Parte 4.1 |
| `rs.initiate`: `Authentication failed` | Password errata | Rileggila con `sudo cat root_password.txt` |
| Container che non partono con errori sul keyFile | Permessi del keyFile | `sudo chown 999:999 keyfile && sudo chmod 400 keyfile` |
| Il `grep` di `extra_hosts` mostra `$FQDN` letterale | Variabili non impostate prima dell'incolla | Imposta le variabili (Parte 2.3) e ricrea il compose |

### Durante l'uso

| Sintomo | Causa | Soluzione |
|---|---|---|
| `rs_eval: command not found` | Nuova sessione | Ridefinisci la funzione (Parte 4.3 o 8.4) |
| `container ... is not running` con `rs_eval` | Il nodo interrogato è spento | Usa un altro nodo: `rs_eval '...' 2` |
| `not primary` | Scrittura su un secondario, o `rs_eval` sul nodo 1 quando non è primario | Scrivi attraverso la stringa del replica set, o aspetta che il nodo 1 riprenda il ruolo |
| Stop che dura ~11 s e `clean shutdown: false` | Manca `stop_grace_period` | Aggiungilo e ricrea i nodi |
| Comandi incollati durante un riavvio "spariscono" | Output mescolato | Un comando alla volta, aspettando il prompt |
| `[1] 12345` e `No such file or directory` dopo aver incollato una stringa `mongodb://` | Stringa incollata in bash | Va nel client; togli la riga dalla cronologia (Parte 7.5) |

### Accesso dall'esterno

| Sintomo | Causa | Soluzione |
|---|---|---|
| Il client si collega all'IP pubblico ma poi fallisce | I membri sono registrati con nomi non risolvibili dal PC | Nome DNS (Parte 7) |
| `Test-NetConnection` `False` | NSG, o porte non pubblicate sull'IP privato | Regola NSG 27101–27103 e `sudo ss -ltnp \| grep 2710` |
| `Resolve-DnsName` non risolve | Etichetta DNS non impostata o non ancora propagata | Portale Azure, attendi qualche minuto |
| Smette di funzionare dopo giorni | Il tuo IP pubblico è cambiato | Aggiorna l'origine della regola NSG |

### TLS

| Sintomo | Causa | Soluzione |
|---|---|---|
| Replica interrotta dopo l'attivazione del TLS, errori sui certificati tra i nodi | Certificato senza `clientAuth` | Rigenera con `extendedKeyUsage=serverAuth,clientAuth` |
| Nessun client riesce più a collegarsi con la sola password | Manca `--tlsAllowConnectionsWithoutCertificates` | Aggiungilo al compose |
| `connection ... closed` dal client | Il client non usa il TLS | `tls=true` nella stringa |
| `certificate verify failed` | `tlsCAFile` errato | Percorso di `ca.pem` della CA giusta |
| `IP address mismatch` / `altnames` | Nome o IP non nel SAN | Usa `<FQDN>`, o aggiungi il nome e rinnova il certificato |
| Dopo un riavvio un nodo è tornato a una modalità precedente | Modalità cambiata solo a caldo | Aggiorna il compose (Parte 8.5) |
| Contatori `transportSecurity` a zero dopo `preferTLS` | Connessioni di replica non ancora rinnovate | `rs.stepDown(30)` e attesa |

### Backup e ripristino

| Sintomo | Causa | Soluzione |
|---|---|---|
| `No such file` su `/run/secrets/...` in `mongo-rs2`/`mongo-rs3` | Il secret esiste solo nel nodo 1 | Password via standard input, come nello script |
| Backup fallito dopo l'attivazione del TLS | Comando senza `--ssl --sslCAFile` | Usa lo script della Parte 10.3 |
| `don't know what to do with subdirectory` | Normale con archivi che contengono l'oplog | Nessuna azione |
| File di backup leggibile da altri utenti | Salvato fuori dalla cartella protetta | Usa lo script (cartella `700`, `umask 077`) |

---

## Parte 14 — Laboratorio e produzione

### 14.1 Le differenze in un colpo d'occhio

| Aspetto | Laboratorio | Produzione |
|---|---|---|
| Server | 3 container sulla stessa VM | 3 VM, zone di disponibilità diverse |
| Guasto della macchina | Cade l'intero replica set | Cade un nodo, il servizio continua |
| Risorse | Cache 256 MB, `mem_limit` 1 GB | Cache predefinita, risorse dedicate |
| Nomi dei membri | Un nome DNS Azure + porte diverse, `extra_hosts` | Un nome DNS per nodo, DNS aziendale |
| Porte | 27101–27103 | 27017 su ogni nodo |
| Rete dei client | Da internet, NSG limitato a un IP | Rete privata (VNet, peering, VPN) |
| Cifratura | TLS obbligatorio, client e tra nodi | Idem |
| Certificati | Uno per tutti i nodi, CA privata | Uno per nodo, CA aziendale o pubblica |
| Autenticazione interna | keyFile | keyFile o x.509 |
| Segreti | File sulla VM, funzione `rs_eval` | Key Vault o gestore di segreti |
| Backup | Script sulla VM, cartella locale | Pianificato, copia fuori dai server, eventualmente da un secondario nascosto |

### 14.2 Checklist per la produzione

- [ ] Tre nodi su tre VM in zone di disponibilità diverse, dischi dati dedicati (XFS).
- [ ] Nomi DNS per ogni nodo, scelti prima di `rs.initiate`.
- [ ] Nessuna esposizione su internet: client nella stessa rete privata.
- [ ] TLS obbligatorio, un certificato per nodo con `serverAuth` e `clientAuth`.
- [ ] keyFile (o x.509) distribuito in modo sicuro.
- [ ] Segreti in Key Vault; nessuna funzione di comodo che esponga password.
- [ ] Backup pianificati, copiati fuori dalla regione o almeno fuori dai server del database, ripristino provato periodicamente.
- [ ] Monitoraggio dello stato dei membri e del ritardo di replica (*replication lag*).
- [ ] Procedura di manutenzione a rotazione documentata e provata.
- [ ] `stop_grace_period` (o l'equivalente del sistema che gestisce i processi) sufficiente per lo spegnimento ordinato.

### 14.3 Opzioni avanzate (non collaudate nel laboratorio)

- **Autenticazione x.509 dei membri** (`clusterAuthMode: x509`): i nodi si riconoscono con i certificati invece del keyFile.
- **Secondario nascosto per i backup** (`hidden: true`, `priority: 0`): non riceve traffico dai client, ideale per i backup.
- **Horizons**: indirizzi diversi per client interni ed esterni, basati sul nome richiesto nel TLS.
- **Membri in un'altra regione** con `priority: 0`, per il disaster recovery.

---

## Parte 15 — Smantellare il laboratorio

🧪 *Non collaudato.* Quando il laboratorio non serve più:

```bash
cd ~/mongo-lab/02-replica-set
pwd                                   # deve essere la cartella del laboratorio!
sudo docker compose down -v
sudo systemctl disable --now mongo-rs-backup.timer
sudo rm /etc/systemd/system/mongo-rs-backup.service /etc/systemd/system/mongo-rs-backup.timer
sudo systemctl daemon-reload
sudo rm /usr/local/bin/mongo-rs-backup.sh
```

Poi, a scelta: eliminare la cartella `~/mongo-lab/02-replica-set` e i backup in `/var/backups/mongo-lab-rs`, la regola NSG `mongo-lab-rs` e, se non serve ad altro, l'etichetta DNS; in VS Code, le connessioni al laboratorio.

---

## Appendice A — Dove si trova ogni cosa

| Cosa | Dove |
|---|---|
| Cartella del laboratorio | `~/mongo-lab/02-replica-set` |
| Configurazione | `docker-compose.yml` (copie: `.pre-tls`, `.allowtls`) |
| keyFile | `keyfile` (`400`, owner 999) |
| Password | `root_password.txt` (owner 999), `appuser_password.txt` |
| Certificati | `tls/` (`server.pem` owner 999 `600`, `ca.pem`, `server.crt`, `server.key`, `server.ext`) |
| CA usata per firmare | `~/mongodb/tls/` (guida 01) |
| Dati | Volumi `mongo-lab-rs_rs1-data`, `_rs2-data`, `_rs3-data` |
| Script di backup | `/usr/local/bin/mongo-rs-backup.sh` |
| Backup | `/var/backups/mongo-lab-rs/daily`, `weekly`, `monthly` |
| Timer | `/etc/systemd/system/mongo-rs-backup.{service,timer}` (03:00 UTC) |
| Azure | Etichetta DNS sull'IP pubblico; regola NSG `mongo-lab-rs` (27101–27103) |

---

## Appendice B — Promemoria dei comandi

```bash
cd ~/mongo-lab/02-replica-set
FQDN=<FQDN>; PRIV_IP=<IP_PRIVATO_VM>

# Funzione di comodo con TLS (in ogni nuova sessione)
rs_eval() {
  local node=${2:-1}
  sudo docker exec -i -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs$node \
    sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 2710'"$node"' -u admin -p "$RS_PWD" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}

# Stato dei membri
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr, "salute:", m.health))' 2

# Modalità TLS e connessioni cifrate
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
for n in 1 2 3; do rs_eval 'printjson(db.serverStatus().transportSecurity)' $n; done

# Cedere il ruolo di primario
rs_eval 'rs.stepDown(60); print("fatto")'

# Spegnimento ordinato riuscito?
sudo docker compose logs mongo-rs1 | grep -o '"Startup from clean shutdown?":[a-z]*' | tail -1

# Backup
sudo /usr/local/bin/mongo-rs-backup.sh
sudo journalctl -u mongo-rs-backup.service -n 5 --no-pager
```

**Dal PC:**

```powershell
Resolve-DnsName <FQDN>
27101..27103 | ForEach-Object { Test-NetConnection <FQDN> -Port $_ | Select-Object RemotePort, TcpTestSucceeded }
```

---

## Le 8 regole d'oro del replica set

1. **Guarda il prompt** prima di ogni `docker compose`: sulla VM ci sono due progetti.
2. **Numero dispari di nodi**, e mai più di uno spento alla volta.
3. **Il replica set non è un backup**: i backup servono comunque.
4. **Scegli i nomi dei membri prima di `rs.initiate`**: devono essere risolvibili da tutti i client.
5. **`stop_grace_period`** abbondante: lascia spegnere MongoDB in modo ordinato.
6. **Certificati con `serverAuth` e `clientAuth`**: i nodi sono anche client gli uni degli altri.
7. **TLS in tre fasi** (`allowTLS` → `preferTLS` → `requireTLS`) e compose aggiornato alla fine.
8. **Manutenzione a rotazione**: secondari uno alla volta, `stepDown`, primario per ultimo, un comando alla volta.
