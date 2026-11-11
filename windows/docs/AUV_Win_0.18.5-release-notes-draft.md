# AUV Windows 0.18.5

> DRAFT, not published. Size, SHA-256 and check counts are from the packaged build (2026-11-11). Move to `docs/releases/AUV_Win_0.18.5.md` only with the user's go-ahead.

**Windows stable · version 0.18.5 · build 20261108.1 · Windows 11 x64 · portable ZIP · unsigned.**

[Download AUV_Win_0.18.5.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.5-win/AUV_Win_0.18.5.zip) · [Install or upgrade](../INSTALLATION.md#windows-installation-guide) · [Claude browser companion guide](../../windows/docs/claude-browser-companion.md)

## What's new

Claude gets exact readings on Windows. A small companion extension for Chrome or Edge does what the Safari companion does on the Mac.

- **Claude's plan limits from claude.ai.** Turn it on in Claude settings and choose Set Up. The AUV Browser Companion reads Claude's five-hour and weekly used percentages and their reset times from claude.ai's official Usage page. Claude's cards then work like Codex's: both windows, the one that matters shown first, and "Resets in 2 hr (Nov 9, 00:30)".
- **English and Chinese Usage pages.** The page reader recognizes claude.ai in English and in Simplified Chinese (当前会话, 本周, 已使用 N%, 星期六06:00 重置). The Mac reader recognizes English only.
- **Your sign-in stays in the browser.** The extension reads only the two percentages, their reset times and when they were read. It never reads or sends passwords, cookies, tokens, conversations or page text. AUV keeps the figures in memory and shows them only while they are current.
- **Syncs on your schedule.** Refresh All, automatic refresh, Sync Claude now and the extension's toolbar button all sync Claude. If a browser window is open, the Usage page opens as an inactive tab and closes after the read. Otherwise it opens in a small minimized window. If that would be the browser's last window, the companion keeps it minimized with a blank tab, because Chrome and Edge quit when their last window closes.
- **It recovers by itself, as on the Mac.** A page that goes silent ends early, and the read is retried 20 seconds after the sync started. The connection reconnects on its own. The companion checks every minute that it can reach AUV.
- **AUV asks before opening a browser.** If the browser is not running, AUV offers to open it minimized. During automatic refresh it asks once per stretch, and you can tell it not to ask. AUV never restarts your browser.

**Off until you turn it on.** Upgrading from 0.18.4 keeps every setting. Claude browser sync starts off and Claude stays unavailable until you set it up.

**Set up once per browser.** The companion is not in the Chrome Web Store or Edge Add-ons yet. Load it on the browser's extensions page with Developer mode → Load unpacked. AUV registers its helper for Chrome and Edge under your Windows account only, with no administrator rights. Remove companion in Claude settings takes that registration out again. See the [guide](../../windows/docs/claude-browser-companion.md).

## What Windows still does not have

- **Claude Code's local estimate and Antigravity** are still unavailable on Windows.
- **No store listing.** The extension loads in Developer mode, and the browser may say so.
- The rest is as in [0.18.4](AUV_Win_0.18.4.md#what-windows-does-not-have-and-why): tray icon instead of a number, no signing, Sectorium interface only, no launch at login.

## Verification and limits

Developer checks on one Windows 11 x64 machine, Chrome 157 and Edge 157, against this package's binaries:

- **256 automated tests passed**, 0 failed.
- **Companion checks in WebView2:** 83 of 83 passed. They cover the Mac's Usage page samples and reset wordings, Chinese samples, the extension's background logic in 20 scenarios, and that three shared scripts are identical to the Mac originals.
- **Native checks:** 138 product checks, 47 refinement checks and 31 feature checks passed; 12 layout cases / 48 captures and the desktop render check completed. With the installed Codex client, all 10 live provider checks passed, also from the final package extracted to a new folder, whose binaries matched the tested ones.
- **Live, on a Chinese claude.ai account:** the readings matched the Usage page exactly. In one hour at the 5-minute interval, 13 of 13 automatic syncs read on the first attempt. The 10- and 30-minute intervals fired on time. Killing the helper recovered in about 2 seconds. Edge-only syncs, minimized-window reads in both browsers, two browsers at once (one is used), the open-browser prompt and Remove companion worked.
- **Found and fixed during live testing:** the helper could reach a stale connection after Update; a browser change synced too early; the browser quit when the read closed its last window; an outdated extension in one browser hid a working one. Each has a test; the last fix was checked by its test only, not again live.

Not tried live: a claude.ai sign-out, site access set to "on click", syncing right after the PC wakes from sleep, and Edge running in the background with no window (covered by automated scenarios). These are developer checks on one machine, not independent QA.

## Download identity

- File: `AUV_Win_0.18.5.zip`
- Size: **71,629,804 bytes**
- SHA-256:

```text
663ad6bc4706b4ba0aef5317f5d3d5c207c303228d0f37c6a75105390c40474c
```

AUV for Mac stays at [0.18.4](AUV_Mac_0.18.4.md). A patch that adds the same Chinese reading to the Mac is in [windows/docs/extractor-zh-patch-for-mac.md](../../windows/docs/extractor-zh-patch-for-mac.md).

[Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**Windows 稳定版 · 版本 0.18.5 · 构建号 20261108.1 · Windows 11 x64 · 便携 ZIP · 未签名。**

### 本版更新

Claude 在 Windows 上有了精确读数：Chrome 或 Edge 中的一个小型伴侣扩展，完成 Mac 上 Safari 伴侣做的事。

- **从 claude.ai 读取 Claude 的套餐额度。** 在 Claude 设置中开启并选择“设置”后，AUV 浏览器伴侣会从 claude.ai 官方用量页读取 5 小时和每周窗口的已用百分比及重置时间。Claude 卡片的显示方式与 Codex 相同：两个窗口都显示，优先显示更要紧的那个，并给出“2 小时后重置（11月9日 00:30）”这样的重置时间。
- **支持英文和中文用量页。** 能识别英文和简体中文界面（当前会话、本周、已使用 N%、星期六06:00 重置）。Mac 版目前只认英文。
- **登录状态留在浏览器中。** 扩展只读取两个百分比、各自的重置时间和读取时间，从不读取或发送密码、Cookie、令牌、对话或页面文字。AUV 只在内存中保留这些读数，且只在读数仍算当前时显示。
- **按你的刷新计划同步。** “全部刷新”、自动刷新、“立即同步 Claude”和扩展的工具栏按钮都会同步 Claude。有浏览器窗口时，用量页在非活动标签页中打开，读完即关闭；没有窗口时，在一个最小化的小窗口中打开。如果这个小窗口会是浏览器的最后一个窗口，伴侣会把它保留为带空白标签页的最小化窗口，因为 Chrome 和 Edge 关闭最后一个窗口时会退出。
- **与 Mac 一样能自行恢复。** 页面沉默时提前结束这次读取，并在同步开始 20 秒后重试一次；连接断开后自动重连；伴侣每分钟检查一次能否联系上 AUV。
- **打开浏览器前先询问。** 浏览器未运行时，AUV 会询问是否以最小化方式打开它。自动刷新时同一轮只问一次，也可以选择不再询问。AUV 不会替你重启浏览器。

**默认关闭。** 从 0.18.4 升级会保留所有设置。Claude 浏览器同步默认关闭，设置完成前 Claude 仍显示不可用。

**每个浏览器设置一次。** 伴侣尚未上架 Chrome 应用商店或 Edge 加载项商店，需要在浏览器扩展页通过“开发者模式 → 加载已解压的扩展程序”加载。AUV 只在你的 Windows 账户下为 Chrome 和 Edge 注册辅助程序，不需要管理员权限；在 Claude 设置中选择“移除伴侣”即可删除注册。详见[使用说明](../../windows/docs/claude-browser-companion.md)。

### Windows 仍不具备的功能

- **Claude Code 本地估算和 Antigravity** 在 Windows 上仍不可用。
- **未上架商店。** 扩展以开发者模式加载，浏览器可能对此给出提示。
- 其余与 [0.18.4](AUV_Win_0.18.4.md#中文) 相同：托盘显示图标而不是数字，不签名，分区工仅为界面，不提供登录时启动。

### 验证范围与限制

在一台 Windows 11 x64 电脑（Chrome 157、Edge 157）上，针对本安装包内的二进制完成的开发者自查：

- **256 项自动测试全部通过**，0 项失败。
- **WebView2 中的伴侣检查：** 83 of 83 通过。覆盖 Mac 的用量页样例与重置写法、中文样例、扩展后台逻辑的 20 个场景，以及三个共享脚本与 Mac 原件一致。
- **原生检查：** 138 项产品检查、47 项界面检查、31 项功能检查全部通过；12 组布局 / 48 张渲染检查和桌面渲染检查完成。使用已安装的 Codex 客户端，10 项实时 provider 检查全部通过；最终安装包解压到新文件夹后，二进制与受测版本一致，同样通过了这 10 项检查。
- **实机（中文 claude.ai 账户）：** 读数与用量页完全一致。5 分钟间隔连续运行 1 小时，13 次自动同步全部一次成功；10 分钟和 30 分钟间隔按时触发。结束辅助程序后约 2 秒恢复。只用 Edge 同步、两个浏览器的最小化窗口读取、两个浏览器同时连接（只用一个）、询问是否打开浏览器和移除伴侣都正常。
- **实测中发现并已修复：** 更新后辅助程序可能连到旧连接；切换浏览器时同步过早；读取关闭最后一个窗口时浏览器随之退出；一个浏览器中的旧扩展掩盖了另一个正常的浏览器。每一项都有对应测试；最后一项只经测试验证，未再次实机复测。

未实机测试：claude.ai 退出登录、站点访问改为“点击时”、电脑刚从睡眠唤醒时的同步，以及 Edge 在后台运行但没有窗口的情形（已有自动化场景覆盖）。以上均为一台电脑上的开发者自查，不是独立 QA。

### 下载文件

- 文件：`AUV_Win_0.18.5.zip`
- 大小：**71,629,804 字节**
- SHA-256：

```text
663ad6bc4706b4ba0aef5317f5d3d5c207c303228d0f37c6a75105390c40474c
```

Mac 版保持 [0.18.4](AUV_Mac_0.18.4.md#中文)。为 Mac 加入同样中文读取能力的补丁见 [windows/docs/extractor-zh-patch-for-mac.md](../../windows/docs/extractor-zh-patch-for-mac.md)。

[反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
