# PasteAll 发布与公证

本项目通过 GitHub Releases 和 Homebrew 站外分发，不走 Mac App Store（右键菜单和 `⌘V` 拦截依赖的能力在 App Sandbox 中不可用）。

## GitHub Actions 自动发布（当前方式，无需开发者账号）

推送 `v<版本号>` 标签即可发布：

```sh
git tag v0.2.0
git push origin v0.2.0
```

[`release.yml`](../.github/workflows/release.yml) 会依次：

1. 运行全部测试。
2. 用 `scripts/package-unsigned.sh` 构建 ad-hoc 签名的通用 App，版本号取自标签，构建号取自 `github.run_number`。
3. 生成 `PasteAll-<版本号>.zip` 与 `.sha256`，创建 GitHub Release 并附上安装说明。
4. 如果配置了 `HOMEBREW_TAP_TOKEN`，用 `scripts/render-cask.sh` 生成 cask 并推送到 tap 仓库。

App 内的检查更新读取的是 GitHub 的 “latest release”，所以草稿和预发布版本不会推送给用户。

### 一次性配置 Homebrew tap

1. 在 GitHub 创建公开仓库 `86XIng/homebrew-tap`（名称必须以 `homebrew-` 开头），里面建一个空的 `Casks/` 目录。
2. 创建一个 fine-grained personal access token，只授权该 tap 仓库的 **Contents: Read and write**。
3. 在 `paste-all` 仓库的 **Settings → Secrets and variables → Actions** 中添加 secret `HOMEBREW_TAP_TOKEN`。
4. 如果 tap 仓库不叫 `86XIng/homebrew-tap`，再添加 variable `HOMEBREW_TAP_REPOSITORY`（例如 `owner/homebrew-tap`）。

用户随后可以运行 `brew install --cask 86xing/tap/paste-all` 安装。由于发布包尚未公证，cask 会在安装后移除隔离属性（见 `packaging/homebrew/paste-all.rb.template` 的 `postflight`）。

### 本地预演打包

```sh
PASTEALL_VERSION=0.2.0 PASTEALL_BUILD_NUMBER=1 ./scripts/package-unsigned.sh
./scripts/render-cask.sh 0.2.0 "$(cut -d' ' -f1 dist/PasteAll-0.2.0.zip.sha256)"
```

## Developer ID 签名与公证（加入 Apple Developer Program 后）

使用 Developer ID 签名后，用户首次打开不再被 Gatekeeper 拦截，更新后辅助功能授权也会保留。切换时需要：

- 用 `scripts/release.sh` 产出已公证的 DMG（或改为打包已公证的 ZIP），并相应修改 `release.yml`；
- 删除 cask 模板中的 `postflight` 和 caveats 里的重新授权说明；
- 首次签名版本发布后，Bundle ID 保持 `io.github.86xing.PasteAll` 不变。

发布脚本会完成：

1. 构建 Intel + Apple Silicon 通用 Release。
2. 使用 Developer ID Application 证书签名并导出 App。
3. 验证 Bundle ID、Hardened Runtime、安全时间戳、架构和签名。
   同时验证主程序与内嵌 `PasteAllCore.framework` 的 Team ID 完全一致。
4. 以 ZIP 提交 App 公证，将票据 staple 到 App。
5. 生成带 `Applications` 快捷方式的 DMG。
6. 再次公证并 staple DMG，最后执行 Gatekeeper 验证。

公证结果和完整日志保存在 `dist/`，方便排查 Apple 返回的警告。

## 本地构建

不需要签名账号即可运行本地构建和测试：

```sh
./scripts/build-local.sh
```

也可以只运行一个阶段：

```sh
./scripts/build-local.sh build
./scripts/build-local.sh test
```

## 开发者账号准备

加入 Apple Developer Program 后：

1. 在开发者后台创建 **Developer ID Application** 证书。
2. 把证书及其私钥安装进“登录”钥匙串。
3. 确认以下命令能看到有效身份：

   ```sh
   security find-identity -v -p codesigning
   ```

4. Bundle ID 使用项目中的 `io.github.86xing.PasteAll`。不要发布后再改 Bundle ID，否则用户的设置和授权都会丢失。
5. 在 Apple ID 网站创建 App 专用密码。

建议把 Developer ID 证书和私钥导出为加密 `.p12` 并离线备份。证书文件本身不够，发布机器还必须持有对应私钥。

## 配置公证凭据

运行下面的脚本：

```sh
PASTEALL_NOTARY_PROFILE=paste-all-notary ./scripts/configure-notary.sh
```

输入 Apple ID、十位 Team ID 和 App 专用密码。密码由 `notarytool` 直接写入 macOS 登录钥匙串，不会写入仓库或脚本。

如果以后改用 App Store Connect API Key，可以直接创建同名 Keychain profile；发布脚本只依赖 profile 名称：

```sh
xcrun notarytool store-credentials paste-all-notary \
  --key /absolute/path/AuthKey_ABC123.p8 \
  --key-id ABC123 \
  --issuer 00000000-0000-0000-0000-000000000000
```

## 正式发布

每次发布都显式提供版本、构建号、Team ID 和 Bundle ID：

```sh
export PASTEALL_TEAM_ID=ABCDE12345
export PASTEALL_BUNDLE_ID=io.github.86xing.PasteAll
export PASTEALL_VERSION=1.0.0
export PASTEALL_BUILD_NUMBER=1
export PASTEALL_NOTARY_PROFILE=paste-all-notary

./scripts/release.sh
```

成功后主要交付物为：

```text
dist/PasteAll-1.0.0-1.dmg
```

脚本不会覆盖相同版本的已有产物。需要重新发布相同版本时，应先使用新的构建号，保留旧产物用于审计和回滚。

## 可选环境变量

| 变量 | 默认值 | 作用 |
| --- | --- | --- |
| `DEVELOPER_DIR` | `/Applications/Xcode.app/Contents/Developer` | 指定完整 Xcode |
| `PASTEALL_SIGNING_IDENTITY` | `Developer ID Application` | 指定证书名称或 SHA-1 |
| `PASTEALL_NOTARY_TIMEOUT` | `60m` | 等待单次公证的最长时间 |
| `PASTEALL_ARTIFACTS_DIR` | `项目目录/dist` | 发布产物目录 |
| `PASTEALL_RELEASE_DERIVED_DATA` | `项目目录/.release/DerivedData` | Release 构建缓存 |
| `PASTEALL_DERIVED_DATA` | `/tmp/PasteAllDerivedData` | 本地构建缓存 |

## 常见失败

- `No Developer ID Application certificate`：证书或对应私钥未安装。
- `Invalid credentials`：检查 Team ID、App 专用密码和 Keychain profile。
- `Invalid`：查看 `dist/*-notary-log.json`，其中包含具体签名路径和错误。
- `Output already exists`：增加构建号，不要覆盖已经生成的发布物。
- Gatekeeper 拒绝：不要跳过脚本末尾的 `spctl` 检查，也不要在公证后重新修改 App 或 DMG。
