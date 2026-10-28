# AUV Mac 0.18.0

**Build 2026102801 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.0/AUV_Mac_0.18.0_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

A redesigned main window and Settings, one Refresh All for every agent, and Claude readings that stay put.

- **A cleaner main window.** One type scale across the window, a narrower agent rail with a new level fill, and an agent page that keeps only the cards you act on: Usage, Connection & Source, and Local Cost Estimate. Claude's actions appear only when something needs doing.
- **Settings in six panes.** General, Refresh, Agents, Menu Bar, Desktop Assistant, and Privacy & Data, each with one place for each setting. Each agent's own settings open from its page.
- **Refresh All includes Claude's Accuracy Sync.** Once you have allowed it, one Refresh All, from the toolbar, the menu bar or the Quick Panel, refreshes every agent and brings Claude's exact figures.
- **Automatic refresh every 5, 15, 30 or 60 minutes, Claude included.** The new Refresh pane sets one schedule for every agent. Claude's part runs only while Safari is already open and never starts it. If you had the old 10-minute Accuracy Sync switch on, automatic refresh is turned on for you once.
- **The window that matters is the one shown.** Where an agent has a five-hour and a seven-day limit, AUV shows the one that changed most recently. A spent window comes first, because a spent five-hour limit stops you even with weekly allowance left. The main list, the agent page, the menu bar and the Desktop Assistant all follow the same rule.
- **Claude stays on the Desktop Assistant.** It no longer drops off after an Accuracy Sync or a rescan.
- **Claude reads the redesigned claude.ai Usage page.**
- **Smaller fixes.** Claude's local activity reading uses far less CPU. You can arrange agents everywhere and pin the menu bar to one. Google Antigravity has its own mark. The Settings window keeps the size you leave it at.

## What this does not change

The Desktop Assistant capsule looks as it did. Which agents are found and how usage figures are calculated are unchanged. Your saved settings and agent order carry over.

The app is named **AUV** when opened; the extracted bundle remains **`UMA.app`** for compatible upgrades. Quit the previous copy before replacing it in Applications.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. The package is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment. Physical Intel Macs and macOS 14/15 were not tested.

The full test suite passed apart from known environmental failures: Sectorium's own disk tests and timing-sensitive helper tests under full load. Refresh All with Accuracy Sync, the most-changeable window and Claude on the Desktop Assistant were checked in the installed app.

Sectorium is unchanged in this release and was not retested.

[Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip), with its existing support limits. Windows Sectorium is UI only; storage actions are disabled.

## Download identity

- File: `AUV_Mac_0.18.0_Universal.zip`
- Size: **14,907,253 bytes**
- SHA-256:

```text
dd506dde11ff662bc685915207641e5ade2409f0fae839973b0b7305c014c55c
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

# AUV Mac 0.18.0

**构建号 2026102801 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.0/AUV_Mac_0.18.0_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

重新设计的主窗口与设置；一次"全部刷新"覆盖所有智能体；Claude 读数不再消失。

- **更清爽的主窗口。** 全窗口统一字号体系；左侧智能体栏变窄，用量填充重新设计；智能体页只保留需要操作的卡片：用量、连接与来源、本地费用估算。Claude 的操作只在需要时出现。
- **设置分为六个面板。** 通用、刷新、智能体、菜单栏、桌面助手、隐私与数据，每项设置只有一个位置。各智能体自己的设置从它的页面打开。
- **"全部刷新"包含 Claude 精确同步。** 在你允许之后，从工具栏、菜单栏或快捷面板点一次"全部刷新"，即刷新所有智能体，并取得 Claude 的精确数值。
- **自动刷新可设为每 5、15、30 或 60 分钟，包含 Claude。** 新的"刷新"面板为所有智能体设定同一个频率。Claude 部分只在 Safari 已打开时运行，绝不自行启动 Safari。如果你之前开着旧的"每 10 分钟精确同步"开关，自动刷新会为你开启一次。
- **显示最要紧的那个窗口。** 智能体同时有 5 小时和 7 天限额时，AUV 显示最近变化最大的那个；已用完的窗口优先，因为 5 小时限额用完后，即使周额度还有也无法使用。主列表、智能体页、菜单栏和桌面助手都遵循同一规则。
- **Claude 留在桌面助手上。** 精确同步或重新扫描后不再消失。
- **Claude 可读取 claude.ai 改版后的用量页。**
- **其他修复。** Claude 本地活动读取的 CPU 占用大幅降低；智能体可在各处排序，菜单栏可固定显示某一智能体；Google Antigravity 有了自己的图标；设置窗口记住你调整后的大小。

### 本版不改变的事

桌面助手胶囊外观不变。能找到哪些智能体、用量数值的计算方式不变。已保存的设置与智能体顺序保留。

打开后产品名为 **AUV**，解压所得文件仍为 **`UMA.app`**，以兼容既有安装。替换"应用程序"中的旧版前，请先正常退出旧应用。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。安装包已完成 Developer ID 签名、Apple 公证与票据装订，并通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

完整测试套件通过，仅余已知的环境相关失败：分区工自身的磁盘测试，以及满负载下对时序敏感的辅助程序测试。含精确同步的"全部刷新"、最大变化窗口规则、Claude 留在桌面助手上，均已在安装后的应用中确认。

本版未改动分区工，也未重新测试。

[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)及原有支持范围；Windows 分区工仅有界面，磁盘操作禁用。

### 下载文件

- 文件：`AUV_Mac_0.18.0_Universal.zip`
- 大小：**14,907,253 字节**
- SHA-256：

```text
dd506dde11ff662bc685915207641e5ade2409f0fae839973b0b7305c014c55c
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
