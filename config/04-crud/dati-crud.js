// Dati di esempio della guida 04 (caricare con: app_eval "$(cat ~/mongo-lab/04-crud/dati-crud.js)")
// Rilanciabile: svuota e ricarica clienti, prodotti e vendite. I valori sono pseudo-casuali ma sempre uguali,
// così i risultati coincidono con quelli riportati nella guida.
// vendite deve essere già distribuita (guida 04, Parte 2): per questo viene svuotata, non eliminata.

let seme = 2026;
function caso(n) { seme = (seme * 16807) % 2147483647; return seme % n; }
function euro(cent) { return NumberDecimal((cent / 100).toFixed(2)); }

// --- prodotti: _id leggibile, prezzo decimale esatto, tag e descrizione per la ricerca testuale ---
const catalogo = [
  ["P001", "Portatile 14 pollici", "Informatica", 89900, 12, ["portatile", "ufficio"], "Computer portatile leggero con schermo da 14 pollici, ideale per lavorare in viaggio"],
  ["P002", "Mouse senza fili", "Informatica", 2490, 140, ["accessori", "wireless"], "Mouse ergonomico senza fili con batteria ricaricabile"],
  ["P003", "Tastiera meccanica", "Informatica", 7990, 35, ["accessori", "gaming"], "Tastiera meccanica retroilluminata, silenziosa e resistente"],
  ["P004", "Monitor 27 pollici", "Informatica", 24900, 20, ["schermo", "ufficio"], "Monitor ad alta risoluzione da 27 pollici per lavoro e grafica"],
  ["P005", "Webcam HD", "Informatica", 4590, 60, ["accessori", "videochiamate"], "Webcam con microfono integrato per videochiamate e riunioni a distanza"],
  ["P006", "Disco SSD 1 TB", "Informatica", 8990, 45, ["archiviazione"], "Disco a stato solido veloce per archiviare foto, video e documenti"],
  ["P007", "Cuffie con microfono", "Informatica", 5990, 0, ["audio", "videochiamate"], "Cuffie leggere con microfono a cancellazione del rumore"],
  ["P008", "Router Wi-Fi", "Informatica", 11900, 18, ["rete", "wireless"], "Router wireless di ultima generazione per una casa sempre connessa"],
  ["P009", "Macchina del caffè", "Casa", 15900, 25, ["cucina", "caffè"], "Macchina per caffè espresso con montalatte per cappuccino cremoso"],
  ["P010", "Bollitore elettrico", "Casa", 2990, 80, ["cucina", "tè"], "Bollitore in acciaio per tè e tisane, si spegne da solo"],
  ["P011", "Lampada da scrivania", "Casa", 3490, 55, ["illuminazione", "ufficio"], "Lampada a luce calda regolabile, perfetta per leggere e studiare"],
  ["P012", "Aspirapolvere robot", "Casa", 29900, 7, ["pulizia", "smart"], "Robot aspirapolvere che pulisce la casa da solo e si ricarica"],
  ["P013", "Set di pentole", "Casa", 12900, 15, ["cucina"], "Set di pentole antiaderenti per cucinare ogni giorno"],
  ["P014", "Purificatore d'aria", "Casa", 18900, 0, ["smart", "salute"], "Purificatore d'aria silenzioso con filtro per allergie e polveri"],
  ["P015", "Il nome della rosa", "Libri", 1400, 90, ["romanzo", "giallo"], "Romanzo giallo ambientato in un'abbazia medievale"],
  ["P016", "I promessi sposi", "Libri", 1200, 120, ["romanzo", "classico"], "Il grande classico della letteratura italiana"],
  ["P017", "Imparare MongoDB", "Libri", 3900, 30, ["informatica", "database"], "Manuale pratico per imparare i database di documenti con MongoDB"],
  ["P018", "Cucina regionale", "Libri", 2500, 40, ["cucina", "ricette"], "Ricette tradizionali delle regioni italiane, dalla pasta ai dolci"],
  ["P019", "Guida alle Dolomiti", "Libri", 1900, 25, ["viaggi", "montagna"], "Sentieri, rifugi e percorsi in montagna nelle Dolomiti"],
  ["P020", "Atlante del cielo", "Libri", 2900, 10, ["scienza", "astronomia"], "Stelle, pianeti e costellazioni spiegati con mappe del cielo"],
  ["P021", "Scarpe da corsa", "Sport", 9900, 50, ["corsa", "abbigliamento"], "Scarpe leggere e ammortizzate per la corsa su strada"],
  ["P022", "Tappetino yoga", "Sport", 2490, 75, ["yoga", "palestra"], "Tappetino antiscivolo per yoga e allenamento a corpo libero"],
  ["P023", "Bicicletta da città", "Sport", 39900, 5, ["bici", "città"], "Bicicletta comoda per muoversi in città, con cestino e luci"],
  ["P024", "Zaino da trekking", "Sport", 6990, 30, ["montagna", "viaggi"], "Zaino capiente e impermeabile per escursioni in montagna"],
  ["P025", "Borraccia termica", "Sport", 1990, 200, ["montagna", "palestra"], "Borraccia in acciaio che mantiene l'acqua fresca per ore"],
  ["P026", "Racchetta da tennis", "Sport", 8900, 0, ["tennis"], "Racchetta leggera per giocatori principianti e intermedi"],
  ["P027", "Agenda 2027", "Ufficio", 1590, 150, ["carta", "organizzazione"], "Agenda settimanale con copertina rigida per organizzare il lavoro"],
  ["P028", "Penne gel (10 pezzi)", "Ufficio", 890, 300, ["carta", "scrittura"], "Confezione di penne a gel colorate per scrivere e sottolineare"],
  ["P029", "Sedia ergonomica", "Ufficio", 21900, 9, ["ufficio", "postura"], "Sedia da ufficio regolabile che sostiene la schiena durante il lavoro"],
  ["P030", "Stampante laser", "Ufficio", 17900, 14, ["stampa", "ufficio"], "Stampante laser veloce in bianco e nero per l'ufficio"]
];
db.prodotti.drop();
db.prodotti.insertMany(catalogo.map(p => ({
  _id: p[0], nome: p[1], categoria: p[2], prezzo: euro(p[3]), giacenza: p[4], tags: p[5], descrizione: p[6]
})));

// --- clienti: _id numerico, indirizzo annidato, array di interessi, alcuni campi presenti solo a volte ---
const nomi = ["Marco", "Giulia", "Luca", "Francesca", "Andrea", "Sara", "Matteo", "Chiara", "Paolo", "Elena"];
const cognomi = ["Rossi", "Bianchi", "Esposito", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno", "Gallo"];
const citta = [["Milano", "MI", "20121"], ["Roma", "RM", "00184"], ["Torino", "TO", "10121"], ["Napoli", "NA", "80133"],
               ["Bologna", "BO", "40121"], ["Firenze", "FI", "50122"], ["Venezia", "VE", "30121"], ["Bari", "BA", "70121"]];
const interessi = ["informatica", "cucina", "lettura", "sport", "viaggi", "montagna", "musica", "casa"];
const clienti = [];
for (let i = 1; i <= 50; i++) {
  const nome = nomi[caso(nomi.length)], cognome = cognomi[caso(cognomi.length)], c = citta[caso(citta.length)];
  const cliente = {
    _id: i,
    nome: nome,
    cognome: cognome,
    email: (nome + "." + cognome + i + "@esempio.it").toLowerCase(),
    tipo: caso(5) === 0 ? "azienda" : "privato",
    indirizzo: { citta: c[0], provincia: c[1], cap: c[2] },
    interessi: [...new Set([interessi[caso(8)], interessi[caso(8)], interessi[caso(8)]])],
    punti: caso(500),
    newsletter: caso(2) === 0,
    iscritto: new Date(Date.UTC(2024, caso(24), 1 + caso(28)))
  };
  if (caso(3) > 0) cliente.telefono = "+39 3" + (100000000 + caso(899999999));
  clienti.push(cliente);
}
db.clienti.drop();
db.clienti.insertMany(clienti);

// --- vendite: 5.000 documenti con righe come array e totale decimale ---
const stati = ["consegnata", "consegnata", "consegnata", "spedita", "in lavorazione", "annullata"];
const canali = ["web", "web", "negozio", "telefono"];
db.vendite.deleteMany({});
const inizio = Date.UTC(2026, 0, 1);
for (let b = 0; b < 5; b++) {
  const docs = [];
  for (let i = 0; i < 1000; i++) {
    const n = b * 1000 + i;
    const righe = [];
    let totale = 0;
    const quante = 1 + caso(3);
    for (let r = 0; r < quante; r++) {
      const p = catalogo[caso(catalogo.length)], qta = 1 + caso(3);
      righe.push({ prodottoId: p[0], qta: qta, prezzo: euro(p[3]) });
      totale += p[3] * qta;
    }
    docs.push({ clienteId: 1 + caso(50), data: new Date(inizio + n * 90 * 60000), stato: stati[caso(stati.length)],
                canale: canali[caso(canali.length)], righe: righe, totale: euro(totale) });
  }
  db.vendite.insertMany(docs);
}

print("prodotti:", db.prodotti.countDocuments(), "- clienti:", db.clienti.countDocuments(), "- vendite:", db.vendite.countDocuments());
