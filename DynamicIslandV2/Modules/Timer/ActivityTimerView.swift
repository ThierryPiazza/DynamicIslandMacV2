import SwiftUI

struct ActivityTimerView: View {
    @ObservedObject var activities: CompactActivityController
    @State private var minutes = 25

    var body: some View {
        VStack(spacing: 5) {
            switch activities.countdown.status {
            case .idle:
                HStack(spacing: 8) {
                    Image(systemName: "timer").foregroundStyle(.white.opacity(0.7))
                    Stepper("\(minutes) min", value: $minutes, in: 1...99)
                        .fixedSize()
                }
                HStack(spacing: 8) {
                    ForEach([5, 15, 25], id: \.self) { preset in
                        Button("\(preset) min") { activities.startTimer(minutes: preset) }
                            .buttonStyle(PillButtonStyle())
                    }
                    Button("Avvia") { activities.startTimer(minutes: minutes) }
                        .buttonStyle(PillButtonStyle())
                }
                Button("Pomodoro · 25 / 5 min") { activities.startPomodoro() }
                    .buttonStyle(PillButtonStyle())
                    .help("25 minuti di lavoro, pausa breve di 5 minuti; ogni quattro sessioni una pausa di 15 minuti")
            case .running, .paused:
                if let session = activities.pomodoro {
                    Text("\(session.title) · sessione \(session.completedFocusSessions + (session.phase == .focus ? 1 : 0))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(ActivityCountdown.formatted(activities.remainingSeconds))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: activities.timerProgress)
                    .progressViewStyle(.linear)
                    .tint(ModuleSettings.shared.accentColor)
                    .accessibilityLabel("Avanzamento timer")
                    .accessibilityValue("\(Int(activities.timerProgress * 100)) per cento")
                    .padding(.horizontal, 12)
                HStack(spacing: 12) {
                    Button(activities.countdown.status == .paused ? "Riprendi" : "Pausa") {
                        activities.toggleTimerPause()
                    }.buttonStyle(PillButtonStyle())
                    Button("Annulla") { activities.cancelTimer() }
                        .buttonStyle(PillButtonStyle())
                }
            case .finished:
                Label("\(activities.timerTitle) terminato", systemImage: "bell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.green)
                ProgressView(value: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .accessibilityLabel("Timer completato")
                    .padding(.horizontal, 12)
                HStack {
                    if let session = activities.pomodoro {
                        Button(session.nextTitle) { activities.advancePomodoro() }.buttonStyle(PillButtonStyle())
                    }
                    Button(activities.pomodoro == nil ? "Nuovo timer" : "Termina") { activities.cancelTimer() }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .foregroundStyle(.white)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
