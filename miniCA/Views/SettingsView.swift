import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.defaultAlgorithm) private var defaultAlgorithm = KeyAlgorithm.ecdsaP256.rawValue
    @AppStorage(SettingsKeys.defaultCAValidityYears) private var defaultCAValidityYears = 10
    @AppStorage(SettingsKeys.defaultValidityDays) private var defaultValidityDays = 397
    @AppStorage(SettingsKeys.expiryWarningDays) private var expiryWarningDays = 30

    var body: some View {
        Form {
            Picker("Default algorithm", selection: $defaultAlgorithm) {
                ForEach(KeyAlgorithm.allCases) { alg in
                    Text(alg.displayName).tag(alg.rawValue)
                }
            }
            Stepper(
                "Default CA validity: \(defaultCAValidityYears) years",
                value: $defaultCAValidityYears, in: 1...30)
            Stepper(
                "Default certificate validity: \(defaultValidityDays) days",
                value: $defaultValidityDays, in: 30...3650, step: 30)
            Stepper(
                "Warn \(expiryWarningDays) days before expiry",
                value: $expiryWarningDays, in: 7...180, step: 1)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
