# AUV Mac 0.18.8

**Build 2026111506 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app (DMG)](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.8/AUV_Mac_0.18.8_Universal.dmg) · [ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.8/AUV_Mac_0.18.8_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

AUV now comes as a disk image, and the full page shows when each limit resets.

- **Install from a DMG.** Open `AUV_Mac_0.18.8_Universal.dmg` and drag **UMA.app** onto the **Applications** shortcut beside it. The disk image is itself signed, notarized and stapled, so it opens without a warning even offline. The ZIP is still published for anyone who prefers it.
- **Reset times on the full page.** Claude's and Codex's pages now show under each 7D and 5H bar when that window resets, for example "Resets in 4 hr (Nov 15, 19:20)". The Quick Panel's reset setting still decides only what the minimalist panel shows.
- **No "sync once" after every restart.** After a restart Claude's last reading comes back as stale, and 0.18.7 then showed the setup's last step, "sync once", again until the next sync. AUV now remembers that the first exact reading arrived and asks for that step only before it. The earlier steps (Safari Bridge, extension, claude.ai access and sign-in) are still checked every time.

The Safari Bridge inside AUV is unchanged: **UMA Safari Bridge 0.14.4**. Claude's exact usage needs Apple silicon, as in 0.18.7.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and the Safari Bridge inside it are each Developer ID signed, Apple notarized and stapled. The DMG is signed, notarized and stapled as well. A copy of the DMG carrying a download quarantine flag passed Gatekeeper, and so did the app inside it; the ZIP passed after a clean re-extraction. The full test suite ran with only known, unrelated failures.

In the installed app, installed from this DMG, both pages showed their reset times, and after a restart Claude's page no longer asked to sync once; the next automatic sync brought exact readings and the plan, Max.

- **Known problem:** a read and its retry can both fail when the Mac is busy, because Safari suspends the hidden page. Claude then shows its last reading until the next sync.
- **Not tried:** whether "Open Safari Settings" opens the Extensions pane directly. Physical Intel Macs and macOS 14/15.

Sectorium is unchanged and was not retested. [Windows is at 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win) and is released separately.

## Download identity

- File: `AUV_Mac_0.18.8_Universal.dmg`
- Size: **18,434,897 bytes**
- SHA-256:

```text
f949de12ff3b72362cef4f23383aae5dd5573e0644370685f6b4188b8ebfa5a6
```

- File: `AUV_Mac_0.18.8_Universal.zip`
- Size: **15,725,150 bytes**
- SHA-256:

```text
b6da0d2a72ac25873219c13cdc46f39101272f02e8db28f4cb5f0109d9c477e6
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026111506 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用（DMG）](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.8/AUV_Mac_0.18.8_Universal.dmg) · [ZIP](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.8/AUV_Mac_0.18.8_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

AUV 改为磁盘映像（DMG）发布；完整页面显示每个额度的重置时间。

- **用 DMG 安装。** 打开 `AUV_Mac_0.18.8_Universal.dmg`，把 **UMA.app** 拖到旁边的 **Applications（应用程序）** 快捷方式上即可。磁盘映像本身也已签名、公证并装订票据，离线也能直接打开，不会出现警告。ZIP 仍然提供，习惯用 ZIP 的可以继续使用。
- **完整页面显示重置时间。** Claude 和 Codex 页面在每个 7D、5H 进度条下方显示该窗口的重置时间，例如“重置 4 小时后 (11月15日 19:20)”。快捷面板的重置时间设置仍只影响极简面板。
- **重启后不再要求“同步一次”。** 重启后 Claude 的上次读数会标记为过期，0.18.7 因此会再次显示设置的最后一步“同步一次”，直到下一次同步。现在 AUV 会记住已经收到过精确读数，只在第一次之前显示这一步。前面几步（Safari 助手、扩展、claude.ai 访问权限和登录）仍然每次检查。

AUV 内置的 Safari 助手没有变化，仍为 **UMA Safari 助手 0.14.4**。与 0.18.7 相同，Claude 精确用量需要 Apple 芯片。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 及其内置的 Safari 助手均已完成 Developer ID 签名、Apple 公证与票据装订；DMG 本身也已签名、公证并装订票据。带下载隔离标记的 DMG 副本及其中的应用通过 Gatekeeper 检查；ZIP 重新解压后通过检查。全量测试中只有已知、与本版无关的失败。

从这个 DMG 安装后，两个页面都显示了重置时间；重启后 Claude 页面不再要求同步一次，下一次自动同步读到了精确读数和套餐 Max。

- **已知问题：** Mac 繁忙时，Safari 会挂起隐藏页面，一次读取和它的重试可能都失败。此时 Claude 显示上次的读数，直到下一次同步。
- **未测试：** “打开 Safari 设置”能否直接打开“扩展”面板；Intel 实机；macOS 14/15。

本版未改动分区工，也未重新测试。[Windows 版为 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win)，单独发布。

### 下载文件

- 文件：`AUV_Mac_0.18.8_Universal.dmg`
- 大小：**18,434,897 字节**
- SHA-256：

```text
f949de12ff3b72362cef4f23383aae5dd5573e0644370685f6b4188b8ebfa5a6
```

- 文件：`AUV_Mac_0.18.8_Universal.zip`
- 大小：**15,725,150 字节**
- SHA-256：

```text
b6da0d2a72ac25873219c13cdc46f39101272f02e8db28f4cb5f0109d9c477e6
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
