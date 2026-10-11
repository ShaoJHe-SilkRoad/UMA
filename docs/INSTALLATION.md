# Install AUV / 安装 AUV

[English](#english-installation-guide) · [中文](#中文安装指南) · [Windows 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip) · [macOS 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Mac_0.16.3.zip)

## English installation guide

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

### macOS 0.16.3

### Before you start

You need **macOS 14 or later and an Apple silicon Mac (M-series chip)**. Check Apple menu → About This Mac if you are unsure. This release does not include an Intel version.

AUV 0.16.3 includes ThreadOS and Sectorium. You only need one app download.

### Install

1. [Download AUV_Mac_0.16.3.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Mac_0.16.3.zip). Choose this application ZIP, not GitHub’s “Source code” download.
2. Double-click the ZIP in Finder. It extracts **`UMA.app`** — the app opens as **AUV**, but keeps its old filename for compatibility.
3. Drag it into **Applications** on your Mac’s internal disk. Your personal `~/Applications` folder also works. Keep the app on the internal disk if you plan to eject an external development drive.
4. Open the installed copy and follow the normal macOS first-open prompt. This release is Developer ID signed and Apple notarized.
5. Open **AUV → About AUV** and check **0.16.3**. The build number is **2026101101**; Finder → Get Info can also show the installed app’s version details.

### Upgrade from UMA or an older AUV

Quit the old app through its menu — closing the window may leave it running in the menu bar. Keep a copy of the old app as a backup, then replace it with the new `UMA.app` in the same installation folder. Open the new copy.

Your saved settings are retained. You do not need to clear preferences, history or caches. Installing AUV does not automatically install or activate Sectorium’s storage tools.

### What to do after opening

- **AUV:** choose an agent to see the usage information available for its account.
- **ThreadOS:** choose each role’s model and thinking level, copy the instruction, and paste it into your Leader conversation. [ThreadOS guide](https://shaotinghe.com/threados/).
- **Sectorium:** follow the [setup guide](https://shaotinghe.com/sectorium/) before using storage actions. It is still experimental: back up important data and start with noncritical data. Do not unplug a drive until its complete safe-eject operation succeeds.

### If something goes wrong

- **An older version opens:** quit it, then open the copy in your chosen Applications folder rather than Downloads.
- **macOS blocks the app or says it is damaged:** download it again from the official release and check the file below. Do not disable system security or force it open. If the problem remains, [report the message](https://github.com/ShaoJHe-SilkRoad/UMA/issues).
- **You need to go back:** quit AUV and restore your backed-up app to the same folder. This restores the app only; it does not undo changes to Sectorium tools, services or disk data.

### Optional: verify your download

For the ZIP saved with its original name in Downloads, run:

```sh
shasum -a 256 ~/Downloads/AUV_Mac_0.16.3.zip
```

The first value should match:

[HASHES.txt](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Mac_0.16.3.HASHES.txt) (`AUV_Mac_0.16.3.zip`)

If it differs, do not install that file. Download it again. The [release page](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.16.3) also provides `AUV_Mac_0.16.3.HASHES.txt` and the signing record. The signing identity is **SHAOTING HE (C6TUZVJ6SJ)**.

## 中文安装指南

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

### macOS 0.16.3

### 安装前

需要 **macOS 14 或更新版本，以及 Apple silicon Mac（M 系列芯片）**。不确定时，可在苹果菜单 →“关于本机”查看。本版不提供 Intel 版本。

AUV 0.16.3 已包含线程工和分区工，只需下载一个应用。

### 安装

1. [下载 AUV_Mac_0.16.3.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Mac_0.16.3.zip)。请选择这个应用 ZIP，不要选择 GitHub 的“Source code”源码包。
2. 在 Finder 中双击解压，得到 **`UMA.app`**。打开后显示为 **AUV**，文件名沿用旧名以兼容已有安装。
3. 将它拖入 Mac 内置盘的**“应用程序”**文件夹，也可以使用个人 `~/Applications` 文件夹。如果以后需要弹出外接开发硬盘，应用本身请放在内置盘。
4. 打开安装后的应用，按 macOS 正常首次启动提示操作。本版已使用 Developer ID 签名，并通过 Apple 公证。
5. 在 **AUV → 关于 AUV** 中确认版本为 **0.16.3**。构建号为 **2026101101**；Finder →“显示简介”也可查看已安装应用的版本信息。

### 从 UMA 或旧版 AUV 升级

先通过菜单正常退出旧应用；只关窗口可能仍会在菜单栏运行。保留一份旧应用备份，再用新的 `UMA.app` 替换原安装文件夹中的应用，然后打开新版。

已保存的设置会保留，无需清空偏好、历史或缓存。安装 AUV 不会自动安装或启用分区工的存储工具。

### 打开后做什么

- **AUV：**选择代理，查看其账户能够提供的用量信息。
- **线程工：**分别选择角色的模型与思考档位，复制指令，粘贴给 Leader。[线程工指南](https://shaotinghe.com/threados/)。
- **分区工：**先阅读[设置指南](https://shaotinghe.com/sectorium/)，再使用磁盘操作。它仍是试验功能，请先备份重要数据，用非关键数据试用；完整安全弹出成功前不要拔盘。

### 遇到问题

- **打开的还是旧版：**正常退出后，从选定的“应用程序”文件夹打开，不要打开“下载”里的旧副本。
- **macOS 阻止启动或提示应用损坏：**从正式发布页重新下载，并按下方方法校验。不要关闭系统安全检查或强行启动。仍有问题时，请[反馈具体提示](https://github.com/ShaoJHe-SilkRoad/UMA/issues)。
- **需要退回旧版：**退出 AUV，将备份的旧应用放回原位置。这只回退应用，不会撤销分区工工具、服务或磁盘数据的变化。

### 可选：校验下载文件

如果 ZIP 保留原名并位于“下载”文件夹，在终端执行：

```sh
shasum -a 256 ~/Downloads/AUV_Mac_0.16.3.zip
```

输出的第一个值应为：

[HASHES.txt](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Mac_0.16.3.HASHES.txt) (`AUV_Mac_0.16.3.zip`)

不一致就不要安装，请重新下载。[正式发布页](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.16.3)也提供 `AUV_Mac_0.16.3.HASHES.txt` 和签名记录；签名者为 **SHAOTING HE (C6TUZVJ6SJ)**。
