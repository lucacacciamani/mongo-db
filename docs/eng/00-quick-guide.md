# MongoDB 8.0 in Docker on Debian 13 — Quick guide

Setup of MongoDB 8.0 in a container on a Debian 13 VM (Azure): authentication, application user, backups with retention, access from a development PC, hardening.

**Placeholders:** `<IP_PUBBLICO_VM>`, `<IP_PRIVATO_VM>`, `<IL_TUO_IP>`. Example database/user: `appdb` / `appuser`.
**Note:** MongoDB has no official server packages for trixie, hence the choice of Docker.

> 📖 **Commands and symbols** (`sudo`, `chmod`, `|`, `<< EOF`, `docker compose`…): the [command legend](linux-commands-legend.md) explains everything that appears in this guide.

---

```mermaid
flowchart LR
    PC["PC"] -- "SSH 22 / 27017" --> NSG["Azure NSG"] --> VM
    subgraph VM["Debian 13 VM"]
        MG["mongo container"] --- VOL[("Data volume")]
        TM["Timer 02:30"] -- "mongodump" --> BK[("Local backups")]
    end
```

## 1. Prerequisites

```bash
grep -o avx /proc/cpuinfo | head -1   # must print "avx" (required by MongoDB 8.0)
sudo apt-get update
```

## 2. Docker

```bash
# Remove unofficial packages ("Unable to locate package" = ok)
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

# Official repository
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install and start at boot
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
```

## 3. Transparent Huge Pages (host)

Settings required by MongoDB 8.0, persistent across reboots.

```bash
sudo tee /etc/tmpfiles.d/mongodb-thp.conf > /dev/null << 'EOF'
w /sys/kernel/mm/transparent_hugepage/enabled - - - - always
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
w /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 0
EOF
sudo systemd-tmpfiles --create /etc/tmpfiles.d/mongodb-thp.conf
cat /sys/kernel/mm/transparent_hugepage/enabled   # [always]
```

## 4. MongoDB configuration

```bash
mkdir -p ~/mongodb && cd ~/mongodb

# Root password: owner UID 999 (the mongodb user in the container), otherwise the init fails
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
    stop_grace_period: 1m
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

- Port on `127.0.0.1` only: Docker bypasses ufw/iptables, never `0.0.0.0`.
- `stop_grace_period: 1m`: by default Docker kills the container after 10 s; MongoDB can take longer to shut down cleanly (up to ~15 s in a replica set), and a forced stop means a recovery at the next start.
- `MONGO_INITDB_*` are read **only at the first start** with an empty volume.
- Logs capped at 5 × 50 MB.

## 5. Start and verification

```bash
sudo docker compose up -d
sudo docker compose logs -f mongo          # wait for "Waiting for connections", then Ctrl+C
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin

# Startup warnings (only the XFS one is expected)
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.adminCommand({ getLog: "startupWarnings" }).log.forEach(l => print(l))'

# Only warning/error/fatal entries from the logs
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'
```

The `Use of deprecated server parameter` warnings (`ctx: ftdc`) are harmless.

## 6. Application user

Password passed through an environment variable: pasting it into `passwordPrompt()` can cause `U_STRINGPREP_PROHIBITED_ERROR`.

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee ~/mongodb/appuser_password.txt > /dev/null
sudo chmod 600 ~/mongodb/appuser_password.txt

# Creation (asks for the admin password)
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("appdb").createUser({ user: "appuser", pwd: process.env.APP_PWD, roles: [ { role: "readWrite", db: "appdb" } ] })'

# Verification
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.runCommand({ ping: 1 })"'
```

**Password rotation** (regenerate the file, then update MongoDB):

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee ~/mongodb/appuser_password.txt > /dev/null
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("appdb").changeUserPassword("appuser", process.env.APP_PWD)'
```

**Connection strings:**

| Client | URI |
|---|---|
| On the VM | `mongodb://appuser:PWD@127.0.0.1:27017/appdb?authSource=appdb` |
| Container in the same compose | `mongodb://appuser:PWD@mongo:27017/appdb?authSource=appdb` |
| PC through SSH tunnel | `mongodb://appuser:PWD@127.0.0.1:27017/appdb?authSource=appdb&directConnection=true` |
| PC direct access | `mongodb://appuser:PWD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true` |

## 7. Backup

Nightly compressed dump; retention of 7 daily / 4 weekly (Sunday) / 12 monthly (day 1) through hard links. Password through a temporary file (not visible in `ps`); with `set -e` the cleanup does not happen if the dump fails. With TLS enabled it must be replaced by the version from guide 01 (`config/01-tls/mongo-backup.sh`).

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

🧪 Weekly/monthly retention not yet observed over a real period (tested: backup, timer, nightly run and restore).

**systemd timer** (02:30 UTC; `Persistent=true` catches up on runs missed while the VM was off):

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

- Retention: change `KEEP_*` in the script.
- The folder is `700` root: globs must be run with `sudo sh -c '...'`.

## 8. Restore

`--drop` replaces the collections present in the dump; users are restored.

```bash
# Latest daily (for a specific file: f=/var/backups/mongodb/<cartella>/<file>)
sudo sh -c 'f=$(ls -t /var/backups/mongodb/daily/mongo-*.archive.gz | head -1); echo "Ripristino: $f"; \
  docker exec -i mongo sh -c "mongorestore -u admin -p \"\$(cat /run/secrets/mongo_root_password)\" --authenticationDatabase admin --archive --gzip --drop" < "$f"'
```

Test periodically: test insert → backup → drop → restore → verification.

## 9. Access from the development PC

### 9.1 SSH tunnel (recommended)

🧪 Not yet tested (the test run used direct access, §9.2).

No changes on the VM side, encrypted traffic. From the PC:

```bash
ssh -N -L 27017:127.0.0.1:27017 azureuser@<IP_PUBBLICO_VM>
```

Or in `~/.ssh/config`, then `ssh -N mongo-azure`:

```
Host mongo-azure
    HostName <IP_PUBBLICO_VM>
    User azureuser
    IdentityFile ~/.ssh/chiave.pem
    LocalForward 27017 127.0.0.1:27017
    ServerAliveInterval 60
```

Compass: *Advanced Connection Options → Proxy/SSH → SSH with Identity File*.

### 9.2 Direct access (dev only, unencrypted traffic)

To encrypt the traffic: `01-tls-quick-guide.md`.

```bash
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1        # private IP
# In docker-compose.yml, ports section, add:  - "<IP_PRIVATO_VM>:27017:27017"
sudo docker compose up -d
sudo ss -ltnp | grep 27017                                      # 127.0.0.1 + private IP
```

Azure NSG: inbound rule TCP 27017, **source `<IL_TUO_IP>`** (never Any). Check the NSG on both the NIC and the subnet.

```powershell
Test-NetConnection <IP_PUBBLICO_VM> -Port 27017    # from the PC
```

## 10. Logs

**Default (json-file):** size limit, 5 × 50 MB. Change it in the compose + `up -d` (previous logs are lost).

```bash
sudo docker inspect mongo --format '{{json .HostConfig.LogConfig}}'
sudo sh -c 'du -sh /var/lib/docker/containers/*/*-json.log*'
```

**Time-based alternative (journald)** 🧪 not tested: in the compose `logging: { driver: journald, options: { tag: mongo } }`, then:

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

`diagnostic.data` (FTDC) caps itself at ~250 MB.

## 11. Hardening

🧪 SSH key and disabling password login not yet tested: always test from a second session.

**Unattended upgrades** (Debian security + Docker, optional automatic reboot):

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

A Docker upgrade restarts the daemon (brief downtime). In production, update Docker manually.

**SSH key** (if `ssh`/`scp` ask for the password), from the PC:

```powershell
ssh-keygen -t ed25519
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh azureuser@<IP_PUBBLICO_VM> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh azureuser@<IP_PUBBLICO_VM>    # must log in without a password
```

**SSH** (key only; keep the current session open and test from a second one):

```bash
sudo sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin)'

sudo tee /etc/ssh/sshd_config.d/50-hardening.conf > /dev/null << 'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo systemctl reload ssh
```

NSG port 22: source `<IL_TUO_IP>`.

## 12. Operations

From `~/mongodb`:

| Operation | Command |
|---|---|
| Status | `sudo docker compose ps` |
| Logs | `sudo docker compose logs -f mongo` |
| Stop / start / restart | `sudo docker compose stop` · `start` · `restart` |
| Apply compose changes | `sudo docker compose up -d` |
| Admin shell | `sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin` |
| Manual backup / results | `sudo /usr/local/bin/mongo-backup.sh` · `sudo journalctl -u mongo-backup.service -n 20` |
| Update to the latest 8.0 patch | `sudo /usr/local/bin/mongo-backup.sh && sudo docker compose pull && sudo docker compose up -d` |
| Version | `sudo docker exec mongo mongod --version \| head -1` |
| Published addresses (configured in `ports`, not in MongoDB) | `sudo docker port mongo` · `sudo ss -ltnp \| grep 27017` |
| Reboot needed? | `ls /var/run/reboot-required` |

- **Start at boot:** `docker` enabled + `restart: unless-stopped` (a container stopped manually stays stopped).
- **Major upgrade:** one version at a time, with a backup and the `featureCompatibilityVersion` update.
- ⛔ **`docker compose down -v` deletes the data volume.**

## 13. Troubleshooting

| Symptom | Solution |
|---|---|
| `no configuration file provided` | Run from `~/mongodb` |
| `Authentication failed` | Check the current password in the file; look for `Successfully added user` in the logs |
| Root password changed in the file with no effect | Init only runs on an empty volume: use `db.changeUserPassword()` |
| Init failed, permission denied on the secret | `sudo chown 999:999 mongo_root_password.txt` |
| `U_STRINGPREP_PROHIBITED_ERROR` | Pass the password through `-e APP_PWD` instead of pasting it |
| Glob on `/var/backups/mongodb` not found | `sudo sh -c '...'` |
| `Soft rlimits ... too low` | `ulimits` block in the compose |
| `sysfsFile` / allocator warning | Configure THP (§3) |
| XFS warning | Can be ignored in dev; in prod use an XFS data disk |
| 27017 not reachable from outside | SSH tunnel, or private IP in the compose + NSG |
| Direct access stops working | The client's public IP changed: update the NSG |

## 14. Production checklist

- [ ] Remove the exposure of 27017 (compose + NSG) or configure TLS (guide 01)
- [ ] Application connections over a private network (VNet/peering/VPN)
- [ ] Dedicated XFS data disk (Premium SSD)
- [ ] Off-VM backups (Azure Backup or Storage Account)
- [ ] Azure Monitor alerts on disk and failed backups
- [ ] Secrets in Key Vault / password manager
- [ ] 3-node replica set if HA is needed
- [ ] Manual Docker updates in a maintenance window
- [ ] Periodic restore test
