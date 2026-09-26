import SwiftUI

struct AppearanceSettingsView: View {
  @ObservedObject var settings: ModuleSettings
  let section: Int

  var body: some View {
    Section(section == 0 ? "Aspetto e colore" : section == 1 ? "Interazione" : "Island compatta") {
      if section != 1 { preview }
      if section == 0 {
        VStack(alignment: .leading, spacing: 12) {
          Text("Palette accento").font(.headline)
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(ModuleSettings.accentColors.indices, id: \.self) { index in
              Button {
                settings.customAccentRGB = []
                settings.accentColorIndex = index
              } label: {
                Circle().fill(ModuleSettings.accentColors[index])
                  .frame(width: 22, height: 22)
                  .overlay {
                    if settings.customAccentRGB.isEmpty && settings.accentColorIndex == index {
                      Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                    }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(ModuleSettings.accentColorNames[index])
              .accessibilityAddTraits(
                settings.customAccentRGB.isEmpty && settings.accentColorIndex == index
                  ? .isSelected : [])
            }
          }
        }
        ColorPicker(
          "Colore personalizzato",
          selection: Binding(
            get: { settings.accentColor },
            set: { settings.setCustomAccent($0) }
          ), supportsOpacity: false)
        HStack {
          Text("Opacità sfondo")
          Slider(value: $settings.notchOpacity, in: 0.3...1, step: 0.05)
            .accessibilityLabel("Opacità dello sfondo")
          Text("\(Int((settings.notchOpacity * 100).rounded()))%")
            .monospacedDigit().frame(width: 40)
        }
      } else if section == 1 {
        Picker("Apri l’Island", selection: $settings.openModeIndex) {
          Text("Con un clic").tag(0)
          Text("Al passaggio del mouse").tag(1)
          Text("Clic e passaggio del mouse").tag(2)
        }
        if settings.openOnHover {
          HStack {
            Text("Ritardo apertura")
            Slider(value: $settings.hoverDelay, in: 0.2...1, step: 0.1)
              .accessibilityLabel("Ritardo apertura")
            Text("\(Int((settings.hoverDelay * 1000).rounded())) ms").monospacedDigit()
          }
        }
        Toggle("Animazioni ridotte", isOn: $settings.reduceAnimations)
        Text(
          "Riduce le transizioni e ferma le barre musicali. L’opzione di accessibilità di macOS ha sempre precedenza."
        )
        .font(.caption).foregroundStyle(.secondary)
      } else {
        Picker("Quando è chiusa", selection: $settings.compactContent) {
          Text("Automatico").tag(0)
          Text("Prima la musica").tag(1)
          Text("Prima timer e attività").tag(2)
          Text("Solo Island").tag(3)
        }
        Toggle("Copertina laterale", isOn: $settings.compactArtwork)
          .disabled(!settings.showsCompactMusic)
        Toggle("Mostra titolo al cambio brano", isOn: $settings.compactTitle)
          .disabled(!settings.showsCompactMusic)
        Text(
          "Il titolo appare brevemente sotto il notch al cambio brano. Se il contenuto prioritario non è attivo, viene mostrato l’altro."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if section == 0 {
        Button("Ripristina aspetto") { settings.resetAppearance() }.font(.caption)
      }
    }
  }

  private var preview: some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        if settings.compactContent != 3 {
          if settings.compactArtwork {
            Image(systemName: settings.compactContent == 2 ? "timer" : "music.note")
              .frame(width: 28, height: 28)
              .background(settings.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
          }
          if settings.compactTitle || settings.compactContent == 2 {
            VStack(alignment: .leading, spacing: 3) {
              Text(settings.compactContent == 2 ? "Sessione di studio" : "Midnight City")
                .font(.system(size: 12, weight: .medium))
              Text(
                settings.compactContent == 2 ? "18:42 · Concentrazione" : "M83 · In riproduzione"
              )
              .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
            }
          }
          Spacer(minLength: 0)
          Image(systemName: "waveform").foregroundStyle(settings.accentColor)
        }
      }
      .foregroundStyle(.white)
      .padding(14)
      .frame(width: 270, height: 65)
      .background(
        .black.opacity(settings.notchOpacity),
        in: UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22)
      )
      Text("Anteprima illustrativa · Island chiusa")
        .font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, 12)
    .background(settings.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }
}
