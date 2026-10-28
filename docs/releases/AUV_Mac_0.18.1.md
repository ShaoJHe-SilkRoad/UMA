# AUV Mac 0.18.1

**Build 2026102802 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.1/AUV_Mac_0.18.1_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

Claude's bar on the Desktop Assistant now shows how current its reading is, and automatic refresh can run every 10 minutes.

- **Claude's Desktop Assistant bar is green while its exact reading is current, and grey once it is outdated.** Before, the bar stayed grey even right after an Accuracy Sync. The plan chosen in Claude's settings never reached the Desktop Assistant, so the bar was drawn as for an unknown plan. Now a current reading shows green like Codex, or red when it is low. An outdated, retained or estimated reading turns the bar grey.
- **The percentage is in the normal text colour again.** Synced Claude readings were shown in green text. The bar now says whether the reading is current, so the number stays white in dark mode and black in light mode.
- **Automatic refresh can run every 10 minutes.** The Refresh pane now offers 5, 10, 15, 30 and 60 minutes. Claude's Accuracy Sync follows the same interval, and it still runs only while Safari is already open.

Which agents are found and how usage figures are calculated are unchanged.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. The package is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment. Physical Intel Macs and macOS 14/15 were not tested.

A new test confirms the Desktop Assistant receives the plan chosen in Claude's settings. That test fails when the fix is removed.

Sectorium is unchanged in this release and was not retested. [Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip).

## Download identity

- File: `AUV_Mac_0.18.1_Universal.zip`
- Size: **14,910,427 bytes**
- SHA-256:

```text
a2cba26152fe20afd2943aac5816f4cce47d474b70074040127dd2a132f3abbe
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102802 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.1/AUV_Mac_0.18.1_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

桌面助手上 Claude 的进度条现在能看出读数是否仍然最新；自动刷新新增每 10 分钟一档。

- **读数最新时，桌面助手上 Claude 的进度条为绿色；读数过时后变为灰色。** 此前即使刚完成精确同步，进度条仍是灰色。原因是在 Claude 设置里选的套餐没有传到桌面助手，进度条一直按“套餐未知”绘制。现在读数最新时显示绿色，与 Codex 一致，额度偏低时为红色。读数过时、为保留的旧值或仅为估算时，进度条为灰色。
- **百分比恢复为正常文字颜色。** 此前同步后的 Claude 读数以绿色文字显示。现在由进度条表明读数是否最新，数字保持深色模式下白色、浅色模式下黑色。
- **自动刷新可设为每 10 分钟。** “刷新”面板现提供 5、10、15、30、60 分钟。Claude 精确同步按相同频率运行，仍然只在 Safari 已打开时进行。

能找到哪些智能体、用量数值的计算方式不变。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。安装包已完成 Developer ID 签名、Apple 公证与票据装订，并通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

新增一条测试，确认桌面助手能拿到 Claude 设置中选择的套餐；移除修复后，这条测试会失败。

本版未改动分区工，也未重新测试。[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)。

### 下载文件

- 文件：`AUV_Mac_0.18.1_Universal.zip`
- 大小：**14,910,427 字节**
- SHA-256：

```text
a2cba26152fe20afd2943aac5816f4cce47d474b70074040127dd2a132f3abbe
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
