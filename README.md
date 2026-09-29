# MongoDB 8.0 in Docker su Debian 13

Documentazione e file di configurazione per installare **MongoDB 8.0** in un container Docker su una macchina virtuale **Debian 13 (trixie)**, con particolare riferimento ad **Azure**.

## Scopo del progetto

Installare MongoDB su Debian 13 non è immediato: MongoDB non pubblica ancora pacchetti server ufficiali per questa versione, e molte guide in circolazione usano comandi ormai obsoleti (`apt-key`, repository di vecchie versioni di Debian, MongoDB 5.0 fuori supporto, la vecchia shell `mongo`).

Questo progetto nasce per offrire un percorso **aggiornato, completo e verificato sul campo** che porti da una VM appena creata a un'istanza MongoDB pronta all'uso, senza fermarsi alla sola installazione: sicurezza, backup, accesso e manutenzione fanno parte del percorso fin dall'inizio.

Il setup è pensato per ambienti di **sviluppo e test**, con una checklist dedicata ai passi necessari prima di portarlo in produzione.

## Obiettivi

1. **Sicurezza di default.** Autenticazione sempre attiva, database non esposto su internet, password generate casualmente e mai scritte in chiaro nei comandi, utente applicativo con permessi limitati al proprio database.
2. **Dati protetti.** Backup automatici con retention su più livelli (giornaliera, settimanale, mensile) e una procedura di ripristino testata, non solo descritta.
3. **Riproducibilità.** Gli stessi comandi e file di configurazione portano sempre allo stesso risultato; i file in `config/` si possono copiare sulla VM così come sono.
4. **Manutenzione semplice.** Avvio automatico, aggiornamenti di sicurezza automatici, log con dimensione limitata, aggiornamento di MongoDB con pochi comandi.
5. **Accessibilità.** Una guida completa per chi parte da zero, che spiega il perché di ogni passaggio, e una guida rapida per chi vuole solo i comandi.
6. **Scelte motivate.** Ogni decisione tecnica (Docker, porte, permessi, retention) è spiegata, così è possibile adattarla consapevolmente al proprio contesto.
7. **Esperienza reale.** Gli errori incontrati durante un'installazione effettiva, e la loro soluzione, sono raccolti nelle sezioni di risoluzione dei problemi.

## Cosa comprende

Autenticazione, utente applicativo con permessi limitati, backup automatici con retention giornaliera/settimanale/mensile, accesso dall'ambiente di sviluppo (tunnel SSH o accesso diretto), gestione dei log e hardening di base del sistema (aggiornamenti automatici, SSH solo con chiave). Una seconda parte copre la cifratura delle connessioni con **TLS**, tramite una CA privata, e una terza il **replica set**, costruito in laboratorio e accompagnato dallo scenario di produzione.

> **Perché Docker?** L'immagine Docker ufficiale di MongoDB include tutte le dipendenze, quindi funziona su Debian 13 senza forzature, e rende semplici aggiornamenti e rimozione.

## Documentazione

Le guide sono numerate nell'ordine in cui vanno seguite. Ogni argomento ha due versioni: una **completa**, per chi ha poca esperienza con Linux, Docker o MongoDB (ogni passaggio spiega cosa fa il comando e cosa aspettarsi), e una **rapida**, per chi conosce già l'ambiente (sequenza dei comandi con spiegazioni essenziali).

| # | Argomento | Guida completa | Guida rapida |
|---|---|---|---|
| 00 | Installazione, sicurezza di base, utente applicativo, backup, accesso, manutenzione | [00-guida-completa](docs/00-guida-completa.md) | [00-guida-rapida](docs/00-guida-rapida.md) |
| 01 | Cifratura delle connessioni con TLS (CA privata, client, rinnovi) | [01-tls-guida-completa](docs/01-tls-guida-completa.md) | [01-tls-guida-rapida](docs/01-tls-guida-rapida.md) |
| 02 | Replica set: costruzione, failover, accesso esterno, TLS a rotazione, backup con oplog, manutenzione | [02-replica-set-guida-completa](docs/02-replica-set-guida-completa.md) | [02-replica-set-guida-rapida](docs/02-replica-set-guida-rapida.md) |

Per tutte le guide vale la **[legenda dei comandi](docs/legenda-comandi-linux.md)**: spiega ogni comando Linux, simbolo della shell, comando Docker, MongoDB e PowerShell usato nel progetto, con esempi presi dalle guide.

La guida 01 presuppone di aver completato la 00; la 02 presuppone la 00 e la 01 (riusa la CA per il TLS). Gli [appunti di laboratorio della guida 02](docs/02-replica-set-appunti.md) raccolgono il diario delle prove, delle scelte e degli inconvenienti da cui è nata la guida.

## Struttura del repository

```
.
├── README.md
├── docs/
│   ├── 00-guida-completa.md
│   ├── 00-guida-rapida.md
│   ├── 01-tls-guida-completa.md
│   ├── 01-tls-guida-rapida.md
│   ├── 02-replica-set-guida-completa.md
│   ├── 02-replica-set-guida-rapida.md
│   ├── 02-replica-set-appunti.md     (diario del laboratorio)
│   └── legenda-comandi-linux.md      (legenda dei comandi, valida per tutte le guide)
└── config/
    ├── 00-base/                      Risorse della guida 00 (senza TLS)
    │   ├── docker-compose.yml        → ~/mongodb/docker-compose.yml
    │   ├── mongo-backup.sh           → /usr/local/bin/mongo-backup.sh
    │   ├── mongo-backup.service      → /etc/systemd/system/mongo-backup.service
    │   ├── mongo-backup.timer        → /etc/systemd/system/mongo-backup.timer
    │   └── mongodb-thp.conf          → /etc/tmpfiles.d/mongodb-thp.conf
    ├── 01-tls/                       Risorse della guida 01 (con TLS)
    │   ├── docker-compose.yml        → ~/mongodb/docker-compose.yml (sostituisce quello della 00)
    │   ├── mongo-backup.sh           → /usr/local/bin/mongo-backup.sh (sostituisce quello della 00)
    │   └── genera-certificati-tls.sh → ~/mongodb/tls/ (crea o rinnova i certificati)
    └── 02-replica-set/               Risorse della guida 02 (laboratorio replica set)
        ├── docker-compose.yml        → ~/mongo-lab/02-replica-set/ (fase iniziale, senza TLS)
        ├── docker-compose-tls.yml    → ~/mongo-lab/02-replica-set/docker-compose.yml (finale, con TLS)
        ├── server.ext.example        → ~/mongo-lab/02-replica-set/tls/server.ext
        ├── mongo-rs-backup.sh        → /usr/local/bin/mongo-rs-backup.sh (impostare LAB e FQDN)
        ├── mongo-rs-backup.service   → /etc/systemd/system/
        └── mongo-rs-backup.timer     → /etc/systemd/system/ (03:00 UTC)
```

Ogni guida ha la propria cartella di risorse, con gli stessi file riportati nel testo, pronti da copiare sulla VM nei percorsi indicati. La guida 01 contiene solo i file che cambiano rispetto alla 00: timer, servizio systemd e impostazioni del kernel restano quelli di `00-base`.

Lo script di backup esiste in due versioni: quella di `00-base` si collega senza TLS; quella di `01-tls` rileva da sola se il TLS è attivo e funziona in entrambi i casi, anche dopo un eventuale rollback. Attivando il TLS va quindi installata la versione `01-tls`, altrimenti i backup smettono di funzionare.

## Requisiti

- VM Debian 13 con CPU che supporta le istruzioni **AVX** (richieste da MongoDB 8.0)
- Accesso SSH con utente abilitato a `sudo`
- Per l'accesso dall'esterno: permessi per modificare il Network Security Group (NSG) su Azure

## Avvio rapido

Dopo aver installato Docker e configurato le Transparent Huge Pages (vedi la guida):

```bash
mkdir -p ~/mongodb && cd ~/mongodb
# copia qui config/00-base/docker-compose.yml

openssl rand -base64 24 | tr -d '/+=' | sudo tee mongo_root_password.txt > /dev/null
sudo chown 999:999 mongo_root_password.txt && sudo chmod 600 mongo_root_password.txt

sudo docker compose up -d
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin
```

Per utente applicativo, backup, accesso remoto e hardening segui la [guida rapida](docs/00-guida-rapida.md) o la [guida completa](docs/00-guida-completa.md); per il TLS, le guide [01](docs/01-tls-guida-completa.md).

## Note di sicurezza

- Le password **non** fanno parte del repository: vengono generate sulla VM e conservate in file leggibili solo da root (esclusi tramite `.gitignore`).
- Di default MongoDB è raggiungibile solo da `127.0.0.1` della VM. Non pubblicare mai la porta su `0.0.0.0`: Docker scavalca il firewall di sistema.
- L'accesso diretto sulla porta 27017 senza TLS è pensato **solo per lo sviluppo**, perché il traffico viaggia in chiaro: per cifrarlo segui le guide 01. Per la produzione consulta la checklist finale delle guide.
- La chiave privata della CA (`ca.key`) e le chiavi del server non devono mai finire nel repository né restare senza protezione: le guide 01 spiegano come custodirle.

## Versioni di riferimento e stato di verifica

Testato con MongoDB 8.0.32, Docker Engine 29, Docker Compose 5 su Debian 13 (Azure).

| Guida | Stato |
|---|---|
| 00 | Collaudata su un'installazione reale: installazione, utente applicativo, backup e ripristino, accesso diretto, log, aggiornamenti automatici. Non ancora collaudati (🧪): tunnel SSH, log con journald, chiave SSH e disattivazione delle password, retention settimanale/mensile su un periodo reale |
| 01 (TLS) | Parti 2–9 collaudate su un'installazione reale, compresa l'esecuzione notturna del backup con TLS. Rinnovo del certificato, rollback e script `genera-certificati-tls.sh` non ancora collaudati su VM (🧪) |
| 02 (replica set) | Collaudata su un'installazione reale (laboratorio con tre container su una VM). Non ancora collaudati (🧪): rollback del TLS, cambio password, smantellamento, retention settimanale/mensile su un periodo reale; opzioni avanzate (x.509, secondario nascosto, horizons) solo descritte |

Le parti non ancora collaudate sono segnalate nelle guide con il simbolo 🧪. Se le esegui, segnala eventuali differenze.

## Licenza

Da definire.
