# Verifica Zen → DynamicIsland

## Risultati ottenuti in questa sessione (2026-11-17)

- Probe reale MediaRemote: Zen playing=true; titolo, durata, posizione presenti;
  immagine assente. Eseguito fuori sandbox sull'app già installata.
- Build Xcode Debug dell'app aggiornata: superata, firma disattivata per preview.
- `./Tests/run_zen_bridge_checks.sh`: superato. Controlla sintassi dei tre script
  e arbitraggio simulato, poi avvia **l'host Swift reale**, invia messaggi framed
  anche parziali e usa **ZenMediaProvider + NowPlayingInfo reali** per verificare
  zero, immagine, seek, pausa, ripresa, ×2, live senza durata/copertina, scadenza,
  duplicati vecchi e chiusura del collegamento.
- Installatore: provato solo con directory temporanee; nessuna registrazione
  nell'installazione dell'utente. Controlli browser preesistenti: 12 superati.
- **NON ESEGUITA**: prova di estensione dentro Zen e rendering della nuova app.
  Il controllo del computer ha negato accesso a Zen; l'utente ha scelto la consegna
  di file e procedura. I test precedenti non sostituiscono questa prova.

## Controlli per la release 1.7, build 8

- Build Release universale Intel/Apple Silicon: superata.
- Verifica firma ad hoc del bundle e firma EdDSA Sparkle, catalogo e archivio: superata.
- `bash Tests/run_productivity_checks.sh`: superato (note, promemoria, clipboard,
  schede, timer, file/conversioni, download, browser e identità artwork).
- Il runner dei test è stato aggiornato per includere `FileEditResult`; la fixture
  che nasconde tutte le schede usa ora gli ID di tutte le schede, compresa Stats.
- La prova end-to-end dentro Zen resta da eseguire come nella matrice seguente.

## Preparazione

Seguire [installazione del ponte](../Extensions/ZenTimeline/README.md).
Dal root del progetto, per l'osservatore (non stampa titolo o URL):

```sh
xcrun swiftc DynamicIslandV2/System/ZenMediaSnapshot.swift DynamicIslandV2/System/ZenMediaProvider.swift DynamicIslandV2/Modules/NowPlaying/NowPlayingInfo.swift DynamicIslandV2/Core/NSImage+Resize.swift Tests/observe_zen_bridge.swift -o /tmp/observe-zen-bridge
/tmp/observe-zen-bridge
```

Legge gli stessi dati e la stessa conversione dell'app per 180 s. `identityHash`
identifica il video solo in quella esecuzione. `sampleAge` deve restare vicino a
0–3 s. Questo log è un riscontro del provider; osservare anche l'app reale.

Per una prova ripetibile, con `ffmpeg` e Python 3 installati:

```sh
./Tests/ZenFixture/serve.sh
```

Aprire **in Zen** `http://127.0.0.1:8765`. Il server ascolta solo su loopback.
Genera due video locali senza audio di 30 s. La diretta usa `canvas.captureStream`,
quindi una sorgente media reale senza durata finita. Nel riquadro sotto il video
sono mostrati i valori del player per confrontarli con il log e la barra.

## Matrice da eseguire e registrare

| Passo | Riscontro nel provider e nell'app | Stato attuale |
| --- | --- | --- |
| Avvia A con un click, senza pausa/play aggiuntivo | Durata 30, posizione ≥0, rate 1, playing true; copertina A; barra parte entro ~3 s | Da eseguire |
| Seek a 8 s | Posizione torna a 8±1 e barra si riallinea, senza attendere pausa/play | Da eseguire |
| Pausa per 5 s, seek in pausa, poi Play | Posizione ferma, seek recepito anche in pausa, ripresa dal punto reale | Da eseguire |
| Velocità ×2 | rate 2, barra avanza di circa 2 s/s | Da eseguire |
| Porta Zen in secondo piano per 15 s | sampleAge resta basso; posizione e barra avanzano; nessun ritorno a zero | Da eseguire |
| Apri una seconda scheda della fixture; lascia A in pausa lì, poi riprendi la prima e passa all'app | La scheda in pausa non ruba il player; l'identità resta quella della prima | Da eseguire |
| Nella scheda attiva premi B | Cambia identità/titolo; vecchia copertina sparisce subito e resta placeholder | Da eseguire |
| Ripeti A→B→A rapidamente | Nessun download in ritardo mostra la copertina sbagliata; A torna con copertina | Da eseguire |
| Diretta locale | Durata null, timeline false, nessuna copertina ereditata, etichetta avanzamento non disponibile | Da eseguire |
| Chiudi la scheda proprietaria senza altri video playing | Stato vuoto entro ~3 s, nessuna scheda solo in pausa riemerge | Da eseguire |
| Chiudi Zen o interrompi l'host | Dati diretti rimossi entro 10–11 s; nessun vecchio snapshot Zen di sistema riemerge | Da eseguire |
| Disattiva Now Playing e riattiva | Nessun dato mentre è disattivato, stato fresco dopo riattivazione | Da eseguire |
| Ripeti su YouTube e su un video iframe cross-origin | Verificare comportamento reale del sito, copertina, cambio SPA, seek e background | Da eseguire |

Per confronto del solo percorso macOS, usando un'app compilata:

```sh
python3 Tests/probe_system_media.py 'dist/ZenBridge-preview/Dynamic Island.app'
```

Eseguire prima del play, durante, dopo seek, pausa/ripresa e cambio video; annotare
quali campi esistono. Questo probe non legge il ponte. Una sola lettura positiva
non dimostra continuità né sincronizzazione. Per completare la verifica registrare
versione Zen/macOS, pagina/video, log del provider e risultato visivo di ogni riga.
Non segnare “superato” sulla sola base della simulazione o del badge OK.
