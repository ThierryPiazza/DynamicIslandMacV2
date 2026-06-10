import SwiftUI

struct WeatherView: View {
    @ObservedObject var monitor: WeatherMonitor

    var body: some View {
        Group {
            if monitor.locationDenied {
                deniedView
            } else if monitor.temperature == nil {
                loadingView
            } else {
                weatherContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { monitor.start() }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .tint(.white.opacity(0.3))
            Text(monitor.isLoading ? "Rilevamento posizione…" : "In attesa di posizione")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var deniedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.22))
            Text("Accesso alla posizione\nnecessario per il meteo")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            Button("Impostazioni Privacy") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
                )
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(10)
    }

    private var weatherContent: some View {
        HStack(spacing: 0) {
            // Icon + temperature
            VStack(spacing: 2) {
                Image(systemName: monitor.weatherCode.map { WeatherMonitor.icon(for: $0) } ?? "cloud.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.multicolor)
                    .frame(height: 36)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(monitor.temperature.map { "\($0)" } ?? "--")
                        .font(.system(size: 28, weight: .thin, design: .rounded))
                        .foregroundColor(.white)
                    Text("°")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(width: 86)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1, height: 58)
                .padding(.horizontal, 14)

            // Details
            VStack(alignment: .leading, spacing: 5) {
                if !monitor.cityName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.4))
                        Text(monitor.cityName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                if let code = monitor.weatherCode {
                    Text(WeatherMonitor.description(for: code))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                if let feels = monitor.feelsLike {
                    Text("Percepito \(feels)°")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.32))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }
}
