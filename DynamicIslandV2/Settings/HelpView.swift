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
                         text: "Mostra il brano in riproduzione con copertina e controlli (play/pausa, traccia precedente/successiva). Funziona con Spotify, Apple Music e i browser.")

                helpItem(icon: "tray.full", title: "Shelf",
                         text: "Una mensola temporanea per i file: trascinali sul notch per parcheggiarli, poi trascinali fuori dove ti servono.")

                helpItem(icon: "doc.on.clipboard", title: "Clipboard",
                         text: "Cronologia degli appunti: ritrova testi e contenuti copiati di recente e riutilizzali con un click.")

                helpItem(icon: "calendar", title: "Calendario",
                         text: "Mostra i prossimi eventi del tuo calendario direttamente nel notch.")

                helpItem(icon: "cloud.sun", title: "Meteo",
                         text: "Condizioni meteo attuali per la tua posizione, oppure per una città fissa configurabile nelle impostazioni.")

                helpItem(icon: "arrow.triangle.2.circlepath", title: "FileHub",
                         text: "Trascina un file sul notch per convertirlo in altri formati o rimuovere lo sfondo dalle immagini. I risultati vengono salvati nella cartella di output scelta nelle impostazioni.")

                helpItem(icon: "gearshape", title: "Personalizzazione",
                         text: "Dalle impostazioni puoi scegliere come aprire il notch (click, hover o mix), la trasparenza, il colore accento, la tab di default e quali moduli attivare.")
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
