import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject private var settings = ModuleSettings.shared
  @ObservedObject private var media = SystemMediaProvider.shared

  @State private var selection: SettingsPage = .appearance

  private enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance = "Aspetto"
    case behavior = "Comportamento"
    case content = "Contenuti"
    case modules = "Schede e moduli"
    case screen = "Schermo"
    case files = "File e Shelf"
    case system = "Generali"
    var id: String { rawValue }
    var icon: String {
      switch self {
      case .appearance: "paintpalette"
      case .behavior: "cursorarrow.motionlines"
      case .content: "rectangle.topthird.inset.filled"
      case .modules: "square.grid.2x2"
      case .screen: "display"
      case .files: "folder"
      case .system: "gearshape"
      }
    }
    var subtitle: String {
      switch self {
      case .appearance: "Colori e dettagli, con anteprima immediata."
      case .behavior: "Scegli come aprire e animare l’Island."
      case .content: "Decidi cosa vedere quando l’Island è chiusa."
      case .modules: "Organizza le schede e le sorgenti multimediali."
      case .screen: "Scegli il display su cui mostrare l’Island."
      case .files: "Gestisci la Shelf e la destinazione dei file."
      case .system: "Avvio dell’app, scorciatoie e aggiornamenti."
      }
    }
  }

  /// Display attualmente collegati: (id, nome). Ricalcolato a ogni render.
  private var availableDisplays: [(id: Int, name: String)] {
    NSScreen.screens.compactMap { screen in
      guard
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? CGDirectDisplayID
      else { return nil }
      return (Int(id), screen.localizedName)
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Dynamic Island").font(.headline).padding(.horizontal, 12).padding(.vertical, 16)
        ForEach(SettingsPage.allCases) { page in
          Button {
            selection = page
          } label: {
            Label(page.rawValue, systemImage: page.icon)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12).padding(.vertical, 10)
              .background(
                selection == page ? Color.accentColor.opacity(0.15) : .clear,
                in: RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selection == page ? .isSelected : [])
        }
        Spacer()
      }
      .padding(12).frame(width: 200)
      .background(.quaternary.opacity(0.35))
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
          Text(selection.rawValue).font(.title2.weight(.semibold))
          Text(selection.subtitle).font(.callout).foregroundStyle(.secondary)
        }.padding(24)
        Form {
          switch selection {
          case .appearance: AppearanceSettingsView(settings: settings, section: 0)
          case .behavior: AppearanceSettingsView(settings: settings, section: 1)
          case .content: AppearanceSettingsView(settings: settings, section: 2)
          default: EmptyView()
          }

          // ── Schermo ──────────────────────────────────────────────────────
          if selection == .screen {
            Section("Schermo") {
              Picker("Mostra il notch su", selection: $settings.preferredDisplayID) {
                Text("Automatico").tag(0)
                ForEach(availableDisplays, id: \.id) { display in
                  Text(display.name).tag(display.id)
                }
                // Display scelto in passato ma ora scollegato: mantieni la voce
                // così la selezione non si azzera (riaggancia quando ricollegato).
                if settings.preferredDisplayID != 0,
                  !availableDisplays.contains(where: { $0.id == settings.preferredDisplayID })
                {
                  Text("Display scollegato").tag(settings.preferredDisplayID)
                }
              }
              Text(
                "Con \"Automatico\" il notch va sul display integrato; se il Mac è chiuso (clamshell) passa allo schermo principale."
              )
              .font(.system(size: 11))
              .foregroundColor(.secondary)
            }
          }

          // ── Vista ────────────────────────────────────────────────────────
          if selection == .content {
            Section("Vista") {
              Toggle("Mostra barra tab quando aperto", isOn: $settings.showTabBar)
              Toggle("Viste laterali nel notch compatto", isOn: $settings.compactSideViewsEnabled)
              Toggle("Attività nel notch compatto", isOn: $settings.compactActivitiesEnabled)

              Picker("Tab di default", selection: $settings.defaultTabIndex) {
                Text("Ultimo usato").tag(-1)
                ForEach(settings.visibleTabs, id: \.rawValue) { tab in
                  Text(tab.title).tag(tab.rawValue)
                }
              }
            }
          }

          if selection == .modules {
            Section("Ordine e visibilità delle schede") {
              ForEach(settings.orderedTabs, id: \.rawValue) { tab in
                HStack {
                  Toggle(
                    tab.title,
                    isOn: Binding(
                      get: { settings.visibleTabs.contains(tab) },
                      set: { settings.setTab(tab, visible: $0) }
                    )
                  )
                  .disabled(settings.visibleTabs.count == 1 && settings.visibleTabs.contains(tab))
                  Button {
                    settings.moveTab(tab, offset: -1)
                  } label: {
                    Image(systemName: "arrow.up")
                  }
                  .disabled(settings.orderedTabs.first == tab).help("Sposta prima")
                  Button {
                    settings.moveTab(tab, offset: 1)
                  } label: {
                    Image(systemName: "arrow.down")
                  }
                  .disabled(settings.orderedTabs.last == tab).help("Sposta dopo")
                }
              }
              Text(
                "I gesti seguono questo ordine e saltano le schede nascoste. Mantieni almeno una scheda visibile."
              )
              .font(.system(size: 11)).foregroundStyle(.secondary)
            }
          }

          // ── Moduli ───────────────────────────────────────────────────────
          if selection == .modules {
            Section("Moduli") {
              Toggle("Now Playing", isOn: $settings.nowPlayingEnabled)
              Toggle("Lettura generica della riproduzione", isOn: $settings.systemMediaEnabled)
                .disabled(!settings.nowPlayingEnabled)
              Text(media.status).font(.system(size: 11)).foregroundStyle(.secondary)
              Toggle("Rilevamento browser alternativo", isOn: $settings.browserObserverEnabled)

            }
          }

          // ── FileHub ──────────────────────────────────────────────────────
          if selection == .files {
            Section("File e Shelf") {
              Toggle(
                "Ricorda i file della Shelf al riavvio", isOn: $settings.shelfPersistenceEnabled)
              HStack(spacing: 8) {
                Text(settings.outputDirectory.path)
                  .font(.system(size: 11))
                  .foregroundColor(.secondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .frame(maxWidth: .infinity, alignment: .leading)

                Button("Cambia…") {
                  let panel = NSOpenPanel()
                  panel.canChooseFiles = false
                  panel.canChooseDirectories = true
                  panel.allowsMultipleSelection = false
                  panel.prompt = "Scegli"
                  panel.message = "Scegli la cartella dove salvare i file convertiti"
                  if panel.runModal() == .OK, let url = panel.url {
                    settings.outputDirectory = url
                  }
                }
                .fixedSize()
              }
              Button("Ripristina Desktop") {
                settings.outputDirectory = FileManager.default
                  .homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
              }
              .foregroundColor(.secondary)
              .font(.system(size: 11))
            }
          }

          // ── Sistema ──────────────────────────────────────────────────────
          if selection == .system {
            AppUpdateSettings()
            Section("Sistema") {
              Toggle("Avvia al login", isOn: $settings.launchAtLogin)
              Toggle("Scorciatoia globale ⌃⌥Spazio (apri/chiudi)", isOn: $settings.hotkeyEnabled)
            }
          }
        }
        .formStyle(.grouped)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 760, height: 660)
  }

}
