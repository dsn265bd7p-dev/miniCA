import Foundation

/// Headless end-to-end test of the CA pipeline, run via `miniCA --selftest <dir>`.
/// Creates a root CA, an intermediate, and leaf certificates for several
/// algorithms, writes the PEMs to <dir>, then removes the Keychain entries.
enum SelfTest {
    static func runIfRequested() {
        guard let idx = CommandLine.arguments.firstIndex(of: "--selftest"),
            CommandLine.arguments.count > idx + 1
        else { return }
        let outDir = URL(fileURLWithPath: CommandLine.arguments[idx + 1])

        Task.detached {
            do {
                try await run(outDir: outDir)
                print("SELFTEST OK")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("SELFTEST FAILED: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    private static func run(outDir: URL) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var tags: [String] = []
        defer { tags.forEach { KeychainService.delete(tag: $0) } }

        func write(_ name: String, _ contents: String) throws {
            try contents.write(
                to: outDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let root = try await CAService.createRootCA(
            name: "SelfTest Root", commonName: "SelfTest Root CA",
            organization: "miniCA", country: "DE", algorithm: .ecdsaP256, validityDays: 3650)
        tags.append(root.keychainKeyTag)
        try write("root.crt", root.certificatePEM)

        let intermediate = try await CAService.createIntermediateCA(
            name: "SelfTest Intermediate", commonName: "SelfTest Intermediate CA",
            organization: "miniCA", country: "DE", algorithm: .ecdsaP384, validityDays: 1825,
            parentCAPEM: root.certificatePEM, parentCAAlgorithm: .ecdsaP256,
            parentCAKeyTag: root.keychainKeyTag, parentSerial: 2)
        tags.append(intermediate.keychainKeyTag)
        try write("intermediate.crt", intermediate.certificatePEM)

        for (algorithm, label) in [
            (KeyAlgorithm.ecdsaP256, "p256"),
            (.ed25519, "ed25519"),
            (.rsa2048, "rsa2048"),
        ] {
            let leaf = try await CAService.issueCertificate(
                commonName: "web.selftest.lan", organization: "miniCA",
                role: .server, algorithm: algorithm, validityDays: 397,
                sanDNS: ["web.selftest.lan", "www.selftest.lan"], sanIP: ["192.168.1.10"],
                caCertPEM: intermediate.certificatePEM, caAlgorithm: .ecdsaP384,
                caKeyTag: intermediate.keychainKeyTag, caSerial: 100)
            tags.append(leaf.keychainKeyTag)
            try write("leaf-\(label).crt", leaf.certificatePEM)
            try write("leaf-\(label).key", try await CAService.exportPrivateKeyPEM(tag: leaf.keychainKeyTag))
        }

        let client = try await CAService.issueCertificate(
            commonName: "alice", organization: "miniCA",
            role: .client, algorithm: .ecdsaP256, validityDays: 365,
            sanDNS: [], sanIP: [],
            caCertPEM: intermediate.certificatePEM, caAlgorithm: .ecdsaP384,
            caKeyTag: intermediate.keychainKeyTag, caSerial: 101)
        tags.append(client.keychainKeyTag)
        try write("client.crt", client.certificatePEM)
    }
}
