import SwiftData
import SwiftUI

struct NewCASheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CertificateAuthority.createdAt) private var cas: [CertificateAuthority]
    @AppStorage(SettingsKeys.defaultAlgorithm) private var defaultAlgorithm = KeyAlgorithm.ecdsaP256.rawValue
    @AppStorage(SettingsKeys.defaultCAValidityYears) private var defaultCAValidityYears = 10

    @State private var isRoot = true
    @State private var parentCA: CertificateAuthority?
    @State private var name = ""
    @State private var commonName = ""
    @State private var organization = ""
    @State private var country = "DE"
    @State private var algorithm = KeyAlgorithm.ecdsaP256
    @State private var validityYears = 10
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !name.isEmpty && !commonName.isEmpty && (isRoot || parentCA != nil) && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Certificate Authority")
                .font(.title2.bold())
                .padding(24)

            Form {
                Picker("Type", selection: $isRoot) {
                    Text("Root CA").tag(true)
                    Text("Intermediate CA").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(cas.isEmpty)

                if !isRoot {
                    Picker("Parent CA", selection: $parentCA) {
                        Text("Select…").tag(nil as CertificateAuthority?)
                        ForEach(cas) { ca in
                            Text(ca.name).tag(ca as CertificateAuthority?)
                        }
                    }
                }

                TextField("Name", text: $name, prompt: Text("My Homelab CA"))
                TextField("Common Name (CN)", text: $commonName, prompt: Text("Homelab Root CA"))
                TextField("Organization (O)", text: $organization)
                TextField("Country (C)", text: $country)
                    .onChange(of: country) { _, new in
                        country = String(new.uppercased().prefix(2))
                    }
                Picker("Algorithm", selection: $algorithm) {
                    ForEach(KeyAlgorithm.allCases) { alg in
                        Text(alg.displayName).tag(alg)
                    }
                }
                Stepper("Validity: \(validityYears) years", value: $validityYears, in: 1...30)
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
                    create()
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Create CA")
                    }
                }
                .prominentActionButtonStyle()
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
            .padding(24)
        }
        .frame(width: 480)
        .onAppear {
            algorithm = KeyAlgorithm(rawValue: defaultAlgorithm) ?? .ecdsaP256
            validityYears = defaultCAValidityYears
        }
    }

    private func create() {
        isWorking = true
        errorMessage = nil
        let days = validityYears * 365

        Task {
            do {
                let result: CACreationResult
                var parentID: UUID?

                if isRoot {
                    result = try await CAService.createRootCA(
                        name: name, commonName: commonName, organization: organization,
                        country: country, algorithm: algorithm, validityDays: days)
                } else {
                    guard let parent = parentCA else { return }
                    parent.serialCounter += 1
                    parentID = parent.id
                    result = try await CAService.createIntermediateCA(
                        name: name, commonName: commonName, organization: organization,
                        country: country, algorithm: algorithm, validityDays: days,
                        parentCAPEM: parent.certificatePEM,
                        parentCAAlgorithm: parent.algorithm,
                        parentCAKeyTag: parent.keychainKeyTag,
                        parentSerial: parent.serialCounter)
                }

                let ca = CertificateAuthority(
                    name: name, commonName: commonName, organization: organization,
                    country: country, isRoot: isRoot, parentCAID: parentID,
                    algorithm: algorithm, certificatePEM: result.certificatePEM,
                    keychainKeyTag: result.keychainKeyTag,
                    notBefore: result.notBefore, notAfter: result.notAfter)
                modelContext.insert(ca)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
