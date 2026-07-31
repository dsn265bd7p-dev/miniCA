import SwiftData
import SwiftUI

struct CAListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CertificateAuthority.createdAt) private var cas: [CertificateAuthority]
    @State private var showNewCA = false
    @State private var selectedCA: CertificateAuthority?
    @State private var caToDelete: CertificateAuthority?

    var body: some View {
        List {
            ForEach(cas) { ca in
                Button {
                    selectedCA = ca
                } label: {
                    CARow(ca: ca)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Details…") { selectedCA = ca }
                    Button("Copy PEM") { copyToPasteboard(ca.certificatePEM) }
                    Divider()
                    Button("Delete", role: .destructive) { caToDelete = ca }
                }
            }
        }
        .navigationTitle("Certificate Authorities")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New CA", systemImage: "plus") { showNewCA = true }
            }
        }
        .overlay {
            if cas.isEmpty {
                ContentUnavailableView {
                    Label("No Certificate Authorities", systemImage: "checkmark.seal")
                } description: {
                    Text("Create your first Root CA.")
                } actions: {
                    Button("Create Root CA") { showNewCA = true }
                        .prominentActionButtonStyle()
                }
            }
        }
        .sheet(isPresented: $showNewCA) { NewCASheet() }
        .sheet(item: $selectedCA) { ca in CADetailSheet(ca: ca) }
        .confirmationDialog(
            "Delete CA “\(caToDelete?.name ?? "")”?",
            isPresented: .init(
                get: { caToDelete != nil },
                set: { if !$0 { caToDelete = nil } })
        ) {
            Button("Delete CA and private key", role: .destructive) {
                if let ca = caToDelete {
                    KeychainService.delete(tag: ca.keychainKeyTag)
                    modelContext.delete(ca)
                }
                caToDelete = nil
            }
        } message: {
            Text("The private key is removed from the Keychain. Certificates issued by this CA remain but can no longer be renewed.")
        }
    }
}

private struct CARow: View {
    let ca: CertificateAuthority

    var body: some View {
        HStack {
            Image(systemName: ca.isRoot ? "checkmark.seal.fill" : "checkmark.seal")
                .foregroundStyle(.teal)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(ca.name).font(.headline)
                Text("\(ca.commonName) · \(ca.algorithm.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ca.isRoot ? "Root CA" : "Intermediate CA")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .badgeBackground(tint: ca.isRoot ? .teal : .cyan)
            ExpiryBadge(level: ca.expiryLevel, days: ca.daysUntilExpiry)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

struct CADetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let ca: CertificateAuthority
    @State private var keyExportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.teal)
                VStack(alignment: .leading) {
                    Text(ca.name).font(.title2.bold())
                    Text(ca.isRoot ? "Root CA" : "Intermediate CA")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                detailRow("Common Name", ca.commonName)
                detailRow("Organization", ca.organization)
                detailRow("Country", ca.country)
                detailRow("Algorithm", ca.algorithm.displayName)
                detailRow(
                    "Validity",
                    "\(ca.notBefore.formatted(date: .abbreviated, time: .omitted)) – \(ca.notAfter.formatted(date: .abbreviated, time: .omitted))"
                )
                detailRow("Issued certificates", "\(max(ca.serialCounter - 1, 0))")
                detailRow("SHA-256", PEM.fingerprint(pem: ca.certificatePEM))
            }
            .font(.callout)

            GroupBox("Certificate (PEM)") {
                ScrollView {
                    Text(ca.certificatePEM)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 140)
            }

            if let keyExportError {
                Text(keyExportError).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Button("Copy PEM") { copyToPasteboard(ca.certificatePEM) }
                Button("Save Certificate…") {
                    saveToFile(defaultName: "\(ca.name).crt", contents: ca.certificatePEM)
                }
                .help("Save Root CA certificate for import on other devices")
                Button("Export Private Key…") { exportKey() }
                Spacer()
                Button("Done") { dismiss() }
                    .prominentActionButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func exportKey() {
        do {
            let pem = try KeychainService.loadString(tag: ca.keychainKeyTag)
            saveToFile(defaultName: "\(ca.name).key", contents: pem)
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
