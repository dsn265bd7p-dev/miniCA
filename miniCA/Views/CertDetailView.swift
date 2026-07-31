import SwiftData
import SwiftUI

struct CertDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let cert: ManagedCertificate
    let caName: String
    @Query private var cas: [CertificateAuthority]
    @State private var showDeploySheet = false
    @State private var keyExportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: cert.role.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(cert.name).font(.title2.bold())
                    HStack(spacing: 8) {
                        RoleBadge(role: cert.role)
                        ExpiryBadge(level: cert.expiryLevel, days: cert.daysUntilExpiry)
                    }
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                detailRow("Common Name", cert.commonName)
                detailRow("SANs", cert.sanSummary)
                detailRow("Issued by", caName)
                detailRow("Serial", "\(cert.serial)")
                detailRow("Algorithm", cert.algorithm.displayName)
                detailRow(
                    "Validity",
                    "\(cert.notBefore.formatted(date: .abbreviated, time: .omitted)) – \(cert.notAfter.formatted(date: .abbreviated, time: .omitted))"
                )
                detailRow("SHA-256", PEM.fingerprint(pem: cert.certificatePEM))
            }
            .font(.callout)

            GroupBox("Certificate (PEM)") {
                ScrollView {
                    Text(cert.certificatePEM)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 120)
            }

            if let keyExportError {
                Text(keyExportError).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Button("Copy PEM") { copyToPasteboard(cert.certificatePEM) }
                Button("Save Certificate…") {
                    saveToFile(defaultName: "\(cert.commonName).crt", contents: cert.certificatePEM)
                }
                Button("Save Chain…") {
                    saveToFile(defaultName: "\(cert.commonName)-fullchain.crt", contents: chainPEM)
                }
                Button("Export Private Key…") { exportKey() }
                Spacer()
                Button("Deploy…", systemImage: "arrow.up.circle") { showDeploySheet = true }
                Button("Done") { dismiss() }
                    .prominentActionButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
        .sheet(isPresented: $showDeploySheet) {
            DeploySheet(preselectedCertificate: cert)
        }
    }

    /// Leaf certificate followed by its CA chain up to (and including) the root.
    private var chainPEM: String {
        var chain = [cert.certificatePEM]
        var currentID: UUID? = cert.issuingCAID
        while let id = currentID, let ca = cas.first(where: { $0.id == id }) {
            chain.append(ca.certificatePEM)
            currentID = ca.parentCAID
        }
        return chain.joined(separator: "\n")
    }

    private func exportKey() {
        do {
            let pem = try KeychainService.loadString(tag: cert.keychainKeyTag)
            saveToFile(defaultName: "\(cert.commonName).key", contents: pem)
        } catch {
            keyExportError = error.localizedDescription
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
