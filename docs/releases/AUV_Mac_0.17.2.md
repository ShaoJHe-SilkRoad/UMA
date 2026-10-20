# AUV Mac 0.17.2

**Build 2026102001 · macOS 14+ · Universal for Apple silicon and Intel.**

[Download the Mac app](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.2/AUV_Mac_0.17.2_Universal.zip) · [Install or upgrade](../INSTALLATION.md#mac-installation-guide) · [Compatibility](../MAC_COMPATIBILITY.md)

## What's new

- **One Mac download for both processors.** AUV and its bundled helpers include arm64 and x86_64 executables. The package is Developer ID signed, Apple notarized and stapled, and passed Gatekeeper assessment.
- **More compatible Codex connections.** AUV uses the default local connection mode and accepts responses that omit optional platform details. Required fields are still validated. Optional token-statistics errors do not hide a valid account allowance.
- **Clearer development-volume controls.** Load mounts a development volume; Unload closes it while leaving its parent drive connected; Disconnect safely ejects the entire external drive. Registered volumes persist across page changes. macOS disk notifications and a five-minute consistency check keep state current.

The app is named **AUV** when opened; the extracted bundle remains **`UMA.app`** for compatible upgrades. Quit the previous copy before replacing it in Applications.

## Verification and limits

Package checks ran on macOS 27.2 on Apple silicon, including the Intel executable through Rosetta 2. Physical Intel Macs and macOS 14/15 were not tested. Provider availability still depends on the installed provider app and account; live-account compatibility was not tested across different Macs.

The user confirmed the basic Sectorium Load, Unload and Disconnect cycle on the tested external-drive setup. This is not a claim that every device or filesystem has been tested. Keep important data backed up and wait for successful disconnection before unplugging.

[Windows remains at 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip), with its existing support limits. Windows Sectorium is UI only; storage actions are disabled.

## Download identity

- File: `AUV_Mac_0.17.2_Universal.zip`
- Size: **14,559,662 bytes**
- SHA-256:

```text
99f435b8d4b35a51863e4b1242054bb0c1cd7f9e95912505e687c8170b281bc4
```

[Connection troubleshooting](../FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

---

## 中文

**构建号 2026102001 · macOS 14 及以上 · Apple silicon / Intel 通用包。**

[下载 Mac 应用](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.17.2/AUV_Mac_0.17.2_Universal.zip) · [安装与升级](../INSTALLATION.md#mac-中文安装指南) · [兼容性说明](../MAC_COMPATIBILITY.md#中文)

### 本版更新

- **一个包覆盖两种 Mac 处理器。** 主程序与辅助程序均包含 arm64 和 x86_64 版本。已完成 Developer ID 签名、Apple 公证及票据装订，并通过 Gatekeeper 检查。
- **改善 Codex 连接兼容性。** 使用默认本地连接方式，兼容缺少可选平台信息的响应，同时保留必需字段核验。可选 token 统计失败时，已取得的账户额度仍可显示。
- **明确开发卷操作。** Load 装载开发卷；Unload 卸载开发卷，母盘保持连接；Disconnect 安全弹出整个外接硬盘。切换页面保留已登记卷，使用 macOS 磁盘通知和每五分钟一致性检查更新状态。

打开后产品名为 **AUV**，解压所得文件仍为 **`UMA.app`**，以兼容既有安装。替换“应用程序”中的旧版前，请先正常退出旧应用。

### 验证范围与限制

包验证在 macOS 27.2 的 Apple silicon Mac 上完成，并通过 Rosetta 2 运行 Intel 程序。尚未测试 Intel 实机或 macOS 14/15。智能体数据仍依赖其客户端与账户；本次未覆盖不同 Mac 上的真实账户兼容性。

用户已在本次外接硬盘环境中确认分区工基本装载、卸载和断开流程可用。这不代表所有设备和文件系统都通过测试。请备份重要数据，断开成功后再拔线。

[Windows 保持 0.16.3](https://github.com/ShaoJHe-SilkRoad/UMA/releases/download/v0.16.3/AUV_Win_0.16.3.zip)及原有支持范围；Windows 分区工仅有界面，磁盘操作禁用。

### 下载文件

- 文件：`AUV_Mac_0.17.2_Universal.zip`
- 大小：**14,559,662 字节**
- SHA-256：

```text
99f435b8d4b35a51863e4b1242054bb0c1cd7f9e95912505e687c8170b281bc4
```

[连接排错](../FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
