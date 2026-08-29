# Backlog — prossimo aggiornamento

Elenco di cose rimandate volontariamente durante il lavoro sulla v1.0, da
valutare per la prossima release.

## 1. Sync iCloud per i dati (mood/calendario)
Oggi tutto è locale (`UserDefaults`/App Group) — se l'utente disinstalla
l'app o cambia iPhone perde tutta la cronologia, anche se ha fatto
"sign in". Idea: usare `NSUbiquitousKeyValueStore` (o CloudKit se serve
più capacità) per sincronizzare automaticamente tra i dispositivi
dell'utente collegati allo stesso iCloud — gratis, nessun backend da
gestire, indipendente da quale provider di login (Apple/Google) ha usato.
Non banale: va implementato e testato con cura prima di spedirlo.

## 2. Widget home screen (streak) — ✅ FATTO
Target "Productivity Widget" creato in Xcode, codice incollato, App Groups
configurato su entrambi i target, testato su device reale con successo.
Formato small (streak + stato) e medium (streak + mini-preview 7 giorni)
entrambi funzionanti; tap sul widget apre l'app sulla home via deep link
`productivitycal://log`.

## 3. Automazione wallpaper con meno step
Oggi il setup richiede ~12 passaggi manuali in Shortcuts (tutorial con
screenshot). Idea per ridurlo a 2-3 tap: generare un file `.shortcut`
precompilato che l'utente importa con un tap, con azione e trigger già
dentro — l'utente conferma solo alla fine invece di costruire tutto a
mano. iOS non permette di creare l'Automazione Personale in modo del
tutto invisibile (serve comunque un passaggio in Shortcuts la prima
volta), ma si può ridurre drasticamente il lavoro manuale.

## 4. Icona dell'app
L'icona attuale (freccia + scintilla) viene dal progetto originale
ricevuto a inizio sessione — probabilmente un placeholder, mai deciso
consapevolmente. Da valutare: tenerla così o sostituirla con un logo
vero prima del prossimo aggiornamento importante.

## 5. Verificare se Xcode Cloud basta da solo per le prossime submission
La prima pubblicazione ha richiesto un archivio manuale da Xcode
("Distribute App" → "App Store Connect") perché le build di Xcode Cloud
non erano selezionabili per la review — causa probabile: mancava la
"Test Information" (Beta App Review Information) su App Store Connect,
ora compilata. Da verificare al prossimo aggiornamento: pushare il
codice, lasciare che sia Xcode Cloud a creare la build, e provare se
stavolta è selezionabile senza archivio manuale. Se sì, per gli
aggiornamenti futuri basterà pushare — nessun lavoro manuale in Xcode.

## 6. Sistemare le animazioni di swipe (calendario + tab)
Entrambe percepite come macchinose, poco fluide:
- **Swipe mesi nel calendario**: si "bugga" e slida male — probabilmente il
  drag live (`dragOffset` + `swipeToMonth(delta:)`) ha timing/curve
  dell'animazione da rivedere, o casi limite dove il gesto in corso e lo
  stepper a frecce entrano in conflitto lasciando lo stato inconsistente.
- **Swipe tra tab** (home/calendar/set): stessa sensazione di
  macchinosità — la `DragGesture` sul `TabView` va rivista (soglie,
  velocità, easing) per renderla naturale come uno swipe nativo.
Da fare: riprovare da zero l'approccio (magari `TabView` con
`.tabViewStyle(.page)` nativo per le tab, e per il calendario valutare
`ScrollView` con paging invece di un `DragGesture` custom) invece di
continuare a patchare i gesture attuali.

## 7. Rilavorare le immagini della pagina App Store
Le screenshot attuali su App Store Connect sono da rifare/arricchire:
1. **Screenshot dell'app**: aggiornare con le schermate reali post-redesign
   (tutorial nuovo, calendario, home) invece delle prime caricate.
2. **Screenshot "vision"**: 1-2 immagini con un concetto/claim forte invece
   che solo UI nuda, es. "Tieni la tua vita sotto controllo" — da rifinire
   il copy esatto e lo stile grafico (testo overlay su mockup del telefono).
3. **Screenshot della notifica**: mostrare la notifica giornaliera (18:00)
   com'è realmente su schermo, per comunicare il reminder automatico.

## 8. Login + backend vero, dati legati al profilo
Oggi il login (Apple/Google) esiste ma i dati restano locali sul
dispositivo (vedi punto 1) — non c'è un vero account nel senso di "i miei
dati mi seguono ovunque faccio login". Da fare: backend con database
(es. Supabase/Firebase) dove ogni utente autenticato ha il proprio storico
mood salvato lato server, associato al suo account — non più legato al
singolo iPhone/App Group locale. Alternativa più leggera al punto 1
(iCloud): qui il vantaggio è che funziona anche se in futuro l'app girasse
su più piattaforme o l'utente cambiasse provider di login. Da valutare
insieme a quale via scegliere (iCloud-only vs backend proprio) prima di
implementare — sono due strade diverse, non serve farle entrambe.
