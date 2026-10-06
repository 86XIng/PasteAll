# PasteAll｜把剪贴板粘贴成文件

[English](README.md) | **简体中文**

**复制什么，都能粘贴成文件。**

PasteAll 是一款适用于 macOS 14 及以上版本的原生菜单栏 App，可以在访达中把剪贴板内容变成文件。复制图片、文字、表格或链接后，在访达文件夹里按 `⌘V`，或者点按右键选择**将剪贴板粘贴为文件**，PasteAll 就会生成对应的文件。

## 功能

| 剪贴板内容 | 生成的文件 |
| --- | --- |
| PNG / JPEG / TIFF / HEIC / GIF 图片 | `.png` 或 `.jpg` |
| 纯文本 | UTF-8 `.txt` |
| Markdown（自动识别） | `.md` |
| HTML 表格、TSV、CSV（例如从 Excel、Numbers、网页复制） | Excel `.xlsx` |
| 网页链接 | macOS `.webloc` 或跨平台 `.url` |

- **两种粘贴方式：** 在访达中按配置的快捷键（默认 `⌘V`），或使用访达右键菜单。
- **识别模式：** 积极识别（默认）、严格识别，或每次询问并弹出格式选择。
- **可自定义快捷键：** 只在访达位于前台时生效，不影响其他 App。
- **注重隐私：** 不保存剪贴板历史，无需账号，不发送遥测。

## 安装

### Homebrew（推荐）

```sh
brew install --cask 86xing/tap/paste-all
```

以后用 `brew upgrade --cask paste-all` 升级。

### 磁盘映像

1. 从[最新版本](https://github.com/86XIng/PasteAll/releases/latest)下载 `PasteAll-<版本号>.dmg`。
2. 打开后把 **PasteAll** 拖到 **Applications（应用程序）** 上。映像中还附有中英双语的**安装说明**。

每个版本也会附带同一 App 的 `.zip`，供 Homebrew cask 使用。

### 首次打开

PasteAll 目前还没有经过 Apple 公证，所以 macOS 会拦截手动下载版本的首次打开（通过 Homebrew 安装则无需处理）：

- 在终端运行 `xattr -dr com.apple.quarantine /Applications/PasteAll.app`；**或者**
- 先打开一次 PasteAll，然后前往**系统设置 → 隐私与安全性**，点按**仍要打开**。

## 设置

### 辅助功能权限（用于 `⌘V`）

首次启动的使用指南会请求辅助功能权限。PasteAll 只用它识别访达中的快捷键并重放访达的粘贴命令，不会记录你输入的内容。

请在**系统设置 → 隐私与安全性 → 辅助功能**中打开 PasteAll，授权状态会自动刷新。

### 访达右键菜单（可选）

打开**设置 → 访达右键菜单**，点按**开启…**。如果 macOS 打开的是扩展设置页面，请在访达扩展中勾选 **PasteAll**。

之后在任意访达文件夹的空白处（或某个文件夹上）点按右键，选择：

- **将剪贴板粘贴为文件**：按当前识别模式生成文件。
- **将剪贴板粘贴为…**：每次都让你选择格式。

右键菜单会把文件直接写入该文件夹，不会改动剪贴板，也不需要辅助功能权限。

## 更新

PasteAll 每天检查一次 GitHub Releases，有新版本时会提醒你。可以在**设置 → 更新**中关闭自动检查，或者在设置和菜单栏中手动检查。如果是通过 Homebrew 安装的，提醒中会给出 `brew upgrade` 命令，而不是下载链接。

**更新之后，** macOS 可能不再认可之前的辅助功能授权：在 PasteAll 使用 Developer ID 签名之前，这项授权与每个版本的签名绑定，即使系统设置里的开关看起来还是打开的。PasteAll 会在更新后检测到这种情况并提示**重新授权**：它会清除失效的授权记录并重新请求，你只需要再次打开 PasteAll 的开关。

## 隐私

- 剪贴板内容只在你的 Mac 上处理。
- 唯一的网络请求是可选的检查更新，只会访问 `api.github.com`。
- 为 `⌘V` 准备的文件存放在 `~/Library/Caches/io.github.86xing.PasteAll/PreparedFiles`（目录权限 `0700`，文件权限 `0600`），24 小时后清理。
- 通过 `⌘V` 粘贴后会恢复原剪贴板内容，除非期间剪贴板已经发生变化。

## 从源码构建

环境要求：macOS 14 及以上，Xcode 26 或更新版本。

```sh
./scripts/build-local.sh            # 构建（Debug）并运行全部测试
./scripts/build-local.sh build      # 只构建
./scripts/build-local.sh test       # 只测试
./scripts/build-local.sh universal  # 通用架构 Release 版，输出到 /tmp/PasteAllUniversalDerivedData
```

在已登录的 macOS 图形会话中，还可运行 `./scripts/test-finder-ipc.sh`，用临时应用验证沙盒发送方在冷启动和已启动状态下的请求交付，以及相同 Bundle ID 的伪造发送方被拒绝。测试不读取剪贴板，也不使用已安装的 PasteAll。

本地构建使用临时（ad-hoc）签名，macOS 会把每次重新构建的版本视为新的 App，需要重新授予辅助功能权限。为避免这种情况，可以使用钥匙串中长期有效的签名身份：

```sh
PASTEALL_LOCAL_SIGNING_IDENTITY="Apple Development: you@example.com (TEAMID)" ./scripts/build-local.sh build
```

Xcode 工程由 `project.yml` 生成，修改后请运行 `xcodegen generate`。仓库也附带 Swift Package 清单，便于在命令行构建核心库。

### 目录结构

| 路径 | 内容 |
| --- | --- |
| `Sources/PasteAllCore` | 剪贴板识别、解析器、文件生成、更新逻辑 |
| `Sources/PasteAll` | 菜单栏 App、访达 `⌘V` 处理、设置、使用指南 |
| `Sources/PasteAllFinderExtension` | 提供右键菜单的访达扩展（Finder Sync） |
| `scripts/` | 本地构建、发布打包、Homebrew cask 生成 |

## 发布

推送 `v1.2.0` 这样的标签会触发 [`.github/workflows/release.yml`](.github/workflows/release.yml)：自动测试、构建通用 App、发布 GitHub Release 并更新 Homebrew tap。一次性配置以及签名、公证发布请参阅 [docs/RELEASING.md](docs/RELEASING.md)。

## 许可证

PasteAll 以 [MIT 许可证](LICENSE)发布，并随附 [SwiftSoup](https://github.com/scinfu/SwiftSoup)（MIT）和 [libxlsxwriter](https://github.com/jmcnamara/libxlsxwriter)（FreeBSD）；详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
