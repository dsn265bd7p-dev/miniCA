import SwiftData
import SwiftUI

@main
struct miniCAApp: App {
    init() {
        SelfTest.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootSplitView()
        }
        .modelContainer(for: [
            CertificateAuthority.self,
            ManagedCertificate.self,
            LinuxServer.self,
            Deployment.self,
        ])

        Settings {
            SettingsView()
        }
    }
}

/// App-wide user defaults keys (same keys the original app used).
enum SettingsKeys {
    static let defaultAlgorithm = "defaultAlgorithm"
    static let defaultCAValidityYears = "defaultCAValidityYears"
    static let defaultValidityDays = "defaultValidityDays"
    static let expiryWarningDays = "expiryWarningDays"
}
