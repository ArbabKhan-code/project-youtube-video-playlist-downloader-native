import AppKit
import Foundation
import UserNotifications

@MainActor final class DownloadManager: ObservableObject {
    @Published var jobs: [DownloadJob] = []
    @Published var history: [DownloadRecord] = []
    @Published var ytDlpPath: String? = DownloadManager.findTool("yt-dlp")
    @Published var ffmpegPath: String? = DownloadManager.findTool("ffmpeg")
    @Published var isInspecting = false
    @Published var isUpdatingYtDlp = false
    @Published var useBrowserCookies = false
    @Published var cookieBrowser = "safari"
    @Published var alertMessage: String?
    @Published var inputURL = ""
    @Published var search = ""
    @Published var selectedTab = 0
    @Published var playlistMode = true
    @Published var showIndexChoice = false
    @Published var expandedLogs: Set<UUID> = []
    @Published var qualityRaw = VideoQuality.best.rawValue
    @Published var formatRaw = DownloadFormat.mp4.rawValue
    private var activeCount = 0
    private var terminationObserver: NSObjectProtocol?
    private let historyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/YouTubeDownloader/history.json")

    init() {
        qualityRaw = UserDefaults.standard.string(forKey: "quality") ?? VideoQuality.best.rawValue
        formatRaw = UserDefaults.standard.string(forKey: "format") ?? DownloadFormat.mp4.rawValue
        useBrowserCookies = UserDefaults.standard.bool(forKey: "useBrowserCookies")
        cookieBrowser = UserDefaults.standard.string(forKey: "cookieBrowser") ?? "safari"
        if let data = try? Data(contentsOf: historyURL), let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) { history = records }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if (try? StorageManager.requireMounted()) != nil {
            try? FileManager.default.createDirectory(at: StorageManager.root.appendingPathComponent("Individual Videos", isDirectory: true), withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: StorageManager.root.appendingPathComponent("Playlists", isDirectory: true), withIntermediateDirectories: true)
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopProcessesForTermination() }
        }
    }

    func setQuality(_ value: String) { qualityRaw = value; UserDefaults.standard.set(value, forKey: "quality") }
    func setFormat(_ value: String) { formatRaw = value; UserDefaults.standard.set(value, forKey: "format") }
    func setCookieBrowser(_ value: String) { cookieBrowser = value; UserDefaults.standard.set(value, forKey: "cookieBrowser") }
    func setUseBrowserCookies(_ value: Bool) { useBrowserCookies = value; UserDefaults.standard.set(value, forKey: "useBrowserCookies") }
    func containsPlaylist(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), let items = components.queryItems else { return false }
        return items.contains { $0.name == "list" }
    }
    func containsVideoIndex(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), let items = components.queryItems else { return false }
        return items.contains { $0.name == "index" || $0.name == "v" }
    }

    nonisolated static func findTool(_ name: String) -> String? {
        let candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var ready: Bool { ytDlpPath != nil && ffmpegPath != nil }

    func inspect(url: String, preferPlaylist: Bool = true, quality: VideoQuality, format: DownloadFormat) async {
        guard let tool = ytDlpPath else { alertMessage = "yt-dlp is not installed. Install it with Homebrew (brew install yt-dlp), then check again."; return }
        guard validMediaURL(url) else { alertMessage = "Enter a YouTube link or a supported Internet Archive video link."; return }
        isInspecting = true
        defer { isInspecting = false }
        do {
            let selectedCookieBrowser = useBrowserCookies ? cookieBrowser : nil
            let info = try await metadata(url: url, tool: tool, playlist: preferPlaylist, cookieBrowser: selectedCookieBrowser)
            let playlist = preferPlaylist && (info.entries != nil || URLComponents(string: url)?.queryItems?.contains(where: { $0.name == "list" }) == true)
            let title = info.title ?? info.entries?.first?.title ?? "YouTube Download"
            let job = DownloadJob(url: url, title: title, thumbnail: info.thumbnail.flatMap(URL.init(string:)), kind: playlist ? .playlist : .video, quality: quality, format: format, cookieBrowser: selectedCookieBrowser)
            job.videoTotal = info.playlist_count ?? info.entries?.count ?? (playlist ? 0 : 1)
            job.state = .queued
            job.message = playlist ? "\(job.videoTotal > 0 ? "\(job.videoTotal) videos · " : "")Ready to download" : "Ready to download"
            jobs.insert(job, at: 0)
            pumpQueue()
        } catch { alertMessage = userMessage(for: error) }
    }

    private func validMediaURL(_ raw: String) -> Bool {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), let host = c.host?.lowercased() else { return false }
        let supportedHosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be", "archive.org", "www.archive.org"]
        return supportedHosts.contains(host) && ["http", "https"].contains(c.scheme?.lowercased() ?? "")
    }

    private func metadata(url: String, tool: String, playlist: Bool, cookieBrowser: String?) async throws -> MediaInfo {
        try await Task.detached(priority: .userInitiated) {
            try Self.runMetadata(url: url, tool: tool, playlist: playlist, cookieBrowser: cookieBrowser)
        }.value
    }

    nonisolated private static func runMetadata(url: String, tool: String, playlist: Bool, cookieBrowser: String?) throws -> MediaInfo {
        let process = Process(); process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["--dump-single-json", "--no-warnings"] + (cookieBrowser.map { ["--cookies-from-browser", $0] } ?? []) + (playlist ? ["--flat-playlist"] : ["--no-playlist"]) + [url]
        let out = Pipe(), err = Pipe(); process.standardOutput = out; process.standardError = err
        try process.run()
        let output = out.fileHandleForReading.readDataToEndOfFile(); let error = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EngineError.output(String(data: error, encoding: .utf8) ?? "Metadata lookup failed") }
        return try JSONDecoder().decode(MediaInfo.self, from: output)
    }

    private func pumpQueue() {
        while activeCount < 2, let job = jobs.first(where: { $0.state == .queued }) { start(job) }
    }

    private func start(_ job: DownloadJob) {
        guard let tool = ytDlpPath else { job.state = .failed; job.message = "yt-dlp is not installed"; return }
        do {
            try StorageManager.requireMounted()
            job.state = .preparing; job.message = "Preparing download…"
            let folder = try StorageManager.folder(kind: job.kind, title: job.title); job.targetFolder = folder
            var args = ["--no-warnings", "--newline", "--no-overwrites", "--continue", "--ignore-errors", "--retries", "10", "--fragment-retries", "10", "--extractor-retries", "3", "--progress-template", "download:__YT_PROGRESS__%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress.filename)s|%(progress.downloaded_bytes)s", "--print", "before_dl:__YT_ITEM__%(playlist_index)s|%(n_entries)s|%(title)s"]
            if let ffmpegPath { args += ["--ffmpeg-location", ffmpegPath] }
            if let browser = job.cookieBrowser { args += ["--cookies-from-browser", browser] }
            if job.kind == .video { args.append("--no-playlist") }
            args += ["-P", folder.path, "-o", "%(playlist_index&{} - |)s%(title)s [%(id)s].%(ext)s"]
            if job.format == .mp3 { args += ["-x", "--audio-format", "mp3", "--audio-quality", "0"] }
            else {
                let height: String? = switch job.quality { case .best: nil; case .p1080: "1080"; case .p720: "720"; case .p480: "480"; case .p360: "360" }
                let cap = height.map { "[height<=\($0)]" } ?? ""
                let video = "bv*\(cap)"
                let formatSelector = job.format == .mp4
                    ? "\(video)[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/\(video)+ba/b\(cap)"
                    : "\(video)+ba/b\(cap)"
                let container = job.format.rawValue.lowercased()
                args += ["-f", formatSelector, "--merge-output-format", container, "--remux-video", container]
            }
            args.append(job.url)
            let process = Process(); process.executableURL = URL(fileURLWithPath: tool); process.arguments = args
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            job.process = process
            pipe.fileHandleForReading.readabilityHandler = { [weak self, weak job] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.consume(text, for: job) }
            }
            process.terminationHandler = { [weak self, weak job] process in
                pipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in self?.finished(job, status: process.terminationStatus) }
            }
            try process.run(); activeCount += 1; job.state = .downloading; job.message = "Downloading"
        } catch { job.process = nil; job.state = .failed; job.message = userMessage(for: error); job.technicalLog = String(describing: error) }
    }

    private func consume(_ text: String, for job: DownloadJob?) {
        guard let job else { return }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            job.technicalLog = String((job.technicalLog + line + "\n").suffix(16_000))
            if line.hasPrefix("__YT_PROGRESS__") {
                let fields = String(line.dropFirst("__YT_PROGRESS__".count)).components(separatedBy: "|")
                if fields.count >= 4 {
                    job.progress = Double(fields[0].filter { $0.isNumber || $0 == "." }) ?? job.progress
                    job.speed = fields[1].isEmpty ? "—" : fields[1]
                    job.eta = fields[2].isEmpty ? "—" : fields[2]
                    job.currentFile = URL(fileURLWithPath: fields[3]).lastPathComponent
                    if fields.count >= 5, let bytes = Int64(fields[4]) { job.downloadedSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
                }
            } else if line.hasPrefix("__YT_ITEM__") {
                let fields = String(line.dropFirst("__YT_ITEM__".count)).components(separatedBy: "|")
                if fields.count >= 3 {
                    job.videoIndex = Int(fields[0]) ?? (job.videoIndex + 1)
                    job.videoTotal = Int(fields[1]) ?? job.videoTotal
                    job.currentFile = fields[2]
                    job.downloadedSize = "—"
                    job.message = job.kind == .playlist && job.videoTotal > 0 ? "Video \(job.videoIndex) of \(job.videoTotal)" : "Downloading"
                    job.progress = 0
                }
            }
        }
    }

    private func finished(_ job: DownloadJob?, status: Int32) {
        activeCount = max(0, activeCount - 1)
        guard let job else { pumpQueue(); return }
        job.process = nil
        if job.state == .cancelled { job.message = "Download cancelled" }
        else if job.state == .paused { job.state = .failed; job.message = "Download stopped unexpectedly" }
        else if let folder = job.targetFolder {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
            job.outputPaths = files.filter { file in
                guard !file.lastPathComponent.hasSuffix(".part") else { return false }
                return ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
            }
            if job.outputPaths.isEmpty {
                job.state = .failed
                job.message = status == 0 ? "No completed output file was found." : failureMessage(for: job)
            } else {
                job.state = status == 0 ? .completed : .failed
                job.progress = status == 0 ? 100 : job.progress
                job.message = status == 0 ? "Download complete · \(folder.path)" : failureMessage(for: job, folder: folder)
                let record = DownloadRecord(id: UUID(), title: job.title, path: folder.path, date: Date(), kind: job.kind)
                history.insert(record, at: 0); persistHistory()
                if status == 0 { notify(job.title) }
            }
        } else { job.state = .failed; job.message = "Download failed. Check the technical log for details." }
        pumpQueue()
    }

    func cancel(_ job: DownloadJob) { job.state = .cancelled; job.process?.terminate(); if job.process == nil { pumpQueue() } }
    func pause(_ job: DownloadJob) { signal(job, signal: "-STOP", state: .paused, message: "Paused") }
    func resume(_ job: DownloadJob) { signal(job, signal: "-CONT", state: .downloading, message: "Downloading") }
    private func signal(_ job: DownloadJob, signal: String, state: DownloadState, message: String) {
        guard let pid = job.process?.processIdentifier else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/kill"); p.arguments = [signal, "\(pid)"]; try? p.run(); job.state = state; job.message = message
    }
    func retry(_ job: DownloadJob) { job.state = .queued; job.progress = 0; job.message = "Waiting in queue"; pumpQueue() }
    func forget(_ record: DownloadRecord) { history.removeAll { $0.id == record.id }; persistHistory() }
    func remove(_ job: DownloadJob) { jobs.removeAll { $0.id == job.id } }
    private func stopProcessesForTermination() {
        for job in jobs where job.state.isActive {
            job.state = .cancelled
            job.process?.terminate()
        }
    }
    func checkTools() {
        ytDlpPath = Self.findTool("yt-dlp"); ffmpegPath = Self.findTool("ffmpeg")
        if !ready { alertMessage = "yt-dlp and FFmpeg are required. Install Homebrew, then run: brew install yt-dlp ffmpeg" }
    }
    private func failureMessage(for job: DownloadJob, folder: URL? = nil) -> String {
        let has403 = job.technicalLog.localizedCaseInsensitiveContains("HTTP Error 403")
        let needsMembership = job.technicalLog.localizedCaseInsensitiveContains("members-only") || job.technicalLog.localizedCaseInsensitiveContains("join this channel")
        let destination = folder.map { " Completed files remain in \($0.path)." } ?? ""
        if needsMembership {
            return "This video is for channel members. Enable signed-in browser access and select a browser account with an active membership. The app cannot unlock memberships or bypass YouTube access checks.\(destination)"
        }
        if has403 {
            return "YouTube refused the media request (HTTP 403). Update yt-dlp from the menu and retry. If it continues, the selected stream may require YouTube-issued verification or sign-in.\(destination)"
        }
        if job.technicalLog.localizedCaseInsensitiveContains("space") { return "Not enough storage space on the external SSD.\(destination)" }
        return "Some items failed. Check the technical log for details.\(destination)"
    }

    func updateYtDlp() async {
        guard let tool = ytDlpPath else { checkTools(); return }
        isUpdatingYtDlp = true
        defer { isUpdatingYtDlp = false }
        let result = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let process = Process()
            if let brew = Self.findTool("brew") {
                process.executableURL = URL(fileURLWithPath: brew)
                process.arguments = ["upgrade", "yt-dlp"]
            } else {
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = ["-U"]
            }
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            do {
                try process.run()
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, String(data: output, encoding: .utf8) ?? "")
            } catch { return (-1, error.localizedDescription) }
        }.value
        if result.0 == 0 {
            alertMessage = "yt-dlp is up to date. Retry the failed download. If YouTube still returns 403, that stream may require YouTube-issued verification or authorized sign-in."
            ytDlpPath = Self.findTool("yt-dlp")
        } else {
            let detail = result.1.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").suffix(4).joined(separator: "\n")
            alertMessage = detail.isEmpty ? "yt-dlp could not be updated. Check the technical log and Homebrew installation." : "yt-dlp could not be updated:\n\(detail)"
        }
    }
    private func persistHistory() {
        try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: historyURL, options: .atomic) }
    }
    private func notify(_ title: String) {
        let content = UNMutableNotificationContent(); content.title = "Download complete"; content.body = title
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    private func userMessage(for error: Error) -> String {
        let detail = String(describing: error).localizedLowercase
        if detail.contains("members-only") || detail.contains("join this channel") {
            return "This video is for channel members. Enable signed-in browser access and select a browser account with an active membership. The app cannot unlock memberships or bypass YouTube access checks."
        }
        if detail.contains("http error 403") {
            return "YouTube refused access while reading this link (HTTP 403). Update yt-dlp, then retry. If the video requires membership, enable signed-in browser access for an account that already has access."
        }
        if let message = (error as? LocalizedError)?.errorDescription { return message }
        return "Could not inspect the link. Check your network connection and the technical log."
    }
    private enum EngineError: LocalizedError {
        case output(String)
        var errorDescription: String? {
            switch self { case .output: return "yt-dlp could not read this link. Check the URL, account access, and network connection." }
        }
    }
}
