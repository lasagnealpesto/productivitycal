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

**Aggiunta — ✅ FATTO anche questa**: se il mood di oggi non è ancora
segnato, al posto del testo "tap to log today" il widget mostra 3 pallini
colorati toccabili (lavoro / personale / non produttivo) — toccandone uno
il mood viene salvato subito, senza aprire l'app (widget interattivo iOS
17+, via 3 `AppIntent` dedicati in `WidgetExtensionSource.swift`:
`LogWorkProductiveMoodIntent`, `LogPersonallyProductiveMoodIntent`,
`LogNotProductiveMoodIntent`). Contenuto ricopiato in
`Productivity_Widget.swift` e pushato su `productivitycal1.1` — da
verificare sul device/TestFlight che i pallini funzionino davvero.

## 3. Automazione wallpaper con meno step — ↩️ RIPRISTINATO ai 12 step originali
Avevo provato a ridurli a 8 con un primo step "importa la shortcut pronta"
(link iCloud) al posto dei vecchi step 6-11 manuali — su richiesta,
ripristinato il flusso originale a 12 screenshot passo-passo. Il codice
del link/step di import è stato rimosso da `ContentView.swift`. Se in
futuro si vuole ritentare la riduzione degli step, l'idea e il link
iCloud della shortcut restano validi, andrebbero solo re-implementati.

## 4. Icona dell'app — ✅ decisa e generata, manca solo il collegamento in Xcode
L'icona precedente (freccia + scintilla) era un placeholder ereditato dal
progetto originale, mai una scelta consapevole. Decisa la direzione "the
grid": una versione semplificata della griglia dell'anno (lo stesso
elemento visivo già presente sul wallpaper), la più riconoscibile e
distintiva tra le opzioni valutate. Asset generato a piena risoluzione
(1024x1024, PNG opaco, verificato leggibile anche a dimensioni piccole)
e già copiato nel repo in
`endar/Icon-test.icon/Assets/grid-icon-1024.png`.

Non ancora collegata: il progetto usa Icon Composer di Xcode 26 (il file
`Icon-test.icon`), che si aspetta un livello "template" ricolorabile, non
un'immagine piatta a colori fissi come questa. Va aperta in Xcode,
sostituito il livello immagine con questo file, e disattivata la
colorazione automatica in modo che mantenga i suoi colori reali in ogni
aspetto (chiaro/scuro/tinted). Operazione da 2 minuti nell'interfaccia di
Icon Composer, dove si vede subito il risultato prima di salvare.

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

## 6. Animazioni di swipe (calendario + tab) — ✅ RISOLTO rimuovendole del tutto
Dopo 3 tentativi diversi (drag custom con offset live, `TabView` nativo con
`.tabViewStyle(.page)` annidato, carousel hand-rolled con `HStack` +
`highPriorityGesture`) il calendario restava comunque buggato — annidare
due gesture orizzontali (tab + mesi) non è mai stato affidabile su iOS.
Su richiesta esplicita, rimossi tutti gli swipe/scroll custom:
- **Menù sotto**: tornato al `TabView(selection:)` di sistema con
  `.tabItem` (come all'inizio) — Liquid Glass automatico, nessun codice
  custom (`CustomTabBar` rimosso).
- **Calendario**: cambio mese solo tramite le frecce (`stepMonth(by:)`),
  griglia statica con un semplice cross-fade su `selectedMonth`/
  `selectedYear` — nessun `DragGesture`, nessun carousel.
Pushato su `productivitycal1.1`/`testing`, da confermare su
device/TestFlight che sia fluido e senza i bug precedenti.

## 7. Rilavorare le immagini della pagina App Store
Le screenshot attuali su App Store Connect sono da rifare/arricchire:
1. **Screenshot dell'app**: aggiornare con le schermate reali post-redesign
   (tutorial nuovo, calendario, home) invece delle prime caricate.
2. **Screenshot "vision"**: 1-2 immagini con un concetto/claim forte invece
   che solo UI nuda, es. "Tieni la tua vita sotto controllo", da rifinire
   il copy esatto e lo stile grafico (testo overlay su mockup del telefono).
3. **Screenshot della notifica**: mostrare la notifica giornaliera (19:30)
   com'è realmente su schermo, per comunicare il reminder automatico.

**Testi (non le immagini) — ✅ FATTO**: partendo dai campi reali già live
per la 1.0 (promotional text, descrizione, parole chiave, note per il
team di revisione), riscritti in tono brand e aggiornati per la 1.1 (la
frase "i dati non lasciano mai il telefono" non è più vera ora che
esiste la sync, sostituita con un claim di privacy corretto). Pacchetto
completo, con conteggio caratteri verificato contro i limiti reali di
Apple, consegnato come documento a parte (recap release 1.1).

## 8. Login + backend vero, dati legati al profilo — ✅ FATTO, da verificare su device
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
- Pacchetto `supabase-swift` aggiunto in Xcode, build locale riuscita
  ("Build Succeeded"), tutto pushato su `productivitycal1.1`. Resta da
  confermare sul device/TestFlight che login e sync funzionino davvero
  end-to-end (non solo che compili).
- Non ancora fatto (rifinitura futura, non blocca): passare un `nonce` nello
  scambio Sign in with Apple → Supabase per protezione anti-replay più
  forte; oggi funziona ma senza quell'indurimento extra.

## 9. Pulsante feedback in app → issue GitHub automatica — ✅ FATTO lato codice, manca un ultimo step manuale
In Set, sotto "share my year", nuovo pulsante "send feedback" che apre un
foglio con una casella di testo libera. Alla conferma, il testo viene
salvato nella tabella `feedback` di Supabase (RLS: solo utenti loggati
possono inserire, nessuno può leggere le righe altrui). Lato codice tutto
pronto e pushato su `productivitycal1.1`:
- `endar/SupabaseSync.swift`: `MoodSyncService.submitFeedback(message:appVersion:)`.
- `endar/ContentView.swift`: `FeedbackView` (foglio) + pulsante in `SetView`.
- Supabase: tabella `feedback` creata (migration `create_feedback_table`),
  Edge Function `feedback-to-issue` pubblicata — riceve l'insert e apre una
  issue su `lasagnealpesto/productivitycal` con label `feedback`, titolo
  preso dal testo e corpo con email/versione app/data.

**Manca un solo step, da fare tu una volta sola su supabase.com** (non
posso farlo io: serve un tuo token GitHub, non va condiviso in chat):
1. Su GitHub, crea un Personal Access Token (fine-grained, solo su questo
   repo, permesso "Issues: Read and write") — Settings → Developer
   settings → Personal access tokens.
2. Su supabase.com, progetto "productivitycal" → Edge Functions →
   `feedback-to-issue` → Secrets: aggiungi `GITHUB_TOKEN` con quel token.
3. Sempre su supabase.com → Database → Webhooks → "Create a new hook":
   tabella `feedback`, evento `INSERT`, tipo "Supabase Edge Functions",
   funzione `feedback-to-issue`, header `Authorization: Bearer
   <service_role key del progetto, da Project Settings → API>`.
Fatto questo, ogni feedback mandato dall'app diventa una issue GitHub in
automatico, senza altro lavoro manuale.

## 10. Cancellare il branch `testing` su GitHub — da fare tu
Deciso di tenere solo `productivitycal1.1` come branch di sviluppo/test
(agganciato al workflow Xcode Cloud "TestFlight Beta"); `testing` era un
duplicato rimasto da un tentativo di rinomina, ora inutile. Non riesco a
cancellarlo io: GitHub rifiuta il push di cancellazione con HTTP 403
(stessa protezione già vista sul branch dell'harness). Da fare tu una
volta sola: GitHub → repo → Branches → cestino su `testing` (oppure da
Xcode). Da parte mia continuo a pushare solo su `productivitycal1.1`.
