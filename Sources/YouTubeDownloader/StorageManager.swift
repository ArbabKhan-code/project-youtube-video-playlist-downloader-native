import AppKit
import Foundation

enum StorageManager {
    static let volume = URL(fileURLWithPath: "/Volumes/Arbab Mac SSD", isDirectory: true)
    static var root: URL { volume.appendingPathComponent("YouTube Downloads", isDirectory: true) }

    static func requireMounted() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: volume.path, isDirectory: &isDirectory), isDirectory.boolValue,
              (try? volume.resourceValues(forKeys: [.volumeIsLocalKey])) != nil else { throw StorageError.driveMissing }
        let values = try volume.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        if let free = values.volumeAvailableCapacity, free < 100 * 1024 * 1024 { throw StorageError.lowSpace }
    }

    static func folder(kind: DownloadKind, title: String) throws -> URL {
        try requireMounted()
        let parent = root.appendingPathComponent(kind == .video ? "Individual Videos" : "Playlists", isDirectory: true)
        let url = parent.appendingPathComponent(sanitize(title), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r").union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String((cleaned.isEmpty ? "YouTube Download" : cleaned).prefix(150))
    }

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
    static func searchLicensedAlternatives(for title: String) {
        var components = URLComponents(string: "https://archive.org/search")!
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "")
        components.queryItems = [URLQueryItem(name: "query", value: "\"\(escapedTitle)\" AND mediatype:movies AND (licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)")]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
    enum StorageError: LocalizedError {
        case driveMissing, lowSpace
        var errorDescription: String? {
            switch self {
            case .driveMissing: return "The external SSD “Arbab Mac SSD” is not mounted. Connect it before downloading."
            case .lowSpace: return "The external SSD has less than 100 MB of free space."
            }
        }
    }
}
