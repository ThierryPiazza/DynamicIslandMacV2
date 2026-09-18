import SwiftUI

/// Guida all'uso dell'app, mostrata in una finestra dedicata.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("L'app trasforma il notch del Mac in una Dynamic Island: passa il mouse o clicca sul notch per espanderla e accedere ai moduli. Trascina file sul notch per raccoglierli al volo.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                helpItem(icon: "music.note", title: "Now Playing",
                         text: "Legge titolo, artista e copertina dal Now Playing di macOS per i player che lo supportano. Nelle impostazioni puoi vedere lo stato della lettura generica. Se non è disponibile, usa gli osservatori Music/Spotify e i browser compatibili. Il browser richiede i permessi di automazione e JavaScript da Apple Events: vengono rilevati audio/video e Media Session anche su siti non predefiniti. I controlli non disponibili restano disabilitati.")

                helpItem(icon: "tray.full", title: "Shelf",
                         text: "Una mensola per i file: trascinali sul notch, poi trascinali fuori dove ti servono. Con il tasto destro puoi rinominare il file originale, copiare il percorso, creare uno ZIP o salvare una copia PNG ridimensionata (512, 1024 o 1920 px di lato massimo). ZIP e immagini vengono aggiunti alla Shelf e salvati nella cartella di output; gli originali non vengono sovrascritti.")

                helpItem(icon: "doc.on.clipboard", title: "Clipboard",
                         text: "Cerca nei 30 contenuti recenti e copiali con un click. La stella salva un preferito sul Mac anche dopo il riavvio; il filtro a stella mostra solo i preferiti. Svuota recenti li conserva. Puoi salvare fino a 30 preferiti, entro 16 MB; i contenuti marcati sensibili dai password manager non vengono acquisiti.")

                helpItem(icon: "note.text", title: "Appunti",
                         text: "Crea note o checklist con +, cerca per titolo e contenuto e fissa le note importanti con la puntina. Ogni nota si salva automaticamente sul Mac; il vecchio blocco note viene conservato come prima nota. Il tasto destro nell’elenco permette di eliminare una nota e Annulla eliminazione la ripristina. La freccia torna all’elenco, Fine chiude la Island.")

                helpItem(icon: "checklist.checked", title: "Checklist su iPhone",
                         text: "Quando aggiungi una voce, scegli la data di scadenza, un’ora facoltativa e l’anticipo della notifica (anche personalizzato). Senza ora, gli avvisi si calcolano dalle 09:00. Il pulsante calendario o campanella accanto alla voce permette di modificarli. Per ricevere gli avvisi, apri una checklist e premi l’icona Promemoria accanto al titolo. Consenti l’accesso e scegli iCloud: viene creata una lista Island con il nome della checklist. Testo, nuove voci e spunte si sincronizzano nei due sensi; rimuovere una voce la elimina anche dalla lista collegata. Su iPhone usa lo stesso Apple Account, attiva Promemoria in iCloud e aggiungi il widget Promemoria nella Home o nella schermata di blocco scegliendo la lista. Il widget di blocco ha spazio limitato; per vederlo senza riattivare lo schermo serve Always-On. Scollegare o eliminare l’intera nota conserva la lista in Promemoria. Se manca iCloud, abilitalo sul Mac e crea una lista in Promemoria, poi riprova.")

                helpItem(icon: "arrow.triangle.2.circlepath", title: "FileHub",
                         text: "Trascina un file sul notch per convertirlo in altri formati o rimuovere lo sfondo dalle immagini. I risultati vengono salvati nella cartella di output scelta nelle impostazioni.")

                helpItem(icon: "timer", title: "Timer e attività compatte",
                         text: "Avvia un timer da 5, 15 o 25 minuti, oppure scegli la durata. Pomodoro alterna lavoro di 25 minuti e pause di 5 minuti; ogni quattro sessioni la pausa dura 15 minuti. Alla fine di ogni fase senti un suono e vedi un avviso nella Island. Premi il pulsante per iniziare la fase successiva; pausa e ripresa conservano il tempo rimanente. La barra mostra il tempo trascorso, anche lungo il bordo del notch chiuso. A notch chiuso, i lati mostrano l’attività in corso: operazioni FileHub, file aggiunti alla shelf e timer. Clicca sull’attività per aprirla. Gli esiti compaiono per pochi secondi, poi torna l’attività precedente o la musica. Puoi disabilitarli nelle impostazioni.")

                helpItem(icon: "gearshape", title: "Personalizzazione",
                         text: "Dalle impostazioni puoi scegliere apertura, trasparenza, colore e scheda iniziale. In Ordine e visibilità delle schede usa le frecce per riordinarle e gli interruttori per nasconderle. I gesti seguono lo stesso ordine e saltano le schede nascoste. Una scheda deve rimanere visibile; le attività e il trascinamento possono comunque aprire direttamente il relativo modulo.")
            }
            .padding(20)
        }
        .frame(width: 380, height: 460)
    }

    private func helpItem(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
