import AppKit
import Combine

@MainActor
final class CompactActivityController: ObservableObject {
    @Published private(set) var current: CompactActivity?
    @Published private(set) var countdown = ActivityCountdown()
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var pomodoro: PomodoroSession?
    var timerTitle: String { pomodoro?.title ?? "Timer" }
    let fileHub = FileHubViewModel()

    var timerProgress: Double { countdown.progress(remaining: remainingSeconds) }

    private var fileActivity: CompactActivity?
    private var shelfActivity: CompactActivity?
    private var timerFinishedAt: Date?
    private var lastShelfAddition: Date?
    private var shelfBatchCount = 0
    private var wakeup: Timer?
    private var subscriptions = Set<AnyCancellable>()

    init(shelf: ShelfManager) {
        fileHub.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            self?.fileChanged(state)
        }.store(in: &subscriptions)
        shelf.$additionCount.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.shelfAdded()
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.refresh()
            }.store(in: &subscriptions)
    }

    deinit { wakeup?.invalidate() }

    func startTimer(minutes: Int) {
        pomodoro = nil
        beginCountdown(minutes: minutes)
    }

    func startPomodoro() {
        pomodoro = PomodoroSession()
        beginCountdown(minutes: 25)
    }

    func advancePomodoro() {
        guard countdown.status == .finished, var session = pomodoro else { return }
        session.advance()
        pomodoro = session
        beginCountdown(minutes: session.minutes)
    }

    private func beginCountdown(minutes: Int) {
        countdown.start(seconds: max(1, min(minutes, 99)) * 60, at: Date())
        timerFinishedAt = nil
        refresh()
    }

    func toggleTimerPause() {
        let now = Date()
        if countdown.status == .running { countdown.pause(at: now) }
        else { countdown.resume(at: now) }
        refresh()
    }

    func cancelTimer() {
        pomodoro = nil
        countdown.cancel()
        timerFinishedAt = nil
        refresh()
    }

    func openCurrent(in notch: NotchState) {
        guard let current else { notch.expand(); return }
        switch current.destination {
        case .fileHub:
            fileHub.showingShelf = false
            notch.expand(tab: .shelf)
        case .shelf:
            fileHub.showingShelf = true
            notch.expand(tab: .shelf)
        case .timer: notch.expand(tab: .timer)
        }
    }

    private func fileChanged(_ state: FileHubState) {
        let now = Date()
        switch state {
        case .processing(let label):
            fileActivity = CompactActivity(id: "file", symbol: "arrow.triangle.2.circlepath", label: "",
                                           detail: label, destination: .fileHub, style: .working, priority: 80)
        case .bgRemoving:
            fileActivity = CompactActivity(id: "file", symbol: "scissors", label: "",
                                           detail: "Rimozione sfondo in corso", destination: .fileHub, style: .working, priority: 80)
        case .done(_, let label):
            fileActivity = CompactActivity(id: "file-done", symbol: "checkmark.circle.fill", label: "OK",
                                           detail: label, destination: .fileHub, style: .success, priority: 100,
                                           expiresAt: now.addingTimeInterval(6))
        case .bgDone:
            fileActivity = CompactActivity(id: "file-done", symbol: "checkmark.circle.fill", label: "OK",
                                           detail: "Sfondo rimosso — apri per salvare", destination: .fileHub, style: .success,
                                           priority: 100, expiresAt: now.addingTimeInterval(6))
        case .error(let message):
            fileActivity = CompactActivity(id: "file-error", symbol: "exclamationmark.triangle.fill", label: "!",
                                           detail: message, destination: .fileHub, style: .failure, priority: 100,
                                           expiresAt: now.addingTimeInterval(8))
        default: fileActivity = nil
        }
        refresh()
    }

    private func shelfAdded() {
        let now = Date()
        shelfBatchCount = lastShelfAddition.map { now.timeIntervalSince($0) < 1 } == true ? shelfBatchCount + 1 : 1
        lastShelfAddition = now
        shelfActivity = CompactActivity(id: "shelf", symbol: "tray.and.arrow.down.fill", label: "+\(shelfBatchCount)",
                                        detail: "\(shelfBatchCount) file aggiunti alla shelf", destination: .shelf,
                                        style: .notice, priority: 90, expiresAt: now.addingTimeInterval(5))
        refresh()
    }

    private func refresh() {
        let now = Date()
        if countdown.status == .running {
            var updated = countdown
            updated.update(at: now)
            if updated.status != countdown.status { countdown = updated }
        }
        if countdown.status == .finished, timerFinishedAt == nil {
            timerFinishedAt = now
            // Una sola volta per fase, anche al risveglio del Mac.
            NSSound(named: "Glass")?.play()
        }
        let seconds = countdown.remaining(at: now)
        if seconds != remainingSeconds { remainingSeconds = seconds }

        var candidates = [fileActivity, shelfActivity].compactMap { $0 }
        if countdown.status == .running || countdown.status == .paused {
            candidates.append(CompactActivity(id: "timer", symbol: countdown.status == .paused ? "pause.fill" : "timer",
                                              label: ActivityCountdown.formatted(seconds),
                                              detail: "\(timerTitle) \(countdown.status == .paused ? "in pausa" : "in corso"): \(ActivityCountdown.formatted(seconds))",
                                              destination: .timer, style: .countdown, priority: 40))
        } else if let finished = timerFinishedAt {
            candidates.append(CompactActivity(id: "timer-done", symbol: "bell.fill", label: "Fine",
                                              detail: "\(timerTitle) terminato", destination: .timer, style: .success,
                                              priority: 100, expiresAt: finished.addingTimeInterval(8)))
        }
        let selected = CompactActivity.preferred(from: candidates, at: now)
        if current != selected { current = selected }

        // Nessun polling quando non ci sono scadenze; un solo timer mentre si conta.
        wakeup?.invalidate()
        var deadlines = candidates.compactMap(\.expiresAt).filter { $0 > now }
        if countdown.status == .running {
            deadlines.append(now.addingTimeInterval(1))
        }
        if let next = deadlines.min() {
            let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            wakeup = timer
        } else { wakeup = nil }
    }
}
