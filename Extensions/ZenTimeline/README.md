# Zen macOS Timeline Fix 0.3.0 — DynamicIsland bridge

## Scelta del collegamento

DynamicIsland legge `SystemMediaProvider → MediaController → run.pl →
MediaRemoteAdapter.framework → MediaRemote` e converte i campi del dizionario
Now Playing (durata/posizione in microsecondi, timestamp, velocità, stato e dati
binari della copertina). Non legge direttamente `navigator.mediaSession`.
`NowPlayingObserver` ascolta notifiche Music/Spotify/Vox, non Zen.
`BrowserObserver` interroga via AppleScript Chromium/Safari: Zen non offre quel
fallback DOM. Ripetere `setPositionState` non garantisce che Gecko pubblichi ogni
campo nel dizionario di macOS.

Probe reale del 17 novembre 2026, sull'app installata e fuori sandbox: Zen attivo,
titolo presente, durata e posizione presenti, **copertina assente**. La precedente
lettura documentata nello stesso progetto mancava anche di durata/posizione.
Queste sono osservazioni puntuali: non certificano seek, cambi video o background.

La versione 0.3.0 sostituisce il reinvio Media Session con:

`HTMLVideoElement → content.js → background.js → Native Messaging → host Swift → snapshot atomico → ZenMediaProvider → NowPlayingMonitor → NowPlayingView`

Non cambia il playback e non riscrive i metadati del sito. Lo stato proviene dal
video reale; Media Session fornisce solo testo/immagine, con poster/OG/Twitter come
alternative. La durata non finita diventa assenza di timeline, mai una durata
inventata. I dati di immagini vengono ridimensionati a 320 px nel background e
trasferiti in base64: l'app non deve risolvere URL `blob:` o autenticarsi nel sito.
Immagini che richiedono cookie, URL blob/data, video in closed shadow DOM e siti
che impediscono l'iniezione non sono supportati in questa versione. In quei casi
rimane il placeholder. Ogni frame HTTP(S) ha il proprio content script.

Il background persistente richiede nuove misure ogni 2 s anche da schede nascoste;
gli eventi di play/pausa/seek/rate inviano subito. Un proprietario resta selezionato
finché esiste; una scheda inattiva in pausa e un autoplay nascosto non possono
sostituirlo. Un nuovo play nella scheda attiva può sostituirlo. Questo è un criterio
esplicito, non la pretesa di identificare sempre l'intenzione dell'utente quando
più video suonano simultaneamente. Una misura oltre 10 s scade anche se l'host
continua a ricevere duplicati. Dopo una sessione diretta, l'app non ripristina un
vecchio snapshot Zen di macOS alla disconnessione del ponte.

Cambio documento/elemento/URL/sorgente invalida l'identità del video e la copertina.
Una pagina SPA che conserva l'immagine precedente la lascia nascosta finché il
sito ne pubblica una diversa: può quindi apparire un placeholder anche quando due
video hanno legittimamente la stessa immagine. L'assenza non avvia ricerche iTunes.
Le risposte di download in ritardo non possono applicarsi al nuovo video.

## Installazione locale di prova

Richiede macOS 14.6+, Zen 128+, Xcode/Command Line Tools per compilare l'host.
Non è un rilascio firmato/notarizzato. L'XPI è sperimentale e non firmato: caricarlo
temporaneamente, senza disabilitare i controlli di firma del browser.

1. Dal root del progetto: `./Scripts/install_zen_bridge.sh`.
   Installa un binario standalone in
   `~/Library/Application Support/DynamicIsland/ZenBridge/zen-native-host` e il
   manifest in `~/Library/Application Support/Mozilla/NativeMessagingHosts/`.
   Il manifest autorizza solo `zen-macos-timeline-fix@local.invalid`. Zen su macOS
   usa il percorso Mozilla ereditato da Firefox; confermare la scoperta con il
   badge OK nell'add-on (non è ancora stata verificata su questa installazione).
2. In Zen aprire `about:debugging#/runtime/this-firefox` → “Carica componente
   aggiuntivo temporaneo” e scegliere `manifest.json` qui, oppure l'XPI preparato.
   Rimuovere la vecchia versione temporanea se Zen segnala un ID duplicato.
   Il nuovo permesso `nativeMessaging` serve per il collegamento locale;
   l'accesso HTTP(S) serve per video e immagini nelle pagine. Le schede private
   vengono escluse. Nessun dato viene inviato a servizi remoti dall'host.
3. Ricaricare le pagine video già aperte per attivare il nuovo content script.
4. Chiudere l'app installata e avviare la build di prova `Dynamic Island.app`
   contenuta in `dist/ZenBridge-preview/`. In Impostazioni lasciare attivi Now
   Playing e “Rilevamento browser alternativo”. Il ponte funziona anche con
   lettura di sistema disattivata. Con altra app attiva in MediaRemote, quella
   sorgente mantiene precedenza; con Zen viene usato il ponte diretto.
5. Il badge dell'estensione deve mostrare `OK`: significa che l'host ha risposto,
   non che esista un video valido. `!` indica host non trovato/connessione fallita;
   il tooltip contiene l'errore. Controllare percorsi, eseguibilità e ID esatto.

Questa versione è un ponte dati: i pulsanti play/pausa/skip dell'app sono disabilitati
per la sorgente diretta. Il vecchio comando MediaRemote non garantisce di colpire
la stessa scheda selezionata. Usare i controlli di Zen per la prova. Un futuro
canale comandi dovrà includere identità documento/frame/video e conferma del
player, anziché indirizzare genericamente il browser.

L'host non richiede Python, server HTTP o porte aperte. Salva l'ultimo stato
(titolo, URL pagina, tempi e immagine) in un file privato, non uno storico.
Un lock ammette un solo profilo Zen collegato alla volta. Alla chiusura normale
invia uno stato vuoto; crash/SIGTERM vengono coperti dalla scadenza. Per disinstallare:
rimuovere l'add-on temporaneo, chiudere Zen, spostare nel Cestino il manifest
`com.thierrypiazza.dynamicisland.zen.json` e la cartella `DynamicIsland/ZenBridge`.

Specifiche: [Native Messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging),
[manifest nativi](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_manifests).
