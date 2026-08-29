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

## 2. Widget home screen (streak)
Preparato ma non collegato al progetto Xcode:
- `WidgetExtensionSource.swift` (nella root del repo) contiene già il
  codice completo del widget (streak + "today done/tap to log today"),
  pronto da incollare in un nuovo target.
- Lo storage condiviso via App Group (`group.com.productivitycal.productivitycal`)
  è già configurato lato app principale, con fallback automatico.
- Manca solo: creare il target "Widget Extension" in Xcode (File → New →
  Target), incollare il codice, e aggiungere la capability "App Groups"
  a entrambi i target. ~5 minuti in Xcode, va fatto da lì (non in modo
  sicuro via modifica diretta del `project.pbxproj`).

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
