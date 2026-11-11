# AUV Windows 0.18.6

**Windows stable · version 0.18.6 · build 20261111.1 · Windows 11 x64 · portable ZIP · unsigned.**

[Download AUV_Win_0.18.6.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.6-win/AUV_Win_0.18.6.zip) · [Install or upgrade](../INSTALLATION.md#windows-installation-guide) · [Claude browser companion guide](../../windows/docs/claude-browser-companion.md)

## What's new

Connecting Claude takes fewer steps, Claude's bars look like Codex's, and the whole app looks and moves better.

- **One Connect button.** The Claude page shows **Connect Claude**. One confirmation sets up the browser companion. A three-step checklist then ticks itself: registered, extension loaded in Chrome or Edge, signed in to claude.ai. **Load in Chrome** and **Load in Edge** copy the extension folder's path and open the browser's extensions page; **Open claude.ai** opens the sign-in page, where you sign in yourself. Once everything is ticked, the checklist folds into one line: "Connected · Chrome · last reading 17:39".
- **Claude's bars in Codex's colours.** Claude's quota bars, its agent-list fill, the tray panel and the Desktop Wizard row now turn green or red by the same rule as Codex. When Claude's plan is unknown, which is the case for browser readings, red starts below 20% remaining.
- **The companion stays in the AUV folder.** AUV now uses the companion where it ships, in `BrowserCompanion\` inside the AUV folder, instead of copying it to `%LOCALAPPDATA%`. Load `BrowserCompanion\extension` once in Chrome or Edge. A new AUV folder needs one more load; AUV moves its registration there by itself and shows the step again. Coming from 0.18.5, AUV offers to delete its old copy, and finishes the job after the browser closes if a file is still in use. Put AUV in a folder you can write to, not under Program Files.
- **Fewer things to think about.** The browser, the placement of the Usage page and the open-browser question move into a collapsed **Advanced** group. A failure on the Claude card comes with the button that fixes it, such as Open claude.ai or the extensions page.
- **Future updates reload the extension themselves.** From this version, AUV can ask an extension from an older build to reload itself. Extensions from 0.18.5 do not know this request yet, so after this upgrade, reload or load the extension once by hand.
- **A cleaner look, with restrained motion.**
  - Cards share one corner radius and spacing; the light theme gets a soft shadow.
  - The agent list and Settings show hover and selection more clearly, with a sliding selection bar. Keyboard focus shows a clear ring.
  - Pages fade in, the refresh icon spins while refreshing, status messages cross-fade, and windows and the tray panel open smoothly.
  - Motion is off when Windows "Show animations" is off or in high contrast.
  - The quota bars and the Desktop Wizard look exactly as before.

Settings from 0.18.5, 0.18.4 and 0.16.x carry over. Claude browser sync stays off until you connect it.

## What Windows still does not have

- **Claude Code's local estimate and Antigravity** are still unavailable on Windows.
- **No store listing.** The extension loads in Developer mode, and the browser may say so.
- The rest is as in [0.18.4](AUV_Win_0.18.4.md#what-windows-does-not-have-and-why): tray icon instead of a number, no signing, Sectorium interface only, no launch at login.

## Verification and limits

Developer checks on one Windows 11 x64 machine, against this package's binaries:

- **301 automated tests passed**, 0 failed.
- **Native checks:** 138 product, 47 refinement and 31 feature checks passed (feature checks also with motion off); 12 layout cases with 48 captures and the desktop render check completed; 40 UI captures; companion checks 86/86; Claude Connect flow checks passed; 10 live Codex provider checks passed, also from the final ZIP.
- **Live, before packaging, with a build of the same code in Chrome on a Chinese claude.ai account:** Connect, the checklist and the reading on connect worked, Claude's bars showed green. Removing the 0.18.5 copy left one file a browser still had open; that case is now handled and covered by tests, but was not retried live.

Not tried live: Edge with this version, AUV under Program Files, and the self-reload request (covered by automated checks, since no extension in use yet understands it). These are developer checks on one machine, not independent QA.

## Download identity

- File: `AUV_Win_0.18.6.zip`
- Size: **71,566,976 bytes**
- SHA-256:

```text
8f8d54c6f910cb9392b2c3ae05749f70d7ac87ac7a4108f0bb95c88e0645f2c3
```

See also `HASHES.txt` and `RELEASE-MANIFEST.json` on the release. AUV for Mac stays at [0.18.4](AUV_Mac_0.18.4.md) and is unchanged.

[Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**Windows 稳定版 · 版本 0.18.6 · 构建号 20261111.1 · Windows 11 x64 · 便携 ZIP · 未签名。**

[下载 AUV_Win_0.18.6.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.6-win/AUV_Win_0.18.6.zip) · [安装与升级](../INSTALLATION.md#windows-中文安装指南) · [浏览器伴侣使用说明](../../windows/docs/claude-browser-companion.md#中文)

### 本版更新

连接 Claude 的步骤更少了，Claude 的额度条和 Codex 用同样的颜色，整个应用的外观和动效也更好了。

- **一个“连接”按钮。** Claude 页面会显示“连接 Claude”。确认一次就完成浏览器伴侣的设置。之后的三步清单会自动打勾：已注册、扩展已在 Chrome 或 Edge 中加载、已登录 claude.ai。“在 Chrome 中加载”“在 Edge 中加载”会复制扩展文件夹路径并打开浏览器扩展页；“打开 claude.ai”会打开登录页，由你自己登录。全部完成后，清单收起为一行，例如“已连接 · Chrome · 上次读数 17:39”。
- **Claude 额度条使用 Codex 的颜色。** Claude 的额度条、智能体列表中的填充、托盘面板和桌面浮窗中的这一行，都按与 Codex 相同的规则显示绿色或红色。Claude 套餐未知时（浏览器读数都是如此），剩余低于 20% 显示红色。
- **伴侣留在 AUV 文件夹中。** AUV 直接使用随包附带的 `BrowserCompanion\`，不再复制到 `%LOCALAPPDATA%`。在 Chrome 或 Edge 中加载一次 `BrowserCompanion\extension` 即可。换用新的 AUV 文件夹时需要再加载一次；AUV 会自动把注册改到新文件夹，并重新显示这一步。从 0.18.5 升级时，AUV 会询问是否删除旧副本；如果有文件仍被浏览器占用，会在浏览器关闭后自动删完。请把 AUV 放在可写的文件夹中，不要放在 Program Files 下。
- **要操心的选项更少。** 浏览器、用量页打开位置、是否询问打开浏览器都收进默认折叠的“高级”分组。Claude 卡片上的失败原因旁边会附带对应的处理按钮，例如“打开 claude.ai”或“打开扩展页”。
- **以后更新时，扩展会自己重新加载。** 从本版起，AUV 可以请较旧构建的扩展自行重新加载。0.18.5 的扩展还不认识这个请求，所以这次升级后需要手动重新加载或加载一次扩展。
- **更整洁的外观和克制的动效。**
  - 卡片统一圆角和间距，浅色主题带柔和投影。
  - 智能体列表和设置的悬停、选中更清楚，有滑动的选中指示条；键盘焦点有清晰的焦点框。
  - 页面淡入，刷新时图标旋转，状态消息交叉淡入淡出，窗口和托盘面板平滑弹出。
  - Windows 关闭“显示动画”或使用高对比度时，动效全部关闭。
  - 额度条和桌面浮窗的外观完全不变。

0.18.5、0.18.4 和 0.16.x 的设置都会沿用。Claude 浏览器同步在你连接之前保持关闭。

### Windows 仍不具备的功能

- **Claude Code 本地估算和 Antigravity** 在 Windows 上仍不可用。
- **未上架商店。** 扩展以开发者模式加载，浏览器可能对此给出提示。
- 其余与 [0.18.4](AUV_Win_0.18.4.md#中文) 相同：托盘显示图标而不是数字，不签名，分区工仅为界面，不提供登录时启动。

### 验证范围与限制

在一台 Windows 11 x64 电脑上，针对本安装包内的二进制完成的开发者自查：

- **301 项自动测试全部通过**，0 项失败。
- **原生检查：** 产品检查 138 项、细节检查 47 项、功能检查 31 项通过（功能检查在关闭动效时也通过）；12 种布局、48 张截图和桌面浮窗渲染检查完成；界面截图 40 张；浏览器伴侣检查 86/86；Claude 连接流程检查通过；10 项 Codex 实时检查通过，并用最终 ZIP 复查。
- **打包前的实机检查（同一代码的测试构建，Chrome，中文 claude.ai 账户）：** “连接”、自动打勾的清单和连上后的自动读取都正常，Claude 额度条显示为绿色。删除 0.18.5 旧副本时，留下了一个仍被浏览器占用的文件；这种情况现已处理并有测试覆盖，但未再次实机复测。

未实机测试：本版在 Edge 中的使用、AUV 放在 Program Files 下的情形，以及扩展自行重新加载（目前在用的扩展还都不认识这个请求，已由自动化检查覆盖）。以上均为一台电脑上的开发者自查，不是独立 QA。

### 下载文件

- 文件：`AUV_Win_0.18.6.zip`
- 大小：**71,566,976 字节**
- SHA-256：

```text
8f8d54c6f910cb9392b2c3ae05749f70d7ac87ac7a4108f0bb95c88e0645f2c3
```

另见 Release 中的 `HASHES.txt` 和 `RELEASE-MANIFEST.json`。Mac 版保持 [0.18.4](AUV_Mac_0.18.4.md#中文)，未改动。

[反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
