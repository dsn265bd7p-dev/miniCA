import SwiftData
import SwiftUI

struct DeploySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ManagedCertificate.createdAt, order: .reverse)
    private var certificates: [ManagedCertificate]
    @Query(sort: \LinuxServer.createdAt) private var servers: [LinuxServer]
    @Query private var cas: [CertificateAuthority]

    var preselectedCertificate: ManagedCertificate?
    var preselectedServer: LinuxServer?

    @State private var certificate: ManagedCertificate?
    @State private var server: LinuxServer?
    @State private var remoteCertPath = ""
    @State private var remoteKeyPath = ""
    @State private var installRootCA = false
    @State private var runReload = true
    @State private var isDeploying = false
    @State private var stepLog: [DeployStep] = []
    @State private var finished = false
    @State private var errorMessage: String?

    struct DeployStep: Identifiable {
        let id = UUID()
        let title: String
        var state: State

        enum State { case running, done, failed }
    }

    private var canDeploy: Bool {
        certificate != nil && server != nil && !remoteCertPath.isEmpty
            && !remoteKeyPath.isEmpty && !isDeploying && !finished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Deploy Certificate")
                .font(.title2.bold())
                .padding(24)

            Form {
                Picker("Certificate", selection: $certificate) {
                    Text("Select…").tag(nil as ManagedCertificate?)
                    ForEach(certificates.filter { $0.status == .active }) { cert in
                        Text("\(cert.name) (\(cert.commonName))").tag(cert as ManagedCertificate?)
                    }
                }
                .onChange(of: certificate) { _, _ in updateDefaultPaths() }

                Picker("Target Server", selection: $server) {
                    Text("Select…").tag(nil as LinuxServer?)
                    ForEach(servers) { srv in
                        Text("\(srv.name) (\(srv.connectionString))").tag(srv as LinuxServer?)
                    }
                }
                .onChange(of: server) { _, _ in updateDefaultPaths() }

                TextField("Remote certificate path", text: $remoteCertPath)
                TextField("Remote key path", text: $remoteKeyPath)

                Toggle("Install Root CA in server trust store", isOn: $installRootCA)
                Toggle("Run reload command after deployment", isOn: $runReload)
            }
            .formStyle(.grouped)

            if !stepLog.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(stepLog) { step in
                        HStack(spacing: 8) {
                            switch step.state {
                            case .running: ProgressView().controlSize(.small)
                            case .done:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failed:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            Text(step.title)
                        }
                        .font(.callout)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .padding(.horizontal, 24)
            }

            HStack {
                Button(finished ? "Close" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if finished {
                    Label("Deployed successfully!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        deploy()
                    } label: {
                        if isDeploying {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Deploy", systemImage: "arrow.up.circle")
                        }
                    }
                    .prominentActionButtonStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canDeploy)
                }
            }
            .padding(24)
        }
        .frame(width: 520)
        .interactiveDismissDisabled(isDeploying)
        .onAppear {
            certificate = preselectedCertificate ?? certificates.first { $0.status == .active }
            server = preselectedServer ?? (servers.count == 1 ? servers.first : nil)
            updateDefaultPaths()
        }
    }

    private func updateDefaultPaths() {
        guard let cert = certificate else { return }
        let dir = server?.certInstallDir ?? "/etc/ssl/minica"
        remoteCertPath = "\(dir)/\(cert.commonName).crt"
        remoteKeyPath = "\(dir)/\(cert.commonName).key"
    }

    private func rootCA(for cert: ManagedCertificate) -> CertificateAuthority? {
        var current = cas.first { $0.id == cert.issuingCAID }
        while let ca = current, !ca.isRoot, let parentID = ca.parentCAID {
            current = cas.first { $0.id == parentID }
        }
        return current
    }

    private func addStep(_ title: String) {
        stepLog.append(DeployStep(title: title, state: .running))
    }

    private func finishStep(failed: Bool = false) {
        guard let last = stepLog.indices.last else { return }
        stepLog[last].state = failed ? .failed : .done
    }

    private func deploy() {
        guard let cert = certificate, let srv = server else { return }
        isDeploying = true
        errorMessage = nil
        stepLog = []

        let config = srv.sshConfig()
        let certPEM = cert.certificatePEM
        let certPath = remoteCertPath
        let keyPath = remoteKeyPath
        let wantTrustCA = installRootCA
        let wantReload = runReload
        let root = rootCA(for: cert)
        let rootPEM = root?.certificatePEM
        let rootName = root?.name ?? "miniCA-root"

        Task {
            do {
                let keyPEM = try KeychainService.loadString(tag: cert.keychainKeyTag)

                addStep("Deploying certificate")
                _ = try await SSHService.deployCertificate(
                    certPEM: certPEM, keyPEM: keyPEM,
                    remoteCertPath: certPath, remoteKeyPath: keyPath, config: config)
                finishStep()

                if wantTrustCA, let rootPEM {
                    addStep("Installing Root CA in trust store")
                    _ = try await SSHService.installTrustCA(
                        caPEM: rootPEM, caName: rootName, config: config)
                    finishStep()
                }

                if wantReload {
                    addStep("Reloading service")
                    _ = try await SSHService.reloadService(config: config)
                    finishStep()
                }

                recordDeployment(cert: cert, server: srv, certPath: certPath, keyPath: keyPath)
                finished = true
            } catch {
                finishStep(failed: true)
                errorMessage = error.localizedDescription
            }
            isDeploying = false
        }
    }

    private func recordDeployment(
        cert: ManagedCertificate, server: LinuxServer, certPath: String, keyPath: String
    ) {
        let existing = try? modelContext.fetch(FetchDescriptor<Deployment>())
        if let deployment = existing?.first(where: {
            $0.certificateID == cert.id && $0.serverID == server.id
                && $0.remoteCertPath == certPath
        }) {
            deployment.deployedAt = .now
            deployment.remoteKeyPath = keyPath
        } else {
            let deployment = Deployment(
                certificateID: cert.id, serverID: server.id,
                remoteCertPath: certPath, remoteKeyPath: keyPath,
                deployedAt: .now)
            modelContext.insert(deployment)
        }
    }
}
