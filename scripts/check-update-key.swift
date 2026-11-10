// Checks that the private update key on standard input belongs to the public key passed as the
// only argument (SPARKLE_PUBLIC_KEY in scripts/config.sh). The release workflow runs it before
// signing, because an update signed with any other key would be refused by every installed copy.
//
// Usage: printf '%s' "$SPARKLE_PRIVATE_KEY" | swift scripts/check-update-key.swift "$SPARKLE_PUBLIC_KEY"
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: check-update-key.swift <public key>") }
let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
// Sparkle's key format: the base64 encoded 32-byte Ed25519 seed.
guard let seed = Data(base64Encoded: input), seed.count == 32,
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
    fail("the private update key is not a base64 encoded Ed25519 seed")
}
guard key.publicKey.rawRepresentation.base64EncodedString() == CommandLine.arguments[1] else {
    fail("the private update key does not belong to SPARKLE_PUBLIC_KEY in scripts/config.sh")
}
print("The private update key matches SPARKLE_PUBLIC_KEY.")
