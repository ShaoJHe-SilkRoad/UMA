# AUV Windows 0.18.7

**Windows stable · version 0.18.7 · build 20261116.1 · Windows 11 x64 · portable ZIP · unsigned.**

[Download AUV_Win_0.18.7.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.7-win/AUV_Win_0.18.7.zip) · [Install or upgrade](../INSTALLATION.md#windows-installation-guide) · [Claude browser companion guide](../../windows/docs/claude-browser-companion.md)

## What's new

Three fixes for the Desktop Wizard, the tray panel and the main window, and AUV's new icon.

- **The Desktop Wizard opens again.** If "Enable Desktop Wizard" was off, showing the Wizard did nothing and said nothing. This happened from the bottom button, Ctrl+Shift+W, the tray panel, the tray menu and Settings. Showing the Wizard now also turns it on; hiding it leaves the setting alone. If the Wizard is on but no agent has a reading yet, the status line says so. The Wizard looks exactly as before.
- **Tray Usage panel clicks.** When the panel was open, clicking the tray icon closed it and opened it again at once, and a double click made it flash and disappear. Now a click on the tray icon while the panel is open closes it, and a double click keeps it open. The panel button in the main window behaves the same way.
- **The main window keeps its size, and says where it went.**
  - A maximized window comes back maximized after minimizing, after settings are saved while it is minimized, and when you choose **Open AUV** in the tray.
  - The first time AUV hides to the tray, Windows shows a one-time notice that AUV is still running and where its icon is. Windows often puts the icon of a new AUV folder in the hidden icons (^); drag it onto the taskbar to keep it visible.
- **New icon.** AUV uses the same "B3" icon as AUV for Mac: in the taskbar, the tray, window title bars, Explorer, and for the browser extension.

Settings from 0.18.6, 0.18.5, 0.18.4 and 0.16.x carry over. One new setting records that the tray notice has been shown; older settings files read it as not shown.

## What Windows still does not have

- **Claude Code's local estimate and Antigravity** are still unavailable on Windows.
- **No store listing.** The browser extension loads in Developer mode, and the browser may say so.
- **Claude's plan is not read on Windows yet.** AUV for Mac now reads the plan from the Usage page; the Windows companion still ships the earlier scripts and reads only the percentages and reset times.
- The rest is as in [0.18.4](AUV_Win_0.18.4.md#what-windows-does-not-have-and-why): tray icon instead of a number, no signing, Sectorium interface only, no launch at login.

## Verification and limits

Developer checks on one Windows 11 x64 machine, against this package's binaries:

- **309 automated tests passed**, 0 failed, including 8 new tests for the Wizard, tray panel and window-state fixes.
- **Native checks:** 137 product checks (the per-monitor check ran on the one connected display), 47 refinement and 31 feature checks passed (feature checks also with motion off); 12 layout cases with 48 captures and the desktop render check completed; 40 UI captures; companion checks 86/86; Claude Connect flow checks passed; 25 new tray, Wizard and minimize checks passed, also with motion off; 10 live Codex provider checks passed, also from the final ZIP.
- **Live, before packaging:** the Wizard fix was reproduced and confirmed on the developer's own settings, and the Wizard was compared pixel by pixel with 0.18.6 (no difference). The new icon was checked at 125% scaling with the dark theme: taskbar, tray overflow, snap-layout window icons and AUV.exe in Explorer.

Not verified live:

- **Real mouse clicks.** The tray icon, the tray panel and minimizing were driven by window messages and UI Automation, not a physical mouse. Clicks on the icon inside the hidden-icons (^) area were not tried.
- **The tray notice** has not actually been shown; only its rule is covered by tests.
- **AUV closing by itself after minimizing** was reported but never reproduced: the process kept running. Most likely AUV was hidden to the tray with its icon in the hidden-icons area; the notice above addresses that, but this is a judgement, not a proven cause.
- **The icon** in Alt+Tab, at 150% or 200% scaling, with the light theme, and in Chrome or Edge's extension list.

These are developer checks on one machine, not independent QA.

## Download identity

- File: `AUV_Win_0.18.7.zip`
- Size: **70,461,229 bytes**
- SHA-256:

```text
a16ac520c8a929148eda4086e1ecab27606f630e0b9e413d1310861a60bc38a2
```

See also `HASHES.txt` and `RELEASE-MANIFEST.json` on the release. AUV for Mac is released separately and is unchanged by this release.

[Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**Windows 稳定版 · 版本 0.18.7 · 构建号 20261116.1 · Windows 11 x64 · 便携 ZIP · 未签名。**

[下载 AUV_Win_0.18.7.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.7-win/AUV_Win_0.18.7.zip) · [安装与升级](../INSTALLATION.md#windows-中文安装指南) · [浏览器伴侣使用说明](../../windows/docs/claude-browser-companion.md#中文)

### 本版更新

修复了桌面浮窗、托盘面板和主窗口的三个问题，并换用 AUV 的新图标。

- **桌面浮窗又能打开了。** 以前如果“启用桌面浮窗”被关掉，点“显示桌面浮窗”没有任何反应，也没有提示。底部按钮、Ctrl+Shift+W、托盘面板、托盘菜单和设置里的入口都是这样。现在显示浮窗会同时把它启用；隐藏时不改动这项设置。浮窗已启用但还没有任何智能体读数时，状态栏会说明。浮窗外观完全不变。
- **托盘用量面板的点击。** 以前面板打开时再点托盘图标，面板会关掉又马上打开；双击则一闪就消失。现在面板打开时点托盘图标会关闭面板，双击会让面板保持打开。主窗口里的面板按钮也一样。
- **主窗口保持原来的大小，并告诉你它去了哪里。**
  - 最大化的窗口在最小化后、最小化期间保存设置后，以及从托盘选择“打开 AUV”时，都会恢复为最大化。
  - 第一次隐藏到托盘时，Windows 会弹出一次通知，说明 AUV 仍在运行以及图标在哪里。Windows 常把新 AUV 文件夹的图标放进隐藏图标（^）里；把图标拖到任务栏上即可一直显示。
- **新图标。** AUV 使用与 Mac 版相同的“B3”图标：任务栏、托盘、窗口标题栏、文件资源管理器，以及浏览器扩展。

0.18.6、0.18.5、0.18.4 和 0.16.x 的设置都会沿用。新增的一项设置记录托盘通知是否已显示；旧的设置文件按“未显示”读取。

### Windows 仍不具备的功能

- **Claude Code 本地估算和 Antigravity** 在 Windows 上仍不可用。
- **未上架商店。** 浏览器扩展以开发者模式加载，浏览器可能对此给出提示。
- **Windows 版还读不到 Claude 的套餐。** Mac 版现在会从用量页读取套餐；Windows 伴侣仍附带之前的脚本，只读取百分比和重置时间。
- 其余与 [0.18.4](AUV_Win_0.18.4.md#中文) 相同：托盘显示图标而不是数字，不签名，分区工仅为界面，不提供登录时启动。

### 验证范围与限制

在一台 Windows 11 x64 电脑上，针对本安装包内的二进制完成的开发者自查：

- **309 项自动测试全部通过**，0 项失败，其中 8 项是针对浮窗、托盘面板和窗口状态修复的新测试。
- **原生检查：** 产品检查 137 项（逐显示器检查在当前唯一连接的显示器上运行）、细节检查 47 项、功能检查 31 项通过（功能检查在关闭动效时也通过）；12 种布局、48 张截图和桌面浮窗渲染检查完成；界面截图 40 张；浏览器伴侣检查 86/86；Claude 连接流程检查通过；新增的托盘、浮窗和最小化检查 25 项通过，关闭动效时也通过；10 项 Codex 实时检查通过，并用最终 ZIP 复查。
- **打包前的实机检查：** 用开发者自己的设置复现并确认了浮窗修复，并与 0.18.6 的浮窗逐像素比较（无差异）。新图标在 125% 缩放、深色主题下检查过：任务栏、托盘溢出区、贴靠布局中的窗口图标，以及文件资源管理器中的 AUV.exe。

未经实机验证：

- **真实鼠标点击。** 托盘图标、托盘面板和最小化是通过窗口消息和 UI 自动化驱动的，没有用实体鼠标点击。在隐藏图标（^）区域里点击图标的情况没有试过。
- **托盘通知**还没有真正弹出过，只有判定规则由测试覆盖。
- **最小化后 AUV 自行退出**的问题有人报告过，但一直没有复现：进程始终在运行。最可能的情况是 AUV 被隐藏到托盘，而图标在隐藏图标区里；上面的通知就是针对这一点，但这只是判断，不是已证实的原因。
- **新图标**在 Alt+Tab、150% 或 200% 缩放、浅色主题，以及 Chrome 或 Edge 扩展列表中的显示。

以上均为一台电脑上的开发者自查，不是独立 QA。

### 下载文件

- 文件：`AUV_Win_0.18.7.zip`
- 大小：**70,461,229 字节**
- SHA-256：

```text
a16ac520c8a929148eda4086e1ecab27606f630e0b9e413d1310861a60bc38a2
```

另见 Release 中的 `HASHES.txt` 和 `RELEASE-MANIFEST.json`。Mac 版单独发布，本次发布不改动 Mac 版。

[反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
