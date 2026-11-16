# AUV Mac 0.18.7

**Build 2026111504 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.7/AUV_Mac_0.18.7_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

Claude's exact usage now works on a new Mac after the Safari Bridge is installed, AUV reads your Claude plan by itself, and setting up Safari goes step by step.

- **The Safari Bridge works on a new Mac.** In 0.18.6, the Bridge AUV installed kept the download mark AUV itself arrived with. macOS then ran it from a temporary location, the extension kept answering its own checks, and no reading ever reached Safari. AUV now clears the mark when it installs the Bridge. If you installed it with 0.18.6, Claude's page offers **Update Safari Bridge**; one press fixes it.
- **Your Claude plan is read for you.** claude.ai shows the plan beside "Your usage". Accuracy Sync now reads it, and Claude's bars turn green or red with an exact reading even if you never chose a plan. The Claude plan menu reads **Automatic (Max)**, or whatever your plan is; a plan you choose there still wins.
- **Setup, one step at a time.** Until Claude's exact usage arrives, Claude's page shows the next step with one button: install the Safari Bridge, turn on "UMA Browser Companion for Claude" in Safari's Settings → Extensions, allow it on claude.ai and sign in, then sync once. Claude Settings lists all four steps with ticks, and the list goes away after the first exact reading.
- **A simpler Claude Settings.** It opens with the reading, the setup steps while they matter, and your settings. The three internal status lines (Local Smart, Companion, Browser Accuracy) moved under "How it works".

The Safari side of the plan reader is part of **UMA Safari Bridge 0.14.4**, which comes with AUV 0.18.7. Claude's page offers to update an older Bridge.

**Apple silicon only for Claude's exact usage.** The Bridge runs on Apple silicon. On an Intel Mac, AUV works as before, but Claude's exact sync is not available.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and the Safari Bridge inside it are each Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment after a clean re-extraction. The full test suite ran with only known, unrelated failures.

In the installed app, updating from Bridge 0.14.3 from Claude's page worked, the Bridge then ran from Applications, and the next sync read the plan, Max, from claude.ai. Two earlier builds of 0.18.7 quit right after updating the Bridge, because of how macOS answers when asked about the extension. That is fixed, and a test now repeats that question.

- **Known problem:** a read and its retry can both fail when the Mac is busy, because Safari suspends the hidden page. Claude then shows its last reading until the next sync.
- **Not tried in the installed app:** whether "Open Safari Settings" opens the Extensions pane directly. If it can't, it opens Safari. A first install on a Mac that never had the Bridge was tried with 0.18.6, where it showed the download-mark problem that 0.18.7 fixes. Physical Intel Macs and macOS 14/15 were not tested.

Sectorium is unchanged and was not retested. [Windows is at 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win) and is released separately.

## Download identity

- File: `AUV_Mac_0.18.7_Universal.zip`
- Size: **15,708,085 bytes**
- SHA-256:

```text
15907245e3b003d2e2c64fc90e14370e836a8858c056d00a3fb6d8d86c5f09ce
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026111504 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.7/AUV_Mac_0.18.7_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

装好 Safari 助手后，新 Mac 上也能读到 Claude 的精确用量；AUV 会自动识别你的 Claude 套餐；Safari 设置改为分步引导。

- **新 Mac 上 Safari 助手可以正常工作。** 0.18.6 安装 Safari 助手时，保留了 AUV 下载时带的下载标记。macOS 于是把它放在临时位置运行，扩展自己的检查都正常，但读取请求始终到不了 Safari。现在 AUV 安装时会清除这个标记。如果你用 0.18.6 装过 Safari 助手，Claude 页面会显示 **“更新 Safari 助手”**，点一下即可修复。
- **自动识别 Claude 套餐。** claude.ai 在“Your usage”旁边显示套餐。精确同步现在会读取它，即使你从未选择套餐，有精确读数时 Claude 的进度条也会变绿或变红。Claude 套餐菜单显示 **“自动（Max）”**（或你的实际套餐）；手动选择的套餐仍然优先。
- **分步完成设置。** 在读到 Claude 精确用量之前，Claude 页面会显示下一步并配一个按钮：安装 Safari 助手 → 在 Safari 的“设置 → 扩展”中启用“UMA Browser Companion for Claude” → 允许访问 claude.ai 并登录 → 同步一次。Claude 设置中列出全部 4 步并逐项打勾，读到第一个精确读数后清单自动收起。
- **更简洁的 Claude 设置。** 打开后依次是读数、仍需完成的设置步骤、你的设置。三行内部状态（本地智能、浏览器伴侣、浏览器精确同步）移到了“工作原理”中。

读取套餐的 Safari 部分位于 **UMA Safari 助手 0.14.4** 中，随 AUV 0.18.7 一起提供；Claude 页面会提示更新旧版。

**Claude 精确用量仅支持 Apple 芯片。** Safari 助手只能在 Apple 芯片的 Mac 上运行。在 Intel Mac 上，AUV 其他功能照常，但无法使用 Claude 精确同步。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 及其内置的 Safari 助手均已完成 Developer ID 签名、Apple 公证与票据装订，重新解压后通过 Gatekeeper 检查。全量测试中只有已知、与本版无关的失败。

在安装后的应用中，从 Claude 页面把 Safari 助手由 0.14.3 更新成功，之后助手从“应用程序”运行，下一次同步从 claude.ai 读到了套餐 Max。0.18.7 之前的两个构建在更新 Safari 助手后会立刻退出，原因是 macOS 回答扩展状态的方式。这已修复，并新增测试重现这一询问。

- **已知问题：** Mac 繁忙时，Safari 会挂起隐藏页面，一次读取和它的重试可能都失败。此时 Claude 显示上次的读数，直到下一次同步。
- **未在安装后的应用中实测：** “打开 Safari 设置”能否直接打开“扩展”面板；如果不能，会打开 Safari。在从未装过 Safari 助手的 Mac 上首次安装，用 0.18.6 测过，当时出现的下载标记问题已在 0.18.7 修复。尚未测试 Intel 实机或 macOS 14/15。

本版未改动分区工，也未重新测试。[Windows 版为 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win)，单独发布。

### 下载文件

- 文件：`AUV_Mac_0.18.7_Universal.zip`
- 大小：**15,708,085 字节**
- SHA-256：

```text
15907245e3b003d2e2c64fc90e14370e836a8858c056d00a3fb6d8d86c5f09ce
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
