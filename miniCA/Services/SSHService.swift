import Foundation
import os

enum SSHError: Error, LocalizedError {
    case commandFailed(exitCode: Int32, output: String)
    case localIOError(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let code, let output):
            "Command failed (exit \(code)): \(output)"
        case .localIOError(let message):
            "Local I/O error: \(message)"
        }
    }
}

struct SSHResult: Sendable {
    var success: Bool
    var output: String
}

/// Everything SSHService needs to reach a server, captured as a Sendable value
/// so it can safely cross into background tasks (SwiftData models cannot).
struct SSHConfig: Sendable {
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var password: String?
    var privateKeyPath: String
    var certInstallDir: String
    var reloadCommand: String
    var trustDistro: TrustDistro

    var target: String { "\(username)@\(host)" }
}

/// Runs SSH/SCP against Linux servers via the system `/usr/bin/ssh` and
/// `/usr/bin/scp`. Password auth uses an SSH_ASKPASS helper; the password is
/// passed via the environment, never on the command line or on disk.
enum SSHService {
    private static let logger = Logger(subsystem: "com.local.miniCA", category: "ssh")

    // MARK: - Public API

    static func testConnection(config: SSHConfig) async throws -> SSHResult {
        try await runCommand("echo \"Connected to $(hostname)\" && uname -sr", config: config)
    }

    static func runCommand(_ command: String, config: SSHConfig) async throws -> SSHResult {
        let (code, out, err) = try await ssh(command, config: config)
        let output = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
        guard code == 0 else { throw SSHError.commandFailed(exitCode: code, output: output) }
        return SSHResult(success: true, output: output)
    }

    static func deployCertificate(
        certPEM: String,
        keyPEM: String,
        remoteCertPath: String,
        remoteKeyPath: String,
        config: SSHConfig
    ) async throws -> SSHResult {
        let token = UUID().uuidString
        let tmpCert = "/tmp/minica-\(token).crt"
        let tmpKey = "/tmp/minica-\(token).key"

        let localCert = try writeTempFile(certPEM, suffix: "crt")
        let localKey = try writeTempFile(keyPEM, suffix: "key")
        defer {
            try? FileManager.default.removeItem(at: localCert)
            try? FileManager.default.removeItem(at: localKey)
        }

        try await scp(localPath: localCert.path, remotePath: tmpCert, config: config)
        try await scp(localPath: localKey.path, remotePath: tmpKey, config: config)

        let certDir = shellQuote((remoteCertPath as NSString).deletingLastPathComponent)
        let keyDir = shellQuote((remoteKeyPath as NSString).deletingLastPathComponent)
        let install = [
            "sudo mkdir -p \(certDir) \(keyDir)",
            "sudo mv \(shellQuote(tmpCert)) \(shellQuote(remoteCertPath))",
            "sudo mv \(shellQuote(tmpKey)) \(shellQuote(remoteKeyPath))",
            "sudo chmod 644 \(shellQuote(remoteCertPath))",
            "sudo chmod 600 \(shellQuote(remoteKeyPath))",
        ].joined(separator: " && ")

        return try await runCommand(install, config: config)
    }

    static func installTrustCA(
        caPEM: String, caName: String, config: SSHConfig
    ) async throws -> SSHResult {
        let safeName = caName.map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { $0.append($1) }
        let tmp = "/tmp/minica-ca-\(UUID().uuidString).crt"
        let dest = "\(config.trustDistro.trustAnchorDir)/\(safeName).crt"

        let localCA = try writeTempFile(caPEM, suffix: "crt")
        defer { try? FileManager.default.removeItem(at: localCA) }

        try await scp(localPath: localCA.path, remotePath: tmp, config: config)

        let install = [
            "sudo mkdir -p \(shellQuote(config.trustDistro.trustAnchorDir))",
            "sudo mv \(shellQuote(tmp)) \(shellQuote(dest))",
            "sudo \(config.trustDistro.updateTrustCommand)",
        ].joined(separator: " && ")

        return try await runCommand(install, config: config)
    }

    static func reloadService(config: SSHConfig) async throws -> SSHResult {
        let command = config.reloadCommand.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else {
            return SSHResult(success: true, output: "No reload command configured — skipped.")
        }
        return try await runCommand("sudo \(command)", config: config)
    }

    /// Lists certificates in the server's install directory with their expiry dates.
    static func scanCertificates(config: SSHConfig) async throws -> [(path: String, expiry: Date?)] {
        let dir = shellQuote(config.certInstallDir)
        let script = """
            for f in \(dir)/*.crt \(dir)/*.pem \(dir)/*.cer; do
              [ -f "$f" ] || continue
              exp=$(openssl x509 -enddate -noout -in "$f" 2>/dev/null | cut -d= -f2)
              echo "CERT|$f|$exp"
            done
            """
        let result = try await runCommand(script, config: config)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"

        return result.output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "CERT" else { return nil }
            let expiry = formatter.date(
                from: String(parts[2]).trimmingCharacters(in: .whitespaces))
            return (path: String(parts[1]), expiry: expiry)
        }
    }

    // MARK: - Process plumbing

    private static func ssh(_ command: String, config: SSHConfig) async throws
        -> (Int32, String, String)
    {
        var args = commonOptions(config)
        args += ["-p", String(config.port), config.target, command]
        return try await run("/usr/bin/ssh", args, config: config)
    }

    private static func scp(localPath: String, remotePath: String, config: SSHConfig) async throws {
        var args = commonOptions(config)
        args += ["-P", String(config.port), localPath, "\(config.target):\(remotePath)"]
        let (code, out, err) = try await run("/usr/bin/scp", args, config: config)
        guard code == 0 else {
            throw SSHError.commandFailed(exitCode: code, output: out + err)
        }
    }

    private static func commonOptions(_ config: SSHConfig) -> [String] {
        var options = [
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no",
        ]
        switch config.authMethod {
        case .sshKey:
            options += ["-o", "BatchMode=yes"]
            let keyPath = config.privateKeyPath.trimmingCharacters(in: .whitespaces)
            if !keyPath.isEmpty {
                options += ["-i", (keyPath as NSString).expandingTildeInPath]
            }
        case .password:
            options += ["-o", "NumberOfPasswordPrompts=1", "-o", "PubkeyAuthentication=no"]
        }
        return options
    }

    private static func run(
        _ tool: String, _ arguments: [String], config: SSHConfig
    ) async throws -> (Int32, String, String) {
        var environment = ProcessInfo.processInfo.environment
        if config.authMethod == .password {
            environment["SSH_ASKPASS"] = try askpassHelperPath()
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = ":0"
            environment["MINICA_SSH_PASSWORD"] = config.password ?? ""
        }
        logger.info("running \(tool, privacy: .public) \(arguments.joined(separator: " "), privacy: .public)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let out = String(
                    data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (proc.terminationStatus, out, err))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Tiny helper script that echoes the password from the environment when
    /// ssh asks for it. Contains no secret itself.
    private static func askpassHelperPath() throws -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("miniCA", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("askpass.sh")
        let contents = "#!/bin/sh\nprintf '%s' \"$MINICA_SSH_PASSWORD\"\n"
        if (try? String(contentsOf: script, encoding: .utf8)) != contents {
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: script.path)
        }
        return script.path
    }

    private static func writeTempFile(_ contents: String, suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minica-\(UUID().uuidString).\(suffix)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
