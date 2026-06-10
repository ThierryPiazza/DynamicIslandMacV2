import SwiftUI
import EventKit

struct CalendarView: View {
    @ObservedObject var monitor: CalendarMonitor

    var body: some View {
        Group {
            if monitor.isAuthorized {
                if monitor.events.isEmpty {
                    emptyState
                } else {
                    eventsList
                }
            } else {
                permissionState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - States

    private var eventsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(monitor.events, id: \.eventIdentifier) { event in
                    Button {
                        openEvent(event)
                    } label: {
                        EventRowView(event: event)
                    }
                    .buttonStyle(EventRowButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    /// Apre Calendar.app e naviga alla data dell'evento.
    /// NSWorkspace.open() è il metodo primario: funziona sempre, anche da un panel
    /// non-activating, senza richiedere permessi TCC aggiuntivi per Apple Events.
    /// L'AppleScript è un best-effort: naviga alla data specifica se l'utente
    /// ha già concesso il permesso "Controlla Calendar" in precedenza.
    private func openEvent(_ event: EKEvent) {
        // 1. Apri Calendar in modo affidabile
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.open(url)
        }

        // 2. Naviga alla data (best-effort, richiede permesso apple-events su Calendar)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMMM d, yyyy 'at' HH:mm:ss"
        let dateStr = fmt.string(from: event.startDate)
        let script = """
        tell application "Calendar"
            activate
            switch view to day view
            view calendar at date "\(dateStr)"
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.2))
            Text("Nessun evento nei prossimi 7 giorni")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.28))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var permissionState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.25))
            Text("Accesso al calendario necessario")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            Button("Abilita accesso") {
                if monitor.isNotDetermined {
                    // Prima richiesta: mostra il dialogo TCC
                    monitor.requestAccess()
                } else {
                    // Accesso già negato: apri Impostazioni e inizia a fare poll
                    // per rilevare quando l'utente concede l'accesso dall'esterno.
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
                    )
                    monitor.startPollingAuthStatus()
                }
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding()
    }
}

// MARK: - Event row

struct EventRowView: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(calendarColor)
                .frame(width: 5, height: 5)

            Text(timeString)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 48, alignment: .leading)
                .fixedSize()

            Text(event.title ?? "Evento")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private var calendarColor: Color {
        if let cgColor = event.calendar.cgColor {
            return Color(cgColor: cgColor)
        }
        return .white.opacity(0.4)
    }

    private var timeString: String {
        let cal = Calendar.current

        if event.isAllDay {
            if cal.isDateInToday(event.startDate)    { return "Oggi" }
            if cal.isDateInTomorrow(event.startDate) { return "Domani" }
            return weekdayAbbr(for: event.startDate)
        }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        if cal.isDateInToday(event.startDate) {
            return timeFmt.string(from: event.startDate)
        }
        if cal.isDateInTomorrow(event.startDate) {
            return "Dem \(timeFmt.string(from: event.startDate))"
        }
        return "\(weekdayAbbr(for: event.startDate)) \(timeFmt.string(from: event.startDate))"
    }

    private func weekdayAbbr(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        fmt.locale = Locale.current
        return fmt.string(from: date).prefix(3).capitalized
    }
}

// MARK: - Event row button style

/// Stile senza bordi né sfondo di default; aggiunge una tinta di hover sottile.
struct EventRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.white.opacity(0.10)
                    : Color.clear
            )
            .contentShape(Rectangle())
            .onHover { over in
                if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}
