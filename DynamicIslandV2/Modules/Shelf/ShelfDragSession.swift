import AppKit
import Combine

/// Balances security-scoped access and both event monitors on every exit path.
final class ShelfDragSession: ObservableObject {
    private var monitors: [Any] = []
    private var accessedURL: URL?
    private var timeout: Timer?

    func begin(url: URL, onDropOutside: @escaping () -> Void) {
        finish()
        if url.startAccessingSecurityScopedResource() { accessedURL = url }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            let outside = !NSApp.windows.contains { $0.isVisible && $0.frame.contains(location) }
            self.finish()
            if outside { DispatchQueue.main.async(execute: onDropOutside) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown], handler: { [weak self] event in
            if event.type == .leftMouseUp || event.keyCode == 53 { self?.finish() }
            return event
        }) { monitors.append(monitor) }
        timeout = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in self?.finish() }
    }

    private func finish() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        timeout?.invalidate()
        timeout = nil
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    deinit { finish() }
}
