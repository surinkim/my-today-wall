# MyTodayWall

[한국어](README.ko.md)

A small macOS menu bar app that downloads the Bing image of the day and sets it as the wallpaper on every connected display. Built as a lightweight replacement for the official Bing Wallpaper app.

- Downloads the last 8 days of images in 4K (UHD) on launch and on refresh, and sets the newest one automatically
- Step through downloaded images with Previous / Next and apply them instantly
- Search the pictured place in your browser
- Reapplies automatically when displays are connected or disconnected and when you switch desktops (Spaces)
- Launches at login and cleans up old images (90 days by default)

Design notes and decisions are in [SPEC.md](SPEC.md).

## Requirements

- macOS 15.0 (Sequoia) or later
- Universal build (Apple Silicon and Intel)

## Install

1. Download `MyTodayWall.zip` from [Releases](https://github.com/surinkim/my-today-wall/releases) and unzip it
2. Move `MyTodayWall.app` to the Applications folder. The login item is registered automatically only when the app runs from `/Applications`
3. The app is ad-hoc signed and not notarized, so remove the quarantine flag

   ```bash
   xattr -dr com.apple.quarantine /Applications/MyTodayWall.app
   ```

4. Launch it. On first launch it registers itself as a login item, downloads images and changes the wallpaper

   ```bash
   open /Applications/MyTodayWall.app
   ```

If the official Bing Wallpaper app is also running, the two apps overwrite each other's wallpaper. Uninstall it or turn off its launch at login.

## Usage

Click the photo icon in the menu bar to open the popover.

| Item | Action |
| --- | --- |
| Thumbnail / `Search this place` | Opens Bing search results for the pictured place in your default browser |
| `Previous` / `Next` | Steps through downloaded images by date and applies them |
| `Refresh` | Downloads new images and switches to the newest one if a new image is out. If not, keeps the image you picked |
| `Launch at login` | Same setting as System Settings → General → Login Items |
| `Keep images for` | 30 / 90 / 180 days / Forever. The current wallpaper is never deleted, even past the limit |

- The image region follows your system language and region (for example `en-US` or `ko-KR`). Regions Bing does not serve get the worldwide image
- Bing publishes a new image once a day; the time depends on the region (around local midnight for most)
- The app checks only on launch and when you press Refresh. It does not switch by itself after waking from sleep or at midnight
- The UI is in English and Korean, following the system language

## Files

| Path | Contents |
| --- | --- |
| `~/Pictures/MyTodayWall/` | Downloaded images (`yyyyMMdd_Name.jpg`) and `index.json` (image list, current image) |
| `/Applications/MyTodayWall.app` | The app |

## Troubleshooting

Errors are logged with `os.Logger` (subsystem `kr.pe.corecode.MyTodayWall`). View past logs in Terminal:

```bash
log show --last 1d --predicate 'subsystem == "kr.pe.corecode.MyTodayWall"' --style compact
```

To watch live, search Console.app for subsystem `kr.pe.corecode.MyTodayWall`, turn on Action → Include Info Messages, then press Start.

| Log message | Cause |
| --- | --- |
| `Failed to fetch Bing archive` | Network problem, or a firewall blocking bing.com |
| `Failed to download image` | An image file failed to download |
| `Failed to set wallpaper (display name)` | Could not set the wallpaper on that display |
| `Failed to register login item` | Could not register the login item |

## Build from source

Requires Xcode 16 or later. No third-party dependencies.

```bash
git clone https://github.com/surinkim/my-today-wall.git
```

```bash
cd my-today-wall && xcodebuild -project MyTodayWall.xcodeproj -scheme MyTodayWall -configuration Release -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

The result is `build/Build/Products/Release/MyTodayWall.app`. If the active developer directory is Command Line Tools, prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

To check the core logic (download, storage, auto-select, previous/next, retention) against the real API without launching the app, run the script below. It works in a temp folder and does not change your wallpaper.

```bash
scripts/check-core.sh
```

## Uninstall

1. In the popover, turn off `Launch at login` and press `Quit`
2. Move `/Applications/MyTodayWall.app` to the Trash
3. To remove downloaded images too, move `~/Pictures/MyTodayWall/` to the Trash

## Notes

MyTodayWall uses `HPImageArchive.aspx`, an undocumented Bing endpoint. Its format may change at any time, and the app may stop working until it is updated.

This repository contains only the app's code, no Bing images. Images are downloaded by each user's own app, are copyrighted by their respective photographers and agencies, and are meant for personal wallpaper use only, as stated in Bing's response. Do not redistribute them.

## License

[MIT](LICENSE)

## Disclaimer

MyTodayWall is an independent project and is not affiliated with or endorsed by Microsoft. Bing is a trademark of Microsoft Corporation. All images are copyrighted by their respective owners.
