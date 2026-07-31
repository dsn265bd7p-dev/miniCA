import SwiftData
import SwiftUI

struct CertificateListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ManagedCertificate.createdAt, order: .reverse)
    private var certificates: [ManagedCertificate]
    @Query private var cas: [CertificateAuthority]
    @State private var showIssueSheet = false
    @State private var selectedCert: ManagedCertificate?
    @State private var certToDelete: ManagedCertificate?

    var body: some View {
        List {
            ForEach(certificates) { cert in
                Button {
                    selectedCert = cert
                } label: {
                    CertRow(cert: cert, caName: caName(for: cert))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Details…") { selectedCert = cert }
                    Button("Copy PEM") { copyToPasteboard(cert.certificatePEM) }
                    Divider()
                    Button("Delete", role: .destructive) { certToDelete = cert }
                }
            }
        }
        .navigationTitle("Certificates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Issue Certificate", systemImage: "plus") { showIssueSheet = true }
                    .disabled(cas.isEmpty)
            }
        }
        .overlay {
            if certificates.isEmpty {
                ContentUnavailableView {
                    Label("No Certificates", systemImage: "doc.badge.ellipsis")
                } description: {
                    Text(
                        cas.isEmpty
                            ? "Create a Root CA to get started."
                            : "Issue your first certificate.")
                } actions: {
                    if !cas.isEmpty {
                        Button("Issue Certificate") { showIssueSheet = true }
                            .prominentActionButtonStyle()
                    }
                }
            }
        }
        .sheet(isPresented: $showIssueSheet) { IssueCertSheet() }
        .sheet(item: $selectedCert) { cert in
            CertDetailView(cert: cert, caName: caName(for: cert))
        }
        .confirmationDialog(
            "Delete certificate “\(certToDelete?.name ?? "")”?",
            isPresented: .init(
                get: { certToDelete != nil },
                set: { if !$0 { certToDelete = nil } })
        ) {
            Button("Delete certificate and private key", role: .destructive) {
                if let cert = certToDelete {
                    KeychainService.delete(tag: cert.keychainKeyTag)
                    modelContext.delete(cert)
                }
                certToDelete = nil
            }
        }
    }

    private func caName(for cert: ManagedCertificate) -> String {
        cas.first { $0.id == cert.issuingCAID }?.name ?? "Unknown CA"
    }
}

private struct CertRow: View {
    let cert: ManagedCertificate
    let caName: String

    var body: some View {
        HStack {
            Image(systemName: cert.role.systemImage)
                .foregroundStyle(.blue)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(cert.name).font(.headline)
                Text("\(cert.commonName) · \(cert.sanSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Issued by \(caName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            RoleBadge(role: cert.role)
            ExpiryBadge(level: cert.expiryLevel, days: cert.daysUntilExpiry)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
