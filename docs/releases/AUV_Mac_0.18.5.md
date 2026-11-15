# AUV Mac 0.18.5

**Build 2026111401 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.5/AUV_Mac_0.18.5_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

AUV opens on every Mac again.

- **"Cannot be opened" is fixed.** AUV 0.17.8 through 0.18.4 were signed with permissions that macOS only allows when the app carries its provisioning profile, and the package did not include it. On a Mac that had not run an older AUV, macOS refused to start the app and said it "cannot be opened". The profile is now part of the app.
- **Nothing else changed.** The app is the same as 0.18.4: Claude's automatic refresh recovers by itself when Safari's companion goes quiet, a read that gets no answer is retried within seconds, and Claude no longer turns Unavailable between syncs. See the [0.18.4 release note](AUV_Mac_0.18.4.md) for details.

If 0.18.4 already opens on your Mac, upgrading changes nothing you will notice. If it would not open, install 0.18.5 in its place.

Claude's Accuracy Sync still needs **UMA Safari Bridge 0.14.3**.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon. AUV is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment. Opening it on a Mac that has never run AUV is being checked after release, through the website download. Physical Intel Macs and macOS 14/15 were not tested.

Sectorium is unchanged and was not retested. [Windows is at 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win) and is released separately.

## Download identity

- File: `AUV_Mac_0.18.5_Universal.zip`
- Size: **14,997,204 bytes**
- SHA-256:

```text
7d9cd0791569316dc09247b218e76f104084d5b95e9c7e2f4a2f6cdc5596dcc3
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026111401 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.18.5/AUV_Mac_0.18.5_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

AUV 在所有 Mac 上都能正常打开了。

- **修复“无法打开”。** AUV 0.17.8 到 0.18.4 签名时带有一些权限，macOS 只在应用附带描述文件时才允许使用，但安装包里漏掉了这个文件。在没有运行过旧版 AUV 的 Mac 上，macOS 会拒绝启动，并提示应用“无法打开”。现在描述文件已包含在应用中。
- **其他没有变化。** 应用本身与 0.18.4 相同：Safari 伴侣失去响应时，Claude 的自动刷新能自行恢复；没有回应的读取几秒内就会重试；两次同步之间，Claude 也不再显示 Unavailable。详见 [0.18.4 更新说明](AUV_Mac_0.18.4.md#中文)。

如果 0.18.4 在你的 Mac 上已经能打开，升级后不会有可见的变化；如果打不开，请安装 0.18.5 替换它。

Claude 精确同步仍需要 **UMA Safari Bridge 0.14.3**。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成。AUV 已完成 Developer ID 签名、Apple 公证与票据装订，并通过 Gatekeeper 检查。在从未运行过 AUV 的 Mac 上通过网站下载并打开，会在发布后检查。尚未测试 Intel 实机或 macOS 14/15。

本版未改动分区工，也未重新测试。[Windows 版为 0.18.6](https://github.com/ShaoJHe-SilkRoad/UMA/releases/tag/v0.18.6-win)，单独发布。

### 下载文件

- 文件：`AUV_Mac_0.18.5_Universal.zip`
- 大小：**14,997,204 字节**
- SHA-256：

```text
7d9cd0791569316dc09247b218e76f104084d5b95e9c7e2f4a2f6cdc5596dcc3
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
