import Foundation

struct CommandResult {
    let argv: [String]
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }
    var display: String {
        let head = "$ " + argv.joined(separator: " ")
        let body = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return body.isEmpty ? head : head + "\n" + body
    }
}

/// Runs external tools (git / gh) off the main thread. GUI apps get a minimal
/// PATH, so Homebrew locations are appended explicitly (gh lives there).
enum ExternalTool {
    static func run(_ argv: [String], cwd: String? = nil) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = argv
                if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                var env = ProcessInfo.processInfo.environment
                let path = env["PATH"] ?? "/usr/bin:/bin"
                env["PATH"] = path + ":/opt/homebrew/bin:/usr/local/bin"
                process.environment = env

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(
                        argv: argv, status: -1, stdout: "", stderr: "\(error)"))
                    return
                }
                // Drain stderr concurrently so neither pipe can fill and stall.
                var errData = Data()
                let errQueue = DispatchQueue(label: "tool-stderr")
                let errItem = DispatchWorkItem {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                }
                errQueue.async(execute: errItem)
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                errItem.wait()
                process.waitUntilExit()

                continuation.resume(returning: CommandResult(
                    argv: argv,
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .newlines),
                    stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .newlines)))
            }
        }
    }
}

/// git / gh operations against the zmk-config repo.
struct GitPipeline {
    let repoPath: String
    static let keymapRelPath = "config/roBa.keymap"
    static let cheatsheetRelPath = "CHEATSHEET.md"
    /// Files this app owns in the zmk-config repo (edited + committed together).
    static let managedPaths = [keymapRelPath, cheatsheetRelPath]

    private func git(_ args: String...) async -> CommandResult {
        await git(args)
    }

    private func git(_ args: [String]) async -> CommandResult {
        await ExternalTool.run(["git", "-C", repoPath] + args)
    }

    private func gh(_ args: [String]) async -> CommandResult {
        await ExternalTool.run(["gh"] + args, cwd: repoPath)
    }

    // MARK: - Local state

    func keymapDiff() async -> String {
        let result = await git(["diff", "--no-color", "--"] + Self.managedPaths)
        return result.ok ? result.stdout : result.display
    }

    func restoreKeymap() async -> CommandResult {
        await git(["restore", "--"] + Self.managedPaths)
    }

    /// Dirt outside the files we manage (warn before committing).
    func unrelatedChanges() async -> [String] {
        let result = await git(["status", "--porcelain"])
        guard result.ok else { return [] }
        return result.stdout.split(separator: "\n")
            .map(String.init)
            .filter { line in
                !line.isEmpty && !Self.managedPaths.contains { line.hasSuffix($0) }
            }
    }

    func headSHA() async -> String? {
        let result = await git("rev-parse", "HEAD")
        return result.ok ? result.stdout : nil
    }

    // MARK: - Commit & push

    func commitAndPush(message: String) async -> [CommandResult] {
        var results: [CommandResult] = []
        let add = await git(["add", "--"] + Self.managedPaths)
        results.append(add)
        guard add.ok else { return results }
        let commit = await git("commit", "-m", message)
        results.append(commit)
        guard commit.ok else { return results }
        let push = await git("push")
        results.append(push)
        return results
    }

    // MARK: - GitHub Actions

    func ghAuthOK() async -> Bool {
        await gh(["auth", "status"]).ok
    }

    struct WorkflowRun: Decodable {
        let databaseId: Int
        let status: String          // queued / in_progress / completed
        let conclusion: String?     // success / failure / …
        let headSha: String
    }

    /// Most recent build.yml run for the given commit, if any.
    func findRun(sha: String) async -> WorkflowRun? {
        let result = await gh(["run", "list", "--workflow", "build.yml",
                               "--json", "databaseId,status,conclusion,headSha",
                               "--limit", "10"])
        guard result.ok else { return nil }
        return Self.matchRun(json: result.stdout, sha: sha)
    }

    /// Pure part, selftest-able against fixture JSON.
    static func matchRun(json: String, sha: String) -> WorkflowRun? {
        guard let data = json.data(using: .utf8),
              let runs = try? JSONDecoder().decode([WorkflowRun].self, from: data) else {
            return nil
        }
        return runs.first { $0.headSha == sha }
    }

    /// Download the firmware artifact into ~/Downloads/roba-firmware-<sha>/.
    func downloadArtifact(runID: Int, sha: String) async -> (CommandResult, URL) {
        let short = String(sha.prefix(7))
        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/roba-firmware-\(short)", isDirectory: true)
        var result = await gh(["run", "download", "\(runID)", "-n", "firmware", "-D", dest.path])
        if !result.ok {
            // Artifact name may differ across reusable-workflow versions.
            result = await gh(["run", "download", "\(runID)", "-D", dest.path])
        }
        return (result, dest)
    }

    func triggerDrawWorkflow() async -> CommandResult {
        await gh(["workflow", "run", "draw.yml"])
    }
}
