# AUV Mac 0.17.3

**Build 2026102101 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.3/AUV_Mac_0.17.3_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

This release is about reading Claude's usage at a glance. Codex has had coloured quota bars, a menu bar number and a cost estimate for several versions; Claude had a percentage and little else.

- **Low-usage colour for Claude.** Claude quota bars turn red when little remains and green when plenty does, on the same thresholds Codex uses. Claude does not report which plan you are on, and AUV does not guess one, so you state it yourself: open a Claude agent's settings and set **Claude plan** to Pro or Max. Until you do, the bars stay neutral grey exactly as before.
- **Claude can hold the menu bar number.** The menu bar still prefers Codex. When Codex reports no usable quota it now falls back to the next connected agent instead of showing a dash, and the tooltip and VoiceOver label name whichever agent the number belongs to.
- **Reset times in the menu bar panel.** Each agent row can show when its window resets, following the existing **Show reset times** preference. The main window's agent list stays compact and does not show them; its detail view is one click away.
- **A local cost estimate for Claude.** The Claude page now shows an API-equivalent estimate for the last seven days and lifetime, with the share of tokens it could price. It is calculated on this Mac from local Claude Code activity and public list prices. It is an estimate, not a subscription bill, and AUV reads no billing or payment information.

The app is named **AUV** when opened; the extracted bundle remains **`UMA.app`** for compatible upgrades. Quit the previous copy before replacing it in Applications.

## About the cost estimate and your data

The cost estimate is a new kind of figure for AUV to publish, so its limits are written into the product rather than only into this note. AUV derives it from the aggregate token total it already counted and a fixed public price table. Per-task token counts, per-task timestamps and raw model identifiers stay outside what the Claude connector is permitted to publish, so the estimate cannot be taken apart into individual sessions. Prompts, responses, file names and credentials are never read into AUV.

The figure appears only when this Mac has local Claude Code activity to measure. A Mac that has none will not show the panel.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon, including the Intel executable through Rosetta 2. Physical Intel Macs and macOS 14/15 were not tested. The package is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment after a clean re-extraction.

The colour thresholds, menu bar fallback and reset display were verified by automated tests and rendered review images. The cost panel's data path was verified by test, but the panel itself was not exercised against real data during these release checks. Provider availability still depends on the installed provider app and account.

**Correction, 2026-10-22.** This section originally said the cost panel was not exercised because the Mac used for release checks had no local Claude Code activity. That reason was false: the check behind it used a shell command that failed silently instead of reporting no matches. That Mac did have local Claude Code activity, and in a later build the cost panel was seen rendering real figures from it. The panel genuinely was not exercised at release time — only the reason given for it was wrong.

Sectorium is unchanged in this release and was not re-tested. Its existing guidance stands: keep important data backed up and wait for successful disconnection before unplugging.

[Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip), with its existing support limits. Windows Sectorium is UI only; storage actions are disabled.

## Download identity

- File: `AUV_Mac_0.17.3_Universal.zip`
- Size: **14,591,341 bytes**
- SHA-256:

```text
2822fa3f74f2f51c8f58978e9c497fa2328c6aaa7393ada383f015a7d61a9265
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102101 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.3/AUV_Mac_0.17.3_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

本版的重点是让 Claude 的用量一眼可读。Codex 已有彩色额度条、菜单栏数字和费用估算，而 Claude 此前基本只有一个百分比。

- **Claude 额度不足时显示颜色。** Claude 的额度条在余量偏低时变红、充足时变绿，阈值与 Codex 一致。Claude 不会报告订阅方案，AUV 也不会猜测，因此由你自己说明：打开 Claude 智能体设置，将 **Claude 方案**设为 Pro 或 Max。未说明时，额度条与此前一样保持中性灰色。
- **菜单栏数字可以来自 Claude。** 菜单栏仍优先显示 Codex；当 Codex 没有可用额度时，不再显示短横线，而是改用下一个已连接的智能体，工具提示与旁白标签会说明该数字属于哪个智能体。
- **菜单栏面板显示重置时间。** 每个智能体行可显示本窗口的重置时间，遵循已有的**显示重置时间**设置。主窗口的智能体列表保持紧凑、不显示重置时间，详情页一次点击即可查看。
- **Claude 的本地费用估算。** Claude 页面新增近 7 天与累计的 API 等效估算，并显示可计价令牌的比例。该数值在本机根据本地 Claude Code 活动和公开价目表计算，属于估算而非订阅账单；AUV 不读取任何账单或支付信息。

打开后产品名为 **AUV**，解压所得文件仍为 **`UMA.app`**，以兼容既有安装。替换“应用程序”中的旧版前，请先正常退出旧应用。

### 关于费用估算与你的数据

费用估算是 AUV 新增发布的一类数值，因此其边界写入产品本身，而不只写在这份说明里。AUV 依据已统计的令牌总量和固定的公开价目表得出该数值。单条任务的令牌数、单条任务的时间戳和原始模型标识，仍不在 Claude 连接器允许发布的范围内，因此该估算无法还原为具体会话。提示、回复、文件名和凭据始终不会进入 AUV。

只有当本机存在可统计的本地 Claude Code 活动时才会显示该面板；没有活动的 Mac 不会显示。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成，并通过 Rosetta 2 运行 Intel 程序。尚未测试 Intel 实机或 macOS 14/15。安装包已完成 Developer ID 签名、Apple 公证与票据装订，重新解压后仍通过 Gatekeeper 检查。

颜色阈值、菜单栏回退和重置时间显示已通过自动化测试与渲染审阅图验证。费用面板的数据链路已通过测试验证，但发布验证期间未用真实数据实测面板本身。各智能体能否取得数据，仍取决于其客户端与账户。

**更正（2026-10-22）。** 本节原先称费用面板未实测的原因，是用于发布验证的 Mac 没有本地 Claude Code 活动。该理由不成立：得出它的检查用了一条静默失败、而非报告“无匹配”的 shell 命令。那台 Mac 确有本地 Claude Code 活动，且在后续构建中已见费用面板用这些数据渲染出真实数值。发布时确实未实测该面板——错的只是给出的理由。

本版未改动分区工，也未重新测试。既有提示依然适用：请备份重要数据，断开成功后再拔线。

[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)及原有支持范围；Windows 分区工仅有界面，磁盘操作禁用。

### 下载文件

- 文件：`AUV_Mac_0.17.3_Universal.zip`
- 大小：**14,591,341 字节**
- SHA-256：

```text
2822fa3f74f2f51c8f58978e9c497fa2328c6aaa7393ada383f015a7d61a9265
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
