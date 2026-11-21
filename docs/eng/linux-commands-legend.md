# Command legend

This legend explains **all the commands and symbols** used in the project guides: what they do, what the options we use mean, and an example taken from the guides. You don't need to read it all: keep it open next to the guide and look things up when you meet something you don't know.

The **Guides** column shows where the command appears: `00` installation, `01` TLS, `02` replica set, `03` sharding. All the commands listed were used during the test run of the guides.

---

## Contents

1. [How to read a command](#1-how-to-read-a-command)
2. [Shell symbols](#2-shell-symbols)
3. [Variables, functions and small scripts](#3-variables-functions-and-small-scripts)
4. [Administrator privileges](#4-administrator-privileges)
5. [Files and folders](#5-files-and-folders)
6. [Permissions and owners](#6-permissions-and-owners)
7. [Working with text](#7-working-with-text)
8. [System, network and resources](#8-system-network-and-resources)
9. [Packages and updates](#9-packages-and-updates)
10. [Services, timers and logs (systemd)](#10-services-timers-and-logs-systemd)
11. [SSH and copying files](#11-ssh-and-copying-files)
12. [Certificates and cryptography (openssl)](#12-certificates-and-cryptography-openssl)
13. [Docker and Docker Compose](#13-docker-and-docker-compose)
14. [MongoDB tools](#14-mongodb-tools)
15. [PowerShell on the Windows PC](#15-powershell-on-the-windows-pc)
15. bis [Parts of the guides that are not commands](#15-bis-parts-of-the-guides-that-are-not-commands)
16. [Dangerous commands](#16-dangerous-commands)

---

## 1. How to read a command

A command is made of three parts: the **name**, the **options** and the **arguments**.

```
ls   -lh   /var/backups/mongodb
│    │     └── argument: what to act on
│    └── options: how to behave
└── command name
```

- **Short options**: one dash and one letter (`-l`, `-h`). They can be joined: `-lh` is the same as `-l -h`.
- **Long options**: two dashes and a word (`--quiet`, `--no-pager`). Some need a value: `--port 27101` or `--port=27101`.
- **Upper and lower case matter**: `-d` and `-D` are different options, `File.txt` and `file.txt` are different files.
- **Paths**: `/home/user/mongodb` is an **absolute** path (it starts from the root `/`); `tls/ca.pem` is **relative** to the folder you are in.

| Symbol in paths | Meaning |
|---|---|
| `~` | Your home folder (e.g. `/home/azureuser`) |
| `.` | The current folder |
| `..` | The parent folder |
| `/` | The root of the system, or the separator between folders |

**To learn more about a command:** `man name` (full manual, quit with `q`) or `name --help`.

---

## 2. Shell symbols

The **shell** (bash) is the program that interprets what you type in the terminal. Some symbols are not commands, but instructions for the shell.

### 2.1 Connecting commands

| Symbol | Meaning | Example from the guides |
|---|---|---|
| `\|` (pipe) | Passes the output of the command on the left as input to the one on the right | `sudo docker compose logs mongo \| grep "Waiting"` |
| `&&` | Runs the second command **only if the first one succeeded** | `sudo docker compose config --quiet && echo "compose valido"` |
| `\|\|` | Runs the second command **only if the first one failed** | `... -checkend ... && echo OK \|\| echo "IN SCADENZA"` |
| `;` | Runs the commands one after the other, whatever happens | `sleep 15; rs_eval '...'` |
| `\` at the end of a line | The command continues on the next line | Long commands `docker exec ... \` |
| `&` at the end of a command | Runs the command **in the background** | To be avoided by mistake: a `mongodb://...&...` string pasted into bash is sent to the background |
| `{ ...; }` | Groups several commands, for example to join their output | `{ sudo cat password.txt; sudo cat backup.gz; } \| ...` |

### 2.2 Redirections: where the output goes

| Symbol | Meaning | Example |
|---|---|---|
| `>` | Writes the output to a file, **overwriting it** | `openssl rand -base64 756 > keyfile` |
| `>>` | Adds the output **at the end** of the file | `cat >> docker-compose.yml << EOF` |
| `< file` | Uses the file as the command's input | `openssl s_client ... </dev/null` |
| `2>/dev/null` | Throws away error messages (`/dev/null` is a "bin" that deletes everything) | `docker inspect ... 2>/dev/null` |
| `2>&1` | Merges error messages into the normal output | `unattended-upgrade --dry-run --debug 2>&1 \| grep ...` |
| `>&2` | Writes to the error channel | `echo "ERRORE: ..." >&2` |
| `> /dev/null` | Throws away the normal output | `sudo tee file > /dev/null` |

### 2.3 Here document: writing a file from the terminal

```bash
cat > filename << 'EOF'
file content
EOF
```

Everything between the first line and the `EOF` line becomes the command's input. This is how the guides create configuration files. While you paste, the terminal shows `>` at the start of each line: that is normal.

| Form | Difference |
|---|---|
| `<< 'EOF'` (with quotes) | The content is written **exactly as it is**: `$HOME` stays as the text `$HOME` |
| `<< EOF` (without quotes) | Variables are **replaced** with their value: `$FQDN` becomes the real name |

**Typical mistakes:** pasting only part of the block (the file is not created or is left incomplete); very long blocks getting corrupted during the paste (the guides split them into two parts, with `>` and then `>>`).

### 2.4 Quotes and special characters

| Symbol | Meaning |
|---|---|
| `'text'` | Single quotes: everything is taken **literally**, no substitution |
| `"text"` | Double quotes: variables (`$VAR`) and commands (`$(...)`) are substituted |
| `$(command)` | Is replaced by the command's output: `"$(sudo cat root_password.txt)"` |
| `*` | Wildcard: "anything" (`mongo-*.archive.gz`). It is expanded by the shell **before** the command runs, with your user's permissions: this is why folders reserved for root need `sudo sh -c '...'` |
| `#` | Comment: the shell ignores the rest of the line |
| `{a,b}` | Expands into several words: `mongo-rs-backup.{service,timer}` = the two files |

### 2.5 Useful keys

| Key | Effect |
|---|---|
| **Ctrl+C** | Interrupts the running command |
| **Ctrl+D** | Exits a shell (including `mongosh`) |
| **Up/down arrow** | Scrolls through previous commands |
| **Tab** | Completes names of commands, files and folders |
| **Ctrl+Shift+V** | Paste (in Linux terminals); in PowerShell right-click or Ctrl+V |

---

## 3. Variables, functions and small scripts

| Element | Meaning | Example |
|---|---|---|
| `NAME=value` | Creates a variable (no spaces around `=`). It lives **only in the current session** | `FQDN=nome.regione.cloudapp.azure.com` |
| `$NAME` | Uses the variable's value | `echo "Nome DNS: $FQDN"` |
| `${2:-1}` | The second argument, or `1` if it is missing | In the `rs_eval` function |
| `$(( ... ))` | Arithmetic calculation | `$((KEEP_WEEKLY * 7 - 1))` |
| `$?` | Result of the last command (`0` = succeeded) | `status=$?` in the backup scripts |
| `name() { ...; }` | Defines a **function**, a custom command. It lives only in the session | `rs_eval() { ... }` |
| `local` | Variable valid only inside the function | `local node=${2:-1}` |
| `for x in a b c; do ...; done` | Repeats the commands for each value | `for n in 1 2 3; do rs_eval '...' $n; done` |
| `if ...; then ...; fi` | Runs the commands only if the condition is true | Choosing the running node in the backup script |
| `[ condition ]` | Checks a condition (file exists, texts are equal…) | `[ -f /etc/mongo/tls/ca.pem ]` = "the file exists" |
| `case ... in ... esac` | Chooses based on a value | Placeholder check in the backup script |
| `break` | Leaves a loop | In the backup script |
| `read -r VAR` | Reads a line from the input and puts it in a variable | Reading the password from standard input |
| `exit N` | Ends the script with result `N` | `exit $status` |
| `sh -c '...'` | Runs a line of commands in a new shell | `sudo sh -c 'rm -f /var/backups/.../*.gz'`, and inside the containers |
| `source file` | Runs a file **in the current session**: the functions and variables it defines stay available | `source funzioni-lab.sh` (03) |
| `~/.bashrc` | File that bash runs when every session opens: a `source ...` line added here loads the functions at every login | `echo 'source ...' >> ~/.bashrc` (03) |
| `trap 'commands' EXIT` | Runs the commands when the script ends, **even because of an error** | Re-enabling the balancer in the backup script (03) |
| `set -- a b` | Assigns the values to the parameters `$1`, `$2`… | `set -- $c` in the loops over the nodes (03) |
| `export VAR` | Makes the variable visible to programs started afterwards (here: `mongosh` reads the password from `process.env`) | Backup script (03) |

**The first lines of the scripts:**

| Line | Meaning |
|---|---|
| `#!/bin/bash` | Tells the system to run the file with bash |
| `set -euo pipefail` | Stops the script **at the first error** (`-e`), if a variable that does not exist is used (`-u`) or if a command in a pipe fails (`pipefail`). In the backup scripts it prevents the cleanup from deleting the old backups if the new one did not succeed |
| `umask 077` | Files created from that moment on are readable **only by the owner** |

---

## 4. Administrator privileges

| Command | What it does | Example | Guides |
|---|---|---|---|
| `sudo command` | Runs the command as administrator (root). It may ask for your user's password | `sudo docker compose up -d` | 00 01 02 |
| `sudo tee file` | Writes to a file reserved for root. It is needed because with `sudo echo ... > file` the `>` redirection would be performed by your user, not by root | `... \| sudo tee mongo_root_password.txt > /dev/null` | 00 01 02 |
| `sudo tee -a file` | As above, but **appends** at the end | Second part of the backup script (02) | 02 |
| `sudo sh -c '...'` | Runs a whole line as root, including the `*` wildcards | `sudo sh -c 'chmod 600 /var/backups/mongodb/*.archive.gz'` | 00 01 02 |
| `sudo usermod -aG docker $USER` | Adds your user to the `docker` group (not recommended: it is the same as full powers) | Mentioned in guide 00 | 00 |

---

## 5. Files and folders

| Command | What it does | Options used | Example | Guides |
|---|---|---|---|---|
| `pwd` | Shows the current folder | | Check before `down -v` | 02 |
| `cd` | Changes folder | `cd ~` goes back to the home folder | `cd ~/mongo-lab/02-replica-set` | 00 01 02 |
| `ls` | Lists files and folders | `-l` details (permissions, owner, size); `-a` hidden files too; `-h` readable sizes (K, M); `-d` the folder itself instead of its content; `-t` sorts by date; `-R` subfolders too | `ls -la ~/mongodb/tls` | 00 01 02 |
| `mkdir` | Creates a folder | `-p` also creates the intermediate folders and gives no error if it already exists | `mkdir -p ~/mongodb/tls` | 00 01 02 |
| `rmdir` | Deletes a folder **only if it is empty** | | Removing the folder created by mistake | 01 |
| `cp` | Copies a file | | `cp docker-compose.yml docker-compose.yml.pre-tls` | 01 02 |
| `mv` | Moves or renames | | `mv "$FILE.tmp" "$FILE"` | 00 01 02 |
| `rm` | Deletes files | `-f` without asking for confirmation and without an error if it does not exist | `rm -f /tmp/rs-backup.archive.gz` | 00 01 02 |
| `ln` | Creates a link | With no options: *hard link* (the same file visible from two locations, no extra space); `-f` replaces it if it exists | `ln -f "$FILE" "$DEST/weekly/"` | 00 01 02 |
| `cat` | Shows the content of a file (or passes it to another command) | | `sudo cat root_password.txt` | 00 01 02 |
| `tee` | Writes to a file what it receives from the pipe (and also shows it on screen); `-a` appends at the end instead of overwriting. With `sudo` it writes to files reserved for root; `> /dev/null` avoids showing the content | | `... \| sudo tee /etc/tmpfiles.d/mongodb-thp.conf > /dev/null` | 00 01 02 03 |
| `head` | Shows the first lines | `-N` the first N lines | `sudo head -3 /usr/local/bin/mongo-backup.sh` | 00 01 02 |
| `wc -l` | Counts the lines | | `docker compose config --services \| wc -l` | 03 |
| `tail` | Shows the last lines | `-N` the last N lines | `... \| tail -1` | 02 |
| `nano` | Text editor in the terminal | **Ctrl+O** saves, **Ctrl+X** exits | `nano docker-compose.yml` | 00 |
| `du` | Space used | `-s` total; `-h` readable | `sudo du -sh /var/backups/mongodb` | 00 01 02 |
| `df` | Free space on the disks | `-h` readable | `df -h /` | 00 02 |
| `find` | Searches for files | `-name` by name; `-mtime +N` modified more than N days ago; `-delete` deletes them | Cleanup of old backups | 00 01 02 |
| `install -m 0755 -d` | Creates a folder with exact permissions | | `sudo install -m 0755 -d /etc/apt/keyrings` | 00 |
| `shred -u` | Overwrites a file and then deletes it, so it cannot be recovered | | `shred -u ~/mongodb/tls/ca.key` | 01 |
| `sha256sum` | Computes the fingerprint of a file, to check that two copies are identical | | `sha256sum ~/mongodb/tls/ca.key` | 01 |

---

## 6. Permissions and owners

Every file has an **owner**, a **group** and some **permissions**. In `ls -l` they appear like this:

```
-rw-------  1  999  systemd-journal  3274  server.pem
│└┬┘└┬┘└┬┘     │    │
│ │  │  │      │    └── group
│ │  │  │      └── owner (here the number 999: the MongoDB user in the containers)
│ │  │  └── permissions of other users
│ │  └── permissions of the group
│ └── permissions of the owner
└── type: - file, d folder
```

`r` = read, `w` = write, `x` = execute (for a folder: being able to enter it).

**Permissions as numbers**, the way the guides use them: each digit is the sum of `r=4`, `w=2`, `x=1`, in the order owner / group / others.

| Number | Letters | Used for |
|---|---|---|
| `400` | `r--------` | Replica set keyFile (read only, owner only: mandatory for MongoDB) |
| `600` | `rw-------` | Passwords, private keys, `server.pem`, backups |
| `644` | `rw-r--r--` | Public certificates (`ca.pem`, `server.crt`) |
| `700` | `rwx------` | Reserved folders (`tls`, backups) and scripts that only root can run |
| `755` | `rwxr-xr-x` | Folders and programs accessible to everyone |

| Command | What it does | Example | Guides |
|---|---|---|---|
| `chmod` | Changes the permissions | `chmod 600 ca.key`; `chmod a+r file` (read for everyone); `chmod +x script.sh` (executable) | 00 01 02 |
| `chown` | Changes owner and group | `sudo chown 999:999 server.pem` | 00 01 02 |
| `umask` | Default permissions of new files | `umask 077` → owner only | 00 01 02 |

> **Why 999?** It is the number of the `mongodb` user inside the containers of the official image. On the VM that number happens to match the `systemd-journal` group: this is why it appears next to the files, and it is harmless.

---

## 7. Working with text

| Command | What it does | Options used | Example | Guides |
|---|---|---|---|---|
| `echo` | Prints a text | | `echo "Nome DNS: $FQDN"` | 00 01 02 |
| `printf` | Prints a text with a format (`%s` = "insert a value here") | | `printf "password: %s\n" "$PWD"` | 00 01 02 |
| `grep` | Searches for lines that contain a text | `-n` line number; `-c` counts the lines; `-A N` also shows the N lines after; `-E` extended expressions (`A\|B` = A or B); `-i` ignores case; `-o` shows only the matching part; `-q` quiet (only the result matters) | `grep -c "requireTLS" docker-compose.yml` | 00 01 02 |
| `sed -i` | Edits a file by replacing text | `s\|old\|new\|` replaces; `&` in the new text = the text found; `\n` = new line; `-i` edits the file directly | Adding `stop_grace_period`, the TLS options | 00 02 |
| `tr -d` | Deletes characters | | `tr -d '/+='` removes the troublesome characters from the password | 00 02 |
| `cut` | Extracts a part of each line | `-d/` separator `/`; `-f1` first field | `cut -d/ -f1` | 00 01 02 |
| `awk` | Extracts columns | `'{print $4}'` = fourth column | `ip -4 -o addr show eth0 \| awk '{print $4}'` | 00 01 02 |
| `history` | Command history | `-d N` deletes line N | Removing a string with a password | 02 |

---

## 8. System, network and resources

| Command | What it does | Example | Guides |
|---|---|---|---|
| `free -h` | RAM and swap memory | Check before the lab | 02 |
| `nproc` | Number of CPUs | | 02 |
| `date` | Date and time; with `+format` in an exact format | `date +%Y%m%d-%H%M%S` (name of the backups); `date +%u` (day of the week, 7 = Sunday); `date +%d` (day of the month) | 00 01 02 |
| `sleep N` | Waits N seconds | `sleep 15` | 02 |
| `reboot` | Restarts the machine | `sudo reboot` | 00 |
| `exit` | Leaves the session (or `mongosh`) | | 00 01 02 |
| `ip -4 -o addr show eth0` | IPv4 address of the network card | Finding the private IP | 00 01 02 |
| `ss -ltnp` | Listening ports (`-l` listening, `-t` TCP, `-n` numbers, `-p` program) | `sudo ss -ltnp \| grep 27017` | 00 02 |
| `curl` | Downloads a web address | `-f` error if it fails; `-s` silent; `-S` shows errors; `-L` follows redirects; `-o` saves to a file | 00 01 |
| `grep -o avx /proc/cpuinfo` | Checks the CPU's AVX support | | 00 |
| `fallocate -l 4G /swapfile` | Creates a file of the given size, reserving the space | Creating the swap | 03 |
| `mkswap file` | Prepares a file (or a partition) as a swap area | | 03 |
| `swapon file` / `swapon --show` | Turns swap on / shows the active one. `sudo` is needed even just to look at it: it lives in `/usr/sbin`, outside the path of normal users (otherwise `command not found`) | `sudo swapon --show` | 03 |
| `swapoff file` | Turns swap off | Removing the swap | 03 |
| `cat /sys/kernel/mm/transparent_hugepage/enabled` | Active THP setting (the one between `[ ]`) | | 00 |

---

## 9. Packages and updates

| Command | What it does | Guides |
|---|---|---|
| `apt-get update` | Updates the list of available programs (installs nothing) | 00 |
| `apt-get install -y package` | Installs (`-y` = answers yes to the questions) | 00 |
| `apt-get remove -y package` | Removes | 00 |
| `dpkg --print-architecture` | Architecture of the machine (`amd64`, `arm64`) | 00 |
| `dpkg-reconfigure -plow unattended-upgrades` | Guided configuration of automatic updates | 00 |
| `unattended-upgrade -v` / `--dry-run --debug` | Installs the security updates now / simulates without installing | 00 |

---

## 10. Services, timers and logs (systemd)

**systemd** is the system that starts and manages Debian's services. A **service** (`.service`) says *what* to run; a **timer** (`.timer`) says *when*.

| Command | What it does | Guides |
|---|---|---|
| `systemctl enable --now X` | Enables X at boot **and** starts it right away | 00 01 02 |
| `systemctl start X` | Starts X now (for a backup service: runs a backup) | 00 01 02 |
| `systemctl disable --now X` | Disables X and stops it | 02 |
| `systemctl daemon-reload` | Re-reads the service files after creating or editing them | 00 01 02 |
| `systemctl reload ssh` | Re-reads the SSH configuration without interrupting sessions | 00 |
| `systemctl is-enabled docker` | Tells whether a service starts at boot | 00 |
| `systemctl list-timers 'mongo*'` | Lists the timers with their next and last run | 00 02 |
| `journalctl -u X -n 5 --no-pager` | Last 5 log lines of service X, without paging | 00 01 02 |
| `journalctl ... --since "2026-09-29 02:00"` | Logs starting from an exact moment | 02 |
| `systemd-tmpfiles --create file` | Applies right away the settings of a file in `/etc/tmpfiles.d` (used for THP) | 00 |

---

## 11. SSH and copying files

| Command | What it does | Options used | Guides |
|---|---|---|---|
| `ssh user@address` | Opens a terminal on the VM | `-i key` key file; `-v` shows the details (troubleshooting) | 00 |
| `ssh -N -L 27017:127.0.0.1:27017 ...` | Tunnel: brings port 27017 of the VM to the PC | `-N` no shell, tunnel only; `-L local:destination:port` | 00 |
| `scp source destination` | Copies files over SSH; `user@address:path` refers to a file on the VM | `-i key` as for `ssh` | 01 |
| `ssh-keygen -t ed25519` | Creates an SSH key pair (private + public `.pub`) | | 00 |
| `sshd -T` | Shows the effective configuration of the SSH server | | 00 |
| `sshd -t` | Checks that the SSH configuration is valid | | 00 |

**SSH configuration directives** used in guide 00 (files in `/etc/ssh/sshd_config.d/`):

| Directive | Meaning |
|---|---|
| `PubkeyAuthentication yes` | Login with a key allowed |
| `PasswordAuthentication no` | Login with a password forbidden |
| `KbdInteractiveAuthentication no` | Passwords typed interactively are forbidden too |
| `PermitRootLogin no` | Direct login as `root` forbidden |

---

## 12. Certificates and cryptography (openssl)

| Command | What it does | Guides |
|---|---|---|
| `openssl rand -base64 N` | Generates N random bytes as text (passwords, keyFile) | 00 01 02 |
| `openssl genrsa -out file.key 2048` | Creates an RSA private key (2048 or 4096 bits) | 01 02 |
| `openssl req -x509 -new ...` | Creates a self-signed certificate (here: the CA's) | 01 |
| `openssl req -new -key ... -subj "/CN=name" -out file.csr` | Prepares a certificate request | 01 02 |
| `openssl x509 -req -in file.csr -CA ... -CAkey ...` | The CA signs the request and produces the certificate; `-CAcreateserial` creates the counter, `-CAserial` reuses it; `-days` validity; `-extfile` settings (SAN, usages) | 01 02 |
| `openssl verify -CAfile ca.pem server.crt` | Checks that the certificate is signed by that CA | 01 02 |
| `openssl x509 -in file.crt -noout -subject -enddate` | Shows name and expiry date | 01 |
| `openssl x509 ... -ext subjectAltName,extendedKeyUsage` | Shows valid names (SAN) and allowed usages | 01 02 |
| `openssl x509 ... -checkend SECONDS` | Succeeds if the certificate is still valid N seconds from now | 01 |
| `openssl s_client -connect host:port -CAfile ca.pem` | Connects as a TLS client and shows the server's certificate; `Verify return code: 0 (ok)` = everything is fine | 01 02 |

---

## 13. Docker and Docker Compose

**Image** = the downloaded template (`mongo:8.0`); **container** = the running image; **volume** = where the data outlives the container; **Compose** = the `docker-compose.yml` file that describes the containers.

> ⚠️ `docker compose` commands act on the project **of the current folder**.

### 13.1 Docker Compose

| Command | What it does | Guides |
|---|---|---|
| `docker compose up -d` | Creates and starts the containers in the background; if the compose file has changed, it **recreates** the affected ones (the volumes stay) | 00 01 02 |
| `docker compose up -d service` | Recreates only that service: the basis of rolling maintenance | 02 |
| `docker compose ps` | Status of the project's containers | 00 01 02 |
| `docker compose logs -f service` | Live logs (quit with Ctrl+C); `--tail N` only the last N lines | 00 01 02 |
| `docker compose stop` / `start` / `restart` [service] | Stops / starts / restarts | 00 02 |
| `docker compose config --quiet` | Checks the syntax of the compose file (no output = valid) | 00 01 02 |
| `docker compose config --services` / `--volumes` | Lists services and volumes: checks that the file is complete | 02 |
| `docker compose pull` | Downloads the updated version of the images | 00 |
| `docker compose down` | Stops and removes the containers (the data stays) | 00 02 |
| `docker compose down -v` | ⚠️ As above **and deletes the volumes, that is, the data** | 00 02 |

### 13.2 Docker

| Command | What it does | Guides |
|---|---|---|
| `docker run --rm hello-world` | Runs a test container and deletes it at the end (`--rm`) | 00 |
| `docker exec -it container command` | Runs a command inside a running container; `-i` input, `-t` interactive terminal | 00 01 02 |
| `docker exec -i -e VAR=value ...` | As above, passing an environment variable (`-e`); without `-t` so it can receive data from a pipe | 00 01 02 |
| `docker inspect container --format '{{...}}'` | Reads a property of the container (logs, restart, status) | 00 02 |
| `docker port container` | Published ports | 00 |
| `docker ps` | Running containers | 00 |
| `docker stats --no-stream` | CPU and memory usage (a single reading) | 02 |

---

## 14. MongoDB tools

These are not Linux commands, but they appear in almost every block. They are run inside the containers with `docker exec`.

| Command | What it does | Options used |
|---|---|---|
| `mongosh` | MongoDB shell | `-u` user; `-p` password (with no value: it asks for it); `--authenticationDatabase` where the user is defined; `--port`; `--tls --tlsCAFile` encrypted connection; `--eval 'js'` runs a command and exits; `--quiet` fewer messages; or a `"mongodb://..."` string |
| `mongodump` | Backup | `--archive` a single file; `--gzip` compressed; `--oplog` consistent copy (replica set, not through the router); `--config` file with the password; `--ssl --sslCAFile` TLS; `--db` a single database; `--dumpDbUsersAndRoles` the database's users too |
| `mongorestore` | Restore | `--drop` replaces the collections; `--oplogReplay` reapplies the oplog; `--nsFrom`/`--nsTo` restores under another name; `--restoreDbUsersAndRoles` restores the users; same options as `mongodump` |
| `mongod --version` | Server version | |
| `mongos --configdb rs/host:port,...` | Router of a sharded cluster (03) | `--port`, `--keyFile`, TLS options like `mongod` |

Inside `mongosh`, the commands used in the guides:

| Command | Meaning |
|---|---|
| `db.runCommand({ ping: 1 })` | Checks that the server responds |
| `db.getSiblingDB("name")` | Switches to another database |
| `db.createUser(...)` / `db.changeUserPassword(...)` | Creates a user / changes the password |
| `db.collection.insertOne(...)` / `find()` / `countDocuments()` / `drop()` | Inserts / reads / counts / drops the collection |
| `rs.initiate(...)` / `rs.status()` / `rs.stepDown(N)` | Creates the replica set / status of the members / the primary gives up its role for N seconds |
| `db.hello()` | Information about the node's role (primary, members) |
| `db.adminCommand({ getParameter / setParameter ... })` | Reads / changes a server parameter (e.g. `tlsMode`) |
| `db.serverStatus().transportSecurity` | Encrypted connections received, by TLS version |
| `sh.addShard("rs/host:port,...")` | Registers a shard in the cluster (03) |
| `sh.status()` / `db.adminCommand({ listShards: 1 })` | Status of the cluster / list of the shards (on the router only) |
| `sh.enableSharding("db")` / `sh.shardCollection("db.coll", { field: "hashed" or 1 })` | Enables a database / distributes a collection with the given shard key |
| `db.coll.getShardDistribution()` | Data and documents per shard (includes orphans) |
| `.explain()` → `queryPlanner.winningPlan.stage` | `SINGLE_SHARD` (targeted query) or `SHARD_MERGE` (all the shards) |
| `sh.stopBalancer()` / `sh.startBalancer()` / `sh.getBalancerState()` / `sh.isBalancerRunning()` | Stops / re-enables / state of the balancer |
| `config.chunks`, `config.changelog`, `config.rangeDeletions`, `config.settings` | Ranges, migration history, pending orphan deletions, settings (`chunksize`) |
| `db.getMongo().setReadPref("secondary")` | Reads from the secondaries |
| `exit` | Exits `mongosh` |

---

## 15. PowerShell on the Windows PC

| Command | What it does | Guides |
|---|---|---|
| `ssh`, `scp`, `ssh-keygen` | Same as on Linux: they are included in Windows 10/11 | 00 01 |
| `mkdir folder -Force` | Creates a folder (`-Force`: no error if it exists) | 01 |
| `dir folder` | Lists the content | 01 |
| `Move-Item source destination` | Moves a file | 01 |
| `type file` | Shows a file (here: the public key to send to the VM) | 00 |
| `$env:USERPROFILE` | Your user folder (`C:\Users\<nome>`) | 00 |
| `Get-FileHash file -Algorithm SHA256` | Fingerprint of a file (to compare with `sha256sum`) | 01 |
| `Test-NetConnection host -Port N` | Checks that a port is reachable (`TcpTestSucceeded : True`) | 00 02 |
| `Resolve-DnsName name` | Resolves a DNS name | 02 |
| `27101..27103 \| ForEach-Object { ... $_ ... }` | Repeats a command for each number (`$_` = the current value; short form `%`) | 02 |
| `Select-Object columns` | Shows only some columns of the result | 02 |
| `ping -n 1 name` | Shows which address a name resolves to | — |
| `git status` / `git mv` / `git add --renormalize .` | Repository status / move keeping history / reapplies the `.gitattributes` rules | — |

> **Windows paths:** they use `\`. In MongoDB connection strings they are written with `/` (`C:/Users/...`), and spaces must be encoded as `%20` or avoided.

---

## 15 bis. Parts of the guides that are not commands

| Element | Meaning |
|---|---|
| ` ```mermaid ` blocks | Diagrams drawn by GitHub (in other viewers they appear as text) |
| `<details>` / `<summary>` | Collapsible sections, used for the real output of the test run |
| `<FQDN>`, `<IP_PRIVATO_VM>`, … | Placeholders to replace, removing `<` and `>` as well |

---

## 16. Dangerous commands

Commands that appear in the guides with a warning, and why.

| Command | Risk | Precaution |
|---|---|---|
| `docker compose down -v` | Deletes **all the data** of the project, without confirmation | `pwd` first; never in the folder of a database with real data |
| `rm -f` with `*` | Deletes everything that matches | First `ls` with the same path |
| `shred -u` | Unrecoverable deletion | Only after checking the copy (`sha256sum`) |
| `sed -i` | Edits the file without asking | Backup copy first (`cp file file.bak`) |
| SSH configuration | You can get locked out of the VM | Keep one session open and test from a second one |
| `rs.stepDown` / `docker compose stop` on the primary | Election: short pause in writes | One node at a time, checking the status |
| `mongodb://user:password@...` strings in the terminal | Password in the history; the `&` sends the command to the background | They belong in the client; `history -d` to remove them |
