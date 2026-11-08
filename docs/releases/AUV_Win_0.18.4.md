# AUV Windows 0.18.4

**Windows stable · version 0.18.4 · build 20261107.1 · Windows 11 x64 · portable ZIP · unsigned.**

[Download AUV_Win_0.18.4.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.4-win/AUV_Win_0.18.4.zip) · [Install or upgrade](../INSTALLATION.md#windows-installation-guide) · [Windows source](../../windows/README.md)

## What's new

AUV for Windows catches up with AUV for Mac 0.18.4 wherever Windows can do the same thing. Windows moves from 0.16.3 straight to 0.18.4 so both platforms share one version number.

- **One Refresh All for every agent.** The toolbar, the footer, the tray menu, the tray panel and F5 all refresh every agent at once. Before, F5 refreshed only the agent you were looking at.
- **Automatic refresh on a schedule you choose.** The new Refresh settings offer every 5, 10, 15, 30 or 60 minutes, plus an optional refresh after Windows wakes. 0.16.3 read Codex every minute with no way to change it. After the upgrade, automatic refresh is on at 5 minutes.
- **The quota window shown is the one that matters.** Where Codex has a five-hour and a seven-day window, AUV shows the one that dropped most since the last reading. A spent window comes first, because a spent five-hour limit stops you even with weekly allowance left. The agent list, the tray panel, the tray tooltip and the Desktop Wizard follow the same rule. The agent page shows both windows, each with its reset time.
- **Your agent order.** Drag an agent in the main window, or use the arrows in Settings → Agents. AUV saves the order by agent as soon as you change it and keeps it across restarts. The tray panel, the tray tooltip and the Desktop Wizard follow it. Restore Default Order puts Codex first again.
- **Choose which agent the tray tooltip shows.** By default it follows your order. You can also pin it to one agent.
- **A redesigned main window.** It uses one type scale and a narrower agent list. Each agent page has three cards: Usage, Connection & Source, and Local Cost Estimate (shown only when you turn it on). Each agent's own settings open from its page.
- **Settings in six panes:** General, Refresh, Agents, System Tray, Desktop Wizard, and Privacy & Data. The Settings window keeps the size you leave it at.
- **ThreadOS moved into Codex settings.** Open it from the ThreadOS row there. A Back to Codex button takes you back. The top bar now keeps AUV and Sectorium. Thinking levels have Chinese labels, so Ultra reads as 超高. Ultra is marked "· ?" because Windows does not check whether the receiving host supports it.
- **English and Chinese.** Settings → General → Language: same as Windows, English, or 中文. The switch applies at once.
- **Optional Local Cost Estimate for Codex, off by default.** When you turn it on in Codex settings, AUV estimates an API-equivalent cost for the last 7 days and in total. It uses the token counters in your local Codex session logs and the same public price table as the Mac. It is not a bill. Prompts, responses and file names are not read.
- **AUV keeps running when Codex misbehaves.** A malformed reply from the Codex app-server could close the whole app when you pressed F5. It now marks Codex as failed and keeps running. If the app-server exits or is replaced, AUV reconnects once. AUV now starts the app-server in its default mode. A failure of the optional token statistics no longer hides a valid allowance.

**Readings stay honest.** Only current, verified readings appear. A Codex reading is current until the refresh interval plus two minutes has passed (15 minutes plus two when automatic refresh is off). After that it is hidden until the next successful read. A verified zero still shows.

**Upgrading keeps your settings.** AUV still uses `%LOCALAPPDATA%\AUV.Windows.UI.Preview`. Your 0.16.x theme, text size, Desktop Wizard, tray, Codex, WorkBuddy and ThreadOS settings carry over unchanged. New settings start at their defaults. The Desktop Wizard looks as it did.

## What Windows does not have, and why

- **Claude has no reading on Windows.** On the Mac, Claude's exact figures come from the Safari companion and Accuracy Sync, and its local estimate comes from Claude Code activity. Safari does not exist on Windows, and the Claude Code routes have not been qualified on Windows. Claude therefore stays unavailable and shows no estimate in place of a reading. Antigravity also stays unavailable.
- **Nothing from Mac 0.18.2–0.18.4 that depends on Safari:** the Safari companion and UMA Safari Bridge, Accuracy Sync, and the Safari open/restart prompts.
- **The tray shows the AUV icon, not a number.** The Mac menu bar shows a percentage. Windows shows the reading in the tray tooltip and the tray panel instead.
- **No Developer ID signing or notarization.** Those are Apple processes. The Windows package is not signed.
- **Sectorium remains an interface only on Windows.** Its storage operations are disabled.
- **No launch at login.** AUV adds no startup item, service or installer on Windows.

## Verification and limits

Developer checks on one Windows 11 x64 machine, against the binaries in this package:

- **198 automated tests passed**, 0 failed (146 carried over from 0.16.3, 52 new).
- **Native checks:** 138 product checks, 47 refinement checks and 31 new 0.18.4 feature checks passed. 12 layout cases / 48 render-density captures and the desktop render check completed.
- **Live, with the installed Codex client:** all 10 provider checks passed. Both Codex windows were read. The six Settings panes, the tray panel and the Desktop Wizard were captured with real data. ThreadOS was opened from Codex settings, and Back to Codex returned to the Codex page.
- **Upgrade:** AUV started on this machine's existing 0.16.3 preferences, which were backed up first. Every earlier setting was kept, and the new settings started at their defaults.
- **Agent order** was kept after a real quit and relaunch.
- **Automatic refresh** at the 5-minute interval fired at 5.0 and 10.0 minutes. Each run produced a new Codex reading.
- **Final package:** it was extracted to a new folder. Its binaries matched the tested ones, and it started and read Codex.

These are developer checks on one Windows 11 x64 machine, not independent QA or clean-machine certification. ARM64, other display scaling settings and other Windows versions were not tested. A real mouse drag in the agent list and a real click on the tray icon were not performed. The same code paths were exercised inside the app, and the order was confirmed to survive a real restart. WorkBuddy sync was not repeated, because it needs a manual sign-in. The Local Cost Estimate was checked with automated tests. On the test machine the current Codex models (GPT-6.x) are not in the public price table, so no amount is shown there; priced coverage reads 0%.

## Download identity

- File: `AUV_Win_0.18.4.zip`
- Size: **65,496,355 bytes**
- SHA-256:

```text
5c227954e0377417247fc8b701933bcf5b4cdf5b029c674ca9ae7e9a7079f5c2
```

See also `HASHES.txt` and `RELEASE-MANIFEST.json` on the release. AUV for Mac stays at [0.18.4](AUV_Mac_0.18.4.md) and is unchanged.

[Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**Windows 稳定版 · 版本 0.18.4 · 构建号 20261107.1 · Windows 11 x64 · 便携 ZIP · 未签名。**

[下载 AUV_Win_0.18.4.zip](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.4-win/AUV_Win_0.18.4.zip) · [安装与升级](../INSTALLATION.md#windows-中文安装指南)

### 本版更新

凡是 Windows 能做到的，AUV Windows 版都与 Mac 版 0.18.4 对齐。版本号直接从 0.16.3 升到 0.18.4，两个平台用同一个版本号。

- **一个“全部刷新”刷新所有智能体。** 工具栏、底栏、托盘菜单、托盘面板和 F5 都会一次刷新所有智能体。此前 F5 只刷新当前查看的智能体。
- **按你选的间隔自动刷新。** 新的“刷新”设置提供 5、10、15、30、60 分钟，以及可选的“Windows 从睡眠唤醒后刷新”。0.16.3 固定每分钟读取一次 Codex，无法更改；升级后自动刷新默认开启，间隔 5 分钟。
- **显示真正要紧的额度窗口。** Codex 同时有 5 小时和 7 天两个窗口时，AUV 显示自上次读数以来下降最多的那个。已用完的窗口优先，因为 5 小时额度用完时，即使周额度还有剩余也无法继续使用。智能体列表、托盘面板、托盘提示和桌面浮窗都遵循同一规则；智能体页面同时列出两个窗口及各自的重置时间。
- **按你的顺序排列智能体。** 在主窗口拖动，或在“设置 → 智能体”中用箭头调整。顺序按智能体保存，改动后立即保存，重启后仍然保留；托盘面板、托盘提示和桌面浮窗都跟随这个顺序。“恢复默认顺序”会让 Codex 重新排在第一位。
- **可指定托盘提示显示哪个智能体。** 默认跟随顺序，也可以固定到某个智能体。
- **重新设计的主窗口。** 字号统一，智能体列表更窄。每个智能体页面只有三张卡片：用量、连接与来源、本地费用估算（开启后才显示）。各智能体自己的设置从其页面打开。
- **设置分为六个分区：** 通用、刷新、智能体、系统托盘、桌面浮窗、隐私与数据。设置窗口会记住你调整后的大小。
- **线程工移到 Codex 设置中。** 在 Codex 设置的线程工一行打开，再用“返回 Codex”按钮回来；顶部只保留 AUV 和分区工。思考档位有中文名称，Ultra 显示为“超高”；由于 Windows 不检查接收端是否支持，Ultra 后面标有“· ?”。
- **中英双语界面。** 设置 → 通用 → 语言：跟随系统、English 或中文，切换立即生效。
- **可选的 Codex 本地费用估算，默认关闭。** 在 Codex 设置中开启后，AUV 根据本地 Codex 会话日志中的令牌计数和与 Mac 版相同的公开价目表，估算近 7 天和累计的 API 等效费用。这不是账单，也不读取提示、回复或文件名。
- **Codex 出问题时 AUV 不再退出。** 此前 Codex app-server 返回格式异常的响应时，按 F5 可能导致整个 App 退出；现在只把 Codex 标为出错，App 继续运行。app-server 退出或被替换时，AUV 会自动重连一次。AUV 现在以默认方式启动 app-server；可选的令牌统计接口出错时，不再影响有效额度的显示。

**读数保持真实。** 只显示当前的、已验证的读数。Codex 读数在“刷新间隔 + 2 分钟”内算当前（关闭自动刷新时为 15 + 2 分钟），超过后隐藏，直到下一次读取成功。已确认的零照常显示。

**升级保留原有设置。** 偏好目录仍为 `%LOCALAPPDATA%\AUV.Windows.UI.Preview`。0.16.x 的外观、字号、桌面浮窗、托盘、Codex、WorkBuddy 和线程工设置原样沿用，新增的设置取默认值。桌面浮窗外观不变。

### Windows 缺少的 Mac 功能及原因

- **Claude 在 Windows 上没有读数。** Mac 上 Claude 的精确读数来自 Safari 伴侣和精确同步，本地估算来自 Claude Code 的本地记录。Windows 没有 Safari，Claude Code 的读取途径也还没有在 Windows 上验证，所以 Claude 仍显示不可用，也不会用估算值代替。Antigravity 同样不可用。
- **Mac 0.18.2–0.18.4 中依赖 Safari 的内容都不适用：** Safari 伴侣与 UMA Safari Bridge、精确同步、打开或重启 Safari 的询问。
- **托盘显示 AUV 图标，不显示数字。** Mac 菜单栏显示百分比；Windows 改为在托盘提示和托盘面板中显示读数。
- **没有 Developer ID 签名和公证。** 这两项属于 Apple 的流程；Windows 包未签名。
- **分区工在 Windows 上仍只有界面，** 存储操作禁用。
- **不提供登录时启动。** AUV 在 Windows 上不添加开机启动项、服务或安装程序。

### 验证范围与限制

以下均针对本安装包内的二进制，在一台 Windows 11 x64 电脑上完成：

- **198 项自动测试全部通过**，0 项失败（146 项沿用自 0.16.3，52 项为新增）。
- **原生检查：** 138 项产品检查、47 项界面检查、31 项 0.18.4 新功能检查全部通过；12 组布局 / 48 张渲染检查和桌面渲染检查完成。
- **实机（使用已安装的 Codex 客户端）：** 10 项 provider 检查全部通过；读到了 Codex 的两个额度窗口；用真实数据截取了设置的六个分区、托盘面板和桌面浮窗；从 Codex 设置打开线程工，再用“返回 Codex”回到 Codex 页面。
- **升级：** 先备份本机已有的 0.16.3 偏好设置，再用它启动 AUV。原有设置全部保留，新增设置取默认值。
- **智能体顺序**在实际退出并重新启动后仍然保留。
- **自动刷新**按 5 分钟间隔分别在第 5.0 和第 10.0 分钟触发，每次都得到新的 Codex 读数。
- **最终安装包**解压到新文件夹后，二进制与受测版本一致，能正常启动并读取 Codex。

以上均为在一台 Windows 11 x64 电脑上的开发者自查，不是独立 QA，也未在干净机器上认证；ARM64、其他显示缩放比例和其他 Windows 版本未测试。没有实际用鼠标拖动智能体列表，也没有实际点击托盘图标；改为在 App 内部执行同一代码路径，并通过实际重启确认顺序会保留。WorkBuddy 同步需要手动登录，本轮未重新测试。本地费用估算由自动测试覆盖；测试电脑上当前使用的 Codex 模型（GPT-6.x）不在公开价目表中，因此不显示金额，计价覆盖率为 0%。

### 下载文件

- 文件：`AUV_Win_0.18.4.zip`
- 大小：**65,496,355 字节**
- SHA-256：

```text
5c227954e0377417247fc8b701933bcf5b4cdf5b029c674ca9ae7e9a7079f5c2
```

另见 Release 中的 `HASHES.txt` 和 `RELEASE-MANIFEST.json`。Mac 版保持 [0.18.4](AUV_Mac_0.18.4.md#中文)，未改动。

[反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
