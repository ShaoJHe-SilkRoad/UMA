# AUV Mac 0.18.4

**Build 2026110607 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.4/AUV_Mac_0.18.4_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

Claude's automatic refresh recovers by itself when Safari's companion goes quiet, a read that gets no answer is retried within seconds, and Claude no longer turns Unavailable between syncs.

- **Claude stays on screen between syncs.** An exact reading used to count as current for only 5 minutes. With a longer refresh interval, Claude showed "Unavailable" until the next sync. A reading now stays current until shortly after the next sync is due, then stays visible, marked as out of date, for up to 2 hours.
- **Reads that Safari suspends end early and are retried.** Safari can suspend a background tab before the Usage page has been read, and the page then can't do anything until its tab closes. AUV now notices after about 11 seconds instead of waiting 30, and tries again 20 seconds after the sync started. This applies to automatic refresh, Refresh All and reads after a Safari prompt.
- **The Safari companion recovers by itself.** It now gives up on messages that never get a reply, checks every minute that it can still reach AUV, renews a connection that has been idle for 5 minutes, and reloads itself if it stays out of touch.
- **AUV asks when it needs Safari.** If Safari is closed, AUV offers to open it in the background. If the companion stays silent for several minutes, AUV offers to restart Safari. It asks before doing either, and automatic refresh asks only once per stretch; you can tell it to stop asking.
- **Restarting Safari is harder to trigger by accident.** The Restart Safari button can't be clicked for the first 4 seconds, and Return means Not Now. The prompt also says that open windows and tabs may not come back, which is what happens unless Safari is set to reopen them.
- **Repeated commands are dropped.** After the companion's native process was killed, Safari could deliver a command twice. Both copies started a read, the read failed and a tab stayed open. Each command now runs once.
- **ThreadOS moved into Codex's settings.** Open it from the ThreadOS row there; a button takes you back to Codex. Sectorium stays in the toolbar.

**A correction to 0.18.3.** Its notes said one failed sync no longer stops Claude's Accuracy Sync for hours. That was too strong: on one Mac, 0.18.3 still stopped syncing for days after the companion went quiet while Safari kept running.

The Safari side of these fixes is part of **UMA Safari Bridge 0.14.3**. Claude's Accuracy Sync in AUV 0.18.4 needs that Bridge version; with an earlier one it reports a version mismatch and reads nothing.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and Safari Bridge are each Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment. Physical Intel Macs and macOS 14/15 were not tested.

In the installed app, build 2026110606 ran for about an hour at a 5-minute interval. All 13 syncs got a reading: 10 on the first read, and 3 from the retry about 13 seconds after the first read failed. At least two of those failures came while the Mac was running builds. Build 2026110607 changes only the wording of the restart prompt.

Both Safari prompts were tried in the installed app, including accepting them: AUV restarted Safari, opened it in the background, and syncing resumed. In that testing, a click whose source was never identified accepted the restart prompt 3.1 seconds after it appeared, which is why the button now waits.

- **Known problem:** a read and its retry can both fail, especially when the Mac is busy. Claude then shows its last reading until the next sync.
- **Not tried in the installed app:** syncing right after the Mac wakes from sleep, and a retry after a failed first read just after Safari starts, which is covered only by automated tests.

Sectorium is unchanged in this release and was not retested. [Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip).

## Download identity

- File: `AUV_Mac_0.18.4_Universal.zip`
- Size: **14,988,871 bytes**
- SHA-256:

```text
a12dd9f9814b54032ecbb0f845c184311076e7172b11694285006412d7fd62ac
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026110607 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.4/AUV_Mac_0.18.4_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

Safari 伴侣失去响应时，Claude 的自动刷新能自行恢复；没有回应的读取几秒内就会重试；两次同步之间，Claude 也不再显示 Unavailable。

- **两次同步之间读数保持显示。** 此前精确读数只在 5 分钟内算最新。刷新间隔更长时，Claude 会一直显示 Unavailable，直到下一次同步。现在读数在下一次同步到期后不久才算过期，之后最多再显示 2 小时，并标记为已过期。
- **被 Safari 挂起的读取会提前结束并重试。** Safari 可能在用量页读完之前挂起后台标签页，此后页面在标签页关闭前什么也做不了。AUV 现在约 11 秒就能发现，不再等 30 秒，并在这次同步开始 20 秒后重试。自动刷新、全部刷新和 Safari 询问之后的读取都是如此。
- **Safari 伴侣能自行恢复。** 它现在会放弃等不到回复的消息，每分钟检查一次能否联系上 AUV，更新闲置 5 分钟的连接，一直联系不上时还会重新加载自己。
- **需要 Safari 时，AUV 会先询问。** Safari 未运行时，AUV 会询问是否在后台打开；伴侣持续几分钟没有响应时，会询问是否重启 Safari。自动刷新在同一轮问题中只问一次，你也可以让它不再询问。
- **更难误触重启 Safari。** “重启 Safari”按钮在前 4 秒不可点，回车键等于“暂不”。询问里也写明，当前打开的窗口和标签页可能不会恢复；除非 Safari 设置为恢复上次的窗口，否则确实如此。
- **重复命令会被丢弃。** 伴侣的原生进程被终止后，Safari 可能把同一条命令发送两次。两份命令都会启动读取，导致读取失败并留下一个标签页。现在每条命令只执行一次。
- **线程工移到 Codex 的设置中。** 在设置的线程工一行打开，再用按钮返回 Codex。分区工仍在工具栏中。

**更正 0.18.3 的说明。** 0.18.3 的更新说明称，一次同步失败不再让 Claude 精确同步停摆几小时。这个说法过于肯定：在一台 Mac 上，Safari 仍在运行而伴侣失去响应后，0.18.3 仍然连续几天没有同步。

Safari 一侧的修复位于 **UMA Safari Bridge 0.14.3** 中。AUV 0.18.4 的 Claude 精确同步需要该版本的 Bridge；使用更早版本时会提示版本不匹配，且读不到数据。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 与 Safari Bridge 均已完成 Developer ID 签名、Apple 公证与票据装订，并通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

在安装后的应用中，构建 2026110606 以 5 分钟间隔运行了约 1 小时。13 次同步都拿到了读数：10 次第一次读取就成功，3 次在第一次读取失败约 13 秒后由重试补上。其中至少两次失败发生在这台 Mac 正在跑构建的时候。构建 2026110607 只改动了重启询问的文字。

两个 Safari 询问都在安装后的应用中实测过，包括接受它们：AUV 重启了 Safari，也在后台打开过 Safari，之后同步都恢复了。测试中，一次来源始终未查明的点击在询问出现 3.1 秒后接受了重启，所以现在按钮要等几秒才能点。

- **已知问题：** 一次读取和它的重试可能都失败，Mac 繁忙时更容易发生。此时 Claude 显示上次的读数，直到下一次同步。
- **未在安装后的应用中实测：** Mac 刚从睡眠唤醒时的同步，以及 Safari 刚启动、第一次读取失败后的重试（只有自动化测试覆盖）。

本版未改动分区工，也未重新测试。[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)。

### 下载文件

- 文件：`AUV_Mac_0.18.4_Universal.zip`
- 大小：**14,988,871 字节**
- SHA-256：

```text
a12dd9f9814b54032ecbb0f845c184311076e7172b11694285006412d7fd62ac
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
