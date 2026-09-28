# MongoDB 8.0 in Docker su Debian 13 — Guida rapida

Setup di MongoDB 8.0 in container su VM Debian 13 (Azure): autenticazione, utente applicativo, backup con retention, accesso da sviluppo, hardening.

**Segnaposto:** `<IP_PUBBLICO_VM>`, `<IP_PRIVATO_VM>`, `<IL_TUO_IP>`. Database/utente d'esempio: `appdb` / `appuser`.
**Nota:** MongoDB non ha pacchetti server ufficiali per trixie, da qui la scelta di Docker.

---

## 1. Prerequisiti

```bash
grep -o avx /proc/cpuinfo | head -1   # deve stampare "avx" (richiesto da MongoDB 8.0)
sudo apt-get update
```

## 2. Docker

```bash
# Rimozione pacchetti non ufficiali ("Unable to locate package" = ok)
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

# Repository ufficiale
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Installazione e avvio al boot
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
```

## 3. Transparent Huge Pages (host)

Impostazioni richieste da MongoDB 8.0, persistenti al riavvio.

```bash
sudo tee /etc/tmpfiles.d/mongodb-thp.conf > /dev/null << 'EOF'
w /sys/kernel/mm/transparent_hugepage/enabled - - - - always
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
w /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 0
EOF
sudo systemd-tmpfiles --create /etc/tmpfiles.d/mongodb-thp.conf
cat /sys/kernel/mm/transparent_hugepage/enabled   # [always]
```

## 4. Configurazione MongoDB

```bash
mkdir -p ~/mongodb && cd ~/mongodb

# Password root: owner UID 999 (utente mongodb nel container), altrimenti l'init fallisce
openssl rand -base64 24 | tr -d '/+=' | sudo tee mongo_root_password.txt > /dev/null
sudo chown 999:999 mongo_root_password.txt && sudo chmod 600 mongo_root_password.txt
```

```bash
cat > docker-compose.yml << 'EOF'
services:
  mongo:
    image: mongo:8.0
    container_name: mongo
    restart: unless-stopped
    ports:
      - "127.0.0.1:27017:27017"
      # - "<IP_PRIVATO_VM>:27017:27017"   # accesso diretto, vedi §9.2
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
sudo docker compose config --quiet && echo "compose valido"
```

- Porta solo su `127.0.0.1`: Docker scavalca ufw/iptables, mai `0.0.0.0`.
- `MONGO_INITDB_*` vengono letti **solo al primo avvio** con volume vuoto.
- Log limitati a 5 × 50 MB.

## 5. Avvio e verifica

```bash
sudo docker compose up -d
sudo docker compose logs -f mongo          # attendere "Waiting for connections", poi Ctrl+C
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin

# Avvisi di avvio (atteso solo quello su XFS)
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.adminCommand({ getLog: "startupWarnings" }).log.forEach(l => print(l))'

# Solo warning/error/fatal dai log
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'
```

I warning `Use of deprecated server parameter` (`ctx: ftdc`) sono innocui.

## 6. Utente applicativo

Password passata via variabile d'ambiente: incollarla in `passwordPrompt()` può causare `U_STRINGPREP_PROHIBITED_ERROR`.

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee ~/mongodb/appuser_password.txt > /dev/null
sudo chmod 600 ~/mongodb/appuser_password.txt

# Creazione (chiede la password di admin)
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("appdb").createUser({ user: "appuser", pwd: process.env.APP_PWD, roles: [ { role: "readWrite", db: "appdb" } ] })'

# Verifica
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.runCommand({ ping: 1 })"'
```

**Rotazione password** (rigenerare il file, poi aggiornare MongoDB):

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee ~/mongodb/appuser_password.txt > /dev/null
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("appdb").changeUserPassword("appuser", process.env.APP_PWD)'
```

**Stringhe di connessione:**

| Client | URI |
|---|---|
| Sulla VM | `mongodb://appuser:PWD@127.0.0.1:27017/appdb?authSource=appdb` |
| Container nello stesso compose | `mongodb://appuser:PWD@mongo:27017/appdb?authSource=appdb` |
| PC via tunnel SSH | `mongodb://appuser:PWD@127.0.0.1:27017/appdb?authSource=appdb&directConnection=true` |
| PC accesso diretto | `mongodb://appuser:PWD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true` |

## 7. Backup

Dump compresso notturno; retention 7 giornalieri / 4 settimanali (domenica) / 12 mensili (giorno 1) tramite hard link. Password via file temporaneo (non visibile in `ps`); con `set -e` la pulizia non avviene se il dump fallisce.

```bash
sudo mkdir -p /var/backups/mongodb && sudo chmod 700 /var/backups/mongodb

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
sudo /usr/local/bin/mongo-backup.sh
```

**Timer systemd** (02:30 UTC; `Persistent=true` recupera le esecuzioni perse a VM spenta):

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
sudo systemctl start mongo-backup.service && sudo journalctl -u mongo-backup.service -n 5 --no-pager
```

- Retention: modificare `KEEP_*` nello script.
- La cartella è `700` root: i glob vanno eseguiti con `sudo sh -c '...'`.

## 8. Ripristino

`--drop` sostituisce le collezioni presenti nel dump; gli utenti vengono ripristinati.

```bash
# Ultimo giornaliero (per un file specifico: f=/var/backups/mongodb/<cartella>/<file>)
sudo sh -c 'f=$(ls -t /var/backups/mongodb/daily/mongo-*.archive.gz | head -1); echo "Ripristino: $f"; \
  docker exec -i mongo sh -c "mongorestore -u admin -p \"\$(cat /run/secrets/mongo_root_password)\" --authenticationDatabase admin --archive --gzip --drop" < "$f"'
```

Testare periodicamente: insert di prova → backup → drop → restore → verifica.

## 9. Accesso dal PC di sviluppo

### 9.1 Tunnel SSH (consigliato)

Nessuna modifica lato VM, traffico cifrato. Dal PC:

```bash
ssh -N -L 27017:127.0.0.1:27017 azureuser@<IP_PUBBLICO_VM>
```

Oppure in `~/.ssh/config`, poi `ssh -N mongo-azure`:

```
Host mongo-azure
    HostName <IP_PUBBLICO_VM>
    User azureuser
    IdentityFile ~/.ssh/chiave.pem
    LocalForward 27017 127.0.0.1:27017
    ServerAliveInterval 60
```

Compass: *Advanced Connection Options → Proxy/SSH → SSH with Identity File*.

### 9.2 Accesso diretto (solo dev, traffico in chiaro)

```bash
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1        # IP privato
# In docker-compose.yml, sezione ports, aggiungere:  - "<IP_PRIVATO_VM>:27017:27017"
sudo docker compose up -d
sudo ss -ltnp | grep 27017                                      # 127.0.0.1 + IP privato
```

NSG Azure: regola in ingresso TCP 27017, **origine `<IL_TUO_IP>`** (mai Any). Verificare NSG sia su NIC sia su subnet.

```powershell
Test-NetConnection <IP_PUBBLICO_VM> -Port 27017    # dal PC
```

## 10. Log

**Default (json-file):** limite di spazio, 5 × 50 MB. Modifica nel compose + `up -d` (i log precedenti vanno persi).

```bash
sudo docker inspect mongo --format '{{json .HostConfig.LogConfig}}'
sudo sh -c 'du -sh /var/lib/docker/containers/*/*-json.log*'
```

**Alternativa a tempo (journald):** nel compose `logging: { driver: journald, options: { tag: mongo } }`, poi:

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/retention.conf > /dev/null << 'EOF'
[Journal]
Storage=persistent
MaxRetentionSec=30day
SystemMaxUse=1G
EOF
sudo systemctl restart systemd-journald && sudo docker compose up -d
sudo journalctl CONTAINER_NAME=mongo --since "2 days ago"
```

`diagnostic.data` (FTDC) si autolimita a ~250 MB.

## 11. Hardening

**Unattended upgrades** (Debian security + Docker, reboot automatico opzionale):

```bash
sudo apt-get install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -plow unattended-upgrades

sudo tee /etc/apt/apt.conf.d/51unattended-docker > /dev/null << 'EOF'
Unattended-Upgrade::Origins-Pattern {
        "origin=Docker";
};
EOF

sudo tee /etc/apt/apt.conf.d/52unattended-reboot > /dev/null << 'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

sudo unattended-upgrade --dry-run --debug 2>&1 | grep -E "Allowed origins|Packages that will be upgraded"
```

Un upgrade di Docker riavvia il daemon (breve downtime). In produzione aggiornare Docker manualmente.

**SSH** (solo chiave; tenere aperta la sessione corrente e testare da una seconda):

```bash
sudo sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin)'

sudo tee /etc/ssh/sshd_config.d/50-hardening.conf > /dev/null << 'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo systemctl reload ssh
```

NSG porta 22: origine `<IL_TUO_IP>`.

## 12. Operatività

Da `~/mongodb`:

| Operazione | Comando |
|---|---|
| Stato | `sudo docker compose ps` |
| Log | `sudo docker compose logs -f mongo` |
| Stop / start / restart | `sudo docker compose stop` · `start` · `restart` |
| Applicare modifiche compose | `sudo docker compose up -d` |
| Shell admin | `sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin` |
| Backup manuale / esiti | `sudo /usr/local/bin/mongo-backup.sh` · `sudo journalctl -u mongo-backup.service -n 20` |
| Aggiornare patch 8.0 | `sudo /usr/local/bin/mongo-backup.sh && sudo docker compose pull && sudo docker compose up -d` |
| Versione | `sudo docker exec mongo mongod --version \| head -1` |
| Reboot necessario? | `ls /var/run/reboot-required` |

- **Avvio al boot:** `docker` enabled + `restart: unless-stopped` (un container fermato manualmente resta fermo).
- **Major upgrade:** una versione alla volta, con backup e aggiornamento del `featureCompatibilityVersion`.
- ⛔ **`docker compose down -v` elimina il volume dati.**

## 13. Troubleshooting

| Sintomo | Soluzione |
|---|---|
| `no configuration file provided` | Eseguire da `~/mongodb` |
| `Authentication failed` | Verificare la password corrente nel file; nei log cercare `Successfully added user` |
| Password root cambiata nel file senza effetto | Init solo a volume vuoto: usare `db.changeUserPassword()` |
| Init fallito, permission denied sul secret | `sudo chown 999:999 mongo_root_password.txt` |
| `U_STRINGPREP_PROHIBITED_ERROR` | Passare la password via `-e APP_PWD` invece di incollarla |
| Glob su `/var/backups/mongodb` non trovato | `sudo sh -c '...'` |
| `Soft rlimits ... too low` | Blocco `ulimits` nel compose |
| Warning `sysfsFile` / allocatore | Configurare THP (§3) |
| Warning XFS | Ignorabile in dev; in prod disco dati XFS |
| 27017 non raggiungibile dall'esterno | Tunnel SSH, oppure IP privato nel compose + NSG |
| Accesso diretto smette di funzionare | IP pubblico del client cambiato: aggiornare NSG |

## 14. Checklist produzione

- [ ] Rimuovere l'esposizione della 27017 (compose + NSG) o configurare TLS
- [ ] Connessioni applicative su rete privata (VNet/peering/VPN)
- [ ] Disco dati dedicato XFS (Premium SSD)
- [ ] Backup off-VM (Azure Backup o Storage Account)
- [ ] Alert Azure Monitor su disco e backup falliti
- [ ] Segreti in Key Vault / password manager
- [ ] Replica set a 3 nodi se serve HA
- [ ] Aggiornamenti Docker manuali in finestra di manutenzione
- [ ] Test di ripristino periodico