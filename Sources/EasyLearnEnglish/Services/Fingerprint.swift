import Foundation
import CryptoKit

enum Fingerprint {
    static func forFile(url: URL) -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = attrs[.size] as? NSNumber
        let mdate = attrs[.modificationDate] as? Date

        var components = "\(url.path)"
        if let size = size { components += "|\(size)" }
        if let mdate = mdate { components += "|\(mdate.timeIntervalSince1970)" }

        let data = Data(components.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
