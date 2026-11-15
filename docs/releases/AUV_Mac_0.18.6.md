# AUV Mac 0.18.6

**Build 2026111501 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.6/AUV_Mac_0.18.6_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

The Safari Bridge that Claude's exact usage needs now comes with AUV.

- **One download.** Claude's exact figures are read through Safari by the UMA Safari Bridge and its extension. Until now the Bridge was not published, so on a new Mac Claude's exact sync could not be set up at all. AUV 0.18.6 carries the Bridge build it is matched to.
- **Install it from Claude's page.** Once you have allowed AUV to read Claude, Claude's page shows **Install Safari Bridge**. AUV copies the Bridge into Applications in your home folder and starts it. One step is left that only you can take: in Safari's Settings → Extensions, turn on **UMA Browser Companion for Claude** and allow it on claude.ai. AUV offers to open those settings. Then sign in to claude.ai in Safari.
- **Updates itself with AUV.** When a later AUV is matched to a newer Bridge, the button reads **Update Safari Bridge**. The old copy goes to the Trash.
- **Move AUV to Applications first.** Opened straight from Downloads, macOS runs AUV from a temporary location, and AUV asks you to move it to Applications before installing the Bridge.
- **No Safari prompts before the Bridge is there.** Until the Bridge is installed, automatic refresh and Refresh All don't try Claude's exact sync and don't ask to open Safari. This step also comes before repairing Local Smart, so it shows for people who use claude.ai without Claude Code.

**Apple silicon only for Claude's exact usage.** The Bridge runs on Apple silicon. On an Intel Mac, AUV works as before, but Claude's exact sync is not available.

If the Bridge is already installed from an earlier setup, nothing changes for you: it is the same Bridge build, 0.14.3.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and the Safari Bridge inside it are each Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment after a clean re-extraction. New tests cover finding, installing and updating the Bridge, and the full test suite ran with only known, unrelated failures.

Installing the Bridge from Claude's page on a Mac that has never had it is checked after release, through the website download. Physical Intel Macs and macOS 14/15 were not tested.

Sectorium is unchanged and was not retested. [Windows is at 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win) and is released separately; it has its own browser companion for Chrome and Edge.

## Download identity

- File: `AUV_Mac_0.18.6_Universal.zip`
- Size: **15,656,617 bytes**
- SHA-256:

```text
b77abee071718d9434d69f2b0812619a26141762c976af5a429ac6e8b4d24c68
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026111501 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.6/AUV_Mac_0.18.6_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

Claude 精确用量所需的 Safari 助手现在随 AUV 一起提供。

- **只需下载一个应用。** Claude 的精确数值由 UMA Safari 助手及其扩展通过 Safari 读取。此前 Safari 助手没有公开发布，在新 Mac 上根本无法设置 Claude 精确同步。AUV 0.18.6 自带与之配对的 Safari 助手版本。
- **在 Claude 页面安装。** 允许 AUV 读取 Claude 后，Claude 页面会显示 **“安装 Safari 助手”**。AUV 会把它复制到你个人文件夹里的“应用程序”中并启动。剩下一步只能由你完成：在 Safari 的“设置 → 扩展”中启用 **UMA Browser Companion for Claude**，并允许它访问 claude.ai。AUV 可以帮你打开这个设置。然后在 Safari 中登录 claude.ai。
- **随 AUV 更新。** 以后的 AUV 配对更新的 Safari 助手时，按钮会显示 **“更新 Safari 助手”**，旧版会移到废纸篓。
- **请先把 AUV 移到“应用程序”。** 从“下载”直接打开时，macOS 会让 AUV 在临时位置运行，AUV 会先请你把它移到“应用程序”，再安装 Safari 助手。
- **装好之前不会弹出 Safari 询问。** Safari 助手装好之前，自动刷新和“全部刷新”不会尝试 Claude 精确同步，也不会询问是否打开 Safari。这一步排在修复本地智能之前，所以只用 claude.ai、不用 Claude Code 的人也能看到。

**Claude 精确用量仅支持 Apple 芯片。** Safari 助手只能在 Apple 芯片的 Mac 上运行。在 Intel Mac 上，AUV 其他功能照常，但无法使用 Claude 精确同步。

如果你之前已经装过 Safari 助手，这次没有变化：仍是同一个版本 0.14.3。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 及其内置的 Safari 助手均已完成 Developer ID 签名、Apple 公证与票据装订，重新解压后通过 Gatekeeper 检查。新增测试覆盖查找、安装和更新 Safari 助手；全量测试中只有已知、与本版无关的失败。

在从未装过 Safari 助手的 Mac 上从 Claude 页面安装，会在发布后通过网站下载检查。尚未测试 Intel 实机或 macOS 14/15。

本版未改动分区工，也未重新测试。[Windows 版为 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win)，单独发布，使用自己的 Chrome / Edge 浏览器伴侣。

### 下载文件

- 文件：`AUV_Mac_0.18.6_Universal.zip`
- 大小：**15,656,617 字节**
- SHA-256：

```text
b77abee071718d9434d69f2b0812619a26141762c976af5a429ac6e8b4d24c68
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
