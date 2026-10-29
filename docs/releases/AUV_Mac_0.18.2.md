# AUV Mac 0.18.2

**Build 2026102803 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.2/AUV_Mac_0.18.2_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

Claude's cards show when its limit resets again, in the same form as Codex.

- **Claude's reset time is back.** claude.ai's redesigned Usage page shows a reset only as text, such as "Resets at 6:40 PM" or "Resets Saturday 9:00 AM". Accuracy Sync did not read that text, so Claude's cards on the Desktop Assistant, the menu bar and the main window showed no reset. AUV now reads it in your Mac's time zone and shows it like Codex's: "Resets in 2 hr (Oct 28, 18:40)".
- **A reset that cannot be read stays blank rather than wrong.** A time further ahead than the window is long, or a wording AUV does not know, is not shown. A countdown such as "Resets in 2 hr 5 min" is not read either, because readings a minute apart would look like different windows. While Claude's five-hour window has not started, claude.ai shows no reset, so none is shown.

The new page reader is part of **UMA Safari Bridge 0.14.1**. Claude's Accuracy Sync in AUV 0.18.2 needs that Bridge version; with an earlier one it reports a version mismatch and reads nothing.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and Safari Bridge are each Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment. Physical Intel Macs and macOS 14/15 were not tested.

New tests read each reset wording against saved copies of the Usage page. In the installed app, an Accuracy Sync saved reset times for both of Claude's windows.

Sectorium is unchanged in this release and was not retested. [Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip).

## Download identity

- File: `AUV_Mac_0.18.2_Universal.zip`
- Size: **14,910,449 bytes**
- SHA-256:

```text
3b45b66e748ec0ac9696fe5075578cfbf0d759fb41ccb20f29466dda17fff0f5
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102803 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.2/AUV_Mac_0.18.2_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

Claude 卡片重新显示额度重置时间，格式与 Codex 一致。

- **Claude 的重置时间恢复显示。** claude.ai 改版后的用量页只以文字显示重置时间，例如“Resets at 6:40 PM”“Resets Saturday 9:00 AM”。精确同步此前没有读取这些文字，所以桌面助手、菜单栏和主窗口里 Claude 的卡片都没有重置时间。现在 AUV 按你 Mac 的时区读取，并以与 Codex 相同的格式显示：“2 小时后重置（10月28日 18:40）”。
- **读不准的重置时间留空，不显示错误时间。** 超出窗口长度的时间、AUV 不认识的写法都不显示。倒计时写法（如“Resets in 2 hr 5 min”）也不读取，因为相隔一分钟的读数会被当成不同窗口。Claude 的 5 小时窗口尚未开始时，claude.ai 不显示重置时间，AUV 也不显示。

新的页面读取逻辑位于 **UMA Safari Bridge 0.14.1** 中。AUV 0.18.2 的 Claude 精确同步需要该版本的 Bridge；使用更早版本时会提示版本不匹配，且读不到数据。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 与 Safari Bridge 均已完成 Developer ID 签名、Apple 公证与票据装订，并通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

新增测试用保存的用量页副本逐一验证各种重置时间写法。在安装后的应用中，一次精确同步为 Claude 的两个窗口都保存了重置时间。

本版未改动分区工，也未重新测试。[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)。

### 下载文件

- 文件：`AUV_Mac_0.18.2_Universal.zip`
- 大小：**14,910,449 字节**
- SHA-256：

```text
3b45b66e748ec0ac9696fe5075578cfbf0d759fb41ccb20f29466dda17fff0f5
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
