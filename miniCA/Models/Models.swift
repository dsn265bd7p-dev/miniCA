import Foundation
import SwiftData

@Model
final class CertificateAuthority {
    var id: UUID
    var name: String
    var commonName: String
    var organization: String
    var country: String
    var isRoot: Bool
    var parentCAID: UUID?
    var algorithm: KeyAlgorithm
    var certificatePEM: String
    var keychainKeyTag: String
    var notBefore: Date
    var notAfter: Date
    var createdAt: Date
    var serialCounter: Int

    init(
        id: UUID = UUID(),
        name: String,
        commonName: String,
        organization: String,
        country: String,
        isRoot: Bool,
        parentCAID: UUID? = nil,
        algorithm: KeyAlgorithm,
        certificatePEM: String,
        keychainKeyTag: String,
        notBefore: Date,
        notAfter: Date,
        createdAt: Date = .now,
        serialCounter: Int = 1
    ) {
        self.id = id
        self.name = name
        self.commonName = commonName
        self.organization = organization
        self.country = country
        self.isRoot = isRoot
        self.parentCAID = parentCAID
        self.algorithm = algorithm
        self.certificatePEM = certificatePEM
        self.keychainKeyTag = keychainKeyTag
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.createdAt = createdAt
        self.serialCounter = serialCounter
    }

    var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: .now, to: notAfter).day ?? 0
    }

    var isExpired: Bool { notAfter < .now }

    var expiryLevel: ExpiryLevel { .forDays(daysUntilExpiry) }
}

@Model
final class ManagedCertificate {
    var id: UUID
    var name: String
    var commonName: String
    var organization: String
    var role: CertRole
    var algorithm: KeyAlgorithm
    var certificatePEM: String
    var keychainKeyTag: String
    var sanDNS: [String]
    var sanIP: [String]
    var serial: Int
    var issuingCAID: UUID
    var status: CertStatus
    var notBefore: Date
    var notAfter: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        commonName: String,
        organization: String,
        role: CertRole,
        algorithm: KeyAlgorithm,
        certificatePEM: String,
        keychainKeyTag: String,
        sanDNS: [String] = [],
        sanIP: [String] = [],
        serial: Int,
        issuingCAID: UUID,
        status: CertStatus = .active,
        notBefore: Date,
        notAfter: Date,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.commonName = commonName
        self.organization = organization
        self.role = role
        self.algorithm = algorithm
        self.certificatePEM = certificatePEM
        self.keychainKeyTag = keychainKeyTag
        self.sanDNS = sanDNS
        self.sanIP = sanIP
        self.serial = serial
        self.issuingCAID = issuingCAID
        self.status = status
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.createdAt = createdAt
    }

    var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: .now, to: notAfter).day ?? 0
    }

    var isExpired: Bool { notAfter < .now }

    var expiryLevel: ExpiryLevel { .forDays(daysUntilExpiry) }

    var sanSummary: String {
        let all = sanDNS + sanIP
        return all.isEmpty ? "—" : all.joined(separator: ", ")
    }
}

@Model
final class LinuxServer {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var credentialTag: String
    var privateKeyPath: String
    var trustDistro: TrustDistro
    var certInstallDir: String
    var reloadCommand: String
    var notes: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "root",
        authMethod: AuthMethod = .sshKey,
        credentialTag: String = "",
        privateKeyPath: String = "",
        trustDistro: TrustDistro = .debian,
        certInstallDir: String = "/etc/ssl/minica",
        reloadCommand: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.credentialTag = credentialTag
        self.privateKeyPath = privateKeyPath
        self.trustDistro = trustDistro
        self.certInstallDir = certInstallDir
        self.reloadCommand = reloadCommand
        self.notes = notes
        self.createdAt = createdAt
    }

    var sshTarget: String { "\(username)@\(host)" }

    var connectionString: String {
        port == 22 ? sshTarget : "\(sshTarget):\(port)"
    }
}

@Model
final class Deployment {
    var id: UUID
    var certificateID: UUID
    var serverID: UUID
    var remoteCertPath: String
    var remoteKeyPath: String
    var deployedAt: Date?
    var lastScanAt: Date?
    var lastScanExpiry: Date?
    var lastScanStatus: ScanStatus
    var lastScanLog: String
    var notes: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        certificateID: UUID,
        serverID: UUID,
        remoteCertPath: String,
        remoteKeyPath: String,
        deployedAt: Date? = nil,
        lastScanAt: Date? = nil,
        lastScanExpiry: Date? = nil,
        lastScanStatus: ScanStatus = .unknown,
        lastScanLog: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.certificateID = certificateID
        self.serverID = serverID
        self.remoteCertPath = remoteCertPath
        self.remoteKeyPath = remoteKeyPath
        self.deployedAt = deployedAt
        self.lastScanAt = lastScanAt
        self.lastScanExpiry = lastScanExpiry
        self.lastScanStatus = lastScanStatus
        self.lastScanLog = lastScanLog
        self.notes = notes
        self.createdAt = createdAt
    }

    var daysUntilRemoteExpiry: Int? {
        guard let lastScanExpiry else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: lastScanExpiry).day
    }
}
