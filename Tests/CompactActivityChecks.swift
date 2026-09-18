import Foundation

// Esegui con:
// swiftc DynamicIslandV2/Core/CompactActivity.swift Tests/CompactActivityChecks.swift -o /tmp/compact-activity-checks
// /tmp/compact-activity-checks
@main
struct CompactActivityChecks {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000)
        let timer = CompactActivity(id: "timer", symbol: "timer", label: "00:30", detail: "Timer",
                                    destination: .timer, style: .countdown, priority: 40)
        let working = CompactActivity(id: "file", symbol: "doc", label: "", detail: "Conversione",
                                      destination: .fileHub, style: .working, priority: 80)
        let done = CompactActivity(id: "done", symbol: "checkmark", label: "OK", detail: "Completato",
                                   destination: .fileHub, style: .success, priority: 100,
                                   expiresAt: now.addingTimeInterval(6))
        let shelf = CompactActivity(id: "shelf", symbol: "tray", label: "+3", detail: "File aggiunti",
                                    destination: .shelf, style: .notice, priority: 90,
                                    expiresAt: now.addingTimeInterval(5))
        expect(CompactActivity.preferred(from: [timer, working, done, shelf], at: now) == done,
               "L’esito deve avere precedenza su conversione, shelf e timer")
        expect(CompactActivity.preferred(from: [timer, working, done, shelf], at: now.addingTimeInterval(6)) == working,
               "Alla scadenza degli avvisi deve tornare l’operazione in corso")
        expect(CompactActivity.preferred(from: [timer, done], at: now.addingTimeInterval(6)) == timer,
               "Il timer deve riapparire dopo la conferma FileHub")
        expect(CompactActivity.preferred(from: [done], at: now.addingTimeInterval(6)) == nil,
               "Senza attività valide deve tornare il contenuto musicale")
        expect(CompactActivity.preferred(from: [working, shelf], at: now)?.destination == .shelf,
               "La conferma shelf deve aprire la shelf, non il risultato FileHub")

        var countdown = ActivityCountdown()
        countdown.start(seconds: 90, at: now)
        expect(countdown.remaining(at: now.addingTimeInterval(30)) == 60, "Il countdown usa il tempo trascorso")
        countdown.pause(at: now.addingTimeInterval(30))
        expect(countdown.remaining(at: now.addingTimeInterval(500)) == 60, "La pausa conserva il tempo restante")
        countdown.resume(at: now.addingTimeInterval(500))
        expect(countdown.remaining(at: now.addingTimeInterval(510)) == 50, "La ripresa ricrea la scadenza")
        countdown.update(at: now.addingTimeInterval(900))
        expect(countdown.status == .finished && countdown.remaining(at: now.addingTimeInterval(900)) == 0,
               "Dopo lo stop del Mac, un timer scaduto deve risultare terminato")
        countdown.cancel()
        expect(countdown.status == .idle && countdown.deadline == nil, "L’annullamento elimina la scadenza")
        countdown.start(seconds: 1, at: now)
        countdown.pause(at: now.addingTimeInterval(2))
        expect(countdown.status == .finished, "Una pausa dopo la scadenza non deve congelare un timer a zero")
        expect(ActivityCountdown.formatted(754) == "12:34", "Formato del countdown compatto")
        countdown.start(seconds: 100, at: now)
        expect(countdown.progress(remaining: 100) == 0, "La barra parte da zero")
        countdown.pause(at: now.addingTimeInterval(25))
        expect(countdown.progress(remaining: countdown.remaining(at: now.addingTimeInterval(400))) == 0.25,
               "La barra non avanza in pausa")
        countdown.resume(at: now.addingTimeInterval(400))
        expect(countdown.totalSeconds == 100, "Riprendere mantiene la durata originale")
        expect(countdown.progress(remaining: countdown.remaining(at: now.addingTimeInterval(425))) == 0.5,
               "La barra continua dal punto di pausa invece di ripartire")
        countdown.update(at: now.addingTimeInterval(600))
        expect(countdown.progress(remaining: 0) == 1, "La barra si completa alla scadenza")
        countdown.cancel()
        expect(countdown.progress(remaining: 0) == 0, "Annullare azzera anche la barra")
        print("Controlli superati: priorità, scadenze, timer e avanzamento dopo pausa/ripresa.")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
