// Dynamic Island listener for the vendored MediaRemote Adapter helper.
import Foundation
import Darwin

@MainActor
public final class MediaController {
    public var onTrackInfoReceived: ((TrackInfo?) -> Void)?
    public var onListenerTerminated: (() -> Void)?
    public var onDecodingError: ((Error, Data) -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var generation = 0
    private let commandQueue = DispatchQueue(label: "dynamicisland.media.commands")

    public init() {}
    public var isListening: Bool { process?.isRunning == true }

    public func startListening() {
        guard process == nil else { return }
        guard let script = Bundle.module.path(forResource: "run", ofType: "pl"),
              let library = Bundle(for: MediaController.self).executablePath else {
            onListenerTerminated?()
            return
        }
        generation += 1
        let token = generation
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [script, library, "loop"]
        let output = Pipe()
        let input = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.consume(data)
            }
        }
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.stopListening()
                self.onListenerTerminated?()
            }
        }
        process = child
        self.input = input
        do { try child.run() }
        catch {
            stopListening()
            onListenerTerminated?()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        // Artwork can be large; still bound memory if a helper produces malformed output.
        guard buffer.count <= 32 * 1024 * 1024 else {
            stopListening()
            onListenerTerminated?()
            return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line == Data("NIL".utf8) {
                onTrackInfoReceived?(nil)
            } else if !line.isEmpty {
                do { onTrackInfoReceived?(try JSONDecoder().decode(TrackInfo.self, from: line)) }
                catch { onDecodingError?(error, Data()) }
            }
        }
    }

    public func stopListening() {
        generation += 1
        let old = process
        process = nil
        input = nil
        buffer.removeAll()
        (old?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        old?.terminationHandler = nil
        if old?.isRunning == true { old?.terminate() }
    }

    @discardableResult
    public func send(_ command: String, expectedBundleID: String) -> Bool {
        guard ["play", "pause", "toggle_play_pause", "next_track", "previous_track"].contains(command),
              !expectedBundleID.isEmpty,
              expectedBundleID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              isListening, let input else { return false }
        let token = generation
        let data = Data(("target " + expectedBundleID + " " + command + "\n").utf8)
        commandQueue.async { [weak self] in
            do { try input.fileHandleForWriting.write(contentsOf: data) }
            catch {
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.stopListening()
                    self.onListenerTerminated?()
                }
            }
        }
        return true
    }

    deinit {
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
    }
}
