# Backlog — prossimo aggiornamento

Elenco di cose rimandate volontariamente durante il lavoro sulla v1.0, da
valutare per la prossima release.

## 1. Sync iCloud per i dati (mood/calendario) — ❌ NON SERVE PIÙ
Scelta la strada del backend vero (vedi punto 8) invece di iCloud — erano
due alternative per lo stesso problema, non serviva farle entrambe.

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

## 8. Login + backend vero, dati legati al profilo — 🟡 codice pronto, manca 1 step in Xcode
Backend Supabase creato (progetto "productivitycal", ref `nxcdjnmiulliwpwnbbsx`,
org Supabase esistente) con tabella `moods` (user_id, day, mood, updated_at)
e row-level-security per account. Lato codice:
- `endar/SupabaseSync.swift` (nuovo file): `MoodSyncService` — scambia il
  token nativo di Sign in with Apple/Google per una sessione Supabase vera,
  fa pull+merge (locale vince sui conflitti, riempie solo i buchi) al primo
  avvio dopo login, e push di ogni singolo giorno modificato in tempo reale.
  Tutto dentro `#if canImport(Supabase)`, quindi l'app compila e funziona
  anche prima di aggiungere il pacchetto (la sync resta solo inattiva).
- `MoodStore` (in `ContentView.swift`): aggiunto `onDayChanged` hook e
  `mergeRemote(_:)` per collegarsi alla sync senza che sappia che Supabase
  esiste.
- `endarApp.swift`: dopo login Apple/Google chiama `MoodSyncService.signIn`;
  al logout chiama `MoodSyncService.signOut`.
- **Manca solo**: in Xcode, File → Add Package Dependencies → incolla
  `https://github.com/supabase/supabase-swift` → aggiungi il prodotto
  "Supabase" al target "endar". ~2 minuti, poi build — a differenza del
  widget qui gli errori di compilazione (se ce ne sono) li vedi subito in
  Xcode, quindi è normale/atteso dover sistemare qualche dettaglio all'API
  al primo build.
- Non ancora fatto (rifinitura futura, non blocca): passare un `nonce` nello
  scambio Sign in with Apple → Supabase per protezione anti-replay più
  forte; oggi funziona ma senza quell'indurimento extra.
