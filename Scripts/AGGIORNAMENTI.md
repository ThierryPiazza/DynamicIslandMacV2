# Aggiornamenti gratuiti di Dynamic Island

L’app usa Sparkle 2.10.0 e le release pubbliche di
[ThierryPiazza/DynamicIslandMacV2](https://github.com/ThierryPiazza/DynamicIslandMacV2/releases).
Non servono un server, GitHub Pages o un abbonamento Apple Developer.

Il feed fisso è:
`https://github.com/ThierryPiazza/DynamicIslandMacV2/releases/latest/download/appcast.xml`.
Ogni release stabile deve quindi includere `appcast.xml`, oltre allo ZIP.
Non pubblicare altre release stabili senza il catalogo: interromperebbero i controlli.

## Per gli amici

Installa manualmente una prima copia con Sparkle (dalla versione 1.1, build 2).
Poi usa **Controlla aggiornamenti…** dal menu dell’app, oppure
**Impostazioni → Generali → Aggiornamenti**. Sparkle chiede il consenso ai controlli
automatici; il consenso può essere modificato nelle impostazioni. La firma
EdDSA verifica gli aggiornamenti, ma non sostituisce la notarizzazione Apple:
questa distribuzione resta firmata ad hoc e macOS può chiedere conferma o permessi.

## Preparare la prossima versione

Esegui dalla cartella del progetto, sul Mac che conserva la chiave di firma:

```sh
RELEASE_VERSION=1.2 RELEASE_BUILD=3 Scripts/package_free_release.sh
```

Incrementa sempre `RELEASE_BUILD` rispetto all’ultima versione pubblicata.
Gli override non modificano il progetto Xcode. In alternativa aggiorna
`MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` nelle due configurazioni del progetto.
Per aggiungere note visibili nella finestra di aggiornamento:

```sh
RELEASE_VERSION=1.2 RELEASE_BUILD=3 RELEASE_NOTES_FILE=/percorso/note.md Scripts/package_free_release.sh
```

Lo script compila per Intel e Apple Silicon, controlla firma e risorse del bundle,
crea lo ZIP, genera il catalogo e verifica la firma EdDSA usando la chiave pubblica
inclusa nell’app. Il risultato si trova in una nuova cartella `dist/Dynamic Island-…`.
I log e la `.app` restano locali. Il pacchetto include le modifiche locali presenti
al momento della compilazione; conserva la revisione dei sorgenti corrispondente.

## Pubblicare

Con [GitHub CLI](https://cli.github.com/) installata e `gh auth login` completato:

```sh
Scripts/publish_update.sh "dist/Dynamic Island-XXXXXX"
```

Lo script verifica il pacchetto e il numero di build, crea una bozza, carica tutti
i file e solo dopo rende pubblica la release come **Latest**. Una release già
pubblicata non viene sovrascritta; una bozza può essere ripresa. Il tag viene
creato da GitHub sul ramo predefinito: sincronizza prima i sorgenti se vuoi che
il tag identifichi esattamente la build distribuita.

Puoi anche pubblicare dal browser, senza installare GitHub CLI:

1. Apri **Releases → Create a new release** nel repository.
2. Usa il tag in `release.json`, per esempio `v1.1-build2`.
3. Carica **tutti e quattro** i file: `Dynamic-Island.zip`, `appcast.xml`,
   `SHA256.txt`, `LEGGIMI.txt`. Mantieni esattamente questi nomi.
4. Pubblica come release stabile **Latest**, dopo che tutti i caricamenti sono terminati.
5. Verifica che l’URL del feed sia raggiungibile e prova **Controlla aggiornamenti…**.

Non modificare lo ZIP dopo la firma: il catalogo ne contiene firma e dimensione.
Gli URL dei pacchetti includono il tag, così le vecchie versioni mantengono il
proprio download anche dopo la pubblicazione di una nuova release.

## Chiave di firma

La chiave privata è nel Portachiavi di questo Mac, nell’account Sparkle
`com.thierrypiazza.DynamicIslandV2`. Nel repository c’è soltanto la chiave pubblica,
in `Config/UpdaterInfo.plist`. Non esportare la chiave privata nel repository,
nelle release o nei log. Fanne un backup sicuro tramite gli strumenti di Sparkle
prima di cambiare Mac: senza questa chiave le copie già distribuite non potranno
verificare i tuoi nuovi aggiornamenti. Non rigenerarla a ogni release.

Riferimenti: [Sparkle](https://sparkle-project.org/documentation/) e
[pubblicazione](https://sparkle-project.org/documentation/publishing/).
