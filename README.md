# PasteAll — Clipboard to Files for Mac

**Paste anything. Get a file.**

**PasteAll｜把剪贴板粘贴成文件**

复制什么，都能粘贴成文件。

PasteAll is a native macOS 14+ menu bar app that turns clipboard content into files when you press its configured shortcut in Finder. The default shortcut is `⌘V` and can be changed or reset in Settings.

在访达中按下配置的快捷键时，PasteAll 会根据剪贴板内容生成图片、文本、Markdown、Excel 工作簿或网页快捷方式。默认快捷键为 `⌘V`，可在设置中修改或恢复默认；其他 App 中的按键不会被改变。

## Supported output / 支持格式

- PNG and JPEG images / 图片
- UTF-8 `.txt` and `.md`
- Excel `.xlsx` generated from HTML tables, TSV, or CSV
- macOS `.webloc` and cross-platform `.url` shortcuts

PasteAll defaults to aggressive detection. The menu bar settings also provide strict detection and an ask-every-time picker.

默认使用“积极识别”，也可在菜单栏中切换为“严格识别”或“每次询问”。

## Run in Xcode / 使用 Xcode 运行

1. Open `PasteAll.xcodeproj` in Xcode 26 or newer.
2. Select the `PasteAll` scheme and run **My Mac**.
3. Follow the first-launch guide and grant Accessibility permission when prompted.
4. If macOS does not refresh permission immediately, quit and run PasteAll again.
5. Copy supported content, open a Finder folder, and press the configured shortcut (default: `⌘V`).

首次运行需要在“系统设置 → 隐私与安全性 → 辅助功能”中允许 PasteAll。这个权限只用于在访达中识别配置的快捷键并重放标准粘贴命令。

首次启动会自动显示三步使用指南，并实时检测授权状态。关闭后可随时从菜单栏或设置页的“使用指南”再次打开。

## Build and test / 构建与测试

For the normal unsigned developer build, run:

```sh
./scripts/build-local.sh
```

To build an unsigned universal Release app for testing on both Apple Silicon and Intel Macs, run:

```sh
./scripts/build-local.sh universal
```

The universal app is written to `/tmp/PasteAllUniversalDerivedData/Build/Products/Release/PasteAll.app` by default.
Because this local build has no Developer ID Team ID, the script disables Hardened Runtime for this artifact so its embedded framework can load. Formal releases keep Hardened Runtime enabled and sign both the app and framework with the same Developer ID identity.

正式发布已提供 Developer ID 签名、通用架构构建、DMG、公证、staple 和 Gatekeeper 验证流程。开发者账号准备好后，请按照 [发布与公证说明](docs/RELEASING.md) 配置。

The checked-in Xcode project can be built directly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteAll.xcodeproj -scheme PasteAll \
  -derivedDataPath /tmp/PasteAllDerivedData CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteAll.xcodeproj -scheme PasteAll \
  -derivedDataPath /tmp/PasteAllDerivedData CODE_SIGNING_ALLOWED=NO test
```

The project is generated from `project.yml`. After changing that file, regenerate it with `xcodegen generate`. A Swift Package manifest is also included for command-line builds and core tests.

## Privacy and cache / 隐私与缓存

- No clipboard history, accounts, telemetry, or app-initiated network requests.
- Prepared files live in `~/Library/Caches/com.local.PasteAll/PreparedFiles`.
- The cache directory uses mode `0700`; generated files use mode `0600`.
- Files older than 24 hours are removed when the app starts.
- The clipboard is restored only if it has not changed since PasteAll prepared the Finder paste.

项目依赖首次解析时，Xcode/Swift Package Manager 会从 GitHub 下载 SwiftSoup 与 libxlsxwriter；运行中的 App 本身不联网。

## Current distribution scope / 当前发布范围

The repository includes a Developer ID + notarized DMG release workflow for direct distribution. Mac App Store sandboxing, installer packaging, Homebrew publishing, and automatic updates remain out of scope.
