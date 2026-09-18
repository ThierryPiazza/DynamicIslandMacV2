# Funzioni di produttività

Eseguire i controlli con `bash Tests/run_productivity_checks.sh` dalla root del progetto.
I test usano preferenze isolate e file temporanei, senza leggere la clipboard reale o modificare gli appunti dell'utente.

Copertura:
- Migrazione del blocco note precedente; ricerca senza distinzione di accenti/maiuscole, note fissate, checklist persistenti ed eliminazione annullabile.
- Preferiti clipboard persistenti, deduplicazione, conservazione dei preferiti oltre il limite di cronologia e svuotamento dei soli recenti.
- Ripristino dell'ordine delle schede, rimozione di ID sconosciuti/duplicati, almeno una scheda visibile, fallback della scheda iniziale, swipe ciclico tra le schede visibili.
- Pomodoro: 25 minuti di lavoro, pause di 5 minuti, pausa di 15 minuti ogni quattro sessioni. L'utente avvia la fase successiva; non viene avviata automaticamente durante un'assenza.
- Rinomina senza sovrascritture o percorsi esterni, ZIP di file/cartelle con spazi e Unicode, nomi di output unici e prevenzione degli archivi ricorsivi. Ridimensionamento PNG proporzionale senza cambiare l'originale.
- Regressione timer: pausa, ripresa, risveglio, progressione e scadenza.

Verifiche UI sulla build:
1. Negli Appunti usare + per una nota o checklist; modificare titolo/testo, spuntare voci, tornare all'elenco, cercare e fissare una nota. Provare eliminazione e annullamento.
2. Nella Clipboard cercare, salvare con la stella e filtrare i preferiti; riavviare e verificare che rimangano. Lo svuotamento mantiene i preferiti.
3. Avviare un timer e un Pomodoro; controllare pausa/ripresa e, alla scadenza, suono, attività compatta e pulsante della fase successiva.
4. Nella Shelf aprire il menu con il tasto destro: rinomina, copia percorso, ZIP e ridimensionamento. I nuovi file usano la cartella di output delle impostazioni. La rinomina modifica l'originale; ZIP e PNG creano copie.
5. Nelle impostazioni riordinare e nascondere schede. I gesti devono rispettare l'ordine. Trascinamenti e attività compatte possono aprire direttamente un modulo nascosto.

Le anteprime di elenco note, clipboard, timer iniziale e Pomodoro sono state renderizzate e ispezionate a 344 × 108 pt (area contenuti minima). Le notifiche di fine timer sono un suono locale e un avviso nella Island, non notifiche del Centro notifiche. Le fasi del Pomodoro e la cronologia non preferita non vengono mantenute dopo l'uscita dall'app.

## Download → Documenti

- All’avvio viene fotografato il contenuto di Download: i file già presenti non vengono aggiunti alla Shelf.
- I nuovi file o quelli modificati vengono proposti dopo almeno quattro secondi senza cambiamenti. Le estensioni `.crdownload`, `.part`, `.download` e `.tmp` e i placeholder con un corrispondente file parziale sono esclusi. Il controllo riguarda la cartella Download, non lo stato interno del browser; un file scritto direttamente col nome finale può sembrare pronto durante una pausa prolungata.
- Nella Shelf, **Sposta** apre le cartelle reali di Documenti. Clic su una cartella per entrare, freccia per risalire, casa per tornare a Documenti, **Sposta qui** per confermare. **Nuova cartella** crea una sottocartella. Le cartelle nascoste, i pacchetti app e i link simbolici non sono mostrati.
- Durante la scelta della destinazione l’isola si estende di 180 punti verso il basso, tornando all’altezza normale alla chiusura. Dopo uno spostamento riuscito il file viene rimosso dalla Shelf. L’ultimo spostamento si annulla dalla Shelf, anche se vuota, ripristinando il file nella posizione originale e nella Shelf. Se la destinazione contiene già lo stesso nome, anche durante l’annullamento, l’operazione fallisce senza sovrascrivere.
- Il monitor si disattiva da Impostazioni → Moduli → Mostra i nuovi download nella Shelf. L’accesso a Download e Documenti è soggetto ai permessi macOS per File e cartelle. La Shelf conserva fino a 50 riferimenti; rimuovere un riferimento non elimina il file.
- `bash Tests/run_productivity_checks.sh` include `DownloadOrganizerChecks.swift`: navigazione, nomi invalidi, spostamento/annullamento, collisioni, baseline, file parziali, crescita e deduplicazione. I test operano esclusivamente in una cartella temporanea.
- Verifica manuale: avviare la nuova build, consentire l’accesso alle cartelle se richiesto, scaricare un file nella cartella Download, aprire la Shelf dall’avviso e spostarlo in una sottocartella di Documenti; quindi usare Annulla. Ripetere con un nome già presente nella destinazione.
