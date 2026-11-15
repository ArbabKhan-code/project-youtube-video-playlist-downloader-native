# YouTube Downloader for macOS

A native SwiftUI app that uses `yt-dlp` and FFmpeg to download videos to an external SSD. It also offers an Internet Archive search filtered for items marked Creative Commons or public domain.

## Requirements

- macOS 13 or newer
- Apple Silicon release bundle (or Swift 5.10+ to build from source)
- Homebrew, `yt-dlp`, and FFmpeg
- External volume mounted at `/Volumes/Arbab Mac SSD`

Install the command-line tools with:

```sh
brew install yt-dlp ffmpeg
```

Build the app executable with:

```sh
swift build -c release
```

The packaged app is in [`outputs/YouTube Downloader-macOS.zip`](outputs/YouTube%20Downloader-macOS.zip). Expand it and move `YouTube Downloader.app` to Applications. The local bundle is ad-hoc signed and not notarized for public distribution.

## Downloads

The fixed destination is `/Volumes/Arbab Mac SSD/YouTube Downloads/`. Individual videos go in `Individual Videos/<title>/`; playlists go in `Playlists/<title>/`. The app checks that the named SSD is mounted and does not fall back to internal storage.

Video and playlist downloads use yt-dlp format selection and FFmpeg remuxing/merging. Audio-only downloads use yt-dlp's MP3 post-processing. yt-dlp is updated from the app menu on Homebrew installations.

## Signed-in access

The optional **Use signed-in browser** setting passes cookies from the chosen Safari, Chrome, Firefox, Brave, Edge, or Chromium profile to yt-dlp. It is off by default. Use only an account already entitled to view the content. The app does not join memberships, bypass access controls, or circumvent DRM.

## Free alternatives

**Find free licensed copies** opens Internet Archive search for videos marked Creative Commons or public domain. License metadata is provided by uploaders; check the item page and rights before downloading. Paste a supported Archive.org item URL into the app to download it.

## Notes

YouTube may change its access requirements. If yt-dlp reports HTTP 403, update yt-dlp and retry. Some streams require platform-issued verification or authorized sign-in. The app reports failed playlist items and continues where yt-dlp can.
