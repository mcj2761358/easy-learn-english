import Foundation

enum MediaSignature {
    static func forFile(url: URL) -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = attrs[.size] as? NSNumber
        let mdate = attrs[.modificationDate] as? Date
        var components = url.path
        if let size { components += "|\(size)" }
        if let mdate { components += "|\(mdate.timeIntervalSince1970)" }
        return components
    }
}
