# MongoDB 8.0 in Docker su Debian 13

Documentazione e file di configurazione per installare **MongoDB 8.0** in un container Docker su una macchina virtuale **Debian 13 (trixie)**, con particolare riferimento ad **Azure**.

## Scopo del progetto

Installare MongoDB su Debian 13 non è immediato: MongoDB non pubblica ancora pacchetti server ufficiali per questa versione, e molte guide in circolazione usano comandi ormai obsoleti (`apt-key`, repository di vecchie versioni di Debian, MongoDB 5.0 fuori supporto, la vecchia shell `mongo`).

Questo progetto nasce per offrire un percorso **aggiornato, completo e verificato** che porti da una VM appena creata a un'istanza MongoDB pronta all'uso, senza fermarsi alla sola installazione: sicurezza, backup, accesso e manutenzione fanno parte del percorso fin dall'inizio.

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

Autenticazione, utente applicativo con permessi limitati, backup automatici con retention giornaliera/settimanale/mensile, accesso dall'ambiente di sviluppo (tunnel SSH o accesso diretto), gestione dei log e hardening di base del sistema (aggiornamenti automatici, SSH solo con chiave).

> **Perché Docker?** L'immagine Docker ufficiale di MongoDB include tutte le dipendenze, quindi funziona su Debian 13 senza forzature, e rende semplici aggiornamenti e rimozione.

## Documentazione

| Guida | Per chi |
|---|---|
| [Guida completa](docs/guida-completa.md) | Chi ha poca esperienza con Linux, Docker o MongoDB: ogni passaggio spiega cosa fa il comando e cosa aspettarsi |
| [Guida rapida](docs/guida-rapida.md) | Chi conosce già l'ambiente: sequenza dei comandi con spiegazioni essenziali |

## Struttura del repository

```
.
├── README.md
├── docs/
│   ├── guida-completa.md
│   └── guida-rapida.md
└── config/
    ├── docker-compose.yml     → ~/mongodb/docker-compose.yml
    ├── mongo-backup.sh        → /usr/local/bin/mongo-backup.sh
    ├── mongo-backup.service   → /etc/systemd/system/mongo-backup.service
    ├── mongo-backup.timer     → /etc/systemd/system/mongo-backup.timer
    └── mongodb-thp.conf       → /etc/tmpfiles.d/mongodb-thp.conf
```

I file in `config/` sono gli stessi riportati nelle guide, pronti da copiare sulla VM nei percorsi indicati.

## Requisiti

- VM Debian 13 con CPU che supporta le istruzioni **AVX** (richieste da MongoDB 8.0)
- Accesso SSH con utente abilitato a `sudo`
- Per l'accesso dall'esterno: permessi per modificare il Network Security Group (NSG) su Azure

## Avvio rapido

Dopo aver installato Docker e configurato le Transparent Huge Pages (vedi la guida):

```bash
mkdir -p ~/mongodb && cd ~/mongodb
# copia qui config/docker-compose.yml

openssl rand -base64 24 | tr -d '/+=' | sudo tee mongo_root_password.txt > /dev/null
sudo chown 999:999 mongo_root_password.txt && sudo chmod 600 mongo_root_password.txt

sudo docker compose up -d
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin
```

Per utente applicativo, backup, accesso remoto e hardening segui la [guida rapida](docs/guida-rapida.md) o la [guida completa](docs/guida-completa.md).

## Note di sicurezza

- Le password **non** fanno parte del repository: vengono generate sulla VM e conservate in file leggibili solo da root (esclusi tramite `.gitignore`).
- Di default MongoDB è raggiungibile solo da `127.0.0.1` della VM. Non pubblicare mai la porta su `0.0.0.0`: Docker scavalca il firewall di sistema.
- L'accesso diretto sulla porta 27017 descritto nelle guide è pensato **solo per lo sviluppo**: senza TLS il traffico viaggia in chiaro. Per la produzione consulta la checklist finale delle guide.

## Versioni di riferimento

Testato con MongoDB 8.0.32, Docker Engine 29, Docker Compose 5 su Debian 13 (Azure).

## Licenza

Da definire.
