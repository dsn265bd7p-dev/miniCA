import Crypto
import Foundation
import SwiftASN1
import X509
import _CryptoExtras

enum CAServiceError: Error, LocalizedError {
    case invalidIPAddress(String)
    case keyGenerationFailed
    case invalidParentCertificate

    var errorDescription: String? {
        switch self {
        case .invalidIPAddress(let ip): "Invalid IP address: \(ip)"
        case .keyGenerationFailed: "Key generation failed"
        case .invalidParentCertificate: "The parent CA certificate could not be parsed"
        }
    }
}

struct CACreationResult: Sendable {
    let certificatePEM: String
    let keychainKeyTag: String
    let notBefore: Date
    let notAfter: Date
}

struct CertCreationResult: Sendable {
    let certificatePEM: String
    let keychainKeyTag: String
    let notBefore: Date
    let notAfter: Date
}

/// Creates CAs and issues certificates. All functions are nonisolated async,
/// so key generation (RSA can take seconds) runs off the main actor.
enum CAService {

    // MARK: - Public API

    static func createRootCA(
        name: String,
        commonName: String,
        organization: String,
        country: String,
        algorithm: KeyAlgorithm,
        validityDays: Int
    ) async throws -> CACreationResult {
        let key = try generateKey(algorithm)
        let subject = try distinguishedName(
            commonName: commonName, organization: organization, country: country)
        let notBefore = Date.now.addingTimeInterval(-300)
        let notAfter = Date.now.addingTimeInterval(TimeInterval(validityDays) * 86_400)

        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            Critical(KeyUsage(keyCertSign: true, cRLSign: true))
            SubjectKeyIdentifier(hash: key.publicKey)
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: serialNumber(1),
            publicKey: key.publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: subject,
            subject: subject,
            signatureAlgorithm: signatureAlgorithm(for: algorithm),
            extensions: extensions,
            issuerPrivateKey: key)

        let tag = KeychainService.keyTag(for: UUID())
        try KeychainService.store(
            string: try privateKeyPEM(key: key, algorithm: algorithm),
            tag: tag, label: "miniCA Root CA: \(name)")

        return CACreationResult(
            certificatePEM: try PEM.certToPEM(certificate),
            keychainKeyTag: tag,
            notBefore: notBefore,
            notAfter: notAfter)
    }

    static func createIntermediateCA(
        name: String,
        commonName: String,
        organization: String,
        country: String,
        algorithm: KeyAlgorithm,
        validityDays: Int,
        parentCAPEM: String,
        parentCAAlgorithm: KeyAlgorithm,
        parentCAKeyTag: String,
        parentSerial: Int
    ) async throws -> CACreationResult {
        let parentCert = try PEM.certFromPEM(parentCAPEM)
        let parentKey = try loadPrivateKey(algorithm: parentCAAlgorithm, tag: parentCAKeyTag)
        let key = try generateKey(algorithm)
        let subject = try distinguishedName(
            commonName: commonName, organization: organization, country: country)
        let notBefore = Date.now.addingTimeInterval(-300)
        let notAfter = Date.now.addingTimeInterval(TimeInterval(validityDays) * 86_400)

        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
            Critical(KeyUsage(keyCertSign: true, cRLSign: true))
            SubjectKeyIdentifier(hash: key.publicKey)
            if let ski = try parentCert.extensions.subjectKeyIdentifier {
                AuthorityKeyIdentifier(keyIdentifier: ski.keyIdentifier)
            }
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: serialNumber(parentSerial),
            publicKey: key.publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: parentCert.subject,
            subject: subject,
            signatureAlgorithm: signatureAlgorithm(for: parentCAAlgorithm),
            extensions: extensions,
            issuerPrivateKey: parentKey)

        let tag = KeychainService.keyTag(for: UUID())
        try KeychainService.store(
            string: try privateKeyPEM(key: key, algorithm: algorithm),
            tag: tag, label: "miniCA Intermediate CA: \(name)")

        return CACreationResult(
            certificatePEM: try PEM.certToPEM(certificate),
            keychainKeyTag: tag,
            notBefore: notBefore,
            notAfter: notAfter)
    }

    static func issueCertificate(
        commonName: String,
        organization: String,
        role: CertRole,
        algorithm: KeyAlgorithm,
        validityDays: Int,
        sanDNS: [String],
        sanIP: [String],
        caCertPEM: String,
        caAlgorithm: KeyAlgorithm,
        caKeyTag: String,
        caSerial: Int
    ) async throws -> CertCreationResult {
        let caCert = try PEM.certFromPEM(caCertPEM)
        let caKey = try loadPrivateKey(algorithm: caAlgorithm, tag: caKeyTag)
        let key = try generateKey(algorithm)
        let subject = try distinguishedName(
            commonName: commonName, organization: organization, country: nil)
        let notBefore = Date.now.addingTimeInterval(-300)
        let notAfter = Date.now.addingTimeInterval(TimeInterval(validityDays) * 86_400)

        var generalNames: [GeneralName] = sanDNS.map { .dnsName($0) }
        for ip in sanIP {
            generalNames.append(.ipAddress(try ipOctets(ip)))
        }

        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true, keyEncipherment: true))
            try ExtendedKeyUsage(role == .server ? [.serverAuth] : [.clientAuth])
            SubjectKeyIdentifier(hash: key.publicKey)
            if let ski = try caCert.extensions.subjectKeyIdentifier {
                AuthorityKeyIdentifier(keyIdentifier: ski.keyIdentifier)
            }
            if !generalNames.isEmpty {
                SubjectAlternativeNames(generalNames)
            }
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: serialNumber(caSerial),
            publicKey: key.publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: caCert.subject,
            subject: subject,
            signatureAlgorithm: signatureAlgorithm(for: caAlgorithm),
            extensions: extensions,
            issuerPrivateKey: caKey)

        let tag = KeychainService.keyTag(for: UUID())
        try KeychainService.store(
            string: try privateKeyPEM(key: key, algorithm: algorithm),
            tag: tag, label: "miniCA Certificate: \(commonName)")

        return CertCreationResult(
            certificatePEM: try PEM.certToPEM(certificate),
            keychainKeyTag: tag,
            notBefore: notBefore,
            notAfter: notAfter)
    }

    static func exportPrivateKeyPEM(tag: String) async throws -> String {
        try KeychainService.loadString(tag: tag)
    }

    // MARK: - Keys

    private static func generateKey(_ algorithm: KeyAlgorithm) throws -> Certificate.PrivateKey {
        switch algorithm {
        case .ecdsaP256: Certificate.PrivateKey(P256.Signing.PrivateKey())
        case .ecdsaP384: Certificate.PrivateKey(P384.Signing.PrivateKey())
        case .ed25519: Certificate.PrivateKey(Curve25519.Signing.PrivateKey())
        case .rsa2048: Certificate.PrivateKey(try _RSA.Signing.PrivateKey(keySize: .bits2048))
        case .rsa4096: Certificate.PrivateKey(try _RSA.Signing.PrivateKey(keySize: .bits4096))
        }
    }

    private static func privateKeyPEM(key: Certificate.PrivateKey, algorithm: KeyAlgorithm) throws -> String {
        try key.serializeAsPEM().pemString
    }

    static func loadPrivateKey(algorithm: KeyAlgorithm, tag: String) throws -> Certificate.PrivateKey {
        let pem = try KeychainService.loadString(tag: tag)
        return try Certificate.PrivateKey(pemEncoded: pem)
    }

    // MARK: - Helpers

    private static func distinguishedName(
        commonName: String, organization: String, country: String?
    ) throws -> DistinguishedName {
        try DistinguishedName {
            if let country, !country.isEmpty {
                CountryName(country)
            }
            if !organization.isEmpty {
                OrganizationName(organization)
            }
            CommonName(commonName)
        }
    }

    private static func signatureAlgorithm(for algorithm: KeyAlgorithm) -> Certificate.SignatureAlgorithm {
        switch algorithm {
        case .ecdsaP256: .ecdsaWithSHA256
        case .ecdsaP384: .ecdsaWithSHA384
        case .ed25519: .ed25519
        case .rsa2048, .rsa4096: .sha256WithRSAEncryption
        }
    }

    private static func serialNumber(_ value: Int) -> Certificate.SerialNumber {
        // Random 64-bit suffix keeps serials unique even if a counter is reused.
        var bytes = withUnsafeBytes(of: UInt64(max(value, 1)).bigEndian, Array.init)
        bytes.append(contentsOf: (0..<8).map { _ in UInt8.random(in: 0...255) })
        return Certificate.SerialNumber(bytes: ArraySlice(bytes.drop { $0 == 0 }))
    }

    private static func ipOctets(_ ip: String) throws -> ASN1OctetString {
        var v4 = in_addr()
        if inet_pton(AF_INET, ip, &v4) == 1 {
            let bytes = withUnsafeBytes(of: v4.s_addr, Array.init)
            return ASN1OctetString(contentBytes: ArraySlice(bytes))
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, ip, &v6) == 1 {
            let bytes = withUnsafeBytes(of: v6, Array.init)
            return ASN1OctetString(contentBytes: ArraySlice(bytes))
        }
        throw CAServiceError.invalidIPAddress(ip)
    }
}
