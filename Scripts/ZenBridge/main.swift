import Foundation
import Darwin

// No sockets, no shell, no URL downloads. Firefox validates allowed_extensions.
// Both files stay in a private per-user directory. stdout is framing only.
umask(0o077)
let directory = ProcessInfo.processInfo.environment["DYNAMICISLAND_ZEN_STATE_DIRECTORY"].map {
    URL(fileURLWithPath: $0, isDirectory: true)
} ?? ZenMediaSnapshot.directory
let destination = directory.appendingPathComponent("snapshot.json")
let session = UUID().uuidString
let manager = FileManager.default
try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                            attributes: [.posixPermissions: 0o700])

func readExactly(_ count: Int) throws -> Data? {
    var result = Data()
    while result.count < count {
        guard let part = try FileHandle.standardInput.read(upToCount: count - result.count), !part.isEmpty else {
            if result.isEmpty { return nil }
            throw CocoaError(.fileReadCorruptFile)
        }
        result.append(part)
    }
    return result
}
func writeSnapshot(_ value: ZenMediaSnapshot) throws {
    try JSONEncoder().encode(value).write(to: destination, options: .atomic)
}
func ack() throws {
    let payload = Data("{\"ok\":true,\"version\":1}".utf8)
    var length = UInt32(payload.count).littleEndian
    var framed = withUnsafeBytes(of: &length) { Data($0) }
    framed.append(payload)
    try FileHandle.standardOutput.write(contentsOf: framed)
}
// An advisory lock prevents two profiles/instances from interleaving snapshots.
let lock = open(directory.appendingPathComponent("host.lock").path, O_CREAT | O_RDWR, 0o600)
guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(1) }
defer {
    try? writeSnapshot(ZenMediaSnapshot(version: 1, receivedAt: Date().timeIntervalSince1970,
                                       session: session, track: nil))
    close(lock)
}
do {
    while let header = try readExactly(4) {
        let size = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        guard size > 0, size <= 768_000, let body = try readExactly(Int(size)) else { break }
        var snapshot = try JSONDecoder().decode(ZenMediaSnapshot.self, from: body)
        guard snapshot.version == 1, snapshot.track?.isValid != false else { break }
        snapshot.receivedAt = Date().timeIntervalSince1970
        snapshot.session = session
        try writeSnapshot(snapshot)
        try ack()
    }
} catch {
    FileHandle.standardError.write(Data("DynamicIsland Zen host: invalid message or I/O failure\n".utf8))
}
