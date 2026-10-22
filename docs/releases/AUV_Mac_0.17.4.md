# AUV Mac 0.17.4

**Build 2026102102 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.4/AUV_Mac_0.17.4_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

A single fix to the cost panel that 0.17.3 introduced.

- **The Claude cost panel now honours its own setting.** Each agent's settings include a **Token Cost Estimate** switch. In 0.17.3 the new Claude panel checked only whether a figure was available, so it could appear while that switch was off. It now reads the switch and stays hidden when you turn it off. The switch is off by default, so the panel is hidden unless you ask for it.

Nothing else changed. Everything 0.17.3 added behaves as before: low-remaining colour for Claude once you state your plan, the menu bar falling back to Claude when Codex reports no usable quota, reset times in the menu bar panel, and the cost estimate itself.

If you are upgrading from 0.17.2 or earlier, the [0.17.3 release note](AUV_Mac_0.17.3.md) describes what those additions are and what the cost estimate does and does not read.

The app is named **AUV** when opened; the extracted bundle remains **`UMA.app`** for compatible upgrades. Quit the previous copy before replacing it in Applications.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon, including the Intel executable through Rosetta 2. The package is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment after a clean re-extraction, including with a download quarantine flag applied. Physical Intel Macs and macOS 14/15 were not tested.

The fix is covered by a test that asserts the panel reads the same preference its switch writes; the test was confirmed to fail when the check is removed. As in 0.17.3, the cost panel's data path is covered by automated tests but was not exercised against a live Claude account. Sectorium is unchanged and was not retested.

[Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip), with its existing support limits. Windows Sectorium is UI only; storage actions are disabled.

## Download identity

- File: `AUV_Mac_0.17.4_Universal.zip`
- Size: **14,592,367 bytes**
- SHA-256:

```text
595be654c07527e16980ce28a20e33a9b49c6684655ed99017079720c95e04a7
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102102 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.4/AUV_Mac_0.17.4_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

本版只修复 0.17.3 新增费用面板的一个问题。

- **Claude 费用面板现在遵循自己的开关。** 每个智能体的设置中都有 **Token 费用估算**开关。0.17.3 的费用面板只判断是否取得数值，因此开关关闭时仍可能显示。现在面板会读取该开关，关闭时不再显示。该开关默认关闭，因此除非你主动打开，面板不会出现。

其余没有变化。0.17.3 新增的功能行为不变：说明 Claude 方案后额度不足显示颜色；Codex 没有可用额度时菜单栏改用 Claude 的数字；菜单栏面板显示重置时间；以及费用估算本身。

如果你从 0.17.2 或更早版本升级，[0.17.3 更新说明](AUV_Mac_0.17.3.md#中文)介绍了这些新增内容，以及费用估算读取与不读取的范围。

打开后产品名为 **AUV**，解压所得文件仍为 **`UMA.app`**，以兼容既有安装。替换“应用程序”中的旧版前，请先正常退出旧应用。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成，并通过 Rosetta 2 运行 Intel 程序。安装包已完成 Developer ID 签名、Apple 公证与票据装订；重新解压后（含加上下载隔离标记的情况）仍通过 Gatekeeper 检查。尚未测试 Intel 实机或 macOS 14/15。

本次修复有对应测试，核验面板读取的正是其开关所写入的设置；移除该判断后测试确实失败。与 0.17.3 相同，费用面板的数据链路由自动化测试覆盖，但未在真实 Claude 账户下实测。分区工未改动，也未重新测试。

[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)及原有支持范围；Windows 分区工仅有界面，磁盘操作禁用。

### 下载文件

- 文件：`AUV_Mac_0.17.4_Universal.zip`
- 大小：**14,592,367 字节**
- SHA-256：

```text
595be654c07527e16980ce28a20e33a9b49c6684655ed99017079720c95e04a7
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
