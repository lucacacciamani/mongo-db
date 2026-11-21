# MongoDB on Debian 13 with Docker — Complete step-by-step guide

**Who this guide is for:** anyone who has to install MongoDB on a Linux virtual machine in Azure and doesn't have much experience with Linux, Docker or MongoDB. Every step explains **what to do**, **what the command does** and **what you should see** if everything went well.

**What you will have at the end:**

- MongoDB 8.0 up and running, protected by a password, restarting on its own;
- a dedicated user for your application;
- automatic backups every night, kept for days, weeks and months;
- the ability to connect to the database from your development PC;
- an operating system that updates itself with security patches.

**Estimated time:** 1–2 hours, taking it easy.

> 📖 **Commands and symbols** (`sudo`, `chmod`, `|`, `<< EOF`, `docker compose`…): the [command legend](linux-commands-legend.md) explains everything that appears in this guide.

---

## Contents

- [Part 0 — Basic concepts (read it, even if you're in a hurry)](#part-0--basic-concepts-read-it-even-if-youre-in-a-hurry)
- [Part 1 — How to use this guide](#part-1--how-to-use-this-guide)
- [Part 2 — Connecting to the virtual machine](#part-2--connecting-to-the-virtual-machine)
- [Part 3 — Preliminary checks](#part-3--preliminary-checks)
- [Part 4 — Installing Docker](#part-4--installing-docker)
- [Part 5 — Preparing the system for MongoDB](#part-5--preparing-the-system-for-mongodb)
- [Part 6 — Configuring MongoDB](#part-6--configuring-mongodb)
- [Part 7 — Starting MongoDB and checking that it works](#part-7--starting-mongodb-and-checking-that-it-works)
- [Part 8 — Creating the user for your application](#part-8--creating-the-user-for-your-application)
- [Part 9 — Automatic backups](#part-9--automatic-backups)
- [Part 10 — Restoring a backup](#part-10--restoring-a-backup)
- [Part 11 — Connecting from your development PC](#part-11--connecting-from-your-development-pc)
- [Part 12 — Managing the space taken up by logs](#part-12--managing-the-space-taken-up-by-logs)
- [Part 13 — Securing the system](#part-13--securing-the-system)
- [Part 14 — Everyday use and maintenance](#part-14--everyday-use-and-maintenance)
- [Part 15 — When something goes wrong](#part-15--when-something-goes-wrong)
- [Part 16 — Before going to production](#part-16--before-going-to-production)
- [Appendix A — Where everything is](#appendix-a--where-everything-is)
- [Appendix B — Command cheat sheet](#appendix-b--command-cheat-sheet)
- [The 7 golden rules](#the-7-golden-rules)

---

## Part 0 — Basic concepts (read it, even if you're in a hurry)

Understanding these few words will save you from most mistakes.

**Virtual machine (VM).** A "pretend" computer running in the Microsoft Azure data centres. It behaves like a real Linux server: you log in remotely and run commands. In this guide the VM is called `mongo-vm`.

**Terminal.** The window where you type text commands instead of clicking. On your Windows PC it is *PowerShell* or *Windows Terminal*; on the VM it is the Linux *shell* (called *bash*).

**SSH.** The system you use to connect to the VM's terminal from your PC. Everything you type after connecting is executed **on the VM**, not on your computer.

**Prompt.** The text that appears before the cursor, for example:

```
azureuser@mongo-vm:~/mongodb$
```

It tells you **who you are** (`azureuser`), **where you are** (`mongo-vm`, that is, the VM) and **in which folder** (`~/mongodb`, where `~` means "your home folder"). Always look at it: it is the simplest way to tell whether you are working on the VM or on your PC.

**sudo.** Placed in front of a command, it runs it with administrator permissions (like "Run as administrator" in Windows). The first time, it may ask for your user's password.

**apt.** Debian's "app store": it installs, updates and removes programs.

**MongoDB.** The database we want to install. It stores data as *documents* (similar to JSON), grouped into *collections*, which in turn are grouped into *databases*.

**mongosh.** The MongoDB "shell": a terminal where you type commands addressed to the database.

**Docker.** A program that runs applications inside isolated boxes, called *containers*. It is like having MongoDB "pre-packaged" with everything it needs, without having to install it piece by piece on the system.

- **Image:** the "package" downloaded from the internet (here `mongo:8.0`). It is a template and is never modified.
- **Container:** the image while it is running. Our container is called `mongo`.
- **Volume:** the disk space where the container stores data permanently. If the container is deleted and recreated, **the data in the volume stays**. Our volume is called `mongo-data`.
- **Docker Compose:** a text file (`docker-compose.yml`) that describes how the container must be started: which image, which ports, which settings. Instead of remembering very long commands, you write everything once in the file.

**Port.** A "counter number" on which a program waits for connections. MongoDB uses port **27017**, SSH uses port **22**.

**127.0.0.1 (localhost).** A special address that means "this very computer". A service listening on `127.0.0.1` can be reached **only** from the machine it runs on, not from outside.

**NSG (Network Security Group).** The Azure firewall: it decides which connections from the internet can reach the VM. You configure it from the Azure portal.

**Why Docker and not the "classic" installation?** MongoDB does not yet publish official packages for Debian 13. With Docker the problem doesn't exist, because the image already contains everything that is needed. On top of that, updating or removing MongoDB becomes much simpler.

> **If you have an old guide** with commands such as `apt-key add`, `buster/mongodb-org/5.0` or `mongodb-org-shell`: don't use it. `apt-key` no longer exists on Debian 13, MongoDB 5.0 no longer receives security updates and the old `mongo` shell has been replaced by `mongosh`.

---

### The big picture

Here is how the pieces we are going to install connect to each other (the diagram is drawn directly by GitHub):

```mermaid
flowchart LR
    PC["Your PC<br/>PowerShell, VS Code"]
    subgraph AZ["Azure"]
        NSG["NSG<br/>Azure firewall"]
        subgraph VM["Debian 13 VM"]
            DK["Docker"]
            MG["mongo container<br/>MongoDB 8.0"]
            VOL[("mongo-data volume<br/>the data")]
            TM["systemd timer<br/>02:30 UTC"]
            BK[("/var/backups/mongodb")]
        end
    end
    PC -- "SSH, port 22" --> NSG
    PC -. "27017: SSH tunnel<br/>or direct access" .-> NSG
    NSG --> VM
    DK --> MG
    MG --- VOL
    TM -- "mongo-backup.sh" --> MG
    MG -- "mongodump" --> BK
```

---

## Part 1 — How to use this guide

### 1.1 Command blocks

The commands to run are in boxes like this one:

```bash
sudo apt-get update
```

Copy the contents of the box and paste them into the terminal, then press **Enter**.

**How to paste into the terminal:**

- in PowerShell / Windows Terminal: **right mouse button** or **Ctrl+V**;
- in Linux terminals: **Ctrl+Shift+V** (plain Ctrl+V usually doesn't work).

If a box contains several lines, you can paste them all together: they are executed one after the other.

### 1.2 Blocks that create files (very important)

Many boxes look like this:

```bash
sudo tee /percorso/del/file > /dev/null << 'EOF'
...contenuto del file...
EOF
```

It means: "create the file with this content". The content is everything between the first line and the final word `EOF`.

**You must paste the whole block, from the first line to the last, `EOF` included.** While you paste, the terminal shows a `>` symbol at the start of every line: this is normal, it means it is receiving the file's content. When it reaches the `EOF` line, the file is written and the normal prompt comes back.

The most common mistake is copying only part of the block: the file is not created and the following commands fail with errors such as `No such file or directory`.

### 1.3 Placeholders

The parts between `< >`, such as `<IP_PUBBLICO_VM>`, are **placeholders**: they must be replaced with the real value, **removing the `<` and `>` symbols too**.

Example: `ssh azureuser@<IP_PUBBLICO_VM>` becomes `ssh azureuser@20.123.45.67`.

| Placeholder | What to put in | Where to find it |
|---|---|---|
| `<IP_PUBBLICO_VM>` | Public address of the VM | Azure portal → your VM → *Overview* → *Public IP address* |
| `<IP_PRIVATO_VM>` | Internal address of the VM (e.g. `10.0.0.4`) | Command in Part 11.2 |
| `<IL_TUO_IP>` | Public address of your PC/office | Search for "what is my ip" in your PC's browser |

In this guide the VM user is `azureuser`: if yours is different, replace it.

### 1.4 "Nothing happened": that's normal

In Linux, **a command that succeeds often prints nothing**. If you press Enter and the prompt comes straight back with no messages, it usually means everything went well. Errors, on the other hand, are always reported with a message.

### 1.5 Useful keys

| Key | Effect |
|---|---|
| **Ctrl+C** | Interrupts the running command (for example to leave the log view) |
| **Up arrow** | Recalls previous commands |
| **Tab** | Automatically completes file and folder names |
| `clear` + Enter | Clears the screen |

### 1.6 Passwords and chat

During the guide some random passwords will be generated. **Never copy them into chats, emails, tickets or documents**, and when you ask for help by pasting terminal output, check that it doesn't contain a password. If it happens by mistake, change it straight away (the instructions are in the guide).

---

## Part 2 — Connecting to the virtual machine

> 📍 **Where:** on your PC.

### 2.1 Opening the terminal on the PC

On Windows 10/11 press the Windows key, type **PowerShell** and open it. The `ssh` command is already included in Windows, there is nothing to install.

### 2.2 Connecting

When you created the VM on Azure you chose an access method: usually an **SSH key** (a `.pem` file downloaded at creation time).

```powershell
ssh -i C:\percorso\della\chiave.pem azureuser@<IP_PUBBLICO_VM>
```

- The first time, it asks you to confirm the identity of the server: type `yes` and press Enter.
- If all goes well, the prompt changes to `azureuser@mongo-vm:~$`: **you are now on the VM**.

If the connection fails, see [Part 15](#part-15--when-something-goes-wrong), entry "I can't connect to the VM with SSH".

### 2.3 Leaving the VM

Type `exit` and press Enter: you go back to your PC's terminal.

---

## Part 3 — Preliminary checks

> 📍 **Where:** on the VM (prompt `azureuser@mongo-vm`).

### 3.1 Does the CPU support MongoDB 8.0?

MongoDB 8.0 requires a processor feature called AVX.

```bash
grep -o avx /proc/cpuinfo | head -1
```

✅ **You should see:** `avx`
❌ **If nothing appears:** the VM is not suitable for MongoDB 8.0; choose a different VM size on Azure.

### 3.2 Updating the list of available programs

```bash
sudo apt-get update
```

**What it does:** downloads the up-to-date list of installable programs. It doesn't install anything.

✅ **You should see:** several `Get:` or `Hit:` lines and, at the end, `Reading package lists... Done`.

---

## Part 4 — Installing Docker

> 📍 **Where:** on the VM.

### 4.1 Removing any unofficial versions

Debian offers its own version of Docker, which can conflict with the official one. To be safe, we remove it:

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y $pkg
done
```

✅ **Messages such as `Unable to locate package` or `is not installed` are normal:** they mean there was nothing to remove.

### 4.2 Adding the official Docker "source"

We tell apt to download Docker directly from the Docker website, verifying its authenticity with a signing key.

```bash
sudo apt-get install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

**What it does, line by line:**

1. installs two required tools (certificates and `curl`, for downloading files);
2. creates the folder where signing keys are kept;
3. downloads Docker's signing key;
4. makes it readable;
5. adds the Docker repository to apt's list of sources (the `$(...)` part automatically inserts the name of your Debian version, `trixie`).

✅ **You should see:** no errors. The last commands print nothing.

### 4.3 Installing Docker

```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

**What it does:** updates the list (it now includes Docker), installs Docker and the Compose plugin, then starts Docker and sets it to start automatically every time the VM is switched on.

The installation downloads about 120 MB and takes roughly a minute.

### 4.4 Checking that Docker works

```bash
sudo docker run --rm hello-world
```

✅ **You should see:** among the various lines, the message **`Hello from Docker!`**.

> **A note on `sudo`:** in this guide all Docker commands use `sudo`. There is a way to avoid it (`sudo usermod -aG docker $USER`), but it amounts to giving your user full administrator powers: better to leave it alone until you clearly understand why you would want it.

---

## Part 5 — Preparing the system for MongoDB

> 📍 **Where:** on the VM.

MongoDB 8.0 works better with a particular configuration of the system's memory (the *Transparent Huge Pages*). The container uses the VM's system, so the setting has to be made on the VM.

```bash
sudo tee /etc/tmpfiles.d/mongodb-thp.conf > /dev/null << 'EOF'
w /sys/kernel/mm/transparent_hugepage/enabled - - - - always
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
w /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 0
EOF
sudo systemd-tmpfiles --create /etc/tmpfiles.d/mongodb-thp.conf
```

**What it does:** creates a configuration file that applies the settings every time the VM starts, then applies them straight away without having to reboot.

**Check:**

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
```

✅ **You should see:** a line in which `always` is in square brackets, like this: `[always] madvise never`.

---

## Part 6 — Configuring MongoDB

> 📍 **Where:** on the VM.

### 6.1 Creating the working folder

All the MongoDB files will live in a dedicated folder:

```bash
mkdir -p ~/mongodb
cd ~/mongodb
```

✅ The prompt becomes `azureuser@mongo-vm:~/mongodb$`.

> ⚠️ **From here on, `docker compose` commands only work if you are inside this folder.** If you close and reopen the session, remember to go back into it with `cd ~/mongodb`.

### 6.2 Creating the administrator password

Instead of making up a password, we generate a strong random one and save it in a file:

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee mongo_root_password.txt > /dev/null
sudo chown 999:999 mongo_root_password.txt
sudo chmod 600 mongo_root_password.txt
```

**What it does:**

1. generates a random password of about 30 characters (letters and digits) and writes it to the file `mongo_root_password.txt`;
2. assigns the file to the user with number **999**: this is the user MongoDB runs as inside the container, and it must be able to read the password;
3. makes the file readable **only** by that user (and by the administrator).

**To read the password when you need it:**

```bash
sudo cat ~/mongodb/mongo_root_password.txt
```

> 🔐 Save this password in a password manager as well. If you lose both the file and the password, you lose administrator access to the database.

### 6.3 Creating the Docker Compose configuration file

Paste the **whole** block:

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

**What each part means:**

| Line | Meaning |
|---|---|
| `image: mongo:8.0` | Uses the official MongoDB image, version 8.0 (with the latest available fix) |
| `container_name: mongo` | The container will be called `mongo` |
| `restart: unless-stopped` | If it stops or the VM reboots, it starts again on its own (unless you stopped it yourself) |
| `stop_grace_period: 1m` | On shutdown, Docker waits up to one minute for MongoDB to close down cleanly on its own, instead of the default 10 seconds after which it would kill it forcibly |
| `ports: "127.0.0.1:27017:27017"` | MongoDB can be reached on port 27017, **but only from the VM itself** |
| `ulimits` | Lets MongoDB open many files at the same time, as recommended |
| `logging` | Limits the space used by logs: at most 5 files of 50 MB each |
| `MONGO_INITDB_ROOT_USERNAME` | Creates the administrator user `admin` on first start |
| `MONGO_INITDB_ROOT_PASSWORD_FILE` | Reads the `admin` password from the file created earlier |
| `volumes: mongo-data:/data/db` | Stores the data in the `mongo-data` volume, so that it outlives the container |
| `secrets` | Passes the password file to the container securely |

> ⚠️ **The YAML file is sensitive to spaces.** The indentation (the spaces at the start of a line) must be exact and made with spaces, never with the Tab key. That is why it is better to paste the block as it is rather than retype it by hand.

> ⚠️ **Never change `127.0.0.1:27017:27017` to `27017:27017` or `0.0.0.0:27017:27017`.** Docker bypasses the Linux firewall, and the database would end up exposed to everyone.

### 6.4 Checking that the file is written correctly

```bash
sudo docker compose config --quiet && echo "compose valido"
```

✅ **You should see:** `compose valido`
❌ **If an error appears:** the block was probably not pasted in full. Repeat step 6.3.

---

## Part 7 — Starting MongoDB and checking that it works

> 📍 **Where:** on the VM, in the `~/mongodb` folder.

### 7.1 Starting

```bash
sudo docker compose up -d
```

**What it does:** downloads the MongoDB image (only the first time, a few hundred MB) and starts the container. `-d` means "in the background": the terminal is free again.

✅ **You should see:** lines with `Created` and `Started`.

### 7.2 Looking at the startup logs

```bash
sudo docker compose logs -f mongo
```

Lots of technical lines will scroll by: don't be alarmed. On first start MongoDB starts twice: a first time to create the administrator user, then for good.

✅ **You should see, towards the end:** `MongoDB init process complete; ready for start up.` and then `Waiting for connections`.

When you see them, press **Ctrl+C** to exit. The database keeps running.

### 7.3 Connecting to the database as administrator

```bash
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin
```

**What it does:** opens `mongosh` inside the container, as the `admin` user.

It will ask for the password (`Enter password:`). Get it with `sudo cat ~/mongodb/mongo_root_password.txt` and paste it: while you paste it you will only see asterisks.

✅ **You should see:** `Using MongoDB: 8.0.x` and the prompt `test>`.

Try a command:

```javascript
db.runCommand({ ping: 1 })
```

✅ Reply: `{ ok: 1 }`

To leave `mongosh` type `exit` or press **Ctrl+D**.

### 7.4 Checking the warnings

When you log in, `mongosh` may show a box saying "The server generated these startup warnings". With this configuration **only** the warning about the XFS filesystem should appear, and you can ignore it for now (see Part 16).

To check warnings and errors in the future without reading all the logs:

```bash
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'
```

`W` = warning, `E` = error, `F` = fatal error.

> Warnings containing `Use of deprecated server parameter` and `"ctx":"ftdc"` are **harmless**: they come from an internal MongoDB diagnostics system and appear at every start.

---

## Part 8 — Creating the user for your application

> 📍 **Where:** on the VM, in the `~/mongodb` folder.

**Why it is needed:** the `admin` user can do anything, including deleting every database. Your application must use a user that can work **only on its own database**: if one day the application's password were stolen, the damage would stay limited.

In this guide the database is called `appdb` and the user `appuser`. You can use different names: replace them wherever they appear.

### 8.1 Generating the user's password

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee ~/mongodb/appuser_password.txt > /dev/null
sudo chmod 600 ~/mongodb/appuser_password.txt
```

### 8.2 Creating the user

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("appdb").createUser({ user: "appuser", pwd: process.env.APP_PWD, roles: [ { role: "readWrite", db: "appdb" } ] })'
```

**What it does:** reads the new password from the file and passes it to MongoDB, which creates the user `appuser` with permission to read and write (`readWrite`) only in the `appdb` database. It asks you for the **admin** password.

✅ **You should see:** `{ ok: 1 }`

> **Why not simply paste the password?** When you paste a password into the interactive `mongosh` prompt, some terminals add invisible characters, and MongoDB replies with the error `U_STRINGPREP_PROHIBITED_ERROR`. Reading it from the file avoids the problem.

> The `appdb` database does not have to be created beforehand: MongoDB creates it on its own when the application writes to it for the first time.

### 8.3 Checking that the user works

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.runCommand({ ping: 1 })"'
```

✅ **You should see:** `{ ok: 1 }`

### 8.4 Changing the user's password (when needed)

For example if it was copied somewhere by mistake:

```bash
openssl rand -base64 24 | tr -d '/+=' | sudo tee ~/mongodb/appuser_password.txt > /dev/null

sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  mongosh -u admin -p --authenticationDatabase admin --quiet \
  --eval 'db.getSiblingDB("appdb").changeUserPassword("appuser", process.env.APP_PWD)'
```

⚠️ **Run both commands, in order.** The first generates the new password, the second tells MongoDB about it. If you run only the second, you set the old password again.

After the change, remember to update the password in your application's configuration too.

### 8.5 The connection string for the application

The application connects to MongoDB with a "connection string", which contains user, password, address and database. Choose the one that fits:

| Where the application runs | Connection string |
|---|---|
| On the VM itself | `mongodb://appuser:PASSWORD@127.0.0.1:27017/appdb?authSource=appdb` |
| In another container of the same `docker-compose.yml` | `mongodb://appuser:PASSWORD@mongo:27017/appdb?authSource=appdb` |
| On your PC, through an SSH tunnel (Part 11.1) | `mongodb://appuser:PASSWORD@127.0.0.1:27017/appdb?authSource=appdb&directConnection=true` |
| On your PC, with direct access (Part 11.2) | `mongodb://appuser:PASSWORD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true` |

In place of `PASSWORD` put the one you read with `sudo cat ~/mongodb/appuser_password.txt`.

> 🔐 In the application's project, put the connection string in a `.env` file (or in environment variables) and add `.env` to the `.gitignore` file, so the password doesn't end up in the code repository.

---

## Part 9 — Automatic backups

> 📍 **Where:** on the VM.

**How it works:** every night a script saves a compressed copy of all the databases. The copies are kept as follows:

| Type | When it is created | How many copies are kept |
|---|---|---|
| Daily | Every night | Last **7 days** |
| Weekly | Every Sunday | Last **4 weeks** |
| Monthly | On the first of every month | Last **12 months** |

The weekly and monthly copies take up no extra space as long as the daily copy of the same day still exists (they are *hard links*: the same file seen from two folders).

The flow of a nightly backup:

```mermaid
sequenceDiagram
    participant T as systemd timer
    participant S as mongo-backup.sh
    participant C as mongo container
    participant D as Backup folder
    T->>S: every night at 02:30 UTC
    S->>C: docker exec, mongodump --archive --gzip
    C-->>S: compressed archive
    S->>D: saves to daily/ with 600 permissions
    S->>D: Sunday to weekly/, day 1 to monthly/ (hard link)
    S->>D: deletes files past the retention period
    Note over S: if the dump fails, set -e stops the script<br/>before the cleanup: the old backups stay
```

### 9.1 Creating the backup folder

```bash
sudo mkdir -p /var/backups/mongodb
sudo chmod 700 /var/backups/mongodb
```

The folder is accessible only to the administrator: the backups contain all the data.

### 9.2 Creating the backup script

Paste the **whole** block, up to and including the `EOF` line, then the two lines after it:

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

✅ **The last command should show:** `#!/bin/bash`, `set -euo pipefail`, `umask 077`.
❌ **If it says `No such file or directory`:** the block was not pasted in full. Try again.

**What the script does, in plain words:**

1. it stops immediately at the first thing that goes wrong (`set -euo pipefail`), so it never deletes the old backups if the new one failed;
2. it makes sure the files it creates are readable only by the administrator (`umask 077`);
3. it asks MongoDB, inside the container, to export all the data into a single compressed file (`mongodump`); the password is passed through a temporary file, so it is not visible to other programs;
4. if it is Sunday, it "copies" the backup into the `weekly` folder; if it is the first of the month, into `monthly`;
5. it deletes the backups older than the retention period;
6. it writes a confirmation message with the size of the file.

**To change how long backups are kept**, edit the three `KEEP_...` lines at the top of the script. For example, for 14 days of daily backups:

```bash
sudo sed -i 's/^KEEP_DAILY=.*/KEEP_DAILY=14      # giorni/' /usr/local/bin/mongo-backup.sh
sudo grep KEEP_ /usr/local/bin/mongo-backup.sh
```

### 9.3 Trying the backup by hand

```bash
sudo /usr/local/bin/mongo-backup.sh
sudo ls -lhR /var/backups/mongodb
```

✅ **You should see:** `Backup completato: /var/backups/mongodb/daily/mongo-AAAAMMGG-HHMMSS.archive.gz` and, in the listing, the file with permissions `-rw-------`.

With an almost empty database the file is only 1–4 KB: that's normal.

> **If you enable TLS** (guide `01-tls-complete-guide.md`), this script will no longer be able to connect: it will have to be replaced with the version from guide 01, which works both with and without TLS.

### 9.4 Scheduling the backup every night

> Tested: manual backup, execution through systemd, automatic nightly execution (also with the TLS from guide 01 enabled) and restore. The creation of the weekly (Sunday) and monthly (day 1) copies and the expiry cleanup have not yet been observed over a real period 🧪.

We use systemd *timers*; systemd is the system that manages services and scheduled tasks in Debian. Two files are needed: one that says **what** to do (`.service`) and one that says **when** (`.timer`). Paste the whole block:

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

✅ **You should see:** a line with the date of the next run at `02:30:00 UTC`.

**Good to know:**

- The VM uses **UTC** time. 02:30 UTC is **04:30 in Italy** during daylight saving time and **03:30** during standard time.
- `Persistent=true`: if the VM was switched off at the scheduled time, the backup starts as soon as it is switched back on.
- To change the time, edit the `OnCalendar` line in the file `/etc/systemd/system/mongo-backup.timer` (for example with `sudo nano`) and then run `sudo systemctl daemon-reload`.

### 9.5 Checking that it also works automatically

We launch the backup "as if it were night", through systemd:

```bash
sudo systemctl start mongo-backup.service
sudo journalctl -u mongo-backup.service -n 10 --no-pager
```

✅ **You should see:** `Backup completato: ...` and `Finished mongo-backup.service`.

<details>
<summary>📋 Real output from the test run</summary>

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

In the future, with the same `journalctl` command you can check how each night's backup went.

### 9.6 How much space the backups take up

```bash
sudo du -sh /var/backups/mongodb
```

Check it from time to time, especially once the database starts to grow.

> ⚠️ **Watch out for the asterisk.** The backup folder is readable only by the administrator, so a command such as `sudo chmod 600 /var/backups/mongodb/daily/*` fails with `No such file or directory`: the asterisk is interpreted by your user before `sudo`, and your user cannot see the files. Always use the form: `sudo sh -c 'comando con /var/backups/mongodb/daily/*'`.

---

## Part 10 — Restoring a backup

> 📍 **Where:** on the VM.

"Restoring" means bringing the database back to the state saved in a backup.

### 10.1 Restoring the most recent backup

```bash
sudo sh -c 'f=$(ls -t /var/backups/mongodb/daily/mongo-*.archive.gz | head -1); echo "Ripristino: $f"; \
  docker exec -i mongo sh -c "mongorestore -u admin -p \"\$(cat /run/secrets/mongo_root_password)\" --authenticationDatabase admin --archive --gzip --drop" < "$f"'
```

**What it does:** finds the most recent daily backup, shows which one it is using and passes it to `mongorestore`, which loads it back into the database.

⚠️ `--drop` means that **the collections present in the backup are replaced** with the saved version: changes made to those collections after the backup are lost.

✅ **You should see, at the end:** `N document(s) restored successfully. 0 document(s) failed to restore.`

The users (`admin`, `appuser`) are restored too: they appear in the `restoring users` line and not in the document count.

### 10.2 Restoring a specific backup

List the available backups:

```bash
sudo ls -lh /var/backups/mongodb/daily /var/backups/mongodb/weekly /var/backups/mongodb/monthly
```

Then use the same command as in step 10.1, replacing the `f=$(...)` part with the path of the file you chose, for example `f=/var/backups/mongodb/weekly/mongo-20260927-023000.archive.gz`.

### 10.3 Exercise: a full restore test

A backup you have never tried to restore is not a reliable backup. Do this test at least once, **while the database is still a test one**.

**1. Insert a test document:**

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.prova.insertOne({ msg: \"ciao\" }); db.prova.countDocuments()"'
```

✅ Reply: `1`

**2. Take a backup:**

```bash
sudo /usr/local/bin/mongo-backup.sh
```

**3. Delete the collection (simulating an accident):**

```bash
sudo docker exec -it -e APP_PWD="$(sudo cat ~/mongodb/appuser_password.txt)" mongo \
  sh -c 'mongosh -u appuser -p "$APP_PWD" --authenticationDatabase appdb appdb --quiet --eval "db.prova.drop(); db.prova.countDocuments()"'
```

✅ Reply: `0` (the data has "vanished").

**4. Restore** with the command from step 10.1. It should say `1 document(s) restored successfully`.

**5. Check that the data is back:** repeat the command from step 3, replacing `db.prova.drop(); db.prova.countDocuments()` with `db.prova.countDocuments()`. Expected reply: `1`.

**6. Clean up:** run the command from step 3 again (the one with `drop`) to delete the test collection.

---

## Part 11 — Connecting from your development PC

```mermaid
flowchart LR
    PC["Development PC"]
    subgraph TUN["SSH tunnel, recommended"]
        A1["localhost:27017 on the PC"] -- "encrypted by SSH, port 22" --> A2["127.0.0.1:27017 on the VM"]
    end
    subgraph DIR["Direct access, development only"]
        B1["Public IP:27017"] -- "NSG: only your IP<br/>in clear text without TLS" --> B2["Private IP:27017 on the VM"]
    end
    PC --> A1
    PC --> B1
```

The way we configured it, MongoDB accepts connections **only from the VM itself**. To connect from your PC there are two ways.

| | SSH tunnel (recommended) | Direct access |
|---|---|---|
| Security | Encrypted traffic | Traffic **in clear text** over the internet |
| Changes to the VM | None | Compose and NSG rule |
| Convenience | You have to open the tunnel before working | You just connect |
| Suitable for | Development, administration | Development with test data only |

### 11.1 SSH tunnel (recommended)

> 🧪 **Not yet tested** on a real installation: during the test run the direct access from Part 11.2 was used. The commands are standard, but please report any differences.

**The idea:** you use the SSH connection, which already works and encrypts everything, as a "pipe" that brings the VM's port 27017 to your PC. Your application believes MongoDB is on your own computer.

> 📍 **Where:** on your PC (not on the VM!). Open a **new** PowerShell terminal.

```powershell
ssh -i C:\percorso\della\chiave.pem -N -L 27017:127.0.0.1:27017 azureuser@<IP_PUBBLICO_VM>
```

**What the options mean:**

- `-N`: don't open a shell, only create the tunnel;
- `-L 27017:127.0.0.1:27017`: "port 27017 on my PC leads to port 27017 of `127.0.0.1` on the VM".

✅ **What you see:** apparently nothing, the terminal just "sits there". **That's normal:** the tunnel is active as long as that window stays open. Leave the window open and work from another one. To close the tunnel: **Ctrl+C**.

While the tunnel is active, your application uses this string:

```
mongodb://appuser:PASSWORD@127.0.0.1:27017/appdb?authSource=appdb&directConnection=true
```

**If you already have MongoDB installed on your PC** (which already uses port 27017), use a different local port: `-L 27018:127.0.0.1:27017`, and write `27018` in the connection string.

**So that you don't have to retype the command every time**, create (or edit) on your PC the file `C:\Users\<tuo-nome>\.ssh\config` with this content:

```
Host mongo-azure
    HostName <IP_PUBBLICO_VM>
    User azureuser
    IdentityFile C:\percorso\della\chiave.pem
    LocalForward 27017 127.0.0.1:27017
    ServerAliveInterval 60
```

From then on the tunnel is opened with:

```powershell
ssh -N mongo-azure
```

`ServerAliveInterval 60` stops the tunnel from closing on its own when it stays idle.

**With MongoDB Compass** (MongoDB's official graphical interface) you don't even need the command: in the new connection open *Advanced Connection Options* → *Proxy/SSH* tab → *SSH with Identity File*, and enter the VM's address, the user `azureuser` and the key file. As the connection string use the one above.

### 11.2 Direct access (development only)

> ⚠️ **Read this first:** with this solution user, password and data travel over the internet **without encryption**. It is fine only for development with test data, and only if the Azure firewall rule is limited to your IP address. To encrypt the traffic follow the guide `01-tls-complete-guide.md`.

**Step 1 — Find the VM's private IP.**

> 📍 On the VM.

```bash
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1
```

✅ You will see a private address, for example `10.0.0.4`. Make a note of it.

**Step 2 — Publish MongoDB on that address too.**

Edit the compose file with the `nano` editor:

```bash
cd ~/mongodb
nano docker-compose.yml
```

In the `ports` section, below the existing line, add the second line with your private IP (here `10.0.0.4` is an example), keeping the same spaces:

```yaml
    ports:
      - "127.0.0.1:27017:27017"
      - "10.0.0.4:27017:27017"
```

Save with **Ctrl+O** then **Enter**, exit with **Ctrl+X**.

> Why the private IP and not `0.0.0.0`? Azure "translates" your public IP to the VM's private one, so that one is enough. `0.0.0.0` would open MongoDB on all network interfaces, including Docker's internal ones.

Apply and check:

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose up -d
sudo ss -ltnp | grep 27017
```

✅ **You should see two lines** listening: one on `127.0.0.1:27017` and one on your private IP. The data is not touched.

> **Where is the address configured?** Not in a MongoDB configuration file (in this setup there is no `mongod.conf`): inside the container MongoDB listens on all interfaces, and it is **Docker**, with the `ports` section of the compose file, that decides on which of the VM's addresses the port can be reached. To check: `grep -A3 'ports:' docker-compose.yml` shows what you have configured, `sudo docker port mongo` shows what is active. If the private IP appears in the file but not in `docker port`, `sudo docker compose up -d` is missing. The IP written in the compose file must match the VM's (`ip -4 addr show eth0`): if it changed, the container would not start.

**Step 3 — Open the port in the Azure firewall (NSG).**

> 📍 In the Azure portal, from the browser.

1. Open your VM → *Networking* menu (or *Network settings*).
2. Click *Create port rule* → *Inbound port rule*.
3. Fill it in like this:

| Field | Value |
|---|---|
| Source | *IP Addresses* |
| Source IP addresses | `<IL_TUO_IP>` (search for "what is my ip" from your PC's browser) |
| Destination port ranges | `27017` |
| Protocol | TCP |
| Action | Allow |
| Name | `mongodb-dev` |

4. Save and wait a few seconds.

> ⚠️ **Never "Any" or "Internet" as the source:** anyone in the world could try to get into your database.

> In Azure there can be two NSGs: one on the VM's network interface and one on the *subnet*. If the connection doesn't work, check that the port is allowed in both (on the *Networking* page you see the rules of both).

**Step 4 — Test from your PC.**

> 📍 On your PC, in PowerShell.

```powershell
Test-NetConnection <IP_PUBBLICO_VM> -Port 27017
```

✅ **You should see:** `TcpTestSucceeded : True`

Connection string for your application:

```
mongodb://appuser:PASSWORD@<IP_PUBBLICO_VM>:27017/appdb?authSource=appdb&directConnection=true
```

> If one day it stops working, almost always the IP address of your internet connection has changed: update the source in the NSG rule.

**To close direct access** (for example before going to production): remove the second line from `ports`, run `sudo docker compose up -d` and delete the `mongodb-dev` rule from the Azure portal.

---

## Part 12 — Managing the space taken up by logs

> 📍 **Where:** on the VM.

MongoDB writes log messages all the time. Without limits, in a few months they could fill the disk, and **with a full disk MongoDB stops**.

### 12.1 The current configuration

In the compose file we already put:

```yaml
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
```

It means: when the log file reaches 50 MB a new one is started, and at most 5 are kept. Maximum total: **250 MB**. It is a limit on **space**, not on time: how many days of logs fit depends on how "chatty" MongoDB is.

**Check that it is active:**

```bash
sudo docker inspect mongo --format '{{json .HostConfig.LogConfig}}'
```

✅ **You should see:** `{"Type":"json-file","Config":{"max-file":"5","max-size":"50m"}}`

**How much space they take up now:**

```bash
sudo sh -c 'du -sh /var/lib/docker/containers/*/*-json.log*'
```

**To change the limits:** edit `max-size` and/or `max-file` in the compose file, then `sudo docker compose up -d`. Note: when the container is recreated, the logs accumulated up to that point are deleted (the database data is not).

### 12.2 Alternative: keeping logs for a number of days

> 🧪 **Not yet tested** on a real installation: during the test run the default configuration from Part 12.1 was used.

If you prefer a limit in days (for example "keep 30 days"), you can send the logs to the system *journal*.

In the compose file replace the `logging` block with:

```yaml
    logging:
      driver: journald
      options:
        tag: mongo
```

Then set the journal limits and apply:

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

Whichever limit is reached first applies, **30 days** or **1 GB**. These limits apply to all the system's logs, not just MongoDB's.

To read the logs for a given period:

```bash
sudo journalctl CONTAINER_NAME=mongo --since "2 days ago"
```

### 12.3 Diagnostic data

Inside the data volume MongoDB also keeps a `diagnostic.data` folder, with technical information that is useful when there are problems. It manages itself, with a default limit of about 250 MB: there is nothing you need to do.

---

## Part 13 — Securing the system

> 📍 **Where:** on the VM.

### 13.1 Automatic security updates

Security fixes for Linux come out every week. We make the VM install them on its own.

```bash
sudo apt-get install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -plow unattended-upgrades
```

A blue screen opens with the question *Automatically download and install stable updates?*: select **Yes** with the arrow keys and press **Enter**.

**Including Docker updates too.** By default only Debian packages are updated. To include Docker:

```bash
sudo tee /etc/apt/apt.conf.d/51unattended-docker > /dev/null << 'EOF'
Unattended-Upgrade::Origins-Pattern {
        "origin=Docker";
};
EOF
```

When Docker is updated, MongoDB stops for a few seconds and starts again on its own. For a development environment that is fine; in production it is better to update Docker by hand, at a time you choose.

**Automatic reboot when needed (optional).** Some updates (those to the *kernel*, the heart of the system) only take effect after a reboot. You can let the VM reboot on its own at 04:00 UTC when necessary:

```bash
sudo tee /etc/apt/apt.conf.d/52unattended-reboot > /dev/null << 'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF
```

If you prefer to decide yourself when to reboot, skip this step and check every now and then:

```bash
ls /var/run/reboot-required
```

If the file **exists**, it is time to reboot (`sudo reboot`). If it replies `No such file or directory`, there is no need.

**Checking the configuration:**

```bash
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -E "Allowed origins|Packages that will be upgraded"
```

✅ **You should see:** a line `Allowed origins are:` that includes `Debian-Security` and, if you added the file for Docker, `origin=Docker`.

> Messages about *battery* and *metered connection* concern laptops: ignore them.

To install pending updates straight away, without waiting for the automatic run:

```bash
sudo unattended-upgrade -v
```

### 13.2 Protecting SSH access

> 🧪 **Not yet tested** on a real installation: creating the SSH key and disabling password login have not been carried out yet. Follow the test from a second terminal with particular care, so that you don't lock yourself out.

The goal is that the VM can be entered **only with the key**, not with a password (passwords can be guessed by automated programs that try millions of combinations).

**Check the current situation:**

```bash
sudo sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin)'
```

✅ **Ideal situation:**

```
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
permitrootlogin no
```

If it already looks like this, **you don't have to do anything**.

**If `passwordauthentication` or `kbdinteractiveauthentication` are `yes`:**

> ⚠️ Before going on, make sure you log in to the VM with a **key** and not with a password. Otherwise, with the following change, you would be locked out.

**How to tell whether you are using a password:** if `ssh` (or `scp`) asks you for `azureuser@...'s password:`, you are using a password. In that case create an SSH key first.

**Creating an SSH key and installing it on the VM** (📍 from your PC, in PowerShell):

```powershell
# 1. Create the key pair: press Enter for the default path; you can set a passphrase
ssh-keygen -t ed25519

# 2. Copy the public key to the VM (it will ask for the password one last time)
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh azureuser@<IP_PUBBLICO_VM> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# 3. Test: it must log in WITHOUT asking for the password
ssh azureuser@<IP_PUBBLICO_VM>
```

The private key (`id_ed25519`, with no extension) stays on the PC in the folder `C:\Users\<tuo-nome>\.ssh\` and must never be shared; only the public part (`.pub`) ends up on the VM. Since it is in the default location, `ssh` and `scp` use it automatically, with no need for `-i`.

Only when step 3 works without a password, go on:

```bash
sudo tee /etc/ssh/sshd_config.d/50-hardening.conf > /dev/null << 'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo systemctl reload ssh
```

`sshd -t` checks that the configuration is correct before applying it.

**Mandatory safety test:** **do not close** the session you are in. Open a **second** terminal on your PC and try to connect to the VM again. If it works, all is well. If it doesn't, from the first session (still open) undo the change:

```bash
sudo rm /etc/ssh/sshd_config.d/50-hardening.conf
sudo systemctl reload ssh
```

**In the Azure portal**, also check the NSG rule for port **22** (SSH): the source should be `<IL_TUO_IP>`, not "Any". VMs with port 22 open to the whole internet receive continuous login attempts.

---

## Part 14 — Everyday use and maintenance

> 📍 **Where:** on the VM, in the `~/mongodb` folder (`cd ~/mongodb`).

### 14.1 Does MongoDB start on its own when the VM reboots?

Yes, thanks to two things: the Docker service is set to start at power-on, and the compose file contains `restart: unless-stopped`.

**Check:**

```bash
systemctl is-enabled docker
sudo docker inspect mongo --format '{{.HostConfig.RestartPolicy.Name}}'
```

✅ Replies: `enabled` and `unless-stopped`.

> **The "unless-stopped" exception:** if you had stopped the container yourself before the reboot (with `docker compose stop`), it stays stopped after the reboot. You start it again with `sudo docker compose start`.

**Practical test** (when nobody is using the database):

```bash
sudo reboot
```

The SSH connection closes. Wait a couple of minutes, reconnect and check:

```bash
sudo docker ps
cat /sys/kernel/mm/transparent_hugepage/enabled
```

✅ The `mongo` container must show as `Up`, and `always` must be in square brackets.

### 14.2 Everyday commands

| I want to... | Command |
|---|---|
| See whether MongoDB is running | `sudo docker compose ps` |
| See the logs in real time (exit with Ctrl+C) | `sudo docker compose logs -f mongo` |
| See only warnings and errors | `sudo docker compose logs mongo \| grep -E '"s":"(W\|E\|F)"'` |
| Stop MongoDB | `sudo docker compose stop` |
| Start MongoDB | `sudo docker compose start` |
| Restart MongoDB | `sudo docker compose restart` |
| Apply changes to `docker-compose.yml` | `sudo docker compose up -d` |
| Open the database shell as admin | `sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin` |
| See on which addresses MongoDB can be reached | `sudo docker port mongo` and `sudo ss -ltnp \| grep 27017` |
| Take a backup right now | `sudo /usr/local/bin/mongo-backup.sh` |
| See the outcome of the nightly backups | `sudo journalctl -u mongo-backup.service -n 20 --no-pager` |
| See the free disk space | `df -h /` |

### 14.3 Updating MongoDB

To install the latest fix for version 8.0 (recommended every now and then):

```bash
cd ~/mongodb
sudo /usr/local/bin/mongo-backup.sh
sudo docker compose pull
sudo docker compose up -d
```

**What it does:** first a safety backup, then it downloads the updated image, then it recreates the container with the new version. The data stays in the volume. MongoDB is down for a few seconds.

**Check the version:**

```bash
sudo docker exec mongo mongod --version | head -1
```

> **Moving to a new major version** (for example from 8.0 to a future 9.0) is a different and more delicate operation: you go one version step at a time, with a backup, reading the official upgrade notes, and an extra step called *featureCompatibilityVersion*. Don't change the number after `mongo:` in the compose file without having read up on it first.

### 14.4 The command you must never use

```bash
sudo docker compose down -v     # ⛔ DO NOT USE on a database with data
```

The `-v` option **deletes the volume**, that is, **all the data** in the database, without asking for confirmation. `sudo docker compose down` without `-v`, on the other hand, is safe (it stops and removes the container, but the data stays).

---

## Part 15 — When something goes wrong

### Connection problems

**I can't connect to the VM with SSH.**

- Check that you replaced `<IP_PUBBLICO_VM>` with the real address, **without** `<` and `>`. The error `Could not resolve hostname` points to exactly this.
- Make sure you run the command **from your PC**, not from the VM (look at the prompt).
- If the command hangs and then gives a *timeout*: port 22 is closed. In the Azure portal check that the VM has a public IP and that the NSG allows port 22 from your IP.
- On Windows, the error `UNPROTECTED PRIVATE KEY FILE` means that the key file's permissions are too broad: from the file's properties (*Security* → *Advanced*) disable inheritance and leave access to your user only.

**From the PC I can't reach MongoDB on port 27017.**

- With the SSH tunnel: the tunnel window must stay open, and the connection string must use `127.0.0.1`, not the VM's IP.
- With direct access: check that `sudo ss -ltnp | grep 27017` shows the private IP, and that the NSG rule exists, has your **current** IP as its source and covers port 27017 over TCP.

### Problems with commands

| Message | What it means | What to do |
|---|---|---|
| `no configuration file provided: not found` | You are not in the folder with `docker-compose.yml` | `cd ~/mongodb` and try again |
| `permission denied while trying to connect to the Docker daemon` | `sudo` is missing | Run the command again with `sudo` in front |
| `No such file or directory` right after creating a file | The `<< 'EOF'` block was not pasted in full | Copy the block again from the first line up to and including `EOF` |
| `cannot access '/var/backups/mongodb/...*...'` | The asterisk is read by your user, which cannot see the folder | Use `sudo sh -c '...'` (see Part 9.6) |
| `-bash: udo: command not found` or similar | Typing mistake | Check the command again (here the `s` of `sudo` was missing) |

### Problems with MongoDB

| Symptom | Likely cause | Solution |
|---|---|---|
| `MongoServerError: Authentication failed` | Wrong password (perhaps an old one) | Read the current one again with `sudo cat ~/mongodb/mongo_root_password.txt` (or `appuser_password.txt`) |
| I changed the password in the `mongo_root_password.txt` file but it doesn't work | The file is read **only on first start**, when the database is empty | Change the password inside MongoDB with `db.changeUserPassword()`, as in Part 8.4 but for `admin` in the `admin` database |
| The container stops immediately on first start, permission error on the password | The password file is not readable by user 999 | `sudo chown 999:999 ~/mongodb/mongo_root_password.txt` and restart |
| `U_STRINGPREP_PROHIBITED_ERROR` when creating a user | Invisible characters pasted into the password | Use the method from Part 8.2 (password read from the file) |
| Warning `Soft rlimits for open file descriptors too low` | The `ulimits` block is missing from the compose file | Add it (Part 6.3) and `sudo docker compose up -d` |
| Warning that mentions `sysfsFile` or the memory allocator | Transparent Huge Pages not configured | Redo Part 5 |
| Warning `Using the XFS filesystem is strongly recommended` | The disk is not formatted as XFS | For development, ignore it; for production see Part 16 |
| MongoDB stops on its own, space errors appear in the logs | Disk full | `df -h /`, check the backups (`sudo du -sh /var/backups/mongodb`) and the logs (Part 12) |

### Starting from scratch (only on a new, empty database!)

If the first configuration went wrong and **there is no important data yet**, the simplest way to start over:

```bash
cd ~/mongodb
sudo docker compose down -v
sudo docker compose up -d
```

⚠️ This deletes **all** the content of the database, users included. Use it only at the beginning, never after loading real data.

### How to ask for help

When you ask a colleague or a chat for help, provide:

1. the exact command you ran;
2. the full error message;
3. if it concerns MongoDB, only the warning/error lines: `sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'`.

And **check that there are no passwords in the text.**

---

## Part 15 bis — The choices: lab and production

This guide was tested on an Azure VM with Debian 13, 2 vCPUs and 7.8 GB of RAM, used as a **development environment**. Every choice below is justified by that context; the last column shows what to choose in production.

| Choice | In the lab (tested) | Why | In production |
|---|---|---|---|
| Installation | Official Docker image `mongo:8.0` | No official server package for Debian 13 | Docker or packages on a supported system, version pinned and updated in a controlled way |
| Topology | A single instance | Development environment | Three-node replica set (guide 02) |
| Port | Published on `127.0.0.1` | Docker bypasses the Linux firewall | Same, plus a private network |
| Access | SSH tunnel, or direct access with the NSG limited to your own IP | A single developer | Private network only, TLS mandatory (guide 01) |
| Disk | ext4 system disk (XFS warning) | Simplicity | Dedicated XFS data disk |
| Memory | Default cache, no swap | VM dedicated to the instance | RAM sized on the *working set*, small and monitored swap |
| Shutdown | `stop_grace_period: 1m` | Avoids forced kills after 10 s | Same |
| Backup | Local, nightly, 7/4/12 | Protection against mistakes and deletions | A copy outside the VM too, restore tested periodically |
| Passwords | `600` files on the VM | Simplicity | Key Vault or a secrets manager |
| Updates | Automatic, Docker included | No critical service | Docker and MongoDB in maintenance windows |

---

## Part 16 — Before going to production

The configuration in this guide is suitable for development. Before putting real data in it, check these points:

- [ ] **Close direct access on port 27017** (remove the private IP from the compose file and delete the NSG rule), or configure **TLS** encryption on MongoDB (guide `01-tls-complete-guide.md`).
- [ ] **Connect applications through an Azure private network** (same virtual network, peering or VPN), not over the internet.
- [ ] **Dedicated data disk formatted as XFS** (Premium SSD) for the MongoDB data: it is the official recommendation for performance, and it keeps the data separate from the system disk.
- [ ] **Backups outside the VM:** enable *Azure Backup* on the VM or copy the backups to an *Azure Storage Account*. Today the backups are on the same disk as the database: if the VM is lost, both are lost.
- [ ] **Automatic alerts** with *Azure Monitor*: disk space running out and failed backups.
- [ ] **Passwords stored** in *Azure Key Vault* or in a company password manager.
- [ ] **High availability:** consider a three-node *replica set*, if the application cannot afford downtime.
- [ ] **Manual Docker updates**, in scheduled maintenance windows (remove the `51unattended-docker` file).
- [ ] **Restore test** carried out periodically, for example once a month.

---

## Appendix A — Where everything is

| What | Where |
|---|---|
| Working folder | `~/mongodb` (that is, `/home/azureuser/mongodb`) |
| Container configuration | `~/mongodb/docker-compose.yml` |
| `admin` password | `~/mongodb/mongo_root_password.txt` |
| `appuser` password | `~/mongodb/appuser_password.txt` |
| Database data | Docker volume `mongodb_mongo-data` (managed by Docker) |
| Backup script | `/usr/local/bin/mongo-backup.sh` |
| Backups | `/var/backups/mongodb/daily`, `weekly`, `monthly` |
| Backup schedule | `/etc/systemd/system/mongo-backup.timer` and `.service` |
| Memory settings (THP) | `/etc/tmpfiles.d/mongodb-thp.conf` |
| Automatic updates | `/etc/apt/apt.conf.d/51unattended-docker`, `52unattended-reboot` |
| Additional SSH configuration | `/etc/ssh/sshd_config.d/50-hardening.conf` |
| Container logs | `/var/lib/docker/containers/<id>/` (read them with `docker compose logs`) |

---

## Appendix B — Command cheat sheet

```bash
# Go into the working folder (always, before docker compose commands)
cd ~/mongodb

# Status, start, stop
sudo docker compose ps
sudo docker compose start
sudo docker compose stop
sudo docker compose restart

# Logs
sudo docker compose logs -f mongo
sudo docker compose logs mongo | grep -E '"s":"(W|E|F)"'

# Database shell
sudo docker exec -it mongo mongosh -u admin -p --authenticationDatabase admin

# Read the passwords
sudo cat ~/mongodb/mongo_root_password.txt
sudo cat ~/mongodb/appuser_password.txt

# Backup
sudo /usr/local/bin/mongo-backup.sh
sudo journalctl -u mongo-backup.service -n 20 --no-pager
systemctl list-timers mongo-backup.timer
sudo du -sh /var/backups/mongodb

# Update MongoDB (8.0 patch)
sudo /usr/local/bin/mongo-backup.sh && sudo docker compose pull && sudo docker compose up -d

# Disk space
df -h /

# Is a reboot needed?
ls /var/run/reboot-required
```

**From your PC:**

```powershell
# Connect to the VM
ssh -i C:\percorso\della\chiave.pem azureuser@<IP_PUBBLICO_VM>

# Open the tunnel to MongoDB (with the ~/.ssh/config file set up)
ssh -N mongo-azure

# Check that the port is reachable (direct access)
Test-NetConnection <IP_PUBBLICO_VM> -Port 27017
```

---

## The 7 golden rules

1. **Always look at the prompt** before running a command: are you on your PC or on the VM?
2. **Never paste passwords** into chats, emails or tickets. If it happens, change it straight away.
3. **Never `docker compose down -v`** on a database with data: it deletes everything.
4. **Never publish MongoDB on `0.0.0.0`** and never use NSG rules with "Any" as the source.
5. **Paste `<< 'EOF'` blocks in full**, up to the `EOF` line.
6. **Before every important change, take a backup:** `sudo /usr/local/bin/mongo-backup.sh`.
7. **An untested backup is not a backup:** run the restore test (Part 10.3).
