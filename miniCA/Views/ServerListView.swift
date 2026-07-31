import SwiftData
import SwiftUI

struct ServerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LinuxServer.createdAt) private var servers: [LinuxServer]
    @Query private var deployments: [Deployment]
    @State private var editingServer: LinuxServer?
    @State private var showAddServer = false
    @State private var deployTarget: LinuxServer?
    @State private var serverToDelete: LinuxServer?
    @State private var testResults: [UUID: String] = [:]
    @State private var busyServers: Set<UUID> = []

    var body: some View {
        List {
            ForEach(servers) { server in
                ServerRowView(
                    server: server,
                    deployments: deployments.filter { $0.serverID == server.id },
                    testResult: testResults[server.id],
                    isBusy: busyServers.contains(server.id),
                    onEdit: { editingServer = server },
                    onTest: { testConnection(server) },
                    onDeploy: { deployTarget = server },
                    onScan: { scan(server) }
                )
                .contextMenu {
                    Button("Edit…") { editingServer = server }
                    Button("Test Connection") { testConnection(server) }
                    Button("Scan Certificates") { scan(server) }
                    Divider()
                    Button("Delete", role: .destructive) { serverToDelete = server }
                }
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Server", systemImage: "plus") { showAddServer = true }
            }
        }
        .overlay {
            if servers.isEmpty {
                ContentUnavailableView {
                    Label("No Servers", systemImage: "server.rack")
                } description: {
                    Text("Add a Linux server to deploy certificates via SSH.")
                } actions: {
                    Button("Add Server") { showAddServer = true }
                        .prominentActionButtonStyle()
                }
            }
        }
        .sheet(isPresented: $showAddServer) { ServerEditSheet(server: nil) }
        .sheet(item: $editingServer) { server in ServerEditSheet(server: server) }
        .sheet(item: $deployTarget) { server in DeploySheet(preselectedServer: server) }
        .confirmationDialog(
            "Delete server “\(serverToDelete?.name ?? "")”?",
            isPresented: .init(
                get: { serverToDelete != nil },
                set: { if !$0 { serverToDelete = nil } })
        ) {
            Button("Delete server", role: .destructive) {
                if let server = serverToDelete {
                    KeychainService.delete(tag: server.credentialTag)
                    for deployment in deployments where deployment.serverID == server.id {
                        modelContext.delete(deployment)
                    }
                    modelContext.delete(server)
                }
                serverToDelete = nil
            }
        } message: {
            Text("Stored credentials and deployment records for this server are removed. Nothing is changed on the server itself.")
        }
    }

    private func testConnection(_ server: LinuxServer) {
        let config = server.sshConfig()
        busyServers.insert(server.id)
        testResults[server.id] = nil
        Task {
            defer { busyServers.remove(server.id) }
            do {
                let result = try await SSHService.testConnection(config: config)
                testResults[server.id] = "✓ \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
            } catch {
                testResults[server.id] = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func scan(_ server: LinuxServer) {
        let config = server.sshConfig()
        let serverDeployments = deployments.filter { $0.serverID == server.id }
        busyServers.insert(server.id)
        Task {
            defer { busyServers.remove(server.id) }
            do {
                let found = try await SSHService.scanCertificates(config: config)
                let summary = found.map { entry in
                    "\(entry.path): \(entry.expiry?.formatted(date: .abbreviated, time: .omitted) ?? "unreadable")"
                }.joined(separator: "\n")
                for deployment in serverDeployments {
                    deployment.lastScanAt = .now
                    if let match = found.first(where: { $0.path == deployment.remoteCertPath }) {
                        deployment.lastScanStatus = .ok
                        deployment.lastScanExpiry = match.expiry
                        deployment.lastScanLog = summary
                    } else {
                        deployment.lastScanStatus = .failed
                        deployment.lastScanLog = "Certificate not found on server.\n\(summary)"
                    }
                }
                testResults[server.id] =
                    found.isEmpty
                    ? "✓ Scan finished — no certificates in \(config.certInstallDir)"
                    : "✓ Scan found \(found.count) certificate(s)"
            } catch {
                for deployment in serverDeployments {
                    deployment.lastScanAt = .now
                    deployment.lastScanStatus = .failed
                    deployment.lastScanLog = error.localizedDescription
                }
                testResults[server.id] = "✗ \(error.localizedDescription)"
            }
        }
    }
}

struct ServerRowView: View {
    let server: LinuxServer
    let deployments: [Deployment]
    let testResult: String?
    let isBusy: Bool
    let onEdit: () -> Void
    let onTest: () -> Void
    let onDeploy: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.indigo)
                    .font(.title3)
                VStack(alignment: .leading) {
                    Text(server.name).font(.headline)
                    Text("\(server.connectionString) · \(server.trustDistro.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Test", action: onTest)
                Button("Scan", action: onScan)
                    .disabled(deployments.isEmpty)
                Button("Deploy…", action: onDeploy)
                Button("Edit", action: onEdit)
            }
            if !deployments.isEmpty {
                Text("\(deployments.count) deployment(s)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testResult.hasPrefix("✓") ? Color.green : Color.red)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 6)
    }
}

extension LinuxServer {
    /// Snapshot of the server's connection data as a Sendable value, with the
    /// password resolved from the Keychain.
    func sshConfig() -> SSHConfig {
        SSHConfig(
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            password: authMethod == .password
                ? (try? KeychainService.loadString(tag: credentialTag)) : nil,
            privateKeyPath: privateKeyPath,
            certInstallDir: certInstallDir,
            reloadCommand: reloadCommand,
            trustDistro: trustDistro)
    }
}
