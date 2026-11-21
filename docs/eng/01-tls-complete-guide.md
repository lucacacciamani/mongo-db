# Encrypting MongoDB connections with TLS — Complete step-by-step guide

**Who this guide is for:** anyone who already has MongoDB working as described in the `00-complete-guide.md` guide and wants to encrypt the traffic between applications and the database. As in guide 00, every step explains **what to do**, **what the command does** and **what you should see** if it worked.

**What you will have at the end:**

- all connections to MongoDB encrypted, including local ones, backups and restores;
- clients that check they are talking to the right server, not to an impostor;
- your own certificate authority (CA), which lets you renew the certificate without reconfiguring the clients;
- a renewal procedure, an emergency procedure for rolling back, and a table of the most common errors.

**Estimated time:** 45–60 minutes.

**Verification status:** Parts 2–9 have been run and tested on a real installation. The certificate renewal procedure (Part 10) and the rollback procedure (Part 11) have not been tested yet: they are marked with the 🧪 symbol.

> 📖 **Commands and symbols** (`sudo`, `chmod`, `|`, `<< EOF`, `docker compose`…): the [command legend](linux-commands-legend.md) explains everything that appears in this guide.

---

## Contents

- [Part 0 — Basic concepts](#part-0--basic-concepts)
- [Part 1 — TLS or SSH tunnel?](#part-1--tls-or-ssh-tunnel)
- [Part 2 — Preparation](#part-2--preparation)
- [Part 3 — Create the certificate authority (CA)](#part-3--create-the-certificate-authority-ca)
- [Part 4 — Create the server certificate](#part-4--create-the-server-certificate)
- [Part 5 — Protect the files](#part-5--protect-the-files)
- [Part 6 — Configure MongoDB](#part-6--configure-mongodb)
- [Part 7 — Verify that TLS works](#part-7--verify-that-tls-works)
- [Part 8 — Update backup, restore and test commands](#part-8--update-backup-restore-and-test-commands)
- [Part 9 — Configure the clients](#part-9--configure-the-clients)
- [Part 10 — Renew the certificate](#part-10--renew-the-certificate)
- [Part 11 — Rolling back (disabling TLS)](#part-11--rolling-back-disabling-tls)
- [Part 12 — When something goes wrong](#part-12--when-something-goes-wrong)
- [Part 13 — Toward production](#part-13--toward-production)
- [Appendix A — Where everything lives](#appendix-a--where-everything-lives)
- [Appendix B — Command cheat sheet](#appendix-b--command-cheat-sheet)
- [The 6 golden rules of TLS](#the-6-golden-rules-of-tls)

> **Conventions:** the same as in guide 00 apply (prompts, `<< 'EOF'` blocks to paste in full, `<...>` placeholders to replace, removing the `<` and `>` as well). In this guide the VM user is `azureuser`, the VM is called `mongo-vm` and the example private IP is `10.0.0.4`: replace them with your own.

---

## Part 0 — Basic concepts

**TLS.** This is the protocol that encrypts communications on the internet: the same one that makes the padlock appear in your browser on `https` sites. Applied to MongoDB, it makes the user name, password and data travel in a form that is unreadable to anyone intercepting the traffic.

TLS does **two different things**, and it is important to keep them apart:

1. It **encrypts** the traffic, so anyone listening understands nothing.
2. It **verifies the identity** of the server, so the client is sure it is talking to the real MongoDB and not to an impostor who has placed themselves in the middle (a *man in the middle* attack).

Without the second, the first is worth little: an impostor could get hold of the password and then read everything. This guide configures **both**.

**Certificate.** The server's "digital identity card". It contains the server's names and addresses, the expiry date, a *public key* and the signature of whoever issued it. It is not a secret: the server shows it to anyone who connects.

**Private key.** The secret counterpart of the certificate. Whoever holds it can "be" the server. **It must never leave the server** and must never be shared.

**Certificate authority (CA).** The party that signs certificates. The client does not know the server's certificate in advance, but it trusts the CA that signed it: it is like a passport, which you trust because it was issued by the State. In this guide we create **our own** private CA.

**SAN (Subject Alternative Name).** The list of addresses and names the certificate is valid for. If you connect to `20.1.2.3` but that address is not in the SAN, the client refuses the connection, exactly like a passport made out to another person.

**Why a CA and not a simple "self-signed" certificate?** With a self-signed certificate, every renewal produces a new certificate that has to be redistributed to all the clients. With a CA, the clients receive the CA certificate just once (valid for 10 years) and automatically trust every server certificate it signs: renewals become invisible to the clients.

### How the pieces fit together

```mermaid
flowchart TD
    CAKEY["ca.key<br/>CA private key<br/>secret"] -- "signs" --> CRT["server.crt<br/>server certificate"]
    SKEY["server.key<br/>server key, secret"] --> PEM["server.pem<br/>certificate + key<br/>read by MongoDB"]
    CRT --> PEM
    CAPEM["ca.pem<br/>CA certificate, public"] -- "copied to the PC" --> CLI["Client<br/>VS Code, application"]
    CLI -- "checks signature, address in the SAN, expiry" --> CRT
```

And what happens on every connection:

```mermaid
sequenceDiagram
    participant C as Client with ca.pem
    participant M as MongoDB in requireTLS
    C->>M: TLS connection request
    M-->>C: presents server.crt
    C->>C: signed by the CA? address in the SAN? not expired?
    alt verification succeeded
        C->>M: encrypted channel, TLS 1.2 or 1.3
        C->>M: user name and password, encrypted
        M-->>C: authentication succeeded
    else verification failed
        C--xM: connection dropped by the client
    end
    Note over M: a client without TLS is rejected:<br/>connection closed
```

### The files we will create

| File | What it is | Secret? | Where it goes |
|---|---|---|---|
| `ca.key` | CA private key | **Yes, the most important one** | In a safe place outside the VM (only needed for signing) |
| `ca.pem` | CA certificate | No | To the clients and to MongoDB |
| `server.key` | Server private key | **Yes** | Only on the VM |
| `server.crt` | Server certificate | No | On the VM |
| `server.pem` | `server.crt` + `server.key` in a single file | **Yes** (it contains the key) | Only on the VM, read by MongoDB |
| `server.ext` | Certificate settings (SAN) | No | On the VM, needed for renewals |
| `ca.srl` | Counter of signed certificates | No | Together with `ca.key` |

---

## Part 1 — TLS or SSH tunnel?

The SSH tunnel described in guide 00 (Part 11.1) also encrypts the traffic and verifies the server. The two solutions are equally secure: what changes is how you manage them.

| | SSH tunnel | TLS (this guide) |
|---|---|---|
| Port 27017 exposed | No | Yes, restricted to authorized IPs |
| What the client needs | SSH key and an open tunnel | The `ca.pem` file |
| Maintenance | None | Renewal of the server certificate every ~2 years |
| Several people or applications | Each with its own tunnel | Just distribute `ca.pem` |
| Services that cannot open a tunnel | Not suitable | Suitable |

**Rule of thumb:** if you are working alone in development, the tunnel is the simplest choice. TLS pays off with several people, several applications or services that need to connect directly, and it is essential in production anyway when the database communicates over the network.

The two solutions can also coexist: with TLS enabled the tunnel keeps working, but clients will have to use TLS through the tunnel as well.

---

## Part 2 — Preparation

> 📍 **Where:** on the VM, prompt `azureuser@mongo-vm`.

### 2.1 Take a backup and save the current configuration

Before any important change:

```bash
sudo /usr/local/bin/mongo-backup.sh
cd ~/mongodb
cp docker-compose.yml docker-compose.yml.pre-tls
```

The `docker-compose.yml.pre-tls` copy lets you roll back in a moment if something goes wrong (Part 11).

### 2.2 Find the VM's IP addresses

The certificate must contain every address the clients will use to reach MongoDB.

**Private IP:**

```bash
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1
```

**Public IP:** in the Azure portal, on the VM's *Overview* page, under *Public IP address*. Alternatively, from the VM:

```bash
curl -s https://ifconfig.me; echo
```

Write them both down.

### 2.3 Check that the public IP is static

If the public IP changed, the certificate would no longer be valid for the new address. In the Azure portal open the *Public IP address* resource attached to the VM → *Configuration*: the assignment must be **Static**. *Standard* public IPs, the default for recent VMs, already are.

> If you only use the SSH tunnel and access from the VM itself, the public IP is not strictly needed in the certificate, but including it does no harm and leaves you free to enable direct access in the future.

### 2.4 Create the certificates folder

```bash
mkdir -p ~/mongodb/tls
chmod 700 ~/mongodb/tls
cd ~/mongodb/tls
```

✅ The prompt becomes `azureuser@mongo-vm:~/mongodb/tls$`.

> **Shortcut:** Parts 3 and 4 are automated by the `config/01-tls/genera-certificati-tls.sh` script in the repository. We recommend doing them by hand at least the first time, to understand what is going on; the script is mostly handy for renewals.

---

## Part 3 — Create the certificate authority (CA)

> 📍 **Where:** on the VM, in the `~/mongodb/tls` folder.

```bash
openssl genrsa -out ca.key 4096
openssl req -x509 -new -key ca.key -sha256 -days 3650 -subj "/CN=MongoDB Dev CA" -out ca.pem
chmod 600 ca.key
```

**What it does:**

1. `genrsa` creates the CA's private key (4096 bits, very strong);
2. `req -x509` creates the CA certificate, valid for **10 years** (3650 days), with the name `MongoDB Dev CA`;
3. `chmod 600` makes the key readable only by you.

**Check:**

```bash
openssl x509 -in ca.pem -noout -subject -enddate
```

✅ **You should see:** `subject=CN = MongoDB Dev CA` (the spacing may vary) and an expiry date ten years from now.

---

## Part 4 — Create the server certificate

> 📍 **Where:** on the VM, in the `~/mongodb/tls` folder.

### 4.1 Set the addresses

Replace with your own values (Part 2.2):

```bash
PUB_IP=<IP_PUBBLICO_VM>
PRIV_IP=10.0.0.4
echo "Pubblico: $PUB_IP - Privato: $PRIV_IP"
```

✅ Check that the printed line shows the two correct addresses. If either part is empty, repeat the assignment.

### 4.2 Describe the certificate

```bash
cat > server.ext << EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:mongo,IP:127.0.0.1,IP:$PRIV_IP,IP:$PUB_IP
EOF
cat server.ext
```

> Careful: here the first line is `<< EOF` **without quotes**, unlike usual. This is deliberate: it makes the terminal replace `$PRIV_IP` and `$PUB_IP` with the real values.

✅ The last line printed must contain the real addresses, for example `IP:10.0.0.4,IP:20.1.2.3`, and not the text `$PRIV_IP`.

**What the SAN means:**

| Entry | Used for |
|---|---|
| `DNS:localhost`, `IP:127.0.0.1` | Connections from the VM itself, backups, and connections through the SSH tunnel |
| `DNS:mongo` | Applications in other containers of the same `docker-compose.yml` |
| `IP:$PRIV_IP` | Clients in the same Azure private network |
| `IP:$PUB_IP` | Direct access from the internet (e.g. your PC) |

If you later give the VM a DNS name (for example `miodb.westeurope.cloudapp.azure.com`), add it as `DNS:...` and regenerate the certificate (Part 10).

### 4.3 Generate and sign the certificate

```bash
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=mongo-vm" -out server.csr
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 825 -sha256 -extfile server.ext -out server.crt
rm server.csr
```

**What it does:**

1. creates the server's private key;
2. prepares a "certificate request" (`server.csr`);
3. the CA signs the request and produces `server.crt`, valid for **825 days** (about 2 years and 3 months), with the addresses from `server.ext`;
4. deletes the request, which is no longer needed.

### 4.4 Check the certificate

```bash
openssl verify -CAfile ca.pem server.crt
openssl x509 -in server.crt -noout -ext subjectAltName -enddate
```

✅ **You should see:** `server.crt: OK`, the list of addresses in the SAN and the expiry date.

### 4.5 Create the file for MongoDB

MongoDB wants the server's certificate and key in a single file:

```bash
cat server.crt server.key | sudo tee server.pem > /dev/null
```

---

## Part 5 — Protect the files

> 📍 **Where:** on the VM, in the `~/mongodb/tls` folder.

### 5.1 Permissions

```bash
sudo chown 999:999 server.pem
sudo chmod 600 server.pem
chmod 600 server.key
chmod 644 ca.pem server.crt
ls -l
```

✅ **You should see:** `server.pem` with owner `999 999` and permissions `-rw-------`; `ca.key` and `server.key` with `-rw-------`; `ca.pem` and `server.crt` with `-rw-r--r--`.

As with the password file (guide 00, Part 6.2), `server.pem` belongs to the user with number 999, which is the user MongoDB runs as inside the container.

> **The `systemd-journal` group.** In the listing, `server.pem` may show up as belonging to the `systemd-journal` group. This is normal and harmless: on the VM the number 999 happens to match that system group. All that matters is that the permissions are `-rw-------`.

### 5.2 Keep the CA key safe

`ca.key` is the most sensitive file: with it, anyone could sign certificates that your clients would consider valid. On the VM it is only needed at the moment you sign a certificate. Here we copy it to your PC; then you can choose whether to delete it from the VM (safer) or keep it there too (more convenient for renewals).

#### How `scp` works

`scp` copies files over SSH. You run it **from your PC**, in PowerShell, and it is the PC that "goes and fetches" the files from the VM. The format is:

```
scp [opzioni] ORIGINE DESTINAZIONE
```

- The source (`ORIGINE`) on the VM is written as `utente@indirizzo:percorso`, that is user, address and path (there, `~` means your home folder on the VM).
- The destination (`DESTINAZIONE`) on the PC is an ordinary Windows path. If it is a **folder**, the file keeps its name; if you also give a file name, it is saved under that name.
- User, address and key (if any) are **the same as in the `ssh` command** you use to get into the VM. If you connect with a key file, add `-i C:\percorso\della\chiave` (this is the file downloaded from Azure when the VM was created, usually `<nome-vm>_key.pem`, or a key in `C:\Users\<tuo-nome>\.ssh\`); if you connect with a password, leave out `-i` and `scp` will ask you for it.
- Paths containing spaces must be enclosed in quotes.

#### 1. Create a safe folder on the PC

> 📍 **From your PC**, in PowerShell (not in the VM's terminal!):

```powershell
mkdir C:\Users\<tuo-nome>\mongodb-ca -Force
```

Choose a folder **outside the project's Git repository**: that way you don't risk publishing the key by mistake.

> ⚠️ If you run this `mkdir` in the VM's terminal instead of PowerShell, Linux creates a folder with an odd name, for example `C:Users<tuo-nome>mongodb-ca`, because it does not know Windows paths and strips the backslashes. It is harmless: delete it from the VM with `rmdir 'C:Users<tuo-nome>mongodb-ca'` (with the quotes).

#### 2. Copy the key and the counter

> 📍 **From your PC**, in PowerShell:

```powershell
scp azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.key C:\Users\<tuo-nome>\mongodb-ca\
scp azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.srl C:\Users\<tuo-nome>\mongodb-ca\
```

(Add `-i C:\percorso\della\chiave` after `scp` if you access the VM with a key file.)

- The first time you connect from that PC you may see *The authenticity of host ... can't be established*: answer `yes`, as with `ssh`.
- ✅ For each file you should see a line with `100%`. `ca.key` is about 3.2 KB, `ca.srl` a few dozen bytes.

#### 3. Check that the copy is identical

Before you trust the copy, compare the fingerprints of the two files.

📍 On the VM:

```bash
sha256sum ~/mongodb/tls/ca.key
```

📍 On the PC:

```powershell
Get-FileHash C:\Users\<tuo-nome>\mongodb-ca\ca.key -Algorithm SHA256
```

✅ The two sequences must be the same (PowerShell shows them in upper case, Linux in lower case: only the letters and digits matter).

#### 4. Look after the copy

Keep the `mongodb-ca` folder in a protected, backed-up place: a password manager that accepts attachments, Azure Key Vault, an encrypted folder (for example with BitLocker). Avoid cloud-synced folders without encryption, and do **not** put it in the Git repository.

#### 5. Choose: delete the key from the VM or keep it?

**Option A — Delete it (recommended, mandatory in production).** Only after you have checked the fingerprints:

📍 On the VM:

```bash
cd ~/mongodb/tls
shred -u ca.key
ls
```

`shred -u` overwrites the file before deleting it, so it cannot be recovered. ✅ `ca.key` must no longer appear in `ls`; `ca.pem`, `ca.srl`, `server.crt`, `server.ext`, `server.key` and `server.pem` must remain. From this moment the key exists only on the PC: at renewal time it will have to be brought back to the VM (Part 10).

**Option B — Keep it on the VM too (acceptable in development and in the lab).** You have two verified copies and renewals are simpler. In exchange, anyone who gets into the VM with your user or with `sudo` can read it. Reduce the risk like this:

- check the permissions: `ls -l ~/mongodb/tls/ca.key` must show `-rw-------` and `ls -ld ~/mongodb/tls` must show `drwx------`;
- never mount the whole `./tls` folder in the container: the compose file mounts only `server.pem` and `ca.pem`, so MongoDB does not see the key;
- remember that the key does not end up in MongoDB backups, but it **does** end up in any snapshots or backups of the whole VM (for example with Azure Backup);
- if you want one more layer, make it readable only by root with `sudo chown root:root ~/mongodb/tls/ca.key` (at renewal time you will need `sudo` for the signing command).

---

## Part 6 — Configure MongoDB

> 📍 **Where:** on the VM, in the `~/mongodb` folder.

### 6.1 The new docker-compose.yml

```bash
cd ~/mongodb
PRIV_IP=10.0.0.4
echo "IP privato: $PRIV_IP"
```

✅ Check that the IP is the right one, then paste the **whole** block:

```bash
cat > docker-compose.yml << EOF
services:
  mongo:
    image: mongo:8.0
    container_name: mongo
    restart: unless-stopped
    stop_grace_period: 1m
    command:
      - --tlsMode=requireTLS
      - --tlsCertificateKeyFile=/etc/mongo/tls/server.pem
      - --tlsCAFile=/etc/mongo/tls/ca.pem
      - --tlsAllowConnectionsWithoutCertificates
      - --tlsDisabledProtocols=TLS1_0,TLS1_1
    ports:
      - "127.0.0.1:27017:27017"
      - "$PRIV_IP:27017:27017"
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
      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro
      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro
    secrets:
      - mongo_root_password

volumes:
  mongo-data:

secrets:
  mongo_root_password:
    file: ./mongo_root_password.txt
EOF
grep -A2 'ports:' docker-compose.yml
```

✅ The `grep` must show `127.0.0.1:27017:27017` and the line with your real private IP.

> **If you don't need direct access** (you only use the SSH tunnel or applications on the VM), delete the line with the private IP: TLS will still work for all connections.

### 6.2 What has changed

Compared with the compose file in guide 00 there are two new things.

**The `command` block**, that is the options MongoDB starts with:

| Option | Meaning |
|---|---|
| `--tlsMode=requireTLS` | Accepts **only** encrypted connections; unencrypted ones are rejected |
| `--tlsCertificateKeyFile` | The file with the server's certificate and key |
| `--tlsCAFile` | The CA certificate |
| `--tlsAllowConnectionsWithoutCertificates` | Clients authenticate with user name and password, without having to present a certificate of their own (see below) |
| `--tlsDisabledProtocols=TLS1_0,TLS1_1` | Disables the old, weak versions of the protocol; TLS 1.2 and 1.3 remain |

> ⚠️ **The `tlsCAFile` trap.** When you specify a CA, MongoDB by default demands that **every client** also presents a certificate signed by that CA. Without `--tlsAllowConnectionsWithoutCertificates` nobody could connect with just a password any more, not even the backup script.

**Two lines under `volumes`**, which make only the two necessary files visible to the container, read-only (`:ro`). The `tls` folder is not mounted as a whole: even if it contained other sensitive files, MongoDB would not see them.

> There are also the `allowTLS` and `preferTLS` modes, which accept both encrypted and unencrypted connections. They are used to migrate a system with many clients without downtime: you start from `preferTLS`, update the clients one at a time, then switch to `requireTLS`. In a small environment it is better to go straight to `requireTLS`.

### 6.3 Check and apply

> ⚠️ **From this moment existing clients stop connecting.** With `requireTLS`, every connection already configured without TLS (your application, Compass, the MongoDB extension for VS Code, scripts) will be rejected until you update it as described in Part 9. If someone is working on the database, warn them first.

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose up -d
```

✅ **You should see:** `compose valido`, then `Container mongo Recreated` and `Started`. The data is not touched.

---

## Part 7 — Verify that TLS works

> 📍 **Where:** on the VM, in the `~/mongodb` folder.

### 7.1 Is the container running?

```bash
sudo docker compose ps
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'
```

✅ The status must be `Up` (not `Restarting`), and among the warnings and errors there must be no messages about certificates or TLS. The harmless warnings already known from guide 00 (`ftdc`, XFS) remain.

❌ **If the container keeps restarting**, look at the last lines of the logs with `sudo docker compose logs --tail 30 mongo` and see [Part 12](#part-12--when-something-goes-wrong). The most frequent cause is the permissions on `server.pem`.

### 7.2 Does the server present the right certificate?

```bash
openssl s_client -connect 127.0.0.1:27017 -CAfile tls/ca.pem </dev/null 2>/dev/null | grep -E "Verify return code|Protocol"
```

✅ **You should see:** `Verify return code: 0 (ok)` and a `TLSv1.3` or `TLSv1.2` protocol.

<details>
<summary>📋 Real output from the test run</summary>

```
Protocol: TLSv1.3
Verify return code: 0 (ok)
```

</details>

### 7.3 Are the old versions rejected?

```bash
openssl s_client -connect 127.0.0.1:27017 -tls1_1 </dev/null 2>&1 | grep -iE "alert|error|no protocols" | head -2
```

✅ An error must appear: the connection with TLS 1.1 is rejected. (Some versions of OpenSSL don't even let you attempt it: that is fine too.)

### 7.4 Connect with the shell

From now on every connection, even from the VM, must use TLS:

```bash
sudo docker exec -it mongo mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem \
  -u admin -p --authenticationDatabase admin
```

✅ After the password, the `test>` prompt appears. **Leave with `exit`** before moving on.

> As long as the prompt is `test>` you are inside the MongoDB shell, which only accepts JavaScript commands. If you run a command such as `sudo docker ...` there, you get `SyntaxError: Missing semicolon`: it is not a TLS problem, just leave with `exit` and go back to the `azureuser@mongo-vm:~/mongodb$` prompt.

### 7.5 The opposite test

The same connection **without** TLS must fail:

```bash
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin --eval 'db.runCommand({ping:1})'
```

✅ **It must fail** with a connection error (for example `connection closed` or `MongoServerSelectionError`). This means unencrypted connections really are rejected.

<details>
<summary>📋 Real output from the test run</summary>

```
$ sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin --eval 'db.runCommand({ping:1})'
Enter password: *******************************
MongoServerSelectionError: connection <monitor> to 127.0.0.1:27017 closed
```

</details>

---

## Part 8 — Update backup, restore and test commands

> 📍 **Where:** on the VM.

With `requireTLS`, `mongodump` and `mongorestore` must use TLS too: without this part, **the nightly backups would fail**.

### 8.1 The new backup script

This version, also available in the repository as `config/01-tls/mongo-backup.sh`, works out by itself whether TLS is enabled (it checks whether `/etc/mongo/tls/ca.pem` exists in the container), so it works both with and without TLS: it keeps working even after a rollback (Part 11). Compared with the version in guide 00, only the three lines containing `TLS` change. Paste the **whole** block:

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
  TLS=""
  [ -f /etc/mongo/tls/ca.pem ] && TLS="--ssl --sslCAFile=/etc/mongo/tls/ca.pem"
  mongodump $TLS --config=/tmp/dump.yaml -u admin --authenticationDatabase admin --archive --gzip --quiet
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
```

> MongoDB's backup tools still use the historical names `--ssl` and `--sslCAFile`, but the protocol is TLS.

> ⚠️ **Paste the block from the `sudo tee` line down to and including `sudo chmod`.** The lines with `TLS=""` and `mongodump $TLS ...` are part of the script: if you run them on their own you get `mongodump: command not found`, because `mongodump` exists only inside the container. It does no harm, but the script is not updated.

Check that the script contains the TLS part:

```bash
sudo grep -n "TLS" /usr/local/bin/mongo-backup.sh
```

✅ Three lines must appear: `TLS=""`, `[ -f /etc/mongo/tls/ca.pem ] ...` and `mongodump $TLS ...`.

> **If you had an earlier version of the script on the VM**, one that saved backups directly in `/var/backups/mongodb` instead of in the `daily`, `weekly` and `monthly` subfolders, those old files are no longer handled by the automatic cleanup. After checking that the new backups work (Part 8.2), delete them with: `sudo sh -c 'rm -f /var/backups/mongodb/mongo-*.archive.gz'`.

### 8.2 Test the backup

```bash
sudo /usr/local/bin/mongo-backup.sh
sudo systemctl start mongo-backup.service
sudo journalctl -u mongo-backup.service -n 5 --no-pager
```

✅ **You should see** `Backup completato` twice: once from the manual run, once from the run through systemd.

<details>
<summary>📋 Real output from the test run</summary>

```
$ sudo /usr/local/bin/mongo-backup.sh
Backup completato: /var/backups/mongodb/daily/mongo-20260928-134803.archive.gz (4.0K)

$ sudo journalctl -u mongo-backup.service -n 5 --no-pager
Sep 28 13:48:08 mongo-vm systemd[1]: Starting mongo-backup.service - Backup MongoDB...
Sep 28 13:48:09 mongo-vm mongo-backup.sh[2405]: Backup completato: /var/backups/mongodb/daily/mongo-20260928-134809.archive.gz (4.0K)
Sep 28 13:48:09 mongo-vm systemd[1]: Finished mongo-backup.service - Backup MongoDB.
```

</details>

### 8.3 The restore command with TLS

```bash
sudo sh -c 'f=$(ls -t /var/backups/mongodb/daily/mongo-*.archive.gz | head -1); echo "Ripristino: $f"; \
  docker exec -i mongo sh -c "mongorestore --ssl --sslCAFile=/etc/mongo/tls/ca.pem -u admin -p \"\$(cat /run/secrets/mongo_root_password)\" --authenticationDatabase admin --archive --gzip --drop" < "$f"'
```

It is the same command as in guide 00 (Part 10.1), with `--ssl --sslCAFile=...` added. As before, `--drop` replaces the collections present in the backup.

✅ **At the end you should see:** `N document(s) restored successfully. 0 document(s) failed to restore.` If there are already documents in the database, N will be greater than zero: that is the most convincing proof that backup and restore work over TLS. You can check that the data is in place with the command from Part 8.4, replacing `db.runCommand({ ping: 1 })` with `db.<nome collezione>.find()`.

### 8.4 Commands with the application user

The commands in guide 00 that use `mongosh` need `--tls --tlsCAFile /etc/mongo/tls/ca.pem` added. For example, the check for `appuser`:

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.runCommand({ ping: 1 })"'
```

✅ Response: `{ ok: 1 }`

---

## Part 9 — Configure the clients

### 9.1 Bring `ca.pem` to your PC

Every client needs the CA certificate to verify the server. This is a **different** step from the copy of `ca.key` made in Part 5.2: that one was for safekeeping the key, this one is for the client.

> 📍 **From your PC**, in PowerShell (with `-i C:\percorso\della\chiave` if you access the VM with a key file):

```powershell
scp azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/ca.pem C:\Users\<tuo-nome>\mongodb-ca\ca.pem
dir C:\Users\<tuo-nome>\mongodb-ca
```

✅ `ca.pem` (about 1.8 KB) must appear in the listing, next to `ca.key` and `ca.srl` if you copied them to the same folder.

A path **without spaces**, like this one, is best: it saves you from having to encode the spaces in connection strings (see 9.2).

`ca.pem` **is not a secret**: it contains only the public part of the CA. You can also keep it in the project folder and share it with anyone who needs to connect. The files to protect, `ca.key`, `server.key` and `server.pem`, must on the other hand never end up in the repository.

### 9.2 The connection strings

Two parameters are added to all the strings from guide 00: `tls=true` and `tlsCAFile=<percorso di ca.pem>`.

| Where the client runs | Connection string |
|---|---|
| On the VM | `mongodb://appuser:PWD@127.0.0.1:27017/appdb?authSource=appdb&tls=true&tlsCAFile=/percorso/ca.pem` |
| Container in the same compose file | `mongodb://appuser:PWD@mongo:27017/appdb?authSource=appdb&tls=true&tlsCAFile=/percorso/ca.pem` |
| PC through the SSH tunnel | `mongodb://appuser:PWD@127.0.0.1:27017/appdb?authSource=appdb&directConnection=true&tls=true&tlsCAFile=C:/percorso/ca.pem` |
| PC with direct access | `mongodb://appuser:PWD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true&tls=true&tlsCAFile=C:/percorso/ca.pem` |

**Watch out for Windows paths:**

- use forward slashes (`C:/progetti/app/ca.pem`), not backslashes;
- if the path contains **spaces**, inside the connection string they must be written as `%20` (e.g. `C:/Github%20progetti/app/ca.pem`). Alternatively, and more conveniently, pass the path as a separate option in the code (see 9.3).

**For an application in another container** of the same compose file, mount the `./tls/ca.pem` file read-only in its service too, as was done for MongoDB, and use the path inside the container.

### 9.3 In the application

Keep the connection string and the CA path in the project's `.env` file (excluded from Git by the `.gitignore`):

```
MONGODB_URI=mongodb://appuser:PWD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true&tls=true
MONGODB_CA_FILE=C:/percorso con spazi/ca.pem
```

Example with Node.js and the official driver:

```javascript
const { MongoClient } = require("mongodb");

const client = new MongoClient(process.env.MONGODB_URI, {
  tlsCAFile: process.env.MONGODB_CA_FILE,
});
```

By passing `tlsCAFile` as a separate option, spaces in the path are not a problem. The other official drivers (Python, Java, .NET, Go…) have an equivalent option.

> 🚫 **Do not use** `tlsAllowInvalidCertificates=true` or `tlsInsecure=true` to "make a connection work": the traffic would still be encrypted, but the client would accept any server, even an impostor. If the client rejects the certificate, the cause is almost always an address missing from the SAN or the wrong `ca.pem` file: see Part 12.

### 9.4 MongoDB Compass

1. New connection → paste the connection string without `tlsCAFile`.
2. *Advanced Connection Options* → *TLS/SSL* tab.
3. *SSL/TLS Connection*: **On**.
4. *Certificate Authority (.pem)*: select the `ca.pem` file.
5. Leave the *tlsInsecure* and *tlsAllowInvalidCertificates* options **turned off**.

If you connect through the SSH tunnel configured in Compass, the TLS settings are added to those in the *Proxy/SSH* tab.

### 9.5 The MongoDB for VS Code extension

The extension uses the same connection engine as Compass. The connection saved before TLS no longer works: it has to be edited or recreated.

**Editing the existing connection:**

1. Open the **MongoDB** section in the VS Code sidebar (the leaf-shaped icon).
2. Right-click the connection → **Edit Connection** (depending on the version, the item may have a different name or appear when you hover over the connection).
3. In the connection string, add `&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem` at the end (if the string does not contain a `?` yet, the first parameter must be preceded by `?` instead of `&`); or, in the advanced options, **TLS/SSL** tab, set **On** and select `ca.pem` as the *Certificate Authority*.
4. Save and connect.

**Or create a new one:** command palette (**Ctrl+Shift+P**) → **MongoDB: Connect with Connection String**, and paste for example:

```
mongodb://appuser:PASSWORD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

For the administrator: `mongodb://admin:PASSWORD@<IP_PUBBLICO_VM>:27017/?authSource=admin&directConnection=true&tls=true&tlsCAFile=...`. Then delete the old connection (right-click → *Remove Connection*).

The passwords generated with the commands in these guides contain only letters and numbers, so they can be pasted into the string as they are; characters such as `@`, `:` or `/` would have to be encoded instead.

Once connected, the extension's *Playgrounds* use the encrypted connection too.

### 9.6 Can you do without the `ca.pem` file on the client?

A frequent question. It should be made clear that **there is no option on the server that allows this**: the server enforces encryption and presents its certificate; it is the **client** that decides whether to verify it, and to do so it must know which CA to trust. There are three possibilities:

| Solution | How | Protection |
|---|---|---|
| **Point to the file** (recommended) | `tlsCAFile` in the string or in the options, as in this guide | Full |
| **Install the CA in Windows** | Rename `ca.pem` to `ca.crt`, double-click → *Install Certificate* → *Current User* → **Trusted Root Certification Authorities** store. Then `tls=true` is enough in the string. It only works with programs that read the Windows store: recent versions of the MongoDB tools (Compass, mongosh, VS Code extension) and .NET applications usually do; Node.js, Java and Python instead have their own stores and need specific configuration | Full |
| **Turn off verification** | `tls=true&tlsAllowInvalidCertificates=true`, with no file | **Encryption only**: the client would accept an impostor server as well. To be used at most to unblock yourself temporarily, never with real data |

The file remains the simplest and most reliable solution: you copy it once, it is not a secret and it stays valid for the CA's whole ten years, even when you renew the server certificate.

### 9.7 The Azure firewall

TLS protects the traffic, **not** the database from people trying to guess passwords. The NSG rule on port 27017 must keep having only the authorized IPs as its source, never "Any".

---

## Part 10 — Renew the certificate

> 🧪 **Procedure not tested yet.** This part was written with care but, unlike Parts 2–9, it has not yet been run on a real installation. The `config/01-tls/genera-certificati-tls.sh` script has also only been tried in a test environment (creating and renewing the certificate), not on a VM with MongoDB running. If you run it, do so in a development environment first, keep the rollback from Part 11 at hand and report any differences from what is described here.

The server certificate expires after 825 days. Once it has expired, **no client can connect any more**: it is best to renew it a few weeks ahead.

### 10.1 Check the expiry date

> 📍 **On the VM:**

```bash
openssl x509 -in ~/mongodb/tls/server.crt -noout -enddate
openssl x509 -in ~/mongodb/tls/server.crt -noout -checkend $((30*86400)) && echo "OK: valido per almeno 30 giorni" || echo "ATTENZIONE: scade entro 30 giorni"
```

Put the expiry date in your calendar, with a reminder one month before.

### 10.2 Renew

1. **Bring the CA key and the counter back to the VM** (if you kept the key on the VM as well, skip this step). 📍 From your PC:

   ```powershell
   scp C:\Users\<tuo-nome>\mongodb-ca\ca.key C:\Users\<tuo-nome>\mongodb-ca\ca.srl azureuser@<IP_PUBBLICO_VM>:~/mongodb/tls/
   ```

2. **Regenerate the server certificate.** 📍 On the VM:

   ```bash
   cd ~/mongodb/tls
   chmod 600 ca.key
   openssl genrsa -out server.key 2048
   openssl req -new -key server.key -subj "/CN=mongo-vm" -out server.csr
   openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAserial ca.srl \
     -days 825 -sha256 -extfile server.ext -out server.crt
   rm server.csr
   openssl verify -CAfile ca.pem server.crt
   cat server.crt server.key | sudo tee server.pem > /dev/null
   sudo chown 999:999 server.pem && sudo chmod 600 server.pem
   chmod 600 server.key
   ```

   `server.ext` is the one created in Part 4.2. If the addresses have changed in the meantime, edit it first (for example with `nano server.ext`).

3. **Restart MongoDB** so that it reads the new certificate:

   ```bash
   cd ~/mongodb && sudo docker compose restart
   ```

4. **Verify** with the commands from Parts 7.2 and 7.4, then check the new expiry date (10.1).

5. **Put the CA back in a safe place:** copy the updated `ca.srl` to the PC (📍 from the PC, as in Part 5.2). If you had chosen not to keep the key on the VM (Part 5.2, option A), delete it again with `shred -u ~/mongodb/tls/ca.key`.

✅ **The clients don't have to change anything:** the new certificate is signed by the same CA, and their `ca.pem` remains valid.

> As an alternative to steps 2–3, the `config/01-tls/genera-certificati-tls.sh` script in the repository reuses the existing CA and regenerates only the server certificate.

### 10.3 And when the CA expires?

In ten years `ca.pem` will expire too. At that point a new CA must be created (Part 3), a new server certificate signed and **the new `ca.pem` distributed to all the clients**.

---

## Part 11 — Rolling back (disabling TLS)

> 🧪 **Procedure not tested yet.** This part was written with care but has not yet been run on a real installation. Before relying on it in an emergency, it is worth trying it once in a development environment: it is short and does not touch the data.

If something does not work and you need to put everything back the way it was, for example to unblock an application:

```bash
cd ~/mongodb
cp docker-compose.yml docker-compose.yml.tls
cp docker-compose.yml.pre-tls docker-compose.yml
sudo docker compose up -d
```

**What it does:** it saves the configuration with TLS (so you can re-enable it later), restores the previous one and recreates the container. The data is not touched.

- The backup script from Part 8.1 keeps working, because it detects the absence of TLS by itself.
- In the clients, the `tls=true` and `tlsCAFile` parameters must be removed.

To re-enable TLS: `cp docker-compose.yml.tls docker-compose.yml && sudo docker compose up -d`.

---

## Part 12 — When something goes wrong

### Server side

| Symptom | Likely cause | Solution |
|---|---|---|
| Container in `Restarting` state, with certificate read errors or `Permission denied` in the logs | `server.pem` not readable by user 999 | `sudo chown 999:999 ~/mongodb/tls/server.pem && sudo chmod 600 ~/mongodb/tls/server.pem`, then `sudo docker compose restart` |
| Container fails right after starting, logs with `No such file` | Wrong paths for the mounted files, or files missing from `~/mongodb/tls` | Check with `ls -l ~/mongodb/tls` and the `volumes` lines of the compose file |
| Error about the private key not matching the certificate | `server.pem` built with a key different from the certificate's | Regenerate `server.pem` with `cat server.crt server.key` (Part 4.5) |
| `compose valido` does not appear | Indentation error in the compose file | Copy the block from Part 6.1 again in full |
| The nightly backups fail after TLS is enabled | Old backup script, without TLS | Install the script from Part 8.1 |

### Client side

| Message (or similar) | Likely cause | Solution |
|---|---|---|
| `connection closed`, `ECONNRESET`, `MongoServerSelectionError` straight away | The client is not using TLS | Add `tls=true` to the connection string |
| `certificate verify failed`, `unable to get local issuer certificate`, `self-signed certificate in certificate chain` | The client does not have the right `ca.pem` | Check the `tlsCAFile` path and that the file is this CA's `ca.pem` |
| `Hostname/IP does not match certificate's altnames`, `IP address mismatch` | You are connecting to an address that is not in the SAN | Use one of the addresses in the SAN (`openssl x509 -in server.crt -noout -ext subjectAltName`), or add the address and renew the certificate (Part 10) |
| `certificate has expired` | Server certificate expired | Renew it (Part 10) |
| `No SSL certificate provided by peer` (in the server logs) | `--tlsAllowConnectionsWithoutCertificates` is missing | Add the option to the `command` block and run `sudo docker compose up -d` |
| Error on the CA file with a Windows path | Backslashes or spaces in the connection string | Use `/` instead of `\`, `%20` instead of spaces, or the separate option (Part 9.3) |
| `Authentication failed` | Not a TLS problem: wrong password | See guide 00, Part 15 |

### During the procedure

| Symptom | Cause | Solution |
|---|---|---|
| `SyntaxError: Missing semicolon` after a `sudo ...` command | The command was typed inside the MongoDB shell (`test>` prompt) | Leave with `exit` and run it again in the VM's terminal |
| `mongodump: command not found` | Only some lines of the backup script were pasted | Paste the whole block from Part 8.1, from `sudo tee` to `sudo chmod` |
| A folder called `C:Users...` appears on the VM | A PowerShell command (`mkdir C:\...`) was run on the VM | `rmdir 'C:Users...'` on the VM, then run the command again in PowerShell on the PC |
| `scp` asks for a password | You access the VM with a password and not with a key | Normal: enter the password. To switch to SSH keys see guide 00, Part 13.2 |
| `scp`: `No such file or directory` on the destination | The destination folder on the PC does not exist | Create it first with `mkdir` in PowerShell |
| `scp`: `Permission denied (publickey)` | SSH key not specified or wrong | Use the same `-i ...` and the same user as in the `ssh` command you use to get into the VM |
| `ca.pem` is not in the folder on the PC | Only the CA key was copied (Part 5.2) | Do the copy from Part 9.1 |
| A client that used to work no longer connects | With `requireTLS`, connections without TLS are rejected | Update the client as in Part 9 |

### Quick diagnosis

To work out whether the problem is in TLS or elsewhere, from the VM:

```bash
openssl s_client -connect 127.0.0.1:27017 -CAfile ~/mongodb/tls/ca.pem </dev/null 2>/dev/null | grep "Verify return code"
```

- `0 (ok)`: on the server side TLS is fine; the problem is in the client's configuration.
- Any other code: the problem is in the certificate or in the server's configuration.

---

## Part 12 bis — The choices: lab and production

This guide was tested on the development instance from guide 00, with a single client (VS Code). The choices depend on that context:

| Choice | In the lab (tested) | Why | In production |
|---|---|---|---|
| Certificate authority | Private CA created on the VM, valid for 10 years | No corporate CA available; zero cost | Corporate or public CA (the clients already know it) |
| CA key | Copy on the PC, kept on the VM **as well** (option B) | Simpler renewals in development | Only offline or in a secrets manager; never on the servers |
| Server certificate | Public and private IP in the SAN, 825 days | The VM did not have a DNS name yet | DNS names, automatic and monitored renewal |
| Activation | Recreating the instance (a few seconds of downtime) | Single instance, a single client | Rolling migration on a replica set (guide 02) |
| Client authentication | User name and password over TLS (`tlsAllowConnectionsWithoutCertificates`) | Simplicity | Passwords or x.509 client certificates, depending on policy |
| Exposure | Port 27017 reachable only from your own IP (NSG) | Development from an external PC | Private network only |
| Protocols | TLS 1.2 and 1.3 | Current standard | Same |

What TLS does **not** do: it encrypts data **in transit**, not data **stored on disk**, which in MongoDB Community is protected with disk encryption (enabled by default on Azure).

---

## Part 13 — Toward production

The procedure in this guide is correct for production as well, with a few differences:

- **Certificates from a recognized CA.** A corporate CA already distributed to the computers, or a public CA such as Let's Encrypt (you need a DNS name and an automatic renewal every 90 days). In both cases the clients do not need to receive `ca.pem`.
- **DNS names instead of IP addresses** in the SAN: they are more stable and easier to manage.
- **No exposure to the internet:** application and database communicate over the Azure private network; TLS protects that stretch too.
- **CA key in a dedicated system**, such as Azure Key Vault, with controlled and logged access.
- **Monitoring of certificate expiry**, with automatic alerts.
- **Replica set and sharding:** besides the client connections, those **between the nodes** must be encrypted too. In this scenario x.509 certificates can also be used to authenticate the cluster members to one another, in place of the keyFile.

---

## Appendix A — Where everything lives

| What | Where |
|---|---|
| Certificates folder | `~/mongodb/tls` (permissions `700`) |
| CA certificate | `~/mongodb/tls/ca.pem` → in the container `/etc/mongo/tls/ca.pem` |
| Server certificate + key | `~/mongodb/tls/server.pem` → in the container `/etc/mongo/tls/server.pem` |
| SAN settings for renewals | `~/mongodb/tls/server.ext` |
| CA key | On the PC, in a safe folder outside the repository (e.g. `C:\Users\<tuo-nome>\mongodb-ca`), with `ca.srl`; optionally also on the VM with permissions `600` (Part 5.2, option B) |
| CA certificate for the clients | On the PC, e.g. `C:\Users\<tuo-nome>\mongodb-ca\ca.pem` |
| Compose file with TLS | `~/mongodb/docker-compose.yml` (copied to `docker-compose.yml.tls` after a rollback) |
| Compose file without TLS | `~/mongodb/docker-compose.yml.pre-tls` |
| Backup script (TLS-compatible) | `/usr/local/bin/mongo-backup.sh` |

---

## Appendix B — Command cheat sheet

```bash
# Admin shell with TLS
sudo docker exec -it mongo mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem -u admin -p --authenticationDatabase admin

# Check the certificate presented by the server
openssl s_client -connect 127.0.0.1:27017 -CAfile ~/mongodb/tls/ca.pem </dev/null 2>/dev/null | grep -E "Verify return code|Protocol"

# Valid addresses and certificate expiry date
openssl x509 -in ~/mongodb/tls/server.crt -noout -ext subjectAltName -enddate

# Does it expire within 30 days?
openssl x509 -in ~/mongodb/tls/server.crt -noout -checkend $((30*86400)) && echo OK || echo "IN SCADENZA"

# Backup (detects TLS by itself)
sudo /usr/local/bin/mongo-backup.sh

# Roll back to no TLS
cd ~/mongodb && cp docker-compose.yml docker-compose.yml.tls && cp docker-compose.yml.pre-tls docker-compose.yml && sudo docker compose up -d
```

**Parameters to add to the connection strings:**

```
&tls=true&tlsCAFile=<percorso di ca.pem>
```

---

## The 6 golden rules of TLS

1. **Encrypting is not enough, you must verify:** never use `tlsAllowInvalidCertificates` or `tlsInsecure`.
2. **`ca.key` is the most precious file:** off the VM, out of the repository, in a safe place.
3. **`ca.pem` is public:** hand it out freely to the clients.
4. **The SAN must contain every address** you connect with; if you add one, renew the certificate.
5. **Put the expiry date in your calendar:** an expired certificate blocks all the clients in one go.
6. **TLS does not replace the firewall:** port 27017 stays open only to authorized IPs.
