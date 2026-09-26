import CryptoKit
import Foundation

// Verify with the PUBLIC key embedded in the app, never by reading the private key.
do {
    guard CommandLine.arguments.count == 4 else {
        throw NSError(domain: "Usage: verify_update_signature.swift Info.plist archive signature", code: 1)
    }
    let plist = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
    guard let encodedKey = info?["SUPublicEDKey"] as? String,
          let keyData = Data(base64Encoded: encodedKey),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "Invalid public key or signature", code: 2)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "Invalid update signature", code: 3)
    }
    print("PASS: firma EdDSA verificata con la chiave pubblica dell’app.")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
