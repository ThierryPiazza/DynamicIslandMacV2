import Foundation

struct CompactActivity: Equatable {
    enum Destination { case fileHub, shelf, timer }
    enum Style { case working, success, failure, notice, countdown }

    let id: String
    let symbol: String
    let label: String
    let detail: String
    let destination: Destination
    let style: Style
    let priority: Int
    var expiresAt: Date? = nil

    static func preferred(from activities: [CompactActivity], at now: Date) -> CompactActivity? {
        activities.filter { $0.expiresAt.map { $0 > now } ?? true }
            .max { $0.priority < $1.priority }
    }


}

/// Il tempo deriva da una scadenza assoluta: resta corretto anche dopo lo stop del Mac.
struct ActivityCountdown {
    enum Status { case idle, running, paused, finished }
    private(set) var status: Status = .idle
    private(set) var deadline: Date?
    private var pausedSeconds = 0
    private(set) var totalSeconds = 0

    func progress(remaining seconds: Int) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - Double(seconds) / Double(totalSeconds)))
    }

    func remaining(at now: Date) -> Int {
        if let deadline { return max(0, Int(ceil(deadline.timeIntervalSince(now)))) }
        return pausedSeconds
    }

    mutating func start(seconds: Int, at now: Date) {
        guard seconds > 0 else { return }
        totalSeconds = seconds
        deadline = now.addingTimeInterval(TimeInterval(seconds))
        pausedSeconds = 0
        status = .running
    }

    mutating func pause(at now: Date) {
        guard status == .running else { return }
        update(at: now)
        guard status == .running else { return }
        pausedSeconds = remaining(at: now)
        deadline = nil
        status = .paused
    }

    mutating func resume(at now: Date) {
        guard status == .paused else { return }
        deadline = now.addingTimeInterval(TimeInterval(pausedSeconds))
        pausedSeconds = 0
        status = .running
    }

    mutating func update(at now: Date) {
        if status == .running, remaining(at: now) == 0 {
            deadline = nil
            status = .finished
        }
    }

    mutating func cancel() { self = ActivityCountdown() }

    static func formatted(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
