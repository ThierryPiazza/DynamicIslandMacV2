import SwiftUI
import Charts

struct SystemStatsView: View {
    @ObservedObject private var monitor = SystemStatsMonitor.shared

    var body: some View {
        let stats = monitor.snapshot
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("CPU", systemImage: "cpu")
                    Spacer()
                    Text(SystemStatsSnapshot.percent(stats.cpu)).monospacedDigit()
                }
                Chart(Array(stats.history.enumerated()), id: \.offset) { point in
                    LineMark(x: .value("Campione", point.offset), y: .value("CPU", point.element * 100))
                        .foregroundStyle(.cyan)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 45)
                Text("Ultimi 2 minuti · aggiornamento ogni 2 s")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                metric("RAM", symbol: "memorychip", value: SystemStatsSnapshot.percent(stats.memory))
                metric("Download", symbol: "arrow.down", value: SystemStatsSnapshot.rate(stats.download))
                metric("Upload", symbol: "arrow.up", value: SystemStatsSnapshot.rate(stats.upload))
                metric("Batteria", symbol: stats.charging ? "battery.100.bolt" : "battery.100",
                       value: stats.battery == nil ? "Non presente" : SystemStatsSnapshot.percent(stats.battery))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func metric(_ title: String, symbol: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
    }
}
