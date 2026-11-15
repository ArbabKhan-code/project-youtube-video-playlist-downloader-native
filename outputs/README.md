# YouTube Downloader for macOS

A native Apple Silicon macOS app that uses yt-dlp and FFmpeg to download YouTube videos and playlists.

## Install and launch

1. Expand `YouTube Downloader-macOS.zip`.
2. Move `YouTube Downloader.app` to Applications, or open it from the expanded folder.
3. Install dependencies if they are not already present: `brew install yt-dlp ffmpeg`.
4. Connect the external SSD named **Arbab Mac SSD**. The app only writes to `/Volumes/Arbab Mac SSD/YouTube Downloads/` and stops with an error if that volume is unavailable.

Downloads are organized into `Individual Videos/<video title>/` and `Playlists/<playlist title>/`. The app remembers the last selected quality and format on this Mac.

For content the signed-in account is already entitled to watch (including channel-member videos), turn on **Use signed-in browser** and choose Safari, Chrome, Firefox, Brave, Edge, or Chromium. yt-dlp reads the selected browser's cookies locally for metadata and downloads. The setting is off by default. Do not enable it for an account without access; this feature does not join memberships or bypass access checks.

Each video card also has **Find free licensed copies**, which opens an Internet Archive search filtered to video items marked Creative Commons or public domain. Check the item page's license and rights before downloading. Paste a chosen Internet Archive `/details/...` link into the app; yt-dlp will download supported Archive.org videos into the individual-video folder.

If YouTube returns HTTP 403, use **Update yt-dlp** in the app menu, then retry the failed item. The update action uses Homebrew when available. If 403 continues after updating, YouTube may require a current PO token or authorized sign-in for that stream; the app will show this in the download status and technical log.

The app bundle targets Apple Silicon and macOS 13 or newer. This local build is ad-hoc signed and is not notarized for public distribution.

## Development

The Swift sources and `Package.swift` are in the project folder. Build with `swift build -c release`.

## Notes

Use downloads only where you have the rights and authorization to do so. The app does not bypass DRM or access controls. A partially failed playlist keeps completed files in place and displays a failure message; retrying skips files already downloaded.
