import Foundation

struct ConversionOption: Identifiable {
    var id: String { ext }
    let label: String   // "JPG", "WAV"…
    let ext: String     // estensione output
}

