import Foundation

enum DownloadKind: String, Codable { case video = "Individual Video", playlist = "Playlist" }
enum VideoQuality: String, CaseIterable, Codable { case best = "Best Available", p1080 = "1080p", p720 = "720p", p480 = "480p", p360 = "360p" }
enum DownloadFormat: String, CaseIterable, Codable { case mp4 = "MP4", mkv = "MKV", webm = "WebM", mp3 = "Audio Only (MP3)" }
enum DownloadState: String, Codable { case queued, preparing, downloading, paused, completed, failed, cancelled
    var label: String { rawValue.capitalized }
    var isActive: Bool { [.preparing, .downloading, .paused].contains(self) }
}

struct MediaInfo: Decodable {
    var id: String?
    var title: String?
    var thumbnail: String?
    var webpage_url: String?
    var playlist_count: Int?
    var entries: [Entry]?
    struct Entry: Decodable { var id: String?; var title: String?; var thumbnail: String? }
}

struct DownloadRecord: Codable, Identifiable {
    var id: UUID
    var title: String
    var path: String
    var date: Date
    var kind: DownloadKind
}

@MainActor final class DownloadJob: ObservableObject, Identifiable {
    let id = UUID()
    let url: String
    @Published var title: String
    @Published var thumbnail: URL?
    @Published var kind: DownloadKind
    @Published var state: DownloadState = .queued
    @Published var progress = 0.0
    @Published var speed = "—"
    @Published var eta = "—"
    @Published var downloadedSize = "—"
    @Published var currentFile = ""
    @Published var message = "Waiting in queue"
    @Published var technicalLog = ""
    @Published var targetFolder: URL?
    @Published var outputPaths: [URL] = []
    @Published var videoIndex = 0
    @Published var videoTotal = 0
    var overallProgress: Double {
        guard kind == .playlist, videoTotal > 0 else { return progress }
        return min(100, (Double(max(0, videoIndex - 1)) + progress / 100) / Double(videoTotal) * 100)
    }
    var process: Process?
    var quality: VideoQuality
    var format: DownloadFormat
    var cookieBrowser: String?

    init(url: String, title: String, thumbnail: URL?, kind: DownloadKind, quality: VideoQuality, format: DownloadFormat, cookieBrowser: String?) {
        self.url = url; self.title = title; self.thumbnail = thumbnail; self.kind = kind; self.quality = quality; self.format = format; self.cookieBrowser = cookieBrowser
    }
}
