# Revisione generale — settembre 2026

## Interventi

- Esportazioni: `OutputFile` centralizza scrittura temporanea, pubblicazione senza sovrascrittura, nomi progressivi e pulizia degli errori. Usato da conversioni, unione PDF, rimozione sfondo, ZIP e ridimensionamento.
- PDF: esportazione delle presentazioni da una copia privata; drenaggio dello stderr durante l’esecuzione, limite del buffer diagnostico e timeout del processo. Le conversioni Word restano su MainActor perché usano TextKit/NSPrintOperation.
- Immagini: conservazione dell’orientamento nelle conversioni; creazione degli oggetti Vision sulla coda che li usa; codifica PNG della rimozione sfondo fuori dal thread principale.
- Clipboard: miniature ImageIO a 160 px, limite di 16 MB per elemento e 64 MB complessivi per i recenti; i preferiti mantengono il proprio limite di 16 MB. Deduplicazione con aggiornamento della data. Elenco lazy e filtro calcolato una sola volta per render.
- Appunti: nessun salvataggio o sync per modifiche identiche; risultati remoti invariati non ripubblicano la collezione. Copia di recupero dei dati non decodificabili prima di consentire nuove modifiche. Elenco filtrato una volta per render.
- Promemoria: aggiornamenti EventKit e ritorno in primo piano, con controllo di recupero ogni cinque minuti anziché ogni minuto. Scadenze, allarmi e merge restano coperti dai test.
- Animazioni: marquee cancellabile con la view, ripartenza al cambio di testo/larghezza e rispetto di Riduci movimento. Pulizia delle callback hover/peek; stile pulsanti condiviso, stati disabilitati e target coerenti.
- Media: polling browser sospeso durante blocco/display spento; callback obsolete invalidate. Controlli accessibili, font di misura coerenti nel marquee, URL artwork riconosciuti per host e query iTunes codificata con URLComponents.
- Finestre: geometria pubblicata al cambio display, hit testing limitato alla parte visibile, drag basato sul display effettivo dell’Island. Monitor e sottoscrizioni rilasciati al termine del ciclo di vita.
- Shelf: accessi security-scoped bilanciati dopo il drag, cleanup dei monitor anche su mouse-up locale/Esc, anteprime precedenti annullate o ignorate al cambio file. Risoluzione bookmark senza UI di sistema inattesa, fallback per percorsi ancora validi e messaggi per file mancanti.
- Impostazioni: scrittura dei soli valori cambiati; validazione di opacità, ritardo, modalità apertura e colore caricati. Registrazione hotkey ripulita anche in caso di errore.

## Verifica

`bash Tests/run_productivity_checks.sh` copre produttività, notifiche, timer,
organizzazione file, conversioni reali di immagini/PDF, collisioni, cleanup,
limiti clipboard, recupero note, parser browser e riconoscimento dei servizi artwork.
I test usano preferenze isolate e directory temporanee. Nessun promemoria personale
viene creato dai test.

Compilate Debug e Release con Xcode. Verificate anteprime native isolate di elenco
Appunti e creazione Promemoria, incluse le dimensioni compatte.

Da verificare su dispositivi reali: consegna delle notifiche iCloud all’iPhone,
comportamento con più display fisici, export attraverso Keynote/PowerPoint/LibreOffice
e drag verso applicazioni esterne. Non sono state misurate percentuali di miglioramento
CPU/RAM con Instruments; le ottimizzazioni descritte sono verificabili nel codice.
