import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }

    /// Hata mesajı için en anlamlı çıktı: önce stderr, yoksa stdout'un son satırları.
    var failureSummary: String {
        let source = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stdout : stderr
        let lines = source.split(whereSeparator: \.isNewline).suffix(4)
        return lines.joined(separator: "\n")
    }
}

enum ShellError: LocalizedError {
    case failed(command: String, result: ShellResult)

    var errorDescription: String? {
        switch self {
        case let .failed(command, result):
            let summary = result.failureSummary
            return summary.isEmpty ? "\(command) başarısız oldu (çıkış kodu \(result.status))." : summary
        }
    }
}

/// Harici komut çalıştırıcı. GUI uygulamaları login shell PATH'ini almadığı için Homebrew yolları elle eklenir.
enum Shell {
    static let searchPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func which(_ name: String) -> String? {
        for dir in searchPath.split(separator: ":") {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Komutu çalıştırır; `onLine` her yeni çıktı satırında (stdout + stderr) çağrılır.
    /// Görev iptal edilirse süreç sonlandırılır.
    static func run(
        _ executable: String,
        _ arguments: [String],
        environment extra: [String: String] = [:],
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        extra.forEach { env[$0.key] = $0.value }
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = OutputCollector(onLine: onLine)
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData, isError: false)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData, isError: true)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
                process.terminationHandler = { proc in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    collector.append(outPipe.fileHandleForReading.readDataToEndOfFile(), isError: false)
                    collector.append(errPipe.fileHandleForReading.readDataToEndOfFile(), isError: true)
                    let (out, err) = collector.finish()
                    continuation.resume(returning: ShellResult(status: proc.terminationStatus, stdout: out, stderr: err))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Başarısız çıkış kodunda `ShellError` fırlatan sürüm.
    @discardableResult
    static func runChecked(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String] = [:],
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ShellResult {
        let result = try await run(executable, arguments, environment: environment, onLine: onLine)
        guard result.succeeded else {
            let name = URL(fileURLWithPath: executable).lastPathComponent
            throw ShellError.failed(command: ([name] + arguments).joined(separator: " "), result: result)
        }
        return result
    }
}

/// Pipe'lardan gelen veriyi iş parçacığı güvenli biçimde toplar ve satır satır bildirir.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private var pendingLine = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ data: Data, isError: Bool) {
        guard !data.isEmpty else { return }
        var lines: [String] = []
        lock.lock()
        if isError { err.append(data) } else { out.append(data) }
        if onLine != nil, let text = String(data: data, encoding: .utf8) {
            pendingLine += text
            var parts = pendingLine.components(separatedBy: CharacterSet.newlines)
            pendingLine = parts.removeLast()
            lines = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func finish() -> (String, String) {
        lock.lock()
        defer { lock.unlock() }
        let rest = pendingLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { onLine?(rest) }
        pendingLine = ""
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}
