import Foundation
import UIKit

/// Always-on stdout/stderr capture. Documents is intentionally Files-visible.
final class LycorineDiagnosticLog {
    static let shared = LycorineDiagnosticLog()
    let directoryURL: URL
    let currentFileURL: URL
    private let queue = DispatchQueue(label: "com.lycorine.logging.writer", qos: .utility)
    private let fm = FileManager.default
    private let maxBytes = 5 * 1024 * 1024
    private var handle: FileHandle?
    private var byteCount = 0
    private var pending = ""
    private var started = false

    private static let formatter: ISO8601DateFormatter = {
        let result = ISO8601DateFormatter()
        result.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return result
    }()

    private init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directoryURL = docs.appendingPathComponent("Lycorine-Logs", isDirectory: true)
        currentFileURL = directoryURL.appendingPathComponent("latest.log")
        try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        rotateArchives()
        openLatest()
    }

    private func rotateArchives() {
        try? handle?.close()
        handle = nil
        for index in stride(from: 5, through: 1, by: -1) {
            let destination = directoryURL.appendingPathComponent("previous-\(index).log")
            let source = index == 1
                ? currentFileURL
                : directoryURL.appendingPathComponent("previous-\(index - 1).log")
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.removeItem(at: destination)
            try? fm.moveItem(at: source, to: destination)
        }
        byteCount = 0
    }

    private func openLatest() {
        if !fm.fileExists(atPath: currentFileURL.path) {
            _ = fm.createFile(atPath: currentFileURL.path, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: currentFileURL.path)
        if let attrs = try? fm.attributesOfItem(atPath: currentFileURL.path),
           let size = attrs[.size] as? NSNumber {
            byteCount = size.intValue
        }
        _ = try? handle?.seekToEnd()
    }

    func start(reading pipe: Pipe) {
        guard !started else { return }
        started = true
        pipe.fileHandleForReading.readabilityHandler = { [weak self] source in
            let data = source.availableData
            if data.isEmpty {
                source.readabilityHandler = nil
                self?.queue.async { [weak self] in self?.flushPending() }
                return
            }
            self?.queue.async { [weak self] in self?.consume(data) }
        }
    }

    private func stamp() -> String { Self.formatter.string(from: Date()) }

    private func consume(_ data: Data) {
        pending += String(decoding: data, as: UTF8.self)
        var batch = ""
        while let newline = pending.firstIndex(of: "\n") {
            let text = String(pending[..<newline])
                .replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]",
                                      with: "", options: .regularExpression)
            pending.removeSubrange(...newline)
            batch += "[\(stamp())] \(text)\n"
        }
        if pending.count > 65536 {
            batch += "[\(stamp())] [long output truncated] \(String(pending.suffix(4096)))\n"
            pending = ""
        }
        if !batch.isEmpty { persist(batch) }
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        let text = "[\(stamp())] \(pending)\n"
        pending = ""
        persist(text)
    }

    private func persist(_ text: String) {
        let data = Data(text.utf8)
        if byteCount + data.count > maxBytes {
            rotateArchives()
            openLatest()
        }
        if handle == nil { openLatest() }
        do {
            try handle?.write(contentsOf: data)
            try handle?.synchronize()
            byteCount += data.count
        } catch {
            // Avoid print here: it would recursively write to this pipe.
        }
        DispatchQueue.main.async {
            let manager = LycorineManager.shared
            manager.log.append(text)
            if manager.log.count > 450000 {
                manager.log = String(manager.log.suffix(350000))
            }
        }
    }
}
