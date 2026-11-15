import SwiftUI

@main
struct YouTubeDownloaderApp: App {
    @StateObject private var manager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            DashboardView(manager: manager)
                .frame(minWidth: 860, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
