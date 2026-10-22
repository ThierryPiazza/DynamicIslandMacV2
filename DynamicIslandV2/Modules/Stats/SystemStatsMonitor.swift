import Foundation
import Combine
import Darwin
import IOKit.ps

struct SystemStatsSnapshot {
    var cpu: Double?
    var memory: Double?
    var memoryUsed: Double = 0
    var memoryTotal: Double = 0
    var download: Double?
    var upload: Double?
    var battery: Double?
    var charging = false
    var history: [Double] = []

    static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
    }
    static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .binary) + "/s"
    }
}

/// One sampler shared by the tab and menu bar; system calls run off the main thread.
final class SystemStatsMonitor: ObservableObject {
    static let shared = SystemStatsMonitor()
    @Published private(set) var snapshot = SystemStatsSnapshot()
    private let queue = DispatchQueue(label: "DynamicIsland.systemStats", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var previousCPU: (total: UInt64, idle: UInt64)?
    private var previousNetwork: [String: (received: UInt64, sent: UInt64)] = [:]
    private var previousTime: TimeInterval?
    private var history: [Double] = []

    private init() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    private func sample() {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var value = SystemStatsSnapshot()
        var cpu = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        if cpuResult == KERN_SUCCESS {
            let ticks = cpu.cpu_ticks
            let total = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.2) + UInt64(ticks.3)
            let idle = UInt64(ticks.2)
            if let old = previousCPU, total > old.total, idle >= old.idle {
                value.cpu = min(1, max(0, 1 - Double(idle - old.idle) / Double(total - old.total)))
            }
            previousCPU = (total, idle)
        }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            value.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
            // App memory + wired + compressed, excluding purgeable pages.
            let pages = max(0, Double(vm.active_count) + Double(vm.inactive_count)
                + Double(vm.wire_count) + Double(vm.compressor_page_count)
                - Double(vm.purgeable_count) - Double(vm.external_page_count))
            value.memoryUsed = min(value.memoryTotal, pages * Double(vm_kernel_page_size))
            value.memory = value.memoryUsed / value.memoryTotal
        }
        let now = ProcessInfo.processInfo.systemUptime
        var addresses: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addresses) == 0 {
            defer { freeifaddrs(addresses) }
            var cursor = addresses
            var counters: [String: (received: UInt64, sent: UInt64)] = [:]
            while let entry = cursor {
                let interface = entry.pointee
                if let address = interface.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                   interface.ifa_flags & UInt32(IFF_UP) != 0,
                   interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                   let data = interface.ifa_data {
                    let name = String(cString: interface.ifa_name)
                    // Physical network interfaces; exclude VPN tunnels and peer-to-peer duplication.
                    if name.hasPrefix("en") {
                        let stats = data.assumingMemoryBound(to: if_data.self).pointee
                        counters[name] = (UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes))
                    }
                }
                cursor = interface.ifa_next
            }
            if let oldTime = previousTime, now > oldTime {
                var received: UInt64 = 0
                var sent: UInt64 = 0
                for (name, current) in counters {
                    if let old = previousNetwork[name], current.received >= old.received, current.sent >= old.sent {
                        received += current.received - old.received
                        sent += current.sent - old.sent
                    }
                }
                value.download = Double(received) / (now - oldTime)
                value.upload = Double(sent) / (now - oldTime)
            }
            previousNetwork = counters
            previousTime = now
        }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = description[kIOPSCurrentCapacityKey] as? Double,
                      let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
                value.battery = min(1, max(0, current / maximum))
                value.charging = description[kIOPSIsChargingKey] as? Bool ?? false
                break
            }
        }
        if let cpu = value.cpu {
            history.append(cpu)
            if history.count > 60 { history.removeFirst(history.count - 60) }
        }
        value.history = history
        let result = value
        DispatchQueue.main.async { [weak self] in self?.snapshot = result }
    }
}
