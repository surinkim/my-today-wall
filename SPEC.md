# MyTodayWall design notes

## Overview

A macOS menu bar app that downloads the Bing image of the day, stores it locally, and sets it as the wallpaper on every connected display. It was written to replace the official Bing Wallpaper app after an update left its buttons unresponsive.

- Usage: wallpaper only, following the "wallpaper only" condition in Bing's response. The repository ships code, never images
- Target OS: macOS Sequoia 15.0 or later
- Displays: any number. When the set of connected displays changes, the image is applied to all of them automatically

| Item | Value |
| --- | --- |
| App display name | MyTodayWall |
| Xcode project and folder | `MyTodayWall` |
| GitHub repo | `my-today-wall` |
| Bundle ID | `kr.pe.corecode.MyTodayWall` |

## Tech stack

A Swift + SwiftUI menu bar app. Setting the wallpaper, listing displays and registering a login item are all native AppKit APIs; doing this in another language would need cgo or AppleScript workarounds.

| Item | Choice | Notes |
| --- | --- | --- |
| Language / UI | Swift 5.10+, SwiftUI `MenuBarExtra` | No Dock icon (`LSUIElement = YES`) |
| Setting the wallpaper | `NSWorkspace.setDesktopImageURL(_:for:options:)` | Called per screen (`NSScreen`) |
| Launch at login | `SMAppService.mainApp` | Official login item API, macOS 13+ |
| Networking | `URLSession` + `async/await` | No external dependencies |
| Storage | File system + `index.json` | No database needed |
| Localization | String Catalog (`Localizable.xcstrings`) | English base, Korean translation |
| Build | Xcode 16, ad-hoc signing (Sign to Run Locally) | Not notarized |

No third-party packages.

## Functional requirements

| ID | Feature | Acceptance |
| --- | --- | --- |
| F1 | Launch at login | Can be toggled from the menu; on by default |
| F2 | Download and store images | On launch and refresh, saves any of the last 8 days' images not yet stored, in UHD, with no duplicate downloads |
| F3 | Pick earlier images | Previous / Next step through stored images and apply them immediately; after a new image is out, launch or refresh selects the newest automatically |
| F4 | Multiple displays | Same image on every connected screen; reapplied automatically when displays are connected or disconnected |

## Architecture

```
[Menu bar UI]   [App launch]   [ScreenObserver]
      \              |               /
             [WallpaperService]
      /              |               \
[BingClient]    [ImageStore]    [WallpaperApplier]
```

All triggers (UI, launch, display changes) call `WallpaperService`, which coordinates fetching, storing and applying in order. The lower modules don't know about each other.

## Bing API

One call to `HPImageArchive.aspx` returns metadata for the last 8 days. It's an undocumented endpoint whose format can change, so parse failures are logged and the existing images are kept.

```
GET https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=en-US
```

| Parameter | Value | Meaning |
| --- | --- | --- |
| `idx` | 0 | Start from today (up to 7 days back) |
| `n` | 8 | Number of images, max 8 |
| `mkt` | System language + region, e.g. `en-US`, `ko-KR` | Market. `BingClient.systemMarket` builds it from `Locale.current`, falling back to `en-US`. Markets Bing doesn't serve get the worldwide (`ROW`) image, as do served markets on days without a local image |

| Response field | Use |
| --- | --- |
| `startdate` | Image date (YYYYMMDD), used as the storage key |
| `fullstartdate` | When the image went live. Differs by market (checked 2026-11-07: en-GB 00:00 UTC, de-DE 23:00 UTC, ja-JP 15:00 UTC, en-US and ko-KR 08:00 UTC) |
| `urlbase` | Image path prefix. `https://www.bing.com` + `urlbase` + `_UHD.jpg` = 4K original |
| `url` | 1920x1080 path. Fallback when UHD fails |
| `title`, `copyright` | Caption and credit shown in the popover, in the market's language |
| `copyrightlink` | Search link for the pictured place, opened by "Search this place" |
| `hsh` | Image hash, used for duplicate detection |
| `wp` | Whether the image may be used as wallpaper. Skipped when `false` |

## Local storage

Images are stored one file per date; the list and current state live in a single `index.json`.

```
~/Pictures/MyTodayWall/
├── 20260927_MichelSunset.jpg
├── 20260926_Kirkjufell.jpg
├── ...
└── index.json
```

- File name: `startdate` + `_` + the name between `OHR.` and `_` in `urlbase`. Sorting by file name is sorting by date
- Why `~/Pictures`: with the sandbox off it's accessible without permission prompts, and it's visible in Finder
- Write order: download to a temp file → rename when complete (atomic) → update `index.json`. If the app quits midway, no broken file ends up in the list
- Retention: images older than 90 days are deleted by default; the popover's retention menu changes this (30 / 90 / 180 days / forever). Cleanup runs right after downloading, and the `current` image is never deleted even past the limit, so the wallpaper file in use never disappears

```json
{
  "current": "20260927",
  "lastAutoDate": "20260927",
  "images": [
    { "date": "20260927", "file": "20260927_MichelSunset.jpg",
      "title": "...", "copyright": "...", "hsh": "...",
      "searchLink": "https://www.bing.com/search?q=..." }
  ]
}
```

`current` is the image set as wallpaper now; `lastAutoDate` is the `startdate` of the newest image last selected automatically.

## Picking earlier images

By default the newest image is applied automatically; Previous / Next switch to another. After a new image is out, launching or refreshing selects the newest again.

Why "today" isn't decided by the local date: each market switches images at its own time (see `fullstartdate` above; ko-KR switches in the late afternoon KST). Matching the local date to `startdate` would leave nothing to apply before the switch, so the rule is "the newest image downloaded".

Popover layout: thumbnail of the current image + caption and date, `Previous` · `Next` · `Refresh` buttons. Below that, the `Launch at login` toggle, the `Keep images for` picker and `Quit`.

Place search: clicking the thumbnail or `Search this place` opens `searchLink` (Bing `copyrightlink`) in the default browser. Images downloaded before this field existed get the link filled in on refresh if they're within the last 8 days; older ones fall back to a Bing search for the caption.

1. **Launch / refresh**: after downloading new images, if the newest image's date differs from `lastAutoDate`, apply it to all screens and set `lastAutoDate` to that date
2. **Refresh again with no new image**: the newest equals `lastAutoDate`, so the image the user picked stays
3. **Previous / Next**: step through stored images by date and apply immediately, updating only `current` in `index.json`. The buttons are disabled at the oldest and newest image (on a day today's image wasn't downloaded, the newest stored image is the end)

```swift
func onLaunchOrRefresh() async {
    await fetchAndStoreNew()
    if let latest = index.images.last, index.lastAutoDate != latest.date {
        select(latest)  // apply to all screens + update current
        index.lastAutoDate = latest.date
    }
    removeExpired()
    save()  // update index.json
}
```

## Multiple displays

The app loops over all of `NSScreen.screens`, so no per-setup configuration is needed.

```swift
func apply(_ url: URL) {
    let opts: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
        .allowClipping: true
    ]
    for screen in NSScreen.screens {
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: opts)
    }
}
```

The image is reapplied at two points:

- Display connect / disconnect: on `NSApplication.didChangeScreenParametersNotification`, reapply the current image (for example when plugging a laptop into an external monitor)
- Space change: on `NSWorkspace.activeSpaceDidChangeNotification`, reapply only on screens where `NSWorkspace.shared.desktopImageURL(for:)` differs from the target image

Constraint: `setDesktopImageURL` only affects each screen's **current Space**. With several desktops, the others change only when you switch to them, hence the Space change handling. Also, overwriting a file at the same path may not refresh because of macOS caching; giving each image its own file name avoids that too.

## Launch at login

A single `SMAppService.mainApp` registration; no hand-written LaunchAgent plist.

```swift
import ServiceManagement

func setLaunchAtLogin(_ on: Bool) throws {
    if on { try SMAppService.mainApp.register() }
    else  { try SMAppService.mainApp.unregister() }
}
// Toggle state: SMAppService.mainApp.status == .enabled

// On by default: register once on first launch
func registerOnFirstLaunch() {
    let key = "didInitialLoginItemSetup"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    try? setLaunchAtLogin(true)
    UserDefaults.standard.set(true, forKey: key)
}
```

- Calling `register()` on every launch would turn the item back on after the user disabled it in System Settings, so it registers once and then follows the user's choice
- The app must be in `/Applications` for registration to stick (registering from the Xcode build folder breaks when the path changes)
- After registering, it appears in System Settings → General → Login Items. If the user turns it off there, `status` changes, so the toggle always reads `status`

## Scheduling, errors and caveats

Updating is simplified to an idempotent step: download only images not in the index, and auto-select only when the newest image changed. With no new image, it's a single JSON request.

| Trigger | Action |
| --- | --- |
| App launch (including launch at login) | Check for new images and auto-select if needed |
| Refresh button | The same, manually |

Wake-from-sleep, midnight and periodic timers are intentionally left out. Machines that stay up for days can use the Refresh button.

| Situation | Handling |
| --- | --- |
| Network failure | Keep the current wallpaper; retry on the next check |
| UHD image 404 | Fall back to the 1920x1080 `url` |
| `wp = false` | Skip that image |
| JSON format change | Log the parse failure and keep existing images |

- App Sandbox is off. With it on, `~/Pictures` access and setting the wallpaper need extra entitlements and permission handling, with no benefit for this app
- Logs go to `os.Logger` (subsystem `kr.pe.corecode.MyTodayWall`) in English and can be viewed in Console.app
- Build: Xcode 16.4. If the active developer directory is Command Line Tools, run `xcodebuild` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- Core check: `scripts/check-core.sh` runs download, auto-select, previous/next and retention against the real API in a temp folder (the wallpaper isn't changed)

## Implementation order

Each step leaves the app in a usable state. After step 2 it already replaces the official app.

- [x] 1\. `BingClient` + `ImageStore`: request, download, storage, `index.json`, verified from the command line
- [x] 2\. `WallpaperApplier` + menu bar app skeleton: apply today's image to all screens
- [x] 3\. Check on launch + Refresh button, `lastAutoDate` auto-select logic
- [x] 4\. Launch-at-login toggle (`SMAppService`, registered once on first launch), install to `/Applications`
- [x] 5\. Previous / Next popover
- [ ] 6\. `ScreenObserver`: reapply on display changes and Space switches, verified on a dual-display setup
- [x] 7\. Retention: clean up old files (except `current`), retention menu
- [x] 8\. Open source: MIT license, English-first docs and UI, Korean translation, market from system locale
