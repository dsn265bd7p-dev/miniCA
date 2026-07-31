import SwiftData
import SwiftUI

struct ServerEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let server: LinuxServer?

    @State private var name = ""
    @State private var host = ""
    @State private var port = 22
    @State private var username = "root"
    @State private var authMethod = AuthMethod.sshKey
    @State private var password = ""
    @State private var privateKeyPath = "~/.ssh/id_ed25519"
    @State private var trustDistro = TrustDistro.debian
    @State private var certInstallDir = "/etc/ssl/minica"
    @State private var reloadCommand = ""
    @State private var notes = ""
    @State private var testResult: String?
    @State private var isTesting = false

    private var canSave: Bool { !name.isEmpty && !host.isEmpty && !username.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(server == nil ? "Add Server" : "Edit Server")
                .font(.title2.bold())
                .padding(24)

            Form {
                TextField("Name", text: $name, prompt: Text("web-01"))
                TextField("Host", text: $host, prompt: Text("192.168.1.10 or web.example.lan"))
                TextField("Port", value: $port, format: .number.grouping(.never))
                TextField("Username", text: $username)

                Picker("Authentication", selection: $authMethod) {
                    ForEach(AuthMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if authMethod == .password {
                    SecureField("Password", text: $password)
                } else {
                    TextField("Private key path", text: $privateKeyPath)
                }

                Section("Certificate deployment") {
                    Picker("Distribution", selection: $trustDistro) {
                        ForEach(TrustDistro.allCases) { distro in
                            Text(distro.displayName).tag(distro)
                        }
                    }
                    TextField("Certificate directory", text: $certInstallDir)
                    TextField(
                        "Reload command", text: $reloadCommand,
                        prompt: Text("systemctl reload nginx"))
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testResult.hasPrefix("✓") ? Color.green : Color.red)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    testConnection()
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(!canSave || isTesting)
                Spacer()
                Button("Save") { save() }
                    .prominentActionButtonStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(24)
        }
        .frame(width: 500)
        .onAppear(perform: load)
    }

    private func load() {
        guard let server else { return }
        name = server.name
        host = server.host
        port = server.port
        username = server.username
        authMethod = server.authMethod
        privateKeyPath = server.privateKeyPath.isEmpty ? "~/.ssh/id_ed25519" : server.privateKeyPath
        trustDistro = server.trustDistro
        certInstallDir = server.certInstallDir
        reloadCommand = server.reloadCommand
        notes = server.notes
        password = (try? KeychainService.loadString(tag: server.credentialTag)) ?? ""
    }

    private func currentConfig() -> SSHConfig {
        SSHConfig(
            host: host, port: port, username: username, authMethod: authMethod,
            password: authMethod == .password ? password : nil,
            privateKeyPath: privateKeyPath, certInstallDir: certInstallDir,
            reloadCommand: reloadCommand, trustDistro: trustDistro)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let config = currentConfig()
        Task {
            defer { isTesting = false }
            do {
                let result = try await SSHService.testConnection(config: config)
                testResult = "✓ \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func save() {
        let target: LinuxServer
        if let server {
            target = server
        } else {
            target = LinuxServer()
            modelContext.insert(target)
        }
        target.name = name
        target.host = host
        target.port = port
        target.username = username
        target.authMethod = authMethod
        target.privateKeyPath = privateKeyPath
        target.trustDistro = trustDistro
        target.certInstallDir = certInstallDir
        target.reloadCommand = reloadCommand
        target.notes = notes

        if target.credentialTag.isEmpty {
            target.credentialTag = KeychainService.sshTag(for: target.id)
        }
        if authMethod == .password, !password.isEmpty {
            try? KeychainService.store(
                string: password, tag: target.credentialTag,
                label: "miniCA SSH: \(username)@\(host)")
        }
        dismiss()
    }
}
