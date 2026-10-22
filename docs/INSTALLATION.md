# Install AUV / 安装 AUV

[English](#english-installation-guide) · [中文](#中文安装指南) · [Mac 0.17.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.3/AUV_Mac_0.17.3_Universal.zip) · [Windows 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)

## English installation guide

<a id="mac-installation-guide"></a>

### Mac 0.17.3

**macOS 14+ · Apple silicon or Intel · Universal app · build 2026102101.** This package is Developer ID signed and Apple notarized. See [tested configurations](MAC_COMPATIBILITY.md) for the distinction between the build's requirements and real-device coverage.

#### Install

1. [Download AUV_Mac_0.17.3_Universal.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.3/AUV_Mac_0.17.3_Universal.zip). Choose the application ZIP, not GitHub's source archive.
2. Double-click the ZIP in Finder. It extracts **`UMA.app`**, which opens as **AUV**.
3. Drag the app to **Applications** on your Mac's internal disk. Keeping it there lets Sectorium disconnect an external drive without ejecting the app itself.
4. Open AUV and follow the normal macOS first-open prompt. The main window's lower-left corner shows **AUV 0.17.3**. Finder → Get Info shows the app version too.

#### Upgrade

Quit the old app through its menu before replacing it; closing its window may leave it running. Replace `UMA.app` in the same Applications folder and open the new copy. Keep your saved preferences and registered volumes. You do not need to clear settings or caches.

#### Connect Codex

1. Install the official Codex desktop app and sign in with your ChatGPT account.
2. In AUV, allow the local Codex connection and choose **Scan for Agents**.
3. Select Codex and **Refresh** to read the allowance available for that account.

Codex is a separate download. AUV reads the allowance supplied by Codex; it does not count ChatGPT website messages. An API-key-only login may not provide a ChatGPT plan allowance. If you are signed in but no usage appears, use the [connection troubleshooting guide](FIRST_INSTALL_TROUBLESHOOTING.md).

#### Use the other workspaces

- **ThreadOS:** choose models and thinking levels, then copy the generated instruction to your project's Leader. Copying does not apply settings by itself. [ThreadOS guide](https://shaotinghe.com/threados/).
- **Sectorium:** select a drive and register an existing development image or create one. **Load** mounts the development volume. **Unload** closes it while keeping its parent drive connected. **Disconnect** safely ejects the entire external drive. Allow removable-drive access when macOS requests it for an operation you selected. Wait for successful disconnection before unplugging. [Sectorium guide](https://shaotinghe.com/sectorium/).

#### Troubleshooting

- **The old version opens:** quit it, then open the copy in Applications instead of an older copy in Downloads.
- **macOS blocks the app or reports damage:** download the official ZIP again and compare the checksum below. Keep macOS security enabled; [report the complete message](https://github.com/ShaoJHe-SilkRoad/UMA/issues) if it persists.
- **Codex is connected but a statistic is missing:** some statistics are optional and depend on the Codex version and account. Missing token statistics do not invalidate an available account allowance.

#### Optional download check

For the ZIP in Downloads, run:

```sh
shasum -a 256 ~/Downloads/AUV_Mac_0.17.3_Universal.zip
```

Expected SHA-256:

```text
2822fa3f74f2f51c8f58978e9c497fa2328c6aaa7393ada383f015a7d61a9265
```

[Mac release notes](releases/AUV_Mac_0.17.3.md) · [Release downloads](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.17.3)

<a id="windows-installation-guide"></a>

### Windows 0.16.3

**Windows 11 · x64 · portable ZIP · unsigned** — build **20261011.1**.

1. [Download for Windows · v0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip). Choose the application ZIP, not GitHub's source archive.
2. Right-click the ZIP in File Explorer → **Extract All**. Keep the complete extracted folder, including every DLL and runtime file.
3. Run **AUV.exe** from that folder as your normal Windows user. Confirm **AUV 0.16.3** in Properties → Details → Product version. This build has no separate About dialog.
4. Choose AUV, ThreadOS or Sectorium. In Settings, enable the **Desktop Wizard**; it floats separately above applications. The AUV tray icon opens the usage/CPU/RAM popup (Windows may put it in the tray overflow).
5. Use **Quit** in the tray or **Ctrl+Shift+Q** to exit completely. Closing the main window can keep the tray running.

The **.NET 10.0.12 desktop runtime is included**; the portable app does not require a separate .NET SDK/runtime installation. Optional WorkBuddy connection additionally needs **Microsoft Edge WebView2 Runtime**, which is not bundled. Codex data requires the installed Codex client and its existing login. No new provider login is required simply to open AUV.

This Windows build is **not digitally signed** and may trigger Windows or organization security controls. Check the official package checksum; keep protections enabled and [report the exact message](https://github.com/ShaoJHe-SilkRoad/UMA/issues) if blocked. No warning-free or clean-machine certification is claimed.

**Upgrade:** quit the old copy, extract the new package into a separate folder and run its AUV.exe. Preserve **%LOCALAPPDATA%\AUV.Windows.UI.Preview**: it contains settings.v1.json and the separate workbuddy-web-* browser profile. The preview-era directory name is intentionally retained. Do not delete settings or assume rollback compatibility. Mac preferences are separate.

**Scope:** Codex read-only usage is connected; WorkBuddy Credit sync is experimental. Claude and Antigravity live connections are unavailable. Missing/stale/disconnected quotas are hidden; verified zero stays visible. ThreadOS generates and copies instructions without dispatching work or applying settings. Sectorium is UI only with storage actions disabled. ARM64, installer, signing reputation, receiving-client execution and Windows storage qualification are not included.

Verify in PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 "$env:USERPROFILE\Downloads\AUV_Win_0.16.3.zip"
```

Expected SHA-256: **bc1577aae1d3ffdc3e3b104de15c6649ab4fb83f452a04865d548002f432085a**.

[Windows release notes](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.16.3) · [Checksums](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/HASHES.txt) · [Release manifest](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/RELEASE-MANIFEST.json) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

## 中文安装指南

<a id="mac-中文安装指南"></a>

### Mac 0.17.3

**macOS 14 及以上 · Apple silicon 或 Intel · 通用包 · 构建号 2026102101。** 本包已完成 Developer ID 签名和 Apple 公证。安装要求与实机测试范围有所区别，详见[已测试环境](MAC_COMPATIBILITY.md#中文)。

#### 安装

1. [下载 AUV_Mac_0.17.3_Universal.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.3/AUV_Mac_0.17.3_Universal.zip)。请选择应用 ZIP，不要选 GitHub 的源码压缩包。
2. 在 Finder 中双击解压，得到 **`UMA.app`**，打开后显示为 **AUV**。
3. 将应用拖入 Mac 内置盘的**“应用程序”**文件夹。这样分区工弹出外接硬盘时，应用本身仍能正常运行。
4. 打开 AUV，按 macOS 正常首次启动提示操作。主窗口左下角应显示 **AUV 0.17.3**，Finder →“显示简介”也可以查看版本。

#### 升级

替换前先通过菜单正常退出旧版；只关窗口可能仍会在后台运行。在原“应用程序”文件夹中替换 `UMA.app`，再打开新版。保留已有偏好和已登记开发卷，无需清空设置或缓存。

#### 连接 Codex

1. 安装官方 Codex 桌面应用，并使用 ChatGPT 账户登录。
2. 在 AUV 中允许连接本机 Codex，然后点击**“扫描智能体”**。
3. 选择 Codex 并点击**“刷新”**，读取该账户能够提供的额度。

Codex 需单独安装。AUV 显示 Codex 返回的额度，不统计 ChatGPT 网页消息数。仅使用 API Key 登录时，可能没有 ChatGPT 套餐额度。已登录但没有用量时，请查看[连接排错指南](FIRST_INSTALL_TROUBLESHOOTING.md#中文)。

#### 使用其他功能区

- **线程工：**选择模型与思考档位，将生成的指令复制给项目的 Leader。复制本身不会应用设置。[线程工指南](https://shaotinghe.com/threados/)。
- **分区工：**选择硬盘，登记已有开发镜像或新建开发卷。**Load · 装载**挂载开发卷；**Unload · 卸载**关闭开发卷，母盘保持连接；**Disconnect · 断开**安全弹出整个外接硬盘。执行所选操作时，按 macOS 提示允许访问移动硬盘。断开成功后再拔线。[分区工指南](https://shaotinghe.com/sectorium/)。

#### 遇到问题

- **打开的仍是旧版：**正常退出后，从“应用程序”打开新版，不要打开“下载”中的旧副本。
- **macOS 阻止启动或提示损坏：**重新下载正式 ZIP，核对下方校验值。保持系统安全保护开启；仍有问题时请[反馈完整提示](https://github.com/ShaoJHe-SilkRoad/UMA/issues)。
- **已连接 Codex，但缺少某项统计：**部分统计取决于 Codex 版本和账户。缺少 token 统计，不影响已经取得的账户额度。

#### 可选：校验下载文件

ZIP 位于“下载”文件夹时，在终端运行：

```sh
shasum -a 256 ~/Downloads/AUV_Mac_0.17.3_Universal.zip
```

SHA-256 应为：

```text
2822fa3f74f2f51c8f58978e9c497fa2328c6aaa7393ada383f015a7d61a9265
```

[Mac 更新说明](releases/AUV_Mac_0.17.3.md#中文) · [发布下载页](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.17.3)

<a id="windows-中文安装指南"></a>

### Windows 0.16.3

**Windows 11 · x64 · 便携 ZIP · 未签名**，构建号 **20261011.1**。

1. [下载 Windows 版 · v0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)。请选择应用 ZIP，不要选 GitHub 的源码压缩包。
2. 在文件资源管理器右键 ZIP → **全部解压**。保留完整文件夹，包含所有 DLL 和运行时文件。
3. 以普通用户运行其中的 **AUV.exe**，在 AUV.exe 文件属性 → 详细信息确认产品版本 **0.16.3**。本版没有单独的“关于”窗口。
4. 切换 AUV、线程工、分区工。在设置中启用 **Desktop Wizard 桌面浮窗**，它独立悬浮于应用上方。AUV 托盘图标可展开用量与 CPU/内存；图标可能位于托盘折叠菜单。
5. 用托盘 **Quit** 或 **Ctrl+Shift+Q** 完全退出；只关闭主窗口可能仍保留托盘。

**已包含 .NET 10.0.12 桌面运行时**，便携包无需另外安装 .NET SDK/运行时。可选 WorkBuddy 连接另需 **Microsoft Edge WebView2 Runtime**，本包不附带。Codex 需已安装的客户端及其现有登录；仅打开 AUV 无需新增代理登录。

Windows 包**未进行数字签名**，可能受到 Windows 或组织安全策略拦截。请核对官方文件校验值，保持安全防护开启；若受阻，请[反馈具体提示](https://github.com/ShaoJHe-SilkRoad/UMA/issues)。不承诺无安全提示，也不宣称通过干净机器认证。

**升级：**先正常退出旧版，将新包全部解压到独立文件夹，再运行新版 AUV.exe。保留 **%LOCALAPPDATA%\AUV.Windows.UI.Preview**，其中含 settings.v1.json 及独立的 workbuddy-web-* 浏览器配置。为延续设置，本版保留预览时期的目录名；不要删除设置，也不保证回退兼容。Mac 偏好单独保存。

**范围：**Codex 只读用量已接入；WorkBuddy Credit 同步为试验功能。Claude、Antigravity 暂无实时连接。不可用、过期或断开的额度隐藏，已确认的零仍显示。线程工生成、复制指令，不代发任务或应用设置。分区工仅为界面，磁盘操作禁用。ARM64、安装器、签名信誉、接收端执行与 Windows 存储认证不在本版范围内。

PowerShell 校验方法同上，SHA-256 应为 **bc1577aae1d3ffdc3e3b104de15c6649ab4fb83f452a04865d548002f432085a**。

[Windows 更新说明](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.16.3) · [校验值](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/HASHES.txt) · [发布清单](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/RELEASE-MANIFEST.json) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
