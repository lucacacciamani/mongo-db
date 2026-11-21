# MongoDB replica set in Docker — Complete step-by-step guide

**Who this guide is for:** anyone who has followed guides 00 and 01 and wants to learn how to build, use, secure and maintain a MongoDB **replica set**. As in the previous guides, every step explains **what to do**, **what the command does** and **what you should see**. In addition, every technical choice comes with a 🧭 box that explains the reason behind it and how it translates to production.

**What you will have at the end:**

- a three-node replica set, with automatic election of the primary and failover;
- nodes reachable from your PC through a DNS name, and a driver that follows the primary even during failures;
- connections encrypted with TLS, both from the clients to the nodes and between the nodes themselves, enabled without ever stopping the service;
- an application user, automatic consistent backups taken from a secondary, and a tested restore procedure;
- the rolling maintenance procedure, to restart or upgrade the nodes with no interruptions.

**Estimated time:** 2–3 hours.

**Prerequisites:** guide 00 completed (Docker, kernel settings) and guide 01 completed (the private CA in `~/mongodb/tls`, reused here for TLS).

**Verification status:** all the steps have been run and tested on a real installation, except those marked with 🧪 (password change, tearing down the lab, weekly/monthly retention over a real period).

> 📖 **Commands and symbols** (`sudo`, `chmod`, `|`, `<< EOF`, `docker compose`…): the [command legend](linux-commands-legend.md) explains everything that appears in this guide.

---

## Contents

- [Part 0 — Concepts](#part-0--concepts)
- [Part 1 — The lab and the real-world scenario](#part-1--the-lab-and-the-real-world-scenario)
- [Part 2 — Preparation](#part-2--preparation)
- [Part 3 — Building the three nodes](#part-3--building-the-three-nodes)
- [Part 4 — Forming the replica set](#part-4--forming-the-replica-set)
- [Part 5 — Using the replica set](#part-5--using-the-replica-set)
- [Part 6 — Failover](#part-6--failover)
- [Part 7 — Access from your PC](#part-7--access-from-your-pc)
- [Part 8 — TLS without stopping the service](#part-8--tls-without-stopping-the-service)
- [Part 9 — Application user](#part-9--application-user)
- [Part 10 — Backup and restore](#part-10--backup-and-restore)
- [Part 11 — Rolling maintenance](#part-11--rolling-maintenance)
- [Part 12 — Changing a password](#part-12--changing-a-password)
- [Part 13 — When something goes wrong](#part-13--when-something-goes-wrong)
- [Part 14 — Lab and production](#part-14--lab-and-production)
- [Part 15 — Tearing down the lab](#part-15--tearing-down-the-lab)
- [Appendix A — Where everything is](#appendix-a--where-everything-is)
- [Appendix B — Command cheat sheet](#appendix-b--command-cheat-sheet)
- [The 8 golden rules of the replica set](#the-8-golden-rules-of-the-replica-set)

> **Conventions:** the same as in guides 00 and 01 (📍 where to run, ✅ what you should see, `<< EOF` blocks to paste in full, `<...>` placeholders to replace, removing `<` and `>` too). Example VM user: `azureuser`. Placeholders specific to this guide: `<FQDN>` (DNS name of the VM, Part 2.2), `<IP_PRIVATO_VM>` (e.g. `10.0.0.4`).

> **The 🧭 boxes** explain every choice with the same structure: **why** we make it, **if you don't** what happens (often with what really happened during the test run), **alternatives**, **in production**.

---

## Part 0 — Concepts

### 0.1 What a replica set is

A **replica set** is a group of MongoDB servers, usually three, that hold **the same data**.

- Only one of them is the **primary**: it receives all the writes.
- The others are **secondaries**: they continuously copy every change from the primary, reading it from a log of operations called the **oplog**.
- The nodes constantly exchange a sign-of-life signal, the **heartbeat**.

If the primary fails, the others notice and **elect a new primary** among the secondaries, usually within a few seconds: this is automatic **failover**. When the old primary comes back, it rejoins as a secondary and catches up.

```mermaid
flowchart TD
    APP["Application<br/>string with replicaSet=rs0"] -- "reads and writes" --> P["Primary"]
    P -- "oplog" --> S1["Secondary 1"]
    P -- "oplog" --> S2["Secondary 2"]
    P -. "heartbeat" .- S1
    P -. "heartbeat" .- S2
    S1 -. "heartbeat" .- S2
```

### 0.2 Majority and odd numbers

Electing a primary takes the **majority** of the voting members. With three nodes, two are enough: the system survives the loss of any one of them.

This is why you use an **odd** number of nodes. With two, if one goes down the other does not have the majority on its own: no primary, no writes. With four you still survive the loss of only one, just as with three, while paying for an extra server.

> There is also the *arbiter*, a member that votes but holds no data, used to reach an odd number while saving money. It is discouraged in modern setups because it weakens the guarantees on writes: three full nodes are better.

### 0.3 How an application connects

The application does not connect to one specific node but to the whole replica set: in the connection string it lists the nodes and the name of the replica set.

```
mongodb://utente:password@nodo1:27017,nodo2:27017,nodo3:27017/?replicaSet=rs0
```

The driver connects to any one of those addresses, asks what the group looks like, receives the list of members **with the names they are registered under**, finds the primary and sends the writes to it. If the primary changes, the driver follows it on its own: the application changes nothing.

Two concepts tied to the connection string:

- **Write concern:** when to consider a write confirmed. Since MongoDB 5.0 the default value is `majority`: the confirmation arrives when the **majority** of the nodes has received the data. A confirmed write therefore survives the loss of the primary.
- **Read preference:** which node to read from. The default is `primary`. With `secondary` or `secondaryPreferred` you read from the secondaries, taking load off the primary and accepting that the data may be slightly behind.

### 0.4 What it is for

- **High availability:** the database stays up even if a server fails or has to be restarted.
- **Maintenance with no interruptions:** upgrades and restarts one node at a time.
- **Several copies of the data** on different servers.
- **Extra features:** multi-document transactions and *change streams* (real-time notifications of changes) require a replica set; with a single instance like the one in guide 00 they are not available.

### 0.5 What it is NOT

**A replica set is not a backup.** If someone drops a collection, the deletion is replicated to all the nodes in an instant. We will see it with our own eyes in Part 10. Backups remain essential.

### 0.6 Replica set and sharding

| | Replica set | Sharding |
|---|---|---|
| What it does | **Copies** the same data to several servers | **Splits** different data across several servers |
| Solves | Failures, maintenance, availability | Too much data or too many writes for one server |
| Minimum servers in production | 3 | About 10 (2 shards × 3, 3 config servers, routers) |
| When you need it | Almost always, in production | Only with very large volumes |

In a sharded cluster, **every shard is itself a replica set**, and so are the config servers: this guide is the prerequisite for guide 03 on sharding.

---

## Part 1 — The lab and the real-world scenario

### 1.1 What we will build

Three containers on the same VM, each playing the role of a separate server:

| Container | Port (inside and outside) | Member registered as | Role |
|---|---|---|---|
| `mongo-rs1` | 27101 | `<FQDN>:27101` | Preferred primary |
| `mongo-rs2` | 27102 | `<FQDN>:27102` | Secondary |
| `mongo-rs3` | 27103 | `<FQDN>:27103` | Secondary |

> 🧭 **Choice — A lab on a single VM, with one container per node**
>
> **Why:** it faithfully reproduces configuration, commands, authentication between the nodes, elections, failover and TLS, at zero cost and reusing the VM from the previous guides.
>
> **What it does not simulate:** all the nodes share disk, RAM and machine. If the VM stops, the whole replica set goes down: the high availability is for demonstration only. Real network latency and partial network failures are missing too.
>
> **Alternatives:** a new VM dedicated to the lab (more isolation, an extra cost); your PC with Docker Desktop (zero cost, but far from the Azure scenario).
>
> **In production:** three separate VMs, ideally in **different availability zones**, each with its own disk. Every node uses the standard port 27017 and has its own DNS name.

### 1.2 Living alongside the development MongoDB

The MongoDB from guides 00 and 01 runs on the same VM, in `~/mongodb`. Rules for not disturbing it:

- a separate folder, `~/mongo-lab/02-replica-set`;
- different ports (27101–27103);
- a Docker Compose project with its own name, and therefore separate network and volumes;
- limited memory for every lab node.

> ⚠️ **The most important rule in this guide.** `docker compose` commands act on the project **in the folder you are in**. From now on there are two of them on the VM: `~/mongodb` (your development database) and `~/mongo-lab/02-replica-set` (the lab). **Look at the prompt before every `docker compose` command**: a `down -v` in the wrong folder would delete the development data.

---

## Part 2 — Preparation

### 2.1 Checking the resources

> 📍 **On the VM.**

```bash
free -h
nproc
df -h /
sudo docker stats --no-stream
```

The replica set in this guide needs about 2–3 GB of free RAM. During the test run the VM had 7.8 GB of RAM, 2 CPUs and **no swap**: this last detail matters, because without swap, if memory runs out, Linux forcibly kills some process. This is why we will limit the memory of every node (Part 3.4).

### 2.2 Giving the VM a DNS name

In Part 7 we will connect to the replica set from the PC. As we will see, to do that the members must be registered under a **name that the PC can resolve too**, and it is best to choose it **before** creating the replica set.

> 📍 **In the Azure portal.**

Open the **Public IP address** resource attached to the VM (from the VM's *Overview*, click the IP address) → *Configuration* → **DNS name label**. Choose a unique name (for example the name of the VM) and save. The full name appears below, in the form `nome.<regione>.cloudapp.azure.com`: this is your `<FQDN>`.

> 📍 **From the PC**, in PowerShell:

```powershell
Resolve-DnsName <FQDN>
```

✅ It must answer with the public IP of the VM. Propagation can take a few minutes.

### 2.3 The session variables

Many commands in this guide use the DNS name and the private IP. To avoid retyping them, we put them in two variables.

> 📍 **On the VM:**

```bash
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1      # shows the private IP
FQDN=<FQDN>
PRIV_IP=<IP_PRIVATO_VM>
echo "Nome DNS: $FQDN - IP privato: $PRIV_IP"
```

✅ The printed line must show the real values.

> ⚠️ **Variables live only in the current session.** If you close the terminal or reconnect to the VM, repeat these commands before going on. The same will apply to the `rs_eval` function (Part 4.3).

---

## Part 3 — Building the three nodes

> 📍 **On the VM.**

### 3.1 Folder, password and keyFile

```bash
mkdir -p ~/mongo-lab/02-replica-set
cd ~/mongo-lab/02-replica-set

# Administrator password
openssl rand -base64 24 | tr -d '/+=' | sudo tee root_password.txt > /dev/null
sudo chown 999:999 root_password.txt && sudo chmod 600 root_password.txt

# keyFile: the "password" shared between the nodes
openssl rand -base64 756 > keyfile
sudo chown 999:999 keyfile && sudo chmod 400 keyfile
ls -l
```

✅ `keyfile` with `-r--------` and `root_password.txt` with `-rw-------`, both owned by `999` (the `systemd-journal` group that appears next to it is a numbering coincidence, harmless).

> 🧭 **Choice — The keyFile for internal authentication**
>
> **What it is:** a secret file, identical on all the nodes, that the members use to recognize each other. A process that does not have it cannot join the replica set or receive the replicated data. It also turns on mandatory authentication for clients.
>
> **Why the `400` permissions:** MongoDB refuses to start if the keyFile is readable by other users. Owner 999 is the user MongoDB runs as inside the containers.
>
> **If you don't:** with user authentication enabled, MongoDB does not accept a replica set without internal authentication.
>
> **Alternatives:** x.509 certificates to authenticate the members (Part 14.3).
>
> **In production:** the same keyFile, distributed securely to every server, or x.509.

### 3.2 The docker-compose.yml

The file is long: to keep it from getting mangled while pasting (it happened during the test run), we write it in **two parts**. The first (`cat >`) creates the file, the second (`cat >>`) completes it. Both use `<< EOF` **without quotes**, so `$FQDN` and `$PRIV_IP` are replaced with the real values: check first that the variables are set (Part 2.3).

**Part A** — common settings and node 1:

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

**Part B** — nodes 2 and 3, volumes and secret (note the `>>`, which **appends**):

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

**Check:**

```bash
sudo docker compose config --quiet && echo "compose valido"
sudo docker compose config --services
sudo docker compose config --volumes
grep -A1 "extra_hosts" docker-compose.yml
```

✅ `compose valido`, the three services `mongo-rs1`, `mongo-rs2`, `mongo-rs3`, the three volumes, and under `extra_hosts` your DNS name with the private IP (real values, not `$FQDN`).

> ⚠️ `compose valido` alone is not enough: during the test run a file mangled by pasting passed that check even though it was incomplete. The checks on services and volumes are the ones that count. As an alternative to pasting, you can always use the editor: `nano docker-compose.yml`, paste, **Ctrl+O** and Enter, **Ctrl+X**.

### 3.3 What each part means

| Element | Meaning |
|---|---|
| `name: mongo-lab-rs` | Project name: network and volumes get this prefix, separate from the development ones |
| `x-mongo-common` / `<<: *mongo-common` | Common settings written once and applied to the three nodes |
| `stop_grace_period: 1m` | Time given to MongoDB to shut down cleanly (Part 6.3) |
| `extra_hosts` | Inside the containers, the DNS name points to the private IP of the VM (Part 7.2) |
| `mem_limit: 1g` | Memory cap per node |
| `--replSet rs0` | The node is part of the replica set `rs0` |
| `--port 2710x` | Each node's own port, the same inside and outside the container |
| `--keyFile` | Internal authentication (Part 3.1) |
| `--wiredTigerCacheSizeGB 0.25` | A 256 MB cache per node, instead of half the RAM |
| Ports on `127.0.0.1` and `$PRIV_IP` | Reachable from the VM and, through the private IP, from outside (Part 7) |
| `MONGO_INITDB_*` only on node 1 | The `admin` user is created only there |

> 🧭 **Choice — Each node has its own port, the same inside and outside**
>
> **Why:** clients receive from the replica set the list of members **with the registered addresses**, and then connect to those. If all the nodes listened on 27017 inside the container and on different ports only on the outside, the registered addresses would not be reachable from outside.
>
> **If you don't:** the external client connects to the first node but fails right after, when it tries the addresses it received.
>
> **In production:** every node is a different server with its own name, so they can all use the standard port 27017.

> 🧭 **Choice — Admin user created only on node 1**
>
> **Why:** nodes 2 and 3 start empty; when we form the replica set, they will copy everything from node 1 (*initial sync*), user included.
>
> **If you don't:** three independent databases, each with its own admin, to be reconciled.
>
> **Consequence to remember:** the password file is mounted only in the node 1 container. When the password is needed in the other containers, we will pass it in from outside (Part 10).

> 🧭 **Choice — Reduced cache and memory cap**
>
> **Why:** by default every node would use about half the RAM for its cache. Three nodes plus the development instance, on a VM without swap, would risk running out of memory.
>
> **In production:** no artificial limit: every node has its own VM and uses the default cache.

### 3.4 Startup

Check that the prompt shows `~/mongo-lab/02-replica-set`, then:

```bash
sudo docker compose up -d
sudo docker compose ps
sleep 15
sudo docker compose logs mongo-rs1 | grep -E "init process complete|Waiting for connections" | head -3
sudo docker compose logs mongo-rs2 | grep -iE "replica set config|Waiting for connections" | head -3
```

✅ **What to expect:**

- three containers `Up`;
- on node 1: a first `Waiting for connections` on port **27017**, then `MongoDB init process complete`, then `Waiting for connections` on port **27101**. The node first started in a temporary mode to create the `admin` user, then for good on its own port;
- on node 2: `Did not find local replica set configuration document at startup`. **This is normal:** the node knows it is part of `rs0`, but nobody has told it yet who the other members are.

---

## Part 4 — Forming the replica set

> 📍 **On the VM**, in the lab folder.

### 4.1 `rs.initiate`

The command is run **only once, on one node only**: the configuration is propagated to the others. It will ask you for the `admin` password (`sudo cat root_password.txt`):

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

The JavaScript is in double quotes, so the shell replaces `$FQDN` with the real name.

✅ **Expected answer:** `{ ok: 1 }`. An `Authentication failed` just means a wrong password: try again.

**What happens now:** nodes 2 and 3 copy all the data from node 1 (initial sync). With an empty database it takes a few seconds.

> 🧭 **Choice — Members registered with the DNS name**
>
> **Why:** external clients will be able to resolve and reach the same names (Part 7). Every node recognizes itself by reaching its own port through the private IP and Docker's proxy, thanks to `extra_hosts`: during the test run `rs.initiate` worked with no problems.
>
> **If you don't:** registering the members with the container names (`mongo-rs1:27101`…), everything works from inside the VM, but from the PC the driver would receive names it cannot resolve.
>
> **In production:** names are chosen **before** creating the replica set. Changing them later is possible (`rs.reconfig`, one member at a time), but delicate.

> 🧭 **Choice — `priority: 2` on node 1**
>
> **Why:** it makes it predictable who the primary is and lets you watch the role "come back" after a failure (Part 6).
>
> **In production:** it is used to keep the primary in the zone or data center closest to the application. Remember that every time the role is taken back there is a short election.

### 4.2 Checking the status

Wait about ten seconds:

```bash
sudo docker exec -it mongo-rs1 mongosh --port 27101 -u admin -p --authenticationDatabase admin --quiet \
  --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr, "salute:", m.health))'
```

✅ **Expected:** `<FQDN>:27101 PRIMARY`, `<FQDN>:27102 SECONDARY`, `<FQDN>:27103 SECONDARY`, all with health `1`. If you see `STARTUP2`, the sync is in progress: try again after a few seconds.

**The proof of replication:** the `admin` user had been created only on node 1. Connect to node 2:

```bash
sudo docker exec -it mongo-rs2 mongosh --port 27102 -u admin -p --authenticationDatabase admin --quiet \
  --eval 'print("Sono il primario?", db.hello().isWritablePrimary)'
```

✅ If the login succeeds and the answer is `Sono il primario? false`, the user arrived through replication and node 2 is a secondary.

### 4.3 A shortcut for the lab

To avoid typing the password with every command, we define a function that reads it from the file:

```bash
rs_eval() {
  local node=${2:-1}
  sudo docker exec -i -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs$node \
    sh -c 'mongosh --port 2710'"$node"' -u admin -p "$RS_PWD" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

Usage: `rs_eval 'comando'` runs on node 1, `rs_eval 'comando' 3` on node 3.

> 🧭 **Choice — The `rs_eval` function (lab only)**
>
> **Why:** convenience. **Limitation:** it passes the password in a way that makes it visible for a moment to the processes in the container: do not use it in production.
>
> **To remember:** it exists only in the current session (in a new session: `rs_eval: command not found`, it has to be redefined). To avoid retyping it, save it in a file and reload it with `source` in every session, or automatically from `~/.bashrc`: this is the method adopted and tested in guide 03 (Part 5.4), which applies identically here with a file `~/mongo-lab/02-replica-set/funzioni-lab.sh` containing the definition of `rs_eval`. Without a number it queries node 1: if node 1 is off it answers `container ... is not running`, and you have to use `rs_eval '...' 2`. After TLS is enabled it will need updating (Part 8.4).

---

## Part 5 — Using the replica set

### 5.1 Writing through the replica set

We connect the way an application would: with a string that lists all the members and the name of the replica set.

```bash
sudo docker exec -i -e FQDN="$FQDN" -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs1 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/labdb?replicaSet=rs0&authSource=admin" --quiet --eval "
    print(\"Primario trovato dal driver:\", db.hello().primary);
    printjson(db.prova.insertOne({ msg: \"ciao dal replica set\", quando: new Date() }));
  "'
```

✅ **Expected:** `Primario trovato dal driver: <FQDN>:27101` and `acknowledged: true`. The driver queried the members, found the primary on its own and wrote there. With the default write concern `majority`, by the time `acknowledged: true` arrives the data already exists on at least two nodes.

### 5.2 Reading from a secondary

```bash
rs_eval 'db.getMongo().setReadPref("secondary"); printjson(db.getSiblingDB("labdb").prova.find().toArray())' 3
```

✅ The document you just wrote appears: replication works. `setReadPref("secondary")` is needed because, by default, reads go to the primary.

### 5.3 Writing to a secondary

```bash
rs_eval 'db.getSiblingDB("labdb").prova.insertOne({ msg: "scrittura sul secondario" })' 3
```

✅ **It must fail** with `MongoServerError: not primary`: only the primary accepts writes.

---

## Part 6 — Failover

What happens, step by step, when the primary shuts down cleanly:

```mermaid
sequenceDiagram
    participant A as Application / driver
    participant N1 as mongo-rs1 (primary)
    participant N2 as mongo-rs2
    participant N3 as mongo-rs3
    Note over N1: docker compose stop
    N1->>N1: steps down, quiesces for up to ~15 s
    N2->>N3: election: vote
    N3-->>N2: vote granted (majority 2 out of 3)
    Note over N2: new PRIMARY
    A->>N2: the driver finds the new primary, writes
    Note over N1: docker compose start
    N1->>N2: rejoins as SECONDARY, catches up on the oplog
    Note over N1: priority 2: takes back the PRIMARY role
```

> ⚠️ Check that the prompt shows `~/mongo-lab/02-replica-set`: the following command, in `~/mongodb`, would stop the development database.

### 6.1 Shutting down the primary

```bash
sudo docker compose stop mongo-rs1
```

After about ten seconds, query node 2 (node 1 is off):

```bash
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ **Expected:** `<FQDN>:27101 (not reachable/healthy)` and one of nodes 2 and 3 now **PRIMARY**. The two remaining nodes are the majority, so they were able to elect one.

<details>
<summary>📋 Real output from the test run (first failover, with the members registered with the container names)</summary>

```
$ sudo docker compose stop mongo-rs1
 ✔ Container mongo-rs1 Stopped                                   11.0s   <- prima di stop_grace_period (Parte 6.3)

$ rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
mongo-rs1:27101 SECONDARY          <- ha già ceduto il ruolo ed è in quiesce
mongo-rs2:27102 PRIMARY
mongo-rs3:27103 SECONDARY

$ rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
mongo-rs1:27101 (not reachable/healthy)
mongo-rs2:27102 PRIMARY
mongo-rs3:27103 SECONDARY

# Stessa stringa di connessione, nuovo primario trovato dal driver:
Primario trovato dal driver: mongo-rs2:27102
{ acknowledged: true, insertedId: ObjectId('6abb9e00b55e465977359d42') }
```

</details>

**Does the application notice?** Same string as before, run from node 2:

```bash
sudo docker exec -i -e FQDN="$FQDN" -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs2 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/labdb?replicaSet=rs0&authSource=admin" --quiet --eval "
    print(\"Primario trovato dal driver:\", db.hello().primary);
    printjson(db.prova.insertOne({ msg: \"scritto durante il guasto\", quando: new Date() }));
  "'
```

✅ The driver finds the **new** primary and the write succeeds, without changing anything in the connection string.

### 6.2 The return

```bash
sudo docker compose start mongo-rs1
```

Run this twice, right away and after about 30 seconds:

```bash
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ On the first reading node 1 is **SECONDARY**: it rejoins and catches up on the writes it missed. On the second it is **PRIMARY** again, thanks to `priority: 2`.

**No data lost:**

```bash
rs_eval 'printjson(db.getSiblingDB("labdb").prova.find({}, { _id: 0, msg: 1 }).toArray())'
```

✅ Both documents: `ciao dal replica set` and `scritto durante il guasto`.

### 6.3 Clean shutdown and `stop_grace_period`

When a primary receives the request to shut down, it immediately gives up its role and enters a **quiesce** phase: it stays on as a secondary for a while, up to about **15 seconds**, to give clients time to move to the new primary. Then it closes cleanly.

Check that the shutdown was clean:

```bash
sudo docker compose logs mongo-rs1 | grep -o '"Startup from clean shutdown?":[a-z]*' | tail -1
```

✅ `"Startup from clean shutdown?":true`. Stopping the primary takes about 16 seconds.

<details>
<summary>📋 Real output from the test run: without and with stop_grace_period</summary>

```
# Senza stop_grace_period (Docker termina dopo 10 s):
 ✔ Container mongo-rs1 Stopped                                   11.0s
"Startup from clean shutdown?":false

# Con stop_grace_period: 1m:
 ✔ Container mongo-rs1 Stopped                                   15.9s
"Startup from clean shutdown?":true
```

</details>

> 🧭 **Choice — `stop_grace_period: 1m`**
>
> **Why:** Docker, by default, waits only **10 seconds** and then forcibly kills the container.
>
> **If you don't — what happened in the test run:** without this option, stopping the primary took **11 seconds** (the 10 of waiting plus the forced kill); right afterwards the node still showed as `SECONDARY`, because it was in quiesce; and on restart the logs reported `"Startup from clean shutdown?":false`. For MongoDB this is like a power cut: no data lost thanks to the journal, but a recovery at startup. With the option: stop in about 16 seconds and `true`.
>
> **In production:** it applies to any MongoDB in a container. This is why `stop_grace_period` was also added to the compose files in guides 00 and 01.

> **Sudden failure vs clean shutdown.** With `docker compose stop` the primary warns the others and the election is almost instant. With a real failure (crash, frozen VM) the secondaries notice only when they stop receiving the heartbeat, by default after about 10 seconds: during that interval writes are left waiting.

---

## Part 7 — Access from your PC

### 7.1 The problem

It might seem enough to put the public IP of the VM in the connection string. It is not:

1. the client connects to the address you give it;
2. the server answers with the list of members **as they are registered**;
3. from that moment the client uses **those names**, not the initial address.

So the PC must be able to resolve and reach the names of the members.

| Alternative | How | Pros | Cons |
|---|---|---|---|
| Direct connection to one node | `directConnection=true` and public IP | No configuration | No failover; writes only if that node is the primary |
| `hosts` file on the PC | The member names pointed at the IP of the VM | Simple | Has to be edited on every client |
| Members registered with the public IP | Public IP in `rs.initiate` | No DNS | The nodes too would talk to each other by going outside: fragile |
| **DNS name** (chosen) | Azure DNS name + `extra_hosts` | No changes to the clients, as in production | Requires a public DNS name |

### 7.2 How the chosen solution works

The name `<FQDN>` is the same for everyone, but it resolves differently depending on who looks it up:

- **from the PC:** public DNS resolves it to the **public IP** → the Azure NSG lets it through → the connection reaches the **private IP** of the VM → Docker forwards it to the right node based on the **port**;
- **inside the containers:** `extra_hosts` makes it point straight to the **private IP**, so the nodes talk to each other without leaving the VM.

Clients and nodes use the same names, exactly as in production with a corporate DNS. This is why, in Part 3, we published the ports on the private IP too.

```mermaid
flowchart LR
    subgraph PCS["From your PC"]
        PC["VS Code"] -- "public DNS" --> PUB["Public IP"]
    end
    PUB -- "NSG: 27101-27103<br/>your IP only" --> PRIV
    subgraph VMS["On the VM"]
        PRIV["Private IP:2710x"] -- "published port" --> NODE["Node mongo-rs x"]
        NODE2["Replica set node"] -- "extra_hosts:<br/>FQDN = private IP" --> PRIV
    end
```

### 7.3 The NSG rule

> 📍 **In the Azure portal:** VM → *Networking* → *Create port rule* → *Inbound port rule*.

| Field | Value |
|---|---|
| Source | *IP Addresses* |
| Source IP addresses | your public IP (search for "what is my ip" in the PC's browser) |
| Destination port ranges | `27101-27103` |
| Protocol | TCP |
| Action | Allow |
| Name | `mongo-lab-rs` |

> ⚠️ **Never "Any" as the source.** Until Part 8 the lab traffic travels unencrypted, password included.

### 7.4 Checking from the PC

> 📍 **From the PC**, in PowerShell:

```powershell
27101..27103 | ForEach-Object { Test-NetConnection <FQDN> -Port $_ | Select-Object RemotePort, TcpTestSucceeded }
```

✅ `True` three times. If any is `False`: check the NSG rule and that `sudo ss -ltnp | grep 2710` on the VM shows the ports on the private IP too.

### 7.5 Connecting from VS Code

MongoDB for VS Code extension → **Ctrl+Shift+P** → *MongoDB: Connect with Connection String*:

```
mongodb://admin:PASSWORD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/?replicaSet=rs0&authSource=admin
```

✅ It connects and shows `labdb`.

> ⚠️ **The connection string is pasted into the client, not into the VM's terminal.** During the test run it ended up in bash by mistake: the `&` character sent the command to the background (`[1] 12022`, then `No such file or directory`). No harm done, but the line, password included, stays in the history. To remove it: `history | grep "mongodb://"` and then `history -d <numero>`.

**The nicest proof:** with VS Code connected, shut down the primary from the VM (`sudo docker compose stop mongo-rs1`), wait about twenty seconds and insert a document from VS Code: it works, because the driver has moved to the new primary. Then `sudo docker compose start mongo-rs1`.

> 🧭 **In production**, the `hosts` file and a public DNS name are not needed: every node has a corporate DNS name on the private network, and the clients are on the same network. If external and internal clients must see different addresses, MongoDB offers **horizons**, which require TLS.

---

## Part 8 — TLS without stopping the service

### 8.1 What to protect

On a replica set there are **two legs** to encrypt:

- **from the clients to the nodes**, as in guide 01;
- **between the nodes**: data replication and heartbeat.

We will do it **without ever stopping the replica set**, going through three modes:

| Mode | Accepts incoming | Uses towards the other nodes |
|---|---|---|
| `allowTLS` | encrypted and unencrypted | unencrypted |
| `preferTLS` | encrypted and unencrypted | encrypted |
| `requireTLS` | encrypted only | encrypted |

The phases: certificate → rolling restart in `allowTLS` → live switch to `preferTLS` and moving the clients → live switch to `requireTLS` → configuration made permanent.

```mermaid
stateDiagram-v2
    SenzaTLS: No TLS
    Permanente: Permanent
    [*] --> SenzaTLS
    SenzaTLS --> allowTLS: compose + rolling restart
    allowTLS --> preferTLS: live setParameter
    preferTLS --> preferTLS: moving the clients to tls=true
    preferTLS --> requireTLS: live setParameter
    requireTLS --> Permanente: compose requireTLS + rolling restart
    Permanente --> [*]
    note right of preferTLS
        still accepts unencrypted clients:
        window for migrating them
    end note
```

### 8.2 The nodes' certificate

> 📍 **On the VM** (with `$FQDN` and `$PRIV_IP` set).

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

✅ The last line contains the real values.

Generate and sign the certificate with the **CA from guide 01**:

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

✅ `server.crt: OK`, the SAN names and the line `TLS Web Server Authentication, TLS Web Client Authentication`.

> If you chose not to keep `ca.key` on the VM (guide 01, Part 5.2), bring it back temporarily into `~/mongodb/tls` for this signing, then remove it again. The `ca.srl` counter moves forward: update the copy on the PC too.

Files and permissions for MongoDB:

```bash
cat server.crt server.key | sudo tee server.pem > /dev/null
sudo chown 999:999 server.pem && sudo chmod 600 server.pem
chmod 600 server.key && chmod 644 ca.pem server.crt
ls -l
cd ..
```

> 🧭 **Choice — Reused CA, one certificate, client and server usage**
>
> **Why the same CA as guide 01:** `ca.pem` is already on the PC and the clients already know how to use it; in production a single CA for all the servers is normal.
>
> **Why only one certificate:** in the lab the three nodes share the same DNS name.
>
> **Why `clientAuth` — the most important detail:** when a node connects to another one to replicate, it acts as a **client** and presents the same certificate. With `serverAuth` alone the other node would reject it and replication would stop. It is the most frequent cause of problems with TLS on replica sets.
>
> **In production:** one certificate per server, with its name in the SAN, from the corporate CA.

### 8.3 Phase 1 — `allowTLS`, with a rolling restart

We update the compose file (with a safety copy for rollback), adding the TLS options and the two files to every node:

```bash
cd ~/mongo-lab/02-replica-set
cp docker-compose.yml docker-compose.yml.pre-tls
sed -i 's|"--wiredTigerCacheSizeGB", "0.25"\]|"--wiredTigerCacheSizeGB", "0.25", "--tlsMode", "allowTLS", "--tlsCertificateKeyFile", "/etc/mongo/tls/server.pem", "--tlsCAFile", "/etc/mongo/tls/ca.pem", "--tlsAllowConnectionsWithoutCertificates", "--tlsDisabledProtocols", "TLS1_0,TLS1_1"]|' docker-compose.yml
sed -i 's|^      - ./keyfile:/etc/mongo/keyfile:ro$|&\n      - ./tls/server.pem:/etc/mongo/tls/server.pem:ro\n      - ./tls/ca.pem:/etc/mongo/tls/ca.pem:ro|' docker-compose.yml
grep -c "allowTLS" docker-compose.yml
grep -c "server.pem:ro" docker-compose.yml
sudo docker compose config --quiet && echo "compose valido"
```

✅ `3`, `3`, `compose valido`. The options are the ones from guide 01; `--tlsAllowConnectionsWithoutCertificates` remains essential, otherwise with a CA specified MongoDB would demand a certificate from every client.

**Rolling restart.** `docker compose up -d <servizio>` recreates **only that node** with the new configuration. First the secondaries, then the primary after making it give up its role. **One command at a time**, waiting for the prompt:

```bash
sudo docker compose up -d mongo-rs3
```

```bash
sleep 15; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

When node 3 is `SECONDARY`:

```bash
sudo docker compose up -d mongo-rs2
```

```bash
sleep 15; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 3
```

When node 2 is `SECONDARY`:

```bash
rs_eval 'rs.stepDown(60); print("fatto")'
```

```bash
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

With node 1 `SECONDARY`:

```bash
sudo docker compose up -d mongo-rs1
```

**Check** (after about a minute):

```bash
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
openssl s_client -connect 127.0.0.1:27101 -CAfile tls/ca.pem </dev/null 2>/dev/null | grep -E "Verify return code|Protocol"
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ `allowTLS` three times, `Verify return code: 0 (ok)` with TLS 1.3, the three members healthy. `rs_eval` and the clients keep working unencrypted: at this phase that is how it should be.

### 8.4 Phase 2 — `preferTLS` and moving the clients

The mode change is made **live**, with no restarts:

```bash
for n in 1 2 3; do rs_eval 'printjson(db.adminCommand({ setParameter: 1, tlsMode: "preferTLS" }).was)' $n; done
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
```

✅ `allowTLS` three times (the previous mode), then `preferTLS` three times.

> ⚠️ **A parameter changed live is lost on restart.** A node that restarted now would go back to the mode in the compose file (`allowTLS`): harmless at this phase, but this is why we will update the compose file at the end.

**Are the nodes talking to each other over TLS?** Replication connections that are already open stay unencrypted until they are renewed: we force an election, then read the counters of encrypted connections received by each node.

```bash
rs_eval 'rs.stepDown(30); print("fatto")'
sleep 45
for n in 1 2 3; do rs_eval 'printjson(db.serverStatus().transportSecurity)' $n; done
```

✅ On every node `'1.3'` greater than zero (in the test run: 18–21) and zero for the older versions.

<details>
<summary>📋 Real output from the test run</summary>

```
{ '1.0': Long('0'), '1.1': Long('0'), '1.2': Long('0'), '1.3': Long('19'), unknown: Long('0') }
{ '1.0': Long('0'), '1.1': Long('0'), '1.2': Long('0'), '1.3': Long('18'), unknown: Long('0') }
{ '1.0': Long('0'), '1.1': Long('0'), '1.2': Long('0'), '1.3': Long('21'), unknown: Long('0') }
```

</details>

**Update `rs_eval`** so that it uses TLS:

```bash
rs_eval() {
  local node=${2:-1}
  sudo docker exec -i -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs$node \
    sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 2710'"$node"' -u admin -p "$RS_PWD" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

**Update VS Code** (the `ca.pem` is the same one as in guide 01, already on the PC):

```
mongodb://admin:PASSWORD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/?replicaSet=rs0&authSource=admin&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

✅ It connects. At this phase **the old unencrypted connection still works too**: it is the window meant for moving the clients one at a time.

> **Before going on**, make sure that **all** the clients use TLS: from the next step unencrypted connections will be rejected.

### 8.5 Phase 3 — `requireTLS` and permanent configuration

**Live switch:**

```bash
for n in 1 2 3; do rs_eval 'printjson(db.adminCommand({ setParameter: 1, tlsMode: "requireTLS" }).was)' $n; done
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
```

✅ `preferTLS` three times, then `requireTLS` three times.

**The proof of the opposite:**

```bash
sudo docker exec mongo-rs2 mongosh --port 27102 --quiet --eval 'db.runCommand({ ping: 1 })'
```

✅ **It must fail** with `MongoServerSelectionError: connection ... closed`. The old VS Code connection without TLS stops working too: you can delete it.

<details>
<summary>📋 Real output from the test run</summary>

```
$ for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
requireTLS
requireTLS
requireTLS
$ sudo docker exec mongo-rs2 mongosh --port 27102 --quiet --eval 'db.runCommand({ ping: 1 })'
MongoServerSelectionError: connection <monitor> to 127.0.0.1:27102 closed
```

</details>

**Making the mode permanent** with one last rotation:

```bash
cp docker-compose.yml docker-compose.yml.allowtls
sed -i 's|"--tlsMode", "allowTLS"|"--tlsMode", "requireTLS"|' docker-compose.yml
grep -c "requireTLS" docker-compose.yml
sudo docker compose config --quiet && echo "compose valido"
```

Then, one command at a time, the same rotation as in phase 1: `up -d mongo-rs3` → check → `up -d mongo-rs2` → check → `rs.stepDown(60)` → `up -d mongo-rs1`.

**Final check** (after about a minute):

```bash
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ `requireTLS` three times, now read from the startup configuration, and the three members healthy. The lab is encrypted in every part.

> 🧭 **Choice — Migration in three phases**
>
> **Why:** at every moment there is a primary and the clients keep working; they move to TLS one at a time during `preferTLS`.
>
> **If you don't:** going straight to `requireTLS` with a restart, all the clients not yet updated would get stuck at the same instant.
>
> **In production:** same procedure, with a `preferTLS` window as long as it takes to update all the applications.

**Going back**, should you need to: `cp docker-compose.yml.pre-tls docker-compose.yml` and a rotation of the three nodes. 🧪 This procedure has not been tested.

---

## Part 9 — Application user

As in guide 00, applications do not use `admin` but a user limited to their own database. We create it **through the replica set string**, so the command is sure to reach the primary.

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

**Check**, reading from a secondary as `appuser`:

```bash
sudo docker exec -i -e FQDN="$FQDN" -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-rs3 \
  sh -c 'mongosh "mongodb://appuser:$APP_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/labdb?replicaSet=rs0&authSource=labdb&tls=true&tlsCAFile=/etc/mongo/tls/ca.pem&readPreference=secondary" --quiet \
    --eval "print(\"Letto da:\", db.hello().me); print(\"Documenti in prova:\", db.prova.countDocuments())"'
```

✅ `Letto da:` with the port of a secondary: the user has been replicated and works there too.

**The string for applications:**

```
mongodb://appuser:PASSWORD@<FQDN>:27101,<FQDN>:27102,<FQDN>:27103/labdb?replicaSet=rs0&authSource=labdb&tls=true&tlsCAFile=C:/Users/<tuo-nome>/mongodb-ca/ca.pem
```

| Parameter | Meaning |
|---|---|
| the three `host:porta` | starting points for discovering the replica set |
| `/labdb` | default database |
| `replicaSet=rs0` | checks that you are on the right replica set |
| `authSource=labdb` | the user is defined in `labdb`, not in `admin` |
| `tls=true` | mandatory: without it, the server closes the connection |
| `tlsCAFile` | the CA used to verify the nodes |

> What enforces encryption **is the server** (`requireTLS`), not the string: the string only makes the client connect in the accepted way. A string without `replicaSet=rs0` works anyway (drivers discover the members on their own), but the parameter is still recommended; `directConnection=true`, on the other hand, would pin the client to a single node, with no failover.

From VS Code, connected as `appuser`, you will see only the `labdb` database.

---

## Part 10 — Backup and restore

### 10.1 A replica set is not a backup: the proof

```bash
rs_eval 'db.getSiblingDB("labdb").prova.insertOne({ msg: "documento importante" }); print("Documenti:", db.getSiblingDB("labdb").prova.countDocuments())'
rs_eval 'db.getSiblingDB("labdb").prova.drop(); print("Documenti:", db.getSiblingDB("labdb").prova.countDocuments())'
rs_eval 'db.getMongo().setReadPref("secondary"); print("Sul nodo 3:", db.getSiblingDB("labdb").prova.countDocuments())' 3
```

The deletion reached the secondary too, in an instant. If `rs_eval` answers `not primary`, node 1 is not the primary at that moment: wait for it to take the role back and try again.

### 10.2 What changes compared with the backup in guide 00

> 🧭 **Choice — A backup script dedicated to the replica set**
>
> - **It connects to the replica set** and reads preferably from a secondary (`readPreference=secondaryPreferred`), so it does not weigh on the primary; if the secondaries are not available, it falls back to the primary instead of failing.
> - **It uses `--oplog`:** a dump takes time and meanwhile the application is writing; with the oplog, `mongodump` also records the operations that happened during the backup and the restore (`--oplogReplay`) reapplies them, for a copy that is **consistent at a single point in time**. It works only on replica sets.
> - **It uses TLS**, mandatory by now.
> - **It runs in the first node that is up:** any node can be off, and the password file exists only in node 1. So the password is read on the VM and passed to the container through **standard input**, which does not show up in the process list.
>
> **In production:** same logic, from an administration server or from a node; backups copied off the database servers; often from a dedicated, hidden secondary (`hidden: true`, `priority: 0`).

### 10.3 The script

The script is written in **two parts**: the first (`<< EOF` without quotes) inserts the real values of `$HOME` and `$FQDN`, the second (`<< 'EOF'`) is copied literally.

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

✅ The `LAB=` and `FQDN=` lines contain the real values. The retention is the same as in guide 00: 7 daily, 4 weekly (🧪 not yet observed over a real period), 12 monthly.

### 10.4 Tests

```bash
sudo /usr/local/bin/mongo-rs-backup.sh
sudo ls -lh /var/backups/mongo-lab-rs/daily
```

✅ `Backup completato (mongo-rs1): ...` and the file with `-rw-------` permissions, owned by root.

**With node 1 off**, one command at a time:

```bash
sudo docker compose stop mongo-rs1
```

```bash
sudo /usr/local/bin/mongo-rs-backup.sh
```

```bash
sudo docker compose start mongo-rs1
```

✅ The backup succeeds, showing `(mongo-rs2)`.

### 10.5 The nightly timer

At a different time from the one in guide 00 (02:30), so they do not overlap:

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

✅ Both timers listed (02:30 and 03:00 UTC) and `Backup completato` in the journal.

### 10.6 Restore

A full test: a document, a backup, an incident, the restore.

```bash
rs_eval 'db.getSiblingDB("labdb").prova.insertOne({ msg: "prova ripristino" }); print("Documenti:", db.getSiblingDB("labdb").prova.countDocuments())'
sudo /usr/local/bin/mongo-rs-backup.sh
rs_eval 'db.getSiblingDB("labdb").prova.drop(); print("Documenti:", db.getSiblingDB("labdb").prova.countDocuments())'
```

The restore from the most recent backup, through the replica set string (so `mongorestore` writes to the primary wherever it is) and with TLS. Standard input carries the password first (one line, read by `read`) and then the backup file:

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

✅ `document(s) restored successfully` and the document back in its place.

<details>
<summary>📋 Real output from the test run</summary>

```
2026-09-29T15:12:40.882+0000    preparing collections to restore from
2026-09-29T15:12:40.882+0000    don't know what to do with subdirectory `labdb`, skipping...
2026-09-29T15:12:40.945+0000    finished restoring `labdb.prova` (1 document, 0 failures)
2026-09-29T15:12:40.945+0000    restoring users from `archive on stdin`
2026-09-29T15:12:41.042+0000    replaying oplog
2026-09-29T15:12:41.044+0000    applied 1 oplog entries
2026-09-29T15:12:41.044+0000    1 document(s) restored successfully. 0 document(s) failed to restore.
```

</details>

**Two kinds of messages to know:**

- `don't know what to do with subdirectory ..., skipping...`: **harmless**, they appear when restoring an archive that contains the oplog;
- `applied N oplog entries`: the operations captured during the backup and reapplied. It can be zero, or greater than zero even if the application was not writing: a replica set also records internal operations. Both cases were seen in the test run.

---

## Part 11 — Rolling maintenance

This is the most common operation on a replica set in production: MongoDB upgrades, operating system patches, configuration changes. The rule: **secondaries first, one at a time; the primary last, after making it give up its role.**

```mermaid
flowchart TD
    A["Restart a secondary"] --> B{"Is it back to<br/>SECONDARY?"}
    B -- "no, wait" --> B
    B -- "yes" --> C{"Other secondaries<br/>to restart?"}
    C -- "yes" --> A
    C -- "no" --> D["rs.stepDown on the primary"]
    D --> E{"Is another node<br/>PRIMARY?"}
    E -- "no, wait" --> E
    E -- "yes" --> F["Restart the old primary"]
    F --> G["With priority 2 it takes back the role"]
```

> ⚠️ **One command at a time.** Every restart takes about 16 seconds (the clean shutdown). During the test run, pasting the next commands while a restart was in progress made the terminal mix up the lines, and the `stepDown` was not executed. Always wait for the prompt, and count waiting times from the end of the restart.

```bash
sudo docker compose restart mongo-rs3
```

```bash
sleep 20; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

Only when node 3 is back to `SECONDARY` (restarting two together would lose the majority):

```bash
sudo docker compose restart mongo-rs2
```

```bash
sleep 20; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 3
```

The primary gives up its role:

```bash
rs_eval 'rs.stepDown(60); print("fatto")'
```

```bash
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ Node 1 is `SECONDARY`, another one is `PRIMARY`. The `60` prevents node 1 from standing for election again for 60 seconds. If the command answers with a closed connection instead of `fatto`, that is normal: the node closes its connections when it changes role.

```bash
sudo docker compose restart mongo-rs1
```

```bash
sleep 60; rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' 2
```

✅ Node 1 is `PRIMARY` again. A connected client (for example VS Code) does not lose its connection during the whole sequence: in the test run it held with no interruptions.

> 🧭 **Why the explicit `stepDown`**, if a primary that shuts down cleanly gives up its role on its own anyway (we saw exactly that when the `stepDown` got lost)? Because it lets you **choose the moment** of the election and **check** that another node is primary **before** shutting down the old one.
>
> **To change configuration** you use `docker compose up -d <servizio>` instead of `restart`: it recreates the node with the updated compose file (as in Part 8). **To upgrade MongoDB**, same sequence, changing the image tag.

---

## Part 12 — Changing a password

🧪 *Not tested in the lab.*

On a replica set it is enough to make the change on the primary: the change is replicated to the other nodes on its own. For `appuser`, through the replica set string:

```bash
cd ~/mongo-lab/02-replica-set
openssl rand -base64 24 | tr -d '/+=' | sudo tee appuser_password.txt > /dev/null
sudo docker exec -i -e FQDN="$FQDN" \
  -e RS_PWD="$(sudo cat root_password.txt)" -e APP_PWD="$(sudo cat appuser_password.txt)" mongo-rs1 \
  sh -c 'mongosh "mongodb://admin:$RS_PWD@$FQDN:27101,$FQDN:27102,$FQDN:27103/?replicaSet=rs0&authSource=admin&tls=true&tlsCAFile=/etc/mongo/tls/ca.pem" --quiet \
    --eval "db.getSiblingDB(\"labdb\").changeUserPassword(\"appuser\", process.env.APP_PWD)"'
```

For `admin`: same procedure with `db.getSiblingDB("admin").changeUserPassword("admin", ...)`, updating `root_password.txt` (owner 999, `600`) **only after** the change has succeeded, because the backup script reads it.

In production it must always be done if a password is exposed (in a chat, in a ticket, in a terminal's history).

---

## Part 13 — When something goes wrong

### During the build

| Symptom | Cause | Solution |
|---|---|---|
| Odd line like `EOF file: ./root_password...` while pasting | Long block mangled by the terminal | Recreate the compose file in two parts or with `nano`; check with `config --services` and `--volumes` |
| `compose valido` but services or volumes are missing | Incomplete file | As above |
| Node 2 or 3: `Did not find local replica set configuration document` | Normal before `rs.initiate` | Run Part 4.1 |
| `rs.initiate`: `Authentication failed` | Wrong password | Read it again with `sudo cat root_password.txt` |
| Containers that do not start, with errors about the keyFile | keyFile permissions | `sudo chown 999:999 keyfile && sudo chmod 400 keyfile` |
| The `grep` for `extra_hosts` shows a literal `$FQDN` | Variables not set before pasting | Set the variables (Part 2.3) and recreate the compose file |

### During use

| Symptom | Cause | Solution |
|---|---|---|
| `rs_eval: command not found` | New session | Redefine the function (Part 4.3 or 8.4) |
| `container ... is not running` with `rs_eval` | The node being queried is off | Use another node: `rs_eval '...' 2` |
| `not primary` | Write to a secondary, or `rs_eval` on node 1 when it is not the primary | Write through the replica set string, or wait for node 1 to take the role back |
| Stop that takes ~11 s and `clean shutdown: false` | `stop_grace_period` is missing | Add it and recreate the nodes |
| Commands pasted during a restart "disappear" | Mixed-up output | One command at a time, waiting for the prompt |
| `[1] 12345` and `No such file or directory` after pasting a `mongodb://` string | String pasted into bash | It goes into the client; remove the line from the history (Part 7.5) |

### Access from outside

| Symptom | Cause | Solution |
|---|---|---|
| The client connects to the public IP but then fails | The members are registered with names the PC cannot resolve | DNS name (Part 7) |
| `Test-NetConnection` `False` | NSG, or ports not published on the private IP | NSG rule 27101–27103 and `sudo ss -ltnp \| grep 2710` |
| `Resolve-DnsName` does not resolve | DNS label not set or not yet propagated | Azure portal, wait a few minutes |
| It stops working after some days | Your public IP has changed | Update the source of the NSG rule |

### TLS

| Symptom | Cause | Solution |
|---|---|---|
| Replication interrupted after enabling TLS, certificate errors between the nodes | Certificate without `clientAuth` | Regenerate with `extendedKeyUsage=serverAuth,clientAuth` |
| No client can connect any more with just the password | `--tlsAllowConnectionsWithoutCertificates` is missing | Add it to the compose file |
| `connection ... closed` from the client | The client is not using TLS | `tls=true` in the string |
| `certificate verify failed` | Wrong `tlsCAFile` | Path of the `ca.pem` of the right CA |
| `IP address mismatch` / `altnames` | Name or IP not in the SAN | Use `<FQDN>`, or add the name and renew the certificate |
| After a restart a node has gone back to a previous mode | Mode changed only live | Update the compose file (Part 8.5) |
| `transportSecurity` counters at zero after `preferTLS` | Replication connections not yet renewed | `rs.stepDown(30)` and wait |

### Backup and restore

| Symptom | Cause | Solution |
|---|---|---|
| `No such file` on `/run/secrets/...` in `mongo-rs2`/`mongo-rs3` | The secret exists only in node 1 | Password via standard input, as in the script |
| Backup failed after enabling TLS | Command without `--ssl --sslCAFile` | Use the script from Part 10.3 |
| `don't know what to do with subdirectory` | Normal with archives that contain the oplog | No action |
| Backup file readable by other users | Saved outside the protected folder | Use the script (`700` folder, `umask 077`) |

---

## Part 14 — Lab and production

### 14.1 The differences at a glance

| Aspect | Lab | Production |
|---|---|---|
| Servers | 3 containers on the same VM | 3 VMs, different availability zones |
| Machine failure | The whole replica set goes down | One node goes down, the service continues |
| Resources | 256 MB cache, `mem_limit` 1 GB | Default cache, dedicated resources |
| Member names | One Azure DNS name + different ports, `extra_hosts` | One DNS name per node, corporate DNS |
| Ports | 27101–27103 | 27017 on every node |
| Client network | From the internet, NSG limited to one IP | Private network (VNet, peering, VPN) |
| Encryption | Mandatory TLS, clients and between nodes | Same |
| Certificates | One for all the nodes, private CA | One per node, corporate or public CA |
| Internal authentication | keyFile | keyFile or x.509 |
| Secrets | Files on the VM, `rs_eval` function | Key Vault or a secrets manager |
| Backup | Script on the VM, local folder | Scheduled, copied off the servers, possibly from a hidden secondary |

### 14.2 Checklist for production

- [ ] Three nodes on three VMs in different availability zones, dedicated data disks (XFS).
- [ ] DNS names for every node, chosen before `rs.initiate`.
- [ ] No exposure to the internet: clients on the same private network.
- [ ] Mandatory TLS, one certificate per node with `serverAuth` and `clientAuth`.
- [ ] keyFile (or x.509) distributed securely.
- [ ] Secrets in Key Vault; no convenience function that exposes passwords.
- [ ] Scheduled backups, copied out of the region or at least off the database servers, restore tested periodically.
- [ ] Monitoring of the members' status and of the *replication lag*.
- [ ] Rolling maintenance procedure documented and tested.
- [ ] `stop_grace_period` (or the equivalent in the system that manages the processes) long enough for a clean shutdown.

### 14.3 Advanced options (not tested in the lab)

- **x.509 authentication of the members** (`clusterAuthMode: x509`): the nodes recognize each other with certificates instead of the keyFile.
- **Hidden secondary for backups** (`hidden: true`, `priority: 0`): it receives no traffic from clients, ideal for backups.
- **Horizons**: different addresses for internal and external clients, based on the name requested in TLS.
- **Members in another region** with `priority: 0`, for disaster recovery.

---

## Part 15 — Tearing down the lab

🧪 *Not tested.* When the lab is no longer needed:

```bash
cd ~/mongo-lab/02-replica-set
pwd                                   # must be the lab folder!
sudo docker compose down -v
sudo systemctl disable --now mongo-rs-backup.timer
sudo rm /etc/systemd/system/mongo-rs-backup.service /etc/systemd/system/mongo-rs-backup.timer
sudo systemctl daemon-reload
sudo rm /usr/local/bin/mongo-rs-backup.sh
```

Then, as you prefer: delete the `~/mongo-lab/02-replica-set` folder and the backups in `/var/backups/mongo-lab-rs`, the NSG rule `mongo-lab-rs` and, if it is not needed for anything else, the DNS label; in VS Code, the connections to the lab.

---

## Appendix A — Where everything is

| What | Where |
|---|---|
| Lab folder | `~/mongo-lab/02-replica-set` |
| Configuration | `docker-compose.yml` (copies: `.pre-tls`, `.allowtls`) |
| keyFile | `keyfile` (`400`, owner 999) |
| Passwords | `root_password.txt` (owner 999), `appuser_password.txt` |
| Certificates | `tls/` (`server.pem` owner 999 `600`, `ca.pem`, `server.crt`, `server.key`, `server.ext`) |
| CA used for signing | `~/mongodb/tls/` (guide 01) |
| Data | Volumes `mongo-lab-rs_rs1-data`, `_rs2-data`, `_rs3-data` |
| Backup script | `/usr/local/bin/mongo-rs-backup.sh` |
| Backups | `/var/backups/mongo-lab-rs/daily`, `weekly`, `monthly` |
| Timer | `/etc/systemd/system/mongo-rs-backup.{service,timer}` (03:00 UTC) |
| Azure | DNS label on the public IP; NSG rule `mongo-lab-rs` (27101–27103) |

---

## Appendix B — Command cheat sheet

```bash
cd ~/mongo-lab/02-replica-set
FQDN=<FQDN>; PRIV_IP=<IP_PRIVATO_VM>

# Convenience function with TLS (in every new session)
rs_eval() {
  local node=${2:-1}
  sudo docker exec -i -e RS_PWD="$(sudo cat ~/mongo-lab/02-replica-set/root_password.txt)" mongo-rs$node \
    sh -c 'mongosh --tls --tlsCAFile /etc/mongo/tls/ca.pem --port 2710'"$node"' -u admin -p "$RS_PWD" --authenticationDatabase admin --quiet --eval "$0"' "$1"
}

# Member status
rs_eval 'rs.status().members.forEach(m => print(m.name, m.stateStr, "salute:", m.health))' 2

# TLS mode and encrypted connections
for n in 1 2 3; do rs_eval 'print(db.adminCommand({ getParameter: 1, tlsMode: 1 }).tlsMode)' $n; done
for n in 1 2 3; do rs_eval 'printjson(db.serverStatus().transportSecurity)' $n; done

# Give up the primary role
rs_eval 'rs.stepDown(60); print("fatto")'

# Did the clean shutdown succeed?
sudo docker compose logs mongo-rs1 | grep -o '"Startup from clean shutdown?":[a-z]*' | tail -1

# Backup
sudo /usr/local/bin/mongo-rs-backup.sh
sudo journalctl -u mongo-rs-backup.service -n 5 --no-pager
```

**From the PC:**

```powershell
Resolve-DnsName <FQDN>
27101..27103 | ForEach-Object { Test-NetConnection <FQDN> -Port $_ | Select-Object RemotePort, TcpTestSucceeded }
```

---

## The 8 golden rules of the replica set

1. **Look at the prompt** before every `docker compose`: there are two projects on the VM.
2. **An odd number of nodes**, and never more than one off at a time.
3. **A replica set is not a backup**: you need backups anyway.
4. **Choose the member names before `rs.initiate`**: every client must be able to resolve them.
5. A generous **`stop_grace_period`**: let MongoDB shut down cleanly.
6. **Certificates with `serverAuth` and `clientAuth`**: the nodes are also clients of one another.
7. **TLS in three phases** (`allowTLS` → `preferTLS` → `requireTLS`) and the compose file updated at the end.
8. **Rolling maintenance**: secondaries one at a time, `stepDown`, primary last, one command at a time.
