# Backlog — prossimo aggiornamento

Elenco di cose rimandate volontariamente durante il lavoro sulla v1.0, da
valutare per la prossima release.

## 1. Sync iCloud per i dati (mood/calendario) — ❌ NON SERVE PIÙ
Scelta la strada del backend vero (vedi punto 8) invece di iCloud — erano
due alternative per lo stesso problema, non serviva farle entrambe.

## 2. Widget home screen (streak) — ✅ FATTO (+ log interattivo)
Target "Productivity Widget" creato in Xcode, codice incollato, App Groups
configurato su entrambi i target, testato su device reale con successo.
Formato small (streak + stato) e medium (streak + mini-preview 7 giorni)
entrambi funzionanti; tap sul widget apre l'app sulla home via deep link
`productivitycal://log`.

**Aggiunta**: se il mood di oggi non è ancora segnato, al posto del testo
"tap to log today" il widget mostra 3 pallini colorati toccabili (lavoro /
personale / non produttivo) — toccandone uno il mood viene salvato subito,
senza aprire l'app (widget interattivo iOS 17+, via 3 `AppIntent` dedicati
in `WidgetExtensionSource.swift`: `LogWorkProductiveMoodIntent`,
`LogPersonallyProductiveMoodIntent`, `LogNotProductiveMoodIntent`).
**Va ricopiato il contenuto aggiornato del file nel target Xcode**
(`Productivity_Widget.swift`) per attivarlo, stesso procedimento fatto la
prima volta — non basta pushare il codice, va incollato di nuovo a mano.

## 3. Automazione wallpaper con meno step — ✅ FATTO
Da 12 step manuali a 8: aggiunto un primo step "importa la shortcut
pronta" che apre un link iCloud (la shortcut con le due azioni "generate
wallpaper" → "set wallpaper photo" già collegate e "lock screen" già
scelto, condivisa una volta da Shortcuts, non generata a mano — niente
formato binario indovinato). I vecchi step 6-11 (cercare e collegare le
azioni a mano) sono sostituiti da un solo step testuale: "aggiungi
l'azione 'Esegui Shortcut' e scegli quella importata". Il link vive in
`WallpaperSetupGuideContent.importShortcutURL` (`endar/ContentView.swift`).
Se in futuro cambia qualcosa nelle azioni sottostanti, va rifatta la
shortcut condivisa e aggiornato quel link.

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

**Aggiornamento**: creato un secondo workflow Xcode Cloud, **"TestFlight
Beta"**, agganciato esclusivamente al branch `productivitycal1.1` con
distribuzione "TestFlight Internal Testing Only". Da ora, pushare su
`productivitycal1.1` fa partire da solo una build di test **senza toccare
`main`** — `main` resta riservato al momento in cui si è pronti a
pubblicare davvero (quello è il workflow "Default", legato a `main`, che
resta com'era). Numerazione build: gestita in automatico da Xcode Cloud in
base ai build già esistenti su App Store Connect per l'app, quindi non
dovrebbe mai collidere con la 21 già in review — da verificare comunque al
primo build reale di questo nuovo workflow.

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
- **Login email + password**: aggiunta una sezione "or" sotto Apple/Google
  in `LoginView` con campi email/password e pulsanti sign in / sign up,
  collegati a `MoodSyncService.signInWithPassword`/`signUpWithPassword`.
  Utile sia per chi non vuole usare Apple/Google, sia per i reviewer Apple.
- **Account demo per App Store Review** (creato direttamente sul database
  Supabase, non serve fare altro): email `reviewer@productivitycal.app`,
  password `YouAreMyFavoriteReviewer!1`. Da mettere nel campo "Note per il
  revisore"/"Sign-In Information" di App Store Connect quando risottometti,
  così il reviewer può accedere senza un vero account Apple/Google. Non
  condividerla altrove.
- **Manca solo**: in Xcode, File → Add Package Dependencies → incolla
  `https://github.com/supabase/supabase-swift` → aggiungi il prodotto
  "Supabase" al target "endar". ~2 minuti, poi build — a differenza del
  widget qui gli errori di compilazione (se ce ne sono) li vedi subito in
  Xcode, quindi è normale/atteso dover sistemare qualche dettaglio all'API
  al primo build.
- Non ancora fatto (rifinitura futura, non blocca): passare un `nonce` nello
  scambio Sign in with Apple → Supabase per protezione anti-replay più
  forte; oggi funziona ma senza quell'indurimento extra.
