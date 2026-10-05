# PasteAll — Clipboard to Files for Mac

**English** | [简体中文](README.zh-CN.md)

**Paste anything. Get a file.**

PasteAll is a native macOS 14+ menu bar app that turns clipboard content into files in Finder. Copy an image, some text, a table, or a link, then press `⌘V` in a Finder folder — or right-click and choose **Paste Clipboard as File** — and PasteAll writes the matching file.

## Features

| Clipboard content | File created |
| --- | --- |
| PNG / JPEG / TIFF / HEIC / GIF images | `.png` or `.jpg` |
| Plain text | UTF-8 `.txt` |
| Markdown (detected automatically) | `.md` |
| HTML tables, TSV, CSV (e.g. copied from Excel, Numbers, web pages) | Excel `.xlsx` |
| Web links | macOS `.webloc` or cross-platform `.url` |

- **Two ways to paste:** press the configured shortcut (default `⌘V`) in Finder, or use the Finder context menu.
- **Detection modes:** Aggressive (default), Strict, or Ask Every Time with a format picker.
- **Customizable shortcut** that applies only while Finder is in front; other apps are never affected.
- **Private:** no clipboard history, no accounts, no telemetry.

## Install

### Homebrew (recommended)

```sh
brew install --cask 86xing/tap/paste-all
```

Upgrade later with `brew upgrade --cask paste-all`.

### Manual download

1. Download `PasteAll-<version>.zip` from the [latest release](https://github.com/86XIng/paste-all/releases/latest).
2. Unzip it and move `PasteAll.app` to **Applications**.

### First launch

PasteAll is not yet notarized by Apple, so macOS blocks the first launch of a downloaded copy (Homebrew handles this for you):

- Open PasteAll once, then go to **System Settings → Privacy & Security** and click **Open Anyway**, **or**
- run `xattr -dr com.apple.quarantine /Applications/PasteAll.app` in Terminal.

## Setup

### Accessibility permission (for `⌘V`)

The first-launch guide asks for Accessibility permission. PasteAll uses it only to recognize your shortcut in Finder and replay Finder's paste command; it never records what you type.

Enable PasteAll under **System Settings → Privacy & Security → Accessibility**. The status updates automatically.

### Finder context menu (optional)

Open **Settings → Finder Context Menu** and click **Turn On…**. If macOS shows its extension settings instead, enable **PasteAll** under Finder extensions.

Then right-click inside any Finder folder (or on a folder) and choose:

- **Paste Clipboard as File** — uses your detection mode.
- **Paste Clipboard as…** — always lets you pick the format.

The context menu writes the file directly into the folder. It does not change the clipboard and does not need Accessibility permission.

## Updates

PasteAll checks GitHub Releases once a day and tells you when a new version is available. You can turn this off or check manually in **Settings → Updates** or from the menu bar. If you installed with Homebrew, the notice shows the `brew upgrade` command instead of a download link.

**After updating,** macOS may stop honoring the Accessibility approval, because it is tied to each build's signature until PasteAll ships with a Developer ID signature. The System Settings switch can still look on. PasteAll detects this after an update and offers **Re-authorize**: it clears the outdated entry and asks again, so you only need to switch PasteAll back on.

## Privacy

- Clipboard content is processed only on your Mac.
- The only network request is the optional update check to `api.github.com`.
- Files prepared for `⌘V` live in `~/Library/Caches/io.github.86xing.PasteAll/PreparedFiles` (mode `0700`, files `0600`) and are removed after 24 hours.
- The clipboard is restored after a `⌘V` paste, unless it changed in the meantime.

## Build from source

Requirements: macOS 14+, Xcode 26 or newer.

```sh
./scripts/build-local.sh            # build (Debug) and run all tests
./scripts/build-local.sh build      # build only
./scripts/build-local.sh test       # tests only
./scripts/build-local.sh universal  # universal Release app in /tmp/PasteAllUniversalDerivedData
./scripts/test-finder-ipc.sh        # IPC integration test; requires a logged-in macOS GUI session
```

The IPC test uses disposable apps to verify sandboxed cold/warm delivery and rejection of a sender with a copied bundle ID. It does not read the clipboard or use the installed PasteAll app.

Local builds are ad-hoc signed, so macOS treats every rebuild as a new app and you must re-grant Accessibility. To avoid that, sign with a stable identity from your keychain:

```sh
PASTEALL_LOCAL_SIGNING_IDENTITY="Apple Development: you@example.com (TEAMID)" ./scripts/build-local.sh build
```

The Xcode project is generated from `project.yml`; after editing it, run `xcodegen generate`. A Swift Package manifest is included for command-line builds of the core library.

### Project layout

| Path | Contents |
| --- | --- |
| `Sources/PasteAllCore` | Clipboard detection, parsers, file generation, update logic |
| `Sources/PasteAll` | Menu bar app, Finder `⌘V` handling, settings, onboarding |
| `Sources/PasteAllFinderExtension` | Finder Sync extension for the context menu |
| `scripts/` | Local build, release packaging, Homebrew cask rendering |

## Releasing

Pushing a tag such as `v1.2.0` runs [`.github/workflows/release.yml`](.github/workflows/release.yml), which tests, builds a universal app, publishes the GitHub Release, and updates the Homebrew tap. See [docs/RELEASING.md](docs/RELEASING.md) for the one-time setup and for signed, notarized releases.

## License

PasteAll is released under the [MIT License](LICENSE). It bundles [SwiftSoup](https://github.com/scinfu/SwiftSoup) (MIT) and [libxlsxwriter](https://github.com/jmcnamara/libxlsxwriter) (FreeBSD); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
