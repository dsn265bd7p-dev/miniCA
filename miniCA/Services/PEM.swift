import Crypto
import Foundation
import SwiftASN1
import X509
import _CryptoExtras

enum PEMError: Error, LocalizedError {
    case invalidPEM
    case unsupportedKey

    var errorDescription: String? {
        switch self {
        case .invalidPEM: "The data is not valid PEM"
        case .unsupportedKey: "Unsupported key type"
        }
    }
}

/// PEM serialization helpers for certificates and private keys.
enum PEM {
    static func certToPEM(_ certificate: Certificate) throws -> String {
        try certificate.serializeAsPEM().pemString
    }

    static func certFromPEM(_ pem: String) throws -> Certificate {
        try Certificate(pemEncoded: pem)
    }

    static func keyToPEM(_ key: Certificate.PrivateKey) throws -> String {
        try key.serializeAsPEM().pemString
    }

    static func keyFromPEM(_ pem: String) throws -> Certificate.PrivateKey {
        try Certificate.PrivateKey(pemEncoded: pem)
    }

    /// SHA-256 fingerprint of the DER encoding, colon-separated uppercase hex.
    static func fingerprint(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let digest = SHA256.hash(data: Data(serializer.serializedBytes))
        return digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    static func fingerprint(pem: String) -> String {
        (try? fingerprint(certFromPEM(pem))) ?? "—"
    }
}
