# AUV Mac 0.18.3

**Build 2026102903 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.3/AUV_Mac_0.18.3_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

Claude's Accuracy Sync keeps working when Safari is on another desktop or minimized, and one failed sync no longer stops it for hours.

- **Safari on another desktop or minimized.** Before each sync AUV checks whether Safari has a window on the current desktop. When it has none, the sync opens claude.ai's Usage page in a small window of its own and closes it afterwards. This applies to Refresh All and to automatic refresh. In testing, the window opened on Safari's own desktop and did not take the front.
- **One failed sync no longer blocks the next ones.** A sync whose page never answered could leave Claude at "Browser Companion is starting…" until Safari was restarted. Three causes are fixed:
  - the connection between Safari and AUV now keeps reconnecting instead of giving up after one try;
  - the record of an unanswered sync is cleared when the next sync starts;
  - AUV no longer waits on a sync it has already given up on.
- **Updating the Safari companion no longer leaves a stale record behind.** An unfinished record from the previous companion version used to refuse every sync after an update. It is now discarded once it has expired.

The Safari side of these fixes is part of **UMA Safari Bridge 0.14.2**. Claude's Accuracy Sync in AUV 0.18.3 needs that Bridge version; with an earlier one it reports a version mismatch and reads nothing.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV and Safari Bridge are each Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment. Physical Intel Macs and macOS 14/15 were not tested.

In the installed app, Claude's exact figures were read with Safari's only window on another desktop, and again with Safari minimized. New tests run the companion's background page against a stand-in for Safari and cover the temporary window, reconnecting, and clearing old records.

Sectorium is unchanged in this release and was not retested. [Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip).

## Download identity

- File: `AUV_Mac_0.18.3_Universal.zip`
- Size: **14,926,083 bytes**
- SHA-256:

```text
eb5ff0036123c530e9e8bd6a03674f03411743cc0e3324dbc5009dabc1bbe4e4
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102903 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.3/AUV_Mac_0.18.3_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

Safari 在另一个桌面或最小化时，Claude 精确同步也能正常进行；一次同步失败不再让它连续几小时停摆。

- **Safari 在另一个桌面或最小化。** 每次同步前，AUV 先检查 Safari 在当前桌面是否有窗口。没有时，同步会单独开一个小窗口打开 claude.ai 用量页，读完再关闭。"全部刷新"和自动刷新都是如此。测试中，这个窗口开在 Safari 自己所在的桌面，没有跑到最前面。
- **一次失败不再挡住之后的同步。** 此前，一次页面没有回应的同步，可能让 Claude 一直停在"浏览器伴侣正在启动…"，直到重启 Safari。修复了三处原因：
  - Safari 与 AUV 之间的连接断开后会持续重连，不再只试一次；
  - 下一次同步开始时，会清除那次未完成同步的记录；
  - AUV 不再等待已经放弃的同步。
- **更新 Safari 伴侣后不再留下旧记录。** 此前，旧版伴侣留下的未完成记录会让更新后的每次同步都被拒绝。现在这类记录过期后会被丢弃。

Safari 一侧的修复位于 **UMA Safari Bridge 0.14.2** 中。AUV 0.18.3 的 Claude 精确同步需要该版本的 Bridge；使用更早版本时会提示版本不匹配，且读不到数据。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 与 Safari Bridge 均已完成 Developer ID 签名、Apple 公证与票据装订，并通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

在安装后的应用中，Safari 唯一的窗口在另一个桌面时，以及 Safari 最小化时，都成功读到了 Claude 的精确数值。新增测试在模拟的 Safari 环境中运行伴侣的后台页面，覆盖临时窗口、持续重连和清除旧记录。

本版未改动分区工，也未重新测试。[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)。

### 下载文件

- 文件：`AUV_Mac_0.18.3_Universal.zip`
- 大小：**14,926,083 字节**
- SHA-256：

```text
eb5ff0036123c530e9e8bd6a03674f03411743cc0e3324dbc5009dabc1bbe4e4
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
