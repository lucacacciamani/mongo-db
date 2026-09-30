# Legenda dei comandi

Questa legenda spiega **tutti i comandi e i simboli** usati nelle guide del progetto: cosa fanno, cosa significano le opzioni che usiamo, e un esempio preso dalle guide. Non serve leggerla tutta: tienila aperta accanto alla guida e consultala quando incontri qualcosa che non conosci.

La colonna **Guide** indica dove compare il comando: `00` installazione, `01` TLS, `02` replica set, `03` sharding. Tutti i comandi elencati sono stati usati durante il collaudo delle guide.

---

## Indice

1. [Come si legge un comando](#1-come-si-legge-un-comando)
2. [I simboli della shell](#2-i-simboli-della-shell)
3. [Variabili, funzioni e piccoli script](#3-variabili-funzioni-e-piccoli-script)
4. [Privilegi di amministratore](#4-privilegi-di-amministratore)
5. [File e cartelle](#5-file-e-cartelle)
6. [Permessi e proprietari](#6-permessi-e-proprietari)
7. [Lavorare con il testo](#7-lavorare-con-il-testo)
8. [Sistema, rete e risorse](#8-sistema-rete-e-risorse)
9. [Pacchetti e aggiornamenti](#9-pacchetti-e-aggiornamenti)
10. [Servizi, timer e log (systemd)](#10-servizi-timer-e-log-systemd)
11. [SSH e copia di file](#11-ssh-e-copia-di-file)
12. [Certificati e crittografia (openssl)](#12-certificati-e-crittografia-openssl)
13. [Docker e Docker Compose](#13-docker-e-docker-compose)
14. [Strumenti di MongoDB](#14-strumenti-di-mongodb)
15. [PowerShell sul PC Windows](#15-powershell-sul-pc-windows)
15. bis [Elementi delle guide che non sono comandi](#15-bis-elementi-delle-guide-che-non-sono-comandi)
16. [Comandi pericolosi](#16-comandi-pericolosi)

---

## 1. Come si legge un comando

Un comando è formato da tre parti: il **nome**, le **opzioni** e gli **argomenti**.

```
ls   -lh   /var/backups/mongodb
│    │     └── argomento: su cosa agire
│    └── opzioni: come comportarsi
└── nome del comando
```

- **Opzioni corte**: un trattino e una lettera (`-l`, `-h`). Si possono unire: `-lh` equivale a `-l -h`.
- **Opzioni lunghe**: due trattini e una parola (`--quiet`, `--no-pager`). Alcune richiedono un valore: `--port 27101` oppure `--port=27101`.
- **Maiuscole e minuscole contano**: `-d` e `-D` sono opzioni diverse, `File.txt` e `file.txt` sono file diversi.
- **Percorsi**: `/home/utente/mongodb` è un percorso **assoluto** (parte dalla radice `/`); `tls/ca.pem` è **relativo** alla cartella in cui ti trovi.

| Simbolo nei percorsi | Significato |
|---|---|
| `~` | La tua cartella personale (es. `/home/azureuser`) |
| `.` | La cartella corrente |
| `..` | La cartella superiore |
| `/` | La radice del sistema, o il separatore tra cartelle |

**Per saperne di più su un comando:** `man nome` (manuale completo, esci con `q`) oppure `nome --help`.

---

## 2. I simboli della shell

La **shell** (bash) è il programma che interpreta ciò che scrivi nel terminale. Alcuni simboli non sono comandi, ma istruzioni per la shell.

### 2.1 Collegare comandi

| Simbolo | Significato | Esempio dalle guide |
|---|---|---|
| `\|` (pipe) | Passa l'output del comando a sinistra come input di quello a destra | `sudo docker compose logs mongo \| grep "Waiting"` |
| `&&` | Esegue il secondo comando **solo se il primo è riuscito** | `sudo docker compose config --quiet && echo "compose valido"` |
| `\|\|` | Esegue il secondo comando **solo se il primo è fallito** | `... -checkend ... && echo OK \|\| echo "IN SCADENZA"` |
| `;` | Esegue i comandi uno dopo l'altro, comunque vada | `sleep 15; rs_eval '...'` |
| `\` a fine riga | Il comando continua nella riga successiva | Comandi lunghi `docker exec ... \` |
| `&` a fine comando | Esegue il comando **in background** | Da evitare per errore: una stringa `mongodb://...&...` incollata in bash viene mandata in background |
| `{ ...; }` | Raggruppa più comandi, per esempio per unirne l'output | `{ sudo cat password.txt; sudo cat backup.gz; } \| ...` |

### 2.2 Redirezioni: dove va l'output

| Simbolo | Significato | Esempio |
|---|---|---|
| `>` | Scrive l'output in un file, **sovrascrivendolo** | `openssl rand -base64 756 > keyfile` |
| `>>` | Aggiunge l'output **in fondo** al file | `cat >> docker-compose.yml << EOF` |
| `< file` | Usa il file come input del comando | `openssl s_client ... </dev/null` |
| `2>/dev/null` | Butta via i messaggi di errore (`/dev/null` è un "cestino" che cancella tutto) | `docker inspect ... 2>/dev/null` |
| `2>&1` | Unisce i messaggi di errore all'output normale | `unattended-upgrade --dry-run --debug 2>&1 \| grep ...` |
| `>&2` | Scrive sul canale degli errori | `echo "ERRORE: ..." >&2` |
| `> /dev/null` | Butta via l'output normale | `sudo tee file > /dev/null` |

### 2.3 Here document: scrivere un file dal terminale

```bash
cat > nomefile << 'EOF'
contenuto del file
EOF
```

Tutto ciò che sta tra la prima riga e la riga `EOF` diventa l'input del comando. È il modo con cui le guide creano i file di configurazione. Mentre incolli, il terminale mostra `>` all'inizio di ogni riga: è normale.

| Forma | Differenza |
|---|---|
| `<< 'EOF'` (con apici) | Il contenuto viene scritto **esattamente com'è**: `$HOME` resta la scritta `$HOME` |
| `<< EOF` (senza apici) | Le variabili vengono **sostituite** con il loro valore: `$FQDN` diventa il nome vero |

**Errori tipici:** incollare solo una parte del blocco (il file non viene creato o resta incompleto); blocchi molto lunghi rovinati durante l'incolla (le guide li dividono in due parti, con `>` e poi `>>`).

### 2.4 Apici e caratteri speciali

| Simbolo | Significato |
|---|---|
| `'testo'` | Apici singoli: tutto è preso **alla lettera**, nessuna sostituzione |
| `"testo"` | Apici doppi: le variabili (`$VAR`) e i comandi (`$(...)`) vengono sostituiti |
| `$(comando)` | Viene sostituito dall'output del comando: `"$(sudo cat root_password.txt)"` |
| `*` | Carattere jolly: "qualunque cosa" (`mongo-*.archive.gz`). Viene espanso dalla shell **prima** di eseguire il comando, con i permessi del tuo utente: per questo su cartelle riservate a root serve `sudo sh -c '...'` |
| `#` | Commento: la shell ignora il resto della riga |
| `{a,b}` | Espande in più parole: `mongo-rs-backup.{service,timer}` = i due file |

### 2.5 Tasti utili

| Tasto | Effetto |
|---|---|
| **Ctrl+C** | Interrompe il comando in corso |
| **Ctrl+D** | Esce da una shell (anche da `mongosh`) |
| **Freccia su/giù** | Scorre i comandi precedenti |
| **Tab** | Completa nomi di comandi, file e cartelle |
| **Ctrl+Shift+V** | Incolla (nei terminali Linux); in PowerShell tasto destro o Ctrl+V |

---

## 3. Variabili, funzioni e piccoli script

| Elemento | Significato | Esempio |
|---|---|---|
| `NOME=valore` | Crea una variabile (senza spazi intorno a `=`). Vive **solo nella sessione corrente** | `FQDN=nome.regione.cloudapp.azure.com` |
| `$NOME` | Usa il valore della variabile | `echo "Nome DNS: $FQDN"` |
| `${2:-1}` | Il secondo argomento, oppure `1` se manca | Nella funzione `rs_eval` |
| `$(( ... ))` | Calcolo aritmetico | `$((KEEP_WEEKLY * 7 - 1))` |
| `$?` | Esito dell'ultimo comando (`0` = riuscito) | `status=$?` negli script di backup |
| `nome() { ...; }` | Definisce una **funzione**, un comando personalizzato. Vive solo nella sessione | `rs_eval() { ... }` |
| `local` | Variabile valida solo dentro la funzione | `local node=${2:-1}` |
| `for x in a b c; do ...; done` | Ripete i comandi per ogni valore | `for n in 1 2 3; do rs_eval '...' $n; done` |
| `if ...; then ...; fi` | Esegue i comandi solo se la condizione è vera | Scelta del nodo acceso nello script di backup |
| `[ condizione ]` | Verifica una condizione (file esiste, testi uguali…) | `[ -f /etc/mongo/tls/ca.pem ]` = "il file esiste" |
| `case ... in ... esac` | Sceglie in base a un valore | Controllo dei segnaposto nello script di backup |
| `break` | Esce da un ciclo | Nello script di backup |
| `read -r VAR` | Legge una riga dall'input e la mette in una variabile | Lettura della password dallo standard input |
| `exit N` | Termina lo script con esito `N` | `exit $status` |
| `sh -c '...'` | Esegue una riga di comandi in una nuova shell | `sudo sh -c 'rm -f /var/backups/.../*.gz'`, e dentro i container |
| `source file` | Esegue un file **nella sessione corrente**: le funzioni e le variabili che definisce restano disponibili | `source funzioni-lab.sh` (03) |
| `~/.bashrc` | File che bash esegue all'apertura di ogni sessione: una riga `source ...` aggiunta qui carica le funzioni a ogni accesso | `echo 'source ...' >> ~/.bashrc` (03) |
| `trap 'comandi' EXIT` | Esegue i comandi quando lo script termina, **anche per un errore** | Riattivazione del bilanciatore nello script di backup (03) |
| `set -- a b` | Assegna i valori ai parametri `$1`, `$2`… | `set -- $c` nei cicli sui nodi (03) |
| `export VAR` | Rende la variabile visibile ai programmi avviati dopo (qui: `mongosh` legge la password da `process.env`) | Script di backup (03) |

**Le prime righe degli script:**

| Riga | Significato |
|---|---|
| `#!/bin/bash` | Indica al sistema di eseguire il file con bash |
| `set -euo pipefail` | Ferma lo script **al primo errore** (`-e`), se si usa una variabile inesistente (`-u`) o se fallisce un comando in una pipe (`pipefail`). Negli script di backup evita che la pulizia cancelli i vecchi backup se quello nuovo non è riuscito |
| `umask 077` | I file creati da quel momento sono leggibili **solo dal proprietario** |

---

## 4. Privilegi di amministratore

| Comando | Cosa fa | Esempio | Guide |
|---|---|---|---|
| `sudo comando` | Esegue il comando come amministratore (root). Può chiedere la password del tuo utente | `sudo docker compose up -d` | 00 01 02 |
| `sudo tee file` | Scrive in un file riservato a root. Serve perché con `sudo echo ... > file` la redirezione `>` verrebbe eseguita dal tuo utente, non da root | `... \| sudo tee mongo_root_password.txt > /dev/null` | 00 01 02 |
| `sudo tee -a file` | Come sopra, ma **aggiunge** in fondo | Seconda parte dello script di backup (02) | 02 |
| `sudo sh -c '...'` | Esegue un'intera riga come root, compresi i caratteri jolly `*` | `sudo sh -c 'chmod 600 /var/backups/mongodb/*.archive.gz'` | 00 01 02 |
| `sudo usermod -aG docker $USER` | Aggiunge il tuo utente al gruppo `docker` (sconsigliato: equivale a pieni poteri) | Citato nella guida 00 | 00 |

---

## 5. File e cartelle

| Comando | Cosa fa | Opzioni usate | Esempio | Guide |
|---|---|---|---|---|
| `pwd` | Mostra la cartella corrente | | Controllo prima di `down -v` | 02 |
| `cd` | Cambia cartella | `cd ~` torna alla cartella personale | `cd ~/mongo-lab/02-replica-set` | 00 01 02 |
| `ls` | Elenca file e cartelle | `-l` dettagli (permessi, proprietario, dimensione); `-a` anche i file nascosti; `-h` dimensioni leggibili (K, M); `-d` la cartella stessa invece del contenuto; `-t` ordina per data; `-R` anche le sottocartelle | `ls -la ~/mongodb/tls` | 00 01 02 |
| `mkdir` | Crea una cartella | `-p` crea anche le cartelle intermedie e non dà errore se esiste già | `mkdir -p ~/mongodb/tls` | 00 01 02 |
| `rmdir` | Elimina una cartella **solo se vuota** | | Rimozione della cartella creata per errore | 01 |
| `cp` | Copia un file | | `cp docker-compose.yml docker-compose.yml.pre-tls` | 01 02 |
| `mv` | Sposta o rinomina | | `mv "$FILE.tmp" "$FILE"` | 00 01 02 |
| `rm` | Elimina file | `-f` senza chiedere conferma e senza errore se non esiste | `rm -f /tmp/rs-backup.archive.gz` | 00 01 02 |
| `ln` | Crea un collegamento | Senza opzioni: *hard link* (lo stesso file visibile da due posizioni, nessuno spazio in più); `-f` sostituisce se esiste | `ln -f "$FILE" "$DEST/weekly/"` | 00 01 02 |
| `cat` | Mostra il contenuto di un file (o lo passa a un altro comando) | | `sudo cat root_password.txt` | 00 01 02 |
| `tee` | Scrive in un file ciò che riceve dalla pipe (e lo mostra anche a schermo); `-a` aggiunge in fondo invece di sovrascrivere. Con `sudo` scrive in file riservati a root; `> /dev/null` evita di mostrare il contenuto | | `... \| sudo tee /etc/tmpfiles.d/mongodb-thp.conf > /dev/null` | 00 01 02 03 |
| `head` | Mostra le prime righe | `-N` le prime N righe | `sudo head -3 /usr/local/bin/mongo-backup.sh` | 00 01 02 |
| `wc -l` | Conta le righe | | `docker compose config --services \| wc -l` | 03 |
| `tail` | Mostra le ultime righe | `-N` le ultime N righe | `... \| tail -1` | 02 |
| `nano` | Editor di testo nel terminale | **Ctrl+O** salva, **Ctrl+X** esce | `nano docker-compose.yml` | 00 |
| `du` | Spazio occupato | `-s` totale; `-h` leggibile | `sudo du -sh /var/backups/mongodb` | 00 01 02 |
| `df` | Spazio libero sui dischi | `-h` leggibile | `df -h /` | 00 02 |
| `find` | Cerca file | `-name` per nome; `-mtime +N` modificati più di N giorni fa; `-delete` li elimina | Pulizia dei backup vecchi | 00 01 02 |
| `install -m 0755 -d` | Crea una cartella con permessi precisi | | `sudo install -m 0755 -d /etc/apt/keyrings` | 00 |
| `shred -u` | Sovrascrive un file e poi lo cancella, così non è recuperabile | | `shred -u ~/mongodb/tls/ca.key` | 01 |
| `sha256sum` | Calcola l'impronta di un file, per verificare che due copie siano identiche | | `sha256sum ~/mongodb/tls/ca.key` | 01 |

---

## 6. Permessi e proprietari

Ogni file ha un **proprietario**, un **gruppo** e dei **permessi**. In `ls -l` compaiono così:

```
-rw-------  1  999  systemd-journal  3274  server.pem
│└┬┘└┬┘└┬┘     │    │
│ │  │  │      │    └── gruppo
│ │  │  │      └── proprietario (qui il numero 999: l'utente di MongoDB nei container)
│ │  │  └── permessi degli altri utenti
│ │  └── permessi del gruppo
│ └── permessi del proprietario
└── tipo: - file, d cartella
```

`r` = lettura, `w` = scrittura, `x` = esecuzione (per una cartella: poterci entrare).

**I permessi in numeri**, come li usano le guide: ogni cifra è la somma di `r=4`, `w=2`, `x=1`, nell'ordine proprietario / gruppo / altri.

| Numero | Lettere | Usato per |
|---|---|---|
| `400` | `r--------` | keyFile del replica set (solo lettura, solo proprietario: obbligatorio per MongoDB) |
| `600` | `rw-------` | Password, chiavi private, `server.pem`, backup |
| `644` | `rw-r--r--` | Certificati pubblici (`ca.pem`, `server.crt`) |
| `700` | `rwx------` | Cartelle riservate (`tls`, backup) e script eseguibili solo da root |
| `755` | `rwxr-xr-x` | Cartelle e programmi accessibili a tutti |

| Comando | Cosa fa | Esempio | Guide |
|---|---|---|---|
| `chmod` | Cambia i permessi | `chmod 600 ca.key`; `chmod a+r file` (lettura per tutti); `chmod +x script.sh` (eseguibile) | 00 01 02 |
| `chown` | Cambia proprietario e gruppo | `sudo chown 999:999 server.pem` | 00 01 02 |
| `umask` | Permessi predefiniti dei file nuovi | `umask 077` → solo il proprietario | 00 01 02 |

> **Perché 999?** È il numero dell'utente `mongodb` dentro i container dell'immagine ufficiale. Sulla VM quel numero corrisponde per coincidenza al gruppo `systemd-journal`: per questo compare accanto ai file, ed è innocuo.

---

## 7. Lavorare con il testo

| Comando | Cosa fa | Opzioni usate | Esempio | Guide |
|---|---|---|---|---|
| `echo` | Stampa un testo | | `echo "Nome DNS: $FQDN"` | 00 01 02 |
| `printf` | Stampa un testo con un formato (`%s` = "inserisci qui un valore") | | `printf "password: %s\n" "$PWD"` | 00 01 02 |
| `grep` | Cerca righe che contengono un testo | `-n` numero di riga; `-c` conta le righe; `-A N` mostra anche le N righe dopo; `-E` espressioni estese (`A\|B` = A oppure B); `-i` ignora maiuscole; `-o` mostra solo la parte trovata; `-q` silenzioso (serve solo l'esito) | `grep -c "requireTLS" docker-compose.yml` | 00 01 02 |
| `sed -i` | Modifica un file sostituendo testo | `s\|vecchio\|nuovo\|` sostituisce; `&` nel nuovo testo = il testo trovato; `\n` = a capo; `-i` modifica il file direttamente | Aggiunta di `stop_grace_period`, delle opzioni TLS | 00 02 |
| `tr -d` | Elimina caratteri | | `tr -d '/+='` toglie dalla password i caratteri problematici | 00 02 |
| `cut` | Estrae una parte di ogni riga | `-d/` separatore `/`; `-f1` primo campo | `cut -d/ -f1` | 00 01 02 |
| `awk` | Estrae colonne | `'{print $4}'` = quarta colonna | `ip -4 -o addr show eth0 \| awk '{print $4}'` | 00 01 02 |
| `history` | Cronologia dei comandi | `-d N` elimina la riga N | Rimozione di una stringa con password | 02 |

---

## 8. Sistema, rete e risorse

| Comando | Cosa fa | Esempio | Guide |
|---|---|---|---|
| `free -h` | Memoria RAM e swap | Controllo prima del laboratorio | 02 |
| `nproc` | Numero di CPU | | 02 |
| `date` | Data e ora; con `+formato` in un formato preciso | `date +%Y%m%d-%H%M%S` (nome dei backup); `date +%u` (giorno della settimana, 7 = domenica); `date +%d` (giorno del mese) | 00 01 02 |
| `sleep N` | Aspetta N secondi | `sleep 15` | 02 |
| `reboot` | Riavvia la macchina | `sudo reboot` | 00 |
| `exit` | Esce dalla sessione (o da `mongosh`) | | 00 01 02 |
| `ip -4 -o addr show eth0` | Indirizzo IPv4 della scheda di rete | Ricerca dell'IP privato | 00 01 02 |
| `ss -ltnp` | Porte in ascolto (`-l` in ascolto, `-t` TCP, `-n` numeri, `-p` programma) | `sudo ss -ltnp \| grep 27017` | 00 02 |
| `curl` | Scarica un indirizzo web | `-f` errore se fallisce; `-s` silenzioso; `-S` mostra gli errori; `-L` segue i reindirizzamenti; `-o` salva in un file | 00 01 |
| `grep -o avx /proc/cpuinfo` | Verifica il supporto AVX della CPU | | 00 |
| `fallocate -l 4G /swapfile` | Crea un file della dimensione indicata, riservando lo spazio | Creazione dello swap | 03 |
| `mkswap file` | Prepara un file (o una partizione) come area di swap | | 03 |
| `swapon file` / `swapon --show` | Attiva lo swap / mostra quello attivo. Serve `sudo` anche solo per consultarlo: sta in `/usr/sbin`, fuori dal percorso degli utenti normali (altrimenti `command not found`) | `sudo swapon --show` | 03 |
| `swapoff file` | Disattiva lo swap | Rimozione dello swap | 03 |
| `cat /sys/kernel/mm/transparent_hugepage/enabled` | Impostazione THP attiva (quella tra `[ ]`) | | 00 |

---

## 9. Pacchetti e aggiornamenti

| Comando | Cosa fa | Guide |
|---|---|---|
| `apt-get update` | Aggiorna l'elenco dei programmi disponibili (non installa nulla) | 00 |
| `apt-get install -y pacchetto` | Installa (`-y` = risponde sì alle domande) | 00 |
| `apt-get remove -y pacchetto` | Rimuove | 00 |
| `dpkg --print-architecture` | Architettura della macchina (`amd64`, `arm64`) | 00 |
| `dpkg-reconfigure -plow unattended-upgrades` | Configurazione guidata degli aggiornamenti automatici | 00 |
| `unattended-upgrade -v` / `--dry-run --debug` | Installa ora gli aggiornamenti di sicurezza / simula senza installare | 00 |

---

## 10. Servizi, timer e log (systemd)

**systemd** è il sistema che avvia e gestisce i servizi di Debian. Un **servizio** (`.service`) dice *cosa* eseguire; un **timer** (`.timer`) dice *quando*.

| Comando | Cosa fa | Guide |
|---|---|---|
| `systemctl enable --now X` | Attiva X all'avvio **e** lo avvia subito | 00 01 02 |
| `systemctl start X` | Avvia X ora (per un servizio di backup: esegue un backup) | 00 01 02 |
| `systemctl disable --now X` | Disattiva X e lo ferma | 02 |
| `systemctl daemon-reload` | Rilegge i file dei servizi dopo averli creati o modificati | 00 01 02 |
| `systemctl reload ssh` | Rilegge la configurazione di SSH senza interrompere le sessioni | 00 |
| `systemctl is-enabled docker` | Dice se un servizio parte all'avvio | 00 |
| `systemctl list-timers 'mongo*'` | Elenca i timer con la prossima e l'ultima esecuzione | 00 02 |
| `journalctl -u X -n 5 --no-pager` | Ultime 5 righe di log del servizio X, senza impaginazione | 00 01 02 |
| `journalctl ... --since "2026-09-29 02:00"` | Log a partire da un momento preciso | 02 |
| `systemd-tmpfiles --create file` | Applica subito le impostazioni di un file in `/etc/tmpfiles.d` (usato per le THP) | 00 |

---

## 11. SSH e copia di file

| Comando | Cosa fa | Opzioni usate | Guide |
|---|---|---|---|
| `ssh utente@indirizzo` | Apre un terminale sulla VM | `-i chiave` file della chiave; `-v` mostra i dettagli (diagnosi) | 00 |
| `ssh -N -L 27017:127.0.0.1:27017 ...` | Tunnel: porta la porta 27017 della VM sul PC | `-N` nessuna shell, solo tunnel; `-L locale:destinazione:porta` | 00 |
| `scp origine destinazione` | Copia file via SSH; `utente@indirizzo:percorso` indica un file sulla VM | `-i chiave` come per `ssh` | 01 |
| `ssh-keygen -t ed25519` | Crea una coppia di chiavi SSH (privata + `.pub` pubblica) | | 00 |
| `sshd -T` | Mostra la configurazione effettiva del server SSH | | 00 |
| `sshd -t` | Controlla che la configurazione di SSH sia valida | | 00 |

**Direttive di configurazione di SSH** usate nella guida 00 (file in `/etc/ssh/sshd_config.d/`):

| Direttiva | Significato |
|---|---|
| `PubkeyAuthentication yes` | Accesso con chiave consentito |
| `PasswordAuthentication no` | Accesso con password vietato |
| `KbdInteractiveAuthentication no` | Vietate anche le password inserite in modo interattivo |
| `PermitRootLogin no` | Vietato l'accesso diretto come `root` |

---

## 12. Certificati e crittografia (openssl)

| Comando | Cosa fa | Guide |
|---|---|---|
| `openssl rand -base64 N` | Genera N byte casuali in testo (password, keyFile) | 00 01 02 |
| `openssl genrsa -out file.key 2048` | Crea una chiave privata RSA (2048 o 4096 bit) | 01 02 |
| `openssl req -x509 -new ...` | Crea un certificato autofirmato (qui: quello della CA) | 01 |
| `openssl req -new -key ... -subj "/CN=nome" -out file.csr` | Prepara una richiesta di certificato | 01 02 |
| `openssl x509 -req -in file.csr -CA ... -CAkey ...` | La CA firma la richiesta e produce il certificato; `-CAcreateserial` crea il contatore, `-CAserial` lo riusa; `-days` validità; `-extfile` impostazioni (SAN, usi) | 01 02 |
| `openssl verify -CAfile ca.pem server.crt` | Verifica che il certificato sia firmato da quella CA | 01 02 |
| `openssl x509 -in file.crt -noout -subject -enddate` | Mostra nome e scadenza | 01 |
| `openssl x509 ... -ext subjectAltName,extendedKeyUsage` | Mostra nomi validi (SAN) e usi consentiti | 01 02 |
| `openssl x509 ... -checkend SECONDI` | Riesce se il certificato è ancora valido tra N secondi | 01 |
| `openssl s_client -connect host:porta -CAfile ca.pem` | Si collega come client TLS e mostra il certificato del server; `Verify return code: 0 (ok)` = tutto a posto | 01 02 |

---

## 13. Docker e Docker Compose

**Immagine** = il modello scaricato (`mongo:8.0`); **container** = l'immagine in esecuzione; **volume** = dove i dati sopravvivono al container; **Compose** = file `docker-compose.yml` che descrive i container.

> ⚠️ I comandi `docker compose` agiscono sul progetto **della cartella corrente**.

### 13.1 Docker Compose

| Comando | Cosa fa | Guide |
|---|---|---|
| `docker compose up -d` | Crea e avvia i container in background; se il compose è cambiato, **ricrea** quelli interessati (i volumi restano) | 00 01 02 |
| `docker compose up -d servizio` | Ricrea solo quel servizio: la base della manutenzione a rotazione | 02 |
| `docker compose ps` | Stato dei container del progetto | 00 01 02 |
| `docker compose logs -f servizio` | Log in tempo reale (esci con Ctrl+C); `--tail N` solo le ultime N righe | 00 01 02 |
| `docker compose stop` / `start` / `restart` [servizio] | Ferma / avvia / riavvia | 00 02 |
| `docker compose config --quiet` | Controlla la sintassi del compose (nessun output = valido) | 00 01 02 |
| `docker compose config --services` / `--volumes` | Elenca servizi e volumi: verifica che il file sia completo | 02 |
| `docker compose pull` | Scarica la versione aggiornata delle immagini | 00 |
| `docker compose down` | Ferma e rimuove i container (i dati restano) | 00 02 |
| `docker compose down -v` | ⚠️ Come sopra **e cancella i volumi, cioè i dati** | 00 02 |

### 13.2 Docker

| Comando | Cosa fa | Guide |
|---|---|---|
| `docker run --rm hello-world` | Esegue un container di prova e lo elimina alla fine (`--rm`) | 00 |
| `docker exec -it container comando` | Esegue un comando dentro un container in esecuzione; `-i` input, `-t` terminale interattivo | 00 01 02 |
| `docker exec -i -e VAR=valore ...` | Come sopra, passando una variabile d'ambiente (`-e`); senza `-t` per poter ricevere dati da una pipe | 00 01 02 |
| `docker inspect container --format '{{...}}'` | Legge una proprietà del container (log, riavvio, stato) | 00 02 |
| `docker port container` | Porte pubblicate | 00 |
| `docker ps` | Container in esecuzione | 00 |
| `docker stats --no-stream` | Uso di CPU e memoria (una lettura sola) | 02 |

---

## 14. Strumenti di MongoDB

Non sono comandi Linux, ma compaiono in quasi tutti i blocchi. Si eseguono dentro i container con `docker exec`.

| Comando | Cosa fa | Opzioni usate |
|---|---|---|
| `mongosh` | Shell di MongoDB | `-u` utente; `-p` password (senza valore: la chiede); `--authenticationDatabase` dove è definito l'utente; `--port`; `--tls --tlsCAFile` connessione cifrata; `--eval 'js'` esegue un comando ed esce; `--quiet` meno messaggi; oppure una stringa `"mongodb://..."` |
| `mongodump` | Backup | `--archive` un unico file; `--gzip` compresso; `--oplog` copia coerente (replica set, non attraverso il router); `--config` file con la password; `--ssl --sslCAFile` TLS; `--db` un solo database; `--dumpDbUsersAndRoles` anche gli utenti del database |
| `mongorestore` | Ripristino | `--drop` sostituisce le collezioni; `--oplogReplay` riapplica l'oplog; `--nsFrom`/`--nsTo` ripristina con un altro nome; `--restoreDbUsersAndRoles` ripristina gli utenti; stesse opzioni di `mongodump` |
| `mongod --version` | Versione del server | |
| `mongos --configdb rs/host:porta,...` | Router di un cluster con sharding (03) | `--port`, `--keyFile`, opzioni TLS come `mongod` |

Dentro `mongosh`, i comandi usati nelle guide:

| Comando | Significato |
|---|---|
| `db.runCommand({ ping: 1 })` | Verifica che il server risponda |
| `db.getSiblingDB("nome")` | Passa a un altro database |
| `db.createUser(...)` / `db.changeUserPassword(...)` | Crea un utente / cambia la password |
| `db.collezione.insertOne(...)` / `find()` / `countDocuments()` / `drop()` | Inserisce / legge / conta / elimina la collezione |
| `rs.initiate(...)` / `rs.status()` / `rs.stepDown(N)` | Crea il replica set / stato dei membri / il primario cede il ruolo per N secondi |
| `db.hello()` | Informazioni sul ruolo del nodo (primario, membri) |
| `db.adminCommand({ getParameter / setParameter ... })` | Legge / cambia un parametro del server (es. `tlsMode`) |
| `db.serverStatus().transportSecurity` | Connessioni cifrate ricevute, per versione TLS |
| `sh.addShard("rs/host:porta,...")` | Registra uno shard nel cluster (03) |
| `sh.status()` / `db.adminCommand({ listShards: 1 })` | Stato del cluster / elenco degli shard (solo sul router) |
| `sh.enableSharding("db")` / `sh.shardCollection("db.coll", { campo: "hashed" o 1 })` | Abilita un database / distribuisce una collezione con la shard key indicata |
| `db.coll.getShardDistribution()` | Dati e documenti per shard (include gli orfani) |
| `.explain()` → `queryPlanner.winningPlan.stage` | `SINGLE_SHARD` (query mirata) o `SHARD_MERGE` (tutti gli shard) |
| `sh.stopBalancer()` / `sh.startBalancer()` / `sh.getBalancerState()` / `sh.isBalancerRunning()` | Ferma / riattiva / stato del bilanciatore |
| `config.chunks`, `config.changelog`, `config.rangeDeletions`, `config.settings` | Intervalli, storico delle migrazioni, cancellazioni degli orfani in attesa, impostazioni (`chunksize`) |
| `db.getMongo().setReadPref("secondary")` | Legge dai secondari |
| `exit` | Esce da `mongosh` |

---

## 15. PowerShell sul PC Windows

| Comando | Cosa fa | Guide |
|---|---|---|
| `ssh`, `scp`, `ssh-keygen` | Come su Linux: sono inclusi in Windows 10/11 | 00 01 |
| `mkdir cartella -Force` | Crea una cartella (`-Force`: nessun errore se esiste) | 01 |
| `dir cartella` | Elenca il contenuto | 01 |
| `Move-Item origine destinazione` | Sposta un file | 01 |
| `type file` | Mostra un file (qui: la chiave pubblica da inviare alla VM) | 00 |
| `$env:USERPROFILE` | La tua cartella utente (`C:\Users\<nome>`) | 00 |
| `Get-FileHash file -Algorithm SHA256` | Impronta di un file (da confrontare con `sha256sum`) | 01 |
| `Test-NetConnection host -Port N` | Verifica che una porta sia raggiungibile (`TcpTestSucceeded : True`) | 00 02 |
| `Resolve-DnsName nome` | Risolve un nome DNS | 02 |
| `27101..27103 \| ForEach-Object { ... $_ ... }` | Ripete un comando per ogni numero (`$_` = il valore corrente; abbreviato `%`) | 02 |
| `Select-Object colonne` | Mostra solo alcune colonne del risultato | 02 |
| `ping -n 1 nome` | Mostra a quale indirizzo si risolve un nome | — |
| `git status` / `git mv` / `git add --renormalize .` | Stato del repository / spostamento con cronologia / riapplica le regole di `.gitattributes` | — |

> **Percorsi Windows:** usano `\`. Nelle stringhe di connessione di MongoDB si scrivono con `/` (`C:/Users/...`), e gli spazi vanno codificati come `%20` o evitati.

---

## 15 bis. Elementi delle guide che non sono comandi

| Elemento | Significato |
|---|---|
| Blocchi ` ```mermaid ` | Diagrammi disegnati da GitHub (su altri visualizzatori compaiono come testo) |
| `<details>` / `<summary>` | Sezioni richiudibili, usate per gli output reali del collaudo |
| `<FQDN>`, `<IP_PRIVATO_VM>`, … | Segnaposto da sostituire, togliendo anche `<` e `>` |

---

## 16. Comandi pericolosi

Comandi che nelle guide compaiono con un avviso, e perché.

| Comando | Rischio | Precauzione |
|---|---|---|
| `docker compose down -v` | Cancella **tutti i dati** del progetto, senza conferma | `pwd` prima; mai nella cartella di un database con dati veri |
| `rm -f` con `*` | Cancella tutto ciò che corrisponde | Prima `ls` con lo stesso percorso |
| `shred -u` | Cancellazione irrecuperabile | Solo dopo aver verificato la copia (`sha256sum`) |
| `sed -i` | Modifica il file senza chiedere | Copia di sicurezza prima (`cp file file.bak`) |
| Configurazione di SSH | Puoi restare chiuso fuori dalla VM | Tieni aperta una sessione e prova da una seconda |
| `rs.stepDown` / `docker compose stop` sul primario | Elezione: breve pausa delle scritture | Un nodo alla volta, verificando lo stato |
| Stringhe `mongodb://utente:password@...` nel terminale | Password nella cronologia; il `&` manda il comando in background | Vanno nel client; `history -d` per rimuoverle |
