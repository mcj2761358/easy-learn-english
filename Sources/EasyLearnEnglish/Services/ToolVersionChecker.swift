import Foundation

struct ToolCheckResult: Equatable {
    let name: String
    let found: Bool
    let version: String
    let path: String?
    let error: String?
}

enum ToolVersionChecker {
    static func checkYtDlp() -> ToolCheckResult {
        run(name: "yt-dlp", args: ["--version"], parse: { output in
            output
        })
    }

    static func checkFFmpeg() -> ToolCheckResult {
        run(name: "ffmpeg", args: ["-version"], parse: { output in
            // first line: "ffmpeg version X ..."
            let first = output.split(separator: "\n").first.map(String.init) ?? output
            return first
        })
    }

    private static func run(name: String, args: [String], parse: (String) -> String) -> ToolCheckResult {
        guard let path = findExecutable(name) else {
            return ToolCheckResult(name: name, found: false, version: "未安装", path: nil, error: nil)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ToolCheckResult(name: name, found: true, version: "", path: path, error: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            let version = parse(output.isEmpty ? err : output)
            return ToolCheckResult(name: name, found: true, version: version, path: path, error: nil)
        }

        let message = err.isEmpty ? output : err
        return ToolCheckResult(name: name, found: true, version: "", path: path, error: message)
    }

    private static func findExecutable(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let path = String(dir) + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

@MainActor
final class ToolsStatusModel: ObservableObject {
    @Published var ytDlp: ToolCheckResult?
    @Published var ffmpeg: ToolCheckResult?
    @Published var lastUpdated: Date?

    func refresh() {
        Task.detached {
            let yt = ToolVersionChecker.checkYtDlp()
            let ff = ToolVersionChecker.checkFFmpeg()
            await MainActor.run {
                self.ytDlp = yt
                self.ffmpeg = ff
                self.lastUpdated = Date()
            }
        }
    }
}
