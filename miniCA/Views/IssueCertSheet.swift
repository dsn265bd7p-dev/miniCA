import SwiftData
import SwiftUI

struct IssueCertSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CertificateAuthority.createdAt) private var cas: [CertificateAuthority]
    @AppStorage(SettingsKeys.defaultAlgorithm) private var defaultAlgorithm = KeyAlgorithm.ecdsaP256.rawValue
    @AppStorage(SettingsKeys.defaultValidityDays) private var defaultValidityDays = 397

    @State private var issuingCA: CertificateAuthority?
    @State private var name = ""
    @State private var commonName = ""
    @State private var organization = ""
    @State private var role = CertRole.server
    @State private var algorithm = KeyAlgorithm.ecdsaP256
    @State private var validityDays = 397
    @State private var sanDNSText = ""
    @State private var sanIPText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var canIssue: Bool {
        issuingCA != nil && !commonName.isEmpty && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Issue Certificate")
                .font(.title2.bold())
                .padding(24)

            Form {
                Picker("Issuing CA", selection: $issuingCA) {
                    Text("Select…").tag(nil as CertificateAuthority?)
                    ForEach(cas) { ca in
                        Text(ca.name).tag(ca as CertificateAuthority?)
                    }
                }
                TextField("Name", text: $name, prompt: Text("web server prod"))
                TextField("Common Name (CN)", text: $commonName, prompt: Text("web.example.lan"))
                    .onChange(of: commonName) { _, new in
                        if name.isEmpty { name = new }
                    }
                TextField("Organization (O)", text: $organization)
                Picker("Role", selection: $role) {
                    ForEach(CertRole.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Algorithm", selection: $algorithm) {
                    ForEach(KeyAlgorithm.allCases) { alg in
                        Text(alg.displayName).tag(alg)
                    }
                }
                Stepper("Validity: \(validityDays) days", value: $validityDays, in: 1...3650, step: 30)

                Section("Subject Alternative Names") {
                    TextField(
                        "DNS names (comma-separated)", text: $sanDNSText,
                        prompt: Text("web.example.lan, www.example.lan"))
                    TextField(
                        "IP addresses (comma-separated)", text: $sanIPText,
                        prompt: Text("192.168.1.10"))
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 24)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    issue()
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Issue Certificate")
                    }
                }
                .prominentActionButtonStyle()
                .keyboardShortcut(.defaultAction)
                .disabled(!canIssue)
            }
            .padding(24)
        }
        .frame(width: 500)
        .onAppear {
            algorithm = KeyAlgorithm(rawValue: defaultAlgorithm) ?? .ecdsaP256
            validityDays = defaultValidityDays
            issuingCA = cas.count == 1 ? cas.first : cas.first { !$0.isRoot } ?? cas.first
        }
    }

    private static func splitList(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func issue() {
        guard let ca = issuingCA else { return }
        isWorking = true
        errorMessage = nil

        var sanDNS = Self.splitList(sanDNSText)
        let sanIP = Self.splitList(sanIPText)
        if role == .server, sanDNS.isEmpty, sanIP.isEmpty {
            // Server certs need at least one SAN; default to the CN.
            sanDNS = [commonName]
        }

        ca.serialCounter += 1

        Task {
            do {
                let result = try await CAService.issueCertificate(
                    commonName: commonName, organization: organization, role: role,
                    algorithm: algorithm, validityDays: validityDays,
                    sanDNS: sanDNS, sanIP: sanIP,
                    caCertPEM: ca.certificatePEM, caAlgorithm: ca.algorithm,
                    caKeyTag: ca.keychainKeyTag, caSerial: ca.serialCounter)

                let cert = ManagedCertificate(
                    name: name.isEmpty ? commonName : name,
                    commonName: commonName, organization: organization,
                    role: role, algorithm: algorithm,
                    certificatePEM: result.certificatePEM,
                    keychainKeyTag: result.keychainKeyTag,
                    sanDNS: sanDNS, sanIP: sanIP,
                    serial: ca.serialCounter, issuingCAID: ca.id,
                    notBefore: result.notBefore, notAfter: result.notAfter)
                modelContext.insert(cert)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
