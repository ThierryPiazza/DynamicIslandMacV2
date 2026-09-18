import Foundation

struct PomodoroSession {
    enum Phase { case focus, shortBreak, longBreak }
    private(set) var phase: Phase = .focus
    private(set) var completedFocusSessions = 0

    var minutes: Int {
        switch phase { case .focus: return 25; case .shortBreak: return 5; case .longBreak: return 15 }
    }
    var title: String {
        switch phase { case .focus: return "Concentrazione"; case .shortBreak: return "Pausa breve"; case .longBreak: return "Pausa lunga" }
    }
    var nextPhase: Phase {
        if phase != .focus { return .focus }
        return (completedFocusSessions + 1).isMultiple(of: 4) ? .longBreak : .shortBreak
    }
    var nextTitle: String {
        switch nextPhase {
        case .focus: return "Avvia lavoro · 25 min"
        case .shortBreak: return "Avvia pausa · 5 min"
        case .longBreak: return "Avvia pausa lunga · 15 min"
        }
    }
    mutating func advance() {
        let next = nextPhase
        if phase == .focus { completedFocusSessions += 1 }
        phase = next
    }
}
