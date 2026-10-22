# Mac compatibility / Mac 兼容性

## English

**AUV 0.17.3 · build 2026102101 · macOS 14 or later.**

The Universal download contains both **Apple silicon (arm64)** and **Intel (x86_64)** versions of AUV and its bundled helpers. It is Developer ID signed, Apple notarized, and includes the notarization ticket. The final package passed Gatekeeper assessment.

### What has been tested

| Configuration or check | Result |
| --- | --- |
| Apple silicon on macOS 27.2 | Package and isolated connection checks passed. |
| Intel executable through Rosetta 2 on that Mac | Package checks passed; this is not an Intel hardware test. |
| Physical Intel Mac | Not yet tested. |
| macOS 14 and macOS 15 | Build deployment target supports macOS 14+; these OS versions have not been tested on hardware. |
| Live Codex accounts across different Macs | Not tested in this compatibility run. |

A successful install does not guarantee every provider can return data. The provider must support your Mac, account and region. This package does not run on iPhone, iPad or macOS 13 and earlier. [Windows uses a separate package](INSTALLATION.md#windows-installation-guide).

### Connecting accounts

For Codex allowance, install the official Codex app and sign in with your ChatGPT account. Open AUV, allow its local Codex connection, then choose **Scan for Agents → Refresh**. AUV checks the app identity and developer signature before using its local interface; it does not start an AI task to read allowance.

Version 0.17.2 uses Codex's default local connection mode and accepts initialization responses without optional platform details. Required response fields are still checked. Optional token statistics are separate from account allowance, so an unavailable token-statistics endpoint does not hide a valid allowance.

AUV does not include Codex or transfer credentials. An API-key-only login may not provide a ChatGPT plan allowance. AUV displays the allowance supplied by Codex, not a count of messages on the ChatGPT website.

Claude requires a supported status-line or browser-companion connection. The optional Antigravity CLI remains limited to its separately verified Apple silicon version. Universal AUV does not broaden that provider's support.

### Permissions

Routine account setup does not require Full Disk Access or disabling macOS security. When you choose to manage a development volume in Sectorium, macOS may ask for removable-drive access. Grant access for the operation you selected.

[Install or upgrade](INSTALLATION.md#mac-installation-guide) · [Connection troubleshooting](FIRST_INSTALL_TROUBLESHOOTING.md) · [Report a problem](https://github.com/ShaoJHe-SilkRoad/UMA/issues)

## 中文

**AUV 0.17.3 · 构建号 2026102101 · macOS 14 及以上。**

通用包同时包含 **Apple silicon（arm64）**与 **Intel（x86_64）**版本的主程序及辅助程序。已完成 Developer ID 签名、Apple 公证，并附有公证票据；最终包已通过 Gatekeeper 检查。

### 实际测试范围

| 环境或检查 | 结果 |
| --- | --- |
| macOS 27.2 的 Apple silicon Mac | 包验证和隔离连接检查通过。 |
| 同一台 Mac 通过 Rosetta 2 运行 Intel 程序 | 包验证通过；不等于 Intel 实机测试。 |
| Intel 实机 | 尚未测试。 |
| macOS 14、macOS 15 | 构建目标为 macOS 14 及以上；尚未在这些系统上实机测试。 |
| 不同 Mac 上的真实 Codex 账户 | 本次兼容性检查未覆盖。 |

应用能够安装，不代表所有智能体都能返回数据。连接的服务也必须支持你的电脑、账户和地区。此包不适用于 iPhone、iPad、macOS 13 及更早版本。[Windows 使用独立安装包](INSTALLATION.md#windows-中文安装指南)。

### 连接账户

查看 Codex 额度时，先安装官方 Codex 并用 ChatGPT 账户登录。打开 AUV，允许本机 Codex 连接，再点击**“扫描智能体”→“刷新”**。AUV 核验应用身份和开发者签名后使用本地接口，读取额度不会启动 AI 任务。

0.17.2 使用 Codex 默认本地连接方式，并兼容缺少可选平台信息的初始化响应；必需字段仍会核验。可选 token 统计与账户额度分开处理，缺少统计接口不会隐藏已经取得的额度。

AUV 不附带 Codex，也不转移账户凭据。仅用 API Key 登录时可能没有 ChatGPT 套餐额度。AUV 显示 Codex 返回的额度，不统计 ChatGPT 网页消息数。

Claude 需要支持的状态行或浏览器伴侣连接。可选 Antigravity CLI 仍只适用于单独验证过的 Apple silicon 版本；AUV 通用包不会扩大该服务的支持范围。

### 权限

正常账户设置不需要“完全磁盘访问权限”，也不需要关闭 macOS 安全保护。在分区工中管理开发卷时，macOS 可能请求访问移动硬盘；按自己选择的操作授权即可。

[安装与升级](INSTALLATION.md#mac-中文安装指南) · [连接排错](FIRST_INSTALL_TROUBLESHOOTING.md#中文) · [反馈问题](https://github.com/ShaoJHe-SilkRoad/UMA/issues)
