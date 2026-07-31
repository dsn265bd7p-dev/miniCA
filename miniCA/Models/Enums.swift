import Foundation
import SwiftUI

enum KeyAlgorithm: String, Codable, CaseIterable, Sendable, Identifiable {
    case ecdsaP256
    case ecdsaP384
    case ed25519
    case rsa2048
    case rsa4096

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ecdsaP256: "ECDSA P-256"
        case .ecdsaP384: "ECDSA P-384"
        case .ed25519: "Ed25519"
        case .rsa2048: "RSA 2048"
        case .rsa4096: "RSA 4096"
        }
    }
}

enum CertRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case server
    case client

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .server: "Server"
        case .client: "Client"
        }
    }

    var systemImage: String {
        switch self {
        case .server: "server.rack"
        case .client: "person.badge.key"
        }
    }
}

enum CertStatus: String, Codable, CaseIterable, Sendable {
    case active
    case revoked

    var displayName: String {
        switch self {
        case .active: "Active"
        case .revoked: "Revoked"
        }
    }
}

enum AuthMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case password
    case sshKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password: "Password"
        case .sshKey: "SSH Key"
        }
    }
}

enum TrustDistro: String, Codable, CaseIterable, Sendable, Identifiable {
    case debian
    case rhel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .debian: "Debian / Ubuntu"
        case .rhel: "RHEL / Fedora"
        }
    }

    /// Directory where the Root CA certificate must be placed on the server.
    var trustAnchorDir: String {
        switch self {
        case .debian: "/usr/local/share/ca-certificates"
        case .rhel: "/etc/pki/ca-trust/source/anchors"
        }
    }

    /// Command that rebuilds the system trust store after adding a CA.
    var updateTrustCommand: String {
        switch self {
        case .debian: "update-ca-certificates"
        case .rhel: "update-ca-trust extract"
        }
    }
}

enum ScanStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case ok
    case failed

    var displayName: String {
        switch self {
        case .unknown: "Never scanned"
        case .ok: "OK"
        case .failed: "Failed"
        }
    }
}

enum ExpiryLevel: Sendable {
    case ok
    case warning
    case critical
    case expired

    var color: Color {
        switch self {
        case .ok: .green
        case .warning: .yellow
        case .critical: .orange
        case .expired: .red
        }
    }

    var label: String {
        switch self {
        case .ok: "Valid"
        case .warning: "Expiring soon"
        case .critical: "Critical"
        case .expired: "Expired"
        }
    }

    static func forDays(_ days: Int, warningDays: Int = 30) -> ExpiryLevel {
        if days < 0 { return .expired }
        if days <= warningDays / 2 { return .critical }
        if days <= warningDays { return .warning }
        return .ok
    }
}

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    case cas
    case certificates
    case servers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .cas: "Certificate Authorities"
        case .certificates: "Certificates"
        case .servers: "Servers"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .cas: "checkmark.seal"
        case .certificates: "doc.badge.ellipsis"
        case .servers: "server.rack"
        }
    }
}
