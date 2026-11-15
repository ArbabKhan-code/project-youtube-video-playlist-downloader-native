import SwiftUI

struct DashboardView: View {
    @ObservedObject var manager: DownloadManager
    private var inputURL: String { manager.inputURL }
    private var search: String { manager.search }
    private var selectedTab: Int { manager.selectedTab }
    private var playlistMode: Bool { manager.playlistMode }
    private var showIndexChoice: Bool { manager.showIndexChoice }
    private var quality: VideoQuality { VideoQuality(rawValue: manager.qualityRaw) ?? .best }
    private var format: DownloadFormat { DownloadFormat(rawValue: manager.formatRaw) ?? .mp4 }
    private var inputBinding: Binding<String> { Binding(get: { manager.inputURL }, set: { manager.inputURL = $0 }) }
    private var searchBinding: Binding<String> { Binding(get: { manager.search }, set: { manager.search = $0 }) }
    private var playlistBinding: Binding<Bool> { Binding(get: { manager.playlistMode }, set: { manager.playlistMode = $0 }) }
    private var choiceBinding: Binding<Bool> { Binding(get: { manager.showIndexChoice }, set: { manager.showIndexChoice = $0 }) }
    private var isPlaylistURL: Bool { manager.containsPlaylist(inputURL) }
    private var hasIndex: Bool { manager.containsVideoIndex(inputURL) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    inputCard
                    settingsRow
                    downloadsSection
                }
                .padding(.horizontal, 32)
                .padding(.top, 25)
                .padding(.bottom, 30)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(nil)
        .alert("YouTube Downloader", isPresented: Binding(get: { manager.alertMessage != nil }, set: { if !$0 { manager.alertMessage = nil } })) {
            Button("OK", role: .cancel) { manager.alertMessage = nil }
        } message: { Text(manager.alertMessage ?? "") }
        .confirmationDialog("This link includes a playlist and a specific video", isPresented: choiceBinding, titleVisibility: .visible) {
            Button("Download This Video") { submit(playlist: false) }
            Button("Download Complete Playlist") { submit(playlist: true) }
        } message: { Text("Choose which content to download.") }
        .onAppear { manager.checkTools() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack { RoundedRectangle(cornerRadius: 11).fill(Color.red.gradient).frame(width: 36, height: 36); Image(systemName: "arrow.down.to.line.compact").font(.system(size: 17, weight: .bold)).foregroundStyle(.white) }
            Text("YouTube Downloader").font(.system(size: 16, weight: .semibold))
            Spacer()
            Button { StorageManager.open(StorageManager.root) } label: { Label("Open Downloads", systemImage: "folder") }
                .buttonStyle(.bordered).controlSize(.small)
            Menu {
                Button("Check yt-dlp and FFmpeg") { manager.checkTools() }
                Button(manager.isUpdatingYtDlp ? "Updating yt-dlp…" : "Update yt-dlp") { Task { await manager.updateYtDlp() } }
                    .disabled(manager.isUpdatingYtDlp)
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 26).padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Save something worth keeping.").font(.system(size: 28, weight: .bold, design: .rounded))
            HStack(spacing: 6) {
                Text("Paste a YouTube link to get started.").foregroundStyle(.secondary)
                Circle().fill(manager.ready ? .green : .orange).frame(width: 6, height: 6).padding(.leading, 5)
                Text(manager.ready ? "Ready" : "Setup needed").font(.caption).foregroundStyle(.secondary)
            }.font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VIDEO OR PLAYLIST URL").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("https://www.youtube.com/watch?v=…", text: inputBinding)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .onChange(of: inputURL) { newValue in
                        let hasList = manager.containsPlaylist(newValue)
                        manager.playlistMode = hasList
                    }
                Button { if let text = NSPasteboard.general.string(forType: .string) { manager.inputURL = text } } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button { manager.inputURL = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help("Clear URL")
            }
            .padding(13)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            HStack {
                if isPlaylistURL {
                    Label("Playlist detected", systemImage: "music.note.list").font(.system(size: 12, weight: .medium)).foregroundStyle(.blue)
                    if !hasIndex {
                        Toggle("Download full playlist", isOn: playlistBinding).toggleStyle(.switch).controlSize(.mini).font(.caption).labelsHidden()
                        Text("Full playlist").font(.caption).foregroundStyle(.secondary)
                    }
                } else if !inputURL.isEmpty {
                    Label("Individual video", systemImage: "play.rectangle").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                } else { Text("Supports videos and playlists").font(.caption).foregroundStyle(.tertiary) }
                Spacer()
                Button(action: startDownload) {
                    HStack(spacing: 8) { if manager.isInspecting { ProgressView().controlSize(.small) }; Text(manager.isInspecting ? "Looking up…" : "Download"); if !manager.isInspecting { Image(systemName: "arrow.down") } }
                        .font(.system(size: 13, weight: .semibold)).frame(minWidth: 128)
                }
                .buttonStyle(.borderedProminent).tint(Color(red: 0.83, green: 0.12, blue: 0.16))
                .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isInspecting)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private var settingsRow: some View {
        HStack(spacing: 12) {
            setting(title: "QUALITY", selection: Binding(get: { manager.qualityRaw }, set: { manager.setQuality($0) }), options: VideoQuality.allCases.map(\.rawValue), icon: "4k.tv")
            setting(title: "FORMAT", selection: Binding(get: { manager.formatRaw }, set: { manager.setFormat($0) }), options: DownloadFormat.allCases.map(\.rawValue), icon: "film")
            memberAccessSetting
        }
    }

    private var memberAccessSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEMBER ACCESS").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Toggle("Use signed-in browser", isOn: Binding(get: { manager.useBrowserCookies }, set: { manager.setUseBrowserCookies($0) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                Picker("Browser", selection: Binding(get: { manager.cookieBrowser }, set: { manager.setCookieBrowser($0) })) {
                    Text("Safari").tag("safari"); Text("Chrome").tag("chrome"); Text("Firefox").tag("firefox")
                    Text("Brave").tag("brave"); Text("Edge").tag("edge"); Text("Chromium").tag("chromium")
                }
                .labelsHidden().pickerStyle(.menu).disabled(!manager.useBrowserCookies)
                Image(systemName: "info.circle").foregroundStyle(.tertiary)
                    .help("When enabled, yt-dlp reads sign-in cookies from this browser. Use an account that already has access. YouTube may restrict accounts used with download tools.")
            }
            .padding(.horizontal, 9).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func setting(title: String, selection: Binding<String>, options: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
                Picker(title, selection: selection) { ForEach(options, id: \.self) { Text($0).tag($0) } }
                    .labelsHidden().pickerStyle(.menu).tint(.primary)
            }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private var downloadsSection: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 16) {
                    tab("Downloads", count: manager.jobs.filter { $0.state.isActive || $0.state == .queued }.count, index: 0)
                    tab("History", count: manager.history.count, index: 1)
                }
                Spacer()
                if selectedTab == 1, !manager.history.isEmpty {
                    TextField("Search history", text: searchBinding).textFieldStyle(.roundedBorder).frame(width: 170)
                }
            }
            if selectedTab == 0 {
                if manager.jobs.isEmpty { emptyState }
                else { ForEach(manager.jobs) { DownloadCard(job: $0, manager: manager) } }
            } else {
                let filtered = manager.history.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
                if filtered.isEmpty { emptyState }
                else { ForEach(filtered) { record in HistoryCard(record: record) { manager.forget(record) } } }
            }
        }
    }

    private func tab(_ label: String, count: Int, index: Int) -> some View {
        Button { manager.selectedTab = index } label: {
            HStack(spacing: 6) { Text(label); if count > 0 { Text("\(count)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.primary.opacity(0.08), in: Capsule()) } }
                .font(.system(size: 14, weight: selectedTab == index ? .semibold : .regular)).foregroundStyle(selectedTab == index ? .primary : .secondary)
                .padding(.vertical, 7).overlay(alignment: .bottom) { if selectedTab == index { Capsule().fill(Color.red).frame(height: 2) } }
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: selectedTab == 0 ? "arrow.down.circle" : "clock.arrow.circlepath").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(selectedTab == 0 ? "Your downloads will appear here" : "Completed downloads will show up here")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text(selectedTab == 0 ? "Paste a YouTube link above to begin." : "Your download history is saved on this Mac.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }

    private func startDownload() {
        if isPlaylistURL && hasIndex { manager.showIndexChoice = true }
        else { submit(playlist: isPlaylistURL && playlistMode) }
    }
    private func submit(playlist: Bool) { Task { await manager.inspect(url: inputURL.trimmingCharacters(in: .whitespacesAndNewlines), preferPlaylist: playlist, quality: quality, format: format) } }
}

private struct DownloadCard: View {
    @ObservedObject var job: DownloadJob
    @ObservedObject var manager: DownloadManager
    private var expanded: Bool { manager.expandedLogs.contains(job.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(job.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(job.kind == .playlist ? "PLAYLIST" : "VIDEO").font(.system(size: 9, weight: .bold)).tracking(0.5).padding(.horizontal, 6).padding(.vertical, 3).background(Color.primary.opacity(0.07), in: Capsule()).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(job.state.label).font(.system(size: 11, weight: .medium)).foregroundStyle(stateColor)
                    }
                    Text(job.message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    if job.state == .downloading || job.state == .paused {
                        ProgressView(value: job.overallProgress, total: 100).tint(.red)
                        HStack(spacing: 12) {
                            if job.kind == .playlist, job.videoTotal > 0 {
                                Text("Playlist \(job.overallProgress, specifier: "%.1f")% · Video \(job.progress, specifier: "%.1f")%")
                            } else { Text("\(job.progress, specifier: "%.1f")%") }
                            Text(job.downloadedSize)
                            if !job.speed.isEmpty { Text(job.speed) }
                            if job.eta != "—" { Text("ETA \(job.eta)") }
                            Spacer()
                            if !job.currentFile.isEmpty { Text(job.currentFile).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .trailing) }
                        }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 8) {
                action("Find free licensed copies", icon: "magnifyingglass") { StorageManager.searchLicensedAlternatives(for: job.title) }
                if job.state == .downloading { action("Pause", icon: "pause.fill") { manager.pause(job) } }
                if job.state == .paused { action("Resume", icon: "play.fill") { manager.resume(job) } }
                if job.state.isActive || job.state == .queued { action("Cancel", icon: "xmark") { manager.cancel(job) } }
                if job.state == .failed || job.state == .cancelled { action("Retry", icon: "arrow.clockwise") { manager.retry(job) } }
                if job.state == .completed, let folder = job.targetFolder {
                    action("Open Folder", icon: "folder") { StorageManager.open(folder) }
                    action("Copy File Path", icon: "doc.on.doc") {
                        let path = job.outputPaths.first?.path ?? folder.path
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string)
                    }
                }
            Button { if expanded { manager.expandedLogs.remove(job.id) } else { manager.expandedLogs.insert(job.id) } } label: { Label(expanded ? "Hide log" : "Technical log", systemImage: "chevron.down").labelStyle(.titleAndIcon).font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(.tertiary)
                Spacer()
                if job.state == .completed || job.state == .cancelled { Button { manager.remove(job) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(.tertiary).help("Remove from list") }
            }
            if expanded {
                ScrollView { Text(job.technicalLog.isEmpty ? "No technical output yet." : job.technicalLog).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(9) }
                    .frame(height: 100).background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            }
            Text("Searches Internet Archive for Creative Commons and public-domain matches. Verify the rights on the item page before downloading.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
    private var thumbnail: some View {
        Group {
            if let url = job.thumbnail { AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }.frame(width: 100, height: 58).clipped().clipShape(RoundedRectangle(cornerRadius: 7)) }
            else { placeholder.frame(width: 100, height: 58).clipShape(RoundedRectangle(cornerRadius: 7)) }
        }
    }
    private var placeholder: some View { ZStack { Color.primary.opacity(0.06); Image(systemName: job.kind == .playlist ? "music.note.list" : "play.rectangle.fill").foregroundStyle(.secondary) } }
    private var stateColor: Color { switch job.state { case .completed: .green; case .failed: .red; case .downloading: .blue; case .paused: .orange; default: .secondary } }
    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View { Button(action: perform) { Label(title, systemImage: icon).font(.system(size: 10, weight: .medium)) }.buttonStyle(.bordered).controlSize(.mini) }
}

private struct HistoryCard: View {
    let record: DownloadRecord
    let forget: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind == .playlist ? "music.note.list" : "play.rectangle.fill").frame(width: 38, height: 38).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(record.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(record.date, style: .date).font(.caption).foregroundStyle(.tertiary)
            Button { StorageManager.open(URL(fileURLWithPath: record.path)) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Open folder")
            Button(action: forget) { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Remove from history")
        }
        .padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
    }
}
